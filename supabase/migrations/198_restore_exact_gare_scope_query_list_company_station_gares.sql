-- Correctif de precision sur 197 : la branche "gare assignee uniquement" de
-- list_company_station_gares avait ete reecrite avec un FROM/JOIN legerement
-- different de l'original (148) -- filtre sur g."companyId" au lieu de
-- ur."companyId", sans le ur."gareId" IS NOT NULL explicite. Fonctionnellement
-- equivalent dans les donnees actuelles, mais on restaure la requete exacte
-- de la migration 148 pour ne rien laisser diverger sur une base en prod.

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
