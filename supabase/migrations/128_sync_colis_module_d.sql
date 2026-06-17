-- Aligne colis_autonome_enabled (Companies) avec le module commercial D.

UPDATE "Companies" c
SET colis_autonome_enabled = true
FROM "CompanyFeatureModules" m
WHERE m."companyId" = c.id
  AND m."moduleD" IS TRUE
  AND c.colis_autonome_enabled IS DISTINCT FROM true;

UPDATE "Companies" c
SET colis_autonome_enabled = false
FROM "CompanyFeatureModules" m
WHERE m."companyId" = c.id
  AND m."moduleD" IS FALSE
  AND c.colis_autonome_enabled IS DISTINCT FROM false;

CREATE OR REPLACE FUNCTION public.sync_colis_autonome_from_module_d()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE "Companies"
  SET colis_autonome_enabled = COALESCE(NEW."moduleD", false)
  WHERE id = NEW."companyId";
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_colis_module_d ON "CompanyFeatureModules";

CREATE TRIGGER trg_sync_colis_module_d
  AFTER INSERT OR UPDATE OF "moduleD" ON "CompanyFeatureModules"
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_colis_autonome_from_module_d();
