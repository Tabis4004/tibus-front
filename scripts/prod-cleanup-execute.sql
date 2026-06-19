-- =============================================================================
-- EXÉCUTION PROD — purge TOUTES les compagnies + ventes associées
-- Projet : kqudaqtydimjclwaihqr · Backup obligatoire avant exécution
--
-- CONSERVÉ : Users / auth.users, rôles globaux (traveler, admin_pays…), référentiels
-- SUPPRIMÉ : toutes les compagnies + données métier liées
--
-- SQL Editor : sélectionner TOUT (Ctrl+A) puis Run en une seule fois.
-- =============================================================================

BEGIN;

DELETE FROM "UserRoles"
WHERE "companyId" IN (SELECT id FROM "Companies");

DELETE FROM "Notifications" n
WHERE n."relatedReservationBusId" IN (
  SELECT rb.id FROM "ReservationBus" rb
  JOIN "ProgrammationTrajetArrets" a ON a.id = rb."arretId"
  JOIN "ProgrammationTrajets" t ON t.id = a."trajetId"
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
)
OR n."relatedReservationId" IN (
  SELECT r.id FROM "Reservations" r
  JOIN "ProgrammationTrajets" t ON t.id = r."trajetId"
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
);

DELETE FROM "Reviews" WHERE "companyId" IN (SELECT id FROM "Companies");
DELETE FROM "PromoCodes" WHERE "companyId" IN (SELECT id FROM "Companies");
DELETE FROM "Subscriptions" WHERE "companyId" IN (SELECT id FROM "Companies");
DELETE FROM public."CounterSaleIdempotency";

DELETE FROM public.colis_natures_selectionnees cns
WHERE cns.colis_id IN (
  SELECT ca.id FROM public.colis_autonomes ca
  WHERE ca.company_id IN (SELECT id FROM "Companies")
);

DELETE FROM public.colis_autonomes
WHERE company_id IN (SELECT id FROM "Companies");

DELETE FROM reversements_comptables r
WHERE r.caisse_id IN (
  SELECT cg.id FROM caisses_gares cg WHERE cg.gare_id IN (SELECT id FROM "Gares")
);

DELETE FROM public.mouvements_caisse m
WHERE m.caisse_id IN (
  SELECT cg.id FROM caisses_gares cg WHERE cg.gare_id IN (SELECT id FROM "Gares")
);

DELETE FROM caisses_gares WHERE gare_id IN (SELECT id FROM "Gares");

DELETE FROM "ReservationBusColis" rbc
WHERE rbc."reservationId" IN (
  SELECT rb.id FROM "ReservationBus" rb
  JOIN "ProgrammationTrajetArrets" a ON a.id = rb."arretId"
  JOIN "ProgrammationTrajets" t ON t.id = a."trajetId"
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
);

-- Paiements via ReservationBus.paymentId (pas de paymentId sur Reservations)
DELETE FROM "Payment" p
WHERE p.id IN (
  SELECT DISTINCT rb."paymentId"
  FROM "ReservationBus" rb
  JOIN "ProgrammationTrajetArrets" a ON a.id = rb."arretId"
  JOIN "ProgrammationTrajets" t ON t.id = a."trajetId"
  WHERE rb."paymentId" IS NOT NULL
    AND (t.depart IN (SELECT id FROM "Gares") OR t.final IN (SELECT id FROM "Gares"))
);

DELETE FROM "ReservationBus" rb
WHERE rb."arretId" IN (
  SELECT a.id FROM "ProgrammationTrajetArrets" a
  JOIN "ProgrammationTrajets" t ON t.id = a."trajetId"
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
);

DELETE FROM "ProgrammationBus" pb
WHERE pb."trajetId" IN (
  SELECT t.id FROM "ProgrammationTrajets" t
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
);

DELETE FROM "ProgrammationTrajetDays" ptd
WHERE ptd."trajetId" IN (
  SELECT t.id FROM "ProgrammationTrajets" t
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
);

DELETE FROM "ProgrammationTrajetArrets" a
WHERE a."trajetId" IN (
  SELECT t.id FROM "ProgrammationTrajets" t
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
);

DELETE FROM "Reservations" r
WHERE r."trajetId" IN (
  SELECT t.id FROM "ProgrammationTrajets" t
  WHERE t.depart IN (SELECT id FROM "Gares")
     OR t.final IN (SELECT id FROM "Gares")
);

DELETE FROM "ProgrammationTrajets" t
WHERE t.depart IN (SELECT id FROM "Gares")
   OR t.final IN (SELECT id FROM "Gares");

DELETE FROM "Bus" WHERE "companyId" IN (SELECT id FROM "Companies");
DELETE FROM "Gares" WHERE "companyId" IN (SELECT id FROM "Companies");

DELETE FROM "CompanyExpense" WHERE "companyId" IN (SELECT id FROM "Companies");
DELETE FROM "CompanyExpenseCategory" WHERE "companyId" IN (SELECT id FROM "Companies");
DELETE FROM public."CompanyFeatureModules" WHERE "companyId" IN (SELECT id FROM "Companies");
DELETE FROM "StakeholderCommissionSettings" WHERE "companyId" IN (SELECT id FROM "Companies");

DELETE FROM "Companies";

SELECT COUNT(*) AS compagnies_restantes FROM "Companies";
SELECT COUNT(*) AS utilisateurs_conserves FROM "Users";
SELECT COUNT(*) AS billets_restants FROM "ReservationBus";

COMMIT;
