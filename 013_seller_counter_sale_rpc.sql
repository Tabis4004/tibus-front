-- Vente guichet Supabase: cree un ticket paye pour un vendeur autorise.
-- Idempotent: ajoute les champs colis puis remplace la RPC.

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "parcelCount" integer,
  ADD COLUMN IF NOT EXISTS "parcelWeight" double precision,
  ADD COLUMN IF NOT EXISTS "parcelAmount" double precision;

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
  total_price double precision,
  currency text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_trajet_id uuid;
  v_depart uuid;
  v_final uuid;
  v_arret_id uuid;
  v_ticket_price double precision;
  v_parcel_amount double precision := COALESCE(p_parcel_amount, 0);
  v_total_price double precision;
  v_capacity integer;
  v_booked integer;
  v_payment_id uuid;
  v_reference text;
  v_currency text;
  v_seat text := NULLIF(BTRIM(COALESCE(p_seat_number, '')), '');
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_passenger_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nom voyageur requis';
  END IF;

  SELECT r."capacity", r."trajetId"
    INTO v_capacity, v_trajet_id
  FROM "Reservations" r
  WHERE r.id = p_reservation_id;

  IF v_trajet_id IS NULL THEN
    RAISE EXCEPTION 'Depart introuvable';
  END IF;

  v_company_id := public.reservation_company_id(p_reservation_id);

  IF NOT public.is_super_admin() AND NOT public.can_sell_for_company(v_company_id) THEN
    RAISE EXCEPTION 'Vendeur non autorise pour cette compagnie';
  END IF;

  SELECT pt.depart, pt.final
    INTO v_depart, v_final
  FROM "ProgrammationTrajets" pt
  WHERE pt.id = v_trajet_id;

  SELECT a.id, a.price
    INTO v_arret_id, v_ticket_price
  FROM "ProgrammationTrajetArrets" a
  WHERE a."trajetId" = v_trajet_id
    AND a."fromGareId" = v_depart
    AND a."toGareId" = v_final
  LIMIT 1;

  IF v_arret_id IS NULL THEN
    RAISE EXCEPTION 'Segment introuvable';
  END IF;

  SELECT COUNT(*)::integer
    INTO v_booked
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb."reservationId" = p_reservation_id
    AND rb."type" = 'voyage'
    AND (rb."isReservation" = false OR p."txID" IS NOT NULL);

  IF v_booked >= v_capacity THEN
    RAISE EXCEPTION 'Plus de places disponibles';
  END IF;

  IF v_seat IS NOT NULL AND EXISTS (
    SELECT 1
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    WHERE rb."reservationId" = p_reservation_id
      AND rb."seatNumber" = v_seat
      AND rb."type" = 'voyage'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Siege deja vendu';
  END IF;

  SELECT COALESCE(cn.currency, 'XOF')
    INTO v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" cn ON cn.id = c."countryId"
  WHERE c.id = v_company_id;

  v_total_price := v_ticket_price + GREATEST(v_parcel_amount, 0);
  v_reference := 'TB-' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', '') FROM 1 FOR 8));

  INSERT INTO "Payment" (reference, phone, amount, "txID")
  VALUES (
    v_reference,
    COALESCE(NULLIF(BTRIM(p_passenger_phone), ''), '0000000000'),
    v_total_price,
    'counter-' || gen_random_uuid()::text
  )
  RETURNING id INTO v_payment_id;

  INSERT INTO "ReservationBus" (
    type,
    "createdBy",
    "reservationId",
    "arretId",
    price,
    "isReservation",
    "paymentId",
    "exceedColisAmount",
    "passengerName",
    "seatNumber",
    "parcelCount",
    "parcelWeight",
    "parcelAmount"
  )
  VALUES (
    'voyage',
    v_user_id,
    p_reservation_id,
    v_arret_id,
    v_total_price,
    false,
    v_payment_id,
    NULLIF(v_parcel_amount, 0),
    BTRIM(p_passenger_name),
    v_seat,
    NULLIF(GREATEST(COALESCE(p_parcel_count, 0), 0), 0),
    NULLIF(GREATEST(COALESCE(p_parcel_weight, 0), 0), 0),
    NULLIF(v_parcel_amount, 0)
  )
  RETURNING id INTO booking_id;

  reference := v_reference;
  total_price := v_total_price;
  currency := COALESCE(v_currency, 'XOF');
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seller_counter_sale(uuid, text, text, text, integer, double precision, double precision) TO authenticated;
