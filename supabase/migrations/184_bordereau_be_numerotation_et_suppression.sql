-- Bordereaux d'emballage : demandes promoteur.
-- 1. Référence simple et croissante BE-0000001 (par compagnie), attribuée
--    par trigger — remplace BL-XXXXXXXX aléatoire.
-- 2. Suppression possible d'un bordereau encore OUVERT (RPC) + purge des
--    bordereaux ouverts de test existants.
-- 3. Unicité de la référence par compagnie (deux compagnies peuvent avoir
--    chacune leur BE-0000001).
-- APPLIQUÉE EN PRODUCTION (apply_migration bordereau_be_numerotation_et_suppression).

ALTER TABLE public.bordereaux_livraison
  DROP CONSTRAINT IF EXISTS bordereaux_livraison_reference_key;
CREATE UNIQUE INDEX IF NOT EXISTS bordereaux_livraison_company_reference_key
  ON public.bordereaux_livraison (company_id, reference);

CREATE TABLE IF NOT EXISTS public.bordereau_numerotation (
  company_id uuid PRIMARY KEY REFERENCES public."Companies"(id) ON DELETE CASCADE,
  last_seq integer NOT NULL DEFAULT 0
);
ALTER TABLE public.bordereau_numerotation ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.assign_bordereau_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_seq integer;
BEGIN
  -- Écrase systématiquement la référence générée par create_bordereau_livraison
  -- (BL-aléatoire) par la séquence simple BE-0000001 par compagnie.
  INSERT INTO bordereau_numerotation (company_id, last_seq)
  VALUES (NEW.company_id, 1)
  ON CONFLICT (company_id) DO UPDATE SET last_seq = bordereau_numerotation.last_seq + 1
  RETURNING last_seq INTO v_seq;
  NEW.reference := 'BE-' || lpad(v_seq::text, 7, '0');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bordereau_reference_trg ON public.bordereaux_livraison;
CREATE TRIGGER bordereau_reference_trg
BEFORE INSERT ON public.bordereaux_livraison
FOR EACH ROW EXECUTE FUNCTION public.assign_bordereau_reference();

-- Purge des bordereaux OUVERTS existants (données de test) — les liaisons
-- bordereau_colis suivent en cascade, les colis gardent leur statut.
DELETE FROM public.bordereaux_livraison WHERE statut = 'ouvert';

-- Renumérotation des bordereaux restants (clos), par compagnie et ordre
-- chronologique, puis alignement des compteurs.
WITH ranked AS (
  SELECT id, company_id,
         row_number() OVER (PARTITION BY company_id ORDER BY created_at, id) AS rn
  FROM public.bordereaux_livraison
)
UPDATE public.bordereaux_livraison b
SET reference = 'BE-' || lpad(r.rn::text, 7, '0')
FROM ranked r WHERE r.id = b.id;

INSERT INTO public.bordereau_numerotation (company_id, last_seq)
SELECT company_id, count(*) FROM public.bordereaux_livraison GROUP BY company_id
ON CONFLICT (company_id) DO UPDATE
SET last_seq = GREATEST(bordereau_numerotation.last_seq, EXCLUDED.last_seq);

-- Suppression d'un bordereau encore ouvert (préenregistré) — les colis déjà
-- passés « chargé » via ce bordereau conservent leur statut.
CREATE OR REPLACE FUNCTION public.delete_bordereau_livraison(p_bordereau_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_bordereau_access(v_bl.company_id);
  IF v_bl.statut <> 'ouvert' THEN
    RAISE EXCEPTION 'Seul un bordereau encore ouvert peut etre supprime';
  END IF;
  DELETE FROM bordereaux_livraison WHERE id = p_bordereau_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.delete_bordereau_livraison(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_bordereau_livraison(uuid) TO authenticated;
