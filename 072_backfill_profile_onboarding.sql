-- =============================================================================
-- Tibus — Comptes existants : ne plus redemander profil / guide à chaque login
-- =============================================================================
-- PRÉREQUIS : 006_profile_completion.sql
-- =============================================================================

ALTER TABLE "Users"
  ADD COLUMN IF NOT EXISTS "profileCompleted" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "onboardingCompleted" boolean NOT NULL DEFAULT false;

UPDATE "Users"
SET "profileCompleted" = true
WHERE "profileCompleted" = false
  AND phone IS NOT NULL
  AND TRIM(phone) <> '';

-- Comptes déjà renseignés = guide considéré vu (évite le popup « Étape 1/1 » à chaque login)
UPDATE "Users"
SET "onboardingCompleted" = true
WHERE "onboardingCompleted" = false
  AND (
    "profileCompleted" = true
    OR (phone IS NOT NULL AND TRIM(phone) <> '')
  );
