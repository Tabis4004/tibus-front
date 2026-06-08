-- =============================================================================
-- Tibus — Données de démo (compagnie, gares, trajets, départs)
-- =============================================================================
-- PRÉREQUIS : scripts 001 à 006 exécutés
-- Projet : kqudaqtydimjclwaihqr
-- Idempotent : supprime puis recrée « Tibus Démo Transport »
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Nettoyage de la démo précédente
-- ---------------------------------------------------------------------------

DELETE FROM "Reservations" r
WHERE r."trajetId" IN (
  SELECT pt.id
  FROM "ProgrammationTrajets" pt
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  WHERE c.name = 'Tibus Démo Transport'
);

DELETE FROM "ProgrammationBus" pb
WHERE pb."trajetId" IN (
  SELECT pt.id
  FROM "ProgrammationTrajets" pt
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  WHERE c.name = 'Tibus Démo Transport'
);

DELETE FROM "ProgrammationTrajetArrets" pa
WHERE pa."trajetId" IN (
  SELECT pt.id
  FROM "ProgrammationTrajets" pt
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  WHERE c.name = 'Tibus Démo Transport'
);

DELETE FROM "ProgrammationTrajetDays" pd
WHERE pd."trajetId" IN (
  SELECT pt.id
  FROM "ProgrammationTrajets" pt
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  WHERE c.name = 'Tibus Démo Transport'
);

DELETE FROM "ProgrammationTrajets" pt
WHERE pt.depart IN (
  SELECT g.id FROM "Gares" g
  JOIN "Companies" c ON c.id = g."companyId"
  WHERE c.name = 'Tibus Démo Transport'
);

DELETE FROM "Bus" b
USING "Companies" c
WHERE b."companyId" = c.id AND c.name = 'Tibus Démo Transport';

DELETE FROM "Gares" g
USING "Companies" c
WHERE g."companyId" = c.id AND c.name = 'Tibus Démo Transport';

DELETE FROM "UserRoles" ur
USING "Companies" c
WHERE ur."companyId" = c.id AND c.name = 'Tibus Démo Transport';

DELETE FROM "Companies" WHERE name = 'Tibus Démo Transport';

-- ---------------------------------------------------------------------------
-- 1. Villes (Côte d'Ivoire)
-- ---------------------------------------------------------------------------

INSERT INTO "Cities" ("name", "countryId")
SELECT v.city, co.id
FROM (VALUES
  ('Abidjan'),
  ('Yamoussoukro'),
  ('Bouaké')
) AS v(city)
JOIN "Countries" co ON co.name = 'Côte d''Ivoire'
WHERE NOT EXISTS (
  SELECT 1 FROM "Cities" c
  WHERE c.name = v.city AND c."countryId" = co.id
);

-- ---------------------------------------------------------------------------
-- 2. Compagnie de démo
-- ---------------------------------------------------------------------------

INSERT INTO "Companies" (
  "name",
  "countryId",
  "isActive",
  "commissionRate",
  "managerName",
  "arretReservation"
)
SELECT
  'Tibus Démo Transport',
  co.id,
  true,
  8.5,
  'Demo Manager',
  true
FROM "Countries" co
WHERE co.name = 'Côte d''Ivoire';

-- ---------------------------------------------------------------------------
-- 3. Gares
-- ---------------------------------------------------------------------------

INSERT INTO "Gares" ("name", "companyId", "googleMapsLink")
SELECT g.name, c.id, g.maps
FROM "Companies" c
CROSS JOIN (VALUES
  ('Gare Adjamé — Abidjan', 'https://maps.app.goo.gl/demo-abidjan'),
  ('Gare Yamoussoukro', 'https://maps.app.goo.gl/demo-yamoussoukro'),
  ('Gare Bouaké', 'https://maps.app.goo.gl/demo-bouake')
) AS g(name, maps)
WHERE c.name = 'Tibus Démo Transport';

-- ---------------------------------------------------------------------------
-- 4. Bus
-- ---------------------------------------------------------------------------

INSERT INTO "Bus" ("registrationNumber", "model", "capacity", "companyId", "isActive")
SELECT
  'CI-DEMO-001',
  'Mercedes Sprinter',
  45,
  c.id,
  true
FROM "Companies" c
WHERE c.name = 'Tibus Démo Transport';

-- ---------------------------------------------------------------------------
-- 5. Programmation trajets (modèle récurrent)
-- ---------------------------------------------------------------------------

INSERT INTO "ProgrammationTrajets" ("depart", "final", "capacity")
SELECT g_from.id, g_to.id, 45
FROM "Companies" c
JOIN "Gares" g_from ON g_from."companyId" = c.id AND g_from.name = 'Gare Adjamé — Abidjan'
JOIN "Gares" g_to ON g_to."companyId" = c.id AND g_to.name = 'Gare Yamoussoukro'
WHERE c.name = 'Tibus Démo Transport';

INSERT INTO "ProgrammationTrajets" ("depart", "final", "capacity")
SELECT g_from.id, g_to.id, 45
FROM "Companies" c
JOIN "Gares" g_from ON g_from."companyId" = c.id AND g_from.name = 'Gare Adjamé — Abidjan'
JOIN "Gares" g_to ON g_to."companyId" = c.id AND g_to.name = 'Gare Bouaké'
WHERE c.name = 'Tibus Démo Transport';

-- ---------------------------------------------------------------------------
-- 6. Segments tarifaires (arrêts)
-- ---------------------------------------------------------------------------

INSERT INTO "ProgrammationTrajetArrets" ("trajetId", "fromGareId", "toGareId", "price", "kilometrage")
SELECT pt.id, g_from.id, g_to.id, 5000, 240
FROM "ProgrammationTrajets" pt
JOIN "Gares" g_from ON g_from.id = pt.depart AND g_from.name = 'Gare Adjamé — Abidjan'
JOIN "Gares" g_to ON g_to.id = pt.final AND g_to.name = 'Gare Yamoussoukro';

INSERT INTO "ProgrammationTrajetArrets" ("trajetId", "fromGareId", "toGareId", "price", "kilometrage")
SELECT pt.id, g_from.id, g_to.id, 3500, 350
FROM "ProgrammationTrajets" pt
JOIN "Gares" g_from ON g_from.id = pt.depart AND g_from.name = 'Gare Adjamé — Abidjan'
JOIN "Gares" g_to ON g_to.id = pt.final AND g_to.name = 'Gare Bouaké';

-- ---------------------------------------------------------------------------
-- 7. Jours / horaires récurrents (day 0 = dimanche … 6 = samedi)
-- ---------------------------------------------------------------------------

INSERT INTO "ProgrammationTrajetDays" ("trajetId", "day", "departureHour", "departureMinutes")
SELECT pt.id, dow.day, sched.hour, sched.minute
FROM "ProgrammationTrajets" pt
JOIN "Gares" g ON g.id = pt.depart
JOIN "Companies" c ON c.id = g."companyId" AND c.name = 'Tibus Démo Transport'
CROSS JOIN generate_series(0, 6) AS dow(day)
CROSS JOIN (VALUES (6, 0), (14, 0)) AS sched(hour, minute);

-- ---------------------------------------------------------------------------
-- 8. Bus assigné aux trajets
-- ---------------------------------------------------------------------------

INSERT INTO "ProgrammationBus" ("busId", "trajetId", "isActive")
SELECT b.id, pt.id, true
FROM "Bus" b
JOIN "Companies" c ON c.id = b."companyId" AND c.name = 'Tibus Démo Transport'
JOIN "ProgrammationTrajets" pt ON pt.depart IN (
  SELECT g.id FROM "Gares" g WHERE g."companyId" = c.id
);

-- ---------------------------------------------------------------------------
-- 9. Départs concrets (14 prochains jours, 6h et 14h)
-- ---------------------------------------------------------------------------

INSERT INTO "Reservations" ("date", "trajetId", "capacity")
SELECT
  (current_date + d.day_offset + sched.hour * interval '1 hour')::timestamptz,
  pt.id,
  COALESCE(pt.capacity, 45)
FROM "ProgrammationTrajets" pt
JOIN "Gares" g ON g.id = pt.depart
JOIN "Companies" c ON c.id = g."companyId" AND c.name = 'Tibus Démo Transport'
CROSS JOIN generate_series(0, 13) AS d(day_offset)
CROSS JOIN (VALUES (6), (14)) AS sched(hour)
WHERE (current_date + d.day_offset + sched.hour * interval '1 hour') > now();

-- ---------------------------------------------------------------------------
-- 10. Owner de démo (tabiscompany@gmail.com si présent)
-- ---------------------------------------------------------------------------

INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId")
SELECT r.id, u.id, c.id, NULL
FROM "Users" u
JOIN "Companies" c ON c.name = 'Tibus Démo Transport'
JOIN "Role" r ON r.name = 'owner'
WHERE u.email = 'tabiscompany@gmail.com'
  AND NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    WHERE ur."userId" = u.id
      AND ur."roleId" = r.id
      AND ur."companyId" = c.id
  );

COMMIT;

-- ---------------------------------------------------------------------------
-- Vérification
-- ---------------------------------------------------------------------------

SELECT c.name AS company, COUNT(DISTINCT g.id) AS gares, COUNT(DISTINCT b.id) AS buses
FROM "Companies" c
LEFT JOIN "Gares" g ON g."companyId" = c.id
LEFT JOIN "Bus" b ON b."companyId" = c.id
WHERE c.name = 'Tibus Démo Transport'
GROUP BY c.name;

SELECT
  g_from.name AS depart,
  g_to.name AS arrivee,
  pa.price,
  COUNT(DISTINCT r.id) AS departs_a_venir
FROM "ProgrammationTrajets" pt
JOIN "Gares" g_from ON g_from.id = pt.depart
JOIN "Gares" g_to ON g_to.id = pt.final
JOIN "ProgrammationTrajetArrets" pa
  ON pa."trajetId" = pt.id AND pa."fromGareId" = pt.depart AND pa."toGareId" = pt.final
LEFT JOIN "Reservations" r ON r."trajetId" = pt.id AND r.date > now()
GROUP BY g_from.name, g_to.name, pa.price
ORDER BY g_from.name, g_to.name;
