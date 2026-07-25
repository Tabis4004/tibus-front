-- Courrier web compatibility: the live PostgREST schema exposes public.users,
-- while older helper functions referenced the legacy quoted table "Users".
-- Recreate the auth helper against public.users so RLS policies and RPCs used
-- by courrier-agent stop failing with relation "Users" does not exist.

CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id
  FROM public.users u
  WHERE u.auth_user_id = auth.uid()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.current_app_user_id() TO authenticated;

-- Some live environments are missing this RPC from migrations 134/170. Recreate
-- the latest shape expected by courrier_mobile and the web seller panel.
CREATE OR REPLACE FUNCTION public.get_open_station_cash_for_user(p_gare_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_row record;
  v_pending boolean;
  v_label text;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  SELECT c.*, g.name AS gare_name, g."companyId" AS company_id INTO v_row
  FROM public.caisses_gares c
  JOIN public."Gares" g ON g.id = c.gare_id
  WHERE c.gestionnaire_id = v_user_id
    AND c.statut IN ('ouverte', 'en_reversement')
    AND (p_gare_id IS NULL OR c.gare_id = p_gare_id)
  ORDER BY c.opened_at DESC
  LIMIT 1;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('open', false);
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.reversements_comptables r
    WHERE r.caisse_id = v_row.id
      AND r.statut_validation = 'en_attente'
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

GRANT EXECUTE ON FUNCTION public.get_open_station_cash_for_user(uuid) TO authenticated;

-- Ask PostgREST/Supabase API to reload function/table metadata immediately.
NOTIFY pgrst, 'reload schema';
