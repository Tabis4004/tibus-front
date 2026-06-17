-- Aligner porte admin SMS colis et préférences owner (plus de conflit sms_on_* / moduleDColisSmsConfig).

CREATE OR REPLACE FUNCTION public.build_colis_sms_payload(
  p_company_id uuid,
  p_statut text,
  p_message text,
  p_expediteur_phone text,
  p_destinataire_phone text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_send boolean;
  v_admin_gate boolean;
BEGIN
  v_admin_gate := public.company_colis_sms_owner_config_enabled(p_company_id);
  v_send := public.colis_sms_enabled_for_statut(p_company_id, p_statut);

  RETURN jsonb_build_object(
    'send', v_send,
    'message', CASE WHEN v_send THEN p_message ELSE NULL END,
    'expediteurPhone', NULLIF(btrim(p_expediteur_phone), ''),
    'destinatairePhone', NULLIF(btrim(p_destinataire_phone), ''),
    'skipReason', CASE
      WHEN v_send THEN NULL
      WHEN NOT v_admin_gate THEN 'admin_gate'
      ELSE 'owner_disabled'
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.build_colis_sms_payload(uuid, text, text, text, text) TO authenticated;

-- Conflit legacy : owner a déjà activé des étapes SMS mais la porte admin était restée à false.
UPDATE public."CompanyFeatureModules" m
SET
  "moduleDColisSmsConfig" = true,
  "updatedAt" = now()
FROM public."Companies" c
WHERE c.id = m."companyId"
  AND m."moduleD" = true
  AND COALESCE(m."moduleDColisSmsConfig", false) = false
  AND (
    COALESCE(c.sms_on_enregistre, false)
    OR COALESCE(c.sms_on_charge, false)
    OR COALESCE(c.sms_on_arrive, false)
    OR COALESCE(c.sms_on_livre, false)
  );

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
    'smsOnEnregistre', v_sms_config_allowed AND COALESCE(v_row.sms_on_enregistre, false),
    'smsOnCharge', v_sms_config_allowed AND COALESCE(v_row.sms_on_charge, false),
    'smsOnArrive', v_sms_config_allowed AND COALESCE(v_row.sms_on_arrive, false),
    'smsOnLivre', v_sms_config_allowed AND COALESCE(v_row.sms_on_livre, false)
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
$$;

CREATE OR REPLACE FUNCTION public.register_colis_autonome(
  p_company_id uuid,
  p_gare_depart_id uuid,
  p_gare_destination_id uuid,
  p_nom_expediteur text,
  p_telephone_expediteur text,
  p_nom_destinataire text,
  p_telephone_destinataire text,
  p_description_contenu text,
  p_poids_kg double precision,
  p_nombre_pieces integer,
  p_montant_fret double precision,
  p_nature_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_colis_id uuid;
  v_nature_id uuid;
  v_caisse_id uuid;
  v_montant_fcfa integer;
  v_company_name text;
  v_gare_depart text;
  v_gare_destination text;
  v_sms_message text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN
    RAISE EXCEPTION 'Module colis autonome non active';
  END IF;
  IF p_gare_depart_id = p_gare_destination_id THEN
    RAISE EXCEPTION 'Gare de depart et destination doivent etre differentes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = p_gare_depart_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de depart invalide';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = p_gare_destination_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de destination invalide';
  END IF;
  IF COALESCE(array_length(p_nature_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Selectionnez au moins une nature de colis';
  END IF;

  SELECT c.id INTO v_caisse_id
  FROM caisses_gares c
  WHERE c.gestionnaire_id = v_user_id
    AND c.statut = 'ouverte'
  ORDER BY c.opened_at DESC
  LIMIT 1;

  IF v_caisse_id IS NULL THEN
    RAISE EXCEPTION 'Ouvrez votre caisse avant une vente cash';
  END IF;

  PERFORM public.assert_seller_cash_departure_gare(v_caisse_id, p_gare_depart_id);

  INSERT INTO public.colis_autonomes (
    company_id, gare_depart_id, gare_destination_id,
    nom_expediteur, telephone_expediteur, nom_destinataire, telephone_destinataire,
    description_contenu, poids_kg, nombre_pieces, montant_fret,
    vendeur_id, source_vente, statut_colis
  ) VALUES (
    p_company_id, p_gare_depart_id, p_gare_destination_id,
    btrim(p_nom_expediteur), btrim(p_telephone_expediteur),
    btrim(p_nom_destinataire), btrim(p_telephone_destinataire),
    NULLIF(btrim(COALESCE(p_description_contenu, '')), ''),
    NULLIF(p_poids_kg, 0),
    GREATEST(COALESCE(p_nombre_pieces, 1), 1),
    GREATEST(COALESCE(p_montant_fret, 0), 0),
    v_user_id, 'guichet_cash', 'enregistre'
  ) RETURNING id INTO v_colis_id;

  FOREACH v_nature_id IN ARRAY p_nature_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.colis_natures n
      WHERE n.id = v_nature_id AND n.company_id = p_company_id AND n.is_active
    ) THEN
      RAISE EXCEPTION 'Nature de colis invalide: %', v_nature_id;
    END IF;
    INSERT INTO public.colis_natures_selectionnees (colis_id, nature_id)
    VALUES (v_colis_id, v_nature_id);
  END LOOP;

  v_montant_fcfa := ROUND(GREATEST(COALESCE(p_montant_fret, 0), 0))::integer;
  IF v_montant_fcfa > 0 THEN
    PERFORM public.record_station_cash_movement(
      v_caisse_id,
      'encaissement_colis',
      v_montant_fcfa,
      NULL,
      NULL,
      v_user_id,
      NULL,
      'Vente colis guichet',
      'in',
      v_colis_id
    );
  END IF;

  SELECT c.name, gd.name, gdest.name
  INTO v_company_name, v_gare_depart, v_gare_destination
  FROM "Companies" c
  JOIN "Gares" gd ON gd.id = p_gare_depart_id
  JOIN "Gares" gdest ON gdest.id = p_gare_destination_id
  WHERE c.id = p_company_id;

  v_sms_message := public.build_colis_sms_message(
    'enregistre', v_colis_id, v_company_name, v_gare_depart, v_gare_destination
  );

  RETURN jsonb_build_object(
    'id', v_colis_id,
    'statutColis', 'enregistre',
    'montantFret', GREATEST(COALESCE(p_montant_fret, 0), 0),
    'sms', public.build_colis_sms_payload(
      p_company_id,
      'enregistre',
      v_sms_message,
      p_telephone_expediteur,
      p_telephone_destinataire
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.update_colis_autonome_statut(p_colis_id uuid, p_new_statut text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_colis public.colis_autonomes%ROWTYPE;
  v_company_name text;
  v_gare_depart text;
  v_gare_destination text;
  v_allowed boolean := false;
  v_message text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF p_new_statut NOT IN ('enregistre', 'charge', 'arrive', 'livre') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  v_allowed := CASE
    WHEN v_colis.statut_colis = 'enregistre' AND p_new_statut = 'charge' THEN true
    WHEN v_colis.statut_colis = 'charge' AND p_new_statut = 'arrive' THEN true
    WHEN v_colis.statut_colis = 'arrive' AND p_new_statut = 'livre' THEN true
    WHEN p_new_statut = v_colis.statut_colis THEN true
    ELSE false
  END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Transition non autorisee: % -> %', v_colis.statut_colis, p_new_statut; END IF;
  UPDATE public.colis_autonomes SET statut_colis = p_new_statut, updated_at = now() WHERE id = p_colis_id;
  SELECT c.name, gd.name, gdest.name
  INTO v_company_name, v_gare_depart, v_gare_destination
  FROM "Companies" c
  JOIN "Gares" gd ON gd.id = v_colis.gare_depart_id
  JOIN "Gares" gdest ON gdest.id = v_colis.gare_destination_id
  WHERE c.id = v_colis.company_id;
  v_message := public.build_colis_sms_message(p_new_statut, p_colis_id, v_company_name, v_gare_depart, v_gare_destination);
  RETURN jsonb_build_object(
    'id', p_colis_id,
    'statutColis', p_new_statut,
    'sms', public.build_colis_sms_payload(
      v_colis.company_id,
      p_new_statut,
      v_message,
      v_colis.telephone_expediteur,
      v_colis.telephone_destinataire
    )
  );
END;
$function$;

