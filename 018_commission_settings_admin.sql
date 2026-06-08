-- Lot 18: configuration des commissions par pays / compagnie.
-- Idempotent: peut etre relance apres 016_accounting_kpis_commissions.sql.

CREATE TABLE IF NOT EXISTS "CommissionSettings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "scope" text NOT NULL,
  "countryId" uuid,
  "companyId" uuid,
  "rate" double precision NOT NULL DEFAULT 0,
  "paidBy" text NOT NULL DEFAULT 'company',
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid,
  CONSTRAINT "CommissionSettings_scope_check"
    CHECK ("scope" IN ('country', 'company')),
  CONSTRAINT "CommissionSettings_rate_check"
    CHECK ("rate" >= 0 AND "rate" <= 100),
  CONSTRAINT "CommissionSettings_paidBy_check"
    CHECK ("paidBy" IN ('company', 'traveler')),
  CONSTRAINT "CommissionSettings_target_check"
    CHECK (
      ("scope" = 'country' AND "countryId" IS NOT NULL AND "companyId" IS NULL)
      OR
      ("scope" = 'company' AND "companyId" IS NOT NULL)
    )
);

ALTER TABLE "CommissionSettings"
  DROP CONSTRAINT IF EXISTS "CommissionSettings_countryId_fkey";
ALTER TABLE "CommissionSettings"
  ADD CONSTRAINT "CommissionSettings_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "CommissionSettings"
  DROP CONSTRAINT IF EXISTS "CommissionSettings_companyId_fkey";
ALTER TABLE "CommissionSettings"
  ADD CONSTRAINT "CommissionSettings_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "CommissionSettings"
  DROP CONSTRAINT IF EXISTS "CommissionSettings_updatedBy_fkey";
ALTER TABLE "CommissionSettings"
  ADD CONSTRAINT "CommissionSettings_updatedBy_fkey"
  FOREIGN KEY ("updatedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

CREATE UNIQUE INDEX IF NOT EXISTS "CommissionSettings_country_active_key"
  ON "CommissionSettings" ("countryId")
  WHERE "scope" = 'country' AND "isActive" = true;

CREATE UNIQUE INDEX IF NOT EXISTS "CommissionSettings_company_active_key"
  ON "CommissionSettings" ("companyId")
  WHERE "scope" = 'company' AND "isActive" = true;

CREATE INDEX IF NOT EXISTS "CommissionSettings_country_idx"
  ON "CommissionSettings" ("countryId", "scope", "isActive");

CREATE INDEX IF NOT EXISTS "CommissionSettings_company_idx"
  ON "CommissionSettings" ("companyId", "scope", "isActive");

ALTER TABLE "CommissionSettings" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "commission_settings_select" ON "CommissionSettings";
CREATE POLICY "commission_settings_select" ON "CommissionSettings"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_country_role("countryId", ARRAY['admin_pays'])
    OR (
      "companyId" IS NOT NULL
      AND public.has_company_droit("companyId", 'view_reports')
    )
  );

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "sellerCommissionRate" double precision,
  ADD COLUMN IF NOT EXISTS "sellerCommissionScope" text;

CREATE OR REPLACE FUNCTION public.can_manage_commission_country(p_country_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_super_admin()
    OR public.has_country_role(p_country_id, ARRAY['admin_pays']);
$$;

CREATE OR REPLACE FUNCTION public.resolve_seller_commission_setting(p_company_id uuid)
RETURNS TABLE(
  setting_id uuid,
  setting_scope text,
  country_id uuid,
  company_id uuid,
  rate double precision,
  paid_by text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH company_row AS (
    SELECT c.id, c."countryId", COALESCE(c."commissionRate", 0) AS legacy_rate
    FROM "Companies" c
    WHERE c.id = p_company_id
  ),
  resolved AS (
    SELECT
      s.id AS setting_id,
      s.scope AS setting_scope,
      COALESCE(s."countryId", cr."countryId") AS country_id,
      s."companyId" AS company_id,
      s.rate,
      s."paidBy" AS paid_by,
      1 AS priority
    FROM company_row cr
    JOIN "CommissionSettings" s
      ON s."scope" = 'company'
     AND s."companyId" = cr.id
     AND s."isActive" = true
    UNION ALL
    SELECT
      s.id AS setting_id,
      s.scope AS setting_scope,
      s."countryId" AS country_id,
      NULL::uuid AS company_id,
      s.rate,
      s."paidBy" AS paid_by,
      2 AS priority
    FROM company_row cr
    JOIN "CommissionSettings" s
      ON s."scope" = 'country'
     AND s."countryId" = cr."countryId"
     AND s."isActive" = true
    UNION ALL
    SELECT
      NULL::uuid AS setting_id,
      'legacy_company'::text AS setting_scope,
      cr."countryId" AS country_id,
      cr.id AS company_id,
      cr.legacy_rate AS rate,
      'company'::text AS paid_by,
      3 AS priority
    FROM company_row cr
  )
  SELECT
    resolved.setting_id,
    resolved.setting_scope,
    resolved.country_id,
    resolved.company_id,
    COALESCE(resolved.rate, 0),
    COALESCE(resolved.paid_by, 'company')
  FROM resolved
  ORDER BY priority
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.list_commission_settings()
RETURNS TABLE(
  id uuid,
  scope text,
  country_id uuid,
  country_name text,
  company_id uuid,
  company_name text,
  rate double precision,
  paid_by text,
  is_active boolean,
  source text,
  updated_at timestamptz,
  updated_by_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH allowed_countries AS (
    SELECT c.id, c.name::text AS name
    FROM "Countries" c
    WHERE public.can_manage_commission_country(c.id)
  ),
  country_rows AS (
    SELECT
      s.id,
      'country'::text AS scope,
      ac.id AS country_id,
      ac.name AS country_name,
      NULL::uuid AS company_id,
      NULL::text AS company_name,
      COALESCE(s.rate, 0) AS rate,
      COALESCE(s."paidBy", 'company') AS paid_by,
      COALESCE(s."isActive", false) AS is_active,
      CASE WHEN s.id IS NULL THEN 'unset' ELSE 'configured' END AS source,
      s."updatedAt" AS updated_at,
      NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '') AS updated_by_name
    FROM allowed_countries ac
    LEFT JOIN LATERAL (
      SELECT *
      FROM "CommissionSettings" cs
      WHERE cs."scope" = 'country'
        AND cs."countryId" = ac.id
      ORDER BY cs."isActive" DESC, cs."updatedAt" DESC
      LIMIT 1
    ) s ON true
    LEFT JOIN "Users" u ON u.id = s."updatedBy"
  ),
  company_rows AS (
    SELECT
      s.id,
      'company'::text AS scope,
      c."countryId" AS country_id,
      ac.name AS country_name,
      c.id AS company_id,
      c.name::text AS company_name,
      s.rate,
      s."paidBy" AS paid_by,
      s."isActive" AS is_active,
      'company_override'::text AS source,
      s."updatedAt" AS updated_at,
      NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '') AS updated_by_name
    FROM "CommissionSettings" s
    JOIN "Companies" c ON c.id = s."companyId"
    JOIN allowed_countries ac ON ac.id = c."countryId"
    LEFT JOIN "Users" u ON u.id = s."updatedBy"
    WHERE s."scope" = 'company'
  )
  SELECT * FROM country_rows
  UNION ALL
  SELECT * FROM company_rows
  ORDER BY country_name, scope, company_name NULLS FIRST;
$$;

CREATE OR REPLACE FUNCTION public.upsert_commission_setting(
  p_scope text,
  p_country_id uuid,
  p_company_id uuid,
  p_rate double precision,
  p_paid_by text DEFAULT 'company',
  p_is_active boolean DEFAULT true
)
RETURNS TABLE(
  id uuid,
  scope text,
  country_id uuid,
  country_name text,
  company_id uuid,
  company_name text,
  rate double precision,
  paid_by text,
  is_active boolean,
  source text,
  updated_at timestamptz,
  updated_by_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_country_id uuid;
  v_existing_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  IF p_scope NOT IN ('country', 'company') THEN
    RAISE EXCEPTION 'Portee commission invalide';
  END IF;
  IF p_rate < 0 OR p_rate > 100 THEN
    RAISE EXCEPTION 'Le taux doit etre entre 0 et 100';
  END IF;
  IF COALESCE(p_paid_by, 'company') NOT IN ('company', 'traveler') THEN
    RAISE EXCEPTION 'paid_by invalide';
  END IF;

  IF p_scope = 'country' THEN
    v_country_id := p_country_id;
    IF v_country_id IS NULL THEN
      RAISE EXCEPTION 'country_id requis';
    END IF;
  ELSE
    IF p_company_id IS NULL THEN
      RAISE EXCEPTION 'company_id requis';
    END IF;
    SELECT c."countryId" INTO v_country_id
    FROM "Companies" c
    WHERE c.id = p_company_id;
    IF v_country_id IS NULL THEN
      RAISE EXCEPTION 'Compagnie introuvable';
    END IF;
  END IF;

  IF NOT public.can_manage_commission_country(v_country_id) THEN
    RAISE EXCEPTION 'Acces commission refuse';
  END IF;

  SELECT cs.id INTO v_existing_id
  FROM "CommissionSettings" cs
  WHERE cs."scope" = p_scope
    AND (
      (p_scope = 'country' AND cs."countryId" = v_country_id)
      OR
      (p_scope = 'company' AND cs."companyId" = p_company_id)
    )
  ORDER BY cs."isActive" DESC, cs."updatedAt" DESC
  LIMIT 1;

  IF v_existing_id IS NULL THEN
    INSERT INTO "CommissionSettings" (
      "scope", "countryId", "companyId", "rate", "paidBy", "isActive", "updatedBy"
    )
    VALUES (
      p_scope,
      CASE WHEN p_scope = 'country' THEN v_country_id ELSE NULL END,
      CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
      p_rate,
      COALESCE(p_paid_by, 'company'),
      COALESCE(p_is_active, true),
      v_user_id
    )
    RETURNING "CommissionSettings".id INTO v_existing_id;
  ELSE
    UPDATE "CommissionSettings"
    SET
      "countryId" = CASE WHEN p_scope = 'country' THEN v_country_id ELSE "CommissionSettings"."countryId" END,
      "companyId" = CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
      "rate" = p_rate,
      "paidBy" = COALESCE(p_paid_by, 'company'),
      "isActive" = COALESCE(p_is_active, true),
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    WHERE "CommissionSettings".id = v_existing_id;
  END IF;

  RETURN QUERY
  SELECT l.*
  FROM public.list_commission_settings() l
  WHERE l.id = v_existing_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_commission_setting(p_setting_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
BEGIN
  SELECT COALESCE(cs."countryId", c."countryId") INTO v_country_id
  FROM "CommissionSettings" cs
  LEFT JOIN "Companies" c ON c.id = cs."companyId"
  WHERE cs.id = p_setting_id;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Configuration introuvable';
  END IF;
  IF NOT public.can_manage_commission_country(v_country_id) THEN
    RAISE EXCEPTION 'Acces commission refuse';
  END IF;

  DELETE FROM "CommissionSettings" WHERE "CommissionSettings".id = p_setting_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_reservationbus_seller_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_setting record;
BEGIN
  IF NEW."type" <> 'voyage' OR COALESCE(NEW."saleChannel", 'traveler') <> 'seller_reservation' THEN
    NEW."sellerCommissionAmount" := NULL;
    NEW."sellerCommissionRate" := NULL;
    NEW."sellerCommissionScope" := NULL;
    RETURN NEW;
  END IF;

  v_company_id := public.reservation_company_id(NEW."reservationId");
  IF v_company_id IS NULL OR public.is_company_role_user(NEW."createdBy", v_company_id) THEN
    NEW."sellerCommissionAmount" := NULL;
    NEW."sellerCommissionRate" := NULL;
    NEW."sellerCommissionScope" := NULL;
    RETURN NEW;
  END IF;

  SELECT * INTO v_setting
  FROM public.resolve_seller_commission_setting(v_company_id);

  NEW."sellerCommissionRate" := COALESCE(v_setting.rate, 0);
  NEW."sellerCommissionScope" := v_setting.setting_scope;
  NEW."sellerCommissionAmount" := ROUND((COALESCE(NEW.price, 0) * COALESCE(v_setting.rate, 0) / 100)::numeric)::double precision;
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
  "sellerCommissionRate" = calc.rate,
  "sellerCommissionScope" = calc.scope,
  "commissionCalculatedAt" = COALESCE(rb."commissionCalculatedAt", now())
FROM (
  SELECT
    rb2.id,
    NULLIF(ROUND((COALESCE(rb2.price, 0) * COALESCE(resolved.rate, 0) / 100)::numeric)::double precision, 0) AS amount,
    COALESCE(resolved.rate, 0) AS rate,
    resolved.setting_scope AS scope
  FROM "ReservationBus" rb2
  JOIN "Reservations" r ON r.id = rb2."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  LEFT JOIN LATERAL public.resolve_seller_commission_setting(c.id) resolved ON true
  WHERE rb2."type" = 'voyage'
    AND rb2."saleChannel" = 'seller_reservation'
    AND NOT public.is_company_role_user(rb2."createdBy", c.id)
    AND (rb2."sellerCommissionAmount" IS NULL OR rb2."sellerCommissionRate" IS NULL)
) calc
WHERE rb.id = calc.id;

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
    COALESCE(rb."sellerCommissionRate", resolved.rate, c."commissionRate", 0) AS commission_rate,
    COALESCE(
      rb."sellerCommissionAmount",
      ROUND((COALESCE(rb.price, 0) * COALESCE(rb."sellerCommissionRate", resolved.rate, c."commissionRate", 0) / 100)::numeric)::double precision
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
  LEFT JOIN LATERAL public.resolve_seller_commission_setting(c.id) resolved ON true
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
      OR public.can_manage_commission_country(c."countryId")
    )
  ORDER BY rb."createdAt" DESC;
$$;

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
  v_commission record;
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

  SELECT * INTO v_commission
  FROM public.resolve_seller_commission_setting(v_company_id);

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
      'currency', v_currency,
      'commissionRate', COALESCE(v_commission.rate, 0),
      'commissionPaidBy', COALESCE(v_commission.paid_by, 'company'),
      'commissionScope', COALESCE(v_commission.setting_scope, 'legacy_company')
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

GRANT EXECUTE ON FUNCTION public.can_manage_commission_country(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_seller_commission_setting(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_commission_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_commission_setting(text, uuid, uuid, double precision, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_commission_setting(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_seller_commission_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_accounting_dashboard(uuid) TO authenticated;
