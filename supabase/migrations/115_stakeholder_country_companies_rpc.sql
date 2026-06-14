-- 115 — Liste compagnies par pays pour le paramétrage recruteur stakeholders

CREATE OR REPLACE FUNCTION public.list_stakeholder_country_companies(p_country_id uuid)
RETURNS TABLE(
  company_id uuid,
  company_name text,
  country_id uuid,
  recruited_by_user_id uuid
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
    c.id,
    c.name::text,
    c."countryId",
    c."recruitedByUserId"
  FROM "Companies" c
  WHERE c."countryId" = p_country_id
  ORDER BY c.name ASC NULLS LAST, c."createdAt" ASC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_stakeholder_country_companies(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
