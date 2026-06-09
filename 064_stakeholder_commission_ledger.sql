-- 064 — Ledger des commissions stakeholders (calcul temps réel + règlements)
-- Exécuter après 063_stakeholder_commission_settings.sql

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
  "rejectionReason" text,
  CONSTRAINT "StakeholderCommissionSettlements_role_check"
    CHECK ("stakeholderRole" IN ('platform', 'admin_pays', 'master', 'seller', 'company')),
  CONSTRAINT "StakeholderCommissionSettlements_status_check"
    CHECK ("status" IN ('pending_confirmation', 'confirmed', 'rejected', 'cancelled')),
  CONSTRAINT "StakeholderCommissionSettlements_amount_check"
    CHECK ("amount" > 0)
);

ALTER TABLE "StakeholderCommissionSettlements"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettlements_countryId_fkey";
ALTER TABLE "StakeholderCommissionSettlements"
  ADD CONSTRAINT "StakeholderCommissionSettlements_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "StakeholderCommissionSettlements"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettlements_beneficiaryUserId_fkey";
ALTER TABLE "StakeholderCommissionSettlements"
  ADD CONSTRAINT "StakeholderCommissionSettlements_beneficiaryUserId_fkey"
  FOREIGN KEY ("beneficiaryUserId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "StakeholderCommissionSettlements"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettlements_initiatedBy_fkey";
ALTER TABLE "StakeholderCommissionSettlements"
  ADD CONSTRAINT "StakeholderCommissionSettlements_initiatedBy_fkey"
  FOREIGN KEY ("initiatedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "StakeholderCommissionSettlements"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettlements_confirmedBy_fkey";
ALTER TABLE "StakeholderCommissionSettlements"
  ADD CONSTRAINT "StakeholderCommissionSettlements_confirmedBy_fkey"
  FOREIGN KEY ("confirmedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "StakeholderCommissionSettlements"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettlements_rejectedBy_fkey";
ALTER TABLE "StakeholderCommissionSettlements"
  ADD CONSTRAINT "StakeholderCommissionSettlements_rejectedBy_fkey"
  FOREIGN KEY ("rejectedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX IF NOT EXISTS "StakeholderCommissionSettlements_country_role_idx"
  ON "StakeholderCommissionSettlements" ("countryId", "stakeholderRole", "status");

CREATE INDEX IF NOT EXISTS "StakeholderCommissionSettlements_beneficiary_idx"
  ON "StakeholderCommissionSettlements" ("beneficiaryUserId", "status", "initiatedAt" DESC);

ALTER TABLE "StakeholderCommissionSettlements" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stakeholder_commission_settlements_select" ON "StakeholderCommissionSettlements";
CREATE POLICY "stakeholder_commission_settlements_select" ON "StakeholderCommissionSettlements"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_country_role("countryId", ARRAY['admin_pays'])
    OR "beneficiaryUserId" = public.current_app_user_id()
    OR "initiatedBy" = public.current_app_user_id()
  );

DROP POLICY IF EXISTS "stakeholder_commission_settlements_write" ON "StakeholderCommissionSettlements";
CREATE POLICY "stakeholder_commission_settlements_write" ON "StakeholderCommissionSettlements"
  FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR "beneficiaryUserId" = public.current_app_user_id()
  )
  WITH CHECK (
    public.is_super_admin()
    OR "beneficiaryUserId" = public.current_app_user_id()
  );

CREATE OR REPLACE FUNCTION public._resolve_stakeholder_commission_country(p_country_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
BEGIN
  IF public.is_super_admin() THEN
    RETURN p_country_id;
  END IF;

  IF p_country_id IS NOT NULL AND public.has_country_role(p_country_id, ARRAY['admin_pays']) THEN
    RETURN p_country_id;
  END IF;

  SELECT ur."countryId"
  INTO v_country_id
  FROM "UserRoles" ur
  JOIN "Role" ro ON ro.id = ur."roleId"
  WHERE ur."userId" = public.current_app_user_id()
    AND ro.name = 'admin_pays'
    AND ur."countryId" IS NOT NULL
  ORDER BY ur."createdAt" DESC NULLS LAST
  LIMIT 1;

  RETURN v_country_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._booking_gateway_base_amount(
  p_nominal_amount double precision,
  p_company_id uuid
)
RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_calc jsonb;
  v_gateway double precision;
BEGIN
  IF p_nominal_amount IS NULL OR p_nominal_amount <= 0 OR p_company_id IS NULL THEN
    RETURN 0;
  END IF;

  BEGIN
    v_calc := public.calculate_traveler_payment_total(p_nominal_amount, p_company_id);
    v_gateway := COALESCE((v_calc->>'gatewayAmount')::double precision, 0);
    IF v_gateway <= 0 THEN
      v_gateway := COALESCE((v_calc->>'platformNetAmount')::double precision, p_nominal_amount);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_gateway := p_nominal_amount;
  END;

  RETURN COALESCE(v_gateway, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_base_amount(
  p_base_type text,
  p_gateway_amount double precision,
  p_total_amount double precision,
  p_platform_net_amount double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_base_type
    WHEN 'total_amount' THEN COALESCE(p_total_amount, p_gateway_amount)
    WHEN 'platform_net' THEN COALESCE(p_platform_net_amount, p_gateway_amount)
    ELSE p_gateway_amount
  END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_earned_rows(p_country_id uuid)
RETURNS TABLE(
  country_id uuid,
  stakeholder_role text,
  beneficiary_user_id uuid,
  beneficiary_name text,
  rate double precision,
  base_type text,
  earned_amount double precision,
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
  WITH settings AS (
    SELECT *
    FROM public.list_stakeholder_commission_settings(p_country_id)
    WHERE is_active = true AND rate > 0
  ),
  paid_bookings AS (
    SELECT
      rb.id AS booking_id,
      rb.price AS nominal_amount,
      rb."createdBy" AS seller_user_id,
      rb."saleChannel" AS sale_channel,
      c.id AS company_id,
      c."countryId" AS country_id,
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
      ON mvn."vendorUserId" = rb."createdBy"
      AND mvn."isActive" = true
    WHERE rb."type" = 'voyage'
      AND c."countryId" = p_country_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."sellerCommissionStatus", 'pending') <> 'cancelled'
  ),
  booking_amounts AS (
    SELECT
      pb.*,
      public._booking_gateway_base_amount(pb.nominal_amount, pb.company_id) AS gateway_amount
    FROM paid_bookings pb
  ),
  admin_users AS (
    SELECT ur."userId" AS user_id
    FROM "UserRoles" ur
    JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ro.name = 'admin_pays'
      AND ur."countryId" = p_country_id
  ),
  admin_count AS (
    SELECT GREATEST(COUNT(*)::double precision, 1) AS cnt FROM admin_users
  ),
  role_slices AS (
    SELECT
      ba.country_id,
      s.stakeholder_role,
      s.rate,
      s.base_type,
      ba.currency,
      ba.gateway_amount,
      CASE s.stakeholder_role
        WHEN 'platform' THEN NULL::uuid
        WHEN 'admin_pays' THEN au.user_id
        WHEN 'master' THEN ba.master_user_id
        WHEN 'seller' THEN CASE
          WHEN ba.sale_channel = 'seller_reservation'
            AND NOT public.is_company_role_user(ba.seller_user_id, ba.company_id)
          THEN ba.seller_user_id
          ELSE NULL
        END
        WHEN 'company' THEN ba.owner_user_id
        ELSE NULL
      END AS beneficiary_user_id,
      CASE s.stakeholder_role
        WHEN 'admin_pays' THEN (SELECT cnt FROM admin_count)
        ELSE 1::double precision
      END AS split_divisor
    FROM booking_amounts ba
    CROSS JOIN settings s
    LEFT JOIN admin_users au ON s.stakeholder_role = 'admin_pays'
    WHERE s.stakeholder_role IN ('platform', 'admin_pays', 'master', 'seller', 'company')
  )
  SELECT
    rs.country_id,
    rs.stakeholder_role,
    rs.beneficiary_user_id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '') AS beneficiary_name,
    MAX(rs.rate) AS rate,
    MAX(rs.base_type) AS base_type,
    ROUND(
      SUM(
        public._stakeholder_commission_base_amount(
          rs.base_type,
          rs.gateway_amount,
          rs.gateway_amount,
          rs.gateway_amount
        ) * rs.rate / 100.0 / rs.split_divisor
      )::numeric,
      2
    )::double precision AS earned_amount,
    MAX(rs.currency) AS currency
  FROM role_slices rs
  LEFT JOIN "Users" u ON u.id = rs.beneficiary_user_id
  WHERE
    rs.stakeholder_role = 'platform'
    OR rs.beneficiary_user_id IS NOT NULL
  GROUP BY rs.country_id, rs.stakeholder_role, rs.beneficiary_user_id, u."firstName", u."lastName"
  HAVING SUM(
    public._stakeholder_commission_base_amount(
      rs.base_type,
      rs.gateway_amount,
      rs.gateway_amount,
      rs.gateway_amount
    ) * rs.rate / 100.0 / rs.split_divisor
  ) > 0;
END;
$$;

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
    IF public.is_super_admin() THEN
      RAISE EXCEPTION 'Pays requis';
    END IF;
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
    OR EXISTS (
      SELECT 1 FROM public._stakeholder_commission_earned_rows(v_country_id) e
      WHERE e.beneficiary_user_id = v_user_id
    )
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  WITH earned AS (
    SELECT * FROM public._stakeholder_commission_earned_rows(v_country_id)
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
      e.country_id,
      e.stakeholder_role,
      e.beneficiary_user_id,
      e.beneficiary_name,
      e.rate,
      e.base_type,
      e.earned_amount,
      COALESCE(st.paid_amount, 0) AS paid_amount,
      COALESCE(st.pending_amount, 0) AS pending_amount,
      e.currency
    FROM earned e
    LEFT JOIN settlements st
      ON st.country_id = e.country_id
      AND st.stakeholder_role = e.stakeholder_role
      AND st.beneficiary_user_id IS NOT DISTINCT FROM e.beneficiary_user_id
  )
  SELECT
    m.country_id,
    c.name::text AS country_name,
    m.stakeholder_role,
    m.beneficiary_user_id,
    m.beneficiary_name,
    m.rate,
    m.base_type,
    m.earned_amount,
    m.paid_amount,
    m.pending_amount,
    GREATEST(m.earned_amount - m.paid_amount - m.pending_amount, 0)::double precision AS balance_due,
    m.currency
  FROM merged m
  JOIN "Countries" c ON c.id = m.country_id
  WHERE
    public.is_super_admin()
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
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
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Seul le super admin peut initier un paiement';
  END IF;

  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  IF p_stakeholder_role NOT IN ('platform', 'admin_pays', 'master', 'seller', 'company') THEN
    RAISE EXCEPTION 'Role stakeholder invalide';
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

  IF EXISTS (
    SELECT 1
    FROM "StakeholderCommissionSettlements" s
    WHERE s."countryId" = p_country_id
      AND s."stakeholderRole" = p_stakeholder_role
      AND s."beneficiaryUserId" IS NOT DISTINCT FROM p_beneficiary_user_id
      AND s.status = 'pending_confirmation'
  ) THEN
    RAISE EXCEPTION 'Un reglement est deja en attente de validation';
  END IF;

  v_user_id := public.current_app_user_id();

  INSERT INTO "StakeholderCommissionSettlements" (
    "countryId",
    "stakeholderRole",
    "beneficiaryUserId",
    "amount",
    "currency",
    "status",
    "earnedSnapshot",
    "note",
    "initiatedBy"
  ) VALUES (
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

  IF NOT (
    public.is_super_admin()
    OR v_settlement."beneficiaryUserId" = v_user_id
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants pour valider ce reglement';
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
    public.is_super_admin()
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

CREATE OR REPLACE FUNCTION public.cancel_stakeholder_commission_settlement(p_settlement_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Seul le super admin peut annuler un reglement';
  END IF;

  UPDATE "StakeholderCommissionSettlements"
  SET status = 'cancelled'
  WHERE id = p_settlement_id
    AND status = 'pending_confirmation';
END;
$$;

CREATE OR REPLACE FUNCTION public.list_stakeholder_commission_settlement_history(
  p_country_id uuid DEFAULT NULL,
  p_beneficiary_user_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  id uuid,
  country_id uuid,
  country_name text,
  stakeholder_role text,
  beneficiary_user_id uuid,
  beneficiary_name text,
  amount double precision,
  currency text,
  status text,
  earned_snapshot double precision,
  note text,
  initiated_by uuid,
  initiated_by_name text,
  initiated_at timestamptz,
  confirmed_by uuid,
  confirmed_by_name text,
  confirmed_at timestamptz,
  rejected_by uuid,
  rejected_by_name text,
  rejected_at timestamptz,
  rejection_reason text
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

  IF NOT (
    public.is_super_admin()
    OR (v_country_id IS NOT NULL AND public.has_country_role(v_country_id, ARRAY['admin_pays']))
    OR p_beneficiary_user_id IS NULL
    OR p_beneficiary_user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s."countryId" AS country_id,
    c.name::text AS country_name,
    s."stakeholderRole" AS stakeholder_role,
    s."beneficiaryUserId" AS beneficiary_user_id,
    NULLIF(TRIM(COALESCE(bu."firstName", '') || ' ' || COALESCE(bu."lastName", '')), '') AS beneficiary_name,
    s.amount,
    s.currency,
    s.status,
    s."earnedSnapshot" AS earned_snapshot,
    s.note,
    s."initiatedBy" AS initiated_by,
    NULLIF(TRIM(COALESCE(iu."firstName", '') || ' ' || COALESCE(iu."lastName", '')), '') AS initiated_by_name,
    s."initiatedAt" AS initiated_at,
    s."confirmedBy" AS confirmed_by,
    NULLIF(TRIM(COALESCE(cu."firstName", '') || ' ' || COALESCE(cu."lastName", '')), '') AS confirmed_by_name,
    s."confirmedAt" AS confirmed_at,
    s."rejectedBy" AS rejected_by,
    NULLIF(TRIM(COALESCE(ru."firstName", '') || ' ' || COALESCE(ru."lastName", '')), '') AS rejected_by_name,
    s."rejectedAt" AS rejected_at,
    s."rejectionReason" AS rejection_reason
  FROM "StakeholderCommissionSettlements" s
  JOIN "Countries" c ON c.id = s."countryId"
  LEFT JOIN "Users" bu ON bu.id = s."beneficiaryUserId"
  LEFT JOIN "Users" iu ON iu.id = s."initiatedBy"
  LEFT JOIN "Users" cu ON cu.id = s."confirmedBy"
  LEFT JOIN "Users" ru ON ru.id = s."rejectedBy"
  WHERE
    (v_country_id IS NULL OR s."countryId" = v_country_id)
    AND (p_beneficiary_user_id IS NULL OR s."beneficiaryUserId" IS NOT DISTINCT FROM p_beneficiary_user_id)
    AND (
      public.is_super_admin()
      OR public.has_country_role(s."countryId", ARRAY['admin_pays'])
      OR s."beneficiaryUserId" = v_user_id
      OR s."initiatedBy" = v_user_id
    )
  ORDER BY s."initiatedAt" DESC
  LIMIT GREATEST(COALESCE(p_limit, 50), 1);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_stakeholder_commission_settings(p_country_id uuid DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  scope text,
  country_id uuid,
  country_name text,
  stakeholder_role text,
  rate double precision,
  base_type text,
  sort_order integer,
  is_active boolean,
  source text,
  updated_at timestamptz,
  updated_by_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
BEGIN
  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);

  IF NOT (
    public.is_super_admin()
    OR (v_country_id IS NOT NULL AND public.has_country_role(v_country_id, ARRAY['admin_pays']))
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF public.is_super_admin() AND v_country_id IS NULL THEN
    RETURN QUERY
    WITH roles AS (
      SELECT unnest(public._stakeholder_commission_roles()) AS stakeholder_role
    ),
    global_rows AS (
      SELECT s.*
      FROM "StakeholderCommissionSettings" s
      WHERE s."scope" = 'global' AND s."isActive" = true
    )
    SELECT
      gr.id,
      'global'::text AS scope,
      NULL::uuid AS country_id,
      NULL::text AS country_name,
      r.stakeholder_role,
      COALESCE(gr.rate, 0::double precision) AS rate,
      COALESCE(gr."baseType", 'gateway_amount') AS base_type,
      public._stakeholder_role_sort(r.stakeholder_role) AS sort_order,
      COALESCE(gr."isActive", false) AS is_active,
      CASE WHEN gr.id IS NOT NULL THEN 'global_default' ELSE 'unset' END AS source,
      gr."updatedAt" AS updated_at,
      NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '') AS updated_by_name
    FROM roles r
    LEFT JOIN global_rows gr ON gr."stakeholderRole" = r.stakeholder_role
    LEFT JOIN "Users" u ON u.id = gr."updatedBy"
    ORDER BY sort_order;
    RETURN;
  END IF;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  RETURN QUERY
  WITH roles AS (
    SELECT unnest(public._stakeholder_commission_roles()) AS stakeholder_role
  ),
  global_rows AS (
    SELECT s.*
    FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = 'global' AND s."isActive" = true
  ),
  country_rows AS (
    SELECT s.*
    FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = 'country' AND s."isActive" = true AND s."countryId" = v_country_id
  )
  SELECT
    COALESCE(cr.id, gr.id) AS id,
    CASE WHEN cr.id IS NOT NULL THEN 'country'::text ELSE 'global'::text END AS scope,
    v_country_id AS country_id,
    c.name::text AS country_name,
    r.stakeholder_role,
    COALESCE(cr.rate, gr.rate, 0::double precision) AS rate,
    COALESCE(cr."baseType", gr."baseType", 'gateway_amount') AS base_type,
    public._stakeholder_role_sort(r.stakeholder_role) AS sort_order,
    COALESCE(cr."isActive", gr."isActive", false) AS is_active,
    CASE
      WHEN cr.id IS NOT NULL THEN 'country_override'
      WHEN gr.id IS NOT NULL THEN 'global_default'
      ELSE 'unset'
    END AS source,
    COALESCE(cr."updatedAt", gr."updatedAt") AS updated_at,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '') AS updated_by_name
  FROM roles r
  CROSS JOIN (SELECT id, name FROM "Countries" WHERE id = v_country_id) c
  LEFT JOIN country_rows cr ON cr."stakeholderRole" = r.stakeholder_role
  LEFT JOIN global_rows gr ON gr."stakeholderRole" = r.stakeholder_role
  LEFT JOIN "Users" u ON u.id = COALESCE(cr."updatedBy", gr."updatedBy")
  ORDER BY sort_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_balances(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.initiate_stakeholder_commission_settlement(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_stakeholder_commission_settlement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_stakeholder_commission_settlement(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_stakeholder_commission_settlement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_settlement_history(uuid, uuid, integer) TO authenticated;
