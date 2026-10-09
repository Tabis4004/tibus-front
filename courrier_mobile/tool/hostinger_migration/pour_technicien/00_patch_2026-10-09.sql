-- ============================================================================
-- Patch du 2026-10-09 : valeur des marchandises dans le détail d'un bordereau
-- (réglage owner « Valeur totale des marchandises » du rapport bordereau).
--
-- Ajoute uniquement la clé valeurMarchandise à get_bordereau_livraison, sans
-- toucher au reste de la fonction. Idempotent : sans risque à rejouer.
--
--   psql "$HOSTINGER_DB_URL" -f 00_patch_2026-10-09.sql
-- ============================================================================

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
