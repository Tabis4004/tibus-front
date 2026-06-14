-- 112 — Liste utilisateurs stakeholders par pays + accès admin pays aux taux

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
  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(p_country_id, ARRAY['admin_pays'])
  ) THEN
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
    COALESCE(array_agg(DISTINCT r.name::text) FILTER (WHERE r.name IS NOT NULL), ARRAY[]::text[])
  FROM "Users" u
  JOIN "UserRoles" ur ON ur."userId" = u.id
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."countryId" = p_country_id
     OR u."countryId" = p_country_id
     OR EXISTS (
       SELECT 1
       FROM "Companies" c
       WHERE c."countryId" = p_country_id
         AND c."recruitedByUserId" = u.id
     )
     OR EXISTS (
       SELECT 1
       FROM "UserRoles" urc
       JOIN "Companies" c ON c.id = urc."companyId"
       WHERE urc."userId" = u.id
         AND c."countryId" = p_country_id
     )
  GROUP BY u.id, u."firstName", u."lastName", u.email
  ORDER BY 2 NULLS LAST, u.email;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_stakeholder_commission_settings(p_country_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(
  id uuid,
  scope text,
  country_id uuid,
  country_name text,
  company_id uuid,
  company_name text,
  stakeholder_role text,
  label text,
  beneficiary_user_id uuid,
  beneficiary_name text,
  rate double precision,
  base_type text,
  sort_order integer,
  is_active boolean,
  source text,
  updated_at timestamp with time zone,
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
    OR (
      p_country_id IS NOT NULL
      AND public.has_country_role(p_country_id, ARRAY['admin_pays'])
    )
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s."scope",
    s."countryId",
    co.name::text,
    s."companyId",
    comp.name::text,
    s."stakeholderRole",
    s.label,
    s."beneficiaryUserId",
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), ''),
    s.rate,
    COALESCE(s."baseType", 'platform_commission'),
    COALESCE(s."sortOrder", public._stakeholder_role_sort(s."stakeholderRole")),
    s."isActive",
    s."scope",
    s."updatedAt",
    NULLIF(TRIM(COALESCE(upd."firstName", '') || ' ' || COALESCE(upd."lastName", '')), '')
  FROM "StakeholderCommissionSettings" s
  LEFT JOIN "Countries" co ON co.id = s."countryId"
  LEFT JOIN "Companies" comp ON comp.id = s."companyId"
  LEFT JOIN "Users" u ON u.id = s."beneficiaryUserId"
  LEFT JOIN "Users" upd ON upd.id = s."updatedBy"
  WHERE (
    public.is_super_admin()
    OR (
      s."scope" = 'country'
      AND s."countryId" = p_country_id
    )
  )
  AND (
    p_country_id IS NULL
    OR s."countryId" = p_country_id
    OR s."scope" = 'global'
  )
  ORDER BY s."scope", co.name NULLS FIRST, comp.name NULLS FIRST, 12, s."stakeholderRole", s.label NULLS FIRST;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_stakeholder_commission_setting(
  p_scope text,
  p_country_id uuid DEFAULT NULL::uuid,
  p_stakeholder_role text DEFAULT 'platform'::text,
  p_rate double precision DEFAULT 0,
  p_base_type text DEFAULT 'platform_commission'::text,
  p_is_active boolean DEFAULT true,
  p_company_id uuid DEFAULT NULL::uuid,
  p_label text DEFAULT NULL::text,
  p_beneficiary_user_id uuid DEFAULT NULL::uuid,
  p_setting_id uuid DEFAULT NULL::uuid
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
    IF p_scope <> 'country'
      OR p_country_id IS NULL
      OR NOT public.has_country_role(p_country_id, ARRAY['admin_pays'])
    THEN
      RAISE EXCEPTION 'Droits insuffisants';
    END IF;
  END IF;

  IF p_scope NOT IN ('global', 'country', 'company') THEN
    RAISE EXCEPTION 'Scope invalide';
  END IF;
  IF COALESCE(p_rate, 0) < 0 THEN
    RAISE EXCEPTION 'Le taux doit etre superieur ou egal a 0';
  END IF;
  IF p_scope = 'country' AND p_country_id IS NULL THEN
    RAISE EXCEPTION 'countryId requis';
  END IF;
  IF p_scope = 'company' AND (p_company_id IS NULL OR p_country_id IS NULL) THEN
    RAISE EXCEPTION 'companyId et countryId requis';
  END IF;
  IF p_stakeholder_role = 'custom' AND COALESCE(p_rate, 0) > 0
    AND (p_label IS NULL OR p_beneficiary_user_id IS NULL) THEN
    RAISE EXCEPTION 'Label et beneficiaire requis pour un stakeholder custom actif';
  END IF;
  IF p_stakeholder_role <> 'platform'
    AND p_stakeholder_role <> 'custom'
    AND COALESCE(p_rate, 0) > 0
    AND p_beneficiary_user_id IS NULL
  THEN
    RAISE EXCEPTION 'Utilisateur beneficiaire requis lorsque le taux est superieur a 0';
  END IF;

  v_user_id := public.current_app_user_id();

  IF COALESCE(p_rate, 0) <= 0 AND p_stakeholder_role <> 'custom' THEN
    DELETE FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = p_scope
      AND s."stakeholderRole" = p_stakeholder_role
      AND (p_scope = 'global' OR s."countryId" IS NOT DISTINCT FROM p_country_id)
      AND (p_scope <> 'company' OR s."companyId" IS NOT DISTINCT FROM p_company_id);
    RETURN NULL;
  END IF;

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

GRANT EXECUTE ON FUNCTION public.list_stakeholder_country_users(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_stakeholder_commission_setting(text, uuid, text, double precision, text, boolean, uuid, text, uuid, uuid) TO authenticated;
