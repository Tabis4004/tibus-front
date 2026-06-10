-- =============================================================================
-- Tibus — Liste utilisateurs plateforme (super_admin réel en base)
-- =============================================================================

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
    SELECT ARRAY_AGG(DISTINCT r.name ORDER BY r.name) AS roles
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = u.id
  ) role_names ON true
  ORDER BY u."createdAt" DESC NULLS LAST, u.email ASC NULLS LAST
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 200), 500))
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_platform_users_for_admin()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RETURN 0;
  END IF;

  RETURN (SELECT COUNT(*)::bigint FROM "Users");
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_platform_users_for_admin(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_platform_users_for_admin() TO authenticated;
