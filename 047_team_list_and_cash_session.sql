-- =============================================================================
-- Tibus 047 — Liste équipe owner + caisse journalière vendeur (sans lien trajet)
-- =============================================================================

-- Liste équipe (SECURITY DEFINER : contourne RLS Users pour l'owner)
CREATE OR REPLACE FUNCTION public.list_owner_team_members(
  p_company_id uuid DEFAULT NULL
)
RETURNS TABLE (
  user_id uuid,
  "firstName" varchar,
  "lastName" varchar,
  email varchar,
  role_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = public.current_app_user_id()
      AND ur."companyId" = v_company_id
      AND r.name = 'owner'
  ) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Action reservee au proprietaire de la compagnie';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u."firstName",
    u."lastName",
    u.email,
    r.name
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  JOIN "Users" u ON u.id = ur."userId"
  WHERE ur."companyId" = v_company_id
    AND r.name IN ('vendeur', 'comptable_compagnie', 'controleur')
  ORDER BY u."lastName", u."firstName", r.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_owner_team_members(uuid) TO authenticated;

-- Une seule caisse ouverte par vendeur (session journalière, tous trajets)
DROP INDEX IF EXISTS caisses_gares_open_gare_gestionnaire_idx;
CREATE UNIQUE INDEX IF NOT EXISTS caisses_gares_open_gestionnaire_idx
  ON caisses_gares (gestionnaire_id)
  WHERE statut = 'ouverte';

-- Caisse : vendeur uniquement (pas comptable)
CREATE OR REPLACE FUNCTION public.can_operate_station_cash(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'vendeur']);
$$;

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
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  v_fond := GREATEST(COALESCE(p_fond_roulement, 0), 0);

  IF EXISTS (
    SELECT 1 FROM caisses_gares c WHERE c.gestionnaire_id = v_user_id AND c.statut = 'ouverte'
  ) THEN
    RAISE EXCEPTION 'Une caisse est deja ouverte pour cette session';
  END IF;

  -- Résoudre la compagnie du vendeur
  SELECT ur."companyId" INTO v_company_id
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user_id
    AND ur."companyId" IS NOT NULL
    AND r.name IN ('vendeur', 'owner')
  ORDER BY CASE WHEN r.name = 'vendeur' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Ouverture caisse reservee aux vendeurs';
  END IF;

  IF NOT public.can_operate_station_cash(v_company_id) THEN
    RAISE EXCEPTION 'Ouverture caisse non autorisee';
  END IF;

  v_gare_id := p_gare_id;
  IF v_gare_id IS NOT NULL THEN
    IF public.station_cash_gare_company_id(v_gare_id) IS DISTINCT FROM v_company_id THEN
      RAISE EXCEPTION 'Gare non autorisee pour cette compagnie';
    END IF;
  ELSE
    SELECT g.id INTO v_gare_id
    FROM "Gares" g
    WHERE g."companyId" = v_company_id
    ORDER BY g.name
    LIMIT 1;
  END IF;

  IF v_gare_id IS NULL THEN
    RAISE EXCEPTION 'Aucune gare configuree pour cette compagnie';
  END IF;

  INSERT INTO caisses_gares (gare_id, gestionnaire_id, solde_especes_actuel, statut, fond_roulement, opened_at)
  VALUES (v_gare_id, v_user_id, v_fond, 'ouverte', v_fond, now())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'gareId', v_gare_id,
    'balance', v_fond,
    'openingFloat', v_fond,
    'status', 'ouverte'
  );
END;
$$;

-- Helper : caisse ouverte du vendeur pour la compagnie (tous trajets du jour)
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

GRANT EXECUTE ON FUNCTION public.get_seller_open_caisse_id(uuid, uuid) TO authenticated;

-- seller_counter_sale : caisse session vendeur (tous trajets)
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
    PERFORM public.process_loyalty_on_ticket(
      v_traveler_user_id,
      v_company_id,
      v_booking_id,
      v_ticket_price,
      0,
      v_traveler_user_id
    );
    PERFORM public.process_platform_loyalty_on_ticket(
      v_traveler_user_id,
      v_company_id,
      v_booking_id,
      v_ticket_price,
      0
    );
  END IF;

  booking_id := v_booking_id;
  reference := v_reference;
  verify_token := v_verify_token;
  total_price := v_total_price;
  currency := COALESCE(v_currency, 'XOF');
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- Backfill codes parrain existants
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT u.id FROM "Users" u WHERE u."referralCode" IS NULL LOOP
    PERFORM public.ensure_user_referral_code(r.id);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- GRANTs
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.normalize_phone_digits(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.generate_referral_code() TO service_role;
GRANT EXECUTE ON FUNCTION public.ensure_user_referral_code(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_user_by_phone_or_email(text, text) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_platform_loyalty_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_platform_loyalty_settings(
  boolean, double precision, integer, double precision, integer, double precision,
  integer, integer, integer, integer
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_referral_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_referral_signup(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_referral_share() TO authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_company_loyalty_users(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_loyalty_booking_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_platform_loyalty_redemption(double precision, integer, uuid) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.process_platform_loyalty_on_ticket(uuid, uuid, uuid, double precision, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_loyalty_on_ticket(uuid, uuid, uuid, double precision, integer, uuid) TO service_role;

