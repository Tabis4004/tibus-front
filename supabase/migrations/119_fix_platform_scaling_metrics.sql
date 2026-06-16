-- Lot 119: Corrige get_platform_scaling_metrics (colonne departureTime inexistante).

CREATE OR REPLACE FUNCTION public._compute_platform_scaling_metrics()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_today_start timestamptz := date_trunc('day', v_now);
  v_7d timestamptz := v_now - interval '7 days';
  v_30d timestamptz := v_now - interval '30 days';
  v_sellers integer := 0;
  v_tickets_today bigint := 0;
  v_tickets_7d bigint := 0;
  v_tickets_30d bigint := 0;
  v_avg_daily numeric := 0;
  v_connections integer := 0;
  v_tier text := 'demarrage';
BEGIN
  SELECT COUNT(DISTINCT ur."userId")::integer
  INTO v_sellers
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE r.name IN ('vendeur', 'vendeur_independant', 'vendeur_master', 'vendeur_reseau');

  v_tickets_today := public._count_issued_tickets_since(v_today_start);
  v_tickets_7d := public._count_issued_tickets_since(v_7d);
  v_tickets_30d := public._count_issued_tickets_since(v_30d);
  v_avg_daily := ROUND(COALESCE(v_tickets_30d, 0)::numeric / 30.0, 1);
  v_connections := GREATEST(5, ROUND(v_sellers * 0.4 + v_avg_daily / 80.0)::integer);
  v_tier := public._resolve_scaling_tier(v_sellers, v_avg_daily, v_connections);

  RETURN jsonb_build_object(
    'generatedAt', v_now,
    'supabaseProjectRef', 'kqudaqtydimjclwaihqr',
    'usersTotal', (SELECT COUNT(*)::integer FROM "Users"),
    'companiesTotal', (SELECT COUNT(*)::integer FROM "Companies"),
    'companiesActive', (SELECT COUNT(*)::integer FROM "Companies" WHERE COALESCE("isActive", true) = true),
    'countriesTotal', (SELECT COUNT(*)::integer FROM "Countries"),
    'citiesTotal', (SELECT COUNT(*)::integer FROM "Cities"),
    'sellersTotal', v_sellers,
    'ownersTotal', (
      SELECT COUNT(DISTINCT ur."userId")::integer
      FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE r.name = 'owner'
    ),
    'travelersTotal', (
      SELECT COUNT(DISTINCT ur."userId")::integer
      FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE r.name = 'traveler'
    ),
    'ticketsToday', COALESCE(v_tickets_today, 0),
    'tickets7d', COALESCE(v_tickets_7d, 0),
    'tickets30d', COALESCE(v_tickets_30d, 0),
    'avgTicketsPerDay30d', v_avg_daily,
    'estimatedPeakConnections', v_connections,
    'databaseSizeBytes', pg_database_size(current_database()),
    'recommendedTier', v_tier,
    'upcomingTrips7d', (
      SELECT COUNT(*)::integer
      FROM "Reservations" r
      WHERE r.date >= v_now
        AND r.date < v_now + interval '7 days'
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_platform_scaling_metrics()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_metrics jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_metrics := public._compute_platform_scaling_metrics();

  BEGIN
    PERFORM public.sync_platform_scaling_notifications();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'sync_platform_scaling_notifications: %', SQLERRM;
  END;

  RETURN v_metrics;
END;
$$;
