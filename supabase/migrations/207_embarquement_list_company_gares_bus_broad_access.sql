-- ============================================================================
-- Embarquement — lecture des VRAIES Gares/Bus de la compagnie (celles gérées
-- via l'administration Tibus existante : list_company_gares_admin /
-- list_company_bus_admin, réservées au rôle owner) pour alimenter
-- l'ouverture de session hors-Tibus SANS ressaisie séparée. Ces deux
-- fonctions reprennent la même requête que les versions "_admin" mais avec
-- une garde can_use_embarquement (tous les rôles Embarquement) au lieu de
-- owner uniquement — une fois qu'un owner a déclaré ses gares/bus via
-- Administration, tout agent Embarquement doit pouvoir les lire pour ouvrir
-- une session, pas seulement l'owner.
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-04
-- (nom de migration côté Supabase :
-- embarquement_list_company_gares_bus_broad_access).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.embarquement_list_company_gares(p_company_id uuid)
RETURNS TABLE(id uuid, name text, "cityName" text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT g.id, g.name::text, c.name::text
  FROM "Gares" g JOIN "Cities" c ON c.id = g."cityId"
  WHERE g."companyId" = p_company_id AND g."isActive"
    AND g.name <> '__CASH_SESSION_HUB__' AND g.name NOT LIKE '\_\_%'
  ORDER BY g.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_list_company_bus(p_company_id uuid)
RETURNS TABLE(id uuid, "registrationNumber" text, model text, capacity integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT b.id, b."registrationNumber"::text, b.model::text, b.capacity
  FROM "Bus" b
  WHERE b."companyId" = p_company_id AND b."isActive"
  ORDER BY b."registrationNumber";
END;
$$;
