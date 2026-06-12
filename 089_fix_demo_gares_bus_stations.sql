-- 089: liens Google Maps + coordonnées des gares routières (pas centres-villes)

UPDATE "Gares"
SET
  "googleMapsLink" = 'https://www.google.com/maps/search/?api=1&query=5.3549207,-4.022938',
  "latitude" = 5.3549207,
  "longitude" = -4.022938
WHERE "name" = 'Gare Adjamé — Abidjan';

UPDATE "Gares"
SET
  "googleMapsLink" = 'https://www.google.com/maps/search/?api=1&query=7.6890917,-5.0284825',
  "latitude" = 7.6890917,
  "longitude" = -5.0284825
WHERE "name" = 'Gare Bouaké';

UPDATE "Gares"
SET
  "googleMapsLink" = 'https://www.google.com/maps/search/?api=1&query=6.8125001,-5.2646573',
  "latitude" = 6.8125001,
  "longitude" = -5.2646573
WHERE "name" = 'Gare Yamoussoukro';
