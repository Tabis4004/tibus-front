-- =============================================================================
-- Tibus 1.0 — Nettoyage données de test avant mise en production
-- Projet cible : kqudaqtydimjclwaihqr (vérifier en haut à gauche du SQL Editor)
--
-- ⚠️  IRRÉVERSIBLE. Backup Supabase (Dashboard → Database → Backups) avant exécution.
--
-- Usage :
--   1. Section AUDIT seule → noter IDs et volumes.
--   2. Ajuster companies_to_purge (noms connus ci-dessous + patterns).
--   3. CLEANUP avec ROLLBACK (dry-run), puis COMMIT.
--
-- Ne pas placer dans supabase/migrations/ (pas de db push automatique).
-- =============================================================================

-- Compagnies de test connues sur Tibus (à confirmer via AUDIT) :
--   • Tibus Démo Transport     (seed 007_seed_demo_data.sql)
--   • Tabis Express BF         (captures / tests guichet)
--   • Tout nom contenant Démo, Demo, Test, Test Live

-- ─── AUDIT (lecture seule) ───────────────────────────────────────────────────

SELECT id, name, "countryId", "isActive", "createdAt"
FROM "Companies"
ORDER BY "createdAt";

SELECT id, name
FROM "Companies"
WHERE name ILIKE ANY (ARRAY[
  '%démo%', '%demo%', '%test%', '%Test Live%',
  'Tibus Démo Transport', 'Tabis Express BF'
]);

SELECT c.name, COUNT(rb.id) AS billets
FROM "ReservationBus" rb
JOIN "ProgrammationTrajetArrets" a ON a.id = rb."arretId"
JOIN "ProgrammationTrajets" t ON t.id = a."trajetId"
JOIN "Gares" g ON g.id = t.depart
JOIN "Companies" c ON c.id = g."companyId"
GROUP BY c.name
ORDER BY billets DESC;

SELECT c.name, COUNT(*) AS caisses_ouvertes
FROM caisses_gares cg
JOIN "Gares" g ON g.id = cg.gare_id
JOIN "Companies" c ON c.id = g."companyId"
WHERE cg.statut = 'ouverte'
GROUP BY c.name;

-- ─── CLEANUP (transaction) ───────────────────────────────────────────────────
-- Décommenter le bloc ci-dessous dans le SQL Editor Supabase.

/*
BEGIN;

CREATE TEMP TABLE companies_to_purge ON COMMIT DROP AS
SELECT id, name
FROM "Companies"
WHERE name ILIKE ANY (ARRAY[
  '%démo%',
  '%demo%',
  '%test%',
  '%Test Live%'
])
OR name IN (
  'Tibus Démo Transport',
  'Tabis Express BF'
);

DO $$
DECLARE n int; r record;
BEGIN
  SELECT COUNT(*) INTO n FROM companies_to_purge;
  IF n = 0 THEN
    RAISE EXCEPTION 'Aucune compagnie à purger — vérifiez le filtre.';
  END IF;
  RAISE NOTICE 'Compagnies ciblées : %', n;
  FOR r IN SELECT name FROM companies_to_purge LOOP
    RAISE NOTICE '  → %', r.name;
  END LOOP;
END $$;

CREATE TEMP TABLE gares_to_purge ON COMMIT DROP AS
SELECT g.id FROM "Gares" g
JOIN companies_to_purge c ON c.id = g."companyId";

CREATE TEMP TABLE trajets_to_purge ON COMMIT DROP AS
SELECT DISTINCT t.id FROM "ProgrammationTrajets" t
WHERE t.depart IN (SELECT id FROM gares_to_purge)
   OR t.final IN (SELECT id FROM gares_to_purge);

CREATE TEMP TABLE arrets_to_purge ON COMMIT DROP AS
SELECT a.id FROM "ProgrammationTrajetArrets" a
WHERE a."trajetId" IN (SELECT id FROM trajets_to_purge);

CREATE TEMP TABLE rb_to_purge ON COMMIT DROP AS
SELECT rb.id, rb."paymentId", rb."reservationId"
FROM "ReservationBus" rb
WHERE rb."arretId" IN (SELECT id FROM arrets_to_purge);

CREATE TEMP TABLE reservations_to_purge ON COMMIT DROP AS
SELECT DISTINCT r.id FROM "Reservations" r
WHERE r.id IN (SELECT "reservationId" FROM rb_to_purge)
   OR r."trajetId" IN (SELECT id FROM trajets_to_purge);

CREATE TEMP TABLE payments_to_purge ON COMMIT DROP AS
SELECT DISTINCT p.id FROM "Payment" p
WHERE p.id IN (SELECT "paymentId" FROM rb_to_purge WHERE "paymentId" IS NOT NULL);

DELETE FROM "Notifications" n
WHERE n."relatedReservationBusId" IN (SELECT id FROM rb_to_purge)
   OR n."relatedReservationId" IN (SELECT id FROM reservations_to_purge);

DELETE FROM "Reviews" rv WHERE rv."companyId" IN (SELECT id FROM companies_to_purge);
DELETE FROM "PromoCodes" pc WHERE pc."companyId" IN (SELECT id FROM companies_to_purge);
DELETE FROM "Subscriptions" s WHERE s."companyId" IN (SELECT id FROM companies_to_purge);

DELETE FROM public."CounterSaleIdempotency" i
WHERE i.reservation_id IN (SELECT id FROM reservations_to_purge);

DELETE FROM public.colis_natures_selectionnees cns
WHERE cns.colis_id IN (
  SELECT ca.id FROM public.colis_autonomes ca
  WHERE ca.company_id IN (SELECT id FROM companies_to_purge)
);

DELETE FROM public.colis_autonomes ca
WHERE ca.company_id IN (SELECT id FROM companies_to_purge);

DELETE FROM public.mouvements_caisse_gare m
WHERE m.caisse_id IN (
  SELECT cg.id FROM caisses_gares cg
  WHERE cg.gare_id IN (SELECT id FROM gares_to_purge)
);

DELETE FROM caisses_gares cg WHERE cg.gare_id IN (SELECT id FROM gares_to_purge);

DELETE FROM "ReservationBusColis" rbc
WHERE rbc."reservationId" IN (SELECT id FROM rb_to_purge);

DELETE FROM "ReservationBus" rb WHERE rb.id IN (SELECT id FROM rb_to_purge);

DELETE FROM "ProgrammationBus" pb
WHERE pb."trajetId" IN (SELECT id FROM trajets_to_purge);

DELETE FROM "ProgrammationTrajetDays" ptd
WHERE ptd."trajetId" IN (SELECT id FROM trajets_to_purge);

DELETE FROM "ProgrammationTrajetArrets" a WHERE a.id IN (SELECT id FROM arrets_to_purge);

DELETE FROM "Reservations" r WHERE r.id IN (SELECT id FROM reservations_to_purge);

DELETE FROM "ProgrammationTrajets" t WHERE t.id IN (SELECT id FROM trajets_to_purge);

DELETE FROM "Payment" p
WHERE p.id IN (SELECT id FROM payments_to_purge)
  AND NOT EXISTS (SELECT 1 FROM "ReservationBus" rb WHERE rb."paymentId" = p.id);

DELETE FROM "Bus" b WHERE b."companyId" IN (SELECT id FROM companies_to_purge);
DELETE FROM "Gares" g WHERE g.id IN (SELECT id FROM gares_to_purge);

-- Comptes Users conservés — supprimer UserRoles liés aux compagnies purgées
DELETE FROM "UserRoles" ur
WHERE ur."companyId" IN (SELECT id FROM companies_to_purge);

DELETE FROM "CompanyExpense" e WHERE e."companyId" IN (SELECT id FROM companies_to_purge);
DELETE FROM "CompanyExpenseCategory" ec WHERE ec."companyId" IN (SELECT id FROM companies_to_purge);

DELETE FROM public."CompanyFeatureModules" m
WHERE m."companyId" IN (SELECT id FROM companies_to_purge);

DELETE FROM "StakeholderCommissionSettings" s
WHERE s."companyId" IN (SELECT id FROM companies_to_purge);

DELETE FROM "Companies" c WHERE c.id IN (SELECT id FROM companies_to_purge);

SELECT COUNT(*) AS companies_restantes FROM "Companies";
SELECT COUNT(*) AS billets_restants FROM "ReservationBus";

ROLLBACK;
-- COMMIT;
*/
