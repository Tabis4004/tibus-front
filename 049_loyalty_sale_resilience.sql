-- Lot 49: La fidélité ne doit jamais bloquer une vente guichet compagnie.

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
  v_traveler_user_id uuid;
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

  v_caisse_id := public.get_seller_open_caisse_id(v_user_id, v_company_id);
  IF v_caisse_id IS NULL THEN RAISE EXCEPTION 'Ouvrez votre caisse avant toute vente cash (session du jour)'; END IF;

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

  v_traveler_user_id := public.resolve_user_by_phone_or_email(p_passenger_phone, NULL);
  IF v_traveler_user_id IS NOT NULL THEN
    BEGIN
      PERFORM public.process_loyalty_on_ticket(
        v_traveler_user_id,
        v_company_id,
        v_booking_id,
        v_ticket_price,
        0,
        v_traveler_user_id
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    BEGIN
      PERFORM public.process_platform_loyalty_on_ticket(
        v_traveler_user_id,
        v_company_id,
        v_booking_id,
        v_ticket_price,
        0
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  booking_id := v_booking_id;
  reference := v_reference;
  verify_token := v_verify_token;
  total_price := v_total_price;
  currency := COALESCE(v_currency, 'XOF');
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seller_counter_sale(uuid, text, text, text, integer, double precision, double precision) TO authenticated;
