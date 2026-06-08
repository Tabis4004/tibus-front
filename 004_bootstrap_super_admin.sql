-- =============================================================================
-- Tibus — Promouvoir un utilisateur en super_admin
-- =============================================================================
-- ÉTAPE 1 : Trouver ton userId (exécute d'abord cette requête seule)
-- =============================================================================

SELECT
  u.id AS "userId",
  u.email,
  u."firstName",
  u."lastName",
  u."auth_user_id",
  au.email AS "auth_email"
FROM "Users" u
LEFT JOIN auth.users au ON au.id = u."auth_user_id"
ORDER BY u."createdAt" DESC;

-- =============================================================================
-- ÉTAPE 2 : Remplace USER_UUID_ICI par l'id de la colonne userId ci-dessus
-- =============================================================================

INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId")
VALUES (
  (SELECT id FROM "Role" WHERE name = 'super_admin'),
  'USER_UUID_ICI',
  NULL,
  NULL
)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- ÉTAPE 3 : Vérification
-- =============================================================================

SELECT u.email, r.name, ur."companyId", ur."countryId"
FROM "UserRoles" ur
JOIN "Users" u ON u.id = ur."userId"
JOIN "Role" r ON r.id = ur."roleId"
WHERE r.name = 'super_admin';
