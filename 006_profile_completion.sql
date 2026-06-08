-- =============================================================================
-- Tibus — Complétion de profil utilisateur
-- =============================================================================
-- PRÉREQUIS : init_schema.sql + 001_roles_model.sql exécutés
-- Projet : kqudaqtydimjclwaihqr
-- =============================================================================

ALTER TABLE "Users"
  ADD COLUMN IF NOT EXISTS "profileCompleted" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "onboardingCompleted" boolean NOT NULL DEFAULT false;

-- Comptes déjà renseignés (téléphone saisi) = profil considéré complet
UPDATE "Users"
SET "profileCompleted" = true
WHERE phone IS NOT NULL AND TRIM(phone) <> '';
