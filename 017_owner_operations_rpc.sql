-- =============================================================================
-- Tibus — RPC operations owner Supabase
-- =============================================================================
-- Focused SECURITY DEFINER functions for owner actions that the client cannot
-- always execute directly under RLS.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.current_owner_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ur."companyId"
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = public.current_app_user_id()
    AND r.name = 'owner'
    AND ur."companyId" IS NOT NULL
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.create_owner_route(
  p_depart uuid,
  p_final uuid,
  p_price double precision DEFAULT 0,
  p_kilometrage double precision DEFAULT NULL,
  p_capacity integer DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_trajet_id uuid;
BEGIN
  v_company_id := public.current_owner_company_id();

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_depart = p_final THEN
    RAISE EXCEPTION 'La gare de depart et la gare d''arrivee doivent etre differentes';
  END IF;

  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Le prix doit etre positif ou nul';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "Gares"
    WHERE id = p_depart AND "companyId" = v_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de depart non autorisee';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "Gares"
    WHERE id = p_final AND "companyId" = v_company_id
  ) THEN
    RAISE EXCEPTION 'Gare d''arrivee non autorisee';
  END IF;

  INSERT INTO "ProgrammationTrajets" ("depart", "final", "capacity")
  VALUES (p_depart, p_final, p_capacity)
  RETURNING id INTO v_trajet_id;

  INSERT INTO "ProgrammationTrajetArrets" (
    "trajetId",
    "fromGareId",
    "toGareId",
    "price",
    "kilometrage"
  )
  VALUES (
    v_trajet_id,
    p_depart,
    p_final,
    p_price,
    p_kilometrage
  );

  RETURN v_trajet_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.find_assignable_company_user_by_email(
  p_email text
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
BEGIN
  v_company_id := public.current_owner_company_id();

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  RETURN QUERY
  SELECT u.id, u."firstName", u."lastName", u.email
  FROM "Users" u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;
END;
$$;

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

  IF p_role_name NOT IN ('vendeur', 'controleur') THEN
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
      "roleId",
      "userId",
      "companyId",
      "countryId",
      "assignedBy"
    )
    VALUES (
      v_role_id,
      v_target_user_id,
      v_company_id,
      NULL,
      v_owner_user_id
    );
  END IF;

  RETURN QUERY
  SELECT u.id, u."firstName", u."lastName", u.email
  FROM "Users" u
  WHERE u.id = v_target_user_id
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_owner_company_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_owner_route(uuid, uuid, double precision, double precision, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_assignable_company_user_by_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_company_user_role_by_email(text, text) TO authenticated;
