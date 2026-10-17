-- 220 — Scan des reçus de ventes faites hors ligne
--
-- Le reçu imprimé hors ligne porte dans son QR l'identifiant local de la
-- vente (« local-<horodatage>-<8 hex> ») et, en clair, une référence
-- provisoire « <gare>-<8 hex> ». Après synchronisation, le scan et la saisie
-- manuelle ne les reconnaissaient pas : resolve_colis_retrait_code ne
-- cherchait que l'UUID, le numéro de reçu et la référence CL-.
-- Les deux formats sont maintenant retrouvés via offline_local_id
-- (migration 217). Le reste de la fonction est inchangé (migration 181).

CREATE OR REPLACE FUNCTION public.resolve_colis_retrait_code(p_code text)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw text := upper(trim(p_code));
  v_alnum text;
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

  -- Vente faite HORS LIGNE : le QR du reçu provisoire contient l'identifiant
  -- local de la vente (« local-<horodatage>-<8 hex> »), conservé après la
  -- synchronisation dans colis_autonomes.offline_local_id (migration 217).
  IF v_raw LIKE 'LOCAL-%' THEN
    SELECT ca.id INTO v_id
    FROM public.colis_autonomes ca
    WHERE ca.offline_local_id = lower(trim(p_code))
    LIMIT 1;
    RETURN v_id;
  END IF;

  -- Référence provisoire imprimée sur ce reçu (« COCO-4EC8D4EB ») : préfixe
  -- de la gare + les 8 derniers caractères de l'identifiant local.
  IF v_raw ~ '^[A-Z0-9]{1,8}-[0-9A-F]{8}$' AND v_raw NOT LIKE 'CL-%' THEN
    SELECT ca.id INTO v_id
    FROM public.colis_autonomes ca
    WHERE ca.offline_local_id LIKE 'local-%-' || lower(split_part(v_raw, '-', 2))
    ORDER BY ca.created_at DESC
    LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  END IF;

  v_alnum := regexp_replace(v_raw, '[^A-Z0-9]', '', 'g');

  -- Numéro de reçu par gare (ex. ABOI000001).
  SELECT ca.id INTO v_id
  FROM public.colis_autonomes ca
  WHERE upper(ca.numero_recu) = v_alnum
  LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  v_raw := regexp_replace(v_alnum, '^CL-?', '');
  IF length(v_raw) < 4 THEN
    RETURN NULL;
  END IF;

  SELECT ca.id
  INTO v_id
  FROM public.colis_autonomes ca
  WHERE upper(replace(ca.id::text, '-', '')) LIKE v_raw || '%'
  ORDER BY ca.created_at DESC
  LIMIT 1;

  IF v_id IS NULL AND length(v_raw) > 8 THEN
    SELECT ca.id
    INTO v_id
    FROM public.colis_autonomes ca
    WHERE upper(replace(ca.id::text, '-', '')) LIKE left(v_raw, 8) || '%'
    ORDER BY ca.created_at DESC
    LIMIT 1;
  END IF;

  RETURN v_id;
END;
$$;
