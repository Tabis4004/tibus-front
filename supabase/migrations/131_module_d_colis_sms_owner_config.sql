-- Option admin : autoriser l'owner à configurer les SMS colis (module D).

ALTER TABLE public."CompanyFeatureModules"
  ADD COLUMN IF NOT EXISTS "moduleDColisSmsConfig" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.get_company_feature_modules(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."CompanyFeatureModules"%ROWTYPE;
  v_country_id uuid;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id requis';
  END IF;

  SELECT c."countryId" INTO v_country_id
  FROM public."Companies" c
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT * INTO v_row
  FROM public."CompanyFeatureModules"
  WHERE "companyId" = p_company_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'companyId', p_company_id,
      'moduleA', true,
      'moduleB', true,
      'moduleC', true,
      'moduleD', true,
      'moduleE', true,
      'moduleF', false,
      'moduleDColisSmsConfig', false,
      'updatedAt', now()
    );
  END IF;

  RETURN jsonb_build_object(
    'companyId', v_row."companyId",
    'moduleA', v_row."moduleA",
    'moduleB', v_row."moduleB",
    'moduleC', v_row."moduleC",
    'moduleD', v_row."moduleD",
    'moduleE', v_row."moduleE",
    'moduleF', v_row."moduleF",
    'moduleDColisSmsConfig', COALESCE(v_row."moduleDColisSmsConfig", false) AND v_row."moduleD",
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_company_feature_modules(
  p_company_id uuid,
  p_module_a boolean,
  p_module_b boolean,
  p_module_c boolean,
  p_module_d boolean,
  p_module_e boolean,
  p_module_f boolean,
  p_module_d_colis_sms_config boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
  v_a boolean := COALESCE(p_module_a, true);
  v_b boolean := COALESCE(p_module_b, false);
  v_c boolean := COALESCE(p_module_c, false);
  v_d boolean := COALESCE(p_module_d, false);
  v_e boolean := COALESCE(p_module_e, false);
  v_f boolean := COALESCE(p_module_f, false);
  v_d_sms boolean;
  v_existing_sms boolean := false;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id requis';
  END IF;

  SELECT c."countryId" INTO v_country_id
  FROM public."Companies" c
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF NOT v_a AND (v_b OR v_c OR v_e) THEN
    RAISE EXCEPTION 'Le module A (billetterie) est requis pour B, C ou E';
  END IF;

  IF v_b AND NOT v_a THEN v_b := false; END IF;
  IF v_c AND NOT v_a THEN v_c := false; END IF;
  IF v_e AND NOT v_a THEN v_e := false; END IF;

  SELECT COALESCE(m."moduleDColisSmsConfig", false)
  INTO v_existing_sms
  FROM public."CompanyFeatureModules" m
  WHERE m."companyId" = p_company_id;

  IF p_module_d_colis_sms_config IS NULL THEN
    v_d_sms := COALESCE(v_existing_sms, false);
  ELSE
    v_d_sms := COALESCE(p_module_d_colis_sms_config, false);
  END IF;

  IF NOT v_d THEN
    v_d_sms := false;
  END IF;

  INSERT INTO public."CompanyFeatureModules" (
    "companyId",
    "moduleA",
    "moduleB",
    "moduleC",
    "moduleD",
    "moduleE",
    "moduleF",
    "moduleDColisSmsConfig",
    "updatedBy"
  ) VALUES (
    p_company_id,
    v_a,
    v_b,
    v_c,
    v_d,
    v_e,
    v_f,
    v_d_sms,
    public.current_app_user_id()
  )
  ON CONFLICT ("companyId") DO UPDATE SET
    "moduleA" = EXCLUDED."moduleA",
    "moduleB" = EXCLUDED."moduleB",
    "moduleC" = EXCLUDED."moduleC",
    "moduleD" = EXCLUDED."moduleD",
    "moduleE" = EXCLUDED."moduleE",
    "moduleF" = EXCLUDED."moduleF",
    "moduleDColisSmsConfig" = EXCLUDED."moduleDColisSmsConfig",
    "updatedAt" = now(),
    "updatedBy" = EXCLUDED."updatedBy";

  RETURN public.get_company_feature_modules(p_company_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.company_colis_sms_owner_config_enabled(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(m."moduleD", false)
    AND COALESCE(m."moduleDColisSmsConfig", false)
  FROM public."CompanyFeatureModules" m
  WHERE m."companyId" = p_company_id;
$$;

CREATE OR REPLACE FUNCTION public.get_company_colis_settings(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_row "Companies"%ROWTYPE;
  v_sms_config_allowed boolean := false;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT * INTO v_row FROM "Companies" WHERE id = p_company_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  SELECT COALESCE(public.company_colis_sms_owner_config_enabled(p_company_id), false)
  INTO v_sms_config_allowed;

  RETURN jsonb_build_object(
    'companyId', v_row.id,
    'colisAutonomeEnabled', COALESCE(v_row.colis_autonome_enabled, false),
    'colisSmsConfigEnabled', v_sms_config_allowed,
    'smsOnEnregistre', COALESCE(v_row.sms_on_enregistre, false),
    'smsOnCharge', COALESCE(v_row.sms_on_charge, false),
    'smsOnArrive', COALESCE(v_row.sms_on_arrive, false),
    'smsOnLivre', COALESCE(v_row.sms_on_livre, false)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.update_company_colis_sms_settings(
  p_company_id uuid,
  p_sms_on_enregistre boolean,
  p_sms_on_charge boolean,
  p_sms_on_arrive boolean,
  p_sms_on_livre boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN
    RAISE EXCEPTION 'Module colis autonome non active pour cette compagnie';
  END IF;
  IF NOT public.company_colis_sms_owner_config_enabled(p_company_id)
     AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Configuration SMS colis non autorisee pour cette compagnie';
  END IF;

  UPDATE "Companies"
  SET
    sms_on_enregistre = COALESCE(p_sms_on_enregistre, false),
    sms_on_charge = COALESCE(p_sms_on_charge, false),
    sms_on_arrive = COALESCE(p_sms_on_arrive, false),
    sms_on_livre = COALESCE(p_sms_on_livre, false)
  WHERE id = p_company_id;

  RETURN public.get_company_colis_settings(p_company_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_company_feature_modules(
  uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.company_colis_sms_owner_config_enabled(uuid) TO authenticated;
