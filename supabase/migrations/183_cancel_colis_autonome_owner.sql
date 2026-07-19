-- Permet au owner (ou comptable_compagnie / super_admin) d'annuler un
-- enregistrement de colis (« annuler une vente ») directement depuis la
-- console owner — ex. erreurs de saisie, doublons, données de formation.
--
-- - Nouveau statut 'annule' ajouté à colis_autonomes.statut_colis.
-- - Impossible d'annuler un colis déjà 'annule' ou déjà 'livre' (transaction
--   soldée avec le destinataire).
-- - Retire le colis de tout bordereau/lot (bordereau_colis) auquel il
--   appartiendrait encore, quel que soit le statut du lot.
-- - Contre-passe l'encaissement (mouvements_caisse, type encaissement_colis)
--   UNIQUEMENT si la caisse concernée est encore ouverte (via
--   record_station_cash_movement, qui gère solde et verrouillage). Si la
--   caisse est déjà clôturée, son solde a déjà été remis à zéro (migration
--   182) : on laisse l'historique tel quel, seule la fiche colis passe en
--   'annule' (traçabilité comptable non ré-ouverte).

ALTER TABLE public.colis_autonomes
  DROP CONSTRAINT IF EXISTS colis_autonomes_statut_check;

ALTER TABLE public.colis_autonomes
  ADD CONSTRAINT colis_autonomes_statut_check
  CHECK (statut_colis = ANY (ARRAY['enregistre'::text, 'charge'::text, 'arrive'::text, 'livre'::text, 'annule'::text]));

ALTER TABLE public.colis_autonomes
  ADD COLUMN IF NOT EXISTS annule_par uuid REFERENCES "Users"(id),
  ADD COLUMN IF NOT EXISTS annule_at timestamptz,
  ADD COLUMN IF NOT EXISTS motif_annulation text;

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

GRANT EXECUTE ON FUNCTION public.cancel_colis_autonome(uuid, text) TO authenticated;
