-- =============================================================================
-- Tibus — Départ test paiement LIVE à 200 XOF
-- =============================================================================
-- PRÉREQUIS : 007_seed_demo_data.sql
-- Projet : kqudaqtydimjclwaihqr
-- Idempotent : bus marqueur CI-LIVE-TEST-200
-- =============================================================================

BEGIN;

DELETE FROM "Reservations" r
WHERE r."trajetId" IN (
  SELECT pb."trajetId" FROM "ProgrammationBus" pb
  JOIN "Bus" b ON b.id = pb."busId"
  WHERE b."registrationNumber" = 'CI-LIVE-TEST-200'
);

DELETE FROM "ProgrammationBus" pb
USING "Bus" b
WHERE pb."busId" = b.id AND b."registrationNumber" = 'CI-LIVE-TEST-200';

DELETE FROM "ProgrammationTrajetDays" pd
WHERE pd."trajetId" IN (
  SELECT pb."trajetId" FROM "ProgrammationBus" pb
  JOIN "Bus" b ON b.id = pb."busId"
  WHERE b."registrationNumber" = 'CI-LIVE-TEST-200'
);

DELETE FROM "ProgrammationTrajetArrets" pa
WHERE pa."trajetId" IN (
  SELECT pb."trajetId" FROM "ProgrammationBus" pb
  JOIN "Bus" b ON b.id = pb."busId"
  WHERE b."registrationNumber" = 'CI-LIVE-TEST-200'
);

DELETE FROM "ProgrammationTrajets" pt
WHERE pt.id IN (
  SELECT pb."trajetId" FROM "ProgrammationBus" pb
  JOIN "Bus" b ON b.id = pb."busId"
  WHERE b."registrationNumber" = 'CI-LIVE-TEST-200'
);

DELETE FROM "Bus" WHERE "registrationNumber" = 'CI-LIVE-TEST-200';

WITH demo AS (
  SELECT c.id AS company_id, g_from.id AS depart_id, g_to.id AS final_id
  FROM "Companies" c
  JOIN "Gares" g_from ON g_from."companyId" = c.id AND g_from.name = 'Gare Adjamé — Abidjan'
  JOIN "Gares" g_to ON g_to."companyId" = c.id AND g_to.name = 'Gare Yamoussoukro'
  WHERE c.name = 'Tibus Démo Transport'
),
new_bus AS (
  INSERT INTO "Bus" ("registrationNumber", "model", "capacity", "companyId", "isActive")
  SELECT 'CI-LIVE-TEST-200', 'Test Live 200 XOF', 20, company_id, true FROM demo
  RETURNING id AS bus_id
),
new_trajet AS (
  INSERT INTO "ProgrammationTrajets" ("depart", "final", "capacity")
  SELECT depart_id, final_id, 20 FROM demo
  RETURNING id AS trajet_id, depart, final
),
new_arret AS (
  INSERT INTO "ProgrammationTrajetArrets" ("trajetId", "fromGareId", "toGareId", "price", "kilometrage")
  SELECT trajet_id, depart, final, 200, 240 FROM new_trajet
  RETURNING "trajetId" AS trajet_id
),
new_bus_link AS (
  INSERT INTO "ProgrammationBus" ("busId", "trajetId", "isActive")
  SELECT nb.bus_id, na.trajet_id, true
  FROM new_bus nb CROSS JOIN new_arret na
  RETURNING "trajetId" AS trajet_id
),
new_days AS (
  INSERT INTO "ProgrammationTrajetDays" ("trajetId", "day", "departureHour", "departureMinutes")
  SELECT nbl.trajet_id, dow.day, 10, 0
  FROM new_bus_link nbl
  CROSS JOIN generate_series(0, 6) AS dow(day)
  RETURNING "trajetId" AS trajet_id
)
INSERT INTO "Reservations" ("date", "trajetId", "capacity")
SELECT
  (current_date + d.day_offset + time '10:00')::timestamptz,
  nd.trajet_id,
  20
FROM new_days nd
CROSS JOIN generate_series(0, 6) AS d(day_offset)
WHERE (current_date + d.day_offset + time '10:00') > now();

COMMIT;

-- Vérification : repérez le trajet à 200 XOF (bus CI-LIVE-TEST-200)
SELECT
  r.id AS reservation_id,
  r.date AS depart_le,
  pa.price AS prix_xof,
  g_from.name AS origine,
  g_to.name AS destination,
  b."registrationNumber" AS bus
FROM "Reservations" r
JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
JOIN "ProgrammationTrajetArrets" pa
  ON pa."trajetId" = pt.id AND pa."fromGareId" = pt.depart AND pa."toGareId" = pt.final
JOIN "Gares" g_from ON g_from.id = pt.depart
JOIN "Gares" g_to ON g_to.id = pt.final
JOIN "ProgrammationBus" pb ON pb."trajetId" = pt.id
JOIN "Bus" b ON b.id = pb."busId"
WHERE b."registrationNumber" = 'CI-LIVE-TEST-200'
  AND r.date > now()
ORDER BY r.date
LIMIT 10;
