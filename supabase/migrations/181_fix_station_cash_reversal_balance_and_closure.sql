-- Corrige le cycle soumission/validation des reversements de caisse guichet :
-- la soumission (submit_station_cash_reversal) retirait déjà le blocage des
-- ventes, mais la version précédente déplaçait aussi le RETRAIT du montant
-- (record_station_cash_movement) à la VALIDATION plutôt qu'à la soumission,
-- et avait retiré la clôture de caisse à la validation. Deux problèmes :
-- 1) "Solde caisse insuffisant" à la validation : le solde avait changé
--    (ventes/décaissements) entre soumission et validation, donc le retrait
--    tardif pouvait dépasser le solde courant.
-- 2) Aucune clôture n'intervenait plus jamais : impossible d'ouvrir une
--    nouvelle session pour ce vendeur/cette gare.
--
-- Nouveau cycle voulu (demande explicite) :
-- - submit_station_cash_reversal : retire le montant de la caisse
--   IMMÉDIATEMENT (le vendeur continue de vendre avec le solde restant),
--   caisse reste 'ouverte'.
-- - validate_station_cash_reversal : ne touche plus au solde (déjà fait),
--   confirme la réception physique des espèces et CLÔTURE la caisse a
--   posteriori (traçabilité comptable) — ce qui libère la gare/le vendeur
--   pour l'ouverture d'une nouvelle session.
--
-- APPLIQUÉE EN PRODUCTION (apply_migration fix_station_cash_reversal_balance_and_closure).
-- Numérotée 181 (et non 180) : collision de numéro avec
-- 180_colis_numero_recu_par_gare.sql, appliquée en parallèle.

CREATE OR REPLACE FUNCTION public.submit_station_cash_reversal(p_caisse_id uuid, p_montant_reverse integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_caisse record;
  v_id uuid;
  v_montant integer;
  v_movement_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  v_montant := COALESCE(p_montant_reverse, 0);
  IF v_montant <= 0 THEN RAISE EXCEPTION 'Montant reversement invalide'; END IF;

  SELECT * INTO v_caisse FROM caisses_gares WHERE id = p_caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;

  IF v_caisse.gestionnaire_id <> v_user_id AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Reversement reserve au vendeur de la session';
  END IF;

  IF v_caisse.statut NOT IN ('ouverte', 'en_reversement') THEN
    RAISE EXCEPTION 'Session deja cloturee';
  END IF;

  INSERT INTO reversements_comptables (caisse_id, montant_reverse, statut_validation, soumis_par)
  VALUES (p_caisse_id, v_montant, 'en_attente', v_user_id)
  RETURNING id INTO v_id;

  -- Retrait immédiat du montant remis — voir commentaire en tête de fichier.
  v_movement_id := public.record_station_cash_movement(
    v_caisse.id,
    'reversement_comptable',
    v_montant,
    NULL,
    NULL,
    v_user_id,
    v_id,
    'Reversement soumis par le vendeur',
    'out'
  );

  RETURN jsonb_build_object(
    'id', v_id,
    'caisseId', p_caisse_id,
    'amount', v_montant,
    'status', 'en_attente',
    'movementId', v_movement_id,
    'currentBalance', (SELECT solde_especes_actuel FROM public.caisses_gares WHERE id = p_caisse_id)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.validate_station_cash_reversal(p_reversement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_rev record;
  v_caisse record;
  v_company_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_rev
  FROM public.reversements_comptables
  WHERE id = p_reversement_id
  FOR UPDATE;

  IF v_rev.id IS NULL THEN RAISE EXCEPTION 'Reversement introuvable'; END IF;
  IF v_rev.statut_validation <> 'en_attente' THEN RAISE EXCEPTION 'Reversement deja traite'; END IF;

  SELECT * INTO v_caisse
  FROM public.caisses_gares
  WHERE id = v_rev.caisse_id
  FOR UPDATE;

  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;

  v_company_id := public.station_cash_gare_company_id(v_caisse.gare_id);

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR public.has_gare_role(
      v_caisse.gare_id,
      ARRAY['comptable_gare', 'gerant_gare', 'gestionnaire_gare']
    )
  ) THEN
    RAISE EXCEPTION 'Validation reservee au comptable ou owner';
  END IF;

  -- Le montant a déjà été retiré de la caisse à la soumission (voir
  -- submit_station_cash_reversal) : plus aucun mouvement de caisse ici.
  UPDATE public.reversements_comptables
  SET
    statut_validation = 'approuve_recu',
    comptable_id = v_user_id,
    validated_at = now()
  WHERE id = p_reversement_id;

  -- Clôture a posteriori (traçabilité comptable) — libère la gare/le
  -- vendeur pour une nouvelle ouverture. Idempotent : si la caisse a déjà
  -- été close autrement (ex. close_station_cash_register par le vendeur
  -- avant la validation), on ne touche pas à statut/closed_at.
  IF v_caisse.statut = 'ouverte' THEN
    UPDATE public.caisses_gares
    SET statut = 'cloturee', closed_at = now()
    WHERE id = v_caisse.id;
  END IF;

  RETURN jsonb_build_object(
    'id', p_reversement_id,
    'status', 'approuve_recu',
    'caisseStatus', 'cloturee',
    'balanceAfter', (SELECT solde_especes_actuel FROM public.caisses_gares WHERE id = v_caisse.id)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.submit_station_cash_reversal(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_station_cash_reversal(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
