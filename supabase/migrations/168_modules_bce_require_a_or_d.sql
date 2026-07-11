-- Le module D (colis autonomes) est indépendant mais réutilise les briques
-- partagées de la compagnie (gares, caisse, équipe, journal, guichet) : les
-- modules B, C et E deviennent activables avec la billetterie (A) OU les
-- colis (D) — plus seulement A. Évite qu'une compagnie « colis seul » perde
-- gares, comptabilité et rapports.

-- 1. Vérification module : B/C/E valides si A OU D actif.
CREATE OR REPLACE FUNCTION public.company_has_module(p_company_id uuid, p_module text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public."CompanyFeatureModules"%ROWTYPE;
  v_enabled boolean;
  v_module text := upper(trim(p_module));
BEGIN
  IF p_company_id IS NULL OR v_module = '' THEN
    RETURN false;
  END IF;

  SELECT * INTO v_row
  FROM public."CompanyFeatureModules"
  WHERE "companyId" = p_company_id;

  IF NOT FOUND THEN
  -- Rétrocompatibilité : compagnies sans ligne = pack quasi complet hors TPE.
    RETURN v_module <> 'F';
  END IF;

  v_enabled := public._company_module_flag(v_row, v_module);
  IF NOT v_enabled THEN
    RETURN false;
  END IF;

  IF v_module IN ('B', 'C', 'E') AND NOT (v_row."moduleA" OR v_row."moduleD") THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$function$;

-- 2. Sauvegarde admin : même règle (A OU D requis pour B/C/E).
CREATE OR REPLACE FUNCTION public.set_company_feature_modules(
  p_company_id uuid,
  p_module_a boolean,
  p_module_b boolean,
  p_module_c boolean,
  p_module_d boolean,
  p_module_e boolean,
  p_module_f boolean,
  p_module_d_colis_sms_config boolean DEFAULT NULL::boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  IF NOT (v_a OR v_d) AND (v_b OR v_c OR v_e) THEN
    RAISE EXCEPTION 'Le module A (billetterie) ou D (colis) est requis pour B, C ou E';
  END IF;

  IF v_b AND NOT (v_a OR v_d) THEN v_b := false; END IF;
  IF v_c AND NOT (v_a OR v_d) THEN v_c := false; END IF;
  IF v_e AND NOT (v_a OR v_d) THEN v_e := false; END IF;

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

  IF NOT v_d_sms THEN
    UPDATE public."Companies"
    SET
      sms_on_enregistre = false,
      sms_on_charge = false,
      sms_on_arrive = false,
      sms_on_livre = false
    WHERE id = p_company_id;
  END IF;

  RETURN public.get_company_feature_modules(p_company_id);
END;
$function$;
