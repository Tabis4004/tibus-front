-- 058 — Owner multi-compagnie (pays différents)
-- Exécuter après 017_owner_operations_rpc.sql et 046_user_role_management.sql

ALTER TABLE "Users"
  ADD COLUMN IF NOT EXISTS "activeOwnerCompanyId" uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Users_activeOwnerCompanyId_fkey'
  ) THEN
    ALTER TABLE "Users"
      ADD CONSTRAINT "Users_activeOwnerCompanyId_fkey"
      FOREIGN KEY ("activeOwnerCompanyId") REFERENCES "Companies"(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.current_owner_company_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_active uuid;
  v_fallback uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT u."activeOwnerCompanyId" INTO v_active
  FROM "Users" u
  WHERE u.id = v_user_id;

  IF v_active IS NOT NULL AND EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = v_active
      AND r.name = 'owner'
  ) THEN
    RETURN v_active;
  END IF;

  SELECT ur."companyId" INTO v_fallback
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user_id
    AND r.name = 'owner'
    AND ur."companyId" IS NOT NULL
  ORDER BY ur."companyId"
  LIMIT 1;

  RETURN v_fallback;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_owner_active_company(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifie';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie requise';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = p_company_id
      AND r.name = 'owner'
  ) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Compagnie non autorisee pour cet utilisateur';
  END IF;

  UPDATE "Users"
  SET "activeOwnerCompanyId" = p_company_id
  WHERE id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_owner_active_company(uuid) TO authenticated;
