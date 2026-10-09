-- 218 — get_bordereau_livraison renvoie aussi la valeur déclarée de chaque
-- colis (valeurMarchandise), pour le réglage owner « Valeur totale des
-- marchandises » du rapport bordereau (hiddenFields 'valeurTotal'), affiché
-- à l'identique sur le web et le mobile.
--
-- Ajout chirurgical (le reste de la fonction est inchangé, quelle que soit
-- sa version sur la base cible) : insère la clé juste après montantFret.
-- Idempotent : sans effet si la clé est déjà présente.
DO $mig$
DECLARE
  v_def text := pg_get_functiondef('public.get_bordereau_livraison'::regproc);
BEGIN
  IF position('valeurMarchandise' IN v_def) = 0 THEN
    IF position('''montantFret'', ca.montant_fret,' IN v_def) = 0 THEN
      RAISE EXCEPTION 'get_bordereau_livraison : motif montantFret introuvable, migration à adapter';
    END IF;
    EXECUTE replace(
      v_def,
      '''montantFret'', ca.montant_fret,',
      '''montantFret'', ca.montant_fret,' || chr(10) || '    ''valeurMarchandise'', ca.valeur_marchandise,'
    );
  END IF;
END
$mig$;
