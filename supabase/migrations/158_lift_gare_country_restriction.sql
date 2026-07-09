-- 158_lift_gare_country_restriction.sql
--
-- Décision produit explicite : une compagnie peut créer des gares dans
-- N'IMPORTE QUEL pays disponible sur la plateforme, pas seulement son pays
-- d'origine ou une liste blanche de pays autorisés. Le mécanisme de liste
-- blanche introduit en migration 155/156 (table CompanyOperatingCountries,
-- RPCs admin_grant/revoke_company_operating_country, trigger de validation)
-- continuait de bloquer certaines gares transfrontalières en pratique. On
-- simplifie donc en levant complètement la contrainte pays côté trigger.
--
-- La table CompanyOperatingCountries et les RPCs admin_grant/revoke restent
-- en place (pas de perte de données), mais n'ont plus aucun effet bloquant :
-- ils ne sont plus consultés par le trigger. Le panneau admin correspondant
-- a été retiré du frontend (CompanyOperatingCountriesPanel.tsx, plus monté).

CREATE OR REPLACE FUNCTION public.tg_validate_gare_city_in_company_country()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Restriction pays levée : une compagnie peut opérer (créer des gares)
  -- dans n'importe quel pays disponible sur la plateforme (itinéraires
  -- transfrontaliers). Le pays d'origine reste utilisé ailleurs pour la
  -- devise/paramètres par défaut de la compagnie, mais ne bloque plus la
  -- création de gares.
  RETURN NEW;
END;
$function$;
