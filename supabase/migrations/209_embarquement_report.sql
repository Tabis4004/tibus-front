-- 209 — embarquement_report(p_session_id) : les chiffres de fin de session
--
-- Phase 4 du plan (§4 et §9). Trois chiffres portent le rapport — embarqués,
-- places disponibles, no-show — le reste est du détail de contrôle.
--
-- Choix assumés :
--
-- * Consultable À TOUT MOMENT, pas seulement après clôture (le plan disait
--   "calculable uniquement après closed_at") : au portillon, connaître les
--   places restantes pendant l'embarquement est précisément l'usage. Le
--   champ is_closed dit si les chiffres sont figés ; l'écran l'affiche.
--
-- * "Embarqués" = scans valides de la session, pas ReservationBus.boardedAt.
--   Un voyageur hors-Tibus ajouté au manifeste n'existe pas dans
--   ReservationBus ; compter les scans est la seule mesure qui couvre les
--   deux origines, et c'est déjà ce qu'affiche le compteur de l'écran de
--   scan (cohérence entre les deux écrans).
--
-- * No-show NOMINATIF pour un départ Tibus seulement : billets non annulés
--   du départ dont boardedAt est vide, nommés via ReservationBus +
--   Payment.reference (la référence TB-XXXXXXXX vit sur Payment, pas sur
--   ReservationBus). Hors-Tibus, aucune liste d'attendus n'existe en base :
--   no_show y vaut capacité − embarqués, donc EXACTEMENT seats_available.
--   C'est pourquoi no_show_basis distingue 'nominatif' de 'capacite' — sans
--   ça l'écran afficherait deux fois le même nombre sous deux noms
--   différents, et un exploitant lirait "59 no-show" sur un bus où personne
--   n'était attendu nominativement.
--
-- * Capacité : Reservations.capacity pour un départ Tibus, sinon
--   embarquement_sessions.capacity_declared. Null si aucune des deux n'a été
--   renseignée — places disponibles et no-show sont alors null, jamais 0
--   (un zéro inventé se lit comme "bus plein").
--
-- Colonnes qualifiées partout (es./s./rb./p.) — cf. migration 208, où un
-- "id" nu rendait embarquement_list_manifest inutilisable.

CREATE OR REPLACE FUNCTION public.embarquement_report(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_reservation_id uuid;
  v_capacity_declared integer;
  v_route_label text;
  v_bus_label text;
  v_opened_at timestamptz;
  v_closed_at timestamptz;
  v_capacity integer;
  v_capacity_source text;
  v_total integer;
  v_boarded integer;
  v_boarded_tibus integer;
  v_boarded_external integer;
  v_duplicates integer;
  v_refused integer;
  v_expected integer;
  v_expected_boarded integer;
  v_no_show integer;
  v_no_show_basis text;
  v_no_show_list jsonb := '[]'::jsonb;
  v_seats_available integer;
BEGIN
  SELECT es.company_id, es.reservation_id, es.capacity_declared,
         es.route_label, es.bus_label, es.opened_at, es.closed_at
  INTO v_company_id, v_reservation_id, v_capacity_declared,
       v_route_label, v_bus_label, v_opened_at, v_closed_at
  FROM public.embarquement_sessions es
  WHERE es.id = p_session_id;

  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE s.status = 'valid'),
         count(*) FILTER (WHERE s.status = 'valid' AND s.source = 'tibus'),
         count(*) FILTER (WHERE s.status = 'valid' AND s.source <> 'tibus'),
         count(*) FILTER (WHERE s.status = 'duplicate'),
         count(*) FILTER (WHERE s.status IN ('invalid', 'wrong_session'))
  INTO v_total, v_boarded, v_boarded_tibus, v_boarded_external, v_duplicates, v_refused
  FROM public.embarquement_scans s
  WHERE s.session_id = p_session_id AND s.deleted_at IS NULL;

  IF v_reservation_id IS NOT NULL THEN
    SELECT r.capacity INTO v_capacity
    FROM public."Reservations" r WHERE r.id = v_reservation_id;
    IF v_capacity IS NOT NULL THEN v_capacity_source := 'reservation'; END IF;
  END IF;
  IF v_capacity IS NULL AND v_capacity_declared IS NOT NULL THEN
    v_capacity := v_capacity_declared;
    v_capacity_source := 'declaree';
  END IF;

  IF v_capacity IS NOT NULL THEN
    v_seats_available := greatest(v_capacity - v_boarded, 0);
  END IF;

  IF v_reservation_id IS NOT NULL THEN
    SELECT count(*), count(*) FILTER (WHERE rb."boardedAt" IS NOT NULL)
    INTO v_expected, v_expected_boarded
    FROM public."ReservationBus" rb
    WHERE rb."reservationId" = v_reservation_id
      AND rb."cancelledAt" IS NULL
      AND coalesce(rb."ticketStatus", '') <> 'cancelled';

    v_no_show := greatest(coalesce(v_expected, 0) - coalesce(v_expected_boarded, 0), 0);
    v_no_show_basis := 'nominatif';

    SELECT coalesce(jsonb_agg(x ORDER BY x->>'passenger_name'), '[]'::jsonb)
    INTO v_no_show_list
    FROM (
      SELECT jsonb_build_object(
               'passenger_name', rb."passengerName",
               'seat_number', rb."seatNumber",
               'reference', p.reference
             ) AS x
      FROM public."ReservationBus" rb
      LEFT JOIN public."Payment" p ON p.id = rb."paymentId"
      WHERE rb."reservationId" = v_reservation_id
        AND rb."cancelledAt" IS NULL
        AND coalesce(rb."ticketStatus", '') <> 'cancelled'
        AND rb."boardedAt" IS NULL
    ) q;
  ELSIF v_capacity IS NOT NULL THEN
    v_no_show := v_seats_available;
    v_no_show_basis := 'capacite';
  END IF;

  RETURN jsonb_build_object(
    'session_id', p_session_id,
    'route_label', v_route_label,
    'bus_label', v_bus_label,
    'opened_at', v_opened_at,
    'closed_at', v_closed_at,
    'is_closed', v_closed_at IS NOT NULL,
    'is_tibus', v_reservation_id IS NOT NULL,
    'capacity', v_capacity,
    'capacity_source', v_capacity_source,
    'total_scans', v_total,
    'boarded', v_boarded,
    'boarded_tibus', v_boarded_tibus,
    'boarded_external', v_boarded_external,
    'duplicates', v_duplicates,
    'refused', v_refused,
    'expected', v_expected,
    'seats_available', v_seats_available,
    'no_show', v_no_show,
    'no_show_basis', v_no_show_basis,
    'no_show_list', v_no_show_list,
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.embarquement_report(uuid) TO authenticated;
