-- 086: coordonnées optionnelles pour afficher les gares sur la carte d'accueil

ALTER TABLE "Gares"
  ADD COLUMN IF NOT EXISTS "latitude" double precision,
  ADD COLUMN IF NOT EXISTS "longitude" double precision;

COMMENT ON COLUMN "Gares"."latitude" IS 'Latitude WGS84 (optionnel, pour carte accueil)';
COMMENT ON COLUMN "Gares"."longitude" IS 'Longitude WGS84 (optionnel, pour carte accueil)';
