-- 224 — Dépense imputée à une gare seule (bus facultatif)
--
-- Les compagnies de courrier n'ont pas toujours de bus : une dépense peut
-- désormais être rattachée à une gare seule (ou à un membre de l'équipe,
-- comme avant). Modification ciblée de upsert_company_expense.
DO $mig$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.upsert_company_expense(uuid,uuid,uuid,double precision,date,text,uuid,uuid,uuid)'::regprocedure);
  IF position('Imputation requise: membre equipe OU gare' IN v_def) = 0 THEN
    IF position('IF v_team IS NULL AND (v_bus IS NULL OR v_gare IS NULL) THEN' IN v_def) = 0
       OR position('IF NOT EXISTS (
      SELECT 1 FROM "Bus" b' IN v_def) = 0 THEN
      RAISE EXCEPTION 'upsert_company_expense : motif introuvable, migration a adapter';
    END IF;
    v_def := replace(v_def,
      'IF v_team IS NULL AND (v_bus IS NULL OR v_gare IS NULL) THEN
    RAISE EXCEPTION ''Imputation requise: membre equipe OU bus+gare'';',
      'IF v_team IS NULL AND v_gare IS NULL THEN
    RAISE EXCEPTION ''Imputation requise: membre equipe OU gare'';');
    v_def := replace(v_def,
      'IF NOT EXISTS (
      SELECT 1 FROM "Bus" b',
      'IF v_bus IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM "Bus" b');
    EXECUTE v_def;
  END IF;
END
$mig$;

-- Même règle dans la contrainte de la table (gare obligatoire, bus facultatif).
ALTER TABLE public."CompanyExpense" DROP CONSTRAINT IF EXISTS company_expense_imputation_xor;
ALTER TABLE public."CompanyExpense" ADD CONSTRAINT company_expense_imputation_xor CHECK (
  ("teamMemberUserId" IS NOT NULL AND "busId" IS NULL AND "gareId" IS NULL)
  OR ("teamMemberUserId" IS NULL AND "gareId" IS NOT NULL)
);
