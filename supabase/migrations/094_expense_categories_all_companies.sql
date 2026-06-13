-- =============================================================================
-- Tibus 094 — Types de dépenses preset pour toutes les compagnies (SYSCOHADA)
-- =============================================================================

CREATE OR REPLACE FUNCTION public._seed_company_expense_categories(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preset record;
BEGIN
  IF p_company_id IS NULL THEN
    RETURN;
  END IF;

  FOR v_preset IN
    SELECT *
    FROM (
      VALUES
        (10,  'Carburant',                      '6047', 'Achats de carburants et lubrifiants', true),
        (20,  'Réparations',                    '6156', 'Entretien, réparations et maintenance', true),
        (30,  'Pièces détachées',              '6042', 'Achats de pièces et fournitures consommables', true),
        (40,  'Salaires équipe',                '6412', 'Salaires, appointements et commissions du personnel', true),
        (50,  'Électricité',                    '6052', 'Eau et électricité', true),
        (60,  'Communication',                  '6241', 'Frais de téléphone et communication', true),
        (70,  'Internet',                       '6248', 'Frais d''Internet', true),
        (80,  'Achat de matériel de bureau',    '6045', 'Achats de matériel et fournitures de bureau', true),
        (90,  'Marketing',                      '6228', 'Publicité, publications et relations publiques', true),
        (100, 'Abonnement TV',                  '6288', 'Abonnements et services (TV, médias)', true),
        (110, 'Transports interne',             '6135', 'Transports internes et déplacements exploitation', true)
    ) AS t(sort_order, name, ohada_code, ohada_label, is_preset)
  LOOP
    INSERT INTO "CompanyExpenseCategory" (
      "companyId",
      name,
      "ohadaAccountCode",
      "ohadaAccountLabel",
      "sortOrder",
      "isPreset"
    )
    VALUES (
      p_company_id,
      v_preset.name,
      v_preset.ohada_code,
      v_preset.ohada_label,
      v_preset.sort_order,
      v_preset.is_preset
    )
    ON CONFLICT ("companyId", name) DO NOTHING;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_company_expense_categories(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, false);
  PERFORM public._seed_company_expense_categories(p_company_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.seed_all_companies_expense_categories()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_count integer := 0;
BEGIN
  FOR v_company_id IN SELECT id FROM "Companies"
  LOOP
    PERFORM public._seed_company_expense_categories(v_company_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'companiesSeeded', v_count,
    'presetCount', 11
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_seed_company_expense_categories()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._seed_company_expense_categories(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS companies_seed_expense_categories ON "Companies";
CREATE TRIGGER companies_seed_expense_categories
  AFTER INSERT ON "Companies"
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_seed_company_expense_categories();

-- Seed toutes les compagnies déjà inscrites
SELECT public.seed_all_companies_expense_categories();

GRANT EXECUTE ON FUNCTION public.ensure_company_expense_categories(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seed_all_companies_expense_categories() TO authenticated;
