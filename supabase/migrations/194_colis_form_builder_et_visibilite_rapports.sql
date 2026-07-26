-- Form builder colis (champs perso par compagnie) + visibilité des rapports
-- (report entier + champs sensibles internes), pilotés par l'owner depuis le
-- web (tibus-front). Mobile (courrier_mobile) et web consomment le même
-- Companies.colis_ui_config via get_company_colis_settings.
--
-- Schéma colis_ui_config (jsonb) :
-- {
--   "formFields": { "poids": true, "pieces": true, "description": true,
--                   "pourcentagePercu": true, "photo": true },
--   "customFields": [
--     { "key": "ref_client", "label": "Réf. client", "type": "text",
--       "required": false },
--     { "key": "urgence", "label": "Urgence", "type": "select",
--       "options": ["Normal", "Urgent"], "required": false }
--   ],
--   "reports": {
--     "salesJournal": { "enabled": true, "hiddenFields": ["valeur"] },
--     "cashJournal":  { "enabled": true, "hiddenFields": [] },
--     "bordereau":    { "enabled": true, "hiddenFields": ["montantTotal"] },
--     "stats":        { "enabled": true, "hiddenFields": [] }
--   }
-- }
--
-- Rétro-compatible avec ColisUiConfig.fromSettings (Dart) qui lit déjà
-- settings['uiConfig'] / ['formFields'] / ['reports'] (bool-map ou objets).

ALTER TABLE public."Companies"
  ADD COLUMN IF NOT EXISTS colis_ui_config jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.colis_autonomes
  ADD COLUMN IF NOT EXISTS custom_fields jsonb NOT NULL DEFAULT '{}'::jsonb;

-- Nettoyage des anciennes surcharges de register_colis_autonome (12 et 14
-- paramètres) : plus aucun appelant (mobile + web) n'utilise ces formes
-- réduites, seule la forme la plus complète (jusqu'à p_bus_id) est utilisée
-- — voir colis_service.dart / colis-autonomes.ts. On évite ainsi tout
-- risque d'ambiguïté "function is not unique" une fois p_custom_fields
-- ajouté (déjà rencontré sur update_colis_autonome_statut, migration 179).
DROP FUNCTION IF EXISTS public.register_colis_autonome(
  uuid, uuid, uuid, text, text, text, text, text, double precision,
  integer, double precision, uuid[], double precision
);
DROP FUNCTION IF EXISTS public.register_colis_autonome(
  uuid, uuid, uuid, text, text, text, text, text, double precision,
  integer, double precision, uuid[], double precision, double precision
);
-- CREATE OR REPLACE avec un paramètre supplémentaire (p_custom_fields) crée
-- une signature DISTINCTE au lieu de remplacer l'existante à 15 paramètres
-- (constaté en prod juste après la première application de cette migration)
-- — on la supprime donc aussi explicitement en amont.
DROP FUNCTION IF EXISTS public.register_colis_autonome(
  uuid, uuid, uuid, text, text, text, text, text, double precision,
  integer, double precision, uuid[], double precision, double precision, uuid
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
  p_valeur_marchandise double precision DEFAULT NULL::double precision,
  p_pourcentage_percu double precision DEFAULT NULL::double precision,
  p_bus_id uuid DEFAULT NULL::uuid,
  p_custom_fields jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
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
  v_notify_recipients uuid[];
  v_notify_title text;
  v_notify_message text;
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
  IF COALESCE(p_valeur_marchandise, 0) <= 0 THEN
    RAISE EXCEPTION 'Valeur marchandise obligatoire (sert de base au remboursement en cas de perte)';
  END IF;
  IF p_bus_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM "Bus" b WHERE b.id = p_bus_id AND b."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Bus invalide';
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
    pourcentage_percu, bus_id, custom_fields,
    vendeur_id, source_vente, statut_colis
  ) VALUES (
    p_company_id, p_gare_depart_id, p_gare_destination_id,
    btrim(p_nom_expediteur), btrim(p_telephone_expediteur),
    btrim(p_nom_destinataire), btrim(p_telephone_destinataire),
    NULLIF(btrim(COALESCE(p_description_contenu, '')), ''),
    NULLIF(p_poids_kg, 0),
    GREATEST(COALESCE(p_nombre_pieces, 1), 1),
    GREATEST(COALESCE(p_montant_fret, 0), 0),
    p_valeur_marchandise,
    CASE WHEN COALESCE(p_pourcentage_percu, 0) > 0 THEN p_pourcentage_percu ELSE NULL END,
    p_bus_id,
    COALESCE(p_custom_fields, '{}'::jsonb),
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

  PERFORM public.process_loyalty_on_colis(v_colis_id);

  SELECT c.name, gd.name, gdest.name
  INTO v_company_name, v_gare_depart, v_gare_destination
  FROM "Companies" c
  JOIN "Gares" gd ON gd.id = p_gare_depart_id
  JOIN "Gares" gdest ON gdest.id = p_gare_destination_id
  WHERE c.id = p_company_id;

  v_sms_message := public.build_colis_sms_message(
    'enregistre', v_colis_id, v_company_name, v_gare_depart, v_gare_destination
  );

  v_notify_recipients := public._colis_notification_recipients(
    p_company_id, p_gare_depart_id, p_gare_destination_id, v_user_id
  );
  v_notify_title := 'Nouveau colis enregistré';
  v_notify_message := format('%s → %s · %s XOF', v_gare_depart, v_gare_destination, v_montant_fcfa);
  PERFORM public._create_colis_notifications(
    v_notify_recipients, 'colis_vente', v_notify_title, v_notify_message,
    jsonb_build_object('colisId', v_colis_id, 'companyId', p_company_id)
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
    ),
    'notifyRecipients', to_jsonb(v_notify_recipients),
    'notifyTitle', v_notify_title,
    'notifyMessage', v_notify_message
  );
END;
$function$;

-- Ajoute customFields (valeurs saisies par l'agent) à la liste et au détail.
CREATE OR REPLACE FUNCTION public.list_colis_autonomes(p_company_id uuid, p_statut text DEFAULT NULL::text, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_rows jsonb;
  v_full_access boolean;
  v_gare_ids uuid[];
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;

  v_full_access := public.is_company_role_user(v_user_id, p_company_id)
    OR public.has_company_role(p_company_id, ARRAY['emballeur_gare','chargeur_gare','distributeur_gare']);

  IF NOT v_full_access THEN
    SELECT array_agg(ur."gareId") INTO v_gare_ids
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = p_company_id
      AND ur."gareId" IS NOT NULL
      AND r.name IN ('comptable_gare', 'emballeur_gare', 'chargeur_gare', 'distributeur_gare');

    IF v_gare_ids IS NULL THEN
      RAISE EXCEPTION 'Droits insuffisants';
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub."createdAt" DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      ca.id,
      ca.statut_colis AS "statutColis",
      ca.numero_recu AS "numeroRecu",
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
      COALESCE(ca.custom_fields, '{}'::jsonb) AS "customFields",
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
      AND (v_full_access OR ca.gare_depart_id = ANY(v_gare_ids) OR ca.gare_destination_id = ANY(v_gare_ids))
    ORDER BY ca.created_at DESC
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 5000), 1)
  ) sub;

  RETURN v_rows;
END;
$function$;

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
  IF NOT (
    public.is_company_role_user(v_user_id, v_colis.company_id)
    OR public.has_gare_colis_access(v_user_id, v_colis.company_id, v_colis.gare_depart_id, v_colis.gare_destination_id)
  ) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  SELECT jsonb_build_object('id', ca.id, 'companyId', ca.company_id, 'statutColis', ca.statut_colis, 'numeroRecu', ca.numero_recu, 'nomExpediteur', ca.nom_expediteur, 'telephoneExpediteur', ca.telephone_expediteur, 'nomDestinataire', ca.nom_destinataire, 'telephoneDestinataire', ca.telephone_destinataire, 'descriptionContenu', ca.description_contenu, 'poidsKg', ca.poids_kg, 'nombrePieces', ca.nombre_pieces, 'montantFret', ca.montant_fret, 'valeurMarchandise', ca.valeur_marchandise, 'sourceVente', ca.source_vente, 'createdAt', ca.created_at, 'updatedAt', ca.updated_at, 'gareDepartId', ca.gare_depart_id, 'gareDestinationId', ca.gare_destination_id, 'gareDepart', gd.name, 'gareDepartPhone', gd.phone, 'gareDestination', gdest.name, 'gareDestinationPhone', gdest.phone, 'companyName', c.name, 'companyPhone', c.phone, 'photoPath', ca.photo_path,
    'customFields', COALESCE(ca.custom_fields, '{}'::jsonb),
    'natureIds', COALESCE((SELECT jsonb_agg(cns.nature_id) FROM public.colis_natures_selectionnees cns WHERE cns.colis_id = ca.id), '[]'::jsonb),
    'natures', COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb))
  INTO v_row FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id JOIN "Companies" c ON c.id = ca.company_id WHERE ca.id = p_colis_id;
  RETURN v_row;
END; $function$;

-- Expose colis_ui_config (form builder + visibilité rapports) dans
-- get_company_colis_settings sous la clé "uiConfig" — déjà l'une des 3 clés
-- lues par ColisUiConfig.fromSettings côté Dart (courrier_mobile).
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
    'smsOnLivre', COALESCE(v_row.sms_on_livre, false),
    'uiConfig', COALESCE(v_row.colis_ui_config, '{}'::jsonb)
  );
END;
$$;

-- RPC d'écriture — réservée owner/comptable_compagnie/super_admin (mêmes
-- droits que la gestion des natures, ColisNaturesManager.tsx).
CREATE OR REPLACE FUNCTION public.update_company_colis_ui_config(
  p_company_id uuid,
  p_ui_config jsonb
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
$$;

GRANT EXECUTE ON FUNCTION public.register_colis_autonome(
  uuid, uuid, uuid, text, text, text, text, text, double precision,
  integer, double precision, uuid[], double precision, double precision, uuid, jsonb
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_company_colis_ui_config(uuid, jsonb) TO authenticated;
