-- Lot 196: alerte superadmin quand la taille de la base approche la limite
-- du plan Supabase Free (500 Mo de *database size* — au-delà, Supabase
-- repasse la base en lecture seule ; voir docs "Database Size"). Réutilise
-- l'infra de notifications superadmin déjà en place (migration 118/195) :
-- même table PlatformSuperAdminNotifications, même popover cloche, même
-- ratio d'alerte à 80 %.
--
-- Le plafond de 500 Mo est en dur car spécifique au plan Free actuel de
-- l'org Supabase "Tabis4004's Org" (projet kqudaqtydimjclwaihqr, "Tibus
-- 1.0"). Si l'org passe en Pro, ce plafond saute à 8 Go inclus (facturé au
-- delà) — il faudra remonter v_db_limit_bytes en conséquence.

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
  v_db_size_bytes bigint := 0;
  v_db_limit_bytes bigint := 500 * 1024 * 1024; -- 500 Mo, plan Free Supabase
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
  v_db_size_bytes := COALESCE((v_metrics->>'databaseSizeBytes')::bigint, 0);

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

  IF v_db_size_bytes > 0 AND (v_db_size_bytes::numeric / v_db_limit_bytes) >= 0.8 THEN
    PERFORM public._upsert_scaling_notification(
      'warn_db_size_' || v_day,
      CASE WHEN v_db_size_bytes >= v_db_limit_bytes THEN 'critical' ELSE 'warning' END,
      'Base de données proche de la limite Free',
      format(
        '%s Mo utilisés sur %s Mo (plan Free, ≥ 80 %%). Au-delà, la base passe en lecture seule.',
        ROUND((v_db_size_bytes / 1048576.0)::numeric, 1),
        v_db_limit_bytes / 1048576
      ),
      'scaling_metrics',
      jsonb_build_object(
        'kind', 'threshold_warning',
        'metric', 'db_size',
        'value', ROUND((v_db_size_bytes / 1048576.0)::numeric, 1),
        'max', v_db_limit_bytes / 1048576
      )
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
