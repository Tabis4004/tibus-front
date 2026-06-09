-- 063 — Répartition des commissions stakeholders sur le montant passerelle
-- Exécuter après 025_fedapay_fee_on_top.sql

CREATE TABLE IF NOT EXISTS "StakeholderCommissionSettings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "scope" text NOT NULL,
  "countryId" uuid,
  "stakeholderRole" text NOT NULL,
  "rate" double precision NOT NULL DEFAULT 0,
  "baseType" text NOT NULL DEFAULT 'gateway_amount',
  "sortOrder" integer NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid,
  CONSTRAINT "StakeholderCommissionSettings_scope_check"
    CHECK ("scope" IN ('global', 'country')),
  CONSTRAINT "StakeholderCommissionSettings_role_check"
    CHECK ("stakeholderRole" IN ('platform', 'admin_pays', 'master', 'seller', 'company')),
  CONSTRAINT "StakeholderCommissionSettings_rate_check"
    CHECK ("rate" >= 0 AND "rate" <= 100),
  CONSTRAINT "StakeholderCommissionSettings_base_check"
    CHECK ("baseType" IN ('gateway_amount', 'total_amount', 'platform_net')),
  CONSTRAINT "StakeholderCommissionSettings_target_check"
    CHECK (
      ("scope" = 'global' AND "countryId" IS NULL)
      OR ("scope" = 'country' AND "countryId" IS NOT NULL)
    )
);

ALTER TABLE "StakeholderCommissionSettings"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettings_countryId_fkey";
ALTER TABLE "StakeholderCommissionSettings"
  ADD CONSTRAINT "StakeholderCommissionSettings_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "StakeholderCommissionSettings"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettings_updatedBy_fkey";
ALTER TABLE "StakeholderCommissionSettings"
  ADD CONSTRAINT "StakeholderCommissionSettings_updatedBy_fkey"
  FOREIGN KEY ("updatedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

CREATE UNIQUE INDEX IF NOT EXISTS "StakeholderCommissionSettings_global_role_key"
  ON "StakeholderCommissionSettings" ("stakeholderRole")
  WHERE "scope" = 'global' AND "isActive" = true;

CREATE UNIQUE INDEX IF NOT EXISTS "StakeholderCommissionSettings_country_role_key"
  ON "StakeholderCommissionSettings" ("countryId", "stakeholderRole")
  WHERE "scope" = 'country' AND "isActive" = true;

ALTER TABLE "StakeholderCommissionSettings" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stakeholder_commission_settings_select" ON "StakeholderCommissionSettings";
CREATE POLICY "stakeholder_commission_settings_select" ON "StakeholderCommissionSettings"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (
      "scope" = 'country'
      AND public.has_country_role("countryId", ARRAY['admin_pays'])
    )
    OR "scope" = 'global'
  );

DROP POLICY IF EXISTS "stakeholder_commission_settings_write" ON "StakeholderCommissionSettings";
CREATE POLICY "stakeholder_commission_settings_write" ON "StakeholderCommissionSettings"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE OR REPLACE FUNCTION public._stakeholder_commission_roles()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY['platform', 'admin_pays', 'master', 'seller', 'company']::text[];
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_role_sort(p_role text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_role
    WHEN 'platform' THEN 1
    WHEN 'admin_pays' THEN 2
    WHEN 'master' THEN 3
    WHEN 'seller' THEN 4
    WHEN 'company' THEN 5
    ELSE 99
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
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (p_country_id IS NOT NULL AND public.has_country_role(p_country_id, ARRAY['admin_pays']))
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  WITH target_countries AS (
    SELECT c.id, c.name::text AS name
    FROM "Countries" c
    WHERE
      (p_country_id IS NULL AND public.is_super_admin())
      OR c.id = p_country_id
  ),
  roles AS (
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
    WHERE s."scope" = 'country' AND s."isActive" = true
  )
  SELECT
    COALESCE(cr.id, gr.id) AS id,
    CASE WHEN cr.id IS NOT NULL THEN 'country'::text ELSE 'global'::text END AS scope,
    tc.id AS country_id,
    tc.name AS country_name,
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
    NULLIF(
      TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')),
      ''
    ) AS updated_by_name
  FROM target_countries tc
  CROSS JOIN roles r
  LEFT JOIN country_rows cr
    ON cr."countryId" = tc.id AND cr."stakeholderRole" = r.stakeholder_role
  LEFT JOIN global_rows gr ON gr."stakeholderRole" = r.stakeholder_role
  LEFT JOIN "Users" u ON u.id = COALESCE(cr."updatedBy", gr."updatedBy")
  ORDER BY tc.name, sort_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_stakeholder_commission_setting(
  p_scope text,
  p_country_id uuid,
  p_stakeholder_role text,
  p_rate double precision,
  p_base_type text DEFAULT 'gateway_amount',
  p_is_active boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  IF p_scope NOT IN ('global', 'country') THEN
    RAISE EXCEPTION 'Scope invalide';
  END IF;

  IF p_stakeholder_role NOT IN ('platform', 'admin_pays', 'master', 'seller', 'company') THEN
    RAISE EXCEPTION 'Role stakeholder invalide';
  END IF;

  IF p_rate IS NULL OR p_rate < 0 OR p_rate > 100 THEN
    RAISE EXCEPTION 'Taux invalide (0-100)';
  END IF;

  IF p_base_type NOT IN ('gateway_amount', 'total_amount', 'platform_net') THEN
    RAISE EXCEPTION 'Base invalide';
  END IF;

  IF p_scope = 'global' AND p_country_id IS NOT NULL THEN
    RAISE EXCEPTION 'Scope global sans pays';
  END IF;

  IF p_scope = 'country' AND p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis pour scope country';
  END IF;

  UPDATE "StakeholderCommissionSettings"
  SET "isActive" = false, "updatedAt" = now(), "updatedBy" = v_user_id
  WHERE "isActive" = true
    AND "scope" = p_scope
    AND "stakeholderRole" = p_stakeholder_role
    AND (
      (p_scope = 'global' AND "countryId" IS NULL)
      OR (p_scope = 'country' AND "countryId" = p_country_id)
    );

  INSERT INTO "StakeholderCommissionSettings" (
    "scope", "countryId", "stakeholderRole", "rate", "baseType", "sortOrder", "isActive", "updatedBy"
  ) VALUES (
    p_scope,
    p_country_id,
    p_stakeholder_role,
    p_rate,
    p_base_type,
    public._stakeholder_role_sort(p_stakeholder_role),
    COALESCE(p_is_active, true),
    v_user_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_stakeholder_commission_setting(p_setting_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  UPDATE "StakeholderCommissionSettings"
  SET "isActive" = false, "updatedAt" = now(), "updatedBy" = public.current_app_user_id()
  WHERE id = p_setting_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.preview_stakeholder_commission_attribution(
  p_gateway_amount double precision,
  p_total_amount double precision DEFAULT NULL,
  p_platform_net_amount double precision DEFAULT NULL,
  p_country_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_base double precision;
  v_amount double precision;
  v_total_rate double precision := 0;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF p_gateway_amount IS NULL OR p_gateway_amount < 0 THEN
    RAISE EXCEPTION 'Montant passerelle invalide';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR (p_country_id IS NOT NULL AND public.has_country_role(p_country_id, ARRAY['admin_pays']))
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  FOR v_row IN
    SELECT *
    FROM public.list_stakeholder_commission_settings(p_country_id)
    WHERE is_active = true OR rate > 0 OR source <> 'unset'
  LOOP
    v_base := CASE v_row.base_type
      WHEN 'total_amount' THEN COALESCE(p_total_amount, p_gateway_amount)
      WHEN 'platform_net' THEN COALESCE(p_platform_net_amount, p_gateway_amount)
      ELSE p_gateway_amount
    END;

    v_amount := ROUND((v_base * v_row.rate / 100.0)::numeric, 2);
    v_total_rate := v_total_rate + COALESCE(v_row.rate, 0);

    v_items := v_items || jsonb_build_array(
      jsonb_build_object(
        'stakeholderRole', v_row.stakeholder_role,
        'rate', v_row.rate,
        'baseType', v_row.base_type,
        'baseAmount', v_base,
        'amount', v_amount,
        'source', v_row.source
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'gatewayAmount', p_gateway_amount,
    'totalAmount', p_total_amount,
    'platformNetAmount', p_platform_net_amount,
    'countryId', p_country_id,
    'totalRatePercent', v_total_rate,
    'items', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_stakeholder_commission_setting(text, uuid, text, double precision, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_stakeholder_commission_setting(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_stakeholder_commission_attribution(double precision, double precision, double precision, uuid) TO authenticated;
