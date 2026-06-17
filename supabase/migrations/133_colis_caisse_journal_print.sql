-- Colis : caisse session vendeur (toutes gares), journal canal guichet.

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
      v_colis_id,
      v_user_id,
      NULL,
      'Vente colis guichet',
      'in'
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

CREATE OR REPLACE FUNCTION public.list_company_ticket_sales(
  p_company_id uuid,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0,
  p_sale_channel text DEFAULT NULL,
  p_created_from timestamptz DEFAULT NULL,
  p_created_to timestamptz DEFAULT NULL,
  p_departure_from timestamptz DEFAULT NULL,
  p_departure_to timestamptz DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS TABLE(
  booking_id uuid,
  created_at timestamptz,
  reference text,
  passenger_name text,
  seat_number text,
  ticket_amount double precision,
  currency text,
  sale_channel text,
  ticket_status text,
  seller_user_id uuid,
  seller_name text,
  route_label text,
  departure_time timestamptz,
  hours_before_departure double precision,
  can_cancel boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_search text := NULLIF(TRIM(p_search), '');
  v_channel text := NULLIF(TRIM(p_sale_channel), '');
  v_include_tickets boolean := v_channel IS NULL OR v_channel <> 'colis_autonome';
  v_include_colis boolean := v_channel IS NULL OR v_channel IN ('counter_sale', 'colis_autonome');
  v_departure_filter boolean := p_departure_from IS NOT NULL OR p_departure_to IS NOT NULL;
BEGIN
  IF NOT public.can_view_company_sales(p_company_id) THEN
    RAISE EXCEPTION 'Acces journal ventes refuse';
  END IF;

  RETURN QUERY
  SELECT sales.*
  FROM (
    SELECT
      rb.id AS booking_id,
      rb."createdAt" AS created_at,
      p.reference::text AS reference,
      COALESCE(rb."passengerName", u."firstName" || ' ' || u."lastName")::text AS passenger_name,
      rb."seatNumber"::text AS seat_number,
      COALESCE(rb.price, 0)::double precision AS ticket_amount,
      COALESCE(country.currency, 'XOF')::text AS currency,
      COALESCE(rb."saleChannel", 'traveler')::text AS sale_channel,
      COALESCE(rb."ticketStatus", 'issued')::text AS ticket_status,
      rb."createdBy" AS seller_user_id,
      NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), '')::text AS seller_name,
      (g_depart.name || ' -> ' || g_final.name)::text AS route_label,
      r.date AS departure_time,
      GREATEST(EXTRACT(EPOCH FROM (r.date - now())) / 3600.0, 0)::double precision AS hours_before_departure,
      (
        COALESCE(rb."ticketStatus", 'issued') = 'issued'
        AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
        AND r.date > now()
        AND public.can_cancel_company_ticket(p_company_id)
      ) AS can_cancel
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g_depart ON g_depart.id = pt.depart
    JOIN "Gares" g_final ON g_final.id = pt.final
    JOIN "Companies" c ON c.id = g_depart."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    LEFT JOIN "Users" u ON u.id = rb."createdBy"
    WHERE v_include_tickets
      AND rb."type" = 'voyage'
      AND c.id = p_company_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND (v_channel IS NULL OR COALESCE(rb."saleChannel", 'traveler') = v_channel)
      AND (p_created_from IS NULL OR rb."createdAt" >= p_created_from)
      AND (p_created_to IS NULL OR rb."createdAt" <= p_created_to)
      AND (p_departure_from IS NULL OR r.date >= p_departure_from)
      AND (p_departure_to IS NULL OR r.date <= p_departure_to)
      AND (
        v_search IS NULL
        OR p.reference ILIKE '%' || v_search || '%'
        OR COALESCE(rb."passengerName", u."firstName" || ' ' || u."lastName") ILIKE '%' || v_search || '%'
      )

    UNION ALL

    SELECT
      ca.id AS booking_id,
      ca.created_at,
      ('CL-' || UPPER(SUBSTRING(REPLACE(ca.id::text, '-', ''), 1, 8)))::text AS reference,
      (ca.nom_expediteur || ' → ' || ca.nom_destinataire)::text AS passenger_name,
      NULL::text AS seat_number,
      COALESCE(ca.montant_fret, 0)::double precision AS ticket_amount,
      COALESCE(country.currency, 'XOF')::text AS currency,
      'counter_sale'::text AS sale_channel,
      ca.statut_colis::text AS ticket_status,
      ca.vendeur_id AS seller_user_id,
      NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), '')::text AS seller_name,
      ('[Colis] ' || gd.name || ' -> ' || gdest.name)::text AS route_label,
      ca.created_at AS departure_time,
      0::double precision AS hours_before_departure,
      false AS can_cancel
    FROM public.colis_autonomes ca
    JOIN "Gares" gd ON gd.id = ca.gare_depart_id
    JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id
    JOIN "Companies" c ON c.id = ca.company_id
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    LEFT JOIN "Users" u ON u.id = ca.vendeur_id
    WHERE v_include_colis
      AND NOT v_departure_filter
      AND ca.company_id = p_company_id
      AND (p_created_from IS NULL OR ca.created_at >= p_created_from)
      AND (p_created_to IS NULL OR ca.created_at <= p_created_to)
      AND (
        v_search IS NULL
        OR ca.nom_expediteur ILIKE '%' || v_search || '%'
        OR ca.nom_destinataire ILIKE '%' || v_search || '%'
        OR ca.id::text ILIKE '%' || v_search || '%'
        OR UPPER(SUBSTRING(REPLACE(ca.id::text, '-', ''), 1, 8)) ILIKE '%' || UPPER(v_search) || '%'
      )
  ) sales
  ORDER BY sales.created_at DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;
