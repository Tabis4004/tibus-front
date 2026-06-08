-- =============================================================================
-- Tibus — Données minimales pour l'inscription (au moins 1 pays requis)
-- Exécuter une fois dans Supabase SQL Editor
-- =============================================================================

INSERT INTO "Countries" ("name", "currency") VALUES
  ('Togo', 'XOF'),
  ('Bénin', 'XOF'),
  ('Côte d''Ivoire', 'XOF'),
  ('Cameroun', 'XAF'),
  ('Gabon', 'XAF')
ON CONFLICT DO NOTHING;
