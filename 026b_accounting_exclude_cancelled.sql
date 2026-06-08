-- Lot 26b: exclure billets annulés du dashboard caisse

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
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued'
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
