-- =============================================================================
-- Tibus — Gestion utilisateurs / rôles (owner + super admin)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.assign_company_user_role_by_email(
  p_email text,
  p_role_name text DEFAULT 'vendeur'
)
RETURNS TABLE (
  id uuid,
  "firstName" varchar,
  "lastName" varchar,
  email varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_owner_user_id uuid;
  v_target_user_id uuid;
  v_role_id uuid;
BEGIN
  v_company_id := public.current_owner_company_id();
  v_owner_user_id := public.current_app_user_id();

  IF v_company_id IS NULL OR v_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_role_name NOT IN ('vendeur', 'controleur', 'comptable_compagnie') THEN
    RAISE EXCEPTION 'Role compagnie non autorise : %', p_role_name;
  END IF;

  SELECT r.id INTO v_role_id
  FROM "Role" r
  WHERE r.name = p_role_name AND r.scope = 'company'
  LIMIT 1;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role introuvable : %', p_role_name;
  END IF;

  SELECT u.id INTO v_target_user_id
  FROM "Users" u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Aucun utilisateur inscrit avec cet email';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_owner_user_id
      AND ur."companyId" = v_company_id
      AND r.name = 'owner'
  ) THEN
    RAISE EXCEPTION 'Action reservee au proprietaire de la compagnie';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    WHERE ur."userId" = v_target_user_id
      AND ur."roleId" = v_role_id
      AND ur."companyId" = v_company_id
  ) THEN
    INSERT INTO "UserRoles" (
      "roleId", "userId", "companyId", "countryId", "assignedBy"
    ) VALUES (
      v_role_id, v_target_user_id, v_company_id, NULL, v_owner_user_id
    );
  END IF;

  RETURN QUERY
  SELECT u.id, u."firstName", u."lastName", u.email
  FROM "Users" u WHERE u.id = v_target_user_id LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_company_user_role(
  p_user_id uuid,
  p_role_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_owner_user_id uuid;
  v_role_id uuid;
BEGIN
  v_company_id := public.current_owner_company_id();
  v_owner_user_id := public.current_app_user_id();

  IF v_company_id IS NULL OR v_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_role_name NOT IN ('vendeur', 'controleur', 'comptable_compagnie') THEN
    RAISE EXCEPTION 'Role compagnie non autorise : %', p_role_name;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_owner_user_id
      AND ur."companyId" = v_company_id
      AND r.name = 'owner'
  ) THEN
    RAISE EXCEPTION 'Action reservee au proprietaire de la compagnie';
  END IF;

  SELECT r.id INTO v_role_id FROM "Role" r
  WHERE r.name = p_role_name AND r.scope = 'company' LIMIT 1;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role introuvable : %', p_role_name;
  END IF;

  DELETE FROM "UserRoles"
  WHERE "userId" = p_user_id AND "roleId" = v_role_id AND "companyId" = v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_assign_user_role(
  p_user_id uuid,
  p_role_name text,
  p_company_id uuid DEFAULT NULL,
  p_country_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_assigner_id uuid;
  v_role_id uuid;
  v_scope varchar;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_assigner_id := public.current_app_user_id();

  SELECT r.id, r.scope INTO v_role_id, v_scope
  FROM "Role" r WHERE r.name = p_role_name LIMIT 1;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role introuvable : %', p_role_name;
  END IF;

  IF v_scope = 'company' AND p_company_id IS NULL THEN
    RAISE EXCEPTION 'companyId requis pour le role %', p_role_name;
  END IF;

  IF p_role_name = 'admin_pays' AND p_country_id IS NULL THEN
    RAISE EXCEPTION 'countryId requis pour admin_pays';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles"
    WHERE "userId" = p_user_id AND "roleId" = v_role_id
      AND ("companyId" IS NOT DISTINCT FROM p_company_id)
      AND ("countryId" IS NOT DISTINCT FROM CASE WHEN p_role_name = 'admin_pays' THEN p_country_id ELSE NULL END)
  ) THEN
    INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId", "assignedBy")
    VALUES (
      v_role_id, p_user_id,
      CASE WHEN v_scope = 'company' THEN p_company_id ELSE NULL END,
      CASE WHEN p_role_name = 'admin_pays' THEN p_country_id ELSE NULL END,
      v_assigner_id
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_user_role(
  p_user_id uuid,
  p_role_name text,
  p_company_id uuid DEFAULT NULL,
  p_country_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT r.id INTO v_role_id FROM "Role" r WHERE r.name = p_role_name LIMIT 1;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role introuvable : %', p_role_name;
  END IF;

  DELETE FROM "UserRoles"
  WHERE "userId" = p_user_id AND "roleId" = v_role_id
    AND ("companyId" IS NOT DISTINCT FROM p_company_id)
    AND (p_role_name <> 'admin_pays' OR "countryId" IS NOT DISTINCT FROM p_country_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_company_user_role(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_assign_user_role(uuid, text, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_remove_user_role(uuid, text, uuid, uuid) TO authenticated;
