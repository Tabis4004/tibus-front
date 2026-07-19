-- Notifications internes (in-app + retour destinataires pour push) pour les
-- ventes de colis et changements de statut faits par les agents.
--
-- Même principe de scoping que get_colis_autonome_stats (migration 182) :
-- owner / comptable_compagnie voient TOUTE l'activité de la compagnie ;
-- gerant_gare voit l'activité de SA gare (départ ou destination) ; les
-- autres rôles n'ont pas besoin de notification (ils sont déjà l'auteur de
-- l'action). L'acteur lui-même est toujours exclu des destinataires.
--
-- Réutilise la table "Notifications" existante (déjà utilisée pour les
-- réservations billets). Chaque RPC concernée renvoie en plus
-- notifyRecipients/notifyTitle/notifyMessage dans son jsonb de retour, pour
-- que le client (web ou mobile) déclenche ensuite un push FCM (edge
-- function send-staff-push, migration suivante) — même pattern que le SMS
-- client (colis-sms-notify) : le serveur prépare, le client orchestre.

CREATE OR REPLACE FUNCTION public._colis_notification_recipients(
  p_company_id uuid,
  p_gare_depart_id uuid,
  p_gare_destination_id uuid DEFAULT NULL::uuid,
  p_exclude_user_id uuid DEFAULT NULL::uuid
)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(array_agg(DISTINCT ur."userId"), ARRAY[]::uuid[])
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."companyId" = p_company_id
    AND (
      r.name IN ('owner', 'comptable_compagnie')
      OR (
        r.name IN ('gerant_gare', 'gestionnaire_gare')
        AND ur."gareId" IN (p_gare_depart_id, COALESCE(p_gare_destination_id, p_gare_depart_id))
      )
    )
    AND (p_exclude_user_id IS NULL OR ur."userId" <> p_exclude_user_id);
$$;

CREATE OR REPLACE FUNCTION public._create_colis_notifications(
  p_user_ids uuid[],
  p_type text,
  p_title text,
  p_message text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL THEN RETURN; END IF;
  INSERT INTO "Notifications" ("userId", type, title, message, "isRead", metadata)
  SELECT uid, p_type, p_title, p_message, false, p_metadata
  FROM unnest(p_user_ids) AS uid;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._colis_notification_recipients(uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._create_colis_notifications(uuid[], text, text, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- register_colis_autonome : notifie à l'enregistrement d'une vente.
-- ---------------------------------------------------------------------------
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
  p_bus_id uuid DEFAULT NULL::uuid
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
    pourcentage_percu, bus_id,
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

-- ---------------------------------------------------------------------------
-- update_colis_autonome_statut : notifie à chaque transition de statut.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_colis_autonome_statut(p_colis_id uuid, p_new_statut text, p_bus_id uuid DEFAULT NULL::uuid)
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
  v_notify_recipients uuid[];
  v_notify_title text;
  v_notify_message text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF p_new_statut NOT IN ('enregistre', 'charge', 'arrive', 'livre') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  IF p_bus_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM "Bus" b WHERE b.id = p_bus_id AND b."companyId" = v_colis.company_id
  ) THEN
    RAISE EXCEPTION 'Bus invalide';
  END IF;

  IF v_colis.statut_colis = 'enregistre' AND p_new_statut = 'charge' THEN
    PERFORM public._assert_lot_access(v_colis.company_id, v_colis.gare_depart_id, ARRAY['chargeur_gare']);
  ELSIF v_colis.statut_colis = 'charge' AND p_new_statut = 'arrive' THEN
    PERFORM public._assert_lot_access(v_colis.company_id, v_colis.gare_destination_id, ARRAY['distributeur_gare']);
  END IF;

  v_allowed := CASE
    WHEN v_colis.statut_colis = 'enregistre' AND p_new_statut = 'charge' THEN true
    WHEN v_colis.statut_colis = 'charge' AND p_new_statut = 'arrive' THEN true
    WHEN v_colis.statut_colis = 'arrive' AND p_new_statut = 'livre' THEN true
    WHEN p_new_statut = v_colis.statut_colis THEN true
    ELSE false
  END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Transition non autorisee: % -> %', v_colis.statut_colis, p_new_statut; END IF;
  UPDATE public.colis_autonomes
  SET statut_colis = p_new_statut,
      bus_id = COALESCE(p_bus_id, bus_id),
      updated_at = now()
  WHERE id = p_colis_id;
  SELECT c.name, gd.name, gdest.name
  INTO v_company_name, v_gare_depart, v_gare_destination
  FROM "Companies" c
  JOIN "Gares" gd ON gd.id = v_colis.gare_depart_id
  JOIN "Gares" gdest ON gdest.id = v_colis.gare_destination_id
  WHERE c.id = v_colis.company_id;
  v_message := public.build_colis_sms_message(p_new_statut, p_colis_id, v_company_name, v_gare_depart, v_gare_destination);

  IF p_new_statut <> v_colis.statut_colis THEN
    v_notify_recipients := public._colis_notification_recipients(
      v_colis.company_id, v_colis.gare_depart_id, v_colis.gare_destination_id, v_user_id
    );
    v_notify_title := 'Colis mis à jour';
    v_notify_message := format('%s → %s : %s → %s', v_gare_depart, v_gare_destination, v_colis.statut_colis, p_new_statut);
    PERFORM public._create_colis_notifications(
      v_notify_recipients, 'colis_statut', v_notify_title, v_notify_message,
      jsonb_build_object('colisId', p_colis_id, 'companyId', v_colis.company_id, 'statut', p_new_statut)
    );
  ELSE
    v_notify_recipients := ARRAY[]::uuid[];
  END IF;

  RETURN jsonb_build_object(
    'id', p_colis_id,
    'statutColis', p_new_statut,
    'sms', public.build_colis_sms_payload(
      v_colis.company_id,
      p_new_statut,
      v_message,
      v_colis.telephone_expediteur,
      v_colis.telephone_destinataire
    ),
    'notifyRecipients', to_jsonb(v_notify_recipients),
    'notifyTitle', v_notify_title,
    'notifyMessage', v_notify_message
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- mark_bordereau_charge / mark_bordereau_arrive : une notification par lot.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_bordereau_charge(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_bl bordereaux_livraison%ROWTYPE;
  v_company_name text;
  v_gare_depart_name text;
  v_gare_destination_name text;
  v_row record;
  v_results jsonb := '[]'::jsonb;
  v_notify_recipients uuid[];
  v_notify_title text;
  v_notify_message text;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_depart_id, ARRAY['chargeur_gare']);
  IF v_bl.statut <> 'clos' THEN
    RAISE EXCEPTION 'Le lot doit d''abord etre cloture (emballage termine) avant chargement';
  END IF;

  SELECT c.name INTO v_company_name FROM "Companies" c WHERE c.id = v_bl.company_id;
  SELECT name INTO v_gare_depart_name FROM "Gares" WHERE id = v_bl.gare_depart_id;
  SELECT name INTO v_gare_destination_name FROM "Gares" WHERE id = v_bl.gare_destination_id;

  FOR v_row IN
    SELECT ca.* FROM colis_autonomes ca
    JOIN bordereau_colis bc ON bc.colis_id = ca.id
    WHERE bc.bordereau_id = p_bordereau_id AND ca.statut_colis = 'enregistre'
  LOOP
    UPDATE colis_autonomes
    SET statut_colis = 'charge', bus_id = COALESCE(v_bl.bus_id, bus_id), updated_at = now()
    WHERE id = v_row.id;

    v_results := v_results || jsonb_build_object(
      'colisId', v_row.id,
      'sms', public.build_colis_sms_payload(
        v_bl.company_id, 'charge',
        public.build_colis_sms_message('charge', v_row.id, v_company_name, v_gare_depart_name, v_gare_destination_name),
        v_row.telephone_expediteur, v_row.telephone_destinataire
      )
    );
  END LOOP;

  UPDATE bordereaux_livraison SET statut = 'charge' WHERE id = p_bordereau_id;

  v_notify_recipients := public._colis_notification_recipients(
    v_bl.company_id, v_bl.gare_depart_id, v_bl.gare_destination_id, v_user_id
  );
  v_notify_title := 'Lot chargé';
  v_notify_message := format('Lot %s (%s → %s) chargé — %s colis', COALESCE(v_bl.numero_lot::text, v_bl.reference), v_gare_depart_name, v_gare_destination_name, jsonb_array_length(v_results));
  PERFORM public._create_colis_notifications(
    v_notify_recipients, 'lot_charge', v_notify_title, v_notify_message,
    jsonb_build_object('bordereauId', p_bordereau_id, 'companyId', v_bl.company_id)
  );

  RETURN jsonb_build_object(
    'id', p_bordereau_id, 'statut', 'charge', 'colisNotifications', v_results,
    'notifyRecipients', to_jsonb(v_notify_recipients),
    'notifyTitle', v_notify_title,
    'notifyMessage', v_notify_message
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_bordereau_arrive(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_bl bordereaux_livraison%ROWTYPE;
  v_company_name text;
  v_gare_depart_name text;
  v_gare_destination_name text;
  v_row record;
  v_results jsonb := '[]'::jsonb;
  v_notify_recipients uuid[];
  v_notify_title text;
  v_notify_message text;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  IF v_bl.gare_destination_id IS NULL THEN RAISE EXCEPTION 'Lot sans gare de destination'; END IF;
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_destination_id, ARRAY['distributeur_gare']);
  IF v_bl.statut <> 'charge' THEN
    RAISE EXCEPTION 'Le lot doit d''abord etre charge (parti) avant confirmation de reception';
  END IF;

  SELECT c.name INTO v_company_name FROM "Companies" c WHERE c.id = v_bl.company_id;
  SELECT name INTO v_gare_depart_name FROM "Gares" WHERE id = v_bl.gare_depart_id;
  SELECT name INTO v_gare_destination_name FROM "Gares" WHERE id = v_bl.gare_destination_id;

  FOR v_row IN
    SELECT ca.* FROM colis_autonomes ca
    JOIN bordereau_colis bc ON bc.colis_id = ca.id
    WHERE bc.bordereau_id = p_bordereau_id AND ca.statut_colis = 'charge'
  LOOP
    UPDATE colis_autonomes SET statut_colis = 'arrive', updated_at = now() WHERE id = v_row.id;

    v_results := v_results || jsonb_build_object(
      'colisId', v_row.id,
      'telephoneExpediteur', v_row.telephone_expediteur,
      'telephoneDestinataire', v_row.telephone_destinataire,
      'sms', public.build_colis_sms_payload(
        v_bl.company_id, 'arrive',
        public.build_colis_sms_message('arrive', v_row.id, v_company_name, v_gare_depart_name, v_gare_destination_name),
        v_row.telephone_expediteur, v_row.telephone_destinataire
      )
    );
  END LOOP;

  UPDATE bordereaux_livraison SET statut = 'arrive' WHERE id = p_bordereau_id;

  v_notify_recipients := public._colis_notification_recipients(
    v_bl.company_id, v_bl.gare_depart_id, v_bl.gare_destination_id, v_user_id
  );
  v_notify_title := 'Lot arrivé';
  v_notify_message := format('Lot %s (%s → %s) arrivé — %s colis', COALESCE(v_bl.numero_lot::text, v_bl.reference), v_gare_depart_name, v_gare_destination_name, jsonb_array_length(v_results));
  PERFORM public._create_colis_notifications(
    v_notify_recipients, 'lot_arrive', v_notify_title, v_notify_message,
    jsonb_build_object('bordereauId', p_bordereau_id, 'companyId', v_bl.company_id)
  );

  RETURN jsonb_build_object(
    'id', p_bordereau_id, 'statut', 'arrive', 'colisNotifications', v_results,
    'notifyRecipients', to_jsonb(v_notify_recipients),
    'notifyTitle', v_notify_title,
    'notifyMessage', v_notify_message
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- cancel_colis_autonome : notifie de l'annulation.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_colis_autonome(p_colis_id uuid, p_motif text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_colis record;
  v_mov record;
  v_cash_reversed boolean := false;
  v_notify_recipients uuid[];
  v_notify_title text;
  v_notify_message text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;

  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id FOR UPDATE;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;

  IF NOT (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND ur."companyId" = v_colis.company_id
        AND r.name IN ('owner', 'comptable_compagnie')
    )
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants — seul le promoteur (ou comptable) peut annuler un colis';
  END IF;

  IF v_colis.statut_colis = 'annule' THEN
    RAISE EXCEPTION 'Ce colis est déjà annulé';
  END IF;
  IF v_colis.statut_colis = 'livre' THEN
    RAISE EXCEPTION 'Impossible d''annuler un colis déjà livré au destinataire';
  END IF;

  UPDATE public.colis_autonomes
  SET statut_colis = 'annule',
      annule_par = v_user_id,
      annule_at = now(),
      motif_annulation = NULLIF(trim(p_motif), ''),
      updated_at = now()
  WHERE id = p_colis_id;

  INSERT INTO public.operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'bordereau_colis', bc.id, v_colis.company_id, to_jsonb(bc), 'cancel_colis_autonome', v_user_id
  FROM public.bordereau_colis bc WHERE bc.colis_id = p_colis_id;
  DELETE FROM public.bordereau_colis WHERE colis_id = p_colis_id;

  SELECT mc.*, cg.statut AS caisse_statut
  INTO v_mov
  FROM public.mouvements_caisse mc
  JOIN public.caisses_gares cg ON cg.id = mc.caisse_id
  WHERE mc.colis_autonome_id = p_colis_id
    AND mc.type_mouvement = 'encaissement_colis'
  ORDER BY mc.created_at ASC
  LIMIT 1;

  IF v_mov.id IS NOT NULL AND v_mov.caisse_statut = 'ouverte' THEN
    PERFORM public.record_station_cash_movement(
      p_caisse_id => v_mov.caisse_id,
      p_type_mouvement => 'decaissement_annulation',
      p_montant => v_mov.montant,
      p_colis_autonome_id => p_colis_id,
      p_effectue_par => v_user_id,
      p_direction => 'out',
      p_note => COALESCE('Annulation colis ' || v_colis.numero_recu, 'Annulation colis')
    );
    v_cash_reversed := true;
  END IF;

  v_notify_recipients := public._colis_notification_recipients(
    v_colis.company_id, v_colis.gare_depart_id, v_colis.gare_destination_id, v_user_id
  );
  v_notify_title := 'Colis annulé';
  v_notify_message := format('%s%s', COALESCE(v_colis.numero_recu, ''), CASE WHEN p_motif IS NOT NULL AND trim(p_motif) <> '' THEN ' — ' || trim(p_motif) ELSE '' END);
  PERFORM public._create_colis_notifications(
    v_notify_recipients, 'colis_annule', v_notify_title, v_notify_message,
    jsonb_build_object('colisId', p_colis_id, 'companyId', v_colis.company_id)
  );

  RETURN jsonb_build_object(
    'id', p_colis_id,
    'statutColis', 'annule',
    'cashReversed', v_cash_reversed,
    'notifyRecipients', to_jsonb(v_notify_recipients),
    'notifyTitle', v_notify_title,
    'notifyMessage', v_notify_message
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_colis_autonome(uuid, uuid, uuid, text, text, text, text, text, double precision, integer, double precision, uuid[], double precision, double precision, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_colis_autonome_statut(uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_bordereau_charge(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_bordereau_arrive(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_colis_autonome(uuid, text) TO authenticated;
