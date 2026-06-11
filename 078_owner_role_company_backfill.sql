-- Tibus 078 — Rattacher les rôles owner orphelins à la compagnie active

UPDATE "UserRoles" ur
SET "companyId" = u."activeOwnerCompanyId"
FROM "Users" u, "Role" r
WHERE ur."userId" = u.id
  AND ur."roleId" = r.id
  AND r.name = 'owner'
  AND ur."companyId" IS NULL
  AND u."activeOwnerCompanyId" IS NOT NULL;
