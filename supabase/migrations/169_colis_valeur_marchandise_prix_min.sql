-- ============================================================
-- Colis autonome : valeur déclarée de la marchandise (informative,
-- imprimée sur le reçu, n'entre pas dans le calcul du prix) + règles
-- de prix minimum par nature de colis, avec override général compagnie
-- (taux ou fixe) qui prévaut sur les règles par nature si non NULL.
-- ============================================================

-- 1) Valeur déclarée de la marchandise.
ALTER TABLE public.colis_autonomes
  ADD COLUMN IF NOT EXISTS valeur_marchandise double precision;

-- 2) Règles de prix minimum par nature (fixe OU taux/kg).
ALTER TABLE public.colis_natures
  ADD COLUMN IF NOT EXISTS prix_min_fixe double precision,
  ADD COLUMN IF NOT EXISTS prix_min_taux double precision;

-- 3) Override général compagnie (fixe OU taux/kg).
ALTER TABLE "Companies"
  ADD COLUMN IF NOT EXISTS colis_prix_min_fixe_general double precision,
  ADD COLUMN IF NOT EXISTS colis_prix_min_taux_general double precision;

-- 4) Helper : calcule le prix minimum requis pour un envoi donné.
CREATE OR REPLACE FUNCTION public.compute_colis_prix_min(
  p_company_id uuid,
  p_nature_ids uuid[],
  p_poids_kg double precision
) RETURNS double precision
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_general_fixe double precision;
  v_general_taux double precision;
  v_min double precision := 0;
  v_nature_min double precision;
  v_row record;
BEGIN
  SELECT colis_prix_min_fixe_general, colis_prix_min_taux_general
    INTO v_general_fixe, v_general_taux
  FROM "Companies" WHERE id = p_company_id;

  IF v_general_fixe IS NOT NULL THEN
    RETURN GREATEST(v_general_fixe, 0);
  END IF;
  IF v_general_taux IS NOT NULL THEN
    RETURN GREATEST(v_general_taux * COALESCE(p_poids_kg, 0), 0);
  END IF;

  IF p_nature_ids IS NULL OR array_length(p_nature_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  FOR v_row IN
    SELECT prix_min_fixe, prix_min_taux
    FROM public.colis_natures
    WHERE id = ANY(p_nature_ids) AND company_id = p_company_id
  LOOP
    IF v_row.prix_min_fixe IS NOT NULL THEN
      v_nature_min := v_row.prix_min_fixe;
    ELSIF v_row.prix_min_taux IS NOT NULL THEN
      v_nature_min := v_row.prix_min_taux * COALESCE(p_poids_kg, 0);
    ELSE
      v_nature_min := 0;
    END IF;
    v_min := GREATEST(v_min, v_nature_min);
  END LOOP;

  RETURN GREATEST(v_min, 0);
END;
$function$;

-- 5) Exposer le calcul au client (indicatif avant enregistrement).
CREATE OR REPLACE FUNCTION public.get_colis_prix_min(
  p_company_id uuid,
  p_nature_ids uuid[],
  p_poids_kg double precision
) RETURNS double precision
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN public.compute_colis_prix_min(p_company_id, p_nature_ids, p_poids_kg);
END;
$function$;

-- 6) get_company_colis_settings : exposer l'override général.
CREATE OR REPLACE FUNCTION public.get_company_colis_settings(p_company_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
    'smsOnLivre', v_a_liv AND COALESCE(v_row.sms_on_livre, false),
    'colisPrixMinFixeGeneral', v_row.colis_prix_min_fixe_general,
    'colisPrixMinTauxGeneral', v_row.colis_prix_min_taux_general
  );
END;
$function$;

-- 7) update_company_colis_price_settings.
CREATE OR REPLACE FUNCTION public.update_company_colis_price_settings(
  p_company_id uuid,
  p_prix_min_fixe_general double precision,
  p_prix_min_taux_general double precision
) RETURNS jsonb
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

-- 8) upsert_colis_nature : ajoute les règles de prix minimum par nature.
DROP FUNCTION IF EXISTS public.upsert_colis_nature(uuid, text, uuid, boolean);

CREATE OR REPLACE FUNCTION public.upsert_colis_nature(
  p_company_id uuid,
  p_libelle text,
  p_nature_id uuid DEFAULT NULL::uuid,
  p_is_active boolean DEFAULT true,
  p_prix_min_fixe double precision DEFAULT NULL::double precision,
  p_prix_min_taux double precision DEFAULT NULL::double precision
) RETURNS jsonb
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

-- 9) register_colis_autonome : ajoute la valeur déclarée + applique le prix minimum.
DROP FUNCTION IF EXISTS public.register_colis_autonome(
  uuid, uuid, uuid, text, text, text, text, text, double precision, integer, double precision, uuid[]
);

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
  p_nature_ids uuid[],
  p_valeur_marchandise double precision DEFAULT NULL::double precision
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  v_prix_min double precision;
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

  v_prix_min := public.compute_colis_prix_min(p_company_id, p_nature_ids, p_poids_kg);
  IF v_prix_min > 0 AND COALESCE(p_montant_fret, 0) < v_prix_min THEN
    RAISE EXCEPTION 'Montant fret insuffisant : minimum requis % XOF', ROUND(v_prix_min);
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
    description_contenu, poids_kg, nombre_pieces, montant_fret, valeur_marchandise,
    vendeur_id, source_vente, statut_colis
  ) VALUES (
    p_company_id, p_gare_depart_id, p_gare_destination_id,
    btrim(p_nom_expediteur), btrim(p_telephone_expediteur),
    btrim(p_nom_destinataire), btrim(p_telephone_destinataire),
    NULLIF(btrim(COALESCE(p_description_contenu, '')), ''),
    NULLIF(p_poids_kg, 0),
    GREATEST(COALESCE(p_nombre_pieces, 1), 1),
    GREATEST(COALESCE(p_montant_fret, 0), 0),
    CASE WHEN COALESCE(p_valeur_marchandise, 0) > 0 THEN p_valeur_marchandise ELSE NULL END,
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
$function$;

-- 10) get_colis_autonome_detail / list_colis_autonomes : exposer valeurMarchandise.
CREATE OR REPLACE FUNCTION public.get_colis_autonome_detail(p_colis_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user_id uuid := public.current_app_user_id(); v_colis public.colis_autonomes%ROWTYPE; v_row jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RETURN NULL; END IF;
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  SELECT jsonb_build_object('id', ca.id, 'companyId', ca.company_id, 'statutColis', ca.statut_colis, 'nomExpediteur', ca.nom_expediteur, 'telephoneExpediteur', ca.telephone_expediteur, 'nomDestinataire', ca.nom_destinataire, 'telephoneDestinataire', ca.telephone_destinataire, 'descriptionContenu', ca.description_contenu, 'poidsKg', ca.poids_kg, 'nombrePieces', ca.nombre_pieces, 'montantFret', ca.montant_fret, 'valeurMarchandise', ca.valeur_marchandise, 'sourceVente', ca.source_vente, 'createdAt', ca.created_at, 'updatedAt', ca.updated_at, 'gareDepartId', ca.gare_depart_id, 'gareDestinationId', ca.gare_destination_id, 'gareDepart', gd.name, 'gareDestination', gdest.name, 'companyName', c.name,
    'natureIds', COALESCE((SELECT jsonb_agg(cns.nature_id) FROM public.colis_natures_selectionnees cns WHERE cns.colis_id = ca.id), '[]'::jsonb),
    'natures', COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb))
  INTO v_row FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id JOIN "Companies" c ON c.id = ca.company_id WHERE ca.id = p_colis_id;
  RETURN v_row;
END; $function$;

CREATE OR REPLACE FUNCTION public.list_colis_autonomes(p_company_id uuid, p_statut text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_rows jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub."createdAt" DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      ca.id,
      ca.statut_colis AS "statutColis",
      ca.nom_expediteur AS "nomExpediteur",
      ca.telephone_expediteur AS "telephoneExpediteur",
      ca.nom_destinataire AS "nomDestinataire",
      ca.telephone_destinataire AS "telephoneDestinataire",
      ca.description_contenu AS "descriptionContenu",
      ca.poids_kg AS "poidsKg",
      ca.nombre_pieces AS "nombrePieces",
      ca.montant_fret AS "montantFret",
      ca.valeur_marchandise AS "valeurMarchandise",
      ca.created_at AS "createdAt",
      ca.updated_at AS "updatedAt",
      gd.name AS "gareDepart",
      gdest.name AS "gareDestination",
      COALESCE(
        (SELECT jsonb_agg(n.libelle ORDER BY n.libelle)
         FROM public.colis_natures_selectionnees cns
         JOIN public.colis_natures n ON n.id = cns.nature_id
         WHERE cns.colis_id = ca.id),
        '[]'::jsonb
      ) AS "natures"
    FROM public.colis_autonomes ca
    JOIN "Gares" gd ON gd.id = ca.gare_depart_id
    JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id
    WHERE ca.company_id = p_company_id
      AND (p_statut IS NULL OR ca.statut_colis = p_statut)
    ORDER BY ca.created_at DESC
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  ) sub;

  RETURN v_rows;
END;
$function$;
