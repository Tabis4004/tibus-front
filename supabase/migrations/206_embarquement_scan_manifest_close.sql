-- ============================================================================
-- Embarquement — scan Tibus/externe, manifeste, clôture (Phase 1).
-- Complète embarquement_sessions/scans (déjà en place) sans y toucher, sauf
-- l'ajout additif de tibus_raw_result (nullable, pour debug/affichage du
-- motif réel de rejet renvoyé par verify_ticket_qr).
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-03
-- (nom de migration côté Supabase : embarquement_scan_manifest_close).
-- ============================================================================

ALTER TABLE public.embarquement_scans ADD COLUMN IF NOT EXISTS tibus_raw_result text;

-- Scan d'un billet Tibus : le QR ne contient que la référence (+ token
-- optionnel, voir ticket_qr_parser.dart) — verify_ticket_qr() est la seule
-- source du nom/gare départ/gare destination écrits sur la ligne de scan.
-- p_record_boarding=true : une seule étape (décision utilisateur, scan =
-- embarqué), jamais d'appel à confirm_passenger_on_board.
CREATE OR REPLACE FUNCTION public.embarquement_scan_tibus(
  p_session_id uuid,
  p_raw_payload text,
  p_reference text,
  p_token text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_closed timestamptz;
  v_user uuid := public.current_app_user_id();
  v_verify jsonb;
  v_result text;
  v_status text;
  v_rb_id uuid;
  v_scan_id uuid;
BEGIN
  SELECT company_id, closed_at INTO v_company_id, v_closed
  FROM public.embarquement_sessions WHERE id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF v_closed IS NOT NULL THEN
    RAISE EXCEPTION 'Session cloturee';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_reference, '')), '') IS NULL THEN
    RAISE EXCEPTION 'reference requise';
  END IF;

  v_verify := public.verify_ticket_qr(p_reference, p_token, true, false, v_company_id);
  v_result := v_verify->>'result';

  v_status := CASE v_result
    WHEN 'valid' THEN 'valid'
    WHEN 'duplicate' THEN 'duplicate'
    WHEN 'on_board' THEN 'duplicate'
    WHEN 'wrong_company' THEN 'wrong_session'
    ELSE 'invalid'
  END;

  v_rb_id := NULLIF(v_verify->>'bookingId', '')::uuid;

  INSERT INTO public.embarquement_scans
    (session_id, scanned_by, raw_payload, source, tibus_raw_result,
     matched_reservation_bus_id, passenger_name, ticket_number,
     origin_label, destination_label, status)
  VALUES
    (p_session_id, v_user, p_raw_payload, 'tibus', v_result,
     v_rb_id, v_verify->>'passengerName', v_verify->>'bookingReference',
     v_verify#>>'{origin,name}', v_verify#>>'{destination,name}', v_status)
  RETURNING id INTO v_scan_id;

  RETURN jsonb_build_object('scanId', v_scan_id, 'status', v_status, 'verify', v_verify);
END;
$$;

-- Scan d'un QR tiers (pas Tibus) : les champs sont déjà extraits/corrigés
-- côté client (parseur multi-format + écran de correction manuelle
-- obligatoire, voir external_qr_parser.dart) — cette RPC enregistre tel
-- quel et détecte les doublons DANS LA SESSION par numéro de billet.
CREATE OR REPLACE FUNCTION public.embarquement_scan_external(
  p_session_id uuid,
  p_raw_payload text,
  p_passenger_name text,
  p_ticket_number text,
  p_origin_label text,
  p_destination_label text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_closed timestamptz;
  v_user uuid := public.current_app_user_id();
  v_status text := 'valid';
  v_scan_id uuid;
  v_dup_count integer;
BEGIN
  SELECT company_id, closed_at INTO v_company_id, v_closed
  FROM public.embarquement_sessions WHERE id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF v_closed IS NOT NULL THEN
    RAISE EXCEPTION 'Session cloturee';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_passenger_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'passenger_name requis';
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_ticket_number, '')), '') IS NOT NULL THEN
    SELECT count(*) INTO v_dup_count
    FROM public.embarquement_scans
    WHERE session_id = p_session_id
      AND deleted_at IS NULL
      AND status = 'valid'
      AND ticket_number IS NOT NULL
      AND UPPER(BTRIM(ticket_number)) = UPPER(BTRIM(p_ticket_number));
    IF v_dup_count > 0 THEN
      v_status := 'duplicate';
    END IF;
  END IF;

  INSERT INTO public.embarquement_scans
    (session_id, scanned_by, raw_payload, source, passenger_name, ticket_number,
     origin_label, destination_label, status)
  VALUES
    (p_session_id, v_user, p_raw_payload, 'external', BTRIM(p_passenger_name),
     NULLIF(BTRIM(COALESCE(p_ticket_number, '')), ''),
     NULLIF(BTRIM(COALESCE(p_origin_label, '')), ''),
     NULLIF(BTRIM(COALESCE(p_destination_label, '')), ''), v_status)
  RETURNING id INTO v_scan_id;

  RETURN jsonb_build_object('scanId', v_scan_id, 'status', v_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_list_manifest(p_session_id uuid)
RETURNS TABLE(
  id uuid, scanned_at timestamptz, source text, passenger_name text,
  ticket_number text, origin_label text, destination_label text, status text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id FROM public.embarquement_sessions WHERE id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT s.id, s.scanned_at, s.source, s.passenger_name, s.ticket_number,
         s.origin_label, s.destination_label, s.status
  FROM public.embarquement_scans s
  WHERE s.session_id = p_session_id AND s.deleted_at IS NULL
  ORDER BY s.scanned_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_close_session(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_closed timestamptz;
  v_user uuid := public.current_app_user_id();
BEGIN
  SELECT company_id, closed_at INTO v_company_id, v_closed
  FROM public.embarquement_sessions WHERE id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF v_closed IS NOT NULL THEN
    RAISE EXCEPTION 'Session deja cloturee';
  END IF;

  UPDATE public.embarquement_sessions
  SET closed_at = now(), closed_by = v_user
  WHERE id = p_session_id;
END;
$$;
