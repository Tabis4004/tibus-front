-- 210 — Montant du billet sur le scan, et rapport de recette
--
-- Besoin : en plus du manifeste (qui est monté), un second rapport de caisse
-- (combien a rentré) listant les embarquements avec leur montant et la somme.
--
-- Décisions prises avec l'exploitant :
--
-- * Billet TIBUS : montant repris AUTOMATIQUEMENT de ReservationBus.price au
--   moment du scan (repli travelerPaidTotal). Aucune saisie au portillon, pas
--   de faute de frappe, et la recette colle à ce qui a réellement été vendu.
--   Le scan Tibus reste donc instantané, sans écran de confirmation.
--
-- * Billet HORS-TIBUS : montant SAISI ET OBLIGATOIRE (RAISE si NULL). Un
--   total amputé d'un billet se lit exactement comme un total complet et
--   fausse la caisse, alors que remplir un champ coûte une seconde.
--
-- * La colonne reste NULLABLE : les scans antérieurs à cette migration n'ont
--   pas de montant, et un billet Tibus peut ne pas avoir de prix en base.
--   embarquement_recette les compte séparément (without_amount) plutôt que
--   de les additionner comme des zéros.
--
-- ATTENTION — surcharge PostgREST : ajouter p_amount à
-- embarquement_scan_external crée une NOUVELLE signature. Sans DROP de
-- l'ancienne à 6 arguments, un appel à 6 paramètres correspondrait aux deux
-- (la 7e ayant un DEFAULT) et PostgREST répondrait "function is not unique"
-- — exactement le piège traité en migration 203. D'où le DROP explicite.
--
-- embarquement_list_manifest est DROP puis recréée : on ne peut pas changer
-- le RETURNS TABLE d'une fonction avec CREATE OR REPLACE.
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-23
-- (nom côté Supabase : embarquement_montant_et_recette).

ALTER TABLE public.embarquement_scans
  ADD COLUMN IF NOT EXISTS amount numeric(12, 2)
  CONSTRAINT embarquement_scans_amount_positive CHECK (amount IS NULL OR amount >= 0);

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
  v_amount numeric(12, 2);
  v_scan_id uuid;
BEGIN
  SELECT es.company_id, es.closed_at INTO v_company_id, v_closed
  FROM public.embarquement_sessions es WHERE es.id = p_session_id;
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

  IF v_rb_id IS NOT NULL THEN
    SELECT round(COALESCE(rb.price, rb."travelerPaidTotal")::numeric, 2)
    INTO v_amount
    FROM public."ReservationBus" rb WHERE rb.id = v_rb_id;
  END IF;

  INSERT INTO public.embarquement_scans
    (session_id, scanned_by, raw_payload, source, tibus_raw_result,
     matched_reservation_bus_id, passenger_name, ticket_number,
     origin_label, destination_label, status, amount)
  VALUES
    (p_session_id, v_user, p_raw_payload, 'tibus', v_result,
     v_rb_id, v_verify->>'passengerName', v_verify->>'bookingReference',
     v_verify#>>'{origin,name}', v_verify#>>'{destination,name}', v_status, v_amount)
  RETURNING id INTO v_scan_id;

  RETURN jsonb_build_object(
    'scanId', v_scan_id, 'status', v_status, 'amount', v_amount, 'verify', v_verify
  );
END;
$$;

DROP FUNCTION IF EXISTS public.embarquement_scan_external(uuid, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.embarquement_scan_external(
  p_session_id uuid,
  p_raw_payload text,
  p_passenger_name text,
  p_ticket_number text,
  p_origin_label text,
  p_destination_label text,
  p_amount numeric DEFAULT NULL
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
  SELECT es.company_id, es.closed_at INTO v_company_id, v_closed
  FROM public.embarquement_sessions es WHERE es.id = p_session_id;
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
  IF p_amount IS NULL THEN
    RAISE EXCEPTION 'montant requis';
  END IF;
  IF p_amount < 0 THEN
    RAISE EXCEPTION 'montant invalide';
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_ticket_number, '')), '') IS NOT NULL THEN
    SELECT count(*) INTO v_dup_count
    FROM public.embarquement_scans s
    WHERE s.session_id = p_session_id
      AND s.deleted_at IS NULL
      AND s.status = 'valid'
      AND s.ticket_number IS NOT NULL
      AND UPPER(BTRIM(s.ticket_number)) = UPPER(BTRIM(p_ticket_number));
    IF v_dup_count > 0 THEN
      v_status := 'duplicate';
    END IF;
  END IF;

  INSERT INTO public.embarquement_scans
    (session_id, scanned_by, raw_payload, source, passenger_name, ticket_number,
     origin_label, destination_label, status, amount)
  VALUES
    (p_session_id, v_user, p_raw_payload, 'external', BTRIM(p_passenger_name),
     NULLIF(BTRIM(COALESCE(p_ticket_number, '')), ''),
     NULLIF(BTRIM(COALESCE(p_origin_label, '')), ''),
     NULLIF(BTRIM(COALESCE(p_destination_label, '')), ''), v_status,
     round(p_amount, 2))
  RETURNING id INTO v_scan_id;

  RETURN jsonb_build_object('scanId', v_scan_id, 'status', v_status, 'amount', round(p_amount, 2));
END;
$$;

DROP FUNCTION IF EXISTS public.embarquement_list_manifest(uuid);

CREATE FUNCTION public.embarquement_list_manifest(p_session_id uuid)
RETURNS TABLE(
  id uuid, scanned_at timestamptz, source text, passenger_name text,
  ticket_number text, origin_label text, destination_label text, status text,
  amount numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT es.company_id INTO v_company_id
  FROM public.embarquement_sessions es
  WHERE es.id = p_session_id;

  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT s.id, s.scanned_at, s.source, s.passenger_name, s.ticket_number,
         s.origin_label, s.destination_label, s.status, s.amount
  FROM public.embarquement_scans s
  WHERE s.session_id = p_session_id AND s.deleted_at IS NULL
  ORDER BY s.scanned_at DESC;
END;
$$;

-- Rapport de recette : uniquement les scans VALIDES — un doublon ou un
-- billet refusé n'entre jamais en caisse.
CREATE OR REPLACE FUNCTION public.embarquement_recette(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_route_label text;
  v_bus_label text;
  v_opened_at timestamptz;
  v_closed_at timestamptz;
  v_lines jsonb := '[]'::jsonb;
  v_count integer;
  v_without_amount integer;
  v_total numeric(14, 2);
  v_total_tibus numeric(14, 2);
  v_total_external numeric(14, 2);
  v_count_tibus integer;
  v_count_external integer;
BEGIN
  SELECT es.company_id, es.route_label, es.bus_label, es.opened_at, es.closed_at
  INTO v_company_id, v_route_label, v_bus_label, v_opened_at, v_closed_at
  FROM public.embarquement_sessions es
  WHERE es.id = p_session_id;

  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE s.amount IS NULL),
         COALESCE(sum(s.amount), 0),
         COALESCE(sum(s.amount) FILTER (WHERE s.source = 'tibus'), 0),
         COALESCE(sum(s.amount) FILTER (WHERE s.source <> 'tibus'), 0),
         count(*) FILTER (WHERE s.source = 'tibus'),
         count(*) FILTER (WHERE s.source <> 'tibus')
  INTO v_count, v_without_amount, v_total, v_total_tibus, v_total_external,
       v_count_tibus, v_count_external
  FROM public.embarquement_scans s
  WHERE s.session_id = p_session_id AND s.deleted_at IS NULL AND s.status = 'valid';

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'scanned_at'), '[]'::jsonb)
  INTO v_lines
  FROM (
    SELECT jsonb_build_object(
             'id', s.id,
             'scanned_at', s.scanned_at,
             'source', s.source,
             'passenger_name', s.passenger_name,
             'ticket_number', s.ticket_number,
             'origin_label', s.origin_label,
             'destination_label', s.destination_label,
             'amount', s.amount
           ) AS x
    FROM public.embarquement_scans s
    WHERE s.session_id = p_session_id AND s.deleted_at IS NULL AND s.status = 'valid'
  ) q;

  RETURN jsonb_build_object(
    'session_id', p_session_id,
    'route_label', v_route_label,
    'bus_label', v_bus_label,
    'opened_at', v_opened_at,
    'closed_at', v_closed_at,
    'is_closed', v_closed_at IS NOT NULL,
    'boarded', v_count,
    'without_amount', v_without_amount,
    'total', v_total,
    'total_tibus', v_total_tibus,
    'total_external', v_total_external,
    'count_tibus', v_count_tibus,
    'count_external', v_count_external,
    'lines', v_lines,
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.embarquement_recette(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_list_manifest(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_scan_external(uuid, text, text, text, text, text, numeric) TO authenticated;
