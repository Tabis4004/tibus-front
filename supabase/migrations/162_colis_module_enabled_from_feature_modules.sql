-- Bug « Impossible d'ajouter une nature de colis » : les RPC colis
-- (upsert_colis_nature, etc.) vérifiaient l'ancienne colonne
-- Companies.colis_autonome_enabled, alors que la source officielle des
-- modules est CompanyFeatureModules (module D) — dont les défauts
-- (get_company_feature_modules) considèrent D actif quand aucune ligne
-- n'existe. L'UI affichait donc le module comme actif pendant que les RPC
-- le refusaient. Alignement : même règle que get_company_feature_modules,
-- avec l'ancienne colonne conservée comme activation legacy.

CREATE OR REPLACE FUNCTION public.company_colis_module_enabled(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (SELECT m."moduleD" FROM "CompanyFeatureModules" m WHERE m."companyId" = p_company_id),
    -- Pas de ligne modules : mêmes défauts que get_company_feature_modules
    -- (module D actif par défaut).
    true
  )
  OR COALESCE(
    (SELECT c.colis_autonome_enabled FROM "Companies" c WHERE c.id = p_company_id),
    false
  );
$function$;
