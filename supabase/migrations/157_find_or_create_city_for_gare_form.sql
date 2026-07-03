-- Autocomplete ville du formulaire gare : si la ville saisie n'existe pas
-- encore dans "Cities" pour le pays sélectionné, un owner (droit
-- manage_stations) ou un super_admin peut la créer. Déduplication
-- insensible à la casse ET aux accents (unaccent) : « Bohicon », « BOHICON »
-- et « Bohìcon » pointent vers la même ligne. La ville créée est partagée :
-- elle apparaît pour toutes les compagnies opérant dans ce pays.

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.find_or_create_city(
  p_company_id uuid,
  p_country_id uuid,
  p_name character varying
)
RETURNS TABLE ("cityId" uuid, "cityName" character varying, "created" boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_name character varying := btrim(p_name);
  v_norm text;
  v_id uuid;
  v_existing character varying;
BEGIN
  IF NOT (public.is_super_admin() OR public.has_company_droit(p_company_id, 'manage_stations')) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF p_country_id IS NULL OR v_name IS NULL OR length(v_name) < 2 THEN
    RAISE EXCEPTION 'Pays et nom de ville requis';
  END IF;

  -- Même règle que le trigger des Gares : pays d'origine de la compagnie
  -- ou pays d'opération explicitement autorisé (transfrontalier).
  IF NOT EXISTS (
    SELECT 1 FROM "Companies" co
    WHERE co.id = p_company_id AND co."countryId" = p_country_id
  ) AND NOT EXISTS (
    SELECT 1 FROM "CompanyOperatingCountries" coc
    WHERE coc."companyId" = p_company_id
      AND coc."countryId" = p_country_id
      AND coc."isActive" = true
  ) THEN
    RAISE EXCEPTION 'Pays non autorise pour cette compagnie';
  END IF;

  v_norm := lower(extensions.unaccent(v_name));

  SELECT c.id, c.name INTO v_id, v_existing
  FROM "Cities" c
  WHERE c."countryId" = p_country_id
    AND lower(extensions.unaccent(c.name)) = v_norm
  ORDER BY c.name
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN QUERY SELECT v_id, v_existing, false;
    RETURN;
  END IF;

  INSERT INTO "Cities" (name, "countryId")
  VALUES (v_name, p_country_id)
  RETURNING "Cities".id, "Cities".name INTO v_id, v_existing;

  RETURN QUERY SELECT v_id, v_existing, true;
END;
$function$;

-- Mutateur sensible : jamais accessible aux clients anonymes.
REVOKE EXECUTE ON FUNCTION public.find_or_create_city(uuid, uuid, character varying) FROM PUBLIC, anon;
