-- Colis retrait : résolution QR (UUID) ou référence imprimée CL-XXXXXXXX

CREATE OR REPLACE FUNCTION public.resolve_colis_retrait_code(p_code text)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw text := upper(trim(p_code));
  v_id uuid;
BEGIN
  IF v_raw IS NULL OR v_raw = '' THEN
    RETURN NULL;
  END IF;

  BEGIN
    v_id := v_raw::uuid;
    IF EXISTS (SELECT 1 FROM public.colis_autonomes WHERE id = v_id) THEN
      RETURN v_id;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation THEN
      NULL;
  END;

  v_raw := regexp_replace(v_raw, '^CL-?', '');
  IF length(v_raw) < 4 THEN
    RETURN NULL;
  END IF;

  SELECT ca.id
  INTO v_id
  FROM public.colis_autonomes ca
  WHERE upper(replace(ca.id::text, '-', '')) LIKE v_raw || '%'
  ORDER BY ca.created_at DESC
  LIMIT 1;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_colis_retrait_code(text) TO authenticated;

DROP FUNCTION IF EXISTS public.deliver_colis_autonome(uuid);

CREATE OR REPLACE FUNCTION public.deliver_colis_autonome(p_retrait_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_colis_id uuid;
  v_colis public.colis_autonomes%ROWTYPE;
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Connexion requise';
  END IF;

  v_colis_id := public.resolve_colis_retrait_code(p_retrait_code);
  IF v_colis_id IS NULL THEN
    RAISE EXCEPTION 'Code de retrait invalide';
  END IF;

  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = v_colis_id;
  IF v_colis.id IS NULL THEN
    RAISE EXCEPTION 'Code de retrait invalide';
  END IF;

  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF v_colis.statut_colis <> 'arrive' THEN
    RAISE EXCEPTION 'Colis non disponible (statut: %)', v_colis.statut_colis;
  END IF;

  v_result := public.update_colis_autonome_statut(v_colis.id, 'livre');
  RETURN v_result || jsonb_build_object(
    'nomDestinataire', v_colis.nom_destinataire,
    'nomExpediteur', v_colis.nom_expediteur
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deliver_colis_autonome(text) TO authenticated;
