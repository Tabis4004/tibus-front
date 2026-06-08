-- Lot 54: métriques plateforme + recommandation scaling (super_admin only)
-- PRÉREQUIS : 002_rls_policies.sql (is_super_admin)

CREATE OR REPLACE FUNCTION public.count_valid_tickets_since(p_since timestamptz)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::bigint
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb."createdAt" >= p_since
    AND COALESCE(rb."ticketStatus", 'issued') = 'issued'
    AND (rb."isReservation" = false OR p."txID" IS NOT NULL);
$$;

CREATE OR REPLACE FUNCTION public.get_platform_scaling_metrics()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_day_start timestamptz := date_trunc('day', v_now);
  v_7d timestamptz := v_now - interval '7 days';
  v_30d timestamptz := v_now - interval '30 days';
  v_tickets_today bigint;
  v_tickets_7d bigint;
  v_tickets_30d bigint;
  v_sellers bigint;
  v_avg_daily_30d numeric;
  v_est_peak_connections integer;
  v_recommended_tier text;
  v_db_bytes bigint;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Accès réservé au super_admin';
  END IF;

  v_tickets_today := public.count_valid_tickets_since(v_day_start);
  v_tickets_7d := public.count_valid_tickets_since(v_7d);
  v_tickets_30d := public.count_valid_tickets_since(v_30d);

  SELECT count(DISTINCT ur."userId")::bigint INTO v_sellers
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE r.name IN (
    'vendeur',
    'vendeur_reseau',
    'vendeur_master',
    'vendeur_independant'
  );

  v_avg_daily_30d := round(v_tickets_30d::numeric / 30.0, 1);
  v_est_peak_connections := greatest(
    1,
    round(v_sellers * 1.2 + (v_tickets_today::numeric / 8.0) * 0.4)::integer
  );

  IF v_sellers < 20 AND v_avg_daily_30d < 500 THEN
    v_recommended_tier := 'demarrage';
  ELSIF v_sellers < 100 AND v_avg_daily_30d < 3000 THEN
    v_recommended_tier := 'croissance';
  ELSIF v_sellers < 300 AND v_avg_daily_30d < 15000 THEN
    v_recommended_tier := 'fort_trafic';
  ELSIF v_sellers < 800 AND v_avg_daily_30d < 50000 THEN
    v_recommended_tier := 'national';
  ELSE
    v_recommended_tier := 'tres_haut_volume';
  END IF;

  BEGIN
    v_db_bytes := pg_database_size(current_database());
  EXCEPTION WHEN OTHERS THEN
    v_db_bytes := NULL;
  END;

  RETURN jsonb_build_object(
    'generatedAt', v_now,
    'supabaseProjectRef', 'kqudaqtydimjclwaihqr',
    'usersTotal', (SELECT count(*)::bigint FROM "Users"),
    'companiesTotal', (SELECT count(*)::bigint FROM "Companies"),
    'companiesActive', (SELECT count(*)::bigint FROM "Companies" WHERE "isActive" = true),
    'countriesTotal', (SELECT count(*)::bigint FROM "Countries"),
    'citiesTotal', (SELECT count(*)::bigint FROM "Cities"),
    'sellersTotal', v_sellers,
    'ownersTotal', (
      SELECT count(DISTINCT ur."userId")::bigint
      FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE r.name = 'owner'
    ),
    'travelersTotal', (
      SELECT count(DISTINCT ur."userId")::bigint
      FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE r.name = 'traveler'
    ),
    'ticketsToday', v_tickets_today,
    'tickets7d', v_tickets_7d,
    'tickets30d', v_tickets_30d,
    'avgTicketsPerDay30d', v_avg_daily_30d,
    'estimatedPeakConnections', v_est_peak_connections,
    'databaseSizeBytes', v_db_bytes,
    'recommendedTier', v_recommended_tier,
    'upcomingTrips7d', (
      SELECT count(*)::bigint
      FROM "Reservations" r
      WHERE r.date >= v_now
        AND r.date < v_now + interval '7 days'
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.count_valid_tickets_since(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.count_valid_tickets_since(timestamptz) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_platform_scaling_metrics() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_platform_scaling_metrics() TO authenticated, service_role;
