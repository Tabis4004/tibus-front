-- Lot 118: Métriques scaling Tibus + notifications superadmin (palier, seuils).

-- Helpers auth/rôles (manquants si init_schema appliqué sans fonctions RLS).
CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id
  FROM "Users" u
  WHERE u."auth_user_id" = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = public.current_app_user_id()
      AND r.name = 'super_admin'
  );
$$;

CREATE TABLE IF NOT EXISTS public."PlatformScalingState" (
  id text PRIMARY KEY DEFAULT 'default',
  "lastTier" text NOT NULL DEFAULT 'demarrage',
  "lastSellers" integer NOT NULL DEFAULT 0,
  "lastAvgDaily" numeric NOT NULL DEFAULT 0,
  "lastConnections" integer NOT NULL DEFAULT 0,
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public."PlatformScalingState" (id)
VALUES ('default')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public."PlatformSuperAdminNotifications" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL DEFAULT 'scaling',
  severity text NOT NULL DEFAULT 'info',
  title text NOT NULL,
  message text NOT NULL,
  "actionTab" text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  "dedupeKey" text,
  "isRead" boolean NOT NULL DEFAULT false,
  "readAt" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS platform_superadmin_notifications_unread_idx
  ON public."PlatformSuperAdminNotifications" ("createdAt" DESC)
  WHERE "isRead" = false;

CREATE UNIQUE INDEX IF NOT EXISTS platform_superadmin_notifications_dedupe_unread_idx
  ON public."PlatformSuperAdminNotifications" ("dedupeKey")
  WHERE "dedupeKey" IS NOT NULL AND "isRead" = false;

ALTER TABLE public."PlatformScalingState" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."PlatformSuperAdminNotifications" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_scaling_state_super_admin ON public."PlatformScalingState";
CREATE POLICY platform_scaling_state_super_admin ON public."PlatformScalingState"
  FOR ALL
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS platform_superadmin_notifications_super_admin ON public."PlatformSuperAdminNotifications";
CREATE POLICY platform_superadmin_notifications_super_admin ON public."PlatformSuperAdminNotifications"
  FOR ALL
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE OR REPLACE FUNCTION public._count_issued_tickets_since(p_since timestamptz)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::bigint
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb.type = 'voyage'
    AND (NOT rb."isReservation" OR COALESCE(NULLIF(BTRIM(p."txID"), ''), NULL) IS NOT NULL)
    AND rb."createdAt" >= p_since;
$$;

CREATE OR REPLACE FUNCTION public._resolve_scaling_tier(
  p_sellers integer,
  p_avg_daily numeric,
  p_connections integer
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_sellers >= 800 OR p_avg_daily >= 50000 OR p_connections >= 600 THEN
    RETURN 'tres_haut_volume';
  ELSIF p_sellers >= 300 OR p_avg_daily >= 15000 OR p_connections >= 200 THEN
    RETURN 'national';
  ELSIF p_sellers >= 100 OR p_avg_daily >= 3000 OR p_connections >= 80 THEN
    RETURN 'fort_trafic';
  ELSIF p_sellers >= 30 OR p_avg_daily >= 500 OR p_connections >= 30 THEN
    RETURN 'croissance';
  END IF;
  RETURN 'demarrage';
END;
$$;

CREATE OR REPLACE FUNCTION public._scaling_tier_thresholds(p_tier text)
RETURNS TABLE(sellers integer, avg_daily numeric, connections integer)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  CASE p_tier
    WHEN 'croissance' THEN
      RETURN QUERY SELECT 100, 3000::numeric, 80;
    WHEN 'fort_trafic' THEN
      RETURN QUERY SELECT 300, 15000::numeric, 200;
    WHEN 'national' THEN
      RETURN QUERY SELECT 800, 50000::numeric, 600;
    WHEN 'tres_haut_volume' THEN
      RETURN QUERY SELECT 1000, 60000::numeric, 800;
    ELSE
      RETURN QUERY SELECT 20, 500::numeric, 30;
  END CASE;
END;
$$;

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
      FROM "ProgrammationTrajets" pt
      WHERE pt."departureTime" >= v_now
        AND pt."departureTime" < v_now + interval '7 days'
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._upsert_scaling_notification(
  p_dedupe_key text,
  p_severity text,
  p_title text,
  p_message text,
  p_action_tab text,
  p_metadata jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_dedupe_key IS NULL THEN
    INSERT INTO public."PlatformSuperAdminNotifications" (
      category, severity, title, message, "actionTab", metadata
    ) VALUES (
      'scaling', p_severity, p_title, p_message, p_action_tab, COALESCE(p_metadata, '{}'::jsonb)
    );
    RETURN;
  END IF;

  INSERT INTO public."PlatformSuperAdminNotifications" (
    category, severity, title, message, "actionTab", metadata, "dedupeKey"
  ) VALUES (
    'scaling', p_severity, p_title, p_message, p_action_tab, COALESCE(p_metadata, '{}'::jsonb), p_dedupe_key
  )
  ON CONFLICT ("dedupeKey") WHERE "dedupeKey" IS NOT NULL AND "isRead" = false
  DO UPDATE SET
    severity = EXCLUDED.severity,
    title = EXCLUDED.title,
    message = EXCLUDED.message,
    metadata = EXCLUDED.metadata,
    "createdAt" = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_platform_scaling_notifications()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_metrics jsonb;
  v_tier text;
  v_prev_tier text := 'demarrage';
  v_sellers integer := 0;
  v_avg_daily numeric := 0;
  v_connections integer := 0;
  v_thresh_sellers integer;
  v_thresh_avg numeric;
  v_thresh_conn integer;
  v_created integer := 0;
  v_day text := to_char(now(), 'YYYY-MM-DD');
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_metrics := public._compute_platform_scaling_metrics();
  v_tier := v_metrics->>'recommendedTier';
  v_sellers := COALESCE((v_metrics->>'sellersTotal')::integer, 0);
  v_avg_daily := COALESCE((v_metrics->>'avgTicketsPerDay30d')::numeric, 0);
  v_connections := COALESCE((v_metrics->>'estimatedPeakConnections')::integer, 0);

  SELECT ps."lastTier"
  INTO v_prev_tier
  FROM public."PlatformScalingState" ps
  WHERE ps.id = 'default';

  IF v_prev_tier IS NULL THEN
    v_prev_tier := 'demarrage';
  END IF;

  IF v_tier IS DISTINCT FROM v_prev_tier THEN
    PERFORM public._upsert_scaling_notification(
      'tier_' || v_tier,
      CASE
        WHEN v_tier IN ('national', 'tres_haut_volume') THEN 'critical'
        WHEN v_tier IN ('fort_trafic', 'croissance') THEN 'warning'
        ELSE 'info'
      END,
      'Palier infra Tibus mis à jour',
      format('Le palier recommandé est passé de %s à %s. Consultez l''onglet Métriques scaling.', v_prev_tier, v_tier),
      'scaling_metrics',
      jsonb_build_object('kind', 'tier_changed', 'previousTier', v_prev_tier, 'newTier', v_tier, 'metrics', v_metrics)
    );
    v_created := v_created + 1;
  END IF;

  SELECT t.sellers, t.avg_daily, t.connections
  INTO v_thresh_sellers, v_thresh_avg, v_thresh_conn
  FROM public._scaling_tier_thresholds(v_tier) t;

  IF v_thresh_sellers > 0 AND (v_sellers::numeric / v_thresh_sellers) >= 0.8 THEN
    PERFORM public._upsert_scaling_notification(
      'warn_sellers_' || v_day,
      'warning',
      'Seuil vendeurs proche de la limite',
      format('%s vendeurs actifs (≥ 80 %% du palier %s, max %s).', v_sellers, v_tier, v_thresh_sellers),
      'scaling_metrics',
      jsonb_build_object('kind', 'threshold_warning', 'metric', 'sellers', 'value', v_sellers, 'max', v_thresh_sellers, 'tier', v_tier)
    );
    v_created := v_created + 1;
  END IF;

  IF v_thresh_avg > 0 AND (v_avg_daily / v_thresh_avg) >= 0.8 THEN
    PERFORM public._upsert_scaling_notification(
      'warn_avg_daily_' || v_day,
      'warning',
      'Volume réservations élevé',
      format('Moyenne %.1f tickets/j (30 j) — ≥ 80 %% du palier %s (max %.0f).', v_avg_daily, v_tier, v_thresh_avg),
      'scaling_metrics',
      jsonb_build_object('kind', 'threshold_warning', 'metric', 'avg_daily', 'value', v_avg_daily, 'max', v_thresh_avg, 'tier', v_tier)
    );
    v_created := v_created + 1;
  END IF;

  IF v_thresh_conn > 0 AND (v_connections::numeric / v_thresh_conn) >= 0.8 THEN
    PERFORM public._upsert_scaling_notification(
      'warn_connections_' || v_day,
      'warning',
      'Connexions simultanées estimées élevées',
      format('~%s connexions estimées — ≥ 80 %% du palier %s (max %s).', v_connections, v_tier, v_thresh_conn),
      'scaling_metrics',
      jsonb_build_object('kind', 'threshold_warning', 'metric', 'connections', 'value', v_connections, 'max', v_thresh_conn, 'tier', v_tier)
    );
    v_created := v_created + 1;
  END IF;

  UPDATE public."PlatformScalingState"
  SET
    "lastTier" = v_tier,
    "lastSellers" = v_sellers,
    "lastAvgDaily" = v_avg_daily,
    "lastConnections" = v_connections,
    "updatedAt" = now()
  WHERE id = 'default';

  RETURN jsonb_build_object('createdOrUpdated', v_created, 'recommendedTier', v_tier);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_platform_scaling_metrics()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
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
  PERFORM public.sync_platform_scaling_notifications();
  RETURN v_metrics;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_superadmin_notifications(p_limit integer DEFAULT 20)
RETURNS TABLE(
  id uuid,
  category text,
  severity text,
  title text,
  message text,
  "actionTab" text,
  metadata jsonb,
  "isRead" boolean,
  "createdAt" timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.category,
    n.severity,
    n.title,
    n.message,
    n."actionTab",
    n.metadata,
    n."isRead",
    n."createdAt"
  FROM public."PlatformSuperAdminNotifications" n
  ORDER BY n."isRead" ASC, n."createdAt" DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_unread_superadmin_notifications()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RETURN 0;
  END IF;

  RETURN (
    SELECT COUNT(*)::integer
    FROM public."PlatformSuperAdminNotifications" n
    WHERE n."isRead" = false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_superadmin_notification_read(p_notification_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  UPDATE public."PlatformSuperAdminNotifications"
  SET "isRead" = true, "readAt" = now()
  WHERE id = p_notification_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_superadmin_notifications_read()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  UPDATE public."PlatformSuperAdminNotifications"
  SET "isRead" = true, "readAt" = now()
  WHERE "isRead" = false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_scaling_metrics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_platform_scaling_notifications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_superadmin_notifications(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_unread_superadmin_notifications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_superadmin_notification_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_superadmin_notifications_read() TO authenticated;
