-- Bug de prod découvert en direct (20/08/2026, capture d'écran utilisateur) :
-- "Villes/gares indisponibles : ... for SELECT DISTINCT, ORDER BY
-- expressions must appear in select list, code: 42P10".
--
-- Cause : SELECT DISTINCT c.id, c.name::text ... ORDER BY c.name -- avec
-- SELECT DISTINCT, Postgres exige que les expressions de ORDER BY
-- correspondent EXACTEMENT (syntaxiquement) aux expressions du select
-- list. `c.name::text` (select) et `c.name` (order by) sont deux
-- expressions différentes à ses yeux (le cast change la signature), d'où
-- le rejet -- bloquait le sélecteur "Ville de départ" de la création de
-- lot (migration 202).
--
-- Fix : trier sur le même alias que celui projeté.
CREATE OR REPLACE FUNCTION public.list_company_villes_depart(p_company_id uuid)
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT DISTINCT c.id, c.name::text AS name
  FROM public."Cities" c
  JOIN public."Gares" g ON g."cityId" = c.id
  WHERE g."companyId" = p_company_id
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY name;
END;
$function$;
