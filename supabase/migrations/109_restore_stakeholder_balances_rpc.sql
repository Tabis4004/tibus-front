-- 109 — Restaure list_stakeholder_commission_balances (supprimée par erreur en fin de 108)

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

GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_balances(uuid) TO authenticated;
