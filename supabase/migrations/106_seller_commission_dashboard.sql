-- 106 — Dashboard commissions vendeurs indépendants / master + demande de paiement

CREATE TABLE IF NOT EXISTS "SellerCommissionPaymentRequests" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "sellerUserId" uuid NOT NULL,
  "amount" double precision NOT NULL,
  "currency" text NOT NULL DEFAULT 'XOF',
  "status" text NOT NULL DEFAULT 'pending_confirmation',
  "bookingCount" integer NOT NULL DEFAULT 0,
  "periodFrom" timestamptz,
  "periodTo" timestamptz,
  "note" text,
  "requestedAt" timestamptz NOT NULL DEFAULT now(),
  "processedBy" uuid,
  "processedAt" timestamptz,
  CONSTRAINT "SellerCommissionPaymentRequests_status_check"
    CHECK ("status" IN ('pending_confirmation', 'confirmed', 'rejected', 'cancelled'))
);

ALTER TABLE "SellerCommissionPaymentRequests"
  DROP CONSTRAINT IF EXISTS "SellerCommissionPaymentRequests_sellerUserId_fkey";
ALTER TABLE "SellerCommissionPaymentRequests"
  ADD CONSTRAINT "SellerCommissionPaymentRequests_sellerUserId_fkey"
  FOREIGN KEY ("sellerUserId") REFERENCES "Users" ("id") ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS "SellerCommissionPaymentRequests_seller_idx"
  ON "SellerCommissionPaymentRequests" ("sellerUserId", "status", "requestedAt" DESC);

ALTER TABLE "SellerCommissionPaymentRequests" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "seller_commission_payment_requests_select" ON "SellerCommissionPaymentRequests";
CREATE POLICY "seller_commission_payment_requests_select" ON "SellerCommissionPaymentRequests"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR "sellerUserId" = public.current_app_user_id()
  );

DROP POLICY IF EXISTS "seller_commission_payment_requests_write" ON "SellerCommissionPaymentRequests";
CREATE POLICY "seller_commission_payment_requests_write" ON "SellerCommissionPaymentRequests"
  FOR ALL TO authenticated
  USING (public.is_super_admin() OR "sellerUserId" = public.current_app_user_id())
  WITH CHECK (public.is_super_admin() OR "sellerUserId" = public.current_app_user_id());

CREATE OR REPLACE FUNCTION public._is_platform_seller_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = p_user_id
      AND r.name IN ('vendeur_independant', 'vendeur_master', 'vendeur_reseau')
  );
$$;

CREATE OR REPLACE FUNCTION public.update_company_recruited_by(
  p_company_id uuid,
  p_recruited_by_user_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_company_id IS NULL THEN RAISE EXCEPTION 'company_id requis'; END IF;
  UPDATE "Companies"
  SET "recruitedByUserId" = p_recruited_by_user_id
  WHERE id = p_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_seller_commission_dashboard(
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL,
  p_seller_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid;
  v_seller_id uuid;
  v_from timestamptz;
  v_to timestamptz;
BEGIN
  v_user_id := public.current_app_user_id();
  v_seller_id := COALESCE(p_seller_user_id, v_user_id);

  IF v_seller_id IS NULL THEN RAISE EXCEPTION 'Utilisateur requis'; END IF;

  IF NOT (
    public.is_super_admin()
    OR v_seller_id = v_user_id
    OR public._is_platform_seller_user(v_user_id)
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF NOT public.is_super_admin() AND v_seller_id <> v_user_id THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_from := COALESCE(p_date_from, date_trunc('month', now()));
  v_to := COALESCE(p_date_to, now());

  RETURN (
    WITH base AS (
      SELECT
        rb.id AS booking_id,
        rb."createdAt" AS created_at,
        rb."sellerCommissionAmount" AS commission_amount,
        COALESCE(rb."sellerCommissionStatus", 'pending') AS commission_status,
        c.name AS company_name,
        p.reference,
        COALESCE(country.currency, 'XOF') AS currency
      FROM "ReservationBus" rb
      JOIN "Payment" p ON p.id = rb."paymentId"
      JOIN "Reservations" r ON r.id = rb."reservationId"
      JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
      JOIN "Gares" g ON g.id = pt.depart
      JOIN "Companies" c ON c.id = g."companyId"
      LEFT JOIN "Countries" country ON country.id = c."countryId"
      WHERE rb."type" = 'voyage'
        AND rb."createdBy" = v_seller_id
        AND COALESCE(rb."saleChannel", 'traveler') = 'seller_reservation'
        AND COALESCE(rb."sellerCommissionAmount", 0) > 0
        AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
        AND rb."createdAt" >= v_from
        AND rb."createdAt" <= v_to
    )
    SELECT jsonb_build_object(
      'sellerUserId', v_seller_id,
      'dateFrom', v_from,
      'dateTo', v_to,
      'currency', COALESCE((SELECT MAX(currency) FROM base), 'XOF'),
      'totalAmount', COALESCE((SELECT SUM(commission_amount) FROM base), 0),
      'pendingAmount', COALESCE((SELECT SUM(commission_amount) FROM base WHERE commission_status = 'pending'), 0),
      'paymentRequestedAmount', COALESCE((SELECT SUM(commission_amount) FROM base WHERE commission_status = 'payment_requested'), 0),
      'paidAmount', COALESCE((SELECT SUM(commission_amount) FROM base WHERE commission_status = 'paid'), 0),
      'ticketCount', COALESCE((SELECT COUNT(*) FROM base), 0),
      'entries', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'bookingId', booking_id,
          'createdAt', created_at,
          'commissionAmount', commission_amount,
          'commissionStatus', commission_status,
          'companyName', company_name,
          'reference', reference,
          'currency', currency
        ) ORDER BY created_at DESC)
        FROM (SELECT * FROM base LIMIT 100) recent
      ), '[]'::jsonb)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.request_seller_commission_payment(
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid;
  v_from timestamptz;
  v_to timestamptz;
  v_amount double precision;
  v_count integer;
  v_currency text;
  v_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF NOT public._is_platform_seller_user(v_user_id) THEN
    RAISE EXCEPTION 'Réservé aux vendeurs indépendants et master';
  END IF;

  v_from := COALESCE(p_date_from, date_trunc('month', now()));
  v_to := COALESCE(p_date_to, now());

  SELECT COALESCE(SUM(rb."sellerCommissionAmount"), 0), COUNT(*)::integer, MAX(COALESCE(country.currency, 'XOF'))
  INTO v_amount, v_count, v_currency
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  LEFT JOIN "Countries" country ON country.id = c."countryId"
  WHERE rb."type" = 'voyage'
    AND rb."createdBy" = v_user_id
    AND COALESCE(rb."saleChannel", 'traveler') = 'seller_reservation'
    AND COALESCE(rb."sellerCommissionStatus", 'pending') = 'pending'
    AND COALESCE(rb."sellerCommissionAmount", 0) > 0
    AND rb."createdAt" >= v_from
    AND rb."createdAt" <= v_to;

  IF v_amount <= 0 THEN RAISE EXCEPTION 'Aucune commission en attente sur cette période'; END IF;

  IF EXISTS (
    SELECT 1 FROM "SellerCommissionPaymentRequests"
    WHERE "sellerUserId" = v_user_id AND status = 'pending_confirmation'
  ) THEN
    RAISE EXCEPTION 'Une demande de paiement est déjà en cours';
  END IF;

  INSERT INTO "SellerCommissionPaymentRequests" (
    "sellerUserId", amount, currency, status, "bookingCount", "periodFrom", "periodTo", note
  ) VALUES (
    v_user_id, v_amount, v_currency, 'pending_confirmation', v_count, v_from, v_to, NULLIF(trim(p_note), '')
  ) RETURNING id INTO v_id;

  UPDATE "ReservationBus" rb
  SET "sellerCommissionStatus" = 'payment_requested'
  FROM "Payment" p
  WHERE p.id = rb."paymentId"
    AND rb."createdBy" = v_user_id
    AND COALESCE(rb."saleChannel", 'traveler') = 'seller_reservation'
    AND COALESCE(rb."sellerCommissionStatus", 'pending') = 'pending'
    AND COALESCE(rb."sellerCommissionAmount", 0) > 0
    AND rb."createdAt" >= v_from
    AND rb."createdAt" <= v_to;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_seller_commission_payment(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_req record;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;

  SELECT * INTO v_req FROM "SellerCommissionPaymentRequests" WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Demande introuvable'; END IF;
  IF v_req.status <> 'pending_confirmation' THEN RAISE EXCEPTION 'Demande déjà traitée'; END IF;

  UPDATE "SellerCommissionPaymentRequests"
  SET status = 'confirmed', "processedBy" = public.current_app_user_id(), "processedAt" = now()
  WHERE id = p_request_id;

  UPDATE "ReservationBus" rb
  SET "sellerCommissionStatus" = 'paid', "sellerCommissionPaidAt" = now()
  WHERE rb."createdBy" = v_req."sellerUserId"
    AND COALESCE(rb."sellerCommissionStatus", 'pending') = 'payment_requested'
    AND rb."createdAt" >= COALESCE(v_req."periodFrom", rb."createdAt")
    AND rb."createdAt" <= COALESCE(v_req."periodTo", rb."createdAt");
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_company_recruited_by(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_seller_commission_dashboard(timestamptz, timestamptz, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_seller_commission_payment(timestamptz, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_seller_commission_payment(uuid) TO authenticated;
