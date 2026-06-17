-- Migration 135 a ajoute p_colis_autonome_id via CREATE OR REPLACE sur une nouvelle signature,
-- ce qui laisse deux surcharges. Les ventes guichet echouent avec « function is not unique ».

DROP FUNCTION IF EXISTS public.record_station_cash_movement(
  uuid,
  text,
  integer,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text
);

CREATE OR REPLACE FUNCTION public.record_station_cash_movement(
  p_caisse_id uuid,
  p_type_mouvement text,
  p_montant integer,
  p_ticket_id uuid DEFAULT NULL::uuid,
  p_colis_id uuid DEFAULT NULL::uuid,
  p_effectue_par uuid DEFAULT NULL::uuid,
  p_reversement_id uuid DEFAULT NULL::uuid,
  p_note text DEFAULT NULL::text,
  p_direction text DEFAULT 'in'::text,
  p_colis_autonome_id uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caisse record;
  v_user_id uuid;
  v_delta integer;
  v_new_balance integer;
  v_movement_id uuid;
BEGIN
  IF COALESCE(p_montant, 0) <= 0 THEN RAISE EXCEPTION 'Montant mouvement invalide'; END IF;
  v_user_id := COALESCE(p_effectue_par, public.current_app_user_id());
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_caisse FROM caisses_gares WHERE id = p_caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  IF v_caisse.statut <> 'ouverte' AND p_type_mouvement <> 'reversement_comptable' THEN
    RAISE EXCEPTION 'Caisse cloturee';
  END IF;

  v_delta := CASE WHEN p_direction = 'out' THEN -p_montant ELSE p_montant END;
  v_new_balance := v_caisse.solde_especes_actuel + v_delta;
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Solde caisse insuffisant (solde: %, mouvement: %)', v_caisse.solde_especes_actuel, v_delta;
  END IF;

  UPDATE caisses_gares SET solde_especes_actuel = v_new_balance WHERE id = p_caisse_id;

  INSERT INTO mouvements_caisse (
    caisse_id, type_mouvement, montant, solde_apres,
    ticket_id, colis_id, colis_autonome_id, effectue_par, reversement_id, note
  ) VALUES (
    p_caisse_id, p_type_mouvement, p_montant, v_new_balance,
    p_ticket_id, p_colis_id, p_colis_autonome_id, v_user_id, p_reversement_id, NULLIF(trim(p_note), '')
  ) RETURNING id INTO v_movement_id;

  RETURN v_movement_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_counter_sale_cash_movements(
  p_caisse_id uuid,
  p_booking_id uuid,
  p_ticket_amount integer,
  p_parcel_amount integer,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(p_ticket_amount, 0) > 0 THEN
    PERFORM public.record_station_cash_movement(
      p_caisse_id => p_caisse_id,
      p_type_mouvement => 'encaissement_billet',
      p_montant => p_ticket_amount,
      p_ticket_id => p_booking_id,
      p_effectue_par => p_user_id,
      p_direction => 'in'
    );
  END IF;
  IF COALESCE(p_parcel_amount, 0) > 0 THEN
    PERFORM public.record_station_cash_movement(
      p_caisse_id => p_caisse_id,
      p_type_mouvement => 'encaissement_colis',
      p_montant => p_parcel_amount,
      p_ticket_id => p_booking_id,
      p_colis_id => p_booking_id,
      p_effectue_par => p_user_id,
      p_direction => 'in'
    );
  END IF;
END;
$$;
