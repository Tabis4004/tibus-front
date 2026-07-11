-- SMS colis facturés à l'étape : le super admin (ou admin pays) choisit,
-- selon l'offre payée par la compagnie, QUELLES étapes de notification SMS
-- l'owner a le droit d'activer (enregistrement, chargement, arrivée,
-- remise) — au lieu d'un accès tout-ou-rien.

-- 1. Étapes autorisées par la plateforme (CompanyFeatureModules).
ALTER TABLE public."CompanyFeatureModules"
  ADD COLUMN IF NOT EXISTS "smsEnregistreAllowed" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "smsChargeAllowed" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "smsArriveAllowed" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "smsLivreAllowed" boolean NOT NULL DEFAULT false;

-- Compatibilité : les compagnies dont l'option SMS était déjà accordée
-- conservent l'accès à toutes les étapes.
UPDATE public."CompanyFeatureModules"
SET "smsEnregistreAllowed" = true,
    "smsChargeAllowed" = true,
    "smsArriveAllowed" = true,
    "smsLivreAllowed" = true
WHERE "moduleD" = true AND COALESCE("moduleDColisSmsConfig", false) = true;

-- 2. Étape autorisée pour une compagnie ?
CREATE OR REPLACE FUNCTION public.company_colis_sms_step_allowed(p_company_id uuid, p_statut text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(m."moduleD", false)
    AND COALESCE(m."moduleDColisSmsConfig", false)
    AND CASE p_statut
      WHEN 'enregistre' THEN COALESCE(m."smsEnregistreAllowed", false)
      WHEN 'charge' THEN COALESCE(m."smsChargeAllowed", false)
      WHEN 'arrive' THEN COALESCE(m."smsArriveAllowed", false)
      WHEN 'livre' THEN COALESCE(m."smsLivreAllowed", false)
      ELSE false
    END
  FROM public."CompanyFeatureModules" m
  WHERE m."companyId" = p_company_id;
$function$;

-- 3. Verrou d'envoi : étape autorisée par la plateforme ET activée par l'owner.
CREATE OR REPLACE FUNCTION public.colis_sms_enabled_for_statut(p_company_id uuid, p_statut text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(public.company_colis_sms_step_allowed(p_company_id, p_statut), false)
    AND CASE p_statut
      WHEN 'enregistre' THEN COALESCE(c.sms_on_enregistre, false)
      WHEN 'charge' THEN COALESCE(c.sms_on_charge, false)
      WHEN 'arrive' THEN COALESCE(c.sms_on_arrive, false)
      WHEN 'livre' THEN COALESCE(c.sms_on_livre, false)
      ELSE false
    END
  FROM public."Companies" c
  WHERE c.id = p_company_id;
$function$;

-- 4. Réglages owner : expose les étapes autorisées, et les toggles effectifs
--    sont bornés aux étapes autorisées.
CREATE OR REPLACE FUNCTION public.get_company_colis_settings(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_row "Companies"%ROWTYPE;
  v_a_enr boolean;
  v_a_cha boolean;
  v_a_arr boolean;
  v_a_liv boolean;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT * INTO v_row FROM "Companies" WHERE id = p_company_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  v_a_enr := COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'enregistre'), false);
  v_a_cha := COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'charge'), false);
  v_a_arr := COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'arrive'), false);
  v_a_liv := COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'livre'), false);

  RETURN jsonb_build_object(
    'companyId', v_row.id,
    'colisAutonomeEnabled', public.company_colis_module_enabled(p_company_id),
    'colisSmsConfigEnabled', (v_a_enr OR v_a_cha OR v_a_arr OR v_a_liv),
    'smsAllowedEnregistre', v_a_enr,
    'smsAllowedCharge', v_a_cha,
    'smsAllowedArrive', v_a_arr,
    'smsAllowedLivre', v_a_liv,
    'smsOnEnregistre', v_a_enr AND COALESCE(v_row.sms_on_enregistre, false),
    'smsOnCharge', v_a_cha AND COALESCE(v_row.sms_on_charge, false),
    'smsOnArrive', v_a_arr AND COALESCE(v_row.sms_on_arrive, false),
    'smsOnLivre', v_a_liv AND COALESCE(v_row.sms_on_livre, false)
  );
END;
$function$;

-- 5. L'owner ne peut activer que les étapes autorisées (borné, pas d'erreur).
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
SET search_path TO 'public', 'pg_temp'
AS $function$
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
    sms_on_enregistre = COALESCE(p_sms_on_enregistre, false)
      AND COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'enregistre'), false),
    sms_on_charge = COALESCE(p_sms_on_charge, false)
      AND COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'charge'), false),
    sms_on_arrive = COALESCE(p_sms_on_arrive, false)
      AND COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'arrive'), false),
    sms_on_livre = COALESCE(p_sms_on_livre, false)
      AND COALESCE(public.company_colis_sms_step_allowed(p_company_id, 'livre'), false)
  WHERE id = p_company_id;

  RETURN public.get_company_colis_settings(p_company_id);
END;
$function$;

-- 6. Super admin / admin pays : choix des étapes incluses dans l'offre.
--    Synchronise le master moduleDColisSmsConfig (= au moins une étape) et
--    coupe les toggles owner des étapes retirées.
CREATE OR REPLACE FUNCTION public.set_company_colis_sms_steps_allowed(
  p_company_id uuid,
  p_enregistre boolean,
  p_charge boolean,
  p_arrive boolean,
  p_livre boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_country uuid;
  v_any boolean := COALESCE(p_enregistre, false) OR COALESCE(p_charge, false)
    OR COALESCE(p_arrive, false) OR COALESCE(p_livre, false);
BEGIN
  SELECT c."countryId" INTO v_country FROM "Companies" c WHERE c.id = p_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;
  IF NOT (public.is_super_admin() OR public.has_country_role(v_country, ARRAY['admin_pays'])) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  INSERT INTO "CompanyFeatureModules" (
    "companyId", "moduleA", "moduleB", "moduleC", "moduleD", "moduleE", "moduleF",
    "moduleDColisSmsConfig",
    "smsEnregistreAllowed", "smsChargeAllowed", "smsArriveAllowed", "smsLivreAllowed",
    "updatedBy"
  ) VALUES (
    p_company_id, true, true, true, true, true, false,
    v_any,
    COALESCE(p_enregistre, false), COALESCE(p_charge, false),
    COALESCE(p_arrive, false), COALESCE(p_livre, false),
    public.current_app_user_id()
  )
  ON CONFLICT ("companyId") DO UPDATE SET
    "moduleDColisSmsConfig" = v_any,
    "smsEnregistreAllowed" = COALESCE(p_enregistre, false),
    "smsChargeAllowed" = COALESCE(p_charge, false),
    "smsArriveAllowed" = COALESCE(p_arrive, false),
    "smsLivreAllowed" = COALESCE(p_livre, false),
    "updatedAt" = now(),
    "updatedBy" = public.current_app_user_id();

  -- Coupe les toggles owner des étapes désormais hors offre.
  UPDATE "Companies"
  SET
    sms_on_enregistre = COALESCE(sms_on_enregistre, false) AND COALESCE(p_enregistre, false),
    sms_on_charge = COALESCE(sms_on_charge, false) AND COALESCE(p_charge, false),
    sms_on_arrive = COALESCE(sms_on_arrive, false) AND COALESCE(p_arrive, false),
    sms_on_livre = COALESCE(sms_on_livre, false) AND COALESCE(p_livre, false)
  WHERE id = p_company_id;

  RETURN public.get_company_feature_modules(p_company_id);
END;
$function$;

-- 7. get_company_feature_modules expose les étapes autorisées.
CREATE OR REPLACE FUNCTION public.get_company_feature_modules(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
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
      'smsEnregistreAllowed', false,
      'smsChargeAllowed', false,
      'smsArriveAllowed', false,
      'smsLivreAllowed', false,
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
    'smsEnregistreAllowed', COALESCE(v_row."smsEnregistreAllowed", false),
    'smsChargeAllowed', COALESCE(v_row."smsChargeAllowed", false),
    'smsArriveAllowed', COALESCE(v_row."smsArriveAllowed", false),
    'smsLivreAllowed', COALESCE(v_row."smsLivreAllowed", false),
    'updatedAt', v_row."updatedAt"
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.company_colis_sms_step_allowed(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_company_colis_sms_steps_allowed(uuid, boolean, boolean, boolean, boolean) FROM PUBLIC, anon;
