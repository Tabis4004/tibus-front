-- Lot 26: annulation billets + pénalités par compagnie + journal des ventes.
-- Remboursement = M - P (M = prix billet encaissé, P = pénalité).

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "ticketStatus" text NOT NULL DEFAULT 'issued',
  ADD COLUMN IF NOT EXISTS "cancelledAt" timestamptz,
  ADD COLUMN IF NOT EXISTS "cancelledBy" uuid,
  ADD COLUMN IF NOT EXISTS "penaltyAmount" double precision,
  ADD COLUMN IF NOT EXISTS "refundAmount" double precision,
  ADD COLUMN IF NOT EXISTS "cancellationReason" text;

ALTER TABLE "ReservationBus"
  DROP CONSTRAINT IF EXISTS "ReservationBus_ticketStatus_check";
ALTER TABLE "ReservationBus"
  ADD CONSTRAINT "ReservationBus_ticketStatus_check"
  CHECK ("ticketStatus" IN ('issued', 'cancelled'));

CREATE INDEX IF NOT EXISTS "reservationbus_ticket_status_idx"
  ON "ReservationBus" ("ticketStatus", "reservationId");

CREATE TABLE IF NOT EXISTS "CompanyCancellationPolicy" (
  "companyId" uuid PRIMARY KEY REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "criticalHoursBeforeDeparture" double precision NOT NULL DEFAULT 24,
  "criticalPenaltyType" text NOT NULL DEFAULT 'percent',
  "criticalPenaltyValue" double precision NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users" ("id") DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT "CompanyCancellationPolicy_criticalPenaltyType_check"
    CHECK ("criticalPenaltyType" IN ('percent', 'fixed')),
  CONSTRAINT "CompanyCancellationPolicy_criticalPenaltyValue_check"
    CHECK ("criticalPenaltyValue" >= 0)
);

CREATE TABLE IF NOT EXISTS "CompanyCancellationPenaltyTier" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "label" text,
  "minHoursBeforeDeparture" double precision NOT NULL,
  "penaltyType" text NOT NULL DEFAULT 'percent',
  "penaltyValue" double precision NOT NULL DEFAULT 0,
  "sortOrder" integer NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "CompanyCancellationPenaltyTier_penaltyType_check"
    CHECK ("penaltyType" IN ('percent', 'fixed')),
  CONSTRAINT "CompanyCancellationPenaltyTier_penaltyValue_check"
    CHECK ("penaltyValue" >= 0),
  CONSTRAINT "CompanyCancellationPenaltyTier_hours_check"
    CHECK ("minHoursBeforeDeparture" >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompanyCancellationPenaltyTier_company_hours_key"
  ON "CompanyCancellationPenaltyTier" ("companyId", "minHoursBeforeDeparture");

ALTER TABLE "CompanyCancellationPolicy" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "CompanyCancellationPenaltyTier" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_cancellation_policy_select" ON "CompanyCancellationPolicy";
CREATE POLICY "company_cancellation_policy_select" ON "CompanyCancellationPolicy"
  FOR SELECT TO authenticated
  USING (public.is_company_role_user(public.current_app_user_id(), "companyId") OR public.is_super_admin());

DROP POLICY IF EXISTS "company_cancellation_policy_write" ON "CompanyCancellationPolicy";
CREATE POLICY "company_cancellation_policy_write" ON "CompanyCancellationPolicy"
  FOR ALL TO authenticated
  USING (public.has_company_role("companyId", ARRAY['owner']) OR public.is_super_admin())
  WITH CHECK (public.has_company_role("companyId", ARRAY['owner']) OR public.is_super_admin());

DROP POLICY IF EXISTS "company_cancellation_tier_select" ON "CompanyCancellationPenaltyTier";
CREATE POLICY "company_cancellation_tier_select" ON "CompanyCancellationPenaltyTier"
  FOR SELECT TO authenticated
  USING (public.is_company_role_user(public.current_app_user_id(), "companyId") OR public.is_super_admin());

DROP POLICY IF EXISTS "company_cancellation_tier_write" ON "CompanyCancellationPenaltyTier";
CREATE POLICY "company_cancellation_tier_write" ON "CompanyCancellationPenaltyTier"
  FOR ALL TO authenticated
  USING (public.has_company_role("companyId", ARRAY['owner']) OR public.is_super_admin())
  WITH CHECK (public.has_company_role("companyId", ARRAY['owner']) OR public.is_super_admin());

CREATE OR REPLACE FUNCTION public.can_view_company_sales(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), p_company_id);
$$;

CREATE OR REPLACE FUNCTION public.can_cancel_company_ticket(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'vendeur']);
$$;

CREATE OR REPLACE FUNCTION public.compute_cancellation_penalty(
  p_nominal_amount double precision,
  p_penalty_type text,
  p_penalty_value double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_nominal_amount, 0) <= 0 THEN 0
    WHEN p_penalty_type = 'fixed' THEN LEAST(GREATEST(COALESCE(p_penalty_value, 0), 0), p_nominal_amount)
    ELSE LEAST(GREATEST(p_nominal_amount * COALESCE(p_penalty_value, 0) / 100.0, 0), p_nominal_amount)
  END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_cancellation_penalty(
  p_company_id uuid,
  p_hours_before_departure double precision
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_policy record;
  v_tier record;
  v_staff_only boolean := false;
  v_penalty_type text;
  v_penalty_value double precision;
  v_label text;
BEGIN
  SELECT * INTO v_policy
  FROM "CompanyCancellationPolicy" cp
  WHERE cp."companyId" = p_company_id;

  IF v_policy IS NULL OR v_policy."isActive" = false THEN
    RETURN jsonb_build_object(
      'staffOnly', false,
      'penaltyType', 'percent',
      'penaltyValue', 0,
      'tierLabel', 'default',
      'hoursBeforeDeparture', p_hours_before_departure
    );
  END IF;

  IF p_hours_before_departure < v_policy."criticalHoursBeforeDeparture" THEN
    RETURN jsonb_build_object(
      'staffOnly', true,
      'penaltyType', v_policy."criticalPenaltyType",
      'penaltyValue', v_policy."criticalPenaltyValue",
      'tierLabel', 'critical',
      'hoursBeforeDeparture', p_hours_before_departure,
      'criticalHours', v_policy."criticalHoursBeforeDeparture"
    );
  END IF;

  SELECT * INTO v_tier
  FROM "CompanyCancellationPenaltyTier" t
  WHERE t."companyId" = p_company_id
    AND t."minHoursBeforeDeparture" <= p_hours_before_departure
  ORDER BY t."minHoursBeforeDeparture" DESC
  LIMIT 1;

  IF v_tier IS NULL THEN
    v_penalty_type := 'percent';
    v_penalty_value := 0;
    v_label := 'default';
  ELSE
    v_penalty_type := v_tier."penaltyType";
    v_penalty_value := v_tier."penaltyValue";
    v_label := COALESCE(v_tier.label, 'tier');
  END IF;

  RETURN jsonb_build_object(
    'staffOnly', false,
    'penaltyType', v_penalty_type,
    'penaltyValue', v_penalty_value,
    'tierLabel', v_label,
    'hoursBeforeDeparture', p_hours_before_departure,
    'criticalHours', v_policy."criticalHoursBeforeDeparture"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_company_cancellation_policy(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_policy jsonb;
  v_tiers jsonb;
BEGIN
  IF NOT public.can_view_company_sales(p_company_id) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acces politique annulation refuse';
  END IF;

  SELECT jsonb_build_object(
    'companyId', cp."companyId",
    'criticalHoursBeforeDeparture', cp."criticalHoursBeforeDeparture",
    'criticalPenaltyType', cp."criticalPenaltyType",
    'criticalPenaltyValue', cp."criticalPenaltyValue",
    'isActive', cp."isActive"
  )
  INTO v_policy
  FROM "CompanyCancellationPolicy" cp
  WHERE cp."companyId" = p_company_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'label', t.label,
      'minHoursBeforeDeparture', t."minHoursBeforeDeparture",
      'penaltyType', t."penaltyType",
      'penaltyValue', t."penaltyValue",
      'sortOrder', t."sortOrder"
    ) ORDER BY t."sortOrder", t."minHoursBeforeDeparture" DESC
  ), '[]'::jsonb)
  INTO v_tiers
  FROM "CompanyCancellationPenaltyTier" t
  WHERE t."companyId" = p_company_id;

  RETURN jsonb_build_object(
    'policy', COALESCE(v_policy, jsonb_build_object(
      'companyId', p_company_id,
      'criticalHoursBeforeDeparture', 24,
      'criticalPenaltyType', 'percent',
      'criticalPenaltyValue', 0,
      'isActive', true
    )),
    'tiers', v_tiers
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_company_cancellation_policy(
  p_company_id uuid,
  p_critical_hours double precision,
  p_critical_penalty_type text,
  p_critical_penalty_value double precision,
  p_is_active boolean DEFAULT true,
  p_tiers jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  tier jsonb;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF NOT public.has_company_role(p_company_id, ARRAY['owner']) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Seul le owner peut configurer les penalites';
  END IF;
  IF p_critical_penalty_type NOT IN ('percent', 'fixed') THEN
    RAISE EXCEPTION 'Type penalite critique invalide';
  END IF;

  INSERT INTO "CompanyCancellationPolicy" (
    "companyId", "criticalHoursBeforeDeparture", "criticalPenaltyType", "criticalPenaltyValue", "isActive", "updatedBy"
  ) VALUES (
    p_company_id, GREATEST(COALESCE(p_critical_hours, 0), 0), p_critical_penalty_type,
    GREATEST(COALESCE(p_critical_penalty_value, 0), 0), COALESCE(p_is_active, true), v_user_id
  )
  ON CONFLICT ("companyId") DO UPDATE SET
    "criticalHoursBeforeDeparture" = EXCLUDED."criticalHoursBeforeDeparture",
    "criticalPenaltyType" = EXCLUDED."criticalPenaltyType",
    "criticalPenaltyValue" = EXCLUDED."criticalPenaltyValue",
    "isActive" = EXCLUDED."isActive",
    "updatedBy" = EXCLUDED."updatedBy",
    "updatedAt" = now();

  DELETE FROM "CompanyCancellationPenaltyTier" WHERE "companyId" = p_company_id;

  IF p_tiers IS NOT NULL AND jsonb_typeof(p_tiers) = 'array' THEN
    FOR tier IN SELECT value FROM jsonb_array_elements(p_tiers)
    LOOP
      INSERT INTO "CompanyCancellationPenaltyTier" (
        "companyId", "label", "minHoursBeforeDeparture", "penaltyType", "penaltyValue", "sortOrder"
      ) VALUES (
        p_company_id,
        NULLIF(trim(tier->>'label'), ''),
        GREATEST(COALESCE(NULLIF(tier->>'minHoursBeforeDeparture', '')::double precision, 0), 0),
        COALESCE(NULLIF(tier->>'penaltyType', ''), 'percent'),
        GREATEST(COALESCE(NULLIF(tier->>'penaltyValue', '')::double precision, 0), 0),
        COALESCE(NULLIF(tier->>'sortOrder', '')::integer, 0)
      );
    END LOOP;
  END IF;

  RETURN public.get_company_cancellation_policy(p_company_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_company_ticket_sales(
  p_company_id uuid,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  booking_id uuid,
  created_at timestamptz,
  reference text,
  passenger_name text,
  seat_number text,
  ticket_amount double precision,
  currency text,
  sale_channel text,
  ticket_status text,
  seller_user_id uuid,
  seller_name text,
  route_label text,
  departure_time timestamptz,
  hours_before_departure double precision,
  can_cancel boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_view_company_sales(p_company_id) THEN
    RAISE EXCEPTION 'Acces journal ventes refuse';
  END IF;

  RETURN QUERY
  SELECT
    rb.id,
    rb."createdAt",
    p.reference::text,
    COALESCE(rb."passengerName", u."firstName" || ' ' || u."lastName")::text,
    rb."seatNumber"::text,
    COALESCE(rb.price, 0)::double precision,
    COALESCE(country.currency, 'XOF')::text,
    COALESCE(rb."saleChannel", 'traveler')::text,
    COALESCE(rb."ticketStatus", 'issued')::text,
    rb."createdBy",
    NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), '')::text,
    (g_depart.name || ' -> ' || g_final.name)::text,
    r.date,
    GREATEST(EXTRACT(EPOCH FROM (r.date - now())) / 3600.0, 0)::double precision,
    (
      COALESCE(rb."ticketStatus", 'issued') = 'issued'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND r.date > now()
      AND public.can_cancel_company_ticket(p_company_id)
    )
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g_depart ON g_depart.id = pt.depart
  JOIN "Gares" g_final ON g_final.id = pt.final
  JOIN "Companies" c ON c.id = g_depart."companyId"
  LEFT JOIN "Countries" country ON country.id = c."countryId"
  LEFT JOIN "Users" u ON u.id = rb."createdBy"
  WHERE rb."type" = 'voyage'
    AND c.id = p_company_id
    AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
  ORDER BY rb."createdAt" DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.preview_ticket_cancellation(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_rb record;
  v_hours double precision;
  v_rule jsonb;
  v_m double precision;
  v_p double precision;
  v_refund double precision;
BEGIN
  SELECT rb.*, r.date AS departure_time, p.reference
  INTO v_rb
  FROM "ReservationBus" rb
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb.id = p_booking_id;

  IF v_rb.id IS NULL THEN RAISE EXCEPTION 'Billet introuvable'; END IF;
  v_company_id := public.reservation_company_id(v_rb."reservationId");
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;
  IF NOT public.can_view_company_sales(v_company_id) THEN RAISE EXCEPTION 'Acces refuse'; END IF;

  v_hours := GREATEST(EXTRACT(EPOCH FROM (v_rb.departure_time - now())) / 3600.0, 0);
  v_rule := public.resolve_cancellation_penalty(v_company_id, v_hours);
  v_m := COALESCE(v_rb.price, 0);
  v_p := public.compute_cancellation_penalty(v_m, v_rule->>'penaltyType', (v_rule->>'penaltyValue')::double precision);
  v_refund := GREATEST(v_m - v_p, 0);

  RETURN jsonb_build_object(
    'bookingId', p_booking_id,
    'reference', v_rb.reference,
    'nominalAmount', v_m,
    'penaltyAmount', v_p,
    'refundAmount', v_refund,
    'hoursBeforeDeparture', v_hours,
    'staffOnly', COALESCE((v_rule->>'staffOnly')::boolean, false),
    'penaltyType', v_rule->>'penaltyType',
    'penaltyValue', (v_rule->>'penaltyValue')::double precision,
    'tierLabel', v_rule->>'tierLabel',
    'canExecute', public.can_cancel_company_ticket(v_company_id)
      AND COALESCE(v_rb."ticketStatus", 'issued') = 'issued'
      AND v_rb.departure_time > now()
      AND (
        COALESCE((v_rule->>'staffOnly')::boolean, false) = false
        OR public.can_cancel_company_ticket(v_company_id)
      )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_company_ticket(
  p_booking_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_rb record;
  v_preview jsonb;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT rb.*, r.date AS departure_time
  INTO v_rb
  FROM "ReservationBus" rb
  JOIN "Reservations" r ON r.id = rb."reservationId"
  WHERE rb.id = p_booking_id
  FOR UPDATE;

  IF v_rb.id IS NULL THEN RAISE EXCEPTION 'Billet introuvable'; END IF;
  IF COALESCE(v_rb."ticketStatus", 'issued') <> 'issued' THEN RAISE EXCEPTION 'Billet deja annule'; END IF;
  IF v_rb.departure_time <= now() THEN RAISE EXCEPTION 'Depart deja effectue ou en cours'; END IF;

  v_company_id := public.reservation_company_id(v_rb."reservationId");
  IF NOT public.can_cancel_company_ticket(v_company_id) THEN
    RAISE EXCEPTION 'Annulation reservee au owner et au vendeur de la compagnie';
  END IF;

  v_preview := public.preview_ticket_cancellation(p_booking_id);
  IF COALESCE((v_preview->>'canExecute')::boolean, false) = false THEN
    RAISE EXCEPTION 'Annulation impossible dans la fenetre actuelle';
  END IF;

  UPDATE "ReservationBus"
  SET
    "ticketStatus" = 'cancelled',
    "cancelledAt" = now(),
    "cancelledBy" = v_user_id,
    "penaltyAmount" = (v_preview->>'penaltyAmount')::double precision,
    "refundAmount" = (v_preview->>'refundAmount')::double precision,
    "cancellationReason" = NULLIF(trim(p_reason), ''),
    "sellerCommissionStatus" = CASE
      WHEN "sellerCommissionAmount" IS NOT NULL THEN 'cancelled'
      ELSE "sellerCommissionStatus"
    END
  WHERE id = p_booking_id;

  RETURN v_preview || jsonb_build_object('status', 'cancelled', 'cancelledAt', now());
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_view_company_sales(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_cancel_company_ticket(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_cancellation_policy(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_company_cancellation_policy(uuid, double precision, text, double precision, boolean, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_ticket_sales(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_ticket_cancellation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_company_ticket(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_cancellation_penalty(uuid, double precision) TO authenticated;
