-- Lot 117: Garde inter-compagnies au scan embarquement.
-- Contrôle gare de départ (gare_id) puis repli compagnie émettrice (compagnie_id).

CREATE OR REPLACE FUNCTION public.resolve_scanner_company_id(p_scanner_company_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_super_admin() THEN
    RETURN NULL;
  END IF;

  IF p_scanner_company_id IS NOT NULL
    AND public.can_scan_ticket_boarding(p_scanner_company_id) THEN
    RETURN p_scanner_company_id;
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.ticket_matches_scanner_company(
  p_reservation_id uuid,
  p_scanner_company_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gare_company_id uuid;
  v_ticket_company_id uuid;
BEGIN
  IF p_scanner_company_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT g."companyId"
  INTO v_gare_company_id
  FROM "Reservations" r
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  LEFT JOIN "Gares" g ON g.id = pt.depart
  WHERE r.id = p_reservation_id;

  IF v_gare_company_id IS NOT NULL AND v_gare_company_id = p_scanner_company_id THEN
    RETURN true;
  END IF;

  v_ticket_company_id := public.reservation_company_id(p_reservation_id);
  IF v_ticket_company_id IS NOT NULL AND v_ticket_company_id = p_scanner_company_id THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.ticket_scan_wrong_company_payload(
  p_reference text,
  p_booking_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'valid', false,
    'result', 'wrong_company',
    'message', 'wrong_company',
    'bookingId', p_booking_id,
    'bookingReference', COALESCE(p_reference, ''),
    'passengerName', '',
    'passengerPhone', NULL,
    'seatNumber', NULL,
    'status', 'cancelled',
    'paymentStatus', 'pending',
    'totalPrice', 0,
    'currency', 'XOF',
    'trip', NULL,
    'origin', NULL,
    'destination', NULL,
    'originLoc', NULL,
    'destLoc', NULL,
    'bus', NULL
  );
$$;

DROP FUNCTION IF EXISTS public.verify_ticket_qr(text, text, boolean, boolean);

CREATE OR REPLACE FUNCTION public.verify_ticket_qr(
  p_reference text,
  p_token text DEFAULT NULL,
  p_record_boarding boolean DEFAULT false,
  p_manual_reference boolean DEFAULT false,
  p_scanner_company_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_ref text;
  v_fragment text;
  v_rb record;
  v_company_id uuid;
  v_company_name text;
  v_currency text := 'XOF';
  v_origin_name text;
  v_dest_name text;
  v_bus_name text;
  v_bus_plate text;
  v_departure_time timestamptz;
  v_staff_boarding boolean := false;
  v_payment_status text;
  v_status text;
  v_result text := 'not_found';
  v_valid boolean := false;
  v_message text := 'Billet introuvable ou contrefait';
  v_scanner_company_id uuid;
BEGIN
  v_ref := public.normalize_ticket_reference(p_reference);

  IF v_ref = '' THEN
    RETURN jsonb_build_object(
      'valid', false, 'result', 'not_found', 'message', 'Numéro de billet vide',
      'bookingReference', '', 'passengerName', '', 'totalPrice', 0, 'currency', 'XOF',
      'paymentStatus', 'pending', 'status', 'cancelled'
    );
  END IF;

  v_fragment := REPLACE(v_ref, 'TB-', '');

  SELECT
    rb.id,
    rb."reservationId",
    rb."createdAt",
    rb.price,
    rb."isReservation",
    rb."passengerName",
    rb."seatNumber",
    rb."ticketStatus",
    rb."verifyToken",
    rb."boardedAt",
    rb."boardingScanCount",
    rb."onBoardAt",
    rb."onBoardScanCount",
    p.reference,
    p.phone,
    p.amount,
    p."txID"
  INTO v_rb
  FROM "Payment" p
  JOIN "ReservationBus" rb ON rb."paymentId" = p.id
  WHERE UPPER(BTRIM(p.reference)) LIKE '%' || v_fragment || '%'
  ORDER BY rb."createdAt" DESC
  LIMIT 1;

  IF v_rb.id IS NULL THEN
    RETURN jsonb_build_object(
      'valid', false,
      'result', 'not_found',
      'message', 'Aucun billet ne correspond à cette référence',
      'bookingReference', v_ref,
      'passengerName', '',
      'totalPrice', 0,
      'currency', 'XOF',
      'paymentStatus', 'pending',
      'status', 'cancelled'
    );
  END IF;

  v_company_id := public.reservation_company_id(v_rb."reservationId");
  v_scanner_company_id := public.resolve_scanner_company_id(p_scanner_company_id);

  IF NOT public.is_super_admin() THEN
    IF v_scanner_company_id IS NULL
      OR NOT public.ticket_matches_scanner_company(v_rb."reservationId", v_scanner_company_id) THEN
      RETURN public.ticket_scan_wrong_company_payload(v_rb.reference, v_rb.id);
    END IF;
  END IF;

  SELECT c.name, COALESCE(country.currency, 'XOF')
  INTO v_company_name, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" country ON country.id = c."countryId"
  WHERE c.id = v_company_id;

  SELECT r.date INTO v_departure_time
  FROM "Reservations" r WHERE r.id = v_rb."reservationId";

  SELECT g_depart.name, g_final.name
  INTO v_origin_name, v_dest_name
  FROM "Reservations" r
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  LEFT JOIN "Gares" g_depart ON g_depart.id = pt.depart
  LEFT JOIN "Gares" g_final ON g_final.id = pt.final
  WHERE r.id = v_rb."reservationId";

  SELECT b.model, b."registrationNumber"
  INTO v_bus_name, v_bus_plate
  FROM "Reservations" r
  JOIN "ProgrammationBus" pb ON pb."trajetId" = r."trajetId" AND pb."isActive" = true
  JOIN "Bus" b ON b.id = pb."busId"
  WHERE r.id = v_rb."reservationId"
  LIMIT 1;

  v_user_id := public.current_app_user_id();
  v_staff_boarding := COALESCE(p_record_boarding, false)
    AND v_user_id IS NOT NULL
    AND public.can_scan_ticket_boarding(v_scanner_company_id);

  IF v_rb."onBoardAt" IS NOT NULL THEN
    v_result := 'on_board';
    v_message := 'already_on_board';
    v_valid := false;
  ELSIF COALESCE(v_rb."ticketStatus", 'issued') <> 'issued' THEN
    v_result := 'cancelled';
    v_message := 'Billet annulé';
  ELSIF v_rb."isReservation" AND v_rb."txID" IS NULL THEN
    v_result := 'unpaid';
    v_message := 'Réservation non payée — embarquement refusé';
  ELSIF v_rb."verifyToken" IS NOT NULL
    AND NULLIF(BTRIM(COALESCE(p_token, '')), '') IS NOT NULL
    AND BTRIM(p_token) <> v_rb."verifyToken" THEN
    v_result := 'invalid';
    v_message := 'Jeton QR invalide — billet suspect';
  ELSIF v_rb."verifyToken" IS NOT NULL
    AND NULLIF(BTRIM(COALESCE(p_token, '')), '') IS NULL
    AND COALESCE(p_record_boarding, false)
    AND NOT COALESCE(p_manual_reference, false)
    AND NOT v_staff_boarding THEN
    v_result := 'invalid';
    v_message := 'QR non sécurisé — jeton manquant pour embarquement';
  ELSIF COALESCE(p_record_boarding, false) OR COALESCE(p_manual_reference, false) THEN
    IF v_user_id IS NULL THEN
      v_result := 'forbidden';
      v_message := 'Connexion requise pour l''embarquement';
    ELSIF NOT public.can_scan_ticket_boarding(v_scanner_company_id) THEN
      v_result := 'forbidden';
      v_message := 'Droits embarquement insuffisants';
    ELSIF v_rb."boardedAt" IS NOT NULL THEN
      v_result := 'duplicate';
      v_message := 'Billet déjà scanné à l''embarquement';
    ELSE
      UPDATE "ReservationBus"
      SET
        "boardedAt" = now(),
        "boardedBy" = v_user_id,
        "boardingScanCount" = COALESCE("boardingScanCount", 0) + 1
      WHERE id = v_rb.id
      RETURNING "boardedAt" INTO v_rb."boardedAt";

      v_result := 'valid';
      v_valid := true;
      v_message := CASE
        WHEN COALESCE(p_manual_reference, false) THEN 'Billet valide — vérification manuelle'
        ELSE 'Billet valide — embarquement autorisé'
      END;
    END IF;
  ELSE
    v_result := 'valid';
    v_valid := true;
    v_message := 'Billet authentique';
    IF v_rb."boardedAt" IS NOT NULL THEN
      v_result := 'duplicate';
      v_message := 'Billet déjà utilisé à l''embarquement';
      v_valid := false;
    END IF;
  END IF;

  IF v_rb."isReservation" = false OR v_rb."txID" IS NOT NULL THEN
    v_payment_status := 'paid';
  ELSE
    v_payment_status := 'pending';
  END IF;

  IF v_departure_time < now() AND v_valid AND v_result = 'valid' THEN
    v_status := 'collected';
  ELSIF v_valid THEN
    v_status := 'confirmed';
  ELSIF v_rb."isReservation" AND v_rb."txID" IS NULL THEN
    v_status := 'pending_payment';
  ELSIF COALESCE(v_rb."ticketStatus", 'issued') <> 'issued' THEN
    v_status := 'cancelled';
  ELSE
    v_status := 'confirmed';
  END IF;

  RETURN jsonb_build_object(
    'valid', v_valid,
    'result', v_result,
    'message', v_message,
    'bookingId', v_rb.id,
    'bookingReference', v_rb.reference,
    'passengerName', COALESCE(NULLIF(BTRIM(v_rb."passengerName"), ''), 'Voyageur'),
    'passengerPhone', CASE WHEN v_rb.phone = '0000000000' THEN NULL ELSE v_rb.phone END,
    'seatNumber', v_rb."seatNumber",
    'status', v_status,
    'paymentStatus', v_payment_status,
    'totalPrice', COALESCE(v_rb.price, v_rb.amount, 0),
    'currency', v_currency,
    'createdAt', v_rb."createdAt",
    'companyId', v_company_id,
    'companyName', COALESCE(v_company_name, 'Compagnie'),
    'boardedAt', v_rb."boardedAt",
    'boardingScanCount', COALESCE(v_rb."boardingScanCount", 0),
    'onBoardAt', v_rb."onBoardAt",
    'onBoardScanCount', COALESCE(v_rb."onBoardScanCount", 0),
    'trip', CASE WHEN v_departure_time IS NULL THEN NULL
      ELSE jsonb_build_object('departureTime', v_departure_time, 'arrivalTime', NULL) END,
    'origin', CASE WHEN v_origin_name IS NULL THEN NULL ELSE jsonb_build_object('name', v_origin_name) END,
    'destination', CASE WHEN v_dest_name IS NULL THEN NULL ELSE jsonb_build_object('name', v_dest_name) END,
    'originLoc', CASE WHEN v_origin_name IS NULL THEN NULL ELSE jsonb_build_object('city', v_origin_name) END,
    'destLoc', CASE WHEN v_dest_name IS NULL THEN NULL ELSE jsonb_build_object('city', v_dest_name) END,
    'bus', CASE WHEN v_bus_name IS NULL THEN NULL
      ELSE jsonb_build_object('name', v_bus_name, 'plateNumber', v_bus_plate) END
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'valid', false,
      'result', 'error',
      'message', 'Erreur serveur : ' || SQLERRM,
      'bookingReference', COALESCE(v_ref, public.normalize_ticket_reference(p_reference)),
      'passengerName', '',
      'totalPrice', 0,
      'currency', 'XOF',
      'paymentStatus', 'pending',
      'status', 'cancelled'
    );
END;
$$;

DROP FUNCTION IF EXISTS public.confirm_passenger_on_board(text);

CREATE OR REPLACE FUNCTION public.confirm_passenger_on_board(
  p_reference text,
  p_scanner_company_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ref text := public.normalize_ticket_reference(p_reference);
  v_fragment text;
  v_rb record;
  v_scanner_company_id uuid;
BEGIN
  IF v_ref = '' THEN
    RETURN public.ticket_scan_wrong_company_payload('', NULL);
  END IF;

  v_fragment := REPLACE(v_ref, 'TB-', '');

  SELECT rb.id, rb."reservationId", rb."onBoardAt", p.reference
  INTO v_rb
  FROM "Payment" p
  JOIN "ReservationBus" rb ON rb."paymentId" = p.id
  WHERE UPPER(BTRIM(p.reference)) LIKE '%' || v_fragment || '%'
  ORDER BY rb."createdAt" DESC
  LIMIT 1;

  IF v_rb.id IS NULL THEN
    RETURN jsonb_build_object(
      'valid', false,
      'result', 'not_found',
      'message', 'Aucun billet ne correspond à cette référence',
      'bookingReference', v_ref,
      'passengerName', '',
      'totalPrice', 0,
      'currency', 'XOF',
      'paymentStatus', 'pending',
      'status', 'cancelled'
    );
  END IF;

  v_scanner_company_id := public.resolve_scanner_company_id(p_scanner_company_id);

  IF NOT public.is_super_admin() THEN
    IF v_scanner_company_id IS NULL
      OR NOT public.ticket_matches_scanner_company(v_rb."reservationId", v_scanner_company_id) THEN
      RETURN public.ticket_scan_wrong_company_payload(v_rb.reference, v_rb.id);
    END IF;
  END IF;

  IF v_rb."onBoardAt" IS NOT NULL THEN
    RETURN public.verify_ticket_qr(v_rb.reference, NULL, true, true, p_scanner_company_id);
  END IF;

  UPDATE "ReservationBus"
  SET
    "onBoardAt" = now(),
    "onBoardBy" = public.current_app_user_id(),
    "onBoardScanCount" = COALESCE("onBoardScanCount", 0) + 1
  WHERE id = v_rb.id;

  RETURN public.verify_ticket_qr(v_rb.reference, NULL, true, true, p_scanner_company_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_scanner_company_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_matches_scanner_company(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_ticket_qr(text, text, boolean, boolean, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_passenger_on_board(text, uuid) TO authenticated;
