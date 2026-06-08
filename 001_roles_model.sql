-- =============================================================================
-- Tibus — Modèle de rôles DEFINITIF (Plateforme + Compagnie)
-- =============================================================================
-- PRÉREQUIS : init_schema.sql déjà exécuté
-- EXÉCUTER AVANT : 002_rls_policies.sql
-- =============================================================================
--
-- HIÉRARCHIE PLATEFORME (companyId = NULL) :
--   super_admin → admin_pays → master → vendeur_master → vendeur_reseau
--   super_admin → master_independant (vente toutes compagnies)
--   vendeur_independant → AUTO-INSCRIPTION, dépend de la plateforme UNIQUEMENT
--                         (hors réseau master, commission sans intermédiaire)
--
-- HIÉRARCHIE COMPAGNIE (companyId requis) :
--   owner → comptable_compagnie | controleur | vendeur
--
-- INSCRIPTION LIBRE :
--   traveler (défaut) | vendeur_independant (candidature plateforme)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Enrichir la table Role
-- ---------------------------------------------------------------------------

ALTER TABLE "Role"
  ADD COLUMN IF NOT EXISTS "scope" varchar NOT NULL DEFAULT 'company',
  ADD COLUMN IF NOT EXISTS "level" integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "isSystem" boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "description" text,
  ADD COLUMN IF NOT EXISTS "createdAt" timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS "createdBy" uuid;

ALTER TABLE "Role"
  DROP CONSTRAINT IF EXISTS "Role_scope_check";
ALTER TABLE "Role"
  ADD CONSTRAINT "Role_scope_check"
  CHECK ("scope" IN ('platform', 'company'));

COMMENT ON COLUMN "Role"."scope" IS 'platform = sans compagnie | company = lié à une compagnie';
COMMENT ON COLUMN "Role"."level" IS 'Ordre hiérarchique indicatif (plus élevé = plus de pouvoir)';
COMMENT ON COLUMN "Role"."isSystem" IS 'true = rôle système, false = rôle custom créé par super_admin';

-- ---------------------------------------------------------------------------
-- 2. Enrichir UserRoles
-- ---------------------------------------------------------------------------

ALTER TABLE "UserRoles"
  ALTER COLUMN "companyId" DROP NOT NULL;

ALTER TABLE "UserRoles"
  ADD COLUMN IF NOT EXISTS "countryId" uuid,
  ADD COLUMN IF NOT EXISTS "assignedBy" uuid,
  ADD COLUMN IF NOT EXISTS "assignedAt" timestamptz NOT NULL DEFAULT now();

ALTER TABLE "UserRoles"
  DROP CONSTRAINT IF EXISTS "UserRoles_countryId_fkey";
ALTER TABLE "UserRoles"
  ADD CONSTRAINT "UserRoles_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "UserRoles"
  DROP CONSTRAINT IF EXISTS "UserRoles_assignedBy_fkey";
ALTER TABLE "UserRoles"
  ADD CONSTRAINT "UserRoles_assignedBy_fkey"
  FOREIGN KEY ("assignedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

-- Index uniques Tibus obsolète
DROP INDEX IF EXISTS "UserRoles_roleId_userId_companyId_key";

-- Rôle plateforme global (ex: traveler, super_admin)
CREATE UNIQUE INDEX IF NOT EXISTS "UserRoles_platform_global_unique"
  ON "UserRoles" ("userId", "roleId")
  WHERE "companyId" IS NULL AND "countryId" IS NULL;

-- Rôle plateforme par pays (ex: admin_pays)
CREATE UNIQUE INDEX IF NOT EXISTS "UserRoles_platform_country_unique"
  ON "UserRoles" ("userId", "roleId", "countryId")
  WHERE "companyId" IS NULL AND "countryId" IS NOT NULL;

-- Rôle compagnie
CREATE UNIQUE INDEX IF NOT EXISTS "UserRoles_company_unique"
  ON "UserRoles" ("userId", "roleId", "companyId")
  WHERE "companyId" IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Règles d'attribution (qui peut assigner quel rôle)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "RoleAssignmentRules" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "assignerRoleId" uuid NOT NULL,
  "assignableRoleId" uuid NOT NULL,
  UNIQUE ("assignerRoleId", "assignableRoleId")
);

ALTER TABLE "RoleAssignmentRules"
  DROP CONSTRAINT IF EXISTS "RoleAssignmentRules_assignerRoleId_fkey";
ALTER TABLE "RoleAssignmentRules"
  ADD CONSTRAINT "RoleAssignmentRules_assignerRoleId_fkey"
  FOREIGN KEY ("assignerRoleId") REFERENCES "Role" ("id")
  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "RoleAssignmentRules"
  DROP CONSTRAINT IF EXISTS "RoleAssignmentRules_assignableRoleId_fkey";
ALTER TABLE "RoleAssignmentRules"
  ADD CONSTRAINT "RoleAssignmentRules_assignableRoleId_fkey"
  FOREIGN KEY ("assignableRoleId") REFERENCES "Role" ("id")
  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

COMMENT ON TABLE "RoleAssignmentRules" IS
  'Définit qui peut attribuer quel rôle. super_admin peut aussi créer des rôles custom.';

-- ---------------------------------------------------------------------------
-- 4. Vendeurs indépendants ↔ compagnies autorisées
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "IndependentSellerCompanies" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "sellerUserId" uuid NOT NULL,
  "companyId" uuid NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "createdBy" uuid NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "IndependentSellerCompanies_seller_company_key"
  ON "IndependentSellerCompanies" ("sellerUserId", "companyId");

ALTER TABLE "IndependentSellerCompanies"
  DROP CONSTRAINT IF EXISTS "IndependentSellerCompanies_sellerUserId_fkey";
ALTER TABLE "IndependentSellerCompanies"
  ADD CONSTRAINT "IndependentSellerCompanies_sellerUserId_fkey"
  FOREIGN KEY ("sellerUserId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "IndependentSellerCompanies"
  DROP CONSTRAINT IF EXISTS "IndependentSellerCompanies_companyId_fkey";
ALTER TABLE "IndependentSellerCompanies"
  ADD CONSTRAINT "IndependentSellerCompanies_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "IndependentSellerCompanies"
  DROP CONSTRAINT IF EXISTS "IndependentSellerCompanies_createdBy_fkey";
ALTER TABLE "IndependentSellerCompanies"
  ADD CONSTRAINT "IndependentSellerCompanies_createdBy_fkey"
  FOREIGN KEY ("createdBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "IndependentSellerCompanies" ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE "IndependentSellerCompanies" IS
  'Compagnies où un vendeur_independant peut vendre (hors réseau master).';

-- ---------------------------------------------------------------------------
-- 4b. Réseau Master ↔ vendeurs (vendeur_reseau) — SÉPARÉ des indépendants
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "MasterVendorNetwork" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "masterUserId" uuid NOT NULL,
  "vendorUserId" uuid NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "assignedBy" uuid NOT NULL,
  UNIQUE ("masterUserId", "vendorUserId")
);

ALTER TABLE "MasterVendorNetwork"
  DROP CONSTRAINT IF EXISTS "MasterVendorNetwork_masterUserId_fkey";
ALTER TABLE "MasterVendorNetwork"
  ADD CONSTRAINT "MasterVendorNetwork_masterUserId_fkey"
  FOREIGN KEY ("masterUserId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "MasterVendorNetwork"
  DROP CONSTRAINT IF EXISTS "MasterVendorNetwork_vendorUserId_fkey";
ALTER TABLE "MasterVendorNetwork"
  ADD CONSTRAINT "MasterVendorNetwork_vendorUserId_fkey"
  FOREIGN KEY ("vendorUserId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "MasterVendorNetwork"
  DROP CONSTRAINT IF EXISTS "MasterVendorNetwork_assignedBy_fkey";
ALTER TABLE "MasterVendorNetwork"
  ADD CONSTRAINT "MasterVendorNetwork_assignedBy_fkey"
  FOREIGN KEY ("assignedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "MasterVendorNetwork" ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE "MasterVendorNetwork" IS
  'Réseau de vendeurs sous un master. Le master touche une commission sur ce réseau.
   Les vendeur_independant n''y figurent JAMAIS.';

-- ---------------------------------------------------------------------------
-- 5. Validation scope / companyId / countryId
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_user_role_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope varchar;
  v_role_name varchar;
BEGIN
  SELECT r.scope, r.name INTO v_scope, v_role_name
  FROM "Role" r WHERE r.id = NEW."roleId";

  IF v_scope IS NULL THEN
    RAISE EXCEPTION 'Rôle introuvable : %', NEW."roleId";
  END IF;

  -- Rôles PLATEFORME : pas de companyId
  IF v_scope = 'platform' AND NEW."companyId" IS NOT NULL THEN
    RAISE EXCEPTION 'Rôle plateforme "%" : companyId doit être NULL', v_role_name;
  END IF;

  -- Rôles COMPAGNIE : companyId obligatoire
  IF v_scope = 'company' AND NEW."companyId" IS NULL THEN
    RAISE EXCEPTION 'Rôle compagnie "%" : companyId est obligatoire', v_role_name;
  END IF;

  -- admin_pays : countryId obligatoire
  IF v_role_name = 'admin_pays' AND NEW."countryId" IS NULL THEN
    RAISE EXCEPTION 'admin_pays requiert un countryId';
  END IF;

  -- Autres rôles plateforme : pas de countryId (sauf admin_pays)
  IF v_scope = 'platform' AND v_role_name <> 'admin_pays' AND NEW."countryId" IS NOT NULL THEN
    RAISE EXCEPTION 'Rôle "%" : countryId doit être NULL', v_role_name;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_roles_assignment_check ON "UserRoles";
CREATE TRIGGER user_roles_assignment_check
  BEFORE INSERT OR UPDATE ON "UserRoles"
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_user_role_assignment();

-- ---------------------------------------------------------------------------
-- 6. Rôles système
-- ---------------------------------------------------------------------------

INSERT INTO "Role" ("name", "scope", "level", "isSystem", "description", "droits") VALUES
  ('super_admin', 'platform', 100, true, 'Administrateur plateforme Tibus', ARRAY[
    'manage_platform', 'manage_roles', 'manage_country', 'manage_company',
    'manage_buses', 'manage_stations', 'manage_routes', 'manage_trips',
    'sell_tickets', 'sell_all_companies', 'reserve_tickets', 'view_bookings',
    'cancel_bookings', 'manage_sellers', 'manage_independent_sellers',
    'view_reports', 'manage_subscriptions', 'manage_accounting', 'control_tickets'
  ]),
  ('admin_pays', 'platform', 80, true, 'Administrateur d''un pays', ARRAY[
    'manage_country', 'manage_company', 'manage_trips', 'sell_tickets',
    'view_bookings', 'manage_sellers', 'manage_independent_sellers', 'view_reports'
  ]),
  ('master', 'platform', 60, true, 'Master — gère son réseau de vendeurs (commission réseau)', ARRAY[
    'manage_network_sellers', 'sell_tickets', 'view_bookings', 'view_reports', 'view_network_commissions'
  ]),
  ('vendeur_master', 'platform', 50, true, 'Chef d''équipe sous un master (réseau uniquement)', ARRAY[
    'manage_network_sellers', 'sell_tickets', 'view_bookings'
  ]),
  ('vendeur_reseau', 'platform', 45, true, 'Vendeur du réseau d''un master (assigné, pas auto-inscription)', ARRAY[
    'sell_tickets', 'view_bookings'
  ]),
  ('vendeur_independant', 'platform', 40, true, 'Vendeur indépendant — auto-inscription plateforme, hors réseau master', ARRAY[
    'sell_tickets', 'view_bookings'
  ]),
  ('master_independant', 'platform', 55, true, 'Master indépendant — vente toutes compagnies', ARRAY[
    'sell_tickets', 'sell_all_companies', 'view_bookings', 'view_reports'
  ]),
  ('traveler', 'platform', 10, true, 'Voyageur — rôle par défaut à l''inscription', ARRAY[
    'reserve_tickets', 'view_bookings'
  ]),
  ('owner', 'company', 70, true, 'Propriétaire de compagnie', ARRAY[
    'manage_company', 'manage_buses', 'manage_stations', 'manage_routes',
    'manage_trips', 'sell_tickets', 'view_bookings', 'cancel_bookings',
    'manage_sellers', 'view_reports', 'manage_subscriptions', 'assign_company_roles'
  ]),
  ('comptable_compagnie', 'company', 30, true, 'Comptable de la compagnie', ARRAY[
    'view_bookings', 'view_reports', 'manage_accounting'
  ]),
  ('controleur', 'company', 25, true, 'Contrôleur de tickets', ARRAY[
    'view_bookings', 'control_tickets'
  ]),
  ('vendeur', 'company', 20, true, 'Vendeur employé de la compagnie', ARRAY[
    'sell_tickets', 'view_bookings'
  ])
ON CONFLICT ("name") DO UPDATE SET
  "scope" = EXCLUDED."scope",
  "level" = EXCLUDED."level",
  "isSystem" = EXCLUDED."isSystem",
  "description" = EXCLUDED."description",
  "droits" = EXCLUDED."droits";

-- ---------------------------------------------------------------------------
-- 7. Règles d'attribution hiérarchiques
-- ---------------------------------------------------------------------------

-- Nettoyer les anciennes règles si re-exécution
DELETE FROM "RoleAssignmentRules";

INSERT INTO "RoleAssignmentRules" ("assignerRoleId", "assignableRoleId")
SELECT a.id, b.id
FROM "Role" a
CROSS JOIN "Role" b
WHERE
  -- super_admin : rôles plateforme (sauf vendeur_independant = auto-inscription)
  (a.name = 'super_admin' AND b.name IN (
    'admin_pays', 'master', 'master_independant', 'vendeur_master', 'vendeur_reseau', 'owner'
  ))
  OR
  -- admin_pays : masters et chefs d'équipe dans son pays
  (a.name = 'admin_pays' AND b.name IN ('master', 'vendeur_master', 'vendeur_reseau'))
  OR
  -- master : son réseau UNIQUEMENT (pas les indépendants)
  (a.name = 'master' AND b.name IN ('vendeur_master', 'vendeur_reseau'))
  OR
  -- vendeur_master : vendeurs de son équipe réseau
  (a.name = 'vendeur_master' AND b.name = 'vendeur_reseau')
  OR
  -- owner : rôles compagnie uniquement
  (a.name = 'owner' AND b.name IN ('comptable_compagnie', 'controleur', 'vendeur'));

-- vendeur_independant : PAS dans RoleAssignmentRules → auto-inscription plateforme

ALTER TABLE "RoleAssignmentRules" ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 8. Liste des permissions disponibles (référence pour l'UI super_admin)
-- ---------------------------------------------------------------------------

COMMENT ON COLUMN "Role"."droits" IS
  'Permissions : manage_platform, manage_roles, manage_country, manage_company,
   manage_buses, manage_stations, manage_routes, manage_trips, sell_tickets,
   sell_all_companies, reserve_tickets, view_bookings, cancel_bookings,
   manage_sellers, manage_independent_sellers, manage_network_sellers,
   view_network_commissions, view_reports, manage_subscriptions,
   manage_accounting, control_tickets, assign_company_roles';
