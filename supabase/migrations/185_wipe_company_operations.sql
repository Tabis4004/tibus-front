-- Bouton superadmin "Vider les opérations" : remet une compagnie à zéro
-- (ventes tickets, colis, bordereaux/manifests, historique de caisse)
-- SANS supprimer la compagnie elle-même ni sa structure (gares, bus,
-- itinéraires, rôles/utilisateurs, abonnements, fidélité, commissions...).
-- Même esprit que admin_delete_company (migration 163) pour le graphe FK,
-- mais périmètre restreint aux données "opérationnelles" — utilisable à
-- tout moment (nettoyage de données de formation/démo), contrairement à la
-- suppression de compagnie qui est définitive.
--
-- SUPPRIMÉ : Reservations/ReservationBus/ReservationBusColis (billets
-- guichet vendus sur les trajets de la compagnie), colis_autonomes (cascade
-- colis_natures_selectionnees + bordereau_colis), bordereaux_livraison,
-- mouvements_caisse et reversements_comptables des caisses de la compagnie.
-- RÉINITIALISÉ : caisses_gares (solde à 0, statut 'cloturee'), compteurs de
-- numérotation colis/bordereaux de la compagnie (redémarrent à 0).
-- NON TOUCHÉ : Companies, Gares, Bus, ProgrammationTrajets/Bus, rôles,
-- utilisateurs, abonnements, fidélité, commissions/stakeholders, garanties,
-- dépenses, codes promo, partenaires API.

CREATE OR REPLACE FUNCTION public.wipe_company_operations(p_company_id uuid, p_confirm_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_name text;
  v_deleted_colis integer;
  v_deleted_reservations integer;
  v_deleted_reservation_bus integer;
  v_deleted_bordereaux integer;
  v_deleted_mouvements integer;
  v_deleted_reversements integer;
  v_reset_caisses integer;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants — réservé au super administrateur';
  END IF;

  SELECT name INTO v_name FROM "Companies" WHERE id = p_company_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;
  IF btrim(COALESCE(p_confirm_name, '')) <> v_name THEN
    RAISE EXCEPTION 'Confirmation invalide : le nom fourni ne correspond pas à la compagnie';
  END IF;

  CREATE TEMP TABLE _wipe_gares ON COMMIT DROP AS
    SELECT id FROM "Gares" WHERE "companyId" = p_company_id;
  CREATE TEMP TABLE _wipe_trajets ON COMMIT DROP AS
    SELECT id FROM "ProgrammationTrajets"
    WHERE depart IN (SELECT id FROM _wipe_gares) OR final IN (SELECT id FROM _wipe_gares);
  CREATE TEMP TABLE _wipe_res ON COMMIT DROP AS
    SELECT id FROM "Reservations" WHERE "trajetId" IN (SELECT id FROM _wipe_trajets);
  CREATE TEMP TABLE _wipe_rb ON COMMIT DROP AS
    SELECT id FROM "ReservationBus" WHERE "reservationId" IN (SELECT id FROM _wipe_res);
  CREATE TEMP TABLE _wipe_caisses ON COMMIT DROP AS
    SELECT id FROM caisses_gares WHERE gare_id IN (SELECT id FROM _wipe_gares);

  DELETE FROM mouvements_caisse WHERE caisse_id IN (SELECT id FROM _wipe_caisses);
  GET DIAGNOSTICS v_deleted_mouvements = ROW_COUNT;
  DELETE FROM reversements_comptables WHERE caisse_id IN (SELECT id FROM _wipe_caisses);
  GET DIAGNOSTICS v_deleted_reversements = ROW_COUNT;

  DELETE FROM "ReservationBusColis" WHERE "reservationId" IN (SELECT id FROM _wipe_rb);
  DELETE FROM "ReservationBus" WHERE id IN (SELECT id FROM _wipe_rb);
  GET DIAGNOSTICS v_deleted_reservation_bus = ROW_COUNT;
  DELETE FROM "Reservations" WHERE id IN (SELECT id FROM _wipe_res);
  GET DIAGNOSTICS v_deleted_reservations = ROW_COUNT;

  DELETE FROM colis_autonomes WHERE company_id = p_company_id;
  GET DIAGNOSTICS v_deleted_colis = ROW_COUNT;

  DELETE FROM bordereaux_livraison WHERE company_id = p_company_id;
  GET DIAGNOSTICS v_deleted_bordereaux = ROW_COUNT;

  UPDATE caisses_gares
  SET solde_especes_actuel = 0,
      statut = 'cloturee',
      closed_at = now()
  WHERE id IN (SELECT id FROM _wipe_caisses);
  GET DIAGNOSTICS v_reset_caisses = ROW_COUNT;

  UPDATE colis_numerotation_gares SET last_seq = 0 WHERE gare_id IN (SELECT id FROM _wipe_gares);
  UPDATE bordereau_lot_numerotation SET next_seq = 0 WHERE gare_depart_id IN (SELECT id FROM _wipe_gares);
  UPDATE bordereau_numerotation SET last_seq = 0 WHERE company_id = p_company_id;

  RETURN jsonb_build_object(
    'companyId', p_company_id,
    'deletedColis', v_deleted_colis,
    'deletedReservations', v_deleted_reservations,
    'deletedReservationBus', v_deleted_reservation_bus,
    'deletedBordereaux', v_deleted_bordereaux,
    'deletedMouvementsCaisse', v_deleted_mouvements,
    'deletedReversements', v_deleted_reversements,
    'resetCaisses', v_reset_caisses
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.wipe_company_operations(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wipe_company_operations(uuid, text) TO authenticated;
