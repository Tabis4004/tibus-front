-- =============================================================================
-- Tibus 148 — Caisse guichet : vendeur_gare, gares assignées, list_company_station_gares
-- =============================================================================

CREATE OR REPLACE FUNCTION public.resolve_seller_company_id(p_user_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := COALESCE(p_user_id, public.current_app_user_id());
BEGIN
  IF v_user IS NULL THEN RETURN NULL; END IF;

  RETURN (
    SELECT ur."companyId"
    FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user
      AND ur."companyId" IS NOT NULL
      AND r.name IN ('owner', 'vendeur', 'vendeur_gare', 'chauffeur')
    ORDER BY
      CASE r.name
        WHEN 'owner' THEN 1
        WHEN 'vendeur' THEN 2
        WHEN 'vendeur_gare' THEN 3
        WHEN 'chauffeur' THEN 4
      END,
      ur.id
    LIMIT 1
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_seller_company_id(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_operate_station_cash(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = public.current_app_user_id()
        AND ur."companyId" = p_company_id
        AND r.name IN ('vendeur', 'vendeur_gare', 'chauffeur')
    );
$$;

CREATE OR REPLACE FUNCTION public.list_company_station_gares(p_company_id uuid)
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_all_gares boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  IF NOT (
    public.is_super_admin()
    OR public.can_operate_station_cash(p_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces gares caisse refuse';
  END IF;

  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user
        AND ur."companyId" = p_company_id
        AND r.name IN ('vendeur', 'chauffeur')
    )
  INTO v_all_gares;

  IF v_all_gares THEN
    RETURN QUERY
    SELECT g.id, g.name::text
    FROM public."Gares" g
    WHERE g."companyId" = p_company_id
      AND g.name <> '__CASH_SESSION_HUB__'
      AND g.name NOT LIKE '\_\_%'
    ORDER BY g.name;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT g.id, g.name::text
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Gares" g ON g.id = ur."gareId"
  WHERE ur."userId" = v_user
    AND ur."companyId" = p_company_id
    AND ur."gareId" IS NOT NULL
    AND r.name = 'vendeur_gare'
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY g.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_station_gares(uuid) TO authenticated;

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
  v_all_gares boolean;
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
    FROM public."Gares" g
    WHERE g.id = p_gare_id
      AND g."companyId" = v_company_id
      AND g.name <> '__CASH_SESSION_HUB__'
      AND g.name NOT LIKE '\_\_%'
  ) THEN
    RAISE EXCEPTION 'Gare invalide pour cette compagnie';
  END IF;

  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND ur."companyId" = v_company_id
        AND r.name IN ('vendeur', 'chauffeur')
    )
  INTO v_all_gares;

  IF NOT v_all_gares AND NOT EXISTS (
    SELECT 1
    FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."gareId" = p_gare_id
      AND ur."companyId" = v_company_id
      AND r.name = 'vendeur_gare'
  ) THEN
    RAISE EXCEPTION 'Ouverture reservee a votre gare assignee';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.caisses_gares c
    WHERE c.gestionnaire_id = v_user_id
      AND c.statut IN ('ouverte', 'en_reversement')
  ) THEN
    RAISE EXCEPTION 'Une session de caisse est deja active ou en attente de validation';
  END IF;

  v_gare_id := p_gare_id;
  SELECT g.name::text INTO v_gare_name FROM public."Gares" g WHERE g.id = v_gare_id;

  INSERT INTO public.caisses_gares (gare_id, gestionnaire_id, solde_especes_actuel, statut, fond_roulement, opened_at)
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

GRANT EXECUTE ON FUNCTION public.open_station_cash_register(uuid, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
