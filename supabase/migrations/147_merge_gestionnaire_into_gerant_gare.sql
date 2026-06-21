-- =============================================================================
-- Tibus 147 — Fusion gestionnaire_gare → gerant_gare (rôle unique gérant de gare)
-- =============================================================================

-- 1. Supprimer les doublons gestionnaire_gare quand gerant_gare existe déjà sur la même gare
DELETE FROM public."UserRoles" ur
USING public."Role" r
WHERE ur."roleId" = r.id
  AND r.name = 'gestionnaire_gare'
  AND EXISTS (
    SELECT 1
    FROM public."UserRoles" ur2
    JOIN public."Role" r2 ON r2.id = ur2."roleId"
    WHERE ur2."userId" = ur."userId"
      AND ur2."gareId" IS NOT DISTINCT FROM ur."gareId"
      AND r2.name = 'gerant_gare'
  );

-- 2. Rattacher gareId aux gestionnaire_gare legacy via Gares.gestionnaireUserId
UPDATE public."UserRoles" ur
SET
  "gareId" = sub.gare_id,
  "companyId" = COALESCE(ur."companyId", sub.company_id)
FROM (
  SELECT DISTINCT ON (ur.id)
    ur.id AS user_role_id,
    g.id AS gare_id,
    g."companyId" AS company_id
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Gares" g ON g."gestionnaireUserId" = ur."userId"
    AND (ur."companyId" IS NULL OR g."companyId" = ur."companyId")
  WHERE r.name = 'gestionnaire_gare'
    AND ur."gareId" IS NULL
  ORDER BY ur.id, g.id
) sub
WHERE ur.id = sub.user_role_id;

-- 2b. Fallback : première gare de la compagnie pour les rôles legacy sans gareId
UPDATE public."UserRoles" ur
SET "gareId" = sub.gare_id
FROM (
  SELECT DISTINCT ON (ur.id)
    ur.id AS user_role_id,
    g.id AS gare_id
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Gares" g ON g."companyId" = ur."companyId"
  WHERE r.name = 'gestionnaire_gare'
    AND ur."gareId" IS NULL
    AND ur."companyId" IS NOT NULL
  ORDER BY ur.id, g.id
) sub
WHERE ur.id = sub.user_role_id;

-- 2c. Supprimer les gestionnaire_gare orphelins (impossible à rattacher à une gare)
DELETE FROM public."UserRoles" ur
USING public."Role" r
WHERE ur."roleId" = r.id
  AND r.name = 'gestionnaire_gare'
  AND ur."gareId" IS NULL;

-- 3. Convertir les gestionnaire_gare restants en gerant_gare (gareId obligatoire)
UPDATE public."UserRoles" ur
SET "roleId" = gerant.id
FROM public."Role" legacy, public."Role" gerant
WHERE ur."roleId" = legacy.id
  AND legacy.name = 'gestionnaire_gare'
  AND gerant.name = 'gerant_gare'
  AND ur."gareId" IS NOT NULL;

-- 4. Backfill gerant_gare pour gares avec gestionnaireUserId sans UserRoles gérant
INSERT INTO public."UserRoles" ("roleId", "userId", "companyId", "gareId", "countryId", "assignedBy")
SELECT
  gerant.id,
  g."gestionnaireUserId",
  g."companyId",
  g.id,
  NULL,
  NULL
FROM public."Gares" g
CROSS JOIN public."Role" gerant
WHERE g."gestionnaireUserId" IS NOT NULL
  AND gerant.name = 'gerant_gare'
  AND NOT EXISTS (
    SELECT 1
    FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = g."gestionnaireUserId"
      AND ur."gareId" = g.id
      AND r.name = 'gerant_gare'
  );

-- 5. Retirer gestionnaire_gare des règles d'assignation
DELETE FROM public."RoleAssignmentRules" rules
USING public."Role" assigner, public."Role" assignable
WHERE rules."assignerRoleId" = assigner.id
  AND rules."assignableRoleId" = assignable.id
  AND (
    assigner.name = 'gestionnaire_gare'
    OR assignable.name = 'gestionnaire_gare'
  );

-- 6. Fonctions : gerant_gare uniquement (gestionnaireUserId conservé sur Gares)
CREATE OR REPLACE FUNCTION public._is_gare_scoped_role(p_role_name text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_role_name IN (
    'gerant_gare', 'vendeur_gare', 'controleur_gare', 'comptable_gare'
  );
$$;

CREATE OR REPLACE FUNCTION public.resolve_user_managed_gare_id(p_user_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := COALESCE(p_user_id, public.current_app_user_id());
  v_gare uuid;
BEGIN
  SELECT ur."gareId" INTO v_gare
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user
    AND ur."gareId" IS NOT NULL
    AND r.name = 'gerant_gare'
  ORDER BY ur.id
  LIMIT 1;

  IF v_gare IS NOT NULL THEN RETURN v_gare; END IF;

  SELECT g.id INTO v_gare FROM public."Gares" g
  WHERE g."gestionnaireUserId" = v_user
  LIMIT 1;

  RETURN v_gare;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_gare(p_gare_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
BEGIN
  SELECT g."companyId" INTO v_company FROM public."Gares" g WHERE g.id = p_gare_id;
  IF v_company IS NULL THEN RETURN false; END IF;
  IF public.is_super_admin() THEN RETURN true; END IF;
  IF public.has_company_role(v_company, ARRAY['owner', 'comptable_compagnie']) THEN RETURN true; END IF;
  IF public.has_gare_role(p_gare_id, ARRAY['gerant_gare']) THEN RETURN true; END IF;
  IF EXISTS (
    SELECT 1 FROM public."Gares" g
    WHERE g.id = p_gare_id AND g."gestionnaireUserId" = public.current_app_user_id()
  ) THEN RETURN true; END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_user_gare_id(p_user_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := COALESCE(p_user_id, public.current_app_user_id());
  v_gare uuid;
BEGIN
  IF v_user IS NULL THEN RETURN NULL; END IF;

  SELECT ur."gareId" INTO v_gare
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user
    AND ur."gareId" IS NOT NULL
    AND r.name IN (
      'gerant_gare', 'comptable_gare', 'controleur_gare', 'vendeur_gare'
    )
  ORDER BY
    CASE r.name
      WHEN 'gerant_gare' THEN 1
      WHEN 'comptable_gare' THEN 2
      ELSE 9
    END,
    ur.id
  LIMIT 1;

  IF v_gare IS NOT NULL THEN RETURN v_gare; END IF;

  SELECT g.id INTO v_gare FROM public."Gares" g
  WHERE g."gestionnaireUserId" = v_user
  LIMIT 1;

  RETURN v_gare;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_gare_team_members(p_gare_id uuid)
RETURNS TABLE (
  user_id uuid,
  "firstName" text,
  "lastName" text,
  email text,
  role_name text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.can_manage_gare(p_gare_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT u.id, u."firstName"::text, u."lastName"::text, u.email::text, r.name::text
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Users" u ON u.id = ur."userId"
  WHERE ur."gareId" = p_gare_id
    AND r.name IN ('vendeur_gare', 'controleur_gare', 'comptable_gare', 'gerant_gare')
  ORDER BY u."lastName", u."firstName", r.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_gare_gerant(
  p_gare_id uuid,
  p_user_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_gerant_role uuid;
  v_assigner uuid;
BEGIN
  SELECT g."companyId" INTO v_company FROM public."Gares" g WHERE g.id = p_gare_id;
  IF v_company IS NULL THEN RAISE EXCEPTION 'Gare introuvable'; END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company, ARRAY['owner'])
  ) THEN
    RAISE EXCEPTION 'Seul le propriétaire peut désigner un gérant de gare';
  END IF;

  SELECT r.id INTO v_gerant_role
  FROM public."Role" r
  WHERE r.name = 'gerant_gare' AND r.scope = 'company';
  IF v_gerant_role IS NULL THEN RAISE EXCEPTION 'Rôle gerant_gare introuvable'; END IF;

  v_assigner := public.current_app_user_id();

  DELETE FROM public."UserRoles" ur
  USING public."Role" r
  WHERE ur."roleId" = r.id
    AND ur."gareId" = p_gare_id
    AND r.name = 'gerant_gare';

  UPDATE public."Gares" SET "gestionnaireUserId" = NULL WHERE id = p_gare_id;

  IF p_user_id IS NOT NULL THEN
    DELETE FROM public."UserRoles" ur
    USING public."Role" r
    WHERE ur."roleId" = r.id
      AND ur."userId" = p_user_id
      AND ur."gareId" IS NOT NULL
      AND r.name = 'gerant_gare';

    IF NOT EXISTS (
      SELECT 1 FROM public."UserRoles" ur
      WHERE ur."userId" = p_user_id
        AND ur."roleId" = v_gerant_role
        AND ur."gareId" = p_gare_id
    ) THEN
      INSERT INTO public."UserRoles" ("roleId", "userId", "companyId", "gareId", "countryId", "assignedBy")
      VALUES (v_gerant_role, p_user_id, v_company, p_gare_id, NULL, v_assigner);
    END IF;

    UPDATE public."Gares" SET "gestionnaireUserId" = p_user_id WHERE id = p_gare_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_validate_station_reversal(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = public.current_app_user_id()
        AND ur."companyId" = p_company_id
        AND ur."gareId" IS NOT NULL
        AND r.name IN ('comptable_gare', 'gerant_gare')
    );
$$;

CREATE OR REPLACE FUNCTION public.current_owner_company_id()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO public
AS $function$
DECLARE
  v_user_id uuid;
  v_active uuid;
  v_fallback uuid;
  v_staff_roles text[] := ARRAY[
    'owner', 'comptable_compagnie', 'controleur',
    'gerant_gare', 'controleur_gare', 'comptable_gare'
  ];
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT u."activeOwnerCompanyId" INTO v_active
  FROM public."Users" u
  WHERE u.id = v_user_id;

  IF v_active IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = v_active
      AND r.name = ANY (v_staff_roles)
  ) THEN
    RETURN v_active;
  END IF;

  SELECT ur."companyId" INTO v_fallback
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user_id
    AND ur."companyId" IS NOT NULL
    AND r.name = ANY (v_staff_roles)
  ORDER BY ur."companyId"
  LIMIT 1;

  IF v_fallback IS NOT NULL THEN
    RETURN v_fallback;
  END IF;

  SELECT g."companyId" INTO v_fallback
  FROM public."Gares" g
  WHERE g."gestionnaireUserId" = v_user_id
  LIMIT 1;

  RETURN v_fallback;
END;
$function$;

-- 7. Supprimer le rôle legacy (UserRoles déjà migrés)
DELETE FROM public."UserRoles" ur
USING public."Role" r
WHERE ur."roleId" = r.id AND r.name = 'gestionnaire_gare';

DELETE FROM public."Role" WHERE name = 'gestionnaire_gare';

NOTIFY pgrst, 'reload schema';
