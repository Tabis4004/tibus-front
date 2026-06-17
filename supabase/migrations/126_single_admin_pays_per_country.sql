-- 126 — Un seul admin pays par pays (UserRoles)

CREATE OR REPLACE FUNCTION public.get_country_admin_pays_holder(
  p_country_id uuid,
  p_exclude_user_id uuid DEFAULT NULL
)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  email text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    u.id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')::text,
    u.email::text
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId" AND r.name = 'admin_pays'
  JOIN public."Users" u ON u.id = ur."userId"
  WHERE ur."countryId" = p_country_id
    AND (p_exclude_user_id IS NULL OR ur."userId" <> p_exclude_user_id)
  ORDER BY u.email
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.enforce_single_admin_pays_per_country()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_name text;
  v_holder record;
BEGIN
  SELECT r.name INTO v_role_name
  FROM public."Role" r
  WHERE r.id = NEW."roleId";

  IF v_role_name IS DISTINCT FROM 'admin_pays' OR NEW."countryId" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT h.user_id, h.full_name, h.email
  INTO v_holder
  FROM public.get_country_admin_pays_holder(NEW."countryId", NEW."userId") h
  LIMIT 1;

  IF v_holder.user_id IS NOT NULL THEN
    RAISE EXCEPTION
      'ADMIN_PAYS_COUNTRY_TAKEN|%|%|%',
      COALESCE(v_holder.full_name, ''),
      COALESCE(v_holder.email, ''),
      NEW."countryId"::text;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_single_admin_pays_per_country ON public."UserRoles";

CREATE TRIGGER trg_single_admin_pays_per_country
BEFORE INSERT OR UPDATE OF "roleId", "countryId", "userId"
ON public."UserRoles"
FOR EACH ROW
EXECUTE FUNCTION public.enforce_single_admin_pays_per_country();

GRANT EXECUTE ON FUNCTION public.get_country_admin_pays_holder(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
