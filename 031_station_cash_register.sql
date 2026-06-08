-- Lot 31: Caisse physique gare — mouvements, annulations cash, reversements comptables.

CREATE TABLE IF NOT EXISTS caisses_gares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  gare_id uuid NOT NULL REFERENCES "Gares" (id) ON DELETE RESTRICT,
  gestionnaire_id uuid NOT NULL REFERENCES "Users" (id) ON DELETE RESTRICT,
  solde_especes_actuel integer NOT NULL DEFAULT 0,
  statut text NOT NULL DEFAULT 'ouverte',
  fond_roulement integer NOT NULL DEFAULT 0,
  opened_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  CONSTRAINT caisses_gares_solde_check CHECK (solde_especes_actuel >= 0),
  CONSTRAINT caisses_gares_fond_check CHECK (fond_roulement >= 0),
  CONSTRAINT caisses_gares_statut_check CHECK (statut IN ('ouverte', 'cloturee'))
);

CREATE UNIQUE INDEX IF NOT EXISTS caisses_gares_open_gare_gestionnaire_idx
  ON caisses_gares (gare_id, gestionnaire_id)
  WHERE statut = 'ouverte';

CREATE INDEX IF NOT EXISTS caisses_gares_gare_idx ON caisses_gares (gare_id, opened_at DESC);
CREATE INDEX IF NOT EXISTS caisses_gares_gestionnaire_idx ON caisses_gares (gestionnaire_id, opened_at DESC);

CREATE TABLE IF NOT EXISTS mouvements_caisse (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  caisse_id uuid NOT NULL REFERENCES caisses_gares (id) ON DELETE RESTRICT,
  type_mouvement text NOT NULL,
  montant integer NOT NULL,
  solde_apres integer NOT NULL,
  ticket_id uuid REFERENCES "ReservationBus" (id) ON DELETE SET NULL,
  colis_id uuid REFERENCES "ReservationBus" (id) ON DELETE SET NULL,
  effectue_par uuid NOT NULL REFERENCES "Users" (id) ON DELETE RESTRICT,
  reversement_id uuid,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mouvements_caisse_montant_check CHECK (montant > 0),
  CONSTRAINT mouvements_caisse_solde_apres_check CHECK (solde_apres >= 0),
  CONSTRAINT mouvements_caisse_type_check CHECK (
    type_mouvement IN (
      'encaissement_billet',
      'encaissement_colis',
      'decaissement_annulation',
      'reversement_comptable'
    )
  )
);

CREATE INDEX IF NOT EXISTS mouvements_caisse_caisse_idx
  ON mouvements_caisse (caisse_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reversements_comptables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  caisse_id uuid NOT NULL REFERENCES caisses_gares (id) ON DELETE RESTRICT,
  comptable_id uuid REFERENCES "Users" (id) ON DELETE SET NULL,
  montant_reverse integer NOT NULL,
  statut_validation text NOT NULL DEFAULT 'en_attente',
  soumis_par uuid NOT NULL REFERENCES "Users" (id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  validated_at timestamptz,
  CONSTRAINT reversements_montant_check CHECK (montant_reverse > 0),
  CONSTRAINT reversements_statut_check CHECK (
    statut_validation IN ('en_attente', 'approuve_recu')
  )
);

CREATE INDEX IF NOT EXISTS reversements_caisse_idx
  ON reversements_comptables (caisse_id, created_at DESC);

CREATE INDEX IF NOT EXISTS reversements_statut_idx
  ON reversements_comptables (statut_validation, created_at DESC);

ALTER TABLE mouvements_caisse
  DROP CONSTRAINT IF EXISTS mouvements_caisse_reversement_fkey;
ALTER TABLE mouvements_caisse
  ADD CONSTRAINT mouvements_caisse_reversement_fkey
  FOREIGN KEY (reversement_id) REFERENCES reversements_comptables (id) ON DELETE SET NULL;

ALTER TABLE caisses_gares ENABLE ROW LEVEL SECURITY;
ALTER TABLE mouvements_caisse ENABLE ROW LEVEL SECURITY;
ALTER TABLE reversements_comptables ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.station_cash_gare_company_id(p_gare_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT g."companyId" FROM "Gares" g WHERE g.id = p_gare_id;
$$;

CREATE OR REPLACE FUNCTION public.can_operate_station_cash(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'vendeur']);
$$;

CREATE OR REPLACE FUNCTION public.can_validate_station_reversal(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie']);
$$;

CREATE OR REPLACE FUNCTION public.fcfa_to_int(p_amount double precision)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT GREATEST(0, ROUND(COALESCE(p_amount, 0))::integer);
$$;

CREATE OR REPLACE FUNCTION public.record_station_cash_movement(
  p_caisse_id uuid,
  p_type_mouvement text,
  p_montant integer,
  p_ticket_id uuid DEFAULT NULL,
  p_colis_id uuid DEFAULT NULL,
  p_effectue_par uuid DEFAULT NULL,
  p_reversement_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_direction text DEFAULT 'in'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caisse record;
  v_user_id uuid;
  v_delta integer;
  v_new_balance integer;
  v_movement_id uuid;
BEGIN
  IF COALESCE(p_montant, 0) <= 0 THEN RAISE EXCEPTION 'Montant mouvement invalide'; END IF;
  v_user_id := COALESCE(p_effectue_par, public.current_app_user_id());
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_caisse FROM caisses_gares WHERE id = p_caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  IF v_caisse.statut <> 'ouverte' AND p_type_mouvement <> 'reversement_comptable' THEN
    RAISE EXCEPTION 'Caisse cloturee';
  END IF;

  v_delta := CASE WHEN p_direction = 'out' THEN -p_montant ELSE p_montant END;
  v_new_balance := v_caisse.solde_especes_actuel + v_delta;
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Solde caisse insuffisant (solde: %, mouvement: %)', v_caisse.solde_especes_actuel, v_delta;
  END IF;

  UPDATE caisses_gares SET solde_especes_actuel = v_new_balance WHERE id = p_caisse_id;

  INSERT INTO mouvements_caisse (
    caisse_id, type_mouvement, montant, solde_apres,
    ticket_id, colis_id, effectue_par, reversement_id, note
  ) VALUES (
    p_caisse_id, p_type_mouvement, p_montant, v_new_balance,
    p_ticket_id, p_colis_id, v_user_id, p_reversement_id, NULLIF(trim(p_note), '')
  ) RETURNING id INTO v_movement_id;

  RETURN v_movement_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_open_station_cash_for_user(p_gare_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid; v_row record;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  SELECT c.*, g.name AS gare_name INTO v_row
  FROM caisses_gares c JOIN "Gares" g ON g.id = c.gare_id
  WHERE c.gestionnaire_id = v_user_id AND c.statut = 'ouverte'
    AND (p_gare_id IS NULL OR c.gare_id = p_gare_id)
  ORDER BY c.opened_at DESC LIMIT 1;
  IF v_row.id IS NULL THEN RETURN jsonb_build_object('open', false); END IF;
  RETURN jsonb_build_object('open', true, 'id', v_row.id, 'gareId', v_row.gare_id,
    'gareName', v_row.gare_name, 'balance', v_row.solde_especes_actuel,
    'openingFloat', v_row.fond_roulement, 'openedAt', v_row.opened_at, 'status', v_row.statut);
END; $$;

CREATE OR REPLACE FUNCTION public.open_station_cash_register(p_gare_id uuid, p_fond_roulement integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid; v_company_id uuid; v_id uuid; v_fond integer;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF p_gare_id IS NULL THEN RAISE EXCEPTION 'Gare requise'; END IF;
  v_fond := GREATEST(COALESCE(p_fond_roulement, 0), 0);
  v_company_id := public.station_cash_gare_company_id(p_gare_id);
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Gare introuvable'; END IF;
  IF NOT public.can_operate_station_cash(v_company_id) THEN RAISE EXCEPTION 'Ouverture caisse non autorisee'; END IF;
  IF EXISTS (SELECT 1 FROM caisses_gares c WHERE c.gestionnaire_id = v_user_id AND c.statut = 'ouverte') THEN
    RAISE EXCEPTION 'Une caisse est deja ouverte pour ce guichetier';
  END IF;
  INSERT INTO caisses_gares (gare_id, gestionnaire_id, solde_especes_actuel, statut, fond_roulement, opened_at)
  VALUES (p_gare_id, v_user_id, v_fond, 'ouverte', v_fond, now()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'gareId', p_gare_id, 'balance', v_fond, 'openingFloat', v_fond, 'status', 'ouverte');
END; $$;

CREATE OR REPLACE FUNCTION public.list_station_cash_movements(p_caisse_id uuid, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid, created_at timestamptz, type_mouvement text, montant integer, solde_apres integer,
  ticket_id uuid, colis_id uuid, effectue_par_name text, note text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company_id uuid;
BEGIN
  SELECT public.station_cash_gare_company_id(c.gare_id) INTO v_company_id FROM caisses_gares c WHERE c.id = p_caisse_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  IF NOT (public.is_super_admin() OR public.can_operate_station_cash(v_company_id) OR public.can_validate_station_reversal(v_company_id)) THEN
    RAISE EXCEPTION 'Acces mouvements refuse';
  END IF;
  RETURN QUERY
  SELECT m.id, m.created_at, m.type_mouvement, m.montant, m.solde_apres, m.ticket_id, m.colis_id,
    NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), ''), m.note
  FROM mouvements_caisse m LEFT JOIN "Users" u ON u.id = m.effectue_par
  WHERE m.caisse_id = p_caisse_id ORDER BY m.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500)) OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END; $$;

CREATE OR REPLACE FUNCTION public.submit_station_cash_reversal(p_caisse_id uuid, p_montant_reverse integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid; v_caisse record; v_id uuid; v_montant integer;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  v_montant := COALESCE(p_montant_reverse, 0);
  IF v_montant <= 0 THEN RAISE EXCEPTION 'Montant reversement invalide'; END IF;
  SELECT * INTO v_caisse FROM caisses_gares WHERE id = p_caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  IF v_caisse.gestionnaire_id <> v_user_id AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Reversement reserve au guichetier de la caisse';
  END IF;
  IF v_caisse.statut <> 'ouverte' THEN RAISE EXCEPTION 'Caisse deja cloturee'; END IF;
  IF EXISTS (SELECT 1 FROM reversements_comptables r WHERE r.caisse_id = p_caisse_id AND r.statut_validation = 'en_attente') THEN
    RAISE EXCEPTION 'Un reversement est deja en attente pour cette caisse';
  END IF;
  INSERT INTO reversements_comptables (caisse_id, montant_reverse, statut_validation, soumis_par)
  VALUES (p_caisse_id, v_montant, 'en_attente', v_user_id) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'caisseId', p_caisse_id, 'amount', v_montant,
    'status', 'en_attente', 'currentBalance', v_caisse.solde_especes_actuel);
END; $$;

CREATE OR REPLACE FUNCTION public.validate_station_cash_reversal(p_reversement_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid; v_rev record; v_caisse record; v_company_id uuid; v_movement_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  SELECT * INTO v_rev FROM reversements_comptables WHERE id = p_reversement_id FOR UPDATE;
  IF v_rev.id IS NULL THEN RAISE EXCEPTION 'Reversement introuvable'; END IF;
  IF v_rev.statut_validation <> 'en_attente' THEN RAISE EXCEPTION 'Reversement deja traite'; END IF;
  SELECT * INTO v_caisse FROM caisses_gares WHERE id = v_rev.caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  v_company_id := public.station_cash_gare_company_id(v_caisse.gare_id);
  IF NOT public.can_validate_station_reversal(v_company_id) THEN
    RAISE EXCEPTION 'Validation reservee au comptable ou owner';
  END IF;
  v_movement_id := public.record_station_cash_movement(v_caisse.id, 'reversement_comptable', v_rev.montant_reverse,
    NULL, NULL, v_user_id, v_rev.id, 'Reversement valide par comptable', 'out');
  UPDATE reversements_comptables SET statut_validation = 'approuve_recu', comptable_id = v_user_id, validated_at = now()
  WHERE id = p_reversement_id;
  UPDATE caisses_gares SET statut = 'cloturee', closed_at = now() WHERE id = v_caisse.id;
  RETURN jsonb_build_object('id', p_reversement_id, 'status', 'approuve_recu', 'movementId', v_movement_id,
    'balanceAfter', (SELECT solde_especes_actuel FROM caisses_gares WHERE id = v_caisse.id));
END; $$;

CREATE OR REPLACE FUNCTION public.list_company_station_cash_reversals(p_company_id uuid, p_status text DEFAULT NULL)
RETURNS TABLE(id uuid, created_at timestamptz, validated_at timestamptz, montant_reverse integer, statut_validation text,
  caisse_id uuid, gare_name text, gestionnaire_name text, solde_caisse integer, soumis_par_name text, comptable_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_super_admin() OR public.can_validate_station_reversal(p_company_id)
    OR public.has_company_role(p_company_id, ARRAY['controleur'])) THEN
    RAISE EXCEPTION 'Acces reversements refuse';
  END IF;
  RETURN QUERY
  SELECT r.id, r.created_at, r.validated_at, r.montant_reverse, r.statut_validation, r.caisse_id, g.name::text,
    NULLIF(TRIM(gest."firstName" || ' ' || gest."lastName"), ''), c.solde_especes_actuel,
    NULLIF(TRIM(sub."firstName" || ' ' || sub."lastName"), ''), NULLIF(TRIM(comp."firstName" || ' ' || comp."lastName"), '')
  FROM reversements_comptables r
  JOIN caisses_gares c ON c.id = r.caisse_id
  JOIN "Gares" g ON g.id = c.gare_id
  JOIN "Users" gest ON gest.id = c.gestionnaire_id
  JOIN "Users" sub ON sub.id = r.soumis_par
  LEFT JOIN "Users" comp ON comp.id = r.comptable_id
  WHERE g."companyId" = p_company_id
    AND (p_status IS NULL OR NULLIF(trim(p_status), '') IS NULL OR r.statut_validation = p_status)
  ORDER BY r.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.list_company_station_gares(p_company_id uuid)
RETURNS TABLE(id uuid, name text) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_super_admin() OR public.is_company_role_user(public.current_app_user_id(), p_company_id)
    OR public.can_operate_station_cash(p_company_id)) THEN
    RAISE EXCEPTION 'Acces gares refuse';
  END IF;
  RETURN QUERY SELECT g.id, g.name::text FROM "Gares" g WHERE g."companyId" = p_company_id ORDER BY g.name;
END; $$;

CREATE OR REPLACE FUNCTION public.record_counter_sale_cash_movements(
  p_caisse_id uuid, p_booking_id uuid, p_ticket_amount integer, p_parcel_amount integer, p_user_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF COALESCE(p_ticket_amount, 0) > 0 THEN
    PERFORM public.record_station_cash_movement(p_caisse_id, 'encaissement_billet', p_ticket_amount,
      p_booking_id, NULL, p_user_id, NULL, NULL, 'in');
  END IF;
  IF COALESCE(p_parcel_amount, 0) > 0 THEN
    PERFORM public.record_station_cash_movement(p_caisse_id, 'encaissement_colis', p_parcel_amount,
      p_booking_id, p_booking_id, p_user_id, NULL, NULL, 'in');
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.record_cash_cancellation_disbursement(
  p_booking_id uuid, p_refund_amount integer, p_user_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rb record; v_caisse_id uuid;
BEGIN
  IF COALESCE(p_refund_amount, 0) <= 0 THEN RETURN NULL; END IF;
  SELECT rb.*, pt.depart AS depart_gare INTO v_rb
  FROM "ReservationBus" rb
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  WHERE rb.id = p_booking_id;
  IF v_rb.id IS NULL OR COALESCE(v_rb."saleChannel", '') <> 'counter_sale' THEN RETURN NULL; END IF;
  SELECT c.id INTO v_caisse_id FROM caisses_gares c
  WHERE c.gare_id = v_rb.depart_gare AND c.statut = 'ouverte'
    AND (c.gestionnaire_id = p_user_id OR c.gestionnaire_id = v_rb."createdBy")
  ORDER BY c.opened_at DESC LIMIT 1;
  IF v_caisse_id IS NULL THEN
    SELECT c.id INTO v_caisse_id FROM caisses_gares c
    WHERE c.gare_id = v_rb.depart_gare AND c.statut = 'ouverte'
    ORDER BY c.opened_at DESC LIMIT 1;
  END IF;
  IF v_caisse_id IS NULL THEN
    RAISE EXCEPTION 'Aucune caisse ouverte a la gare de depart pour enregistrer le decaissement';
  END IF;
  RETURN public.record_station_cash_movement(v_caisse_id, 'decaissement_annulation', p_refund_amount,
    p_booking_id, NULL, p_user_id, NULL, 'Remboursement annulation billet cash', 'out');
END; $$;

CREATE OR REPLACE FUNCTION public.seller_counter_sale(
  p_reservation_id uuid,
  p_passenger_name text,
  p_passenger_phone text DEFAULT NULL,
  p_seat_number text DEFAULT NULL,
  p_parcel_count integer DEFAULT 0,
  p_parcel_weight double precision DEFAULT 0,
  p_parcel_amount double precision DEFAULT 0
)
RETURNS TABLE(booking_id uuid, reference text, total_price double precision, currency text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid; v_company_id uuid; v_trajet_id uuid; v_depart uuid; v_final uuid;
  v_arret_id uuid; v_ticket_price double precision; v_parcel_amount double precision := COALESCE(p_parcel_amount, 0);
  v_total_price double precision; v_capacity integer; v_booked integer; v_payment_id uuid; v_reference text;
  v_currency text; v_seat text := NULLIF(BTRIM(COALESCE(p_seat_number, '')), '');
  v_booking_id uuid; v_caisse_id uuid; v_ticket_fcfa integer; v_parcel_fcfa integer;
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
  ) RETURNING id INTO v_booking_id;

  PERFORM public.record_counter_sale_cash_movements(v_caisse_id, v_booking_id, v_ticket_fcfa, v_parcel_fcfa, v_user_id);

  booking_id := v_booking_id; reference := v_reference; total_price := v_total_price; currency := COALESCE(v_currency, 'XOF');
  RETURN NEXT;
END; $$;

CREATE OR REPLACE FUNCTION public.cancel_company_ticket(p_booking_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company_id uuid; v_rb record; v_preview jsonb; v_user_id uuid;
  v_refund_fcfa integer; v_payment record; v_movement_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT rb.*, r.date AS departure_time INTO v_rb
  FROM "ReservationBus" rb JOIN "Reservations" r ON r.id = rb."reservationId"
  WHERE rb.id = p_booking_id FOR UPDATE;

  IF v_rb.id IS NULL THEN RAISE EXCEPTION 'Billet introuvable'; END IF;
  IF COALESCE(v_rb."ticketStatus", 'issued') <> 'issued' THEN RAISE EXCEPTION 'Billet deja annule'; END IF;
  IF v_rb.departure_time <= now() THEN RAISE EXCEPTION 'Depart deja effectue ou en cours'; END IF;

  v_company_id := public.reservation_company_id(v_rb."reservationId");
  IF NOT public.can_cancel_company_ticket(v_company_id) THEN
    RAISE EXCEPTION 'Annulation reservee au owner et au vendeur de la compagnie';
  END IF;

  v_preview := public.preview_ticket_cancellation(p_booking_id);
  IF COALESCE((v_preview->>'canExecute')::boolean, false) = false THEN
    RAISE EXCEPTION 'Annulation impossible dans la fenetre actuelle';
  END IF;

  UPDATE "ReservationBus" SET
    "ticketStatus" = 'cancelled', "cancelledAt" = now(), "cancelledBy" = v_user_id,
    "penaltyAmount" = (v_preview->>'penaltyAmount')::double precision,
    "refundAmount" = (v_preview->>'refundAmount')::double precision,
    "cancellationReason" = NULLIF(trim(p_reason), ''),
    "sellerCommissionStatus" = CASE WHEN "sellerCommissionAmount" IS NOT NULL THEN 'cancelled' ELSE "sellerCommissionStatus" END
  WHERE id = p_booking_id;

  IF COALESCE(v_rb."saleChannel", '') = 'counter_sale' THEN
    SELECT p.* INTO v_payment FROM "Payment" p WHERE p.id = v_rb."paymentId";
    IF v_payment."txID" IS NOT NULL AND v_payment."txID" LIKE 'counter-%' THEN
      v_refund_fcfa := public.fcfa_to_int((v_preview->>'refundAmount')::double precision);
      IF v_refund_fcfa > 0 THEN
        v_movement_id := public.record_cash_cancellation_disbursement(p_booking_id, v_refund_fcfa, v_user_id);
        v_preview := v_preview || jsonb_build_object('cashMovementId', v_movement_id);
      END IF;
    END IF;
  END IF;

  PERFORM public.release_company_guarantee_fund(p_booking_id);

  RETURN v_preview || jsonb_build_object('status', 'cancelled', 'cancelledAt', now());
END; $$;

DROP POLICY IF EXISTS caisses_gares_select ON caisses_gares;
CREATE POLICY caisses_gares_select ON caisses_gares FOR SELECT TO authenticated USING (
  public.is_super_admin() OR gestionnaire_id = public.current_app_user_id()
  OR public.can_validate_station_reversal(public.station_cash_gare_company_id(gare_id))
  OR public.can_operate_station_cash(public.station_cash_gare_company_id(gare_id))
);

DROP POLICY IF EXISTS mouvements_caisse_select ON mouvements_caisse;
CREATE POLICY mouvements_caisse_select ON mouvements_caisse FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM caisses_gares c WHERE c.id = mouvements_caisse.caisse_id AND (
    public.is_super_admin() OR c.gestionnaire_id = public.current_app_user_id()
    OR public.can_validate_station_reversal(public.station_cash_gare_company_id(c.gare_id))
  ))
);

DROP POLICY IF EXISTS reversements_select ON reversements_comptables;
CREATE POLICY reversements_select ON reversements_comptables FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM caisses_gares c JOIN "Gares" g ON g.id = c.gare_id
    WHERE c.id = reversements_comptables.caisse_id AND (
      public.is_super_admin() OR c.gestionnaire_id = public.current_app_user_id()
      OR public.can_validate_station_reversal(g."companyId")
    ))
);

GRANT EXECUTE ON FUNCTION public.open_station_cash_register(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_open_station_cash_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_station_cash_movements(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_station_cash_reversal(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_station_cash_reversal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_station_cash_reversals(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_station_gares(uuid) TO authenticated;
