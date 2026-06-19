-- =============================================================================
-- PROD — compagnie démo + rôle owner pour tous les utilisateurs
-- Projet : kqudaqtydimjclwaihqr
--
-- SQL Editor : sélectionner TOUT (Ctrl+A) puis Run en une seule fois.
-- Idempotent : réutilise "Tibus Démo Transport" si elle existe déjà.
-- Visibilité publique OFF : isActive=false, arretReservation=false (gares/voyages hors recherche voyageur).
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_country_id uuid;
  v_company_id uuid;
  v_owner_role_id uuid;
  v_user_count int;
  v_assigned int;
BEGIN
  SELECT id INTO v_country_id FROM "Countries" ORDER BY name LIMIT 1;
  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Aucun pays en base — impossible de créer la compagnie démo';
  END IF;

  SELECT id INTO v_company_id
  FROM "Companies"
  WHERE name = 'Tibus Démo Transport'
  LIMIT 1;

  IF v_company_id IS NULL THEN
    INSERT INTO "Companies" (
      name,
      "countryId",
      "isActive",
      "commissionRate",
      "arretReservation",
      "liveAuthorizedByAdmin"
    ) VALUES (
      'Tibus Démo Transport',
      v_country_id,
      false,
      0,
      false,
      false,
      true
    )
    RETURNING id INTO v_company_id;

    INSERT INTO public."CompanyFeatureModules" (
      "companyId", "moduleA", "moduleB", "moduleC", "moduleD", "moduleE", "moduleF"
    ) VALUES (
      v_company_id, true, true, true, true, true, false
    )
    ON CONFLICT ("companyId") DO NOTHING;

    RAISE NOTICE 'Compagnie démo créée : %', v_company_id;
  ELSE
    RAISE NOTICE 'Compagnie démo existante réutilisée : %', v_company_id;

    UPDATE "Companies"
    SET
      "isActive" = false,
      "arretReservation" = false,
      "liveAuthorizedByAdmin" = true
    WHERE id = v_company_id;
  END IF;

  SELECT id INTO v_owner_role_id
  FROM "Role"
  WHERE name = 'owner' AND scope = 'company'
  LIMIT 1;

  IF v_owner_role_id IS NULL THEN
    RAISE EXCEPTION 'Rôle owner (scope company) introuvable';
  END IF;

  SELECT COUNT(*) INTO v_user_count FROM "Users";

  INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId")
  SELECT v_owner_role_id, u.id, v_company_id, NULL
  FROM "Users" u
  WHERE NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    WHERE ur."userId" = u.id
      AND ur."roleId" = v_owner_role_id
      AND ur."companyId" = v_company_id
  );

  GET DIAGNOSTICS v_assigned = ROW_COUNT;

  RAISE NOTICE 'Utilisateurs en base : % | Nouveaux rôles owner assignés : %', v_user_count, v_assigned;
END $$;

SELECT
  c.id AS company_id,
  c.name AS company_name,
  co.name AS country,
  COUNT(ur.id) FILTER (WHERE r.name = 'owner') AS owner_count,
  (SELECT COUNT(*) FROM "Users") AS users_total
FROM "Companies" c
LEFT JOIN "Countries" co ON co.id = c."countryId"
LEFT JOIN "UserRoles" ur ON ur."companyId" = c.id
LEFT JOIN "Role" r ON r.id = ur."roleId"
WHERE c.name = 'Tibus Démo Transport'
GROUP BY c.id, c.name, co.name;

SELECT
  u.id,
  u.email,
  u."firstName",
  u."lastName"
FROM "Users" u
JOIN "UserRoles" ur ON ur."userId" = u.id
JOIN "Role" r ON r.id = ur."roleId" AND r.name = 'owner'
JOIN "Companies" c ON c.id = ur."companyId" AND c.name = 'Tibus Démo Transport'
ORDER BY u.email NULLS LAST, u."lastName", u."firstName";

COMMIT;
