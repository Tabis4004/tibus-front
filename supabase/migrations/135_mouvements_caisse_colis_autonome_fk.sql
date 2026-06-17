-- Colis autonomes : lier les mouvements caisse a colis_autonomes (pas ReservationBus).

ALTER TABLE public.mouvements_caisse
  ADD COLUMN IF NOT EXISTS colis_autonome_id uuid;

ALTER TABLE public.mouvements_caisse
  DROP CONSTRAINT IF EXISTS mouvements_caisse_colis_autonome_id_fkey;

ALTER TABLE public.mouvements_caisse
  ADD CONSTRAINT mouvements_caisse_colis_autonome_id_fkey
  FOREIGN KEY (colis_autonome_id) REFERENCES public.colis_autonomes(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.record_station_cash_movement(
  p_caisse_id uuid,
  p_type_mouvement text,
  p_montant integer,
  p_ticket_id uuid DEFAULT NULL::uuid,
  p_colis_id uuid DEFAULT NULL::uuid,
  p_effectue_par uuid DEFAULT NULL::uuid,
  p_reversement_id uuid DEFAULT NULL::uuid,
  p_note text DEFAULT NULL::text,
  p_direction text DEFAULT 'in'::text,
  p_colis_autonome_id uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caisse record;
  v_user_id uuid;
  v_delta integer;
  v_new_balance integer;
  v_movement_id uuid;
BEGIN
  IF COALESCE(p_montant, 0) <= 0 THEN RAISE EXCEPTION 'Montant mouvement invalide'; END IF;
  v_user_id := COALESCE(p_effectue_par, public.current_app_user_id());
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_caisse FROM caisses_gares WHERE id = p_caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  IF v_caisse.statut <> 'ouverte' AND p_type_mouvement <> 'reversement_comptable' THEN
    RAISE EXCEPTION 'Caisse cloturee';
  END IF;

  v_delta := CASE WHEN p_direction = 'out' THEN -p_montant ELSE p_montant END;
  v_new_balance := v_caisse.solde_especes_actuel + v_delta;
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Solde caisse insuffisant (solde: %, mouvement: %)', v_caisse.solde_especes_actuel, v_delta;
  END IF;

  UPDATE caisses_gares SET solde_especes_actuel = v_new_balance WHERE id = p_caisse_id;

  INSERT INTO mouvements_caisse (
    caisse_id, type_mouvement, montant, solde_apres,
    ticket_id, colis_id, colis_autonome_id, effectue_par, reversement_id, note
  ) VALUES (
    p_caisse_id, p_type_mouvement, p_montant, v_new_balance,
    p_ticket_id, p_colis_id, p_colis_autonome_id, v_user_id, p_reversement_id, NULLIF(trim(p_note), '')
  ) RETURNING id INTO v_movement_id;

  RETURN v_movement_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_station_cash_movements(
  p_caisse_id uuid,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  created_at timestamp with time zone,
  type_mouvement text,
  montant integer,
  solde_apres integer,
  ticket_id uuid,
  colis_id uuid,
  effectue_par_name text,
  note text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT public.station_cash_gare_company_id(c.gare_id) INTO v_company_id
  FROM caisses_gares c
  WHERE c.id = p_caisse_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  IF NOT (
    public.is_super_admin()
    OR public.can_operate_station_cash(v_company_id)
    OR public.can_validate_station_reversal(v_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces mouvements refuse';
  END IF;

  RETURN QUERY
  SELECT
    m.id,
    m.created_at,
    m.type_mouvement,
    m.montant,
    m.solde_apres,
    m.ticket_id,
    COALESCE(m.colis_autonome_id, m.colis_id) AS colis_id,
    NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), ''),
    m.note
  FROM mouvements_caisse m
  LEFT JOIN "Users" u ON u.id = m.effectue_par
  WHERE m.caisse_id = p_caisse_id
  ORDER BY m.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
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
  v_send_sms boolean;
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

  v_send_sms := public.colis_sms_enabled_for_statut(p_company_id, 'enregistre');
  v_sms_message := public.build_colis_sms_message(
    'enregistre', v_colis_id, v_company_name, v_gare_depart, v_gare_destination
  );

  RETURN jsonb_build_object(
    'id', v_colis_id,
    'statutColis', 'enregistre',
    'montantFret', GREATEST(COALESCE(p_montant_fret, 0), 0),
    'sms', jsonb_build_object(
      'send', v_send_sms,
      'message', v_sms_message,
      'expediteurPhone', btrim(p_telephone_expediteur),
      'destinatairePhone', btrim(p_telephone_destinataire)
    )
  );
END;
$$;
