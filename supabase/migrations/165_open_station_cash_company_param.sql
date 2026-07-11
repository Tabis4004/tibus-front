-- Vendeur multi-compagnies : « Gare invalide pour cette compagnie » à
-- l'ouverture de caisse. open_station_cash_register résolvait la compagnie
-- côté serveur via resolve_seller_company_id (priorité owner > vendeur…),
-- qui peut retourner une AUTRE compagnie que celle affichée par l'UI quand
-- l'utilisateur a des rôles de vente dans plusieurs compagnies. La gare
-- sélectionnée (compagnie active côté client) était alors rejetée.
-- Correctif : la RPC accepte p_company_id (compagnie active du dashboard),
-- vérifie que l'utilisateur y détient bien un rôle de vente, et ne retombe
-- sur resolve_seller_company_id qu'en absence du paramètre (anciens clients).

DROP FUNCTION IF EXISTS public.open_station_cash_register(uuid, integer);

CREATE OR REPLACE FUNCTION public.open_station_cash_register(
  p_gare_id uuid DEFAULT NULL::uuid,
  p_fond_roulement integer DEFAULT 0,
  p_company_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  IF p_company_id IS NOT NULL THEN
    -- Compagnie active choisie côté client : l'utilisateur doit y détenir
    -- un rôle de vente.
    IF NOT EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND ur."companyId" = p_company_id
        AND r.name IN ('owner', 'vendeur', 'vendeur_gare', 'chauffeur')
    ) AND NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'Aucun role de vente dans cette compagnie';
    END IF;
    v_company_id := p_company_id;
  ELSE
    v_company_id := public.resolve_seller_company_id(v_user_id);
  END IF;

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
$function$;

REVOKE EXECUTE ON FUNCTION public.open_station_cash_register(uuid, integer, uuid) FROM PUBLIC, anon;
