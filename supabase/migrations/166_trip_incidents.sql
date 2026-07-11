-- Signalement d'incident par les voyageurs sur un voyage.
-- Un voyageur détenteur d'un billet (ReservationBus.createdBy) peut signaler
-- un incident (retard, panne, sécurité…) ; chaque owner de la compagnie
-- reçoit une notification (cloche) et dispose d'un reporting par voyage.

CREATE TABLE public."TripIncidents" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "reservationId" uuid NOT NULL REFERENCES public."Reservations"(id) ON DELETE CASCADE,
  "bookingId" uuid REFERENCES public."ReservationBus"(id) ON DELETE SET NULL,
  "reportedBy" uuid NOT NULL REFERENCES public."Users"(id) ON DELETE CASCADE,
  category text NOT NULL DEFAULT 'autre',
  message text NOT NULL CHECK (btrim(message) <> ''),
  status text NOT NULL DEFAULT 'nouveau' CHECK (status IN ('nouveau', 'traite')),
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX "TripIncidents_reservation_idx" ON public."TripIncidents" ("reservationId");

-- Fail-closed : accès uniquement via les RPC SECURITY DEFINER ci-dessous.
ALTER TABLE public."TripIncidents" ENABLE ROW LEVEL SECURITY;

-- Compagnie d'un voyage (reservation -> trajet -> gare de départ).
CREATE OR REPLACE FUNCTION public._trip_incident_company(p_reservation_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT g."companyId"
  FROM "Reservations" res
  JOIN "ProgrammationTrajets" t ON t.id = res."trajetId"
  JOIN "Gares" g ON g.id = t.depart
  WHERE res.id = p_reservation_id;
$function$;

-- 1. Signalement par le voyageur (doit détenir le billet).
CREATE OR REPLACE FUNCTION public.report_trip_incident(
  p_booking_id uuid,
  p_category text,
  p_message text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_reservation uuid;
  v_company uuid;
  v_id uuid;
  v_category text := COALESCE(NULLIF(btrim(p_category), ''), 'autre');
  v_message text := btrim(COALESCE(p_message, ''));
  v_label text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF v_message = '' THEN RAISE EXCEPTION 'Decrivez l''incident'; END IF;

  SELECT rb."reservationId" INTO v_reservation
  FROM "ReservationBus" rb
  WHERE rb.id = p_booking_id AND rb."createdBy" = v_user;

  IF v_reservation IS NULL THEN
    RAISE EXCEPTION 'Billet introuvable pour ce compte';
  END IF;

  v_company := public._trip_incident_company(v_reservation);
  IF v_company IS NULL THEN RAISE EXCEPTION 'Voyage introuvable'; END IF;

  INSERT INTO "TripIncidents" ("reservationId", "bookingId", "reportedBy", category, message)
  VALUES (v_reservation, p_booking_id, v_user, v_category, v_message)
  RETURNING id INTO v_id;

  -- Notification à chaque owner de la compagnie (cloche).
  SELECT co.name INTO v_label FROM "Companies" co WHERE co.id = v_company;
  INSERT INTO "Notifications" ("userId", "type", "title", "message", "relatedReservationId")
  SELECT DISTINCT ur."userId",
         'trip_incident',
         'Incident signalé sur un voyage',
         '[' || v_category || '] ' || left(v_message, 300) || ' — ' || COALESCE(v_label, ''),
         v_reservation
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."companyId" = v_company AND r.name = 'owner';

  RETURN v_id;
END;
$function$;

-- 2. Reporting owner : incidents d'un voyage.
CREATE OR REPLACE FUNCTION public.list_trip_incidents(p_reservation_id uuid)
RETURNS TABLE (
  id uuid,
  category text,
  message text,
  status text,
  "createdAt" timestamptz,
  "reporterName" text,
  "reporterPhone" text,
  "ticketReference" text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_company uuid := public._trip_incident_company(p_reservation_id);
BEGIN
  IF v_company IS NULL THEN RAISE EXCEPTION 'Voyage introuvable'; END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company, ARRAY['owner', 'comptable_compagnie', 'controleur'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT i.id, i.category, i.message, i.status, i."createdAt",
         (COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", ''))::text,
         u.phone::text,
         p.reference::text
  FROM "TripIncidents" i
  JOIN "Users" u ON u.id = i."reportedBy"
  LEFT JOIN "ReservationBus" rb ON rb.id = i."bookingId"
  LEFT JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE i."reservationId" = p_reservation_id
  ORDER BY i."createdAt" DESC;
END;
$function$;

-- 3. Compteurs par voyage pour la liste Voyages de l'owner.
CREATE OR REPLACE FUNCTION public.list_trip_incident_counts(p_company_id uuid)
RETURNS TABLE ("reservationId" uuid, "total" bigint, "nouveaux" bigint)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie', 'controleur'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT i."reservationId", count(*), count(*) FILTER (WHERE i.status = 'nouveau')
  FROM "TripIncidents" i
  WHERE public._trip_incident_company(i."reservationId") = p_company_id
  GROUP BY i."reservationId";
END;
$function$;

-- 4. Marquer un incident traité / nouveau.
CREATE OR REPLACE FUNCTION public.set_trip_incident_status(p_incident_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_company uuid;
BEGIN
  IF p_status NOT IN ('nouveau', 'traite') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  SELECT public._trip_incident_company(i."reservationId") INTO v_company
  FROM "TripIncidents" i WHERE i.id = p_incident_id;
  IF v_company IS NULL THEN RAISE EXCEPTION 'Incident introuvable'; END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company, ARRAY['owner', 'comptable_compagnie', 'controleur'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  UPDATE "TripIncidents" SET status = p_status WHERE id = p_incident_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._trip_incident_company(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.report_trip_incident(uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_trip_incidents(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_trip_incident_counts(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_trip_incident_status(uuid, text) FROM PUBLIC, anon;
