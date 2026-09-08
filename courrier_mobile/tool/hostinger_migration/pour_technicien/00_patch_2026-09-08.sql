-- ============================================================================
-- Patch du 2026-09-08 : fonctions d'ÉCRITURE de l'écran "Réglages colis
-- autonome" (Natures de colis, Prix minimum général, Formulaire colis)
-- absentes de l'export initial. Cause du bug : l'écran affichait les
-- réglages actuels normalement (fonctions de LECTURE déjà présentes :
-- get_company_colis_settings, get_colis_prix_min), mais toute modification
-- (activer/désactiver une nature, changer un prix minimum, masquer un champ
-- du formulaire) échouait silencieusement côté serveur, la fonction
-- appelée par l'app étant introuvable sur cette instance.
--
-- Idempotent (CREATE OR REPLACE FUNCTION) -- sans risque à rejouer.
-- Aucune table/colonne manquante : toutes les colonnes utilisées
-- (Companies.colis_prix_min_fixe_general/colis_prix_min_taux_general/
-- colis_pourcentage_percu_general/colis_ui_config, colis_natures.is_active/
-- prix_min_fixe/prix_min_taux, contrainte UNIQUE (company_id, libelle))
-- étaient déjà dans le schéma exporté -- seules les fonctions manquaient.
--
-- À exécuter directement sur Hostinger :
--   psql "$HOSTINGER_DB_URL" -f 00_patch_2026-09-08.sql
-- ============================================================================

-- update_company_colis_price_settings : DEUX signatures existent côté
-- Tibus 1.0 (l'ancienne à 3 arguments, avant l'ajout du pourcentage perçu ;
-- la nouvelle à 4). L'app appelle la version à 4 arguments, mais les deux
-- sont incluses pour rester identique à la source.
CREATE OR REPLACE FUNCTION public.update_company_colis_price_settings(p_company_id uuid, p_prix_min_fixe_general double precision, p_prix_min_taux_general double precision)
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
  IF p_prix_min_fixe_general IS NOT NULL AND p_prix_min_fixe_general < 0 THEN
    RAISE EXCEPTION 'Le prix minimum fixe doit etre positif';
  END IF;
  IF p_prix_min_taux_general IS NOT NULL AND p_prix_min_taux_general < 0 THEN
    RAISE EXCEPTION 'Le taux minimum doit etre positif';
  END IF;

  UPDATE "Companies"
  SET
    colis_prix_min_fixe_general = p_prix_min_fixe_general,
    colis_prix_min_taux_general = p_prix_min_taux_general
  WHERE id = p_company_id;

  RETURN public.get_company_colis_settings(p_company_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_company_colis_price_settings(p_company_id uuid, p_prix_min_fixe_general double precision, p_prix_min_taux_general double precision, p_pourcentage_percu_general double precision DEFAULT NULL::double precision)
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
  IF p_prix_min_fixe_general IS NOT NULL AND p_prix_min_fixe_general < 0 THEN
    RAISE EXCEPTION 'Le prix minimum fixe doit etre positif';
  END IF;
  IF p_prix_min_taux_general IS NOT NULL AND p_prix_min_taux_general < 0 THEN
    RAISE EXCEPTION 'Le taux minimum doit etre positif';
  END IF;
  IF p_pourcentage_percu_general IS NOT NULL AND (p_pourcentage_percu_general < 0 OR p_pourcentage_percu_general > 100) THEN
    RAISE EXCEPTION 'Le pourcentage percu doit etre compris entre 0 et 100';
  END IF;

  UPDATE "Companies"
  SET
    colis_prix_min_fixe_general = p_prix_min_fixe_general,
    colis_prix_min_taux_general = p_prix_min_taux_general,
    colis_pourcentage_percu_general = p_pourcentage_percu_general
  WHERE id = p_company_id;

  RETURN public.get_company_colis_settings(p_company_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_company_colis_ui_config(p_company_id uuid, p_ui_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_ui_config IS NULL OR jsonb_typeof(p_ui_config) <> 'object' THEN
    RAISE EXCEPTION 'Configuration invalide';
  END IF;

  UPDATE "Companies"
  SET colis_ui_config = p_ui_config
  WHERE id = p_company_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  RETURN public.get_company_colis_settings(p_company_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_colis_nature(p_company_id uuid, p_libelle text, p_nature_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true, p_prix_min_fixe double precision DEFAULT NULL::double precision, p_prix_min_taux double precision DEFAULT NULL::double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_id uuid;
  v_libelle text := btrim(COALESCE(p_libelle, ''));
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN RAISE EXCEPTION 'Module colis autonome non active'; END IF;
  IF v_libelle = '' THEN RAISE EXCEPTION 'Libelle requis'; END IF;
  IF p_prix_min_fixe IS NOT NULL AND p_prix_min_fixe < 0 THEN RAISE EXCEPTION 'Le prix minimum fixe doit etre positif'; END IF;
  IF p_prix_min_taux IS NOT NULL AND p_prix_min_taux < 0 THEN RAISE EXCEPTION 'Le taux minimum doit etre positif'; END IF;

  IF p_nature_id IS NOT NULL THEN
    UPDATE public.colis_natures
    SET libelle = v_libelle,
        is_active = COALESCE(p_is_active, true),
        prix_min_fixe = p_prix_min_fixe,
        prix_min_taux = p_prix_min_taux
    WHERE id = p_nature_id AND company_id = p_company_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Nature introuvable'; END IF;
  ELSE
    INSERT INTO public.colis_natures (company_id, libelle, is_active, prix_min_fixe, prix_min_taux)
    VALUES (p_company_id, v_libelle, COALESCE(p_is_active, true), p_prix_min_fixe, p_prix_min_taux)
    ON CONFLICT (company_id, libelle) DO UPDATE
      SET is_active = EXCLUDED.is_active,
          prix_min_fixe = EXCLUDED.prix_min_fixe,
          prix_min_taux = EXCLUDED.prix_min_taux
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_id,
    'libelle', v_libelle,
    'isActive', COALESCE(p_is_active, true),
    'prixMinFixe', p_prix_min_fixe,
    'prixMinTaux', p_prix_min_taux
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_colis_nature(p_nature_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_company_id uuid; v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT company_id INTO v_company_id FROM public.colis_natures WHERE id = p_nature_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Nature introuvable'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, v_company_id) OR public.is_super_admin()) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF EXISTS (SELECT 1 FROM public.colis_natures_selectionnees WHERE nature_id = p_nature_id) THEN RAISE EXCEPTION 'Nature utilisee — desactivez-la'; END IF;
  DELETE FROM public.colis_natures WHERE id = p_nature_id;
END; $function$;
