-- 123 — Commission compagnie prioritaire + ventes guichet offline (idempotence)

CREATE TABLE IF NOT EXISTS public."CounterSaleIdempotency" (
  id uuid PRIMARY KEY,
  seller_user_id uuid NOT NULL REFERENCES public."Users"(id) ON DELETE CASCADE,
  reservation_id uuid NOT NULL,
  passenger_name text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_counter_sale_idempotency_seller
  ON public."CounterSaleIdempotency"(seller_user_id, created_at DESC);

ALTER TABLE public."CounterSaleIdempotency" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS counter_sale_idempotency_service ON public."CounterSaleIdempotency";
CREATE POLICY counter_sale_idempotency_service ON public."CounterSaleIdempotency"
  FOR ALL USING (auth.role() = 'service_role');

-- Taux commission : compagnie (setting ou fiche) prime sur le taux pays.
CREATE OR REPLACE FUNCTION public.resolve_seller_commission_setting(p_company_id uuid)
RETURNS TABLE(
  setting_id uuid,
  setting_scope text,
  country_id uuid,
  company_id uuid,
  rate double precision,
  paid_by text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH company_row AS (
    SELECT c.id, c."countryId", COALESCE(c."commissionRate", 0) AS legacy_rate
    FROM public."Companies" c
    WHERE c.id = p_company_id
  ),
  resolved AS (
    SELECT
      s.id AS setting_id,
      s.scope AS setting_scope,
      COALESCE(s."countryId", cr."countryId") AS country_id,
      s."companyId" AS company_id,
      s.rate,
      s."paidBy" AS paid_by,
      1 AS priority
    FROM company_row cr
    JOIN public."CommissionSettings" s
      ON s."scope" = 'company'
     AND s."companyId" = cr.id
     AND s."isActive" = true
    UNION ALL
    SELECT
      NULL::uuid AS setting_id,
      'legacy_company'::text AS setting_scope,
      cr."countryId" AS country_id,
      cr.id AS company_id,
      cr.legacy_rate AS rate,
      'traveler'::text AS paid_by,
      2 AS priority
    FROM company_row cr
    UNION ALL
    SELECT
      NULL::uuid AS setting_id,
      'default'::text AS setting_scope,
      cr."countryId" AS country_id,
      NULL::uuid AS company_id,
      5::double precision AS rate,
      'traveler'::text AS paid_by,
      3 AS priority
    FROM company_row cr
    WHERE cr."countryId" IS NOT NULL
  )
  SELECT
    resolved.setting_id,
    resolved.setting_scope,
    resolved.country_id,
    resolved.company_id,
    COALESCE(resolved.rate, 0),
    COALESCE(resolved.paid_by, 'traveler')
  FROM resolved
  ORDER BY priority
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.seller_counter_sale_idempotent(
  p_client_mutation_id uuid,
  p_reservation_id uuid,
  p_passenger_name text,
  p_passenger_phone text DEFAULT NULL,
  p_seat_number text DEFAULT NULL,
  p_parcel_count integer DEFAULT 0,
  p_parcel_weight double precision DEFAULT 0,
  p_parcel_amount double precision DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cached jsonb;
  v_row record;
  v_user_id uuid;
BEGIN
  IF p_client_mutation_id IS NULL THEN
    RAISE EXCEPTION 'client_mutation_id requis';
  END IF;

  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur non authentifie';
  END IF;

  SELECT result INTO v_cached
  FROM public."CounterSaleIdempotency"
  WHERE id = p_client_mutation_id;

  IF v_cached IS NOT NULL THEN
    RETURN v_cached;
  END IF;

  SELECT * INTO v_row
  FROM public.seller_counter_sale(
    p_reservation_id,
    p_passenger_name,
    p_passenger_phone,
    p_seat_number,
    p_parcel_count,
    p_parcel_weight,
    p_parcel_amount
  )
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vente guichet impossible';
  END IF;

  v_cached := jsonb_build_object(
    'booking_id', v_row.booking_id,
    'reference', v_row.reference,
    'verify_token', v_row.verify_token,
    'total_price', v_row.total_price,
    'currency', v_row.currency
  );

  INSERT INTO public."CounterSaleIdempotency" (
    id, seller_user_id, reservation_id, passenger_name, result
  ) VALUES (
    p_client_mutation_id,
    v_user_id,
    p_reservation_id,
    trim(p_passenger_name),
    v_cached
  );

  RETURN v_cached;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seller_counter_sale_idempotent(
  uuid, uuid, text, text, text, integer, double precision, double precision
) TO authenticated;

NOTIFY pgrst, 'reload schema';
