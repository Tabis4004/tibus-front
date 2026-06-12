-- =============================================================================
-- Tibus 082 — API partenaire : liaison itinéraires externes + places disponibles
-- =============================================================================
-- Permet à une autre compagnie / système de synchroniser ses départs sur Tibus
-- et de lire la disponibilité (même logique que la recherche voyageur).
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS "PartnerApiKeys" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "name" text NOT NULL,
  "externalSystem" text NOT NULL DEFAULT 'default',
  "keyPrefix" text NOT NULL,
  "keyHash" text NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "createdBy" uuid REFERENCES "Users" ("id") ON DELETE SET NULL,
  "lastUsedAt" timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS "PartnerApiKeys_keyHash_key"
  ON "PartnerApiKeys" ("keyHash");

CREATE INDEX IF NOT EXISTS "PartnerApiKeys_company_idx"
  ON "PartnerApiKeys" ("companyId");

CREATE TABLE IF NOT EXISTS "PartnerGareMappings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "externalSystem" text NOT NULL DEFAULT 'default',
  "externalGareId" text NOT NULL,
  "gareId" uuid NOT NULL REFERENCES "Gares" ("id") ON DELETE CASCADE,
  "externalName" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("companyId", "externalSystem", "externalGareId")
);

CREATE INDEX IF NOT EXISTS "PartnerGareMappings_gare_idx"
  ON "PartnerGareMappings" ("gareId");

CREATE TABLE IF NOT EXISTS "PartnerDepartureMappings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "externalSystem" text NOT NULL DEFAULT 'default',
  "externalDepartureId" text NOT NULL,
  "reservationId" uuid NOT NULL REFERENCES "Reservations" ("id") ON DELETE CASCADE,
  "trajetId" uuid NOT NULL REFERENCES "ProgrammationTrajets" ("id") ON DELETE CASCADE,
  "externalPayload" jsonb,
  "isActive" boolean NOT NULL DEFAULT true,
  "lastSyncedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("companyId", "externalSystem", "externalDepartureId")
);

CREATE INDEX IF NOT EXISTS "PartnerDepartureMappings_reservation_idx"
  ON "PartnerDepartureMappings" ("reservationId");

CREATE OR REPLACE FUNCTION public.count_issued_seats(p_reservation_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::integer
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb."reservationId" = p_reservation_id
    AND rb."type" = 'voyage'
    AND (rb."isReservation" = false OR p."txID" IS NOT NULL);
$$;

CREATE OR REPLACE FUNCTION public.get_reservation_availability(p_reservation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_capacity integer;
  v_booked integer;
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
  v_occupied := public.get_occupied_seats(p_reservation_id);

  RETURN jsonb_build_object(
    'reservationId', p_reservation_id,
    'totalSeats', v_capacity,
    'seatsBooked', v_booked,
    'seatsAvailable', GREATEST(v_capacity - v_booked, 0),
    'occupiedSeats', to_jsonb(v_occupied)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_partner_api_key(
  p_name text,
  p_external_system text DEFAULT 'default',
  p_company_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  api_key text,
  key_prefix text,
  external_system text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_company_id uuid;
  v_plain_key text;
  v_prefix text;
  v_hash text;
  v_key_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  v_plain_key := 'tibus_' || encode(gen_random_bytes(24), 'hex');
  v_prefix := left(v_plain_key, 12);
  v_hash := encode(digest(v_plain_key, 'sha256'), 'hex');

  INSERT INTO "PartnerApiKeys" (
    "companyId", "name", "externalSystem", "keyPrefix", "keyHash", "createdBy"
  )
  VALUES (
    v_company_id,
    trim(p_name),
    COALESCE(NULLIF(trim(p_external_system), ''), 'default'),
    v_prefix,
    v_hash,
    public.current_app_user_id()
  )
  RETURNING "PartnerApiKeys".id INTO v_key_id;

  RETURN QUERY
  SELECT v_key_id, v_plain_key, v_prefix, COALESCE(NULLIF(trim(p_external_system), ''), 'default');
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_resolve_api_key(p_api_key text)
RETURNS TABLE (
  key_id uuid,
  company_id uuid,
  external_system text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_hash text;
BEGIN
  IF p_api_key IS NULL OR length(trim(p_api_key)) < 20 THEN
    RAISE EXCEPTION 'Cle API invalide';
  END IF;

  v_hash := encode(digest(trim(p_api_key), 'sha256'), 'hex');

  RETURN QUERY
  SELECT k.id, k."companyId", k."externalSystem"
  FROM "PartnerApiKeys" k
  WHERE k."keyHash" = v_hash
    AND k."isActive" = true
  LIMIT 1;

  UPDATE "PartnerApiKeys"
  SET "lastUsedAt" = now()
  WHERE "keyHash" = v_hash AND "isActive" = true;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_upsert_gare_mapping(
  p_company_id uuid,
  p_external_system text,
  p_external_gare_id text,
  p_gare_id uuid,
  p_external_name text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mapping_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g
    WHERE g.id = p_gare_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare Tibus non autorisee pour cette compagnie';
  END IF;

  INSERT INTO "PartnerGareMappings" (
    "companyId", "externalSystem", "externalGareId", "gareId", "externalName"
  )
  VALUES (
    p_company_id,
    COALESCE(NULLIF(trim(p_external_system), ''), 'default'),
    trim(p_external_gare_id),
    p_gare_id,
    NULLIF(trim(p_external_name), '')
  )
  ON CONFLICT ("companyId", "externalSystem", "externalGareId")
  DO UPDATE SET
    "gareId" = EXCLUDED."gareId",
    "externalName" = EXCLUDED."externalName"
  RETURNING id INTO v_mapping_id;

  RETURN v_mapping_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_resolve_gare_id(
  p_company_id uuid,
  p_external_system text,
  p_external_gare_id text DEFAULT NULL,
  p_tibus_gare_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gare_id uuid;
BEGIN
  IF p_tibus_gare_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM "Gares" g
      WHERE g.id = p_tibus_gare_id AND g."companyId" = p_company_id
    ) THEN
      RAISE EXCEPTION 'Gare Tibus invalide';
    END IF;
    RETURN p_tibus_gare_id;
  END IF;

  IF p_external_gare_id IS NULL OR trim(p_external_gare_id) = '' THEN
    RAISE EXCEPTION 'Identifiant de gare externe requis';
  END IF;

  SELECT m."gareId" INTO v_gare_id
  FROM "PartnerGareMappings" m
  WHERE m."companyId" = p_company_id
    AND m."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND m."externalGareId" = trim(p_external_gare_id)
  LIMIT 1;

  IF v_gare_id IS NULL THEN
    RAISE EXCEPTION 'Gare externe non mappee : %', p_external_gare_id;
  END IF;

  RETURN v_gare_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_upsert_departure(
  p_company_id uuid,
  p_external_system text,
  p_external_departure_id text,
  p_depart_gare_id uuid,
  p_final_gare_id uuid,
  p_departure_at timestamptz,
  p_capacity integer,
  p_price double precision DEFAULT 0,
  p_kilometrage double precision DEFAULT NULL,
  p_payload jsonb DEFAULT NULL
)
RETURNS TABLE (
  reservation_id uuid,
  trajet_id uuid,
  created boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trajet_id uuid;
  v_reservation_id uuid;
  v_mapping_id uuid;
  v_created boolean := false;
  v_arret_id uuid;
BEGIN
  IF p_depart_gare_id = p_final_gare_id THEN
    RAISE EXCEPTION 'Depart et arrivee doivent etre differents';
  END IF;

  IF p_capacity IS NULL OR p_capacity < 1 THEN
    RAISE EXCEPTION 'Capacite invalide';
  END IF;

  IF p_departure_at IS NULL THEN
    RAISE EXCEPTION 'Date de depart requise';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "Gares" gd
    JOIN "Gares" gf ON gf."companyId" = gd."companyId"
    WHERE gd.id = p_depart_gare_id
      AND gf.id = p_final_gare_id
      AND gd."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gares non autorisees pour cette compagnie';
  END IF;

  SELECT m."reservationId", m."trajetId", m.id
  INTO v_reservation_id, v_trajet_id, v_mapping_id
  FROM "PartnerDepartureMappings" m
  WHERE m."companyId" = p_company_id
    AND m."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND m."externalDepartureId" = trim(p_external_departure_id)
  LIMIT 1;

  IF v_mapping_id IS NULL THEN
    SELECT pt.id INTO v_trajet_id
    FROM "ProgrammationTrajets" pt
  JOIN "Gares" gd ON gd.id = pt.depart
    WHERE pt.depart = p_depart_gare_id
      AND pt.final = p_final_gare_id
      AND gd."companyId" = p_company_id
    LIMIT 1;

    IF v_trajet_id IS NULL THEN
      INSERT INTO "ProgrammationTrajets" ("depart", "final", "capacity")
      VALUES (p_depart_gare_id, p_final_gare_id, p_capacity)
      RETURNING id INTO v_trajet_id;

      INSERT INTO "ProgrammationTrajetArrets" (
        "trajetId", "fromGareId", "toGareId", "price", "kilometrage"
      )
      VALUES (
        v_trajet_id, p_depart_gare_id, p_final_gare_id,
        COALESCE(p_price, 0), p_kilometrage
      );
    END IF;

    INSERT INTO "Reservations" ("date", "trajetId", "capacity")
    VALUES (p_departure_at, v_trajet_id, p_capacity)
    RETURNING id INTO v_reservation_id;

    INSERT INTO "PartnerDepartureMappings" (
      "companyId", "externalSystem", "externalDepartureId",
      "reservationId", "trajetId", "externalPayload"
    )
    VALUES (
      p_company_id,
      COALESCE(NULLIF(trim(p_external_system), ''), 'default'),
      trim(p_external_departure_id),
      v_reservation_id,
      v_trajet_id,
      p_payload
    );

    v_created := true;
  ELSE
  IF public.count_issued_seats(v_reservation_id) > 0 AND p_capacity < (
      SELECT r.capacity FROM "Reservations" r WHERE r.id = v_reservation_id
    ) THEN
      RAISE EXCEPTION 'Capacite inferieure aux billets deja vendus';
    END IF;

    UPDATE "Reservations"
    SET "date" = p_departure_at,
        "capacity" = p_capacity
    WHERE id = v_reservation_id;

    SELECT a.id INTO v_arret_id
    FROM "ProgrammationTrajetArrets" a
    WHERE a."trajetId" = v_trajet_id
      AND a."fromGareId" = p_depart_gare_id
      AND a."toGareId" = p_final_gare_id
    LIMIT 1;

    IF v_arret_id IS NOT NULL THEN
      UPDATE "ProgrammationTrajetArrets"
      SET "price" = COALESCE(p_price, "price"),
          "kilometrage" = COALESCE(p_kilometrage, "kilometrage")
      WHERE id = v_arret_id;
    END IF;

    UPDATE "PartnerDepartureMappings"
    SET "externalPayload" = COALESCE(p_payload, "externalPayload"),
        "lastSyncedAt" = now(),
        "isActive" = true
    WHERE id = v_mapping_id;
  END IF;

  RETURN QUERY SELECT v_reservation_id, v_trajet_id, v_created;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_get_departure_availability(
  p_company_id uuid,
  p_external_system text,
  p_external_departure_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reservation_id uuid;
  v_payload jsonb;
  v_departure_at timestamptz;
  v_price double precision;
  v_currency text;
  v_origin_name text;
  v_dest_name text;
  v_origin_gare_id uuid;
  v_dest_gare_id uuid;
BEGIN
  SELECT m."reservationId"
  INTO v_reservation_id
  FROM "PartnerDepartureMappings" m
  WHERE m."companyId" = p_company_id
    AND m."externalSystem" = COALESCE(NULLIF(trim(p_external_system), ''), 'default')
    AND m."externalDepartureId" = trim(p_external_departure_id)
    AND m."isActive" = true
  LIMIT 1;

  IF v_reservation_id IS NULL THEN
    RAISE EXCEPTION 'Depart externe introuvable';
  END IF;

  SELECT
    r.date,
    a.price,
    c.currency,
    gd.name,
    gf.name,
    pt.depart,
    pt.final
  INTO
    v_departure_at,
    v_price,
    v_currency,
    v_origin_name,
    v_dest_name,
    v_origin_gare_id,
    v_dest_gare_id
  FROM "Reservations" r
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" gd ON gd.id = pt.depart
  JOIN "Gares" gf ON gf.id = pt.final
  JOIN "Companies" co ON co.id = gd."companyId"
  JOIN "Countries" c ON c.id = co."countryId"
  LEFT JOIN "ProgrammationTrajetArrets" a
    ON a."trajetId" = pt.id
   AND a."fromGareId" = pt.depart
   AND a."toGareId" = pt.final
  WHERE r.id = v_reservation_id;

  v_payload := public.get_reservation_availability(v_reservation_id);

  RETURN v_payload || jsonb_build_object(
    'externalDepartureId', trim(p_external_departure_id),
    'departureAt', v_departure_at,
    'price', COALESCE(v_price, 0),
    'currency', COALESCE(v_currency, 'XOF'),
    'origin', jsonb_build_object('gareId', v_origin_gare_id, 'name', v_origin_name),
    'destination', jsonb_build_object('gareId', v_dest_gare_id, 'name', v_dest_name)
  );
END;
$$;

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
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    m."externalDepartureId"::text,
    r.id,
    r."trajetId",
    r.date,
    r.capacity,
    GREATEST(r.capacity - public.count_issued_seats(r.id), 0),
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

ALTER TABLE "PartnerApiKeys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PartnerGareMappings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PartnerDepartureMappings" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "partner_api_keys_owner_select" ON "PartnerApiKeys"
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR public.has_company_role("companyId", ARRAY['owner']));

CREATE POLICY "partner_gare_mappings_owner_select" ON "PartnerGareMappings"
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR public.has_company_role("companyId", ARRAY['owner']));

CREATE POLICY "partner_departure_mappings_owner_select" ON "PartnerDepartureMappings"
  FOR SELECT TO authenticated
  USING (public.is_super_admin() OR public.has_company_role("companyId", ARRAY['owner']));

GRANT EXECUTE ON FUNCTION public.count_issued_seats(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_reservation_availability(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_partner_api_key(text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_resolve_api_key(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_upsert_gare_mapping(uuid, text, text, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_resolve_gare_id(uuid, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_upsert_departure(uuid, text, text, uuid, uuid, timestamptz, integer, double precision, double precision, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_get_departure_availability(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.partner_list_departures(uuid, text, timestamptz, timestamptz, integer) TO service_role;
