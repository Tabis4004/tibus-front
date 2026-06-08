-- =============================================================================
-- Tibus — Schéma initial PostgreSQL (Supabase) — ÉTAPE 1/3
-- Référence : Tibus.sql (architecture relationnelle normalisée)
-- Modernisation : UUID, double precision, URLs text, RLS activé
-- Auth : Supabase Auth (password retiré, lien via auth_user_id)
--
-- ORDRE COMPLET : voir SCRIPTS_SUPABASE.md
--   1. init_schema.sql      ← ce fichier
--   2. 001_roles_model.sql
--   3. 002_rls_policies.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------

CREATE TYPE "ReservationType" AS ENUM (
  'colis',
  'voyage',
  'colisVoyage'
);

CREATE TYPE "DiscountType" AS ENUM (
  'percentage',
  'fixed'
);

-- ---------------------------------------------------------------------------
-- Tables sans dépendances externes
-- ---------------------------------------------------------------------------

CREATE TABLE "Countries" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "name" varchar NOT NULL,
  "currency" varchar
);

CREATE TABLE "Role" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "name" varchar UNIQUE NOT NULL,
  "droits" varchar[] NOT NULL
);

CREATE TABLE "Payment" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "reference" varchar UNIQUE NOT NULL,
  "txID" varchar UNIQUE,
  "phone" varchar NOT NULL,
  "amount" double precision NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Géographie & utilisateurs
-- ---------------------------------------------------------------------------

CREATE TABLE "Cities" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "name" varchar NOT NULL,
  "countryId" uuid NOT NULL
);

CREATE TABLE "Users" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "auth_user_id" uuid UNIQUE REFERENCES auth.users(id),
  "firstName" varchar NOT NULL,
  "lastName" varchar NOT NULL,
  "username" varchar UNIQUE NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "email" varchar UNIQUE,
  "phone" varchar UNIQUE,
  "countryId" uuid NOT NULL
);

-- ---------------------------------------------------------------------------
-- Entreprises & flotte
-- ---------------------------------------------------------------------------

CREATE TABLE "Companies" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "name" varchar NOT NULL,
  "countryId" uuid NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true,
  "commissionRate" double precision NOT NULL,
  "logo" text,
  "managerName" varchar,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "arretReservation" boolean NOT NULL DEFAULT true,
  "voyageColisMsg" text,
  CHECK ("commissionRate" >= 0)
);

CREATE TABLE "UserRoles" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "roleId" uuid NOT NULL,
  "userId" uuid NOT NULL,
  "companyId" uuid NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE "Bus" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "registrationNumber" varchar UNIQUE NOT NULL,
  "model" varchar,
  "isActive" boolean NOT NULL DEFAULT true,
  "capacity" integer NOT NULL,
  "companyId" uuid NOT NULL,
  CHECK ("capacity" > 1)
);

CREATE TABLE "Gares" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "name" varchar NOT NULL,
  "companyId" uuid NOT NULL,
  "googleMapsLink" text
);

COMMENT ON TABLE "Gares" IS 'Points d''arrêt / gares routières de la compagnie';
COMMENT ON COLUMN "Gares"."googleMapsLink" IS 'Lien Google Maps à copier-coller (ex: https://maps.app.goo.gl/...)';

-- ---------------------------------------------------------------------------
-- Programmation des trajets (modèle récurrent multi-arrêts)
-- ---------------------------------------------------------------------------

CREATE TABLE "ProgrammationTrajets" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "depart" uuid NOT NULL,
  "final" uuid NOT NULL,
  "capacity" integer
);

CREATE TABLE "ProgrammationTrajetDays" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "trajetId" uuid NOT NULL,
  "day" integer NOT NULL,
  "departureHour" integer NOT NULL,
  "departureMinutes" integer NOT NULL
);

CREATE TABLE "ProgrammationTrajetArrets" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "trajetId" uuid NOT NULL,
  "fromGareId" uuid NOT NULL,
  "toGareId" uuid NOT NULL,
  "price" double precision NOT NULL,
  "kilometrage" double precision,
  CHECK ("price" >= 0)
);

CREATE TABLE "ProgrammationBus" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "busId" uuid NOT NULL,
  "trajetId" uuid NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "isActive" boolean NOT NULL DEFAULT true
);

-- ---------------------------------------------------------------------------
-- Réservations & paiements
-- ---------------------------------------------------------------------------

CREATE TABLE "Reservations" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "date" timestamptz NOT NULL,
  "trajetId" uuid NOT NULL,
  "capacity" integer NOT NULL
);

CREATE TABLE "ReservationBus" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "type" "ReservationType" NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "createdBy" uuid NOT NULL,
  "reservationId" uuid NOT NULL,
  "arretId" uuid NOT NULL,
  "price" double precision NOT NULL,
  "isReservation" boolean NOT NULL,
  "paymentId" uuid NOT NULL,
  "exceedColisAmount" double precision
);

CREATE TABLE "ReservationBusColis" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "reservationId" uuid NOT NULL,
  "weight" double precision,
  "photo" text
);

-- ---------------------------------------------------------------------------
-- Abonnements
-- ---------------------------------------------------------------------------

CREATE TABLE "SubscriptionPlans" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "name" varchar UNIQUE NOT NULL,
  "countryId" uuid NOT NULL,
  "features" varchar[] NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE "SubscriptionPlanDurations" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "planId" uuid NOT NULL,
  "price" double precision NOT NULL,
  "duration" integer NOT NULL,
  CHECK ("price" > 1)
);

CREATE TABLE "Subscriptions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "planId" uuid NOT NULL,
  "companyId" uuid NOT NULL,
  "durationId" uuid NOT NULL,
  "endDate" timestamptz NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "createdBy" uuid NOT NULL,
  "paymentId" uuid NOT NULL
);

-- ---------------------------------------------------------------------------
-- Fonctionnalités produit (tables annexe — liées au modèle Tibus, pas Convex)
-- ---------------------------------------------------------------------------

CREATE TABLE "PromoCodes" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "companyId" uuid NOT NULL,
  "code" varchar NOT NULL,
  "discountType" "DiscountType" NOT NULL,
  "discountValue" double precision NOT NULL,
  "currency" varchar,
  "validFrom" timestamptz NOT NULL,
  "validUntil" timestamptz NOT NULL,
  "maxUsage" integer,
  "usageCount" integer NOT NULL DEFAULT 0,
  "trajetId" uuid,
  "isActive" boolean NOT NULL DEFAULT true,
  CHECK ("discountValue" > 0),
  CHECK ("usageCount" >= 0)
);

CREATE TABLE "Notifications" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "userId" uuid NOT NULL,
  "type" varchar NOT NULL,
  "title" varchar NOT NULL,
  "message" text NOT NULL,
  "isRead" boolean NOT NULL DEFAULT false,
  "relatedReservationBusId" uuid,
  "relatedReservationId" uuid,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE "Reviews" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "companyId" uuid NOT NULL,
  "reservationBusId" uuid NOT NULL,
  "travelerId" uuid NOT NULL,
  "rating" integer NOT NULL,
  "comment" text,
  "ownerReply" text,
  "ownerRepliedAt" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CHECK ("rating" >= 1 AND "rating" <= 5)
);

-- ---------------------------------------------------------------------------
-- Index uniques (Tibus.sql + annexe)
-- ---------------------------------------------------------------------------

CREATE UNIQUE INDEX "UserRoles_roleId_userId_companyId_key"
  ON "UserRoles" ("roleId", "userId", "companyId");

CREATE UNIQUE INDEX "Companies_countryId_name_key"
  ON "Companies" ("countryId", "name");

CREATE UNIQUE INDEX "ProgrammationTrajetDays_day_trajetId_departure_key"
  ON "ProgrammationTrajetDays" ("day", "trajetId", "departureHour", "departureMinutes");

CREATE UNIQUE INDEX "PromoCodes_companyId_code_key"
  ON "PromoCodes" ("companyId", "code");

CREATE UNIQUE INDEX "Reviews_reservationBusId_key"
  ON "Reviews" ("reservationBusId");

CREATE INDEX "Notifications_userId_isRead_idx"
  ON "Notifications" ("userId", "isRead");

-- ---------------------------------------------------------------------------
-- Commentaires colonnes (Tibus.sql)
-- ---------------------------------------------------------------------------

COMMENT ON COLUMN "ProgrammationTrajets"."depart" IS 'Gare de départ — Ex: Lomé';
COMMENT ON COLUMN "ProgrammationTrajets"."final" IS 'Gare d''arrivée — Ex: Cinkassé';
COMMENT ON COLUMN "ProgrammationTrajetArrets"."fromGareId" IS 'Ex: Tsévié, Atakpamé ...';
COMMENT ON COLUMN "ProgrammationTrajetArrets"."toGareId" IS 'Ex: Tsévié, Atakpamé ...';

-- ---------------------------------------------------------------------------
-- Clés étrangères — cœur métier Tibus
-- ---------------------------------------------------------------------------

ALTER TABLE "Users"
  ADD CONSTRAINT "Users_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "UserRoles"
  ADD CONSTRAINT "UserRoles_roleId_fkey"
  FOREIGN KEY ("roleId") REFERENCES "Role" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "UserRoles"
  ADD CONSTRAINT "UserRoles_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "UserRoles"
  ADD CONSTRAINT "UserRoles_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Cities"
  ADD CONSTRAINT "Cities_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Companies"
  ADD CONSTRAINT "Companies_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Bus"
  ADD CONSTRAINT "Bus_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Gares"
  ADD CONSTRAINT "Gares_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationBus"
  ADD CONSTRAINT "ProgrammationBus_busId_fkey"
  FOREIGN KEY ("busId") REFERENCES "Bus" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationBus"
  ADD CONSTRAINT "ProgrammationBus_trajetId_fkey"
  FOREIGN KEY ("trajetId") REFERENCES "ProgrammationTrajets" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationTrajets"
  ADD CONSTRAINT "ProgrammationTrajets_depart_fkey"
  FOREIGN KEY ("depart") REFERENCES "Gares" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationTrajets"
  ADD CONSTRAINT "ProgrammationTrajets_final_fkey"
  FOREIGN KEY ("final") REFERENCES "Gares" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationTrajetDays"
  ADD CONSTRAINT "ProgrammationTrajetDays_trajetId_fkey"
  FOREIGN KEY ("trajetId") REFERENCES "ProgrammationTrajets" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationTrajetArrets"
  ADD CONSTRAINT "ProgrammationTrajetArrets_trajetId_fkey"
  FOREIGN KEY ("trajetId") REFERENCES "ProgrammationTrajets" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationTrajetArrets"
  ADD CONSTRAINT "ProgrammationTrajetArrets_fromGareId_fkey"
  FOREIGN KEY ("fromGareId") REFERENCES "Gares" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ProgrammationTrajetArrets"
  ADD CONSTRAINT "ProgrammationTrajetArrets_toGareId_fkey"
  FOREIGN KEY ("toGareId") REFERENCES "Gares" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Reservations"
  ADD CONSTRAINT "Reservations_trajetId_fkey"
  FOREIGN KEY ("trajetId") REFERENCES "ProgrammationTrajets" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ReservationBus"
  ADD CONSTRAINT "ReservationBus_createdBy_fkey"
  FOREIGN KEY ("createdBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ReservationBus"
  ADD CONSTRAINT "ReservationBus_reservationId_fkey"
  FOREIGN KEY ("reservationId") REFERENCES "Reservations" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ReservationBus"
  ADD CONSTRAINT "ReservationBus_arretId_fkey"
  FOREIGN KEY ("arretId") REFERENCES "ProgrammationTrajetArrets" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ReservationBus"
  ADD CONSTRAINT "ReservationBus_paymentId_fkey"
  FOREIGN KEY ("paymentId") REFERENCES "Payment" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "ReservationBusColis"
  ADD CONSTRAINT "ReservationBusColis_reservationId_fkey"
  FOREIGN KEY ("reservationId") REFERENCES "ReservationBus" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "SubscriptionPlans"
  ADD CONSTRAINT "SubscriptionPlans_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "SubscriptionPlanDurations"
  ADD CONSTRAINT "SubscriptionPlanDurations_planId_fkey"
  FOREIGN KEY ("planId") REFERENCES "SubscriptionPlans" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Subscriptions"
  ADD CONSTRAINT "Subscriptions_planId_fkey"
  FOREIGN KEY ("planId") REFERENCES "SubscriptionPlans" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Subscriptions"
  ADD CONSTRAINT "Subscriptions_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Subscriptions"
  ADD CONSTRAINT "Subscriptions_durationId_fkey"
  FOREIGN KEY ("durationId") REFERENCES "SubscriptionPlanDurations" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Subscriptions"
  ADD CONSTRAINT "Subscriptions_createdBy_fkey"
  FOREIGN KEY ("createdBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Subscriptions"
  ADD CONSTRAINT "Subscriptions_paymentId_fkey"
  FOREIGN KEY ("paymentId") REFERENCES "Payment" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

-- ---------------------------------------------------------------------------
-- Clés étrangères — tables annexe
-- ---------------------------------------------------------------------------

ALTER TABLE "PromoCodes"
  ADD CONSTRAINT "PromoCodes_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "PromoCodes"
  ADD CONSTRAINT "PromoCodes_trajetId_fkey"
  FOREIGN KEY ("trajetId") REFERENCES "ProgrammationTrajets" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Notifications"
  ADD CONSTRAINT "Notifications_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Notifications"
  ADD CONSTRAINT "Notifications_relatedReservationBusId_fkey"
  FOREIGN KEY ("relatedReservationBusId") REFERENCES "ReservationBus" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Notifications"
  ADD CONSTRAINT "Notifications_relatedReservationId_fkey"
  FOREIGN KEY ("relatedReservationId") REFERENCES "Reservations" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Reviews"
  ADD CONSTRAINT "Reviews_companyId_fkey"
  FOREIGN KEY ("companyId") REFERENCES "Companies" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Reviews"
  ADD CONSTRAINT "Reviews_reservationBusId_fkey"
  FOREIGN KEY ("reservationBusId") REFERENCES "ReservationBus" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Reviews"
  ADD CONSTRAINT "Reviews_travelerId_fkey"
  FOREIGN KEY ("travelerId") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

-- ---------------------------------------------------------------------------
-- Row Level Security (RLS) — activé sur chaque table
-- Les politiques seront définies dans une migration ultérieure.
-- ---------------------------------------------------------------------------

ALTER TABLE "Countries" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Role" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Payment" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Cities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Users" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Companies" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "UserRoles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Bus" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Gares" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ProgrammationTrajets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ProgrammationTrajetDays" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ProgrammationTrajetArrets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ProgrammationBus" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Reservations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ReservationBus" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ReservationBusColis" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SubscriptionPlans" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SubscriptionPlanDurations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Subscriptions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PromoCodes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Notifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Reviews" ENABLE ROW LEVEL SECURITY;
