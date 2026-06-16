-- 124 — Restaure list_stakeholder_country_users (régression 122) + rôle demarcheur

CREATE OR REPLACE FUNCTION public.list_stakeholder_country_users(p_country_id uuid)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  email text,
  roles text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(p_country_id, ARRAY['admin_pays'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')::text,
    u.email::text,
    COALESCE(array_agg(DISTINCT r.name::text) FILTER (WHERE r.name IS NOT NULL), ARRAY[]::text[])
  FROM "Users" u
  JOIN "UserRoles" ur ON ur."userId" = u.id
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."countryId" = p_country_id
     OR u."countryId" = p_country_id
     OR EXISTS (
       SELECT 1
       FROM "Companies" c
       WHERE c."countryId" = p_country_id
         AND c."recruitedByUserId" = u.id
     )
     OR EXISTS (
       SELECT 1
       FROM "UserRoles" urc
       JOIN "Companies" c ON c.id = urc."companyId"
       WHERE urc."userId" = u.id
         AND c."countryId" = p_country_id
     )
     OR (
       r.name = 'demarcheur'
       AND (
         ur."countryId" = p_country_id
         OR u."countryId" = p_country_id
         OR EXISTS (
           SELECT 1
           FROM "Companies" c
           WHERE c."countryId" = p_country_id
             AND c."recruitedByUserId" = u.id
         )
       )
     )
  GROUP BY u.id, u."firstName", u."lastName", u.email
  ORDER BY 2 NULLS LAST, u.email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_stakeholder_country_users(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
