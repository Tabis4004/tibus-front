-- =============================================================================
-- Tibus 080 — Fix définitif : structure of query does not match function result type
-- =============================================================================
-- PostgreSQL exige une correspondance exacte entre OUT/RETURNS TABLE et RETURN QUERY.
-- On déclare les chaînes en text et on caste explicitement chaque colonne.
-- =============================================================================

DROP FUNCTION IF EXISTS public.list_owner_team_members(uuid);

CREATE OR REPLACE FUNCTION public.list_owner_team_members(p_company_id uuid DEFAULT NULL)
RETURNS TABLE (
  user_id uuid,
  "firstName" text,
  "lastName" text,
  email text,
  role_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u."firstName"::text,
    u."lastName"::text,
    u.email::text,
    r.name::text
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  JOIN "Users" u ON u.id = ur."userId"
  WHERE ur."companyId" = v_company_id
    AND r.name IN ('vendeur', 'comptable_compagnie', 'controleur', 'gestionnaire_gare')
  ORDER BY u."lastName", u."firstName", r.name;
END;
$$;

DROP FUNCTION IF EXISTS public.assign_company_user_role_by_email(text, text);
DROP FUNCTION IF EXISTS public.assign_company_user_role_by_email(text, text, uuid);

CREATE OR REPLACE FUNCTION public.assign_company_user_role_by_email(
  p_email text,
  p_role_name text DEFAULT 'vendeur',
  p_company_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  "firstName" text,
  "lastName" text,
  email text
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
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  v_owner_user_id := public.current_app_user_id();

  IF v_company_id IS NULL OR v_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_role_name NOT IN ('vendeur', 'controleur', 'comptable_compagnie', 'gestionnaire_gare') THEN
    RAISE EXCEPTION 'Role compagnie non autorise : %', p_role_name;
  END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
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
    SELECT 1 FROM "UserRoles" ur
    WHERE ur."userId" = v_target_user_id
      AND ur."roleId" = v_role_id
      AND ur."companyId" = v_company_id
  ) THEN
    INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId", "assignedBy")
    VALUES (v_role_id, v_target_user_id, v_company_id, NULL, v_owner_user_id);
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u."firstName"::text,
    u."lastName"::text,
    u.email::text
  FROM "Users" u
  WHERE u.id = v_target_user_id
  LIMIT 1;
END;
$$;

DROP FUNCTION IF EXISTS public.find_assignable_company_user_by_email(text);

CREATE OR REPLACE FUNCTION public.find_assignable_company_user_by_email(p_email text)
RETURNS TABLE (
  id uuid,
  "firstName" text,
  "lastName" text,
  email text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  v_company_id := public.current_owner_company_id();

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u."firstName"::text,
    u."lastName"::text,
    u.email::text
  FROM "Users" u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_owner_team_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_company_user_role_by_email(text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_assignable_company_user_by_email(text) TO authenticated;
