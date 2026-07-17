-- Résolution du code de retrait colis plus tolérante à la saisie manuelle.
-- La référence publique fait exactement 8 caractères (CL-XXXXXXXX) mais les
-- agents saisissent parfois un caractère de trop (ex. « 7B77A76D6 ») : la
-- recherche par préfixe strict ne trouvait alors rien. On retente désormais
-- avec les 8 premiers caractères quand la saisie est plus longue.

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
  -- Espaces/tirets internes éventuels recopiés depuis un SMS ou un reçu.
  v_raw := regexp_replace(v_raw, '[^A-Z0-9]', '', 'g');
  IF length(v_raw) < 4 THEN
    RETURN NULL;
  END IF;

  SELECT ca.id
  INTO v_id
  FROM public.colis_autonomes ca
  WHERE upper(replace(ca.id::text, '-', '')) LIKE v_raw || '%'
  ORDER BY ca.created_at DESC
  LIMIT 1;

  -- Saisie plus longue que la référence publique (8 caractères) : on
  -- retombe sur les 8 premiers caractères avant d'abandonner.
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
