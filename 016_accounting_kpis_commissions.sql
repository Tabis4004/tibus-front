-- Prerequis defensifs des lots precedents pour rendre ce script relancable.
ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "saleChannel" text DEFAULT 'traveler',
  ADD COLUMN IF NOT EXISTS "parcelCount" integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "parcelWeight" numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "parcelAmount" numeric DEFAULT 0;

-- Lot 16: caisse / comptabilite / KPI compagnie + commissions vendeurs hors compagnie.
-- Idempotent: peut etre relance apres les lots 011-015.

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "sellerCommissionAmount" double precision,
  ADD COLUMN IF NOT EXISTS "sellerCommissionStatus" text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS "sellerCommissionPaidAt" timestamptz,
  ADD COLUMN IF NOT EXISTS "commissionCalculatedAt" timestamptz;

ALTER TABLE "ReservationBus"
  DROP CONSTRAINT IF EXISTS "ReservationBus_sellerCommissionStatus_check";
ALTER TABLE "ReservationBus"
  ADD CONSTRAINT "ReservationBus_sellerCommissionStatus_check"
  CHECK ("sellerCommissionStatus" IN ('pending', 'paid', 'cancelled'));

CREATE INDEX IF NOT EXISTS "reservationbus_seller_commissions_idx"
  ON "ReservationBus" ("createdBy", "sellerCommissionStatus")
  WHERE "sellerCommissionAmount" IS NOT NULL;

CREATE OR REPLACE FUNCTION public.is_company_role_user(p_user_id uuid, p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ur."userId" = p_user_id
      AND ur."companyId" = p_company_id
      AND ro.name IN ('owner', 'comptable_compagnie', 'controleur', 'vendeur')
  );
$$;

CREATE OR REPLACE FUNCTION public.set_reservationbus_seller_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_rate double precision;
BEGIN
  IF NEW."type" <> 'voyage' OR COALESCE(NEW."saleChannel", 'traveler') <> 'seller_reservation' THEN
    RETURN NEW;
  END IF;

  v_company_id := public.reservation_company_id(NEW."reservationId");
  IF v_company_id IS NULL OR public.is_company_role_user(NEW."createdBy", v_company_id) THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(c."commissionRate", 0)
    INTO v_rate
  FROM "Companies" c
  WHERE c.id = v_company_id;

  NEW."sellerCommissionAmount" := ROUND((COALESCE(NEW.price, 0) * COALESCE(v_rate, 0) / 100)::numeric)::double precision;
  NEW."commissionCalculatedAt" := now();
  IF NEW."sellerCommissionAmount" <= 0 THEN
    NEW."sellerCommissionAmount" := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reservationbus_seller_commission_set ON "ReservationBus";
CREATE TRIGGER reservationbus_seller_commission_set
  BEFORE INSERT OR UPDATE OF price, "saleChannel", "createdBy", "reservationId"
  ON "ReservationBus"
  FOR EACH ROW
  EXECUTE FUNCTION public.set_reservationbus_seller_commission();

UPDATE "ReservationBus" rb
SET
  "sellerCommissionAmount" = calc.amount,
  "commissionCalculatedAt" = now()
FROM (
  SELECT
    rb2.id,
    NULLIF(ROUND((COALESCE(rb2.price, 0) * COALESCE(c."commissionRate", 0) / 100)::numeric)::double precision, 0) AS amount
  FROM "ReservationBus" rb2
  JOIN "Reservations" r ON r.id = rb2."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  WHERE rb2."type" = 'voyage'
    AND rb2."saleChannel" = 'seller_reservation'
    AND NOT public.is_company_role_user(rb2."createdBy", c.id)
) calc
WHERE rb.id = calc.id
  AND rb."sellerCommissionAmount" IS DISTINCT FROM calc.amount;

CREATE OR REPLACE FUNCTION public.get_seller_commission_summary()
RETURNS TABLE(
  booking_id uuid,
  created_at timestamptz,
  company_id uuid,
  company_name text,
  reference text,
  passenger_name text,
  ticket_amount double precision,
  commission_rate double precision,
  commission_amount double precision,
  commission_status text,
  currency text,
  route_label text,
  departure_time timestamptz,
  seller_user_id uuid,
  seller_name text,
  network_master_user_id uuid,
  network_master_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT public.current_app_user_id() AS user_id
  )
  SELECT
    rb.id AS booking_id,
    rb."createdAt" AS created_at,
    c.id AS company_id,
    c.name::text AS company_name,
    p.reference::text AS reference,
    COALESCE(rb."passengerName", u."firstName" || ' ' || u."lastName")::text AS passenger_name,
    rb.price AS ticket_amount,
    COALESCE(c."commissionRate", 0) AS commission_rate,
    COALESCE(
      rb."sellerCommissionAmount",
      ROUND((COALESCE(rb.price, 0) * COALESCE(c."commissionRate", 0) / 100)::numeric)::double precision
    ) AS commission_amount,
    rb."sellerCommissionStatus"::text AS commission_status,
    COALESCE(country.currency, 'XOF')::text AS currency,
    (g_depart.name || ' -> ' || g_final.name)::text AS route_label,
    r.date AS departure_time,
    rb."createdBy" AS seller_user_id,
    (u."firstName" || ' ' || u."lastName")::text AS seller_name,
    mvn."masterUserId" AS network_master_user_id,
    (master_u."firstName" || ' ' || master_u."lastName")::text AS network_master_name
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g_depart ON g_depart.id = pt.depart
  JOIN "Gares" g_final ON g_final.id = pt.final
  JOIN "Companies" c ON c.id = g_depart."companyId"
  LEFT JOIN "Countries" country ON country.id = c."countryId"
  LEFT JOIN "Users" u ON u.id = rb."createdBy"
  LEFT JOIN "MasterVendorNetwork" mvn ON mvn."vendorUserId" = rb."createdBy" AND mvn."isActive" = true
  LEFT JOIN "Users" master_u ON master_u.id = mvn."masterUserId"
  CROSS JOIN me
  WHERE rb."type" = 'voyage'
    AND rb."saleChannel" = 'seller_reservation'
    AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
    AND NOT public.is_company_role_user(rb."createdBy", c.id)
    AND (
      rb."createdBy" = me.user_id
      OR mvn."masterUserId" = me.user_id
      OR public.is_super_admin()
    )
  ORDER BY rb."createdAt" DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_seller_commission_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_company_accounting_dashboard(p_company_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_company_name text;
  v_currency text;
  v_today_start timestamptz := date_trunc('day', now());
  v_today_end timestamptz := date_trunc('day', now()) + interval '1 day';
  v_result jsonb;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  IF p_company_id IS NOT NULL THEN
    v_company_id := p_company_id;
  ELSE
    SELECT ur."companyId"
      INTO v_company_id
    FROM "UserRoles" ur
    JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" IS NOT NULL
      AND ro.name IN ('owner', 'comptable_compagnie', 'controleur', 'vendeur')
    ORDER BY ro.level DESC
    LIMIT 1;
  END IF;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT public.is_super_admin()
     AND NOT public.has_company_droit(v_company_id, 'view_reports')
     AND NOT public.has_company_droit(v_company_id, 'manage_accounting')
     AND NOT public.is_company_staff(v_company_id) THEN
    RAISE EXCEPTION 'Acces rapports refuse';
  END IF;

  SELECT c.name::text, COALESCE(country.currency, 'XOF')::text
    INTO v_company_name, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" country ON country.id = c."countryId"
  WHERE c.id = v_company_id;

  WITH company_reservations AS (
    SELECT r.id, r.date, r.capacity, r."trajetId"
    FROM "Reservations" r
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    WHERE g."companyId" = v_company_id
  ),
  issued_tickets AS (
    SELECT
      rb.id,
      rb."createdAt",
      rb."createdBy",
      rb."reservationId",
      rb."passengerName",
      rb.price,
      rb."parcelAmount",
      rb."saleChannel",
      rb."sellerCommissionAmount",
      rb."sellerCommissionStatus",
      p.reference,
      u."firstName",
      u."lastName",
      cr.date,
      cr.capacity,
      pt.id AS route_id,
      pt.depart,
      pt.final,
      g_depart.name AS origin_name,
      g_final.name AS destination_name,
      b.id AS bus_id,
      b.model AS bus_name,
      b."registrationNumber" AS bus_plate
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN company_reservations cr ON cr.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = cr."trajetId"
    JOIN "Gares" g_depart ON g_depart.id = pt.depart
    JOIN "Gares" g_final ON g_final.id = pt.final
    LEFT JOIN "ProgrammationBus" pb ON pb."trajetId" = pt.id AND pb."isActive" = true
    LEFT JOIN "Bus" b ON b.id = pb."busId"
    LEFT JOIN "Users" u ON u.id = rb."createdBy"
    WHERE rb."type" = 'voyage'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
  ),
  days AS (
    SELECT generate_series(
      (current_date - interval '29 days')::date,
      current_date,
      interval '1 day'
    )::date AS day
  )
  SELECT jsonb_build_object(
    'company', jsonb_build_object(
      'id', v_company_id,
      'name', COALESCE(v_company_name, ''),
      'currency', v_currency
    ),
    'kpis', jsonb_build_object(
      'totalBookings', (SELECT COUNT(*) FROM issued_tickets),
      'confirmedBookings', (SELECT COUNT(*) FROM issued_tickets),
      'totalRevenue', COALESCE((SELECT SUM(price) FROM issued_tickets), 0),
      'todayRevenue', COALESCE((SELECT SUM(price) FROM issued_tickets WHERE "createdAt" >= v_today_start AND "createdAt" < v_today_end), 0),
      'currency', v_currency,
      'totalTrips', (SELECT COUNT(*) FROM company_reservations),
      'upcomingTrips', (SELECT COUNT(*) FROM company_reservations WHERE date > now()),
      'todayTrips', (SELECT COUNT(*) FROM company_reservations WHERE date >= v_today_start AND date < v_today_end),
      'completedTrips', (SELECT COUNT(*) FROM company_reservations WHERE date < now()),
      'totalTravelers', (SELECT COUNT(DISTINCT "createdBy") FROM issued_tickets),
      'totalSellers', (
        SELECT COUNT(*)
        FROM "UserRoles" ur
        JOIN "Role" ro ON ro.id = ur."roleId"
        WHERE ur."companyId" = v_company_id
          AND ro.name IN ('vendeur', 'controleur', 'comptable_compagnie')
      ),
      'totalBuses', (SELECT COUNT(*) FROM "Bus" WHERE "companyId" = v_company_id AND "isActive" = true),
      'caisseRevenue', COALESCE((SELECT SUM(price) FROM issued_tickets WHERE COALESCE("saleChannel", 'traveler') = 'counter_sale'), 0),
      'onlineRevenue', COALESCE((SELECT SUM(price) FROM issued_tickets WHERE COALESCE("saleChannel", 'traveler') <> 'counter_sale'), 0),
      'sellerCommissionsPending', COALESCE((SELECT SUM("sellerCommissionAmount") FROM issued_tickets WHERE "sellerCommissionStatus" = 'pending'), 0)
    ),
    'revenueChart', (
      SELECT jsonb_agg(jsonb_build_object(
        'date', to_char(days.day, 'YYYY-MM-DD'),
        'revenue', COALESCE(day_totals.revenue, 0),
        'tickets', COALESCE(day_totals.tickets, 0)
      ) ORDER BY days.day)
      FROM days
      LEFT JOIN (
        SELECT date_trunc('day', "createdAt")::date AS day, SUM(price) AS revenue, COUNT(*) AS tickets
        FROM issued_tickets
        WHERE "createdAt" >= current_date - interval '29 days'
        GROUP BY 1
      ) day_totals ON day_totals.day = days.day
    ),
    'recentBookings', (
      SELECT COALESCE(jsonb_agg(row_payload ORDER BY created_at DESC), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
          '_id', id,
          '_creationTime', EXTRACT(EPOCH FROM "createdAt") * 1000,
          'passengerName', COALESCE("passengerName", "firstName" || ' ' || "lastName", '-'),
          'passengerPhone', NULL,
          'status', CASE WHEN COALESCE("saleChannel", 'traveler') = 'counter_sale' THEN 'collected' ELSE 'confirmed' END,
          'totalPrice', price,
          'currency', v_currency,
          'bookingReference', reference,
          'sellerName', CASE WHEN COALESCE("saleChannel", 'traveler') = 'traveler' THEN NULL ELSE COALESCE("firstName" || ' ' || "lastName", 'Vendeur') END,
          'originCity', origin_name,
          'destinationCity', destination_name,
          'departureTime', date,
          'busName', COALESCE(bus_name, '-')
        ) AS row_payload,
        "createdAt" AS created_at
        FROM issued_tickets
        ORDER BY "createdAt" DESC
        LIMIT 10
      ) recent
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_accounting_dashboard(uuid) TO authenticated;
