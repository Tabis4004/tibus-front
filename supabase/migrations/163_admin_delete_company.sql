-- Suppression DÉFINITIVE d'une compagnie par le super admin, y compris
-- toutes ses données (gares, bus, itinéraires, réservations, billets,
-- paiements, caisses, colis, abonnements, avis, rôles…). Action
-- irréversible — l'UI affiche une alerte et transmet le nom exact de la
-- compagnie en confirmation.
-- Ordre de suppression déduit du graphe FK réel (contraintes NO ACTION /
-- RESTRICT traitées explicitement ; les FK ON DELETE CASCADE / SET NULL
-- font le reste au moment du DELETE final sur "Companies").

CREATE OR REPLACE FUNCTION public.admin_delete_company(p_company_id uuid, p_confirm_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_name text;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT name INTO v_name FROM "Companies" WHERE id = p_company_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;
  IF btrim(COALESCE(p_confirm_name, '')) <> v_name THEN
    RAISE EXCEPTION 'Confirmation invalide : le nom fourni ne correspond pas a la compagnie';
  END IF;

  -- Périmètre
  CREATE TEMP TABLE _del_gares ON COMMIT DROP AS
    SELECT id FROM "Gares" WHERE "companyId" = p_company_id;
  CREATE TEMP TABLE _del_trajets ON COMMIT DROP AS
    SELECT id FROM "ProgrammationTrajets"
    WHERE depart IN (SELECT id FROM _del_gares) OR final IN (SELECT id FROM _del_gares);
  CREATE TEMP TABLE _del_res ON COMMIT DROP AS
    SELECT id FROM "Reservations" WHERE "trajetId" IN (SELECT id FROM _del_trajets);
  CREATE TEMP TABLE _del_rb ON COMMIT DROP AS
    SELECT id, "paymentId" FROM "ReservationBus"
    WHERE "reservationId" IN (SELECT id FROM _del_res);
  CREATE TEMP TABLE _del_payments ON COMMIT DROP AS
    SELECT DISTINCT "paymentId" AS id FROM _del_rb WHERE "paymentId" IS NOT NULL
    UNION
    SELECT DISTINCT "paymentId" FROM "Subscriptions"
    WHERE "companyId" = p_company_id AND "paymentId" IS NOT NULL;

  -- Billets et dépendances
  DELETE FROM "ReservationBusColis" WHERE "reservationId" IN (SELECT id FROM _del_rb);
  DELETE FROM "Notifications"
    WHERE "relatedReservationBusId" IN (SELECT id FROM _del_rb)
       OR "relatedReservationId" IN (SELECT id FROM _del_res);
  DELETE FROM "Reviews"
    WHERE "companyId" = p_company_id
       OR "reservationBusId" IN (SELECT id FROM _del_rb);
  DELETE FROM "ReservationBus" WHERE id IN (SELECT id FROM _del_rb);
  DELETE FROM "Reservations" WHERE id IN (SELECT id FROM _del_res);

  -- Programmation
  DELETE FROM "ProgrammationTrajetDays" WHERE "trajetId" IN (SELECT id FROM _del_trajets);
  DELETE FROM "ProgrammationTrajetArrets"
    WHERE "trajetId" IN (SELECT id FROM _del_trajets)
       OR "fromGareId" IN (SELECT id FROM _del_gares)
       OR "toGareId" IN (SELECT id FROM _del_gares);
  DELETE FROM "ProgrammationBus"
    WHERE "trajetId" IN (SELECT id FROM _del_trajets)
       OR "busId" IN (SELECT id FROM "Bus" WHERE "companyId" = p_company_id);
  DELETE FROM "PromoCodes" WHERE "companyId" = p_company_id;
  DELETE FROM "ProgrammationTrajets" WHERE id IN (SELECT id FROM _del_trajets);

  -- Colis autonomes (avant les gares : FK NO ACTION sur gare_depart/destination)
  DELETE FROM colis_autonomes WHERE company_id = p_company_id;

  -- Caisses de gare (RESTRICT sur Gares)
  DELETE FROM mouvements_caisse
    WHERE caisse_id IN (SELECT id FROM caisses_gares WHERE gare_id IN (SELECT id FROM _del_gares));
  DELETE FROM reversements_comptables
    WHERE caisse_id IN (SELECT id FROM caisses_gares WHERE gare_id IN (SELECT id FROM _del_gares));
  DELETE FROM caisses_gares WHERE gare_id IN (SELECT id FROM _del_gares);

  -- Structure
  DELETE FROM "Gares" WHERE id IN (SELECT id FROM _del_gares);
  DELETE FROM "Bus" WHERE "companyId" = p_company_id;
  DELETE FROM "Subscriptions" WHERE "companyId" = p_company_id;
  DELETE FROM "Payment" WHERE id IN (SELECT id FROM _del_payments);
  DELETE FROM "UserRoles" WHERE "companyId" = p_company_id;
  DELETE FROM "IndependentSellerCompanies" WHERE "companyId" = p_company_id;

  -- Dépenses (RESTRICT entre expense et catégorie)
  DELETE FROM "CompanyExpense" WHERE "companyId" = p_company_id;
  DELETE FROM "CompanyExpenseCategory" WHERE "companyId" = p_company_id;

  -- Le reste part en cascade / SET NULL avec la compagnie :
  -- CommissionSettings, CompanyGuaranteeLedger/Deposit, Loyalty*,
  -- colis_natures, Partner*, CompanyFeatureModules, GareCounterCommissionTiers,
  -- CompanyOperatingCountries, CompanyCancellation*, StakeholderCommissionSettings,
  -- Users.activeOwnerCompanyId (NULL), PlatformAuditLogs.companyId (NULL).
  DELETE FROM "Companies" WHERE id = p_company_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_company(uuid, text) FROM PUBLIC, anon;
