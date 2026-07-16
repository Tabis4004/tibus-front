-- Statistiques colis autonome calculées côté base (au lieu du calcul
-- client sur list_colis_autonomes limité à 1000 lignes, voir
-- courrier_mobile/lib/data/services/stats_service.dart) — avec filtres
-- optionnels par agent (vendeur), gare de départ et période, et un bloc
-- "mine" toujours scopé à l'utilisateur connecté (indépendant du filtre
-- vendeur) pour la carte "Mes ventes" côté owner.
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
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  WITH filtered AS (
    SELECT ca.*
    FROM public.colis_autonomes ca
    WHERE ca.company_id = p_company_id
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
    'mineMontantTotal', (SELECT COALESCE(SUM(montant_fret), 0) FROM mine)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- Liste des agents (vendeur_id) ayant enregistré au moins un colis pour
-- cette compagnie — alimente le filtre "par agent" côté Stats. Même garde
-- d'accès (is_company_role_user) que les autres RPC du module.
CREATE OR REPLACE FUNCTION public.list_company_colis_vendeurs(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_rows jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
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
    WHERE ca.company_id = p_company_id AND ca.vendeur_id IS NOT NULL
  ) v
  JOIN "Users" u ON u.id = v.vendeur_id;

  RETURN v_rows;
END;
$function$;
