-- Coordonnées de démonstration pour les gares sans lat/lng (liens goo.gl non extractibles côté client)
UPDATE "Gares"
SET
  "latitude" = 5.3599517,
  "longitude" = -4.0082563
WHERE "name" = 'Gare Adjamé — Abidjan'
  AND ("latitude" IS NULL OR "longitude" IS NULL);

UPDATE "Gares"
SET
  "latitude" = 6.827621,
  "longitude" = -5.289343
WHERE "name" = 'Gare Yamoussoukro'
  AND ("latitude" IS NULL OR "longitude" IS NULL);

UPDATE "Gares"
SET
  "latitude" = 7.693856,
  "longitude" = -5.030313
WHERE "name" = 'Gare Bouaké'
  AND ("latitude" IS NULL OR "longitude" IS NULL);
