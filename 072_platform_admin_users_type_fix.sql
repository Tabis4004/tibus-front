-- =============================================================================
-- Tibus 072 — Corriger types varchar/text dans les RPC admin utilisateurs
-- =============================================================================
-- Erreur Postgres : "structure of query does not match function result type"
-- Cause : ARRAY_AGG(r.name) → varchar[] alors que RETURNS TABLE attend text[]
-- PRÉREQUIS : 047_team_list_and_cash_session.sql, 070_platform_admin_users.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_owner_team_members(
  p_company_id uuid DEFAULT NULL
)
RETURNS TABLE (
  user_id uuid,
  "firstName" varchar,
  "lastName" varchar,
  email varchar,
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

  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = public.current_app_user_id()
      AND ur."companyId" = v_company_id
      AND r.name = 'owner'
  ) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Action reservee au proprietaire de la compagnie';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u."firstName",
    u."lastName",
    u.email,
    r.name::text AS role_name
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  JOIN "Users" u ON u.id = ur."userId"
  WHERE ur."companyId" = v_company_id
    AND r.name IN ('vendeur', 'comptable_compagnie', 'controleur')
  ORDER BY u."lastName", u."firstName", r.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_platform_users_for_admin(
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  email character varying,
  "firstName" character varying,
  "lastName" character varying,
  username character varying,
  roles text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants : rôle super_admin requis en base (pas le sandbox UI)';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.email,
    u."firstName",
    u."lastName",
    u.username,
    COALESCE(role_names.roles, ARRAY[]::text[]) AS roles
  FROM "Users" u
  LEFT JOIN LATERAL (
    SELECT ARRAY_AGG(DISTINCT r.name::text ORDER BY r.name::text) AS roles
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = u.id
  ) role_names ON true
  ORDER BY u."createdAt" DESC NULLS LAST, u.email ASC NULLS LAST
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 200), 500))
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_owner_team_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_platform_users_for_admin(integer, integer) TO authenticated;
