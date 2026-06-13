-- Tibus 092 — Company expenses (OHADA) + compte de résultat
-- Tables: CompanyExpenseCategory, CompanyExpense
-- RPCs: categories CRUD, expenses CRUD, get_company_income_statement (SYSCOHADA)

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "CompanyExpenseCategory" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES "Companies"(id) ON DELETE CASCADE,
  name text NOT NULL,
  "ohadaAccountCode" text NOT NULL,
  "ohadaAccountLabel" text NOT NULL,
  "sortOrder" integer NOT NULL DEFAULT 0,
  "isPreset" boolean NOT NULL DEFAULT false,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT company_expense_category_company_name_unique UNIQUE ("companyId", name)
);

CREATE INDEX IF NOT EXISTS company_expense_category_company_idx
  ON "CompanyExpenseCategory" ("companyId", "sortOrder", name);

CREATE TABLE IF NOT EXISTS "CompanyExpense" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES "Companies"(id) ON DELETE CASCADE,
  "categoryId" uuid NOT NULL REFERENCES "CompanyExpenseCategory"(id) ON DELETE RESTRICT,
  amount double precision NOT NULL CHECK (amount > 0),
  currency text NOT NULL DEFAULT 'XOF',
  "expenseDate" date NOT NULL,
  description text,
  "teamMemberUserId" uuid REFERENCES "Users"(id) ON DELETE SET NULL,
  "busId" uuid REFERENCES "Bus"(id) ON DELETE SET NULL,
  "gareId" uuid REFERENCES "Gares"(id) ON DELETE SET NULL,
  "createdByUserId" uuid REFERENCES "Users"(id) ON DELETE SET NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT company_expense_imputation_xor CHECK (
    (
      "teamMemberUserId" IS NOT NULL
      AND "busId" IS NULL
      AND "gareId" IS NULL
    )
    OR (
      "teamMemberUserId" IS NULL
      AND "busId" IS NOT NULL
      AND "gareId" IS NOT NULL
    )
  )
);

CREATE INDEX IF NOT EXISTS company_expense_company_date_idx
  ON "CompanyExpense" ("companyId", "expenseDate" DESC);

CREATE INDEX IF NOT EXISTS company_expense_category_idx
  ON "CompanyExpense" ("categoryId");

CREATE OR REPLACE FUNCTION public.tg_company_expense_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW."updatedAt" := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS company_expense_category_touch_updated_at ON "CompanyExpenseCategory";
CREATE TRIGGER company_expense_category_touch_updated_at
  BEFORE UPDATE ON "CompanyExpenseCategory"
  FOR EACH ROW EXECUTE FUNCTION public.tg_company_expense_touch_updated_at();

DROP TRIGGER IF EXISTS company_expense_touch_updated_at ON "CompanyExpense";
CREATE TRIGGER company_expense_touch_updated_at
  BEFORE UPDATE ON "CompanyExpense"
  FOR EACH ROW EXECUTE FUNCTION public.tg_company_expense_touch_updated_at();

ALTER TABLE "CompanyExpenseCategory" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "CompanyExpense" ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Access helper
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assert_company_expense_access(
  p_company_id uuid,
  p_write boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM "Companies" c WHERE c.id = p_company_id) THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF p_write THEN
    IF NOT (
      public.is_super_admin()
      OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    ) THEN
      RAISE EXCEPTION 'Acces ecriture depenses refuse';
    END IF;
  ELSE
    IF NOT (
      public.is_super_admin()
      OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
      OR public.has_company_droit(p_company_id, 'view_reports')
    ) THEN
      RAISE EXCEPTION 'Acces lecture depenses refuse';
    END IF;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Preset categories (SYSCOHADA)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_company_expense_categories(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preset record;
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, false);

  FOR v_preset IN
    SELECT *
    FROM (
      VALUES
        (1,  'Carburant',            '6047', 'Achats de carburants et lubrifiants', true),
        (2,  'Réparations',          '6156', 'Entretien, réparations et maintenance', true),
        (3,  'Pièces détachées',    '6042', 'Achats de matières et fournitures consommables', true),
        (4,  'Salaires équipe',      '6412', 'Appointements, salaires et commissions du personnel', true),
        (5,  'Électricité',          '6052', 'Eau et électricité', true),
        (6,  'Communication',        '6226', 'Frais de télécommunications', true),
        (7,  'Internet',             '6226', 'Frais de télécommunications (internet)', true),
        (8,  'Matériel de bureau',   '6045', 'Achats de matériel, équipements et travaux', true),
        (9,  'Marketing',            '6228', 'Frais de publicité, publications et relations publiques', true),
        (10, 'Abonnement TV',        '6288', 'Autres charges externes diverses (abonnements)', true)
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

-- ---------------------------------------------------------------------------
-- Categories RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.list_company_expense_categories(p_company_id uuid)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.ensure_company_expense_categories(p_company_id);

  RETURN QUERY
  SELECT jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'ohadaAccountCode', c."ohadaAccountCode",
    'ohadaAccountLabel', c."ohadaAccountLabel",
    'sortOrder', c."sortOrder",
    'isPreset', c."isPreset"
  )
  FROM "CompanyExpenseCategory" c
  WHERE c."companyId" = p_company_id
  ORDER BY c."sortOrder", c.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_company_expense_category(
  p_company_id uuid,
  p_id uuid DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_ohada_account_code text DEFAULT '622',
  p_ohada_account_label text DEFAULT 'Services extérieurs'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_name text := NULLIF(btrim(p_name), '');
  v_code text := NULLIF(btrim(p_ohada_account_code), '');
  v_label text := NULLIF(btrim(p_ohada_account_label), '');
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, true);

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Nom de categorie requis';
  END IF;
  IF v_code IS NULL THEN
    v_code := '622';
  END IF;
  IF v_label IS NULL THEN
    v_label := 'Services extérieurs';
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE "CompanyExpenseCategory" c
    SET
      name = v_name,
      "ohadaAccountCode" = v_code,
      "ohadaAccountLabel" = v_label
    WHERE c.id = p_id
      AND c."companyId" = p_company_id
    RETURNING c.id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Categorie introuvable';
    END IF;
  ELSE
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
      v_name,
      v_code,
      v_label,
      COALESCE((SELECT MAX("sortOrder") + 1 FROM "CompanyExpenseCategory" WHERE "companyId" = p_company_id), 100),
      false
    )
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_company_expense_category(
  p_company_id uuid,
  p_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, true);

  IF EXISTS (
    SELECT 1 FROM "CompanyExpense" e
    WHERE e."categoryId" = p_id
      AND e."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Impossible de supprimer: des depenses utilisent cette categorie';
  END IF;

  DELETE FROM "CompanyExpenseCategory" c
  WHERE c.id = p_id
    AND c."companyId" = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Categorie introuvable';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Expenses RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._company_expense_team_member_valid(
  p_company_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."companyId" = p_company_id
      AND ur."userId" = p_user_id
      AND r.name IN (
        'owner',
        'comptable_compagnie',
        'controleur',
        'vendeur',
        'gestionnaire_gare'
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.list_company_expenses(
  p_company_id uuid,
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, false);

  RETURN QUERY
  SELECT jsonb_build_object(
    'id', e.id,
    'categoryId', e."categoryId",
    'categoryName', c.name,
    'ohadaAccountCode', c."ohadaAccountCode",
    'amount', e.amount,
    'currency', e.currency,
    'expenseDate', e."expenseDate",
    'description', e.description,
    'teamMemberUserId', e."teamMemberUserId",
    'teamMemberName', CASE
      WHEN u.id IS NULL THEN NULL
      ELSE NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')
    END,
    'busId', e."busId",
    'busLabel', CASE
      WHEN b.id IS NULL THEN NULL
      ELSE NULLIF(TRIM(COALESCE(b."registrationNumber", '') || ' ' || COALESCE(b.model, '')), '')
    END,
    'gareId', e."gareId",
    'gareName', g.name,
    'createdAt', e."createdAt"
  )
  FROM "CompanyExpense" e
  JOIN "CompanyExpenseCategory" c ON c.id = e."categoryId"
  LEFT JOIN "Users" u ON u.id = e."teamMemberUserId"
  LEFT JOIN "Bus" b ON b.id = e."busId"
  LEFT JOIN "Gares" g ON g.id = e."gareId"
  WHERE e."companyId" = p_company_id
    AND (p_from IS NULL OR e."expenseDate" >= p_from)
    AND (p_to IS NULL OR e."expenseDate" <= p_to)
  ORDER BY e."expenseDate" DESC, e."createdAt" DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_company_expense(
  p_company_id uuid,
  p_id uuid DEFAULT NULL,
  p_category_id uuid DEFAULT NULL,
  p_amount double precision DEFAULT NULL,
  p_expense_date date DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_team_member_user_id uuid DEFAULT NULL,
  p_bus_id uuid DEFAULT NULL,
  p_gare_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_user_id uuid := public.current_app_user_id();
  v_currency text := 'XOF';
  v_team uuid := p_team_member_user_id;
  v_bus uuid := p_bus_id;
  v_gare uuid := p_gare_id;
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, true);

  IF p_category_id IS NULL THEN
    RAISE EXCEPTION 'Categorie requise';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Montant invalide';
  END IF;
  IF p_expense_date IS NULL THEN
    RAISE EXCEPTION 'Date de depense requise';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "CompanyExpenseCategory" c
    WHERE c.id = p_category_id AND c."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Categorie introuvable';
  END IF;

  IF v_team IS NOT NULL AND (v_bus IS NOT NULL OR v_gare IS NOT NULL) THEN
    RAISE EXCEPTION 'Imputation invalide: membre equipe OU bus+gare';
  END IF;
  IF v_team IS NULL AND (v_bus IS NULL OR v_gare IS NULL) THEN
    RAISE EXCEPTION 'Imputation requise: membre equipe OU bus+gare';
  END IF;

  IF v_team IS NOT NULL THEN
    IF NOT public._company_expense_team_member_valid(p_company_id, v_team) THEN
      RAISE EXCEPTION 'Membre equipe invalide pour cette compagnie';
    END IF;
    v_bus := NULL;
    v_gare := NULL;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM "Bus" b
      WHERE b.id = v_bus AND b."companyId" = p_company_id
    ) THEN
      RAISE EXCEPTION 'Bus invalide pour cette compagnie';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM "Gares" g
      WHERE g.id = v_gare AND g."companyId" = p_company_id
    ) THEN
      RAISE EXCEPTION 'Gare invalide pour cette compagnie';
    END IF;
    v_team := NULL;
  END IF;

  SELECT COALESCE(cn.currency, 'XOF')
  INTO v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" cn ON cn.id = c."countryId"
  WHERE c.id = p_company_id;

  IF p_id IS NOT NULL THEN
    UPDATE "CompanyExpense" e
    SET
      "categoryId" = p_category_id,
      amount = p_amount,
      currency = v_currency,
      "expenseDate" = p_expense_date,
      description = NULLIF(btrim(p_description), ''),
      "teamMemberUserId" = v_team,
      "busId" = v_bus,
      "gareId" = v_gare
    WHERE e.id = p_id
      AND e."companyId" = p_company_id
    RETURNING e.id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Depense introuvable';
    END IF;
  ELSE
    INSERT INTO "CompanyExpense" (
      "companyId",
      "categoryId",
      amount,
      currency,
      "expenseDate",
      description,
      "teamMemberUserId",
      "busId",
      "gareId",
      "createdByUserId"
    )
    VALUES (
      p_company_id,
      p_category_id,
      p_amount,
      v_currency,
      p_expense_date,
      NULLIF(btrim(p_description), ''),
      v_team,
      v_bus,
      v_gare,
      v_user_id
    )
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_company_expense(
  p_company_id uuid,
  p_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, true);

  DELETE FROM "CompanyExpense" e
  WHERE e.id = p_id
    AND e."companyId" = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Depense introuvable';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Compte de résultat (SYSCOHADA)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_company_income_statement(
  p_company_id uuid,
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from date;
  v_to date;
  v_currency text := 'XOF';
  v_company_name text;
  v_ticket_revenue double precision := 0;
  v_parcel_revenue double precision := 0;
  v_commissions double precision := 0;
  v_gare_shares double precision := 0;
  v_products_total double precision := 0;
  v_charges_total double precision := 0;
  v_product_lines jsonb := '[]'::jsonb;
  v_charge_lines jsonb := '[]'::jsonb;
  v_operating double precision := 0;
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, false);

  v_from := COALESCE(p_from, date_trunc('year', current_date)::date);
  v_to := COALESCE(p_to, current_date);
  IF v_from > v_to THEN
    RAISE EXCEPTION 'Periode invalide';
  END IF;

  SELECT c.name, COALESCE(cn.currency, 'XOF')
  INTO v_company_name, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" cn ON cn.id = c."countryId"
  WHERE c.id = p_company_id;

  WITH issued_tickets AS (
    SELECT
      rb.price,
      COALESCE(rb."sellerCommissionAmount", 0) AS seller_commission,
      COALESCE(rb."gareManagerShareAmount", 0) AS gare_share
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    WHERE g."companyId" = p_company_id
      AND rb."type" = 'voyage'
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND rb."createdAt"::date BETWEEN v_from AND v_to
  )
  SELECT
    COALESCE(SUM(price), 0),
    COALESCE(SUM(seller_commission), 0),
    COALESCE(SUM(gare_share), 0)
  INTO v_ticket_revenue, v_commissions, v_gare_shares
  FROM issued_tickets;

  SELECT COALESCE(SUM(ca.montant_fret), 0)
  INTO v_parcel_revenue
  FROM public.colis_autonomes ca
  WHERE ca.company_id = p_company_id
    AND ca.created_at::date BETWEEN v_from AND v_to;

  v_products_total := v_ticket_revenue + v_parcel_revenue;

  v_product_lines := jsonb_build_array(
    jsonb_build_object(
      'accountCode', '7011',
      'accountLabel', 'Ventes de prestations de services (tickets)',
      'amount', v_ticket_revenue
    ),
    jsonb_build_object(
      'accountCode', '7012',
      'accountLabel', 'Ventes de prestations de services (colis)',
      'amount', v_parcel_revenue
    )
  );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'accountCode', s."ohadaAccountCode",
        'accountLabel', s."ohadaAccountLabel",
        'amount', s.amount
      )
      ORDER BY s."ohadaAccountCode", s."ohadaAccountLabel"
    ),
    '[]'::jsonb
  )
  INTO v_charge_lines
  FROM (
    SELECT
      c."ohadaAccountCode",
      MAX(c."ohadaAccountLabel") AS "ohadaAccountLabel",
      SUM(e.amount) AS amount
    FROM "CompanyExpense" e
    JOIN "CompanyExpenseCategory" c ON c.id = e."categoryId"
    WHERE e."companyId" = p_company_id
      AND e."expenseDate" BETWEEN v_from AND v_to
    GROUP BY c."ohadaAccountCode"
    HAVING SUM(e.amount) > 0
  ) s;

  IF v_commissions > 0 THEN
    v_charge_lines := v_charge_lines || jsonb_build_array(
      jsonb_build_object(
        'accountCode', '6612',
        'accountLabel', 'Commissions et courtages sur ventes',
        'amount', v_commissions
      )
    );
  END IF;

  IF v_gare_shares > 0 THEN
    v_charge_lines := v_charge_lines || jsonb_build_array(
      jsonb_build_object(
        'accountCode', '6227',
        'accountLabel', 'Rémunérations et frais de sous-traitance (parts gares)',
        'amount', v_gare_shares
      )
    );
  END IF;

  SELECT COALESCE(SUM((line->>'amount')::double precision), 0)
  INTO v_charges_total
  FROM jsonb_array_elements(v_charge_lines) AS line;

  v_operating := v_products_total - v_charges_total;

  RETURN jsonb_build_object(
    'company', jsonb_build_object(
      'id', p_company_id,
      'name', v_company_name,
      'currency', v_currency
    ),
    'period', jsonb_build_object(
      'from', v_from,
      'to', v_to
    ),
    'framework', 'SYSCOHADA',
    'statementType', 'compte_de_resultat',
    'products', jsonb_build_object(
      'lines', v_product_lines,
      'total', v_products_total
    ),
    'charges', jsonb_build_object(
      'lines', v_charge_lines,
      'total', v_charges_total
    ),
    'results', jsonb_build_object(
      'operatingResult', v_operating,
      'financialResult', 0,
      'currentResult', v_operating,
      'netResult', v_operating
    )
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.assert_company_expense_access(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_company_expense_categories(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_expense_categories(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_company_expense_category(uuid, uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_company_expense_category(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_expenses(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_company_expense(uuid, uuid, uuid, double precision, date, text, uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_company_expense(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_income_statement(uuid, date, date) TO authenticated;
