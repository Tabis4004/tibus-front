-- =============================================================================
-- Tibus — Rôles plateforme live (désactive le besoin du sandbox admin UI)
-- Exécuter dans Supabase SQL Editor, puis déconnexion / reconnexion.
-- =============================================================================

INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId")
SELECT
  (SELECT id FROM "Role" WHERE name = 'super_admin' LIMIT 1),
  u.id,
  NULL,
  NULL
FROM "Users" u
WHERE lower(u.email) IN (
  lower('tabiscompany@gmail.com'),
  lower('tabiscompanytogo@gmail.com'),
  lower('isidoretabati@gmail.com')
)
ON CONFLICT DO NOTHING;

SELECT u.email, r.name AS role, ur."companyId", ur."countryId"
FROM "UserRoles" ur
JOIN "Users" u ON u.id = ur."userId"
JOIN "Role" r ON r.id = ur."roleId"
WHERE lower(u.email) IN (
  lower('tabiscompany@gmail.com'),
  lower('tabiscompanytogo@gmail.com'),
  lower('isidoretabati@gmail.com')
)
ORDER BY u.email, r.name;
