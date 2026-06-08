-- =============================================================================
-- Tibus 050 — Caisse journalière sans lien trajet/gare + vente guichet fiable
-- Exécuter après 046–049 (idempotent)
-- =============================================================================

-- Statut caisse : inclure en_reversement
ALTER TABLE caisses_gares DROP CONSTRAINT IF EXISTS caisses_gares_statut_check;
ALTER TABLE caisses_gares ADD CONSTRAINT caisses_gares_statut_check
  CHECK (statut IN ('ouverte', 'en_reversement', 'cloturee'));

-- Hub caisse interne par compagnie (aucun lien avec un trajet)
CREATE OR REPLACE FUNCTION public.ensure_company_cash_hub_gare(p_company_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_label constant text := '__CASH_SESSION_HUB__';
BEGIN
  IF p_company_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT g.id INTO v_id
  FROM "Gares" g
  WHERE g."companyId" = p_company_id AND g.name = v_label
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO "Gares" (name, "companyId")
  VALUES (v_label, p_company_id)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_company_counter_gare_id(p_company_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.ensure_company_cash_hub_gare(p_company_id);
$$;

CREATE OR REPLACE FUNCTION public.resolve_seller_company_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ur."companyId"
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = p_user_id
    AND ur."companyId" IS NOT NULL
    AND r.name IN ('vendeur', 'owner')
  ORDER BY CASE WHEN r.name = 'vendeur' THEN 0 ELSE 1 END
  LIMIT 1;
$$;

DROP INDEX IF EXISTS caisses_gares_open_gare_gestionnaire_idx;
CREATE UNIQUE INDEX IF NOT EXISTS caisses_gares_open_gestionnaire_idx
  ON caisses_gares (gestionnaire_id)
  WHERE statut = 'ouverte';

CREATE OR REPLACE FUNCTION public.can_operate_station_cash(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'vendeur']);
$$;

DROP FUNCTION IF EXISTS public.open_station_cash_register(uuid, integer);

CREATE OR REPLACE FUNCTION public.open_station_cash_register(
  p_gare_id uuid DEFAULT NULL,
  p_fond_roulement integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_gare_id uuid;
  v_id uuid;
  v_fond integer;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  v_fond := GREATEST(COALESCE(p_fond_roulement, 0), 0);
  v_company_id := public.resolve_seller_company_id(v_user_id);

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Ouverture reservee aux vendeurs rattaches a une compagnie';
  END IF;

  IF NOT public.can_operate_station_cash(v_company_id) THEN
    RAISE EXCEPTION 'Ouverture caisse non autorisee pour ce compte';
  END IF;

  IF EXISTS (
    SELECT 1 FROM caisses_gares c
    WHERE c.gestionnaire_id = v_user_id
      AND c.statut IN ('ouverte', 'en_reversement')
  ) THEN
    RAISE EXCEPTION 'Une session de caisse est deja active ou en attente de validation';
  END IF;

  -- Toujours le hub interne compagnie : jamais une gare de trajet
  v_gare_id := public.ensure_company_cash_hub_gare(v_company_id);
  IF v_gare_id IS NULL THEN
    RAISE EXCEPTION 'Hub caisse compagnie introuvable';
  END IF;

  INSERT INTO caisses_gares (
    gare_id, gestionnaire_id, solde_especes_actuel, statut, fond_roulement, opened_at
  ) VALUES (
    v_gare_id, v_user_id, v_fond, 'ouverte', v_fond, now()
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'gareId', v_gare_id,
    'gareName', 'Session caisse journalière',
    'sessionLabel', 'Session caisse journalière',
    'balance', v_fond,
    'openingFloat', v_fond,
    'status', 'ouverte'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_seller_open_caisse_id(
  p_user_id uuid,
  p_company_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id
  FROM caisses_gares c
  JOIN "Gares" g ON g.id = c.gare_id
  WHERE c.gestionnaire_id = p_user_id
    AND c.statut = 'ouverte'
    AND g."companyId" = p_company_id
  ORDER BY c.opened_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_open_station_cash_for_user(p_gare_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_row record;
  v_pending boolean;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  SELECT c.*, g.name AS gare_name INTO v_row
  FROM caisses_gares c
  JOIN "Gares" g ON g.id = c.gare_id
  WHERE c.gestionnaire_id = v_user_id
    AND c.statut IN ('ouverte', 'en_reversement')
    AND (p_gare_id IS NULL OR c.gare_id = p_gare_id)
  ORDER BY c.opened_at DESC
  LIMIT 1;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('open', false);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM reversements_comptables r
    WHERE r.caisse_id = v_row.id AND r.statut_validation = 'en_attente'
  ) INTO v_pending;

  RETURN jsonb_build_object(
    'open', v_row.statut = 'ouverte',
    'pendingReversal', v_pending OR v_row.statut = 'en_reversement',
    'id', v_row.id,
    'gareId', v_row.gare_id,
    'gareName', 'Session caisse journalière',
    'sessionLabel', 'Session caisse journalière',
    'balance', v_row.solde_especes_actuel,
    'openingFloat', v_row.fond_roulement,
    'openedAt', v_row.opened_at,
    'status', v_row.statut
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_company_station_gares(p_company_id uuid)
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), p_company_id)
    OR public.can_operate_station_cash(p_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces gares refuse';
  END IF;

  RETURN QUERY
  SELECT g.id, g.name::text
  FROM "Gares" g
  WHERE g."companyId" = p_company_id
    AND g.name <> '__CASH_SESSION_HUB__'
  ORDER BY g.name;
END;
$$;

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

  -- Session caisse journalière (tous trajets) — plus de lien gare de depart
  v_caisse_id := public.get_seller_open_caisse_id(v_user_id, v_company_id);
  IF v_caisse_id IS NULL THEN
    RAISE EXCEPTION 'Ouvrez votre caisse avant toute vente cash (session du jour)';
  END IF;

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
        v_traveler_user_id, v_company_id, v_booking_id, v_ticket_price, 0, v_traveler_user_id
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
      PERFORM public.process_platform_loyalty_on_ticket(
        v_traveler_user_id, v_company_id, v_booking_id, v_ticket_price, 0
      );
    EXCEPTION WHEN OTHERS THEN NULL;
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

GRANT EXECUTE ON FUNCTION public.ensure_company_cash_hub_gare(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_company_counter_gare_id(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_seller_company_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.open_station_cash_register(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_seller_open_caisse_id(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_open_station_cash_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_station_gares(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seller_counter_sale(uuid, text, text, text, integer, double precision, double precision) TO authenticated;
