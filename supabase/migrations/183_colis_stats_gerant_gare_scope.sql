-- Stats colis : le gérant de gare (gerant_gare / gestionnaire_gare legacy)
-- voit l'activité de SA (ses) gare(s) — tous vendeurs confondus, filtre par
-- agent autorisé dans ce périmètre. Les autres rôles non privilégiés restent
-- forcés sur leur propre activité (migration 182).
-- APPLIQUÉE EN PRODUCTION (apply_migration colis_stats_gerant_gare_scope).

CREATE OR REPLACE FUNCTION public._colis_stats_gerant_gares(p_user_id uuid, p_company_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT array_agg(DISTINCT ur."gareId")
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = p_user_id
    AND ur."companyId" = p_company_id
    AND ur."gareId" IS NOT NULL
    AND r.name IN ('gerant_gare', 'gestionnaire_gare');
$$;

CREATE OR REPLACE FUNCTION public.get_colis_autonome_stats(
  p_company_id uuid,
  p_vendeur_id uuid DEFAULT NULL::uuid,
  p_gare_depart_id uuid DEFAULT NULL::uuid,
  p_date_from timestamptz DEFAULT NULL::timestamptz,
  p_date_to timestamptz DEFAULT NULL::timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_result jsonb;
  v_full_access boolean;
  v_gerant_gares uuid[];
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_full_access := public._colis_stats_full_access(v_user_id, p_company_id);
  IF NOT v_full_access THEN
    v_gerant_gares := public._colis_stats_gerant_gares(v_user_id, p_company_id);
    IF v_gerant_gares IS NULL THEN
      -- Rôle simple : uniquement SA propre activité.
      p_vendeur_id := v_user_id;
    END IF;
    -- Gérant : périmètre = ses gares (v_gerant_gares appliqué ci-dessous),
    -- filtre par agent autorisé DANS ce périmètre.
  END IF;

  WITH filtered AS (
    SELECT ca.*
    FROM public.colis_autonomes ca
    WHERE ca.company_id = p_company_id
      AND (v_gerant_gares IS NULL OR ca.gare_depart_id = ANY(v_gerant_gares))
      AND (p_vendeur_id IS NULL OR ca.vendeur_id = p_vendeur_id)
      AND (p_gare_depart_id IS NULL OR ca.gare_depart_id = p_gare_depart_id)
      AND (p_date_from IS NULL OR ca.created_at >= p_date_from)
      AND (p_date_to IS NULL OR ca.created_at < p_date_to)
  ),
  mine AS (
    SELECT ca.*
    FROM public.colis_autonomes ca
    WHERE ca.company_id = p_company_id
      AND ca.vendeur_id = v_user_id
      AND (p_gare_depart_id IS NULL OR ca.gare_depart_id = p_gare_depart_id)
      AND (p_date_from IS NULL OR ca.created_at >= p_date_from)
      AND (p_date_to IS NULL OR ca.created_at < p_date_to)
  )
  SELECT jsonb_build_object(
    'total', (SELECT COUNT(*) FROM filtered),
    'montantTotal', (SELECT COALESCE(SUM(montant_fret), 0) FROM filtered),
    'today', (SELECT COUNT(*) FROM filtered WHERE created_at::date = now()::date),
    'montantToday', (SELECT COALESCE(SUM(montant_fret), 0) FROM filtered WHERE created_at::date = now()::date),
    'thisMonth', (SELECT COUNT(*) FROM filtered WHERE date_trunc('month', created_at) = date_trunc('month', now())),
    'montantThisMonth', (SELECT COALESCE(SUM(montant_fret), 0) FROM filtered WHERE date_trunc('month', created_at) = date_trunc('month', now())),
    'delivered', (SELECT COUNT(*) FROM filtered WHERE statut_colis = 'livre'),
    'pending', (SELECT COUNT(*) FROM filtered WHERE statut_colis <> 'livre'),
    'mineTotal', (SELECT COUNT(*) FROM mine),
    'mineMontantTotal', (SELECT COALESCE(SUM(montant_fret), 0) FROM mine),
    'fullAccess', v_full_access,
    'gareScope', v_gerant_gares IS NOT NULL
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_company_colis_vendeurs(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_rows jsonb;
  v_gerant_gares uuid[];
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF NOT public._colis_stats_full_access(v_user_id, p_company_id) THEN
    v_gerant_gares := public._colis_stats_gerant_gares(v_user_id, p_company_id);
    IF v_gerant_gares IS NULL THEN
      RETURN '[]'::jsonb;
    END IF;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', u.id,
        'name', COALESCE(NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), ''), u.username)
      )
      ORDER BY COALESCE(NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), ''), u.username)
    ),
    '[]'::jsonb
  )
  INTO v_rows
  FROM (
    SELECT DISTINCT ca.vendeur_id
    FROM public.colis_autonomes ca
    WHERE ca.company_id = p_company_id
      AND ca.vendeur_id IS NOT NULL
      AND (v_gerant_gares IS NULL OR ca.gare_depart_id = ANY(v_gerant_gares))
  ) v
  JOIN "Users" u ON u.id = v.vendeur_id;

  RETURN v_rows;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._colis_stats_gerant_gares(uuid, uuid) FROM PUBLIC, anon;
