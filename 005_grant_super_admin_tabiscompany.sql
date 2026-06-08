-- =============================================================================
-- Tibus — Accorder super_admin à tabiscompany@gmail.com
-- =============================================================================
-- Projet : kqudaqtydimjclwaihqr
-- À exécuter dans Supabase → SQL Editor (une seule fois)
-- =============================================================================

INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId")
VALUES (
  (SELECT id FROM "Role" WHERE name = 'super_admin'),
  (
    SELECT u.id
    FROM "Users" u
    WHERE u.email = 'tabiscompany@gmail.com'
    LIMIT 1
  ),
  NULL,
  NULL
)
ON CONFLICT DO NOTHING;

-- Vérification
SELECT u.email, r.name, ur."companyId", ur."countryId"
FROM "UserRoles" ur
JOIN "Users" u ON u.id = ur."userId"
JOIN "Role" r ON r.id = ur."roleId"
WHERE u.email = 'tabiscompany@gmail.com'
ORDER BY r.name;
