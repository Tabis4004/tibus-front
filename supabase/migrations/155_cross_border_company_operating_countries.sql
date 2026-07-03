-- Allows a company to create Gares in cities outside its home country,
-- for cross-border itineraries, via an explicit super-admin-managed
-- whitelist rather than opening the constraint entirely.

-- 1. Whitelist table: countries a company is explicitly authorized to
--    operate gares in, in addition to its home country (Companies."countryId").
CREATE TABLE public."CompanyOperatingCountries" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES public."Companies"(id) ON DELETE CASCADE,
  "countryId" uuid NOT NULL REFERENCES public."Countries"(id) ON DELETE CASCADE,
  "isActive" boolean NOT NULL DEFAULT true,
  "authorizedBy" uuid REFERENCES public."Users"(id),
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("companyId", "countryId")
);

-- Fail-closed by default: no direct PostgREST access, only via the
-- SECURITY DEFINER admin functions below.
ALTER TABLE public."CompanyOperatingCountries" ENABLE ROW LEVEL SECURITY;

-- 2. Relax the Gares trigger: allow the company's home country (unchanged
--    behaviour) OR any country explicitly whitelisted for that company.
CREATE OR REPLACE FUNCTION public.tg_validate_gare_city_in_company_country()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "Companies" co
    JOIN "Cities" ci ON ci."countryId" = co."countryId"
    WHERE co.id = NEW."companyId" AND ci.id = NEW."cityId"
  ) THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM "CompanyOperatingCountries" coc
    JOIN "Cities" ci ON ci."countryId" = coc."countryId"
    WHERE coc."companyId" = NEW."companyId"
      AND coc."isActive" = true
      AND ci.id = NEW."cityId"
  ) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'La ville de la gare doit appartenir au pays de la compagnie ou a un pays d''operation autorise';
END;
$function$;

-- 3. Super-admin only management of the whitelist (mirrors the existing
--    admin_* authorization pattern used elsewhere in the schema).
CREATE OR REPLACE FUNCTION public.admin_grant_company_operating_country(p_company_id uuid, p_country_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_admin_id uuid;
  v_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF p_company_id IS NULL OR p_country_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie et pays requis';
  END IF;

  v_admin_id := public.current_app_user_id();

  INSERT INTO "CompanyOperatingCountries" ("companyId", "countryId", "isActive", "authorizedBy")
  VALUES (p_company_id, p_country_id, true, v_admin_id)
  ON CONFLICT ("companyId", "countryId")
  DO UPDATE SET "isActive" = true, "authorizedBy" = v_admin_id
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_revoke_company_operating_country(p_company_id uuid, p_country_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  UPDATE "CompanyOperatingCountries"
  SET "isActive" = false
  WHERE "companyId" = p_company_id AND "countryId" = p_country_id;
END;
$function$;

-- New admin-only mutators: no legitimate reason for a logged-out client
-- to reach them directly.
REVOKE EXECUTE ON FUNCTION public.admin_grant_company_operating_country(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_revoke_company_operating_country(uuid, uuid) FROM PUBLIC, anon;
