-- 088: coordonnées précises extraites des liens Google Maps (goo.gl résolus)

-- Côte d'Ivoire — gares routières (pin exact, pas centre-ville)
UPDATE "Gares"
SET "latitude" = 5.359297, "longitude" = -3.987978
WHERE "name" = 'Gare Adjamé — Abidjan';

UPDATE "Gares"
SET "latitude" = 7.684389, "longitude" = -5.027012
WHERE "name" = 'Gare Bouaké';

UPDATE "Gares"
SET "latitude" = 6.806711, "longitude" = -5.279812
WHERE "name" = 'Gare Yamoussoukro';

-- Burkina Faso — liens maps.app.goo.gl résolus (!3d/!4d ou /maps/search/)
UPDATE "Gares"
SET "latitude" = 5.3631084, "longitude" = -3.9366664
WHERE "name" = 'Bon Prix Faya'
  AND "googleMapsLink" = 'https://maps.app.goo.gl/P7ud4uiT8YLmFR9r6';

UPDATE "Gares"
SET "latitude" = 5.3579116, "longitude" = -3.9247884
WHERE "name" = 'Gare du Nord'
  AND "googleMapsLink" = 'https://maps.app.goo.gl/1sQC9xYbLHGTfCbZ7';

UPDATE "Gares"
SET "latitude" = 11.177583, "longitude" = -4.293594
WHERE "name" = 'Test gare 1'
  AND "googleMapsLink" = 'https://maps.app.goo.gl/5xzZb5nXVVuewQWt9';

UPDATE "Gares"
SET "latitude" = 12.352549, "longitude" = -1.556255
WHERE "name" = 'Test gare 2'
  AND "googleMapsLink" = 'https://maps.app.goo.gl/SGFXzeknPK4pYPWJ7';

UPDATE "Gares"
SET "latitude" = 5.3533024, "longitude" = -3.9416661
WHERE "name" = 'Tibus BF'
  AND "googleMapsLink" = 'https://maps.app.goo.gl/f9kFSfRjQGujiLTZ9';
