-- =============================================================================
-- Tibus 048 — Caisse vendeur : session journalière + reversement consolidé
-- =============================================================================
-- Flux :
--   1. Vendeur ouvre sa caisse (fond de roulement) — une session / jour
--   2. Ventes cash créditent la session (tous trajets de la compagnie)
--   3. Fin de service : vendeur soumet un reversement → caisse en attente
--   4. Comptable ou owner valide → caisse clôturée, mouvement consolidé
-- =============================================================================

-- Statut intermédiaire : session fermée côté vendeur, en attente validation
ALTER TABLE caisses_gares DROP CONSTRAINT IF EXISTS caisses_gares_statut_check;
ALTER TABLE caisses_gares ADD CONSTRAINT caisses_gares_statut_check
  CHECK (statut IN ('ouverte', 'en_reversement', 'cloturee'));

DROP INDEX IF EXISTS caisses_gares_open_gare_gestionnaire_idx;
DROP INDEX IF EXISTS caisses_gares_open_gestionnaire_idx;
CREATE UNIQUE INDEX IF NOT EXISTS caisses_gares_open_gestionnaire_idx
  ON caisses_gares (gestionnaire_id)
  WHERE statut IN ('ouverte', 'en_reversement');

CREATE OR REPLACE FUNCTION public.can_operate_station_cash(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['vendeur']);
$$;

CREATE OR REPLACE FUNCTION public.resolve_seller_company_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ur."companyId"
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = p_user_id
    AND ur."companyId" IS NOT NULL
    AND r.name = 'vendeur'
  ORDER BY ur."assignedAt" DESC NULLS LAST
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.resolve_company_default_gare_id(p_company_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT g.id
  FROM "Gares" g
  WHERE g."companyId" = p_company_id
  ORDER BY g.name
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.open_station_cash_register(
  p_gare_id uuid DEFAULT NULL,
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
  v_id uuid;
  v_fond integer;
  v_gare_name text;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  v_fond := GREATEST(COALESCE(p_fond_roulement, 0), 0);
  v_company_id := public.resolve_seller_company_id(v_user_id);

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Ouverture reservee aux vendeurs rattaches a une compagnie';
  END IF;

  IF NOT public.can_operate_station_cash(v_company_id) THEN
    RAISE EXCEPTION 'Ouverture caisse non autorisee pour ce compte';
  END IF;

  IF EXISTS (
    SELECT 1 FROM caisses_gares c
    WHERE c.gestionnaire_id = v_user_id
      AND c.statut IN ('ouverte', 'en_reversement')
  ) THEN
    RAISE EXCEPTION 'Une session de caisse est deja active ou en attente de validation';
  END IF;

  v_gare_id := p_gare_id;
  IF v_gare_id IS NULL THEN
    v_gare_id := public.resolve_company_default_gare_id(v_company_id);
  END IF;

  IF v_gare_id IS NULL THEN
    RAISE EXCEPTION 'Aucune gare configuree — creez au moins une gare dans Parametrage > Gares';
  END IF;

  IF public.station_cash_gare_company_id(v_gare_id) IS DISTINCT FROM v_company_id THEN
    RAISE EXCEPTION 'Gare non autorisee pour votre compagnie';
  END IF;

  SELECT g.name INTO v_gare_name FROM "Gares" g WHERE g.id = v_gare_id;

  INSERT INTO caisses_gares (
    gare_id, gestionnaire_id, solde_especes_actuel, statut, fond_roulement, opened_at
  ) VALUES (
    v_gare_id, v_user_id, v_fond, 'ouverte', v_fond, now()
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'gareId', v_gare_id,
    'gareName', v_gare_name,
    'balance', v_fond,
    'openingFloat', v_fond,
    'status', 'ouverte'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_seller_open_caisse_id(
  p_user_id uuid,
  p_company_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id
  FROM caisses_gares c
  JOIN "Gares" g ON g.id = c.gare_id
  WHERE c.gestionnaire_id = p_user_id
    AND c.statut = 'ouverte'
    AND g."companyId" = p_company_id
  ORDER BY c.opened_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_open_station_cash_for_user(p_gare_id uuid DEFAULT NULL)
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
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  SELECT c.*, g.name AS gare_name INTO v_row
  FROM caisses_gares c
  JOIN "Gares" g ON g.id = c.gare_id
  WHERE c.gestionnaire_id = v_user_id
    AND c.statut IN ('ouverte', 'en_reversement')
    AND (p_gare_id IS NULL OR c.gare_id = p_gare_id)
  ORDER BY c.opened_at DESC
  LIMIT 1;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('open', false);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM reversements_comptables r
    WHERE r.caisse_id = v_row.id AND r.statut_validation = 'en_attente'
  ) INTO v_pending;

  RETURN jsonb_build_object(
    'open', v_row.statut = 'ouverte',
    'pendingReversal', v_pending OR v_row.statut = 'en_reversement',
    'id', v_row.id,
    'gareId', v_row.gare_id,
    'gareName', v_row.gare_name,
    'balance', v_row.solde_especes_actuel,
    'openingFloat', v_row.fond_roulement,
    'openedAt', v_row.opened_at,
    'status', v_row.statut
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_station_cash_reversal(
  p_caisse_id uuid,
  p_montant_reverse integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_caisse record;
  v_id uuid;
  v_montant integer;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  v_montant := COALESCE(p_montant_reverse, 0);
  IF v_montant <= 0 THEN RAISE EXCEPTION 'Montant reversement invalide'; END IF;

  SELECT * INTO v_caisse FROM caisses_gares WHERE id = p_caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;

  IF v_caisse.gestionnaire_id <> v_user_id AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Reversement reserve au vendeur de la session';
  END IF;

  IF v_caisse.statut <> 'ouverte' THEN
    RAISE EXCEPTION 'Session deja fermee ou en attente de validation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM reversements_comptables r
    WHERE r.caisse_id = p_caisse_id AND r.statut_validation = 'en_attente'
  ) THEN
    RAISE EXCEPTION 'Un reversement est deja en attente';
  END IF;

  INSERT INTO reversements_comptables (caisse_id, montant_reverse, statut_validation, soumis_par)
  VALUES (p_caisse_id, v_montant, 'en_attente', v_user_id)
  RETURNING id INTO v_id;

  -- Fin de service vendeur : plus de ventes jusqu'a validation comptable/owner
  UPDATE caisses_gares
  SET statut = 'en_reversement'
  WHERE id = p_caisse_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'caisseId', p_caisse_id,
    'amount', v_montant,
    'status', 'en_attente',
    'currentBalance', v_caisse.solde_especes_actuel
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_seller_company_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_company_default_gare_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.open_station_cash_register(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_open_station_cash_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_seller_open_caisse_id(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_station_cash_reversal(uuid, integer) TO authenticated;
