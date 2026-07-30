-- Suite du correctif 196 : l'ajout de 'owner' dans open_station_cash_register
-- ne suffisait pas, can_operate_station_cash() (verifiee EN AMONT dans la
-- meme fonction) excluait aussi 'owner' -- d'ou "Ouverture caisse non
-- autorisee pour ce compte" constate juste apres 196.
--
-- Demande explicite : un owner doit avoir TOUS les droits disponibles dans
-- sa compagnie plutot que d'etre ajoute au coup par coup a chaque liste de
-- roles. can_operate_station_cash() et list_company_station_gares() (meme
-- verification "toutes les gares", dupliquee) sont donc alignees ici sur la
-- meme logique.

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
        AND r.name IN ('owner', 'vendeur', 'vendeur_gare', 'chauffeur')
    );
$$;

-- NB : la version de list_company_station_gares appliquee ici a ete affinee
-- par la migration suivante (198), qui restaure exactement la requete de la
-- branche "gare assignee" de la migration 148. Voir 198 pour la version
-- finale.
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
        AND r.name IN ('owner', 'vendeur', 'chauffeur')
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
  FROM public."Gares" g
  JOIN public."UserRoles" ur ON ur."gareId" = g.id
  JOIN public."Role" r ON r.id = ur."roleId"
  WHERE g."companyId" = p_company_id
    AND ur."userId" = v_user
    AND r.name = 'vendeur_gare'
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY g.name;
END;
$$;
