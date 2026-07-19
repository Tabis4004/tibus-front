-- Versionnage / filet de sécurité pour les suppressions destructives : ce
-- projet Supabase est sur le plan free (aucune sauvegarde automatique, pas
-- de Point-in-Time Recovery — vérifié via get_organization). En attendant
-- un éventuel plan payant, on capture un instantané JSON de chaque ligne
-- juste avant sa suppression par wipe_company_operations ou
-- cancel_colis_autonome, dans une table d'archive dédiée, restaurable par
-- le super admin.

CREATE TABLE public.operations_archive (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  record_id uuid NOT NULL,
  company_id uuid REFERENCES "Companies"(id) ON DELETE SET NULL,
  payload jsonb NOT NULL,
  deleted_via text NOT NULL,
  deleted_by uuid REFERENCES "Users"(id) ON DELETE SET NULL,
  deleted_at timestamptz NOT NULL DEFAULT now(),
  restored_at timestamptz,
  restored_by uuid REFERENCES "Users"(id) ON DELETE SET NULL
);

CREATE INDEX operations_archive_company_idx ON public.operations_archive (company_id, deleted_at DESC);
CREATE INDEX operations_archive_table_idx ON public.operations_archive (table_name, deleted_at DESC);

-- RLS activée, AUCUNE policy directe (même pattern que les tables de
-- compteurs internes) : ce sont des instantanés bruts de données d'autres
-- compagnies (noms, téléphones, montants...), consultables uniquement via
-- les RPC super_admin ci-dessous, jamais en lecture directe par l'API.
ALTER TABLE public.operations_archive ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.operations_archive FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- wipe_company_operations : archive chaque ligne avant de la supprimer.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wipe_company_operations(p_company_id uuid, p_confirm_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
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

  -- Mouvements de caisse
  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'mouvements_caisse', mc.id, p_company_id, to_jsonb(mc), 'wipe_company_operations', v_user_id
  FROM mouvements_caisse mc WHERE mc.caisse_id IN (SELECT id FROM _wipe_caisses);
  DELETE FROM mouvements_caisse WHERE caisse_id IN (SELECT id FROM _wipe_caisses);
  GET DIAGNOSTICS v_deleted_mouvements = ROW_COUNT;

  -- Reversements comptables
  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'reversements_comptables', rc.id, p_company_id, to_jsonb(rc), 'wipe_company_operations', v_user_id
  FROM reversements_comptables rc WHERE rc.caisse_id IN (SELECT id FROM _wipe_caisses);
  DELETE FROM reversements_comptables WHERE caisse_id IN (SELECT id FROM _wipe_caisses);
  GET DIAGNOSTICS v_deleted_reversements = ROW_COUNT;

  -- Bordereau_colis (lié aux colis ou aux bordereaux de la compagnie) —
  -- archivé explicitement avant que les CASCADE de colis_autonomes /
  -- bordereaux_livraison ne les suppriment silencieusement.
  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'bordereau_colis', bc.id, p_company_id, to_jsonb(bc), 'wipe_company_operations', v_user_id
  FROM bordereau_colis bc
  WHERE bc.colis_id IN (SELECT id FROM colis_autonomes WHERE company_id = p_company_id)
     OR bc.bordereau_id IN (SELECT id FROM bordereaux_livraison WHERE company_id = p_company_id);

  -- Billets guichet
  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'ReservationBusColis', rbc.id, p_company_id, to_jsonb(rbc), 'wipe_company_operations', v_user_id
  FROM "ReservationBusColis" rbc WHERE rbc."reservationId" IN (SELECT id FROM _wipe_rb);
  DELETE FROM "ReservationBusColis" WHERE "reservationId" IN (SELECT id FROM _wipe_rb);

  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'ReservationBus', rb.id, p_company_id, to_jsonb(rb), 'wipe_company_operations', v_user_id
  FROM "ReservationBus" rb WHERE rb.id IN (SELECT id FROM _wipe_rb);
  DELETE FROM "ReservationBus" WHERE id IN (SELECT id FROM _wipe_rb);
  GET DIAGNOSTICS v_deleted_reservation_bus = ROW_COUNT;

  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'Reservations', r.id, p_company_id, to_jsonb(r), 'wipe_company_operations', v_user_id
  FROM "Reservations" r WHERE r.id IN (SELECT id FROM _wipe_res);
  DELETE FROM "Reservations" WHERE id IN (SELECT id FROM _wipe_res);
  GET DIAGNOSTICS v_deleted_reservations = ROW_COUNT;

  -- Colis autonomes
  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'colis_autonomes', ca.id, p_company_id, to_jsonb(ca), 'wipe_company_operations', v_user_id
  FROM colis_autonomes ca WHERE ca.company_id = p_company_id;
  DELETE FROM colis_autonomes WHERE company_id = p_company_id;
  GET DIAGNOSTICS v_deleted_colis = ROW_COUNT;

  -- Bordereaux / manifests
  INSERT INTO operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'bordereaux_livraison', bl.id, p_company_id, to_jsonb(bl), 'wipe_company_operations', v_user_id
  FROM bordereaux_livraison bl WHERE bl.company_id = p_company_id;
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

-- ---------------------------------------------------------------------------
-- cancel_colis_autonome : archive la ligne bordereau_colis retirée du lot.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_colis_autonome(p_colis_id uuid, p_motif text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_colis record;
  v_mov record;
  v_cash_reversed boolean := false;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;

  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id FOR UPDATE;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;

  IF NOT (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND ur."companyId" = v_colis.company_id
        AND r.name IN ('owner', 'comptable_compagnie')
    )
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants — seul le promoteur (ou comptable) peut annuler un colis';
  END IF;

  IF v_colis.statut_colis = 'annule' THEN
    RAISE EXCEPTION 'Ce colis est déjà annulé';
  END IF;
  IF v_colis.statut_colis = 'livre' THEN
    RAISE EXCEPTION 'Impossible d''annuler un colis déjà livré au destinataire';
  END IF;

  UPDATE public.colis_autonomes
  SET statut_colis = 'annule',
      annule_par = v_user_id,
      annule_at = now(),
      motif_annulation = NULLIF(trim(p_motif), ''),
      updated_at = now()
  WHERE id = p_colis_id;

  INSERT INTO public.operations_archive (table_name, record_id, company_id, payload, deleted_via, deleted_by)
  SELECT 'bordereau_colis', bc.id, v_colis.company_id, to_jsonb(bc), 'cancel_colis_autonome', v_user_id
  FROM public.bordereau_colis bc WHERE bc.colis_id = p_colis_id;
  DELETE FROM public.bordereau_colis WHERE colis_id = p_colis_id;

  SELECT mc.*, cg.statut AS caisse_statut
  INTO v_mov
  FROM public.mouvements_caisse mc
  JOIN public.caisses_gares cg ON cg.id = mc.caisse_id
  WHERE mc.colis_autonome_id = p_colis_id
    AND mc.type_mouvement = 'encaissement_colis'
  ORDER BY mc.created_at ASC
  LIMIT 1;

  IF v_mov.id IS NOT NULL AND v_mov.caisse_statut = 'ouverte' THEN
    PERFORM public.record_station_cash_movement(
      p_caisse_id => v_mov.caisse_id,
      p_type_mouvement => 'decaissement_annulation',
      p_montant => v_mov.montant,
      p_colis_autonome_id => p_colis_id,
      p_effectue_par => v_user_id,
      p_direction => 'out',
      p_note => COALESCE('Annulation colis ' || v_colis.numero_recu, 'Annulation colis')
    );
    v_cash_reversed := true;
  END IF;

  RETURN jsonb_build_object(
    'id', p_colis_id,
    'statutColis', 'annule',
    'cashReversed', v_cash_reversed
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.wipe_company_operations(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_colis_autonome(uuid, text) TO authenticated;
