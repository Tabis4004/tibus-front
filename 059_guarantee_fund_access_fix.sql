-- 059: accès fond de garantie — aligner sur has_company_role (owner / comptable par auth.uid).
-- À exécuter après 028 et 029.

CREATE OR REPLACE FUNCTION public.get_company_guarantee_fund(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance double precision;
  v_currency text;
  v_allow_negative boolean;
  v_recent jsonb;
  v_pending_count integer;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR public.is_company_role_user(public.current_app_user_id(), p_company_id)
    OR public.can_manage_guarantee_deposit(p_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces fond de garantie refuse';
  END IF;

  SELECT c."guaranteeBalance", COALESCE(ct.currency, 'XOF'), COALESCE(c."guaranteeAllowNegative", false)
  INTO v_balance, v_currency, v_allow_negative
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  SELECT COUNT(*)::integer INTO v_pending_count
  FROM "CompanyGuaranteeDeposit" d
  WHERE d."companyId" = p_company_id AND d.status = 'pending';

  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t."createdAt" DESC), '[]'::jsonb)
  INTO v_recent
  FROM (
    SELECT
      l.id,
      l."createdAt",
      l.type,
      l.amount,
      l."balanceAfter",
      l.reference,
      l."bookingId",
      l.note,
      NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), '') AS "authorName"
    FROM "CompanyGuaranteeLedger" l
    LEFT JOIN "Users" u ON u.id = l."createdBy"
    WHERE l."companyId" = p_company_id
    ORDER BY l."createdAt" DESC
    LIMIT 20
  ) t;

  RETURN jsonb_build_object(
    'companyId', p_company_id,
    'balance', v_balance,
    'currency', v_currency,
    'allowNegative', v_allow_negative,
    'pendingDeposits', v_pending_count,
    'recent', v_recent
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_guarantee_fund(uuid) TO authenticated;
