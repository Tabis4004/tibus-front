-- =============================================================================
-- Tibus 093 — Rôle chauffeur + ville (cityId) sur Gares
-- =============================================================================
-- 1. Rôle compagnie chauffeur (vente + contrôle embarquement)
-- 2. cityId obligatoire sur Gares (pays compagnie)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Rôle chauffeur (company scope, level 21)
-- ---------------------------------------------------------------------------

INSERT INTO "Role" ("name", "scope", "level", "isSystem", "description", "droits") VALUES
  (
    'chauffeur',
    'company',
    21,
    true,
    'Chauffeur — vente guichet et controle embarquement',
    ARRAY['sell_tickets', 'view_bookings', 'control_tickets']
  )
ON CONFLICT ("name") DO UPDATE SET
  "scope" = EXCLUDED."scope",
  "level" = EXCLUDED."level",
  "isSystem" = EXCLUDED."isSystem",
  "description" = EXCLUDED."description",
  "droits" = EXCLUDED."droits";

INSERT INTO "RoleAssignmentRules" ("assignerRoleId", "assignableRoleId")
SELECT a.id, b.id
FROM "Role" a
CROSS JOIN "Role" b
WHERE a.name = 'owner' AND b.name = 'chauffeur'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- Owner team RPCs — whitelist chauffeur
-- ---------------------------------------------------------------------------

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
    AND r.name IN (
      'vendeur',
      'chauffeur',
      'comptable_compagnie',
      'controleur',
      'gestionnaire_gare'
    )
  ORDER BY u."lastName", u."firstName", r.name;
END;
$$;

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

  IF p_role_name NOT IN (
    'vendeur',
    'chauffeur',
    'controleur',
    'comptable_compagnie',
    'gestionnaire_gare'
  ) THEN
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

CREATE OR REPLACE FUNCTION public.remove_company_user_role(
  p_user_id uuid,
  p_role_name text,
  p_company_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_role_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_role_name NOT IN (
    'vendeur',
    'chauffeur',
    'controleur',
    'comptable_compagnie',
    'gestionnaire_gare'
  ) THEN
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

  DELETE FROM "UserRoles"
  WHERE "userId" = p_user_id
    AND "roleId" = v_role_id
    AND "companyId" = v_company_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Dépenses compagnie — membre équipe chauffeur
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._company_expense_team_member_valid(
  p_company_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."companyId" = p_company_id
      AND ur."userId" = p_user_id
      AND r.name IN (
        'owner',
        'comptable_compagnie',
        'controleur',
        'vendeur',
        'chauffeur',
        'gestionnaire_gare'
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Gares.cityId — lien ville (pays compagnie)
-- ---------------------------------------------------------------------------

ALTER TABLE "Gares"
  ADD COLUMN IF NOT EXISTS "cityId" uuid REFERENCES "Cities"(id);

CREATE INDEX IF NOT EXISTS gares_city_id_idx ON "Gares" ("cityId");

COMMENT ON COLUMN "Gares"."cityId" IS 'Ville de la gare (doit etre dans le pays de la compagnie)';

-- Seed une ville par defaut pour les pays ayant des gares mais aucune ville
INSERT INTO "Cities" ("name", "countryId")
SELECT 'Ville principale', missing.country_id
FROM (
  SELECT DISTINCT co."countryId" AS country_id
  FROM "Gares" g
  JOIN "Companies" co ON co.id = g."companyId"
  WHERE NOT EXISTS (
    SELECT 1 FROM "Cities" c WHERE c."countryId" = co."countryId"
  )
) missing
WHERE NOT EXISTS (
  SELECT 1
  FROM "Cities" c
  WHERE c."countryId" = missing.country_id
    AND c.name = 'Ville principale'
);

-- Backfill: nom gare = nom ville (meme pays que la compagnie)
UPDATE "Gares" g
SET "cityId" = c.id
FROM "Companies" co
JOIN "Cities" c ON c."countryId" = co."countryId"
WHERE g."companyId" = co.id
  AND g."cityId" IS NULL
  AND lower(btrim(g.name)) = lower(btrim(c.name));

-- Backfill: suffixe apres tiret long (ex: "Gare Adjamé — Abidjan")
UPDATE "Gares" g
SET "cityId" = c.id
FROM "Companies" co
JOIN "Cities" c ON c."countryId" = co."countryId"
WHERE g."companyId" = co.id
  AND g."cityId" IS NULL
  AND position('—' in g.name) > 0
  AND lower(btrim(split_part(g.name, '—', 2))) = lower(btrim(c.name));

-- Backfill: ville contenue dans le nom de gare
UPDATE "Gares" g
SET "cityId" = c.id
FROM "Companies" co
JOIN "Cities" c ON c."countryId" = co."countryId"
WHERE g."companyId" = co.id
  AND g."cityId" IS NULL
  AND lower(g.name) LIKE '%' || lower(c.name) || '%';

-- Fallback: premiere ville du pays de la compagnie
UPDATE "Gares" g
SET "cityId" = fc.city_id
FROM (
  SELECT
    g2.id AS gare_id,
    (
      SELECT c.id
      FROM "Cities" c
      WHERE c."countryId" = co."countryId"
      ORDER BY c.name
      LIMIT 1
    ) AS city_id
  FROM "Gares" g2
  JOIN "Companies" co ON co.id = g2."companyId"
  WHERE g2."cityId" IS NULL
) fc
WHERE g.id = fc.gare_id
  AND fc.city_id IS NOT NULL;

ALTER TABLE "Gares"
  ALTER COLUMN "cityId" SET NOT NULL;

CREATE OR REPLACE FUNCTION public.tg_validate_gare_city_in_company_country()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM "Companies" co
    JOIN "Cities" ci ON ci."countryId" = co."countryId"
    WHERE co.id = NEW."companyId"
      AND ci.id = NEW."cityId"
  ) THEN
    RAISE EXCEPTION 'La ville de la gare doit appartenir au pays de la compagnie';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS gares_validate_city_country ON "Gares";
CREATE TRIGGER gares_validate_city_country
  BEFORE INSERT OR UPDATE OF "cityId", "companyId" ON "Gares"
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_validate_gare_city_in_company_country();

CREATE OR REPLACE FUNCTION public.gare_city_name(p_gare_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.name::text
  FROM "Gares" g
  JOIN "Cities" c ON c.id = g."cityId"
  WHERE g.id = p_gare_id
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.list_owner_team_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_company_user_role_by_email(text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_company_user_role(uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gare_city_name(uuid) TO authenticated;
