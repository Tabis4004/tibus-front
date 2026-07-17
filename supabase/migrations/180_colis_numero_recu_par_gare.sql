-- Numérotation des reçus colis : 4 premiers caractères du nom de la gare de
-- départ + numéro d'ordre sur 6 chiffres (ex. 1er colis d'Aboisso →
-- ABOI000001). Attribué par TRIGGER à l'insertion (couvre toutes les
-- surcharges de register_colis_autonome et tout chemin futur), compteur
-- atomique par gare, backfill des colis existants par ordre chronologique.
-- APPLIQUÉE EN PRODUCTION (apply_migration colis_numero_recu_par_gare).

ALTER TABLE public.colis_autonomes ADD COLUMN IF NOT EXISTS numero_recu text;
CREATE INDEX IF NOT EXISTS colis_autonomes_numero_recu_idx
  ON public.colis_autonomes (numero_recu);

CREATE TABLE IF NOT EXISTS public.colis_numerotation_gares (
  gare_id uuid PRIMARY KEY REFERENCES public."Gares"(id) ON DELETE CASCADE,
  last_seq integer NOT NULL DEFAULT 0
);
ALTER TABLE public.colis_numerotation_gares ENABLE ROW LEVEL SECURITY;

-- Préfixe = 4 premiers caractères alphanumériques du nom de gare, majuscules
-- sans accents ('Aboisso' → ABOI). 'GARE' si le nom ne donne rien.
CREATE OR REPLACE FUNCTION public.colis_gare_prefix(p_gare_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_prefix text;
BEGIN
  SELECT left(regexp_replace(
    upper(translate(coalesce(g.name, ''),
      'ÀÂÄÁÃÉÈÊËÍÎÏÓÔÖÕÚÙÛÜÇÑàâäáãéèêëíîïóôöõúùûüçñ',
      'AAAAAEEEEIIIOOOOUUUUCNaaaaaeeeeiiioooouuuucn')),
    '[^A-Z0-9]', '', 'g'), 4)
  INTO v_prefix
  FROM "Gares" g WHERE g.id = p_gare_id;
  RETURN COALESCE(NULLIF(v_prefix, ''), 'GARE');
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_colis_numero_recu()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_seq integer;
BEGIN
  IF NEW.numero_recu IS NOT NULL THEN RETURN NEW; END IF;
  -- Upsert atomique : le verrou de ligne sérialise les insertions
  -- concurrentes d'une même gare.
  INSERT INTO colis_numerotation_gares (gare_id, last_seq)
  VALUES (NEW.gare_depart_id, 1)
  ON CONFLICT (gare_id) DO UPDATE SET last_seq = colis_numerotation_gares.last_seq + 1
  RETURNING last_seq INTO v_seq;
  NEW.numero_recu := public.colis_gare_prefix(NEW.gare_depart_id) || lpad(v_seq::text, 6, '0');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS colis_numero_recu_trg ON public.colis_autonomes;
CREATE TRIGGER colis_numero_recu_trg
BEFORE INSERT ON public.colis_autonomes
FOR EACH ROW EXECUTE FUNCTION public.assign_colis_numero_recu();

-- Backfill des colis existants, par gare et ordre chronologique.
WITH ranked AS (
  SELECT id, gare_depart_id,
         row_number() OVER (PARTITION BY gare_depart_id ORDER BY created_at, id) AS rn
  FROM public.colis_autonomes
  WHERE numero_recu IS NULL
)
UPDATE public.colis_autonomes ca
SET numero_recu = public.colis_gare_prefix(r.gare_depart_id) || lpad(r.rn::text, 6, '0')
FROM ranked r WHERE r.id = ca.id;

INSERT INTO public.colis_numerotation_gares (gare_id, last_seq)
SELECT gare_depart_id, count(*) FROM public.colis_autonomes GROUP BY gare_depart_id
ON CONFLICT (gare_id) DO UPDATE
SET last_seq = GREATEST(colis_numerotation_gares.last_seq, EXCLUDED.last_seq);
