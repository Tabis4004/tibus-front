-- =============================================================================
-- Tibus 083 — API partenaire : réservations + webhooks de vente
-- =============================================================================
-- PRÉREQUIS : 082_partner_itinerary_api.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS "PartnerBookings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "externalSystem" text NOT NULL DEFAULT 'default',
  "externalBookingId" text NOT NULL,
  "externalDepartureId" text NOT NULL,
  "reservationId" uuid NOT NULL REFERENCES "Reservations" ("id") ON DELETE CASCADE,
  "bookingId" uuid NOT NULL REFERENCES "ReservationBus" ("id") ON DELETE CASCADE,
  "paymentId" uuid NOT NULL REFERENCES "Payment" ("id") ON DELETE CASCADE,
  "status" text NOT NULL DEFAULT 'confirmed'
    CHECK ("status" IN ('hold', 'confirmed', 'cancelled')),
  "holdExpiresAt" timestamptz,
  "externalPaymentRef" text,
  "payload" jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("companyId", "externalSystem", "externalBookingId")
);

CREATE INDEX IF NOT EXISTS "PartnerBookings_reservation_idx"
  ON "PartnerBookings" ("reservationId");

CREATE TABLE IF NOT EXISTS "PartnerWebhookEndpoints" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "externalSystem" text NOT NULL DEFAULT 'default',
  "url" text NOT NULL,
  "secret" text NOT NULL,
  "events" text[] NOT NULL DEFAULT ARRAY['booking.created', 'booking.confirmed', 'booking.cancelled'],
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "createdBy" uuid REFERENCES "Users" ("id") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "PartnerWebhookDeliveries" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "endpointId" uuid NOT NULL REFERENCES "PartnerWebhookEndpoints" ("id") ON DELETE CASCADE,
  "eventType" text NOT NULL,
  "payload" jsonb NOT NULL,
  "responseStatus" integer,
  "responseBody" text,
  "deliveredAt" timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.count_partner_holds(p_reservation_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT COUNT(*)::integer
  FROM "PartnerBookings" pb
  WHERE pb."reservationId" = p_reservation_id
    AND pb."status" = 'hold'
    AND (pb."holdExpiresAt" IS NULL OR pb."holdExpiresAt" > now());
$$;

CREATE OR REPLACE FUNCTION public.get_reservation_availability(p_reservation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_capacity integer;
  v_booked integer;
  v_holds integer;
  v_occupied text[];
BEGIN
  SELECT COALESCE(r.capacity, pt.capacity, 45)
  INTO v_capacity
  FROM "Reservations" r
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  WHERE r.id = p_reservation_id;

  IF v_capacity IS NULL THEN
    RAISE EXCEPTION 'Depart introuvable';
  END IF;

  v_booked := public.count_issued_seats(p_reservation_id);
  v_holds := public.count_partner_holds(p_reservation_id);
  v_occupied := public.get_occupied_seats(p_reservation_id);

  RETURN jsonb_build_object(
    'reservationId', p_reservation_id,
    'totalSeats', v_capacity,
    'seatsBooked', v_booked,
    'seatsHeld', v_holds,
    'seatsAvailable', GREATEST(v_capacity - v_booked - v_holds, 0),
    'occupiedSeats', to_jsonb(v_occupied)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_company_owner_user_id(p_company_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT ur."userId"
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."companyId" = p_company_id
    AND r.name = 'owner'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.partner_create_booking(
  p_company_id uuid,
  p_external_system text,
  p_external_departure_id text,
  p_external_booking_id text,
  p_passenger_name text,
  p_passenger_phone text DEFAULT NULL,
  p_seat_number text DEFAULT NULL,
  p_mode text DEFAULT 'sale',
  p_hold_minutes integer DEFAULT 15,
  p_external_payment_ref text DEFAULT NULL,
  p_price_override double precision DEFAULT NULL,
  p_payload jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_reservation_id uuid;
  v_owner_user_id uuid;
  v_capacity integer;
  v_booked integer;
  v_holds integer;
  v_trajet_id uuid;
  v_arret_id uuid;
  v_price double precision;
  v_payment_id uuid;
  v_booking_id uuid;
  v_reference text;
  v_tx_id text;
  v_partner_booking_id uuid;
  v_mode text;
  v_hold_expires timestamptz;
  v_is_reservation boolean;
BEGIN
  v_mode := lower(COALESCE(NULLIF(trim(p_mode), ''), 'sale'));
  IF v_mode NOT IN ('sale', 'hold') THEN
    RAISE EXCEPTION 'Mode invalide (sale ou hold)';
  END IF;

  SELECT m."reservationId", m."trajetId"
  INTO v_reservation_id, v_trajet_id
  FROM "PartnerDepartureMappings" m
  WHERE m."companyId" = p_company_id
    AND m."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND m."externalDepartureId" = trim(p_external_departure_id)
    AND m."isActive" = true
  LIMIT 1;

  IF v_reservation_id IS NULL THEN
    RAISE EXCEPTION 'Depart externe introuvable';
  END IF;

  IF EXISTS (
    SELECT 1 FROM "PartnerBookings" pb
    WHERE pb."companyId" = p_company_id
      AND pb."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
      AND pb."externalBookingId" = trim(p_external_booking_id)
      AND pb."status" <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'Reservation externe deja existante';
  END IF;

  SELECT r.capacity INTO v_capacity FROM "Reservations" r WHERE r.id = v_reservation_id;
  v_booked := public.count_issued_seats(v_reservation_id);
  v_holds := public.count_partner_holds(v_reservation_id);

  IF v_booked + v_holds >= v_capacity THEN
    RAISE EXCEPTION 'Plus de places disponibles';
  END IF;

  IF p_seat_number IS NOT NULL AND trim(p_seat_number) <> '' THEN
    IF trim(p_seat_number) = ANY (public.get_occupied_seats(v_reservation_id)) THEN
      RAISE EXCEPTION 'Siege deja vendu';
    END IF;
  END IF;

  v_owner_user_id := public.partner_company_owner_user_id(p_company_id);
  IF v_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Proprietaire compagnie introuvable';
  END IF;

  SELECT a.id, a.price
  INTO v_arret_id, v_price
  FROM "ProgrammationTrajets" pt
  JOIN "ProgrammationTrajetArrets" a
    ON a."trajetId" = pt.id
   AND a."fromGareId" = pt.depart
   AND a."toGareId" = pt.final
  WHERE pt.id = v_trajet_id
  LIMIT 1;

  IF v_arret_id IS NULL THEN
    RAISE EXCEPTION 'Segment tarifaire introuvable';
  END IF;

  v_price := COALESCE(p_price_override, v_price, 0);
  v_reference := 'TB-' || upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8));
  v_tx_id := CASE
    WHEN v_mode = 'sale' THEN
      'partner:' || COALESCE(NULLIF(trim(p_external_payment_ref), ''), trim(p_external_booking_id))
    ELSE NULL
  END;
  v_is_reservation := v_mode = 'hold';
  v_hold_expires := CASE
    WHEN v_mode = 'hold' THEN now() + make_interval(mins => GREATEST(COALESCE(p_hold_minutes, 15), 5))
    ELSE NULL
  END;

  INSERT INTO "Payment" ("reference", "phone", "amount", "txID")
  VALUES (
    v_reference,
    COALESCE(NULLIF(trim(p_passenger_phone), ''), '0000000000'),
    v_price,
    v_tx_id
  )
  RETURNING id INTO v_payment_id;

  INSERT INTO "ReservationBus" (
    "type", "createdBy", "reservationId", "arretId", "price",
    "isReservation", "paymentId", "passengerName", "seatNumber", "saleChannel"
  )
  VALUES (
    'voyage',
    v_owner_user_id,
    v_reservation_id,
    v_arret_id,
    v_price,
    v_is_reservation,
    v_payment_id,
    NULLIF(trim(p_passenger_name), ''),
    NULLIF(trim(p_seat_number), ''),
    'partner_api'
  )
  RETURNING id INTO v_booking_id;

  INSERT INTO "PartnerBookings" (
    "companyId", "externalSystem", "externalBookingId", "externalDepartureId",
    "reservationId", "bookingId", "paymentId", "status", "holdExpiresAt",
    "externalPaymentRef", "payload"
  )
  VALUES (
    p_company_id,
    COALESCE(NULLIF(trim(p_external_system), ''), 'default'),
    trim(p_external_booking_id),
    trim(p_external_departure_id),
    v_reservation_id,
    v_booking_id,
    v_payment_id,
    CASE WHEN v_mode = 'hold' THEN 'hold' ELSE 'confirmed' END,
    v_hold_expires,
    NULLIF(trim(p_external_payment_ref), ''),
    p_payload
  )
  RETURNING id INTO v_partner_booking_id;

  RETURN jsonb_build_object(
    'partnerBookingId', v_partner_booking_id,
    'externalBookingId', trim(p_external_booking_id),
    'bookingId', v_booking_id,
    'ticketReference', v_reference,
    'status', CASE WHEN v_mode = 'hold' THEN 'hold' ELSE 'confirmed' END,
    'holdExpiresAt', v_hold_expires,
    'availability', public.get_reservation_availability(v_reservation_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_confirm_booking(
  p_company_id uuid,
  p_external_system text,
  p_external_booking_id text,
  p_external_payment_ref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row "PartnerBookings"%ROWTYPE;
  v_tx_id text;
BEGIN
  SELECT * INTO v_row
  FROM "PartnerBookings" pb
  WHERE pb."companyId" = p_company_id
    AND pb."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND pb."externalBookingId" = trim(p_external_booking_id)
  LIMIT 1;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Reservation externe introuvable';
  END IF;

  IF v_row."status" = 'cancelled' THEN
    RAISE EXCEPTION 'Reservation annulee';
  END IF;

  IF v_row."status" = 'confirmed' THEN
    RETURN jsonb_build_object(
      'externalBookingId', v_row."externalBookingId",
      'bookingId', v_row."bookingId",
      'status', 'confirmed',
      'alreadyConfirmed', true,
      'availability', public.get_reservation_availability(v_row."reservationId")
    );
  END IF;

  IF v_row."holdExpiresAt" IS NOT NULL AND v_row."holdExpiresAt" <= now() THEN
    RAISE EXCEPTION 'Reservation expiree';
  END IF;

  v_tx_id := 'partner:' || COALESCE(NULLIF(trim(p_external_payment_ref), ''), v_row."externalPaymentRef", v_row."externalBookingId");

  UPDATE "Payment"
  SET "txID" = v_tx_id
  WHERE id = v_row."paymentId";

  UPDATE "ReservationBus"
  SET "isReservation" = false
  WHERE id = v_row."bookingId";

  UPDATE "PartnerBookings"
  SET "status" = 'confirmed',
      "externalPaymentRef" = COALESCE(NULLIF(trim(p_external_payment_ref), ''), "externalPaymentRef"),
      "updatedAt" = now()
  WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'externalBookingId', v_row."externalBookingId",
    'bookingId', v_row."bookingId",
    'status', 'confirmed',
    'alreadyConfirmed', false,
    'availability', public.get_reservation_availability(v_row."reservationId")
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_cancel_booking(
  p_company_id uuid,
  p_external_system text,
  p_external_booking_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row "PartnerBookings"%ROWTYPE;
  v_ticket_status text;
BEGIN
  SELECT * INTO v_row
  FROM "PartnerBookings" pb
  WHERE pb."companyId" = p_company_id
    AND pb."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND pb."externalBookingId" = trim(p_external_booking_id)
  LIMIT 1;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Reservation externe introuvable';
  END IF;

  IF v_row."status" = 'cancelled' THEN
    RETURN jsonb_build_object(
      'externalBookingId', v_row."externalBookingId",
      'status', 'cancelled',
      'alreadyCancelled', true
    );
  END IF;

  SELECT rb."ticketStatus" INTO v_ticket_status
  FROM "ReservationBus" rb
  WHERE rb.id = v_row."bookingId";

  IF COALESCE(v_ticket_status, '') IN ('on_board', 'used') THEN
    RAISE EXCEPTION 'Billet deja embarque, annulation impossible';
  END IF;

  UPDATE "ReservationBus"
  SET "ticketStatus" = 'cancelled',
      "cancelledAt" = now()
  WHERE id = v_row."bookingId";

  UPDATE "PartnerBookings"
  SET "status" = 'cancelled',
      "updatedAt" = now()
  WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'externalBookingId', v_row."externalBookingId",
    'status', 'cancelled',
    'alreadyCancelled', false,
    'availability', public.get_reservation_availability(v_row."reservationId")
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_get_booking(
  p_company_id uuid,
  p_external_system text,
  p_external_booking_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row "PartnerBookings"%ROWTYPE;
  v_reference text;
  v_passenger_name text;
  v_seat_number text;
BEGIN
  SELECT * INTO v_row
  FROM "PartnerBookings" pb
  WHERE pb."companyId" = p_company_id
    AND pb."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND pb."externalBookingId" = trim(p_external_booking_id)
  LIMIT 1;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Reservation externe introuvable';
  END IF;

  SELECT p.reference INTO v_reference FROM "Payment" p WHERE p.id = v_row."paymentId";
  SELECT rb."passengerName", rb."seatNumber"
  INTO v_passenger_name, v_seat_number
  FROM "ReservationBus" rb
  WHERE rb.id = v_row."bookingId";

  RETURN jsonb_build_object(
    'partnerBookingId', v_row.id,
    'externalBookingId', v_row."externalBookingId",
    'externalDepartureId', v_row."externalDepartureId",
    'reservationId', v_row."reservationId",
    'bookingId', v_row."bookingId",
    'ticketReference', v_reference,
    'status', v_row."status",
    'holdExpiresAt', v_row."holdExpiresAt",
    'passengerName', v_passenger_name,
    'seatNumber', v_seat_number,
    'externalPaymentRef', v_row."externalPaymentRef",
    'payload', v_row."payload"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_upsert_webhook_endpoint(
  p_company_id uuid,
  p_external_system text,
  p_url text,
  p_events text[] DEFAULT ARRAY['booking.created', 'booking.confirmed', 'booking.cancelled'],
  p_endpoint_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  url text,
  secret text,
  events text[],
  external_system text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret text;
  v_id uuid;
BEGIN
  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(p_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  IF p_url IS NULL OR trim(p_url) = '' THEN
    RAISE EXCEPTION 'URL webhook requise';
  END IF;

  v_secret := 'whsec_' || encode(gen_random_bytes(24), 'hex');

  IF p_endpoint_id IS NULL THEN
    INSERT INTO "PartnerWebhookEndpoints" (
      "companyId", "externalSystem", "url", "secret", "events", "createdBy"
    )
    VALUES (
      p_company_id,
      COALESCE(NULLIF(trim(p_external_system), ''), 'default'),
      trim(p_url),
      v_secret,
      COALESCE(p_events, ARRAY['booking.created', 'booking.confirmed', 'booking.cancelled']),
      public.current_app_user_id()
    )
    RETURNING "PartnerWebhookEndpoints".id INTO v_id;
  ELSE
    UPDATE "PartnerWebhookEndpoints"
    SET "url" = trim(p_url),
        "events" = COALESCE(p_events, "events"),
        "isActive" = true
    WHERE "PartnerWebhookEndpoints".id = p_endpoint_id
      AND "companyId" = p_company_id
    RETURNING "PartnerWebhookEndpoints".id, "PartnerWebhookEndpoints".secret
    INTO v_id, v_secret;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Webhook introuvable';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    w.id,
    w.url,
    CASE WHEN p_endpoint_id IS NULL THEN v_secret ELSE w.secret END,
    w.events,
    w."externalSystem"
  FROM "PartnerWebhookEndpoints" w
  WHERE w.id = v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_list_webhook_deliveries(
  p_company_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  event_type text,
  response_status integer,
  delivered_at timestamptz,
  endpoint_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    d.id,
    d."eventType"::text,
    d."responseStatus",
    d."deliveredAt",
    e.url::text
  FROM "PartnerWebhookDeliveries" d
  JOIN "PartnerWebhookEndpoints" e ON e.id = d."endpointId"
  WHERE e."companyId" = p_company_id
  ORDER BY d."deliveredAt" DESC
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1);
$$;

ALTER TABLE "PartnerBookings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PartnerWebhookEndpoints" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PartnerWebhookDeliveries" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "partner_bookings_owner_select" ON "PartnerBookings"
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR public.has_company_role("companyId", ARRAY['owner']));

CREATE POLICY "partner_webhooks_owner_select" ON "PartnerWebhookEndpoints"
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR public.has_company_role("companyId", ARRAY['owner']));

CREATE POLICY "partner_webhook_deliveries_owner_select" ON "PartnerWebhookDeliveries"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "PartnerWebhookEndpoints" e
      WHERE e.id = "endpointId"
        AND public.has_company_role(e."companyId", ARRAY['owner'])
    )
  );

GRANT EXECUTE ON FUNCTION public.count_partner_holds(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_create_booking(uuid, text, text, text, text, text, text, text, integer, text, double precision, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_confirm_booking(uuid, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_cancel_booking(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_get_booking(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_upsert_webhook_endpoint(uuid, text, text, text[], uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_list_webhook_deliveries(uuid, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.partner_list_departures(
  p_company_id uuid,
  p_external_system text,
  p_from timestamptz DEFAULT now(),
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  external_departure_id text,
  reservation_id uuid,
  trajet_id uuid,
  departure_at timestamptz,
  total_seats integer,
  seats_available integer,
  price double precision,
  currency text,
  origin_name text,
  destination_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  RETURN QUERY
  SELECT
    m."externalDepartureId"::text,
    r.id,
    r."trajetId",
    r.date,
    r.capacity,
    GREATEST(r.capacity - public.count_issued_seats(r.id) - public.count_partner_holds(r.id), 0),
    COALESCE(a.price, 0::double precision),
    COALESCE(c.currency, 'XOF')::text,
    gd.name::text,
    gf.name::text
  FROM "PartnerDepartureMappings" m
  JOIN "Reservations" r ON r.id = m."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" gd ON gd.id = pt.depart
  JOIN "Gares" gf ON gf.id = pt.final
  JOIN "Companies" co ON co.id = gd."companyId"
  JOIN "Countries" c ON c.id = co."countryId"
  LEFT JOIN "ProgrammationTrajetArrets" a
    ON a."trajetId" = pt.id
   AND a."fromGareId" = pt.depart
   AND a."toGareId" = pt.final
  WHERE m."companyId" = p_company_id
    AND m."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND m."isActive" = true
    AND r.date >= COALESCE(p_from, now())
    AND (p_to IS NULL OR r.date <= p_to)
  ORDER BY r.date ASC
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 100), 500), 1);
END;
$$;

GRANT EXECUTE ON FUNCTION public.partner_list_departures(uuid, text, timestamptz, timestamptz, integer) TO service_role;
