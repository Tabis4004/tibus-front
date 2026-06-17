-- Vente cash : le depart du trajet/colis doit correspondre a la gare de caisse ouverte.

CREATE OR REPLACE FUNCTION public.assert_seller_cash_departure_gare(
  p_caisse_id uuid,
  p_depart_gare_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caisse_gare_id uuid;
BEGIN
  SELECT c.gare_id INTO v_caisse_gare_id
  FROM caisses_gares c
  WHERE c.id = p_caisse_id;
  IF v_caisse_gare_id IS NULL THEN
    RAISE EXCEPTION 'Caisse introuvable';
  END IF;
  IF p_depart_gare_id IS DISTINCT FROM v_caisse_gare_id THEN
    RAISE EXCEPTION 'Vente cash reservee aux departs de votre gare ouverte. Pour une autre gare, utilisez la reservation en ligne.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.seller_counter_sale(p_reservation_id uuid, p_passenger_name text, p_passenger_phone text DEFAULT NULL::text, p_seat_number text DEFAULT NULL::text, p_parcel_count integer DEFAULT 0, p_parcel_weight double precision DEFAULT 0, p_parcel_amount double precision DEFAULT 0)
 RETURNS TABLE(booking_id uuid, reference text, verify_token text, total_price double precision, currency text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid; v_company_id uuid; v_trajet_id uuid; v_depart uuid; v_final uuid;
  v_arret_id uuid; v_ticket_price double precision; v_parcel_amount double precision := COALESCE(p_parcel_amount, 0);
  v_total_price double precision; v_capacity integer; v_booked integer; v_payment_id uuid; v_reference text;
  v_currency text; v_seat text := NULLIF(BTRIM(COALESCE(p_seat_number, '')), '');
  v_booking_id uuid; v_caisse_id uuid; v_ticket_fcfa integer; v_parcel_fcfa integer; v_verify_token text;
  v_traveler_user_id uuid; v_has_verify_token boolean;
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
  IF v_caisse_id IS NULL THEN
    RAISE EXCEPTION 'Ouvrez votre caisse avant toute vente cash (session du jour)';
  END IF;

  PERFORM public.assert_seller_cash_departure_gare(v_caisse_id, v_depart);

  SELECT a.id, a.price INTO v_arret_id, v_ticket_price FROM "ProgrammationTrajetArrets" a
  WHERE a."trajetId" = v_trajet_id AND a."fromGareId" = v_depart AND a."toGareId" = v_final LIMIT 1;

  IF v_arret_id IS NULL THEN
    SELECT a.id, a.price INTO v_arret_id, v_ticket_price FROM "ProgrammationTrajetArrets" a
    WHERE a."trajetId" = v_trajet_id AND a."fromGareId" = v_depart
    ORDER BY COALESCE(a.kilometrage, 0) DESC LIMIT 1;
  END IF;

  IF v_arret_id IS NULL THEN
    SELECT a.id, a.price INTO v_arret_id, v_ticket_price FROM "ProgrammationTrajetArrets" a
    WHERE a."trajetId" = v_trajet_id
    ORDER BY COALESCE(a.kilometrage, 0) DESC LIMIT 1;
  END IF;

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

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ReservationBus' AND column_name = 'verifyToken'
  ) INTO v_has_verify_token;

  IF v_has_verify_token THEN
    INSERT INTO "ReservationBus" (
      type, "createdBy", "reservationId", "arretId", price, "isReservation", "paymentId",
      "exceedColisAmount", "passengerName", "seatNumber", "parcelCount", "parcelWeight", "parcelAmount", "saleChannel"
    ) VALUES (
      'voyage', v_user_id, p_reservation_id, v_arret_id, v_total_price, false, v_payment_id,
      NULLIF(v_parcel_amount, 0), BTRIM(p_passenger_name), v_seat,
      NULLIF(GREATEST(COALESCE(p_parcel_count, 0), 0), 0), NULLIF(GREATEST(COALESCE(p_parcel_weight, 0), 0), 0),
      NULLIF(v_parcel_amount, 0), 'counter_sale'
    ) RETURNING id, "verifyToken" INTO v_booking_id, v_verify_token;
  ELSE
    INSERT INTO "ReservationBus" (
      type, "createdBy", "reservationId", "arretId", price, "isReservation", "paymentId",
      "exceedColisAmount", "passengerName", "seatNumber", "parcelCount", "parcelWeight", "parcelAmount", "saleChannel"
    ) VALUES (
      'voyage', v_user_id, p_reservation_id, v_arret_id, v_total_price, false, v_payment_id,
      NULLIF(v_parcel_amount, 0), BTRIM(p_passenger_name), v_seat,
      NULLIF(GREATEST(COALESCE(p_parcel_count, 0), 0), 0), NULLIF(GREATEST(COALESCE(p_parcel_weight, 0), 0), 0),
      NULLIF(v_parcel_amount, 0), 'counter_sale'
    ) RETURNING id INTO v_booking_id;
    v_verify_token := NULL;
  END IF;

  PERFORM public.record_counter_sale_cash_movements(v_caisse_id, v_booking_id, v_ticket_fcfa, v_parcel_fcfa, v_user_id);

  v_traveler_user_id := public.resolve_user_by_phone_or_email(p_passenger_phone, NULL);
  IF v_traveler_user_id IS NOT NULL THEN
    BEGIN
      PERFORM public.process_loyalty_on_ticket(v_traveler_user_id, v_company_id, v_booking_id, v_ticket_price, 0, v_traveler_user_id);
    EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN
      PERFORM public.process_platform_loyalty_on_ticket(v_traveler_user_id, v_company_id, v_booking_id, v_ticket_price, 0);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  booking_id := v_booking_id;
  reference := v_reference;
  verify_token := v_verify_token;
  total_price := v_total_price;
  currency := COALESCE(v_currency, 'XOF');
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_colis_autonome(
  p_company_id uuid,
  p_gare_depart_id uuid,
  p_gare_destination_id uuid,
  p_nom_expediteur text,
  p_telephone_expediteur text,
  p_nom_destinataire text,
  p_telephone_destinataire text,
  p_description_contenu text,
  p_poids_kg double precision,
  p_nombre_pieces integer,
  p_montant_fret double precision,
  p_nature_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_colis_id uuid;
  v_nature_id uuid;
  v_caisse_id uuid;
  v_montant_fcfa integer;
  v_company_name text;
  v_gare_depart text;
  v_gare_destination text;
  v_sms_message text;
  v_send_sms boolean;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN
    RAISE EXCEPTION 'Module colis autonome non active';
  END IF;
  IF p_gare_depart_id = p_gare_destination_id THEN
    RAISE EXCEPTION 'Gare de depart et destination doivent etre differentes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = p_gare_depart_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de depart invalide';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = p_gare_destination_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de destination invalide';
  END IF;
  IF COALESCE(array_length(p_nature_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Selectionnez au moins une nature de colis';
  END IF;

  SELECT c.id INTO v_caisse_id
  FROM caisses_gares c
  WHERE c.gestionnaire_id = v_user_id
    AND c.statut = 'ouverte'
  ORDER BY c.opened_at DESC
  LIMIT 1;

  IF v_caisse_id IS NULL THEN
    RAISE EXCEPTION 'Ouvrez votre caisse avant une vente cash';
  END IF;

  PERFORM public.assert_seller_cash_departure_gare(v_caisse_id, p_gare_depart_id);

  INSERT INTO public.colis_autonomes (
    company_id, gare_depart_id, gare_destination_id,
    nom_expediteur, telephone_expediteur, nom_destinataire, telephone_destinataire,
    description_contenu, poids_kg, nombre_pieces, montant_fret,
    vendeur_id, source_vente, statut_colis
  ) VALUES (
    p_company_id, p_gare_depart_id, p_gare_destination_id,
    btrim(p_nom_expediteur), btrim(p_telephone_expediteur),
    btrim(p_nom_destinataire), btrim(p_telephone_destinataire),
    NULLIF(btrim(COALESCE(p_description_contenu, '')), ''),
    NULLIF(p_poids_kg, 0),
    GREATEST(COALESCE(p_nombre_pieces, 1), 1),
    GREATEST(COALESCE(p_montant_fret, 0), 0),
    v_user_id, 'guichet_cash', 'enregistre'
  ) RETURNING id INTO v_colis_id;

  FOREACH v_nature_id IN ARRAY p_nature_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.colis_natures n
      WHERE n.id = v_nature_id AND n.company_id = p_company_id AND n.is_active
    ) THEN
      RAISE EXCEPTION 'Nature de colis invalide: %', v_nature_id;
    END IF;
    INSERT INTO public.colis_natures_selectionnees (colis_id, nature_id)
    VALUES (v_colis_id, v_nature_id);
  END LOOP;

  v_montant_fcfa := ROUND(GREATEST(COALESCE(p_montant_fret, 0), 0))::integer;
  IF v_montant_fcfa > 0 THEN
    PERFORM public.record_station_cash_movement(
      v_caisse_id,
      'encaissement_colis',
      v_montant_fcfa,
      NULL,
      NULL,
      v_user_id,
      NULL,
      'Vente colis guichet',
      'in',
      v_colis_id
    );
  END IF;

  SELECT c.name, gd.name, gdest.name
  INTO v_company_name, v_gare_depart, v_gare_destination
  FROM "Companies" c
  JOIN "Gares" gd ON gd.id = p_gare_depart_id
  JOIN "Gares" gdest ON gdest.id = p_gare_destination_id
  WHERE c.id = p_company_id;

  v_send_sms := public.colis_sms_enabled_for_statut(p_company_id, 'enregistre');
  v_sms_message := public.build_colis_sms_message(
    'enregistre', v_colis_id, v_company_name, v_gare_depart, v_gare_destination
  );

  RETURN jsonb_build_object(
    'id', v_colis_id,
    'statutColis', 'enregistre',
    'montantFret', GREATEST(COALESCE(p_montant_fret, 0), 0),
    'sms', jsonb_build_object(
      'send', v_send_sms,
      'message', v_sms_message,
      'expediteurPhone', btrim(p_telephone_expediteur),
      'destinatairePhone', btrim(p_telephone_destinataire)
    )
  );
END;
$$;
