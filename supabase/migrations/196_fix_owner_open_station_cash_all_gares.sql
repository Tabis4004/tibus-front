-- Bug : un compte "owner" pur (aucun role vendeur/vendeur_gare/chauffeur) ne
-- peut jamais ouvrir de caisse guichet, sur aucune gare de sa compagnie.
--
-- open_station_cash_register (migration 165) verifie d'abord que
-- l'utilisateur a un role de vente dans la compagnie via la liste
-- ('owner', 'vendeur', 'vendeur_gare', 'chauffeur') -- owner y figure bien.
-- Mais plus loin, le calcul de v_all_gares (acces a TOUTES les gares de la
-- compagnie plutot qu'a une seule gare assignee) ne teste que
-- ('vendeur', 'chauffeur') : owner en est absent. Sans role vendeur_gare
-- rattache a une gare precise (jamais le cas pour un owner), la fonction
-- tombe systematiquement sur "Ouverture reservee a votre gare assignee".
--
-- Constate sur SIS COURRIER (sanaibrahim911@gmail.com, role owner seul) :
-- caisse toujours fermee pour ce compte, donc tout le bloc de session
-- (Journal de caisse, Journal de vente, Remise, Cloture) invisible cote
-- courrier_mobile -- pas un bug de config ni de build, la caisse ne s'ouvre
-- simplement jamais. Corrige ici en alignant la liste de v_all_gares sur
-- celle du controle d'acces compagnie plus haut dans la meme fonction.

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
    -- Compagnie active choisie cote client : l'utilisateur doit y detenir
    -- un role de vente.
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

  -- 'owner' ajoute ici (absent avant ce correctif) : un owner doit pouvoir
  -- ouvrir une caisse sur n'importe quelle gare de sa compagnie, au meme
  -- titre qu'un vendeur ou un chauffeur, sans avoir besoin d'un role
  -- vendeur_gare distinct rattache a une gare precise.
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND ur."companyId" = v_company_id
        AND r.name IN ('owner', 'vendeur', 'chauffeur')
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
