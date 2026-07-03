-- Supports the country -> city cascading dropdown on the gare creation
-- form: returns every country a company can pick from (its home country +
-- any country granted via CompanyOperatingCountries), gated by the same
-- permission required to actually write a Gare
-- (has_company_droit(companyId, 'manage_stations')).
CREATE OR REPLACE FUNCTION public.list_company_available_countries(p_company_id uuid)
RETURNS TABLE ("countryId" uuid, "countryName" character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT c.id, c.name
  FROM "Companies" co
  JOIN "Countries" c ON c.id = co."countryId"
  WHERE co.id = p_company_id
    AND (public.is_super_admin() OR public.has_company_droit(p_company_id, 'manage_stations'))

  UNION

  SELECT c.id, c.name
  FROM "CompanyOperatingCountries" coc
  JOIN "Countries" c ON c.id = coc."countryId"
  WHERE coc."companyId" = p_company_id
    AND coc."isActive" = true
    AND (public.is_super_admin() OR public.has_company_droit(p_company_id, 'manage_stations'));
$function$;

REVOKE EXECUTE ON FUNCTION public.list_company_available_countries(uuid) FROM PUBLIC, anon;
