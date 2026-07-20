-- « Journal de vente » colis — liste détaillée (référence, expéditeur,
-- destinataire, frais, valeur déclarée, destination) sur une plage de
-- dates, groupée par vendeur avec sous-total, + total général. Format
-- calqué sur un journal papier de référence fourni par le promoteur
-- (référence + date/heure + agent, puis expéditeur/destinataire, frais/
-- valeur/destination, sous-total « Total: <agent> » par vendeur, total
-- général en bas).
--
-- Même principe de scoping que get_colis_autonome_stats (migration 183) :
-- owner/comptable_compagnie/super_admin voient TOUTE la compagnie
-- (multi-agents) ; gerant_gare voit l'activité de SA (ses) gare(s), tous
-- vendeurs confondus ; les autres rôles (vendeur, vendeur_gare, chauffeur…)
-- sont forcés sur LEUR SEULE activité, quel que soit p_vendeur_id demandé —
-- c'est le cas d'usage principal côté app agent (impression de son propre
-- journal en fin de session).
CREATE OR REPLACE FUNCTION public.get_colis_sales_journal(
  p_company_id uuid,
  p_date_from timestamptz,
  p_date_to timestamptz DEFAULT NULL::timestamptz,
  p_vendeur_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_full_access boolean;
  v_gerant_gares uuid[];
  v_date_to timestamptz := COALESCE(p_date_to, p_date_from + interval '1 day');
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_full_access := public._colis_stats_full_access(v_user_id, p_company_id);
  IF NOT v_full_access THEN
    v_gerant_gares := public._colis_stats_gerant_gares(v_user_id, p_company_id);
    IF v_gerant_gares IS NULL THEN
      -- Rôle simple (vendeur, vendeur_gare, chauffeur...) : uniquement SA
      -- propre activité, quel que soit le filtre demandé par le client.
      p_vendeur_id := v_user_id;
    END IF;
  END IF;

  WITH filtered AS (
    SELECT
      ca.id,
      ca.numero_recu,
      ca.created_at,
      ca.nom_expediteur,
      ca.nom_destinataire,
      ca.montant_fret,
      ca.valeur_marchandise,
      ca.vendeur_id,
      gdest.name AS gare_destination
    FROM public.colis_autonomes ca
    JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id
    WHERE ca.company_id = p_company_id
      AND ca.statut_colis <> 'annule'
      AND (v_gerant_gares IS NULL OR ca.gare_depart_id = ANY(v_gerant_gares))
      AND (p_vendeur_id IS NULL OR ca.vendeur_id = p_vendeur_id)
      AND ca.created_at >= p_date_from
      AND ca.created_at < v_date_to
  ),
  by_vendeur AS (
    SELECT
      f.vendeur_id,
      COALESCE(NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), ''), u.username, 'Agent inconnu') AS vendeur_name,
      u.username AS vendeur_username,
      jsonb_agg(
        jsonb_build_object(
          'id', f.id,
          'numeroRecu', f.numero_recu,
          'createdAt', f.created_at,
          'nomExpediteur', f.nom_expediteur,
          'nomDestinataire', f.nom_destinataire,
          'montantFret', f.montant_fret,
          'valeurMarchandise', f.valeur_marchandise,
          'gareDestination', f.gare_destination
        )
        ORDER BY f.created_at
      ) AS colis,
      COUNT(*) AS cnt,
      COALESCE(SUM(f.montant_fret), 0) AS total_frais,
      COALESCE(SUM(f.valeur_marchandise), 0) AS total_valeur
    FROM filtered f
    LEFT JOIN "Users" u ON u.id = f.vendeur_id
    GROUP BY f.vendeur_id, u."firstName", u."lastName", u.username
  )
  SELECT jsonb_build_object(
    'groups', COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'vendeurId', bv.vendeur_id,
          'vendeurName', bv.vendeur_name,
          'vendeurUsername', bv.vendeur_username,
          'colis', bv.colis,
          'count', bv.cnt,
          'totalFrais', bv.total_frais,
          'totalValeur', bv.total_valeur
        )
        ORDER BY bv.vendeur_name
      ) FROM by_vendeur bv),
      '[]'::jsonb
    ),
    'grandCount', (SELECT COALESCE(SUM(cnt), 0) FROM by_vendeur),
    'grandTotalFrais', (SELECT COALESCE(SUM(total_frais), 0) FROM by_vendeur),
    'grandTotalValeur', (SELECT COALESCE(SUM(total_valeur), 0) FROM by_vendeur),
    'fullAccess', v_full_access,
    'gareScope', v_gerant_gares IS NOT NULL
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_colis_sales_journal(uuid, timestamptz, timestamptz, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_colis_sales_journal(uuid, timestamptz, timestamptz, uuid) TO authenticated;
