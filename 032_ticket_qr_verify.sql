-- Lot 32: Vérification billets par QR — jeton sécurisé, embarquement, anti-fraude.

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "verifyToken" text,
  ADD COLUMN IF NOT EXISTS "boardedAt" timestamptz,
  ADD COLUMN IF NOT EXISTS "boardedBy" uuid REFERENCES "Users" (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS "boardingScanCount" integer NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS reservationbus_verify_token_idx
  ON "ReservationBus" ("verifyToken")
  WHERE "verifyToken" IS NOT NULL;

UPDATE "ReservationBus"
SET "verifyToken" = encode(gen_random_bytes(16), 'hex')
WHERE "verifyToken" IS NULL
  AND COALESCE("ticketStatus", 'issued') = 'issued';

CREATE OR REPLACE FUNCTION public.new_ticket_verify_token()
RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT encode(gen_random_bytes(16), 'hex');
$$;

CREATE OR REPLACE FUNCTION public.reservationbus_assign_verify_token()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW."verifyToken" IS NULL OR BTRIM(NEW."verifyToken") = '' THEN
    NEW."verifyToken" := public.new_ticket_verify_token();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reservationbus_verify_token_trg ON "ReservationBus";
CREATE TRIGGER reservationbus_verify_token_trg
  BEFORE INSERT ON "ReservationBus"
  FOR EACH ROW
  EXECUTE FUNCTION public.reservationbus_assign_verify_token();

CREATE OR REPLACE FUNCTION public.can_scan_ticket_boarding(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'controleur', 'vendeur']);
$$;

CREATE OR REPLACE FUNCTION public.verify_ticket_qr(
  p_reference text,
  p_token text DEFAULT NULL,
  p_record_boarding boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_ref text := UPPER(BTRIM(COALESCE(p_reference, '')));
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
  v_can_board boolean;
  v_staff_company_id uuid;
  v_payment_status text;
  v_status text;
  v_result text;
  v_valid boolean := false;
  v_message text;
BEGIN
  IF v_ref = '' THEN
    RETURN jsonb_build_object('valid', false, 'result', 'not_found', 'message', 'QR code vide');
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
    AND UPPER(BTRIM(p.reference)) = v_ref
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
    AND p_record_boarding THEN
    v_result := 'invalid';
    v_message := 'QR non sécurisé — jeton manquant pour embarquement';
  ELSE
    v_user_id := public.current_app_user_id();

    IF p_record_boarding THEN
      IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('valid', false, 'result', 'forbidden', 'message', 'Connexion requise');
      END IF;

      v_can_board := public.can_scan_ticket_boarding(v_company_id);
      IF NOT v_can_board THEN
        RETURN jsonb_build_object('valid', false, 'result', 'forbidden', 'message', 'Droits embarquement insuffisants');
      END IF;

      SELECT ur."companyId" INTO v_staff_company_id
      FROM "UserRoles" ur
      JOIN "Role" ro ON ro.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND ro.name IN ('owner', 'controleur', 'vendeur')
        AND ur."companyId" = v_company_id
      LIMIT 1;

      IF NOT public.is_super_admin() AND v_staff_company_id IS NULL THEN
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
        v_message := 'Billet valide — embarquement autorisé';
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
    'trip', jsonb_build_object(
      'departureTime', v_rb.departure_time,
      'arrivalTime', v_rb.arrival_time
    ),
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

DROP FUNCTION IF EXISTS public.seller_counter_sale(uuid, text, text, text, integer, double precision, double precision);
CREATE OR REPLACE FUNCTION public.seller_counter_sale(
  p_reservation_id uuid,
  p_passenger_name text,
  p_passenger_phone text DEFAULT NULL,
  p_seat_number text DEFAULT NULL,
  p_parcel_count integer DEFAULT 0,
  p_parcel_weight double precision DEFAULT 0,
  p_parcel_amount double precision DEFAULT 0
)
RETURNS TABLE(
  booking_id uuid,
  reference text,
  verify_token text,
  total_price double precision,
  currency text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid; v_company_id uuid; v_trajet_id uuid; v_depart uuid; v_final uuid;
  v_arret_id uuid; v_ticket_price double precision; v_parcel_amount double precision := COALESCE(p_parcel_amount, 0);
  v_total_price double precision; v_capacity integer; v_booked integer; v_payment_id uuid; v_reference text;
  v_currency text; v_seat text := NULLIF(BTRIM(COALESCE(p_seat_number, '')), '');
  v_booking_id uuid; v_caisse_id uuid; v_ticket_fcfa integer; v_parcel_fcfa integer; v_verify_token text;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF NULLIF(BTRIM(COALESCE(p_passenger_name, '')), '') IS NULL THEN RAISE EXCEPTION 'Nom voyageur requis'; END IF;

  SELECT r."capacity", r."trajetId" INTO v_capacity, v_trajet_id FROM "Reservations" r WHERE r.id = p_reservation_id;
  IF v_trajet_id IS NULL THEN RAISE EXCEPTION 'Depart introuvable'; END IF;
  v_company_id := public.reservation_company_id(p_reservation_id);

  IF NOT public.is_super_admin() AND NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ur."userId" = v_user_id AND ur."companyId" = v_company_id AND ro.name IN ('vendeur', 'owner')
  ) THEN RAISE EXCEPTION 'Vente directe reservee aux vendeurs de la compagnie'; END IF;

  SELECT pt.depart, pt.final INTO v_depart, v_final FROM "ProgrammationTrajets" pt WHERE pt.id = v_trajet_id;

  SELECT c.id INTO v_caisse_id FROM caisses_gares c
  WHERE c.gestionnaire_id = v_user_id AND c.gare_id = v_depart AND c.statut = 'ouverte'
  ORDER BY c.opened_at DESC LIMIT 1;
  IF v_caisse_id IS NULL THEN RAISE EXCEPTION 'Ouvrez votre caisse a la gare de depart avant une vente cash'; END IF;

  SELECT a.id, a.price INTO v_arret_id, v_ticket_price FROM "ProgrammationTrajetArrets" a
  WHERE a."trajetId" = v_trajet_id AND a."fromGareId" = v_depart AND a."toGareId" = v_final LIMIT 1;
  IF v_arret_id IS NULL THEN RAISE EXCEPTION 'Segment introuvable'; END IF;

  SELECT COUNT(*)::integer INTO v_booked FROM "ReservationBus" rb JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb."reservationId" = p_reservation_id AND rb."type" = 'voyage'
    AND COALESCE(rb."ticketStatus", 'issued') = 'issued' AND (rb."isReservation" = false OR p."txID" IS NOT NULL);
  IF v_booked >= v_capacity THEN RAISE EXCEPTION 'Plus de places disponibles'; END IF;

  IF v_seat IS NOT NULL AND EXISTS (
    SELECT 1 FROM "ReservationBus" rb JOIN "Payment" p ON p.id = rb."paymentId"
    WHERE rb."reservationId" = p_reservation_id AND rb."seatNumber" = v_seat AND rb."type" = 'voyage'
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued' AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
  ) THEN RAISE EXCEPTION 'Siege deja vendu'; END IF;

  SELECT COALESCE(cn.currency, 'XOF') INTO v_currency FROM "Companies" c
  LEFT JOIN "Countries" cn ON cn.id = c."countryId" WHERE c.id = v_company_id;

  v_total_price := v_ticket_price + GREATEST(v_parcel_amount, 0);
  v_ticket_fcfa := public.fcfa_to_int(v_ticket_price);
  v_parcel_fcfa := public.fcfa_to_int(v_parcel_amount);
  v_reference := 'TB-' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', '') FROM 1 FOR 8));

  INSERT INTO "Payment" (reference, phone, amount, "txID")
  VALUES (v_reference, COALESCE(NULLIF(BTRIM(p_passenger_phone), ''), '0000000000'), v_total_price, 'counter-' || gen_random_uuid()::text)
  RETURNING id INTO v_payment_id;

  INSERT INTO "ReservationBus" (
    type, "createdBy", "reservationId", "arretId", price, "isReservation", "paymentId",
    "exceedColisAmount", "passengerName", "seatNumber", "parcelCount", "parcelWeight", "parcelAmount", "saleChannel"
  ) VALUES (
    'voyage', v_user_id, p_reservation_id, v_arret_id, v_total_price, false, v_payment_id,
    NULLIF(v_parcel_amount, 0), BTRIM(p_passenger_name), v_seat,
    NULLIF(GREATEST(COALESCE(p_parcel_count, 0), 0), 0), NULLIF(GREATEST(COALESCE(p_parcel_weight, 0), 0), 0),
    NULLIF(v_parcel_amount, 0), 'counter_sale'
  ) RETURNING id, "verifyToken" INTO v_booking_id, v_verify_token;

  PERFORM public.record_counter_sale_cash_movements(v_caisse_id, v_booking_id, v_ticket_fcfa, v_parcel_fcfa, v_user_id);

  booking_id := v_booking_id;
  reference := v_reference;
  verify_token := v_verify_token;
  total_price := v_total_price;
  currency := COALESCE(v_currency, 'XOF');
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_ticket_qr(text, text, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_scan_ticket_boarding(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seller_counter_sale(uuid, text, text, text, integer, double precision, double precision) TO authenticated;
