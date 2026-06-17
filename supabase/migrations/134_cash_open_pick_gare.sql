-- Ouverture caisse guichet : selection d'une vraie gare (plus de hub invisible seul).

DROP FUNCTION IF EXISTS public.open_station_cash_register(uuid, integer);

CREATE OR REPLACE FUNCTION public.open_station_cash_register(
  p_gare_id uuid DEFAULT NULL::uuid,
  p_fond_roulement integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_gare_id uuid;
  v_gare_name text;
  v_id uuid;
  v_fond integer;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  v_fond := GREATEST(COALESCE(p_fond_roulement, 0), 0);
  v_company_id := public.resolve_seller_company_id(v_user_id);
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Ouverture reservee aux vendeurs rattaches a une compagnie';
  END IF;
  IF NOT public.can_operate_station_cash(v_company_id) THEN
    RAISE EXCEPTION 'Ouverture caisse non autorisee pour ce compte';
  END IF;
  IF p_gare_id IS NULL THEN
    RAISE EXCEPTION 'Selectionnez une gare pour ouvrir la caisse';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM "Gares" g
    WHERE g.id = p_gare_id
      AND g."companyId" = v_company_id
      AND g.name <> '__CASH_SESSION_HUB__'
      AND g.name NOT LIKE '\_\_%'
  ) THEN
    RAISE EXCEPTION 'Gare invalide pour cette compagnie';
  END IF;
  IF EXISTS (
    SELECT 1 FROM caisses_gares c
    WHERE c.gestionnaire_id = v_user_id
      AND c.statut IN ('ouverte', 'en_reversement')
  ) THEN
    RAISE EXCEPTION 'Une session de caisse est deja active ou en attente de validation';
  END IF;

  v_gare_id := p_gare_id;
  SELECT g.name::text INTO v_gare_name FROM "Gares" g WHERE g.id = v_gare_id;

  INSERT INTO caisses_gares (gare_id, gestionnaire_id, solde_especes_actuel, statut, fond_roulement, opened_at)
  VALUES (v_gare_id, v_user_id, v_fond, 'ouverte', v_fond, now())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'gareId', v_gare_id,
    'gareName', v_gare_name,
    'sessionLabel', v_gare_name,
    'balance', v_fond,
    'openingFloat', v_fond,
    'status', 'ouverte'
  );
END;
$$;

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
  SELECT c.*, g.name AS gare_name INTO v_row
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
    'status', v_row.statut
  );
END;
$$;
