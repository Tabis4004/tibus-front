
-- Drop fonctions remplacées (signatures prod variables)
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        '_stakeholder_commission_base_amount',
        '_stakeholder_commission_earned_rows',
        '_stakeholder_settings_for_booking',
        'list_stakeholder_commission_balances',
        'list_stakeholder_revenue_sharing',
        'get_platform_commission_summary',
        'upsert_stakeholder_commission_setting',
        'list_stakeholder_commission_settings'
      )
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s) CASCADE', r.proname, r.args);
  END LOOP;
END $$;

-- 105 — Capture commission plateforme (voyageur) + partage stakeholders par pays/compagnie

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "platformCommissionAmount" double precision,
  ADD COLUMN IF NOT EXISTS "platformCommissionRate" double precision,
  ADD COLUMN IF NOT EXISTS "commissionPaidBy" text,
  ADD COLUMN IF NOT EXISTS "travelerPaidTotal" double precision;

ALTER TABLE "Companies"
  ADD COLUMN IF NOT EXISTS "recruitedByUserId" uuid;

ALTER TABLE "Companies"
  DROP CONSTRAINT IF EXISTS "Companies_recruitedByUserId_fkey";
ALTER TABLE "Companies"
  ADD CONSTRAINT "Companies_recruitedByUserId_fkey"
  FOREIGN KEY ("recruitedByUserId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

CREATE TABLE IF NOT EXISTS "StakeholderCommissionSettings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "scope" text NOT NULL,
  "countryId" uuid,
  "companyId" uuid,
  "stakeholderRole" text NOT NULL,
  "label" text,
  "beneficiaryUserId" uuid,
  "rate" double precision NOT NULL DEFAULT 0,
  "baseType" text NOT NULL DEFAULT 'platform_commission',
  "sortOrder" integer NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid
);

ALTER TABLE "StakeholderCommissionSettings"
  ADD COLUMN IF NOT EXISTS "companyId" uuid,
  ADD COLUMN IF NOT EXISTS "label" text,
  ADD COLUMN IF NOT EXISTS "beneficiaryUserId" uuid;

CREATE TABLE IF NOT EXISTS "StakeholderCommissionSettlements" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "countryId" uuid NOT NULL,
  "stakeholderRole" text NOT NULL,
  "beneficiaryUserId" uuid,
  "amount" double precision NOT NULL,
  "currency" text NOT NULL DEFAULT 'XOF',
  "status" text NOT NULL DEFAULT 'pending_confirmation',
  "earnedSnapshot" double precision,
  "note" text,
  "initiatedBy" uuid NOT NULL,
  "initiatedAt" timestamptz NOT NULL DEFAULT now(),
  "confirmedBy" uuid,
  "confirmedAt" timestamptz,
  "rejectedBy" uuid,
  "rejectedAt" timestamptz,
  "rejectionReason" text
);

CREATE OR REPLACE FUNCTION public._booking_platform_commission_amount(
  p_nominal_amount double precision,
  p_company_id uuid,
  p_sale_channel text DEFAULT 'traveler',
  p_commission_rate double precision DEFAULT NULL
)
RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_margin record;
  v_rate double precision;
BEGIN
  IF p_nominal_amount IS NULL OR p_nominal_amount <= 0 OR p_company_id IS NULL THEN
    RETURN 0;
  END IF;
  IF COALESCE(p_sale_channel, 'traveler') NOT IN ('traveler', 'counter_sale') THEN
    RETURN 0;
  END IF;
  SELECT * INTO v_margin FROM public.resolve_seller_commission_setting(p_company_id) LIMIT 1;
  IF COALESCE(v_margin.paid_by, 'company') <> 'traveler' THEN
    RETURN 0;
  END IF;
  v_rate := COALESCE(p_commission_rate, v_margin.rate, 0);
  RETURN ROUND((p_nominal_amount * v_rate / 100.0)::numeric, 2)::double precision;
END;
$$;

CREATE OR REPLACE FUNCTION public.capture_booking_platform_commission(
  p_booking_id uuid,
  p_nominal_amount double precision DEFAULT NULL,
  p_company_id uuid DEFAULT NULL,
  p_sale_channel text DEFAULT NULL,
  p_commission_rate double precision DEFAULT NULL,
  p_traveler_paid_total double precision DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking record;
  v_company_id uuid;
  v_nominal double precision;
  v_channel text;
  v_margin record;
  v_amount double precision;
BEGIN
  SELECT rb.*, g."companyId" AS resolved_company_id
  INTO v_booking
  FROM "ReservationBus" rb
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g ON g.id = pt.depart
  WHERE rb.id = p_booking_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Billet introuvable'; END IF;

  v_company_id := COALESCE(p_company_id, v_booking.resolved_company_id);
  v_nominal := COALESCE(p_nominal_amount, v_booking.price, 0);
  v_channel := COALESCE(p_sale_channel, v_booking."saleChannel", 'traveler');
  SELECT * INTO v_margin FROM public.resolve_seller_commission_setting(v_company_id) LIMIT 1;
  v_amount := public._booking_platform_commission_amount(
    v_nominal, v_company_id, v_channel, COALESCE(p_commission_rate, v_margin.rate)
  );

  UPDATE "ReservationBus"
  SET
    "platformCommissionAmount" = v_amount,
    "platformCommissionRate" = COALESCE(p_commission_rate, v_margin.rate, 0),
    "commissionPaidBy" = COALESCE(v_margin.paid_by, 'company'),
    "travelerPaidTotal" = COALESCE(p_traveler_paid_total, "travelerPaidTotal")
  WHERE id = p_booking_id;
END;
$$;

DO $$
DECLARE v_row record;
BEGIN
  FOR v_row IN
    SELECT rb.id AS booking_id, rb.price AS nominal_amount,
      COALESCE(rb."saleChannel", 'traveler') AS sale_channel, g."companyId" AS company_id
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    WHERE rb."type" = 'voyage'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."platformCommissionAmount", 0) = 0
  LOOP
    PERFORM public.capture_booking_platform_commission(
      v_row.booking_id, v_row.nominal_amount, v_row.company_id, v_row.sale_channel, NULL, NULL
    );
  END LOOP;
END;
$$;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = '_stakeholder_commission_base_amount' AND n.nspname = 'public'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public._stakeholder_commission_base_amount(%s)', r.args);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_base_amount(
  p_base_type text,
  p_gateway_amount double precision,
  p_total_amount double precision,
  p_platform_net_amount double precision,
  p_platform_commission_amount double precision DEFAULT 0
)
RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_base_type
    WHEN 'platform_commission' THEN COALESCE(NULLIF(p_platform_commission_amount, 0), 0)
    WHEN 'total_amount' THEN COALESCE(p_total_amount, p_gateway_amount)
    WHEN 'platform_net' THEN COALESCE(p_platform_net_amount, p_gateway_amount)
    ELSE COALESCE(p_gateway_amount, 0)
  END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_role_sort(p_role text)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_role
    WHEN 'platform' THEN 1 WHEN 'admin_pays' THEN 2 WHEN 'recruiter' THEN 3
    WHEN 'master' THEN 4 WHEN 'seller' THEN 5 WHEN 'company' THEN 6 WHEN 'custom' THEN 7 ELSE 99 END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_settings_for_booking(p_country_id uuid, p_company_id uuid)
RETURNS TABLE(
  setting_id uuid, stakeholder_role text, label text, beneficiary_user_id uuid,
  rate double precision, base_type text, sort_order integer, source text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  WITH company_rows AS (
    SELECT s.* FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = 'company' AND s."companyId" = p_company_id AND s."isActive" = true AND s.rate > 0
  ), country_rows AS (
    SELECT s.* FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = 'country' AND s."countryId" = p_country_id AND s."isActive" = true AND s.rate > 0
      AND NOT EXISTS (
        SELECT 1 FROM company_rows cr WHERE cr."stakeholderRole" = s."stakeholderRole"
          AND cr."beneficiaryUserId" IS NOT DISTINCT FROM s."beneficiaryUserId"
          AND COALESCE(cr.label, '') = COALESCE(s.label, ''))
  ), global_rows AS (
    SELECT s.* FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = 'global' AND s."isActive" = true AND s.rate > 0
      AND NOT EXISTS (
        SELECT 1 FROM company_rows cr WHERE cr."stakeholderRole" = s."stakeholderRole"
          AND cr."beneficiaryUserId" IS NOT DISTINCT FROM s."beneficiaryUserId"
          AND COALESCE(cr.label, '') = COALESCE(s.label, ''))
      AND NOT EXISTS (
        SELECT 1 FROM country_rows cr WHERE cr."stakeholderRole" = s."stakeholderRole"
          AND cr."beneficiaryUserId" IS NOT DISTINCT FROM s."beneficiaryUserId"
          AND COALESCE(cr.label, '') = COALESCE(s.label, ''))
  ), merged AS (
    SELECT * FROM company_rows UNION ALL SELECT * FROM country_rows UNION ALL SELECT * FROM global_rows
  )
  SELECT m.id, m."stakeholderRole", m.label, m."beneficiaryUserId", m.rate,
    COALESCE(m."baseType", 'platform_commission'),
    COALESCE(m."sortOrder", public._stakeholder_role_sort(m."stakeholderRole")),
    m."scope"
  FROM merged m ORDER BY 7, m."stakeholderRole", m.label NULLS FIRST;
END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_earned_rows(p_country_id uuid)
RETURNS TABLE(
  country_id uuid, company_id uuid, company_name text, stakeholder_role text, stakeholder_label text,
  beneficiary_user_id uuid, beneficiary_name text, rate double precision, base_type text,
  earned_amount double precision, ticket_count bigint, currency text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_country_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
  WITH paid_bookings AS (
    SELECT rb.id AS booking_id, rb.price AS nominal_amount,
      COALESCE(rb."platformCommissionAmount", 0) AS stored_commission,
      rb."createdBy" AS seller_user_id, COALESCE(rb."saleChannel", 'traveler') AS sale_channel,
      c.id AS company_id, c.name AS company_name, c."countryId" AS country_id,
      c."recruitedByUserId" AS recruiter_user_id,
      COALESCE(country.currency, 'XOF')::text AS currency,
      owner_ur."userId" AS owner_user_id, mvn."masterUserId" AS master_user_id
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    LEFT JOIN LATERAL (
      SELECT ur."userId" FROM "UserRoles" ur
      JOIN "Role" owner_role ON owner_role.id = ur."roleId" AND owner_role.name = 'owner'
      WHERE ur."companyId" = c.id LIMIT 1
    ) owner_ur ON true
    LEFT JOIN "MasterVendorNetwork" mvn ON mvn."vendorUserId" = rb."createdBy" AND mvn."isActive" = true
    WHERE rb."type" = 'voyage' AND c."countryId" = p_country_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
  ), booking_commissions AS (
    SELECT pb.*,
      CASE WHEN pb.stored_commission > 0 THEN pb.stored_commission
        ELSE public._booking_platform_commission_amount(pb.nominal_amount, pb.company_id, pb.sale_channel, NULL)
      END AS platform_commission_amount
    FROM paid_bookings pb
  ), admin_users AS (
    SELECT ur."userId" AS user_id FROM "UserRoles" ur
    JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ro.name = 'admin_pays' AND ur."countryId" = p_country_id
  ), admin_count AS (SELECT GREATEST(COUNT(*)::double precision, 1) AS cnt FROM admin_users),
  booking_settings AS (
    SELECT bc.*, s.setting_id, s.stakeholder_role, s.label,
      s.beneficiary_user_id AS setting_beneficiary_user_id, s.rate, s.base_type
    FROM booking_commissions bc
    CROSS JOIN LATERAL public._stakeholder_settings_for_booking(bc.country_id, bc.company_id) s
    WHERE bc.platform_commission_amount > 0
  ), role_slices AS (
    SELECT bs.country_id, bs.company_id, bs.company_name, bs.stakeholder_role,
      COALESCE(bs.label, bs.stakeholder_role) AS stakeholder_label, bs.rate, bs.base_type, bs.currency,
      bs.platform_commission_amount, bs.booking_id,
      CASE bs.stakeholder_role
        WHEN 'platform' THEN NULL::uuid
        WHEN 'admin_pays' THEN au.user_id
        WHEN 'recruiter' THEN bs.recruiter_user_id
        WHEN 'master' THEN bs.master_user_id
        WHEN 'seller' THEN CASE WHEN bs.sale_channel = 'seller_reservation'
          AND NOT public.is_company_role_user(bs.seller_user_id, bs.company_id) THEN bs.seller_user_id ELSE NULL END
        WHEN 'company' THEN bs.owner_user_id
        ELSE bs.setting_beneficiary_user_id
      END AS beneficiary_user_id,
      CASE bs.stakeholder_role WHEN 'admin_pays' THEN (SELECT cnt FROM admin_count) ELSE 1::double precision END AS split_divisor
    FROM booking_settings bs LEFT JOIN admin_users au ON bs.stakeholder_role = 'admin_pays'
  )
  SELECT rs.country_id, rs.company_id, rs.company_name, rs.stakeholder_role, rs.stakeholder_label,
    rs.beneficiary_user_id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), ''),
    MAX(rs.rate), MAX(rs.base_type),
    ROUND(SUM(rs.platform_commission_amount * rs.rate / 100.0 / rs.split_divisor)::numeric, 2)::double precision,
    COUNT(DISTINCT rs.booking_id)::bigint, MAX(rs.currency)
  FROM role_slices rs LEFT JOIN "Users" u ON u.id = rs.beneficiary_user_id
  WHERE rs.stakeholder_role = 'platform' OR rs.beneficiary_user_id IS NOT NULL
  GROUP BY rs.country_id, rs.company_id, rs.company_name, rs.stakeholder_role, rs.stakeholder_label,
    rs.beneficiary_user_id, u."firstName", u."lastName"
  HAVING SUM(rs.platform_commission_amount * rs.rate / 100.0 / rs.split_divisor) > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_stakeholder_commission_balances(p_country_id uuid DEFAULT NULL)
RETURNS TABLE(
  country_id uuid, country_name text, stakeholder_role text, beneficiary_user_id uuid,
  beneficiary_name text, rate double precision, base_type text, earned_amount double precision,
  paid_amount double precision, pending_amount double precision, balance_due double precision, currency text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_country_id uuid; v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);
  IF v_country_id IS NULL THEN
    IF public.is_super_admin() THEN RAISE EXCEPTION 'Pays requis'; END IF;
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT (public.is_super_admin() OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
    OR EXISTS (SELECT 1 FROM public._stakeholder_commission_earned_rows(v_country_id) e WHERE e.beneficiary_user_id = v_user_id))
  THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;

  RETURN QUERY
  WITH earned AS (
    SELECT e.country_id, e.stakeholder_role, e.beneficiary_user_id,
      MAX(e.beneficiary_name) AS beneficiary_name, MAX(e.rate) AS rate, MAX(e.base_type) AS base_type,
      SUM(e.earned_amount) AS earned_amount, MAX(e.currency) AS currency
    FROM public._stakeholder_commission_earned_rows(v_country_id) e
    GROUP BY e.country_id, e.stakeholder_role, e.beneficiary_user_id
  ), settlements AS (
    SELECT s."countryId" AS country_id, s."stakeholderRole" AS stakeholder_role,
      s."beneficiaryUserId" AS beneficiary_user_id,
      SUM(CASE WHEN s.status = 'confirmed' THEN s.amount ELSE 0 END) AS paid_amount,
      SUM(CASE WHEN s.status = 'pending_confirmation' THEN s.amount ELSE 0 END) AS pending_amount
    FROM "StakeholderCommissionSettlements" s WHERE s."countryId" = v_country_id
    GROUP BY s."countryId", s."stakeholderRole", s."beneficiaryUserId"
  ), merged AS (
    SELECT e.*, COALESCE(st.paid_amount,0) AS paid_amount, COALESCE(st.pending_amount,0) AS pending_amount
    FROM earned e LEFT JOIN settlements st ON st.country_id = e.country_id
      AND st.stakeholder_role = e.stakeholder_role
      AND st.beneficiary_user_id IS NOT DISTINCT FROM e.beneficiary_user_id
  )
  SELECT m.country_id, c.name::text, m.stakeholder_role, m.beneficiary_user_id, m.beneficiary_name,
    m.rate, m.base_type, m.earned_amount, m.paid_amount, m.pending_amount,
    GREATEST(m.earned_amount - m.paid_amount - m.pending_amount, 0)::double precision, m.currency
  FROM merged m JOIN "Countries" c ON c.id = m.country_id
  WHERE public.is_super_admin() OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
    OR m.beneficiary_user_id = v_user_id
  ORDER BY public._stakeholder_role_sort(m.stakeholder_role), m.beneficiary_name NULLS FIRST;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_stakeholder_revenue_sharing(
  p_country_id uuid, p_company_id uuid DEFAULT NULL
)
RETURNS TABLE(
  country_id uuid, company_id uuid, company_name text, stakeholder_role text, stakeholder_label text,
  beneficiary_user_id uuid, beneficiary_name text, rate double precision, earned_amount double precision,
  ticket_count bigint, currency text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_country_id uuid;
BEGIN
  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);
  IF v_country_id IS NULL THEN RAISE EXCEPTION 'Pays requis'; END IF;
  IF NOT (public.is_super_admin() OR public.has_country_role(v_country_id, ARRAY['admin_pays'])) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT e.country_id, e.company_id, e.company_name, e.stakeholder_role, e.stakeholder_label,
    e.beneficiary_user_id, e.beneficiary_name, e.rate, e.earned_amount, e.ticket_count, e.currency
  FROM public._stakeholder_commission_earned_rows(v_country_id) e
  WHERE p_company_id IS NULL OR e.company_id = p_company_id
  ORDER BY e.company_name, public._stakeholder_role_sort(e.stakeholder_role), e.stakeholder_label;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_platform_commission_summary(p_country_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_country_id uuid; v_captured double precision := 0; v_tickets bigint := 0;
  v_pending double precision := 0; v_paid double precision := 0; v_currency text := 'XOF';
BEGIN
  IF NOT public.is_super_admin() AND NOT (p_country_id IS NOT NULL AND public.has_country_role(p_country_id, ARRAY['admin_pays'])) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);
  IF v_country_id IS NOT NULL THEN
    SELECT COALESCE(SUM(rb."platformCommissionAmount"), 0), COUNT(*)::bigint, MAX(COALESCE(country.currency, 'XOF'))
    INTO v_captured, v_tickets, v_currency
    FROM "ReservationBus" rb JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    WHERE rb."type" = 'voyage' AND c."countryId" = v_country_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."platformCommissionAmount", 0) > 0;
    SELECT COALESCE(SUM(b.balance_due), 0), COALESCE(SUM(b.paid_amount), 0)
    INTO v_pending, v_paid FROM public.list_stakeholder_commission_balances(v_country_id) b;
  ELSE
    SELECT COALESCE(SUM(rb."platformCommissionAmount"), 0), COUNT(*)::bigint
    INTO v_captured, v_tickets FROM "ReservationBus" rb JOIN "Payment" p ON p.id = rb."paymentId"
    WHERE rb."type" = 'voyage' AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."platformCommissionAmount", 0) > 0;
  END IF;
  RETURN jsonb_build_object(
    'capturedTotal', ROUND(v_captured::numeric, 2), 'ticketCount', v_tickets,
    'stakeholderPending', ROUND(v_pending::numeric, 2), 'stakeholderPaid', ROUND(v_paid::numeric, 2),
    'currency', v_currency);
END;
$$;

DROP FUNCTION IF EXISTS public.upsert_stakeholder_commission_setting(text, uuid, text, double precision, text, boolean);
CREATE OR REPLACE FUNCTION public.upsert_stakeholder_commission_setting(
  p_scope text, p_country_id uuid DEFAULT NULL, p_stakeholder_role text DEFAULT 'platform',
  p_rate double precision DEFAULT 0, p_base_type text DEFAULT 'platform_commission',
  p_is_active boolean DEFAULT true, p_company_id uuid DEFAULT NULL,
  p_label text DEFAULT NULL, p_beneficiary_user_id uuid DEFAULT NULL, p_setting_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_user_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF p_scope NOT IN ('global', 'country', 'company') THEN RAISE EXCEPTION 'Scope invalide'; END IF;
  IF p_scope = 'country' AND p_country_id IS NULL THEN RAISE EXCEPTION 'countryId requis'; END IF;
  IF p_scope = 'company' AND p_company_id IS NULL THEN RAISE EXCEPTION 'companyId requis'; END IF;
  IF p_stakeholder_role = 'custom' AND (p_label IS NULL OR p_beneficiary_user_id IS NULL) THEN
    RAISE EXCEPTION 'Label et bénéficiaire requis pour un stakeholder custom';
  END IF;
  v_user_id := public.current_app_user_id();
  IF p_setting_id IS NOT NULL THEN
    UPDATE "StakeholderCommissionSettings" SET
      "scope" = p_scope,
      "countryId" = CASE WHEN p_scope IN ('country', 'company') THEN p_country_id ELSE NULL END,
      "companyId" = CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
      "stakeholderRole" = p_stakeholder_role, "label" = NULLIF(trim(p_label), ''),
      "beneficiaryUserId" = p_beneficiary_user_id, rate = p_rate,
      "baseType" = COALESCE(p_base_type, 'platform_commission'), "isActive" = p_is_active,
      "updatedAt" = now(), "updatedBy" = v_user_id
    WHERE id = p_setting_id RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  INSERT INTO "StakeholderCommissionSettings" (
    "scope", "countryId", "companyId", "stakeholderRole", "label", "beneficiaryUserId",
    rate, "baseType", "isActive", "updatedBy"
  ) VALUES (
    p_scope,
    CASE WHEN p_scope IN ('country', 'company') THEN p_country_id ELSE NULL END,
    CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
    p_stakeholder_role, NULLIF(trim(p_label), ''), p_beneficiary_user_id,
    p_rate, COALESCE(p_base_type, 'platform_commission'), p_is_active, v_user_id
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

DROP FUNCTION IF EXISTS public.list_stakeholder_commission_settings(uuid);
CREATE OR REPLACE FUNCTION public.list_stakeholder_commission_settings(p_country_id uuid DEFAULT NULL)
RETURNS TABLE(
  id uuid, scope text, country_id uuid, country_name text, company_id uuid, company_name text,
  stakeholder_role text, label text, beneficiary_user_id uuid, beneficiary_name text,
  rate double precision, base_type text, sort_order integer, is_active boolean, source text,
  updated_at timestamptz, updated_by_name text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  RETURN QUERY
  SELECT s.id, s."scope", s."countryId", co.name::text, s."companyId", comp.name::text,
    s."stakeholderRole", s.label, s."beneficiaryUserId",
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), ''),
    s.rate, COALESCE(s."baseType", 'platform_commission'),
    COALESCE(s."sortOrder", public._stakeholder_role_sort(s."stakeholderRole")),
    s."isActive", s."scope", s."updatedAt",
    NULLIF(TRIM(COALESCE(upd."firstName", '') || ' ' || COALESCE(upd."lastName", '')), '')
  FROM "StakeholderCommissionSettings" s
  LEFT JOIN "Countries" co ON co.id = s."countryId"
  LEFT JOIN "Companies" comp ON comp.id = s."companyId"
  LEFT JOIN "Users" u ON u.id = s."beneficiaryUserId"
  LEFT JOIN "Users" upd ON upd.id = s."updatedBy"
  WHERE p_country_id IS NULL OR s."countryId" = p_country_id OR s."scope" = 'global'
  ORDER BY s."scope", co.name NULLS FIRST, comp.name NULLS FIRST, 12, s."stakeholderRole", s.label NULLS FIRST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.capture_booking_platform_commission(uuid, double precision, uuid, text, double precision, double precision) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_platform_commission_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_revenue_sharing(uuid, uuid) TO authenticated;
