-- 107 — Distinction commissions voyageur en ligne / guichet + upsert stakeholders fiable

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "platformCommissionSource" text;

CREATE UNIQUE INDEX IF NOT EXISTS "StakeholderCommissionSettings_company_role_key"
  ON "StakeholderCommissionSettings" ("companyId", "stakeholderRole")
  WHERE "scope" = 'company' AND "isActive" = true;

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
  v_paid_by text;
  v_channel text;
BEGIN
  IF p_nominal_amount IS NULL OR p_nominal_amount <= 0 OR p_company_id IS NULL THEN
    RETURN 0;
  END IF;

  v_channel := COALESCE(p_sale_channel, 'traveler');
  IF v_channel NOT IN ('traveler', 'counter_sale') THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_margin FROM public.resolve_seller_commission_setting(p_company_id) LIMIT 1;
  v_paid_by := COALESCE(v_margin.paid_by, 'company');
  v_rate := COALESCE(p_commission_rate, v_margin.rate, 0);

  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;

  IF v_channel = 'traveler' AND v_paid_by = 'traveler' THEN
    RETURN ROUND((p_nominal_amount * v_rate / 100.0)::numeric, 2)::double precision;
  END IF;

  IF v_channel = 'counter_sale' AND v_paid_by = 'company' THEN
    RETURN ROUND((p_nominal_amount * v_rate / 100.0)::numeric, 2)::double precision;
  END IF;

  RETURN 0;
END;
$$;

CREATE OR REPLACE FUNCTION public._booking_platform_commission_source(
  p_sale_channel text,
  p_paid_by text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_sale_channel, 'traveler') = 'traveler'
      AND COALESCE(p_paid_by, 'company') = 'traveler'
      THEN 'traveler_online'
    WHEN COALESCE(p_sale_channel, 'traveler') = 'counter_sale'
      AND COALESCE(p_paid_by, 'company') = 'company'
      THEN 'counter_company'
    ELSE NULL
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
  v_paid_by text;
  v_source text;
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
  v_paid_by := COALESCE(v_margin.paid_by, 'company');
  v_amount := public._booking_platform_commission_amount(
    v_nominal, v_company_id, v_channel, COALESCE(p_commission_rate, v_margin.rate)
  );
  v_source := public._booking_platform_commission_source(v_channel, v_paid_by);

  UPDATE "ReservationBus"
  SET
    "platformCommissionAmount" = v_amount,
    "platformCommissionRate" = COALESCE(p_commission_rate, v_margin.rate, 0),
    "commissionPaidBy" = v_paid_by,
    "platformCommissionSource" = CASE WHEN v_amount > 0 THEN v_source ELSE NULL END,
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
  LOOP
    PERFORM public.capture_booking_platform_commission(
      v_row.booking_id, v_row.nominal_amount, v_row.company_id, v_row.sale_channel, NULL, NULL
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_platform_commission_summary(p_country_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
  v_traveler_captured double precision := 0;
  v_counter_captured double precision := 0;
  v_traveler_nominal double precision := 0;
  v_counter_nominal double precision := 0;
  v_traveler_tickets bigint := 0;
  v_counter_tickets bigint := 0;
  v_pending double precision := 0;
  v_paid double precision := 0;
  v_currency text := 'XOF';
BEGIN
  IF NOT public.is_super_admin()
    AND NOT (p_country_id IS NOT NULL AND public.has_country_role(p_country_id, ARRAY['admin_pays']))
  THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);

  IF v_country_id IS NOT NULL THEN
    SELECT
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'traveler_online' THEN rb."platformCommissionAmount" ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'counter_company' THEN rb."platformCommissionAmount" ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'traveler_online' THEN rb.price ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'counter_company' THEN rb.price ELSE 0 END), 0),
      COUNT(*) FILTER (WHERE rb."platformCommissionSource" = 'traveler_online'),
      COUNT(*) FILTER (WHERE rb."platformCommissionSource" = 'counter_company'),
      MAX(COALESCE(country.currency, 'XOF'))
    INTO v_traveler_captured, v_counter_captured, v_traveler_nominal, v_counter_nominal,
      v_traveler_tickets, v_counter_tickets, v_currency
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    WHERE rb."type" = 'voyage'
      AND c."countryId" = v_country_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."platformCommissionAmount", 0) > 0;

    SELECT COALESCE(SUM(b.balance_due), 0), COALESCE(SUM(b.paid_amount), 0)
    INTO v_pending, v_paid
    FROM public.list_stakeholder_commission_balances(v_country_id) b;
  ELSE
    SELECT
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'traveler_online' THEN rb."platformCommissionAmount" ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'counter_company' THEN rb."platformCommissionAmount" ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'traveler_online' THEN rb.price ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN rb."platformCommissionSource" = 'counter_company' THEN rb.price ELSE 0 END), 0),
      COUNT(*) FILTER (WHERE rb."platformCommissionSource" = 'traveler_online'),
      COUNT(*) FILTER (WHERE rb."platformCommissionSource" = 'counter_company')
    INTO v_traveler_captured, v_counter_captured, v_traveler_nominal, v_counter_nominal,
      v_traveler_tickets, v_counter_tickets
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    WHERE rb."type" = 'voyage'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."platformCommissionAmount", 0) > 0;
  END IF;

  RETURN jsonb_build_object(
    'capturedTotal', ROUND((v_traveler_captured + v_counter_captured)::numeric, 2),
    'travelerOnlineCaptured', ROUND(v_traveler_captured::numeric, 2),
    'counterCompanyCaptured', ROUND(v_counter_captured::numeric, 2),
    'travelerNominalTotal', ROUND(v_traveler_nominal::numeric, 2),
    'counterNominalTotal', ROUND(v_counter_nominal::numeric, 2),
    'ticketCount', v_traveler_tickets,
    'counterTicketCount', v_counter_tickets,
    'stakeholderPending', ROUND(v_pending::numeric, 2),
    'stakeholderPaid', ROUND(v_paid::numeric, 2),
    'currency', v_currency
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_stakeholder_commission_setting(
  p_scope text,
  p_country_id uuid DEFAULT NULL,
  p_stakeholder_role text DEFAULT 'platform',
  p_rate double precision DEFAULT 0,
  p_base_type text DEFAULT 'platform_commission',
  p_is_active boolean DEFAULT true,
  p_company_id uuid DEFAULT NULL,
  p_label text DEFAULT NULL,
  p_beneficiary_user_id uuid DEFAULT NULL,
  p_setting_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_user_id uuid;
  v_active boolean;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF p_scope NOT IN ('global', 'country', 'company') THEN
    RAISE EXCEPTION 'Scope invalide';
  END IF;
  IF p_scope = 'country' AND p_country_id IS NULL THEN
    RAISE EXCEPTION 'countryId requis';
  END IF;
  IF p_scope = 'company' AND (p_company_id IS NULL OR p_country_id IS NULL) THEN
    RAISE EXCEPTION 'companyId et countryId requis';
  END IF;
  IF p_stakeholder_role = 'custom' AND (p_label IS NULL OR p_beneficiary_user_id IS NULL) THEN
    RAISE EXCEPTION 'Label et bénéficiaire requis pour un stakeholder custom';
  END IF;

  v_user_id := public.current_app_user_id();
  v_active := COALESCE(p_is_active, true) AND COALESCE(p_rate, 0) > 0;

  IF p_setting_id IS NULL THEN
    SELECT s.id
    INTO v_id
    FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = p_scope
      AND s."stakeholderRole" = p_stakeholder_role
      AND (p_scope = 'global' OR s."countryId" IS NOT DISTINCT FROM p_country_id)
      AND (p_scope <> 'company' OR s."companyId" IS NOT DISTINCT FROM p_company_id)
      AND (
        p_stakeholder_role <> 'custom'
        OR (
          COALESCE(s.label, '') = COALESCE(NULLIF(trim(p_label), ''), '')
          AND s."beneficiaryUserId" IS NOT DISTINCT FROM p_beneficiary_user_id
        )
      )
    ORDER BY s."isActive" DESC, s."updatedAt" DESC NULLS LAST
    LIMIT 1;
  ELSE
    v_id := p_setting_id;
  END IF;

  IF v_id IS NOT NULL THEN
    UPDATE "StakeholderCommissionSettings"
    SET
      "scope" = p_scope,
      "countryId" = CASE WHEN p_scope IN ('country', 'company') THEN p_country_id ELSE NULL END,
      "companyId" = CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
      "stakeholderRole" = p_stakeholder_role,
      "label" = NULLIF(trim(p_label), ''),
      "beneficiaryUserId" = p_beneficiary_user_id,
      rate = COALESCE(p_rate, 0),
      "baseType" = COALESCE(p_base_type, 'platform_commission'),
      "isActive" = v_active,
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    WHERE id = v_id
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;

  INSERT INTO "StakeholderCommissionSettings" (
    "scope", "countryId", "companyId", "stakeholderRole", "label", "beneficiaryUserId",
    rate, "baseType", "isActive", "updatedBy"
  )
  VALUES (
    p_scope,
    CASE WHEN p_scope IN ('country', 'company') THEN p_country_id ELSE NULL END,
    CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
    p_stakeholder_role,
    NULLIF(trim(p_label), ''),
    p_beneficiary_user_id,
    COALESCE(p_rate, 0),
    COALESCE(p_base_type, 'platform_commission'),
    v_active,
    v_user_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION
  WHEN unique_violation THEN
    SELECT s.id
    INTO v_id
    FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = p_scope
      AND s."stakeholderRole" = p_stakeholder_role
      AND (p_scope = 'global' OR s."countryId" IS NOT DISTINCT FROM p_country_id)
      AND (p_scope <> 'company' OR s."companyId" IS NOT DISTINCT FROM p_company_id)
    ORDER BY s."updatedAt" DESC NULLS LAST
    LIMIT 1;

    IF v_id IS NULL THEN
      RAISE;
    END IF;

    UPDATE "StakeholderCommissionSettings"
    SET
      rate = COALESCE(p_rate, 0),
      "baseType" = COALESCE(p_base_type, 'platform_commission'),
      "isActive" = v_active,
      "label" = NULLIF(trim(p_label), ''),
      "beneficiaryUserId" = p_beneficiary_user_id,
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    WHERE id = v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_earned_rows(p_country_id uuid)
RETURNS TABLE(
  country_id uuid,
  company_id uuid,
  company_name text,
  stakeholder_role text,
  stakeholder_label text,
  beneficiary_user_id uuid,
  beneficiary_name text,
  rate double precision,
  base_type text,
  earned_amount double precision,
  ticket_count bigint,
  currency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_country_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH paid_bookings AS (
    SELECT
      rb.id AS booking_id,
      rb.price AS nominal_amount,
      COALESCE(rb."platformCommissionAmount", 0) AS stored_commission,
      rb."createdBy" AS seller_user_id,
      COALESCE(rb."saleChannel", 'traveler') AS sale_channel,
      c.id AS company_id,
      c.name AS company_name,
      c."countryId" AS country_id,
      c."recruitedByUserId" AS recruiter_user_id,
      COALESCE(country.currency, 'XOF')::text AS currency,
      owner_ur."userId" AS owner_user_id,
      mvn."masterUserId" AS master_user_id
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    LEFT JOIN LATERAL (
      SELECT ur."userId"
      FROM "UserRoles" ur
      JOIN "Role" owner_role ON owner_role.id = ur."roleId" AND owner_role.name = 'owner'
      WHERE ur."companyId" = c.id
      LIMIT 1
    ) owner_ur ON true
    LEFT JOIN "MasterVendorNetwork" mvn
      ON mvn."vendorUserId" = rb."createdBy" AND mvn."isActive" = true
    WHERE rb."type" = 'voyage'
      AND c."countryId" = p_country_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."platformCommissionSource", 'traveler_online') IN ('traveler_online', 'counter_company')
  ),
  booking_commissions AS (
    SELECT
      pb.*,
      CASE
        WHEN pb.stored_commission > 0 THEN pb.stored_commission
        ELSE public._booking_platform_commission_amount(pb.nominal_amount, pb.company_id, pb.sale_channel, NULL)
      END AS platform_commission_amount
    FROM paid_bookings pb
  ),
  admin_users AS (
    SELECT ur."userId" AS user_id
    FROM "UserRoles" ur
    JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ro.name = 'admin_pays' AND ur."countryId" = p_country_id
  ),
  admin_count AS (
    SELECT GREATEST(COUNT(*)::double precision, 1) AS cnt FROM admin_users
  ),
  booking_settings AS (
    SELECT
      bc.*,
      s.setting_id,
      s.stakeholder_role,
      s.label,
      s.beneficiary_user_id AS setting_beneficiary_user_id,
      s.rate,
      s.base_type
    FROM booking_commissions bc
    CROSS JOIN LATERAL public._stakeholder_settings_for_booking(bc.country_id, bc.company_id) s
    WHERE bc.platform_commission_amount > 0
  ),
  role_slices AS (
    SELECT
      bs.country_id,
      bs.company_id,
      bs.company_name,
      bs.stakeholder_role,
      COALESCE(bs.label, bs.stakeholder_role) AS stakeholder_label,
      bs.rate,
      bs.base_type,
      bs.currency,
      bs.platform_commission_amount,
      bs.booking_id,
      CASE bs.stakeholder_role
        WHEN 'platform' THEN NULL::uuid
        WHEN 'admin_pays' THEN au.user_id
        WHEN 'recruiter' THEN
          CASE
            WHEN bs.setting_beneficiary_user_id IS NOT NULL THEN bs.setting_beneficiary_user_id
            WHEN bs.recruiter_user_id IS NULL THEN NULL
            WHEN EXISTS (
              SELECT 1 FROM admin_users ad WHERE ad.user_id = bs.recruiter_user_id
            ) THEN NULL
            ELSE bs.recruiter_user_id
          END
        WHEN 'master' THEN bs.master_user_id
        WHEN 'seller' THEN
          CASE
            WHEN bs.sale_channel = 'seller_reservation'
              AND NOT public.is_company_role_user(bs.seller_user_id, bs.company_id)
              THEN bs.seller_user_id
            ELSE NULL
          END
        WHEN 'company' THEN bs.owner_user_id
        ELSE bs.setting_beneficiary_user_id
      END AS beneficiary_user_id,
      CASE bs.stakeholder_role
        WHEN 'admin_pays' THEN (SELECT cnt FROM admin_count)
        ELSE 1::double precision
      END AS split_divisor
    FROM booking_settings bs
    LEFT JOIN admin_users au ON bs.stakeholder_role = 'admin_pays'
  )
  SELECT
    rs.country_id,
    rs.company_id,
    rs.company_name,
    rs.stakeholder_role,
    rs.stakeholder_label,
    rs.beneficiary_user_id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), ''),
    MAX(rs.rate),
    MAX(rs.base_type),
    ROUND(SUM(rs.platform_commission_amount * rs.rate / 100.0 / rs.split_divisor)::numeric, 2)::double precision,
    COUNT(DISTINCT rs.booking_id)::bigint,
    MAX(rs.currency)
  FROM role_slices rs
  LEFT JOIN "Users" u ON u.id = rs.beneficiary_user_id
  WHERE rs.stakeholder_role = 'platform' OR rs.beneficiary_user_id IS NOT NULL
  GROUP BY
    rs.country_id,
    rs.company_id,
    rs.company_name,
    rs.stakeholder_role,
    rs.stakeholder_label,
    rs.beneficiary_user_id,
    u."firstName",
    u."lastName"
  HAVING SUM(rs.platform_commission_amount * rs.rate / 100.0 / rs.split_divisor) > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_commission_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_stakeholder_commission_setting(
  text, uuid, text, double precision, text, boolean, uuid, text, uuid, uuid
) TO authenticated;
