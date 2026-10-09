-- 219 — Embarquement hors ligne (Android / Windows, zones sans réseau)
--
-- L'app enregistre d'abord sur l'appareil (session, scans, clôture) puis
-- rejoue ces opérations au retour du réseau. Ces trois fonctions sont des
-- variantes IDEMPOTENTES des RPC existantes (inchangées, les anciennes
-- versions de l'app continuent de marcher) :
--   - l'identifiant (session / scan) est généré par l'appareil : rejouer la
--     même opération renvoie l'existant au lieu de créer un doublon ;
--   - l'heure réelle de l'opération est conservée, bornée côté serveur
--     (jamais dans le futur, jamais avant l'ouverture de la session, session
--     ouverte au plus 8 jours dans le passé — l'app bloque à 7 jours) ;
--   - AUCUN montant ne vient de l'appareil : le tarif est relu dans Tibus
--     (ProgrammationTrajetArrets) à la synchronisation de l'ouverture, puis
--     figé sur la session, comme en ligne (cf. CLAUDE.md, valeur probante).
-- Périmètre : sessions hors-Tibus sur trajet (gare → gare). Le scan de
-- billets Tibus reste en ligne uniquement.

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.embarquement_open_session_gare_offline(
  p_session_id uuid,
  p_opened_at timestamptz,
  p_company_id uuid,
  p_from_gare_id uuid,
  p_to_gare_id uuid,
  p_bus_label text DEFAULT NULL,
  p_capacity_declared integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_existing public.embarquement_sessions%ROWTYPE;
  v_from text;
  v_to text;
  v_min numeric(12, 2);
  v_max numeric(12, 2);
  v_route text;
  v_opened timestamptz;
BEGIN
  IF p_session_id IS NULL THEN RAISE EXCEPTION 'Identifiant de session requis'; END IF;

  -- Rejeu : la session existe déjà.
  SELECT * INTO v_existing FROM public.embarquement_sessions WHERE id = p_session_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.opened_by IS DISTINCT FROM v_user THEN
      RAISE EXCEPTION 'Session deja creee par un autre agent';
    END IF;
    RETURN jsonb_build_object('id', v_existing.id, 'fare_amount', v_existing.fare_amount,
      'route_label', v_existing.route_label, 'alreadySynced', true);
  END IF;

  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.embarquement_my_gares(p_company_id) mg WHERE mg.id = p_from_gare_id
  ) THEN
    RAISE EXCEPTION 'Gare de depart hors de votre perimetre';
  END IF;

  SELECT gf.name::text, gt.name::text, min(a.price), max(a.price)
  INTO v_from, v_to, v_min, v_max
  FROM public."ProgrammationTrajetArrets" a
  JOIN public."Gares" gf ON gf.id = a."fromGareId"
  JOIN public."Gares" gt ON gt.id = a."toGareId"
  WHERE a."fromGareId" = p_from_gare_id
    AND a."toGareId" = p_to_gare_id
    AND gf."companyId" = p_company_id
    AND a.price IS NOT NULL
  GROUP BY gf.name, gt.name;

  IF v_from IS NULL THEN
    RAISE EXCEPTION 'Itineraire introuvable ou sans tarif dans Tibus';
  END IF;
  IF v_min IS DISTINCT FROM v_max THEN
    RAISE EXCEPTION 'Tarifs contradictoires pour cet itineraire dans Tibus (% vs %)', v_min, v_max;
  END IF;
  IF p_capacity_declared IS NULL OR p_capacity_declared <= 0 THEN
    RAISE EXCEPTION 'Capacite requise';
  END IF;

  v_route := v_from || ' → ' || v_to;
  v_opened := LEAST(GREATEST(COALESCE(p_opened_at, now()), now() - interval '8 days'), now());

  INSERT INTO public.embarquement_sessions
    (id, company_id, route_label, bus_label, capacity_declared, gare_id, fare_amount, opened_by, opened_at)
  VALUES
    (p_session_id, p_company_id, v_route, NULLIF(BTRIM(COALESCE(p_bus_label, '')), ''),
     p_capacity_declared, p_from_gare_id, v_min, v_user, v_opened);

  RETURN jsonb_build_object('id', p_session_id, 'fare_amount', v_min, 'route_label', v_route,
    'alreadySynced', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.embarquement_open_session_gare_offline(uuid, timestamptz, uuid, uuid, uuid, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.embarquement_open_session_gare_offline(uuid, timestamptz, uuid, uuid, uuid, text, integer) TO authenticated;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.embarquement_scan_external_offline(
  p_scan_id uuid,
  p_scanned_at timestamptz,
  p_session_id uuid,
  p_raw_payload text,
  p_passenger_name text,
  p_ticket_number text DEFAULT NULL,
  p_origin_label text DEFAULT NULL,
  p_destination_label text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id uuid; v_closed timestamptz; v_opened timestamptz; v_fare numeric(12,2);
  v_user uuid := public.current_app_user_id();
  v_status text := 'valid'; v_dup_count integer; v_hide boolean;
  v_existing public.embarquement_scans%ROWTYPE;
  v_at timestamptz;
BEGIN
  IF p_scan_id IS NULL THEN RAISE EXCEPTION 'Identifiant de scan requis'; END IF;

  SELECT es.company_id, es.closed_at, es.opened_at, es.fare_amount
  INTO v_company_id, v_closed, v_opened, v_fare
  FROM public.embarquement_sessions es WHERE es.id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  v_hide := public.embarquement_hides_money(v_company_id);

  -- Rejeu : le scan existe déjà.
  SELECT * INTO v_existing FROM public.embarquement_scans WHERE id = p_scan_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.session_id IS DISTINCT FROM p_session_id THEN
      RAISE EXCEPTION 'Identifiant de scan deja utilise';
    END IF;
    RETURN jsonb_build_object('scanId', v_existing.id, 'status', v_existing.status,
      'amount', CASE WHEN v_hide THEN NULL ELSE v_existing.amount END, 'alreadySynced', true);
  END IF;

  IF public.embarquement_is_embarqueur_only(v_company_id)
     AND NOT public.embarquement_session_gare_is_mine(p_session_id) THEN
    RAISE EXCEPTION 'Cette session n''est pas celle de votre gare';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_passenger_name, '')), '') IS NULL THEN RAISE EXCEPTION 'passenger_name requis'; END IF;

  -- Heure réelle du scan, bornée à [ouverture de la session, maintenant].
  v_at := LEAST(GREATEST(COALESCE(p_scanned_at, now()), v_opened), now());

  -- Session clôturée : on accepte encore un scan fait AVANT la clôture
  -- (appareil resté hors ligne), jamais après.
  IF v_closed IS NOT NULL AND v_at > v_closed THEN
    RAISE EXCEPTION 'Session cloturee';
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_ticket_number, '')), '') IS NOT NULL THEN
    SELECT count(*) INTO v_dup_count FROM public.embarquement_scans s
    WHERE s.session_id = p_session_id AND s.deleted_at IS NULL AND s.status = 'valid'
      AND s.ticket_number IS NOT NULL AND UPPER(BTRIM(s.ticket_number)) = UPPER(BTRIM(p_ticket_number));
    IF v_dup_count > 0 THEN v_status := 'duplicate'; END IF;
  END IF;

  INSERT INTO public.embarquement_scans
    (id, session_id, scanned_by, scanned_at, raw_payload, source, passenger_name, ticket_number,
     origin_label, destination_label, status, amount)
  VALUES (p_scan_id, p_session_id, v_user, v_at, p_raw_payload, 'external', BTRIM(p_passenger_name),
     NULLIF(BTRIM(COALESCE(p_ticket_number, '')), ''), NULLIF(BTRIM(COALESCE(p_origin_label, '')), ''),
     NULLIF(BTRIM(COALESCE(p_destination_label, '')), ''), v_status, v_fare);

  RETURN jsonb_build_object('scanId', p_scan_id, 'status', v_status,
    'amount', CASE WHEN v_hide THEN NULL ELSE v_fare END, 'alreadySynced', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.embarquement_scan_external_offline(uuid, timestamptz, uuid, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.embarquement_scan_external_offline(uuid, timestamptz, uuid, text, text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Clôture rejouable : sans effet si la session est déjà clôturée ; sinon
-- mêmes contrôles que embarquement_close_session, puis heure réelle de la
-- clôture (bornée à [ouverture, maintenant]) pour une session hors-Tibus.
CREATE OR REPLACE FUNCTION public.embarquement_close_session_offline(
  p_session_id uuid,
  p_closed_at timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_closed timestamptz; v_opened timestamptz; v_res uuid; v_company_id uuid;
BEGIN
  SELECT company_id, closed_at, opened_at, reservation_id INTO v_company_id, v_closed, v_opened, v_res
  FROM public.embarquement_sessions WHERE id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF v_closed IS NOT NULL THEN
    RETURN jsonb_build_object('closedAt', v_closed, 'alreadyClosed', true);
  END IF;

  PERFORM public.embarquement_close_session(p_session_id);

  IF v_res IS NULL AND p_closed_at IS NOT NULL THEN
    UPDATE public.embarquement_sessions
    SET closed_at = LEAST(GREATEST(p_closed_at, v_opened), now())
    WHERE id = p_session_id;
  END IF;

  SELECT closed_at INTO v_closed FROM public.embarquement_sessions WHERE id = p_session_id;
  RETURN jsonb_build_object('closedAt', v_closed, 'alreadyClosed', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.embarquement_close_session_offline(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.embarquement_close_session_offline(uuid, timestamptz) TO authenticated;
