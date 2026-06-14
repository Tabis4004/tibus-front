-- 113 — Autorise recruiter/custom + scope company sur StakeholderCommissionSettings

ALTER TABLE "StakeholderCommissionSettings"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettings_role_check";

ALTER TABLE "StakeholderCommissionSettings"
  ADD CONSTRAINT "StakeholderCommissionSettings_role_check"
  CHECK (
    "stakeholderRole" = ANY (
      ARRAY['platform','admin_pays','master','seller','company','recruiter','custom']::text[]
    )
  );

ALTER TABLE "StakeholderCommissionSettings"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettings_scope_check";

ALTER TABLE "StakeholderCommissionSettings"
  ADD CONSTRAINT "StakeholderCommissionSettings_scope_check"
  CHECK (scope = ANY (ARRAY['global','country','company']::text[]));

ALTER TABLE "StakeholderCommissionSettings"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettings_target_check";

ALTER TABLE "StakeholderCommissionSettings"
  ADD CONSTRAINT "StakeholderCommissionSettings_target_check"
  CHECK (
    (scope = 'global' AND "countryId" IS NULL AND "companyId" IS NULL)
    OR (scope = 'country' AND "countryId" IS NOT NULL AND "companyId" IS NULL)
    OR (scope = 'company' AND "countryId" IS NOT NULL AND "companyId" IS NOT NULL)
  );

ALTER TABLE "StakeholderCommissionSettings"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionSettings_companyId_fkey";

ALTER TABLE "StakeholderCommissionSettings"
  ADD CONSTRAINT "StakeholderCommissionSettings_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies"(id) ON DELETE CASCADE DEFERRABLE;

-- Recruteur : bénéficiaire par défaut = recruitedByUserId de la compagnie si non fourni
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
  v_beneficiary uuid;
  v_company_country uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    IF p_scope <> 'country' AND NOT (
      p_scope = 'company'
      AND p_country_id IS NOT NULL
      AND public.has_country_role(p_country_id, ARRAY['admin_pays'])
    ) THEN
      RAISE EXCEPTION 'Droits insuffisants';
    END IF;
    IF p_scope = 'country'
      AND (p_country_id IS NULL OR NOT public.has_country_role(p_country_id, ARRAY['admin_pays']))
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

  IF p_scope = 'company' AND p_stakeholder_role = 'recruiter' THEN
    SELECT c."countryId", c."recruitedByUserId"
    INTO v_company_country, v_beneficiary
    FROM "Companies" c
    WHERE c.id = p_company_id;

    IF v_company_country IS NULL THEN
      RAISE EXCEPTION 'Compagnie introuvable';
    END IF;
    IF v_company_country IS DISTINCT FROM p_country_id THEN
      RAISE EXCEPTION 'La compagnie n''appartient pas au pays selectionne';
    END IF;

    v_beneficiary := COALESCE(p_beneficiary_user_id, v_beneficiary);
  ELSE
    v_beneficiary := p_beneficiary_user_id;
  END IF;

  IF p_stakeholder_role = 'custom' AND COALESCE(p_rate, 0) > 0
    AND (p_label IS NULL OR v_beneficiary IS NULL) THEN
    RAISE EXCEPTION 'Label et beneficiaire requis pour un stakeholder custom actif';
  END IF;
  IF p_stakeholder_role <> 'platform'
    AND p_stakeholder_role <> 'custom'
    AND COALESCE(p_rate, 0) > 0
    AND v_beneficiary IS NULL
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
          AND s."beneficiaryUserId" IS NOT DISTINCT FROM v_beneficiary
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
      "beneficiaryUserId" = v_beneficiary,
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
    v_beneficiary,
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
      "beneficiaryUserId" = v_beneficiary,
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    WHERE id = v_id;

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_stakeholder_commission_setting(text, uuid, text, double precision, text, boolean, uuid, text, uuid, uuid) TO authenticated;
