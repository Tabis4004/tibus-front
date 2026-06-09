-- 065 — Fix chargement soldes stakeholders (éviter nested RPC + gateway lourde)
-- Exécuter après 064_stakeholder_commission_ledger.sql

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
      COALESCE(gr."baseType", 'gateway_amount') AS base_type,
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
    COALESCE(cr."baseType", gr."baseType", 'gateway_amount') AS base_type,
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
      rb."saleChannel" AS sale_channel,
      c.id AS company_id,
      c."countryId" AS country_id,
      COALESCE(country.currency, 'XOF')::text AS currency,
      COALESCE(p.amount, rb.price, 0::double precision) AS gateway_amount,
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
    FROM paid_bookings ba
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

GRANT EXECUTE ON FUNCTION public._stakeholder_commission_effective_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_balances(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_settlement_history(uuid, uuid, integer) TO authenticated;
