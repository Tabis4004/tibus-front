-- 066 — Répartition stakeholders sur la commission plateforme (M×X% par ligne ReservationBus)
-- Exclut la compagnie (owner) et tout utilisateur lié à une compagnie sur la vente.
-- Exécuter après 065_stakeholder_commission_load_fix.sql

ALTER TABLE "StakeholderCommissionSettings"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettings_base_check";
ALTER TABLE "StakeholderCommissionSettings"
  ADD CONSTRAINT "StakeholderCommissionSettings_base_check"
    CHECK ("baseType" IN ('platform_commission', 'gateway_amount', 'total_amount', 'platform_net'));

ALTER TABLE "StakeholderCommissionSettings"
  ALTER COLUMN "baseType" SET DEFAULT 'platform_commission';

UPDATE "StakeholderCommissionSettings"
SET "baseType" = 'platform_commission', "updatedAt" = now()
WHERE "isActive" = true AND "baseType" IS DISTINCT FROM 'platform_commission';

CREATE OR REPLACE FUNCTION public._stakeholder_commission_roles()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY['platform', 'admin_pays', 'master', 'seller']::text[];
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_pool_amount(
  p_nominal_amount double precision,
  p_company_id uuid
)
RETURNS double precision
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ROUND(
    (
      COALESCE(p_nominal_amount, 0)
      * COALESCE(resolved.rate, 0)
      / 100.0
    )::numeric,
    2
  )::double precision
  FROM public.resolve_seller_commission_setting(p_company_id) resolved;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_base_amount(
  p_base_type text,
  p_platform_commission_amount double precision,
  p_gateway_amount double precision,
  p_total_amount double precision,
  p_platform_net_amount double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_base_type
    WHEN 'platform_commission' THEN COALESCE(p_platform_commission_amount, 0)
    WHEN 'total_amount' THEN COALESCE(p_total_amount, p_gateway_amount)
    WHEN 'platform_net' THEN COALESCE(p_platform_net_amount, p_gateway_amount)
    ELSE p_gateway_amount
  END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_effective_settings(p_country_id uuid)
RETURNS TABLE(
  stakeholder_role text,
  rate double precision,
  base_type text,
  is_active boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_country_id IS NULL THEN
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
      r.stakeholder_role,
      COALESCE(gr.rate, 0::double precision) AS rate,
      COALESCE(gr."baseType", 'platform_commission') AS base_type,
      COALESCE(gr."isActive", false) AS is_active
    FROM roles r
    LEFT JOIN global_rows gr ON gr."stakeholderRole" = r.stakeholder_role;
    RETURN;
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
    WHERE s."scope" = 'country' AND s."isActive" = true AND s."countryId" = p_country_id
  )
  SELECT
    r.stakeholder_role,
    COALESCE(cr.rate, gr.rate, 0::double precision) AS rate,
    COALESCE(cr."baseType", gr."baseType", 'platform_commission') AS base_type,
    COALESCE(cr."isActive", gr."isActive", false) AS is_active
  FROM roles r
  LEFT JOIN country_rows cr ON cr."stakeholderRole" = r.stakeholder_role
  LEFT JOIN global_rows gr ON gr."stakeholderRole" = r.stakeholder_role;
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
    FROM public._stakeholder_commission_effective_settings(p_country_id)
    WHERE is_active = true AND rate > 0
  ),
  paid_bookings AS (
    SELECT
      rb.price AS nominal_amount,
      rb."createdBy" AS seller_user_id,
      c.id AS company_id,
      c."countryId" AS country_id,
      COALESCE(country.currency, 'XOF')::text AS currency,
      public._stakeholder_commission_pool_amount(rb.price, c.id) AS platform_commission_amount,
      mvn."masterUserId" AS master_user_id
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    LEFT JOIN "MasterVendorNetwork" mvn
      ON mvn."vendorUserId" = rb."createdBy"
      AND mvn."isActive" = true
    WHERE rb."type" = 'voyage'
      AND c."countryId" = p_country_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."sellerCommissionStatus", 'pending') <> 'cancelled'
  ),
  eligible_bookings AS (
    SELECT *
    FROM paid_bookings pb
    WHERE pb.platform_commission_amount > 0
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
      ba.platform_commission_amount,
      CASE s.stakeholder_role
        WHEN 'platform' THEN NULL::uuid
        WHEN 'admin_pays' THEN au.user_id
        WHEN 'master' THEN CASE
          WHEN ba.master_user_id IS NOT NULL
            AND NOT public.is_company_role_user(ba.master_user_id, ba.company_id)
          THEN ba.master_user_id
          ELSE NULL
        END
        WHEN 'seller' THEN CASE
          WHEN ba.seller_user_id IS NOT NULL
            AND NOT public.is_company_role_user(ba.seller_user_id, ba.company_id)
          THEN ba.seller_user_id
          ELSE NULL
        END
        ELSE NULL
      END AS beneficiary_user_id,
      CASE s.stakeholder_role
        WHEN 'admin_pays' THEN (SELECT cnt FROM admin_count)
        ELSE 1::double precision
      END AS split_divisor
    FROM eligible_bookings ba
    CROSS JOIN settings s
    LEFT JOIN admin_users au ON s.stakeholder_role = 'admin_pays'
    WHERE s.stakeholder_role IN ('platform', 'admin_pays', 'master', 'seller')
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
          rs.platform_commission_amount,
          rs.platform_commission_amount,
          rs.platform_commission_amount,
          rs.platform_commission_amount
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
      rs.platform_commission_amount,
      rs.platform_commission_amount,
      rs.platform_commission_amount,
      rs.platform_commission_amount
    ) * rs.rate / 100.0 / rs.split_divisor
  ) > 0;
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
    COALESCE(cr."baseType", gr."baseType", 'platform_commission') AS base_type,
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
  p_base_type text DEFAULT 'platform_commission',
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

  IF p_stakeholder_role NOT IN ('platform', 'admin_pays', 'master', 'seller') THEN
    RAISE EXCEPTION 'Role stakeholder invalide';
  END IF;

  IF p_rate IS NULL OR p_rate < 0 OR p_rate > 100 THEN
    RAISE EXCEPTION 'Taux invalide (0-100)';
  END IF;

  IF p_base_type NOT IN ('platform_commission', 'gateway_amount', 'total_amount', 'platform_net') THEN
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
    COALESCE(p_base_type, 'platform_commission'),
    public._stakeholder_role_sort(p_stakeholder_role),
    COALESCE(p_is_active, true),
    v_user_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.preview_stakeholder_commission_attribution(
  p_platform_commission_amount double precision,
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
  IF p_platform_commission_amount IS NULL OR p_platform_commission_amount < 0 THEN
    RAISE EXCEPTION 'Commission plateforme invalide';
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
    WHERE stakeholder_role <> 'company'
      AND (is_active = true OR rate > 0 OR source <> 'unset')
  LOOP
    v_base := public._stakeholder_commission_base_amount(
      COALESCE(v_row.base_type, 'platform_commission'),
      p_platform_commission_amount,
      p_platform_commission_amount,
      p_platform_commission_amount,
      p_platform_commission_amount
    );

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
    'platformCommissionAmount', p_platform_commission_amount,
    'countryId', p_country_id,
    'totalRatePercent', v_total_rate,
    'items', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public._stakeholder_commission_pool_amount(double precision, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_stakeholder_commission_attribution(double precision, uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.preview_stakeholder_commission_attribution(double precision, double precision, double precision, uuid);
DROP FUNCTION IF EXISTS public._stakeholder_commission_base_amount(text, double precision, double precision, double precision);
