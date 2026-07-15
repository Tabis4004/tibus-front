-- Bug "Gare de depart invalide" (courrier_mobile) + gares d'une autre
-- compagnie affichées à l'agent : get_open_station_cash_for_user ne
-- renvoyait pas la compagnie de la caisse ouverte. Les clients (web et
-- courrier_mobile) devaient donc deviner la "compagnie active" via une
-- heuristique côté rôle (première compagnie où l'utilisateur a un rôle
-- staff), qui peut diverger de la compagnie réelle de la caisse ouverte
-- pour un agent multi-compagnies — même classe de bug déjà corrigée côté
-- ouverture de caisse par open_station_cash_register (migration 165).
--
-- Correctif : la RPC renvoie désormais "companyId" (via la gare de la
-- caisse), pour que les clients puissent s'aligner sur la compagnie
-- réellement ouverte plutôt que de la re-deviner.

CREATE OR REPLACE FUNCTION public.get_open_station_cash_for_user(p_gare_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_row record;
  v_pending boolean;
  v_label text;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  SELECT c.*, g.name AS gare_name, g."companyId" AS company_id INTO v_row
  FROM caisses_gares c
  JOIN "Gares" g ON g.id = c.gare_id
  WHERE c.gestionnaire_id = v_user_id
    AND c.statut IN ('ouverte', 'en_reversement')
    AND (p_gare_id IS NULL OR c.gare_id = p_gare_id)
  ORDER BY c.opened_at DESC
  LIMIT 1;
  IF v_row.id IS NULL THEN RETURN jsonb_build_object('open', false); END IF;
  SELECT EXISTS (
    SELECT 1 FROM reversements_comptables r
    WHERE r.caisse_id = v_row.id AND r.statut_validation = 'en_attente'
  ) INTO v_pending;
  v_label := CASE
    WHEN v_row.gare_name = '__CASH_SESSION_HUB__' THEN 'Session caisse journaliere'
    ELSE v_row.gare_name
  END;
  RETURN jsonb_build_object(
    'open', v_row.statut = 'ouverte',
    'pendingReversal', v_pending OR v_row.statut = 'en_reversement',
    'id', v_row.id,
    'gareId', v_row.gare_id,
    'gareName', v_label,
    'sessionLabel', v_label,
    'balance', v_row.solde_especes_actuel,
    'openingFloat', v_row.fond_roulement,
    'openedAt', v_row.opened_at,
    'status', v_row.statut,
    'companyId', v_row.company_id
  );
END;
$$;
