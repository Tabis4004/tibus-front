-- Lot 33b: Correctif vérification manuelle — staff embarquement sans jeton QR.

CREATE OR REPLACE FUNCTION public.can_scan_ticket_boarding(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'controleur', 'vendeur']);
$$;

DROP FUNCTION IF EXISTS public.verify_ticket_qr(text);
DROP FUNCTION IF EXISTS public.verify_ticket_qr(text, text);
DROP FUNCTION IF EXISTS public.verify_ticket_qr(text, text, boolean);
DROP FUNCTION IF EXISTS public.verify_ticket_qr(text, text, boolean, boolean);

CREATE OR REPLACE FUNCTION public.normalize_ticket_reference(p_reference text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_ref text := UPPER(REGEXP_REPLACE(BTRIM(COALESCE(p_reference, '')), '\s+', '', 'g'));
BEGIN
  IF v_ref = '' THEN RETURN ''; END IF;
  IF v_ref NOT LIKE 'TB-%' THEN
    v_ref := 'TB-' || REGEXP_REPLACE(v_ref, '^TB-?', '', 'i');
  END IF;
  RETURN v_ref;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_ticket_qr(
  p_reference text,
  p_token text DEFAULT NULL,
  p_record_boarding boolean DEFAULT false,
  p_manual_reference boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_ref text := public.normalize_ticket_reference(p_reference);
  v_rb record;
  v_company_id uuid;
  v_company_name text;
  v_currency text;
  v_origin_city text;
  v_dest_city text;
  v_origin_name text;
  v_dest_name text;
  v_bus_name text;
  v_bus_plate text;
  v_staff_boarding boolean := false;
  v_payment_status text;
  v_status text;
  v_result text;
  v_valid boolean := false;
  v_message text;
BEGIN
  IF v_ref = '' THEN
    RETURN jsonb_build_object('valid', false, 'result', 'not_found', 'message', 'Numéro de billet vide');
  END IF;

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
    p.reference,
    p.phone,
    p.amount,
    p."txID",
    r.date AS departure_time,
    g_depart.name AS origin_name,
    g_final.name AS dest_name,
    c_depart.city AS origin_city,
    c_final.city AS dest_city,
    co.id AS company_id,
    co.name AS company_name,
    country.currency
  INTO v_rb
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g_depart ON g_depart.id = pt.depart
  JOIN "Gares" g_final ON g_final.id = pt.final
  LEFT JOIN "Cities" c_depart ON c_depart.id = g_depart."cityId"
  LEFT JOIN "Cities" c_final ON c_final.id = g_final."cityId"
  JOIN "Companies" co ON co.id = g_depart."companyId"
  LEFT JOIN "Countries" country ON country.id = co."countryId"
  WHERE rb."type" = 'voyage'
    AND public.normalize_ticket_reference(p.reference) = v_ref
  LIMIT 1;

  IF v_rb.id IS NULL THEN
    RETURN jsonb_build_object(
      'valid', false,
      'result', 'not_found',
      'message', 'Billet introuvable ou contrefait',
      'bookingReference', v_ref
    );
  END IF;

  v_company_id := v_rb.company_id;
  v_company_name := v_rb.company_name;
  v_currency := COALESCE(v_rb.currency, 'XOF');
  v_origin_city := COALESCE(v_rb.origin_city, v_rb.origin_name);
  v_dest_city := COALESCE(v_rb.dest_city, v_rb.dest_name);
  v_origin_name := v_rb.origin_name;
  v_dest_name := v_rb.dest_name;

  SELECT b.model, b."registrationNumber"
  INTO v_bus_name, v_bus_plate
  FROM "ProgrammationBus" pb
  JOIN "Bus" b ON b.id = pb."busId"
  WHERE pb."trajetId" = (SELECT r."trajetId" FROM "Reservations" r WHERE r.id = v_rb."reservationId" LIMIT 1)
    AND pb."isActive" = true
  LIMIT 1;

  v_user_id := public.current_app_user_id();
  v_staff_boarding := COALESCE(p_record_boarding, false)
    AND v_user_id IS NOT NULL
    AND public.can_scan_ticket_boarding(v_company_id);

  IF COALESCE(v_rb."ticketStatus", 'issued') <> 'issued' THEN
    v_result := 'cancelled';
    v_message := 'Billet annulé';
  ELSIF v_rb."isReservation" AND v_rb."txID" IS NULL THEN
    v_result := 'unpaid';
    v_message := 'Réservation non payée';
  ELSIF v_rb."verifyToken" IS NOT NULL
    AND NULLIF(BTRIM(COALESCE(p_token, '')), '') IS NOT NULL
    AND BTRIM(p_token) <> v_rb."verifyToken" THEN
    v_result := 'invalid';
    v_message := 'Jeton QR invalide — billet suspect';
  ELSIF v_rb."verifyToken" IS NOT NULL
    AND NULLIF(BTRIM(COALESCE(p_token, '')), '') IS NULL
    AND COALESCE(p_record_boarding, false)
    AND NOT v_staff_boarding THEN
    v_result := 'invalid';
    v_message := 'QR non sécurisé — jeton manquant pour embarquement';
  ELSIF COALESCE(p_manual_reference, false) AND NOT COALESCE(p_record_boarding, false) THEN
    RETURN jsonb_build_object('valid', false, 'result', 'forbidden', 'message', 'Vérification manuelle réservée à l''embarquement');
  ELSIF COALESCE(p_record_boarding, false) OR COALESCE(p_manual_reference, false) THEN
    IF v_user_id IS NULL THEN
      RETURN jsonb_build_object('valid', false, 'result', 'forbidden', 'message', 'Connexion requise');
    END IF;

    IF NOT public.can_scan_ticket_boarding(v_company_id) THEN
      RETURN jsonb_build_object('valid', false, 'result', 'forbidden', 'message', 'Droits embarquement insuffisants');
    END IF;

    IF NOT public.is_super_admin()
      AND NOT public.has_company_role(v_company_id, ARRAY['owner', 'controleur', 'vendeur']) THEN
      v_result := 'wrong_company';
      v_message := 'Ce billet appartient à une autre compagnie';
    ELSIF v_rb."boardedAt" IS NOT NULL THEN
      v_result := 'duplicate';
      v_message := 'Billet déjà scanné à l''embarquement';
      v_valid := false;
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

  IF v_rb.departure_time < now() AND v_valid AND v_result = 'valid' THEN
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
    'passengerName', COALESCE(v_rb."passengerName", ''),
    'passengerPhone', CASE WHEN v_rb.phone = '0000000000' THEN NULL ELSE v_rb.phone END,
    'seatNumber', v_rb."seatNumber",
    'status', v_status,
    'paymentStatus', v_payment_status,
    'totalPrice', COALESCE(v_rb.price, v_rb.amount, 0),
    'currency', v_currency,
    'createdAt', v_rb."createdAt",
    'companyId', v_company_id,
    'companyName', v_company_name,
    'boardedAt', v_rb."boardedAt",
    'boardingScanCount', COALESCE(v_rb."boardingScanCount", 0),
    'trip', jsonb_build_object('departureTime', v_rb.departure_time, 'arrivalTime', NULL),
    'origin', jsonb_build_object('name', v_origin_name),
    'destination', jsonb_build_object('name', v_dest_name),
    'originLoc', jsonb_build_object('city', v_origin_city),
    'destLoc', jsonb_build_object('city', v_dest_city),
    'bus', CASE
      WHEN v_bus_name IS NULL THEN NULL
      ELSE jsonb_build_object('name', v_bus_name, 'plateNumber', v_bus_plate)
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.normalize_ticket_reference(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_ticket_qr(text, text, boolean, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_scan_ticket_boarding(uuid) TO authenticated;
