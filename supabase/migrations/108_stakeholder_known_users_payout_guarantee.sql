-- 108 — Stakeholders identifiés, seuils de demande, approbation admin/comptable, commission guichet → fonds garantie

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "guaranteeCommissionLedgerId" uuid;

CREATE TABLE IF NOT EXISTS "StakeholderCommissionPayoutMinimums" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "countryId" uuid NOT NULL REFERENCES "Countries" ("id") ON DELETE CASCADE,
  "stakeholderRole" text NOT NULL,
  "minimumAmount" double precision NOT NULL DEFAULT 5000,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users" ("id") DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT "StakeholderCommissionPayoutMinimums_country_role_key"
    UNIQUE ("countryId", "stakeholderRole")
);

CREATE OR REPLACE FUNCTION public._stakeholder_payout_minimum(
  p_country_id uuid,
  p_stakeholder_role text
)
RETURNS double precision
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT m."minimumAmount"
      FROM "StakeholderCommissionPayoutMinimums" m
      WHERE m."countryId" = p_country_id
        AND m."stakeholderRole" = p_stakeholder_role
    ),
    CASE p_stakeholder_role
      WHEN 'platform' THEN 0
      WHEN 'admin_pays' THEN 10000
      WHEN 'recruiter' THEN 5000
      WHEN 'master' THEN 5000
      WHEN 'seller' THEN 3000
      ELSE 5000
    END
  );
$$;

CREATE OR REPLACE FUNCTION public._can_request_stakeholder_settlement(
  p_country_id uuid,
  p_beneficiary_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN public.is_super_admin()
    OR public.has_country_role(p_country_id, ARRAY['admin_pays'])
    OR p_beneficiary_user_id IS NOT DISTINCT FROM v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._can_approve_stakeholder_settlement(p_country_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;
  IF public.is_super_admin() THEN
    RETURN true;
  END IF;
  IF public.has_country_role(p_country_id, ARRAY['admin_pays']) THEN
    RETURN true;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND r.name = 'comptable_compagnie'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.charge_company_counter_platform_commission(
  p_booking_id uuid,
  p_company_id uuid,
  p_amount double precision,
  p_reference text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance double precision;
  v_new_balance double precision;
  v_allow_negative boolean;
  v_ledger_id uuid;
  v_existing uuid;
BEGIN
  IF COALESCE(p_amount, 0) <= 0 OR p_company_id IS NULL OR p_booking_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT rb."guaranteeCommissionLedgerId"
  INTO v_existing
  FROM "ReservationBus" rb
  WHERE rb.id = p_booking_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT c."guaranteeBalance", c."guaranteeAllowNegative"
  INTO v_balance, v_allow_negative
  FROM "Companies" c
  WHERE c.id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT COALESCE(v_allow_negative, false) AND v_balance < p_amount THEN
    RAISE EXCEPTION 'Fond de garantie insuffisant pour la commission guichet (solde: %, requis: %)', v_balance, p_amount
      USING ERRCODE = 'P0001';
  END IF;

  v_new_balance := v_balance - p_amount;

  UPDATE "Companies"
  SET "guaranteeBalance" = v_new_balance
  WHERE id = p_company_id;

  INSERT INTO "CompanyGuaranteeLedger" (
    "companyId", "type", "amount", "balanceAfter", "reference", "bookingId", "note", "createdBy"
  )
  VALUES (
    p_company_id,
    'counter_commission',
    p_amount,
    v_new_balance,
    NULLIF(trim(p_reference), ''),
    p_booking_id,
    'Commission plateforme vente guichet',
    public.current_app_user_id()
  )
  RETURNING id INTO v_ledger_id;

  UPDATE "ReservationBus"
  SET "guaranteeCommissionLedgerId" = v_ledger_id
  WHERE id = p_booking_id;

  IF v_new_balance <= 0 THEN
    PERFORM public.notify_guarantee_balance_low(p_company_id, v_new_balance);
  END IF;

  RETURN v_ledger_id;
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
  v_reference text;
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

  IF v_amount > 0 AND v_source = 'counter_company' THEN
    v_reference := COALESCE(p_booking_id::text, p_booking_id::text);
    PERFORM public.charge_company_counter_platform_commission(
      p_booking_id, v_company_id, v_amount, v_reference
    );
  END IF;
END;
$$;

DO $$
DECLARE v_row record;
BEGIN
  FOR v_row IN
    SELECT rb.id AS booking_id, rb.price AS nominal_amount,
      COALESCE(rb."saleChannel", 'traveler') AS sale_channel, g."companyId" AS company_id,
      rb.id::text
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    WHERE rb."type" = 'voyage'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND rb."platformCommissionSource" = 'counter_company'
      AND COALESCE(rb."platformCommissionAmount", 0) > 0
      AND rb."guaranteeCommissionLedgerId" IS NULL
  LOOP
    PERFORM public.charge_company_counter_platform_commission(
      v_row.booking_id,
      v_row.company_id,
      (
        SELECT COALESCE(rb2."platformCommissionAmount", 0)
        FROM "ReservationBus" rb2
        WHERE rb2.id = v_row.booking_id
      ),
      v_row.reference
    );
  END LOOP;
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
      c.id AS company_id,
      c.name AS company_name,
      c."countryId" AS country_id,
      COALESCE(country.currency, 'XOF')::text AS currency
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
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
        ELSE public._booking_platform_commission_amount(pb.nominal_amount, pb.company_id, 'traveler', NULL)
      END AS platform_commission_amount
    FROM paid_bookings pb
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
      AND (
        s.stakeholder_role = 'platform'
        OR s.beneficiary_user_id IS NOT NULL
      )
  )
  SELECT
    bs.country_id,
    bs.company_id,
    bs.company_name,
    bs.stakeholder_role,
    COALESCE(bs.label, bs.stakeholder_role) AS stakeholder_label,
    bs.setting_beneficiary_user_id AS beneficiary_user_id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), ''),
    MAX(bs.rate),
    MAX(bs.base_type),
    ROUND(SUM(bs.platform_commission_amount * bs.rate / 100.0)::numeric, 2)::double precision,
    COUNT(DISTINCT bs.booking_id)::bigint,
    MAX(bs.currency)
  FROM booking_settings bs
  LEFT JOIN "Users" u ON u.id = bs.setting_beneficiary_user_id
  WHERE bs.stakeholder_role = 'platform' OR bs.setting_beneficiary_user_id IS NOT NULL
  GROUP BY
    bs.country_id,
    bs.company_id,
    bs.company_name,
    bs.stakeholder_role,
    bs.label,
    bs.setting_beneficiary_user_id,
    u."firstName",
    u."lastName"
  HAVING SUM(bs.platform_commission_amount * bs.rate / 100.0) > 0;
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
  IF p_stakeholder_role <> 'platform'
    AND p_stakeholder_role <> 'custom'
    AND COALESCE(p_rate, 0) > 0
    AND p_beneficiary_user_id IS NULL
  THEN
    RAISE EXCEPTION 'Utilisateur bénéficiaire requis pour le rôle %', p_stakeholder_role;
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

DROP FUNCTION IF EXISTS public.list_stakeholder_commission_balances(uuid);

CREATE OR REPLACE FUNCTION public.list_stakeholder_commission_balances(p_country_id uuid DEFAULT NULL)
RETURNS TABLE(
  country_id uuid,
  country_name text,
  stakeholder_role text,
  beneficiary_user_id uuid,
  beneficiary_name text,
  rate double precision,
  base_type text,
  earned_amount double precision,
  paid_amount double precision,
  pending_amount double precision,
  balance_due double precision,
  minimum_payout double precision,
  currency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);
  IF v_country_id IS NULL THEN
    IF public.is_super_admin() THEN RAISE EXCEPTION 'Pays requis'; END IF;
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
    OR public._can_approve_stakeholder_settlement(v_country_id)
    OR EXISTS (
      SELECT 1 FROM public._stakeholder_commission_earned_rows(v_country_id) e
      WHERE e.beneficiary_user_id = v_user_id
    )
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  WITH earned AS (
    SELECT
      e.country_id,
      e.stakeholder_role,
      e.beneficiary_user_id,
      MAX(e.beneficiary_name) AS beneficiary_name,
      MAX(e.rate) AS rate,
      MAX(e.base_type) AS base_type,
      SUM(e.earned_amount) AS earned_amount,
      MAX(e.currency) AS currency
    FROM public._stakeholder_commission_earned_rows(v_country_id) e
    GROUP BY e.country_id, e.stakeholder_role, e.beneficiary_user_id
  ),
  settlements AS (
    SELECT
      s."countryId" AS country_id,
      s."stakeholderRole" AS stakeholder_role,
      s."beneficiaryUserId" AS beneficiary_user_id,
      SUM(CASE WHEN s.status = 'confirmed' THEN s.amount ELSE 0 END) AS paid_amount,
      SUM(CASE WHEN s.status = 'pending_confirmation' THEN s.amount ELSE 0 END) AS pending_amount
    FROM "StakeholderCommissionSettlements" s
    WHERE s."countryId" = v_country_id
    GROUP BY s."countryId", s."stakeholderRole", s."beneficiaryUserId"
  ),
  merged AS (
    SELECT
      e.*,
      COALESCE(st.paid_amount, 0) AS paid_amount,
      COALESCE(st.pending_amount, 0) AS pending_amount
    FROM earned e
    LEFT JOIN settlements st
      ON st.country_id = e.country_id
      AND st.stakeholder_role = e.stakeholder_role
      AND st.beneficiary_user_id IS NOT DISTINCT FROM e.beneficiary_user_id
  )
  SELECT
    m.country_id,
    c.name::text,
    m.stakeholder_role,
    m.beneficiary_user_id,
    m.beneficiary_name,
    m.rate,
    m.base_type,
    m.earned_amount,
    m.paid_amount,
    m.pending_amount,
    GREATEST(m.earned_amount - m.paid_amount - m.pending_amount, 0)::double precision,
    public._stakeholder_payout_minimum(m.country_id, m.stakeholder_role),
    m.currency
  FROM merged m
  JOIN "Countries" c ON c.id = m.country_id
  WHERE public.is_super_admin()
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
    OR public._can_approve_stakeholder_settlement(v_country_id)
    OR m.beneficiary_user_id = v_user_id
  ORDER BY public._stakeholder_role_sort(m.stakeholder_role), m.beneficiary_name NULLS FIRST;
END;
$$;

CREATE OR REPLACE FUNCTION public.initiate_stakeholder_commission_settlement(
  p_country_id uuid,
  p_stakeholder_role text,
  p_beneficiary_user_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_balance record;
  v_id uuid;
  v_minimum double precision;
BEGIN
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  IF p_stakeholder_role NOT IN ('platform', 'admin_pays', 'master', 'seller', 'company', 'recruiter', 'custom') THEN
    RAISE EXCEPTION 'Role stakeholder invalide';
  END IF;

  IF p_stakeholder_role <> 'platform' AND p_beneficiary_user_id IS NULL THEN
    RAISE EXCEPTION 'Beneficiaire requis';
  END IF;

  IF NOT public._can_request_stakeholder_settlement(p_country_id, p_beneficiary_user_id) THEN
    RAISE EXCEPTION 'Droits insuffisants pour demander ce reglement';
  END IF;

  SELECT *
  INTO v_balance
  FROM public.list_stakeholder_commission_balances(p_country_id) b
  WHERE b.stakeholder_role = p_stakeholder_role
    AND b.beneficiary_user_id IS NOT DISTINCT FROM p_beneficiary_user_id
  LIMIT 1;

  IF NOT FOUND OR COALESCE(v_balance.balance_due, 0) <= 0 THEN
    RAISE EXCEPTION 'Aucun solde a regler';
  END IF;

  v_minimum := COALESCE(v_balance.minimum_payout, public._stakeholder_payout_minimum(p_country_id, p_stakeholder_role));
  IF v_balance.balance_due < v_minimum THEN
    RAISE EXCEPTION 'Solde minimum requis : % % (solde actuel : %)', v_minimum, COALESCE(v_balance.currency, 'XOF'), v_balance.balance_due;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM "StakeholderCommissionSettlements" s
    WHERE s."countryId" = p_country_id
      AND s."stakeholderRole" = p_stakeholder_role
      AND s."beneficiaryUserId" IS NOT DISTINCT FROM p_beneficiary_user_id
      AND s.status = 'pending_confirmation'
  ) THEN
    RAISE EXCEPTION 'Une demande est deja en attente de validation';
  END IF;

  v_user_id := public.current_app_user_id();

  INSERT INTO "StakeholderCommissionSettlements" (
    "countryId", "stakeholderRole", "beneficiaryUserId", "amount", "currency",
    "status", "earnedSnapshot", "note", "initiatedBy"
  )
  VALUES (
    p_country_id,
    p_stakeholder_role,
    p_beneficiary_user_id,
    v_balance.balance_due,
    COALESCE(v_balance.currency, 'XOF'),
    'pending_confirmation',
    v_balance.earned_amount,
    NULLIF(trim(p_note), ''),
    v_user_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_stakeholder_commission_settlement(p_settlement_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settlement record;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();

  SELECT *
  INTO v_settlement
  FROM "StakeholderCommissionSettlements"
  WHERE id = p_settlement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reglement introuvable';
  END IF;

  IF v_settlement.status <> 'pending_confirmation' THEN
    RAISE EXCEPTION 'Reglement deja traite';
  END IF;

  IF NOT public._can_approve_stakeholder_settlement(v_settlement."countryId") THEN
    RAISE EXCEPTION 'Validation reservee au super admin, admin pays ou comptable';
  END IF;

  UPDATE "StakeholderCommissionSettlements"
  SET
    status = 'confirmed',
    "confirmedBy" = v_user_id,
    "confirmedAt" = now()
  WHERE id = p_settlement_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_stakeholder_commission_settlement(
  p_settlement_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settlement record;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();

  SELECT *
  INTO v_settlement
  FROM "StakeholderCommissionSettlements"
  WHERE id = p_settlement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reglement introuvable';
  END IF;

  IF v_settlement.status <> 'pending_confirmation' THEN
    RAISE EXCEPTION 'Reglement deja traite';
  END IF;

  IF NOT (
    public._can_approve_stakeholder_settlement(v_settlement."countryId")
    OR v_settlement."initiatedBy" = v_user_id
    OR v_settlement."beneficiaryUserId" = v_user_id
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants pour refuser ce reglement';
  END IF;

  UPDATE "StakeholderCommissionSettlements"
  SET
    status = 'rejected',
    "rejectedBy" = v_user_id,
    "rejectedAt" = now(),
    "rejectionReason" = NULLIF(trim(p_reason), '')
  WHERE id = p_settlement_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_stakeholder_commission_dashboard(
  p_country_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_country_id uuid;
  v_balances jsonb := '[]'::jsonb;
  v_pending jsonb := '[]'::jsonb;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);

  IF v_country_id IS NULL THEN
    SELECT ur."countryId"
    INTO v_country_id
    FROM "UserRoles" ur
    WHERE ur."userId" = v_user_id
      AND ur."countryId" IS NOT NULL
    LIMIT 1;
  END IF;

  IF v_country_id IS NULL THEN
    RETURN jsonb_build_object('balances', '[]'::jsonb, 'pendingSettlements', '[]'::jsonb, 'canApprove', public.is_super_admin());
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(b)), '[]'::jsonb)
  INTO v_balances
  FROM public.list_stakeholder_commission_balances(v_country_id) b
  WHERE b.beneficiary_user_id = v_user_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
  INTO v_pending
  FROM public.list_stakeholder_commission_settlement_history(v_country_id, v_user_id, 20) s
  WHERE s.status = 'pending_confirmation';

  RETURN jsonb_build_object(
    'countryId', v_country_id,
    'balances', v_balances,
    'pendingSettlements', v_pending,
    'canApprove', public._can_approve_stakeholder_settlement(v_country_id),
    'canRequest', true
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_stakeholder_payout_minimum(
  p_country_id uuid,
  p_stakeholder_role text,
  p_minimum_amount double precision
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_country_id IS NULL OR p_stakeholder_role IS NULL THEN
    RAISE EXCEPTION 'Pays et role requis';
  END IF;
  IF COALESCE(p_minimum_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Montant minimum invalide';
  END IF;

  INSERT INTO "StakeholderCommissionPayoutMinimums" (
    "countryId", "stakeholderRole", "minimumAmount", "updatedBy"
  )
  VALUES (
    p_country_id, p_stakeholder_role, p_minimum_amount, public.current_app_user_id()
  )
  ON CONFLICT ("countryId", "stakeholderRole")
  DO UPDATE SET
    "minimumAmount" = EXCLUDED."minimumAmount",
    "updatedAt" = now(),
    "updatedBy" = EXCLUDED."updatedBy"
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_stakeholder_country_users(p_country_id uuid)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  email text,
  roles text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')::text,
    u.email::text,
    COALESCE(array_agg(DISTINCT r.name) FILTER (WHERE r.name IS NOT NULL), ARRAY[]::text[])
  FROM "Users" u
  JOIN "UserRoles" ur ON ur."userId" = u.id
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."countryId" = p_country_id
     OR r.name IN ('admin_pays', 'master', 'master_independant', 'vendeur_master', 'vendeur_independant', 'super_admin')
  GROUP BY u.id, u."firstName", u."lastName", u.email
  ORDER BY 2 NULLS LAST, u.email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_stakeholder_commission_dashboard(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_stakeholder_payout_minimum(uuid, text, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_country_users(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.charge_company_counter_platform_commission(uuid, uuid, double precision, text) TO service_role;

CREATE OR REPLACE FUNCTION public.list_stakeholder_payout_minimums(p_country_id uuid)
RETURNS TABLE(stakeholder_role text, minimum_amount double precision)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT r.role_name, public._stakeholder_payout_minimum(p_country_id, r.role_name)
  FROM (
    SELECT unnest(ARRAY['platform','admin_pays','recruiter','master','seller','custom']) AS role_name
  ) r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_stakeholder_payout_minimums(uuid) TO authenticated;

