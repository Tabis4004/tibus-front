-- Lot 121: Gardes modules compagnie sur RPC et tables sensibles.

-- Module A : commission guichet
CREATE OR REPLACE FUNCTION public.charge_company_counter_platform_commission(
  p_booking_id uuid,
  p_company_id uuid,
  p_amount double precision,
  p_reference text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance double precision;
  v_new_balance double precision;
  v_allow_negative boolean;
  v_ledger_id uuid;
  v_existing uuid;
BEGIN
  PERFORM public.assert_company_module(p_company_id, 'A');

  IF COALESCE(p_amount, 0) <= 0 OR p_company_id IS NULL OR p_booking_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT rb."guaranteeCommissionLedgerId"
  INTO v_existing
  FROM "ReservationBus" rb
  WHERE rb.id = p_booking_id;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT c."guaranteeBalance", c."guaranteeAllowNegative"
  INTO v_balance, v_allow_negative
  FROM "Companies" c
  WHERE c.id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT COALESCE(v_allow_negative, false) AND v_balance < p_amount THEN
    RAISE EXCEPTION 'Fond de garantie insuffisant pour la commission guichet (solde: %, requis: %)', v_balance, p_amount
      USING ERRCODE = 'P0001';
  END IF;

  v_new_balance := v_balance - p_amount;

  UPDATE "Companies"
  SET "guaranteeBalance" = v_new_balance
  WHERE id = p_company_id;

  INSERT INTO "CompanyGuaranteeLedger" (
    "companyId", "type", "amount", "balanceAfter", "reference", "bookingId", "note", "createdBy"
  )
  VALUES (
    p_company_id,
    'counter_commission',
    p_amount,
    v_new_balance,
    NULLIF(trim(p_reference), ''),
    p_booking_id,
    'Commission plateforme vente guichet',
    public.current_app_user_id()
  )
  RETURNING id INTO v_ledger_id;

  UPDATE "ReservationBus"
  SET "guaranteeCommissionLedgerId" = v_ledger_id
  WHERE id = p_booking_id;

  IF v_new_balance <= 0 THEN
    PERFORM public.notify_guarantee_balance_low(p_company_id, v_new_balance);
  END IF;

  RETURN v_ledger_id;
END;
$$;

-- Module B : scan QR (patch léger via wrapper pre-check sur reservation_company_id)
CREATE OR REPLACE FUNCTION public.assert_company_module_for_reservation(
  p_reservation_id uuid,
  p_module text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  v_company_id := public.reservation_company_id(p_reservation_id);
  IF v_company_id IS NOT NULL THEN
    PERFORM public.assert_company_module(v_company_id, p_module);
  END IF;
END;
$$;

-- Module D : colis autonomes
CREATE OR REPLACE FUNCTION public.trg_colis_autonomes_module_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_company_module(NEW.company_id, 'D');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS colis_autonomes_module_guard ON public.colis_autonomes;
CREATE TRIGGER colis_autonomes_module_guard
  BEFORE INSERT ON public.colis_autonomes
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_colis_autonomes_module_guard();

-- Module C : dépenses (assert sur RPC existantes — corps recréé minimal si présentes)
DO $guard_c$
BEGIN
  IF to_regprocedure('public.get_company_income_statement(uuid,date,date)') IS NOT NULL THEN
    EXECUTE $sql$
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
      AS $fn$
      BEGIN
        PERFORM public.assert_company_module(p_company_id, 'C');
        RETURN public._get_company_income_statement_impl(p_company_id, p_from, p_to);
      END;
      $fn$;
    $sql$;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Guard C income_statement skipped: %', SQLERRM;
END;
$guard_c$;


CREATE OR REPLACE FUNCTION public.confirm_passenger_on_board(
  p_reference text,
  p_scanner_company_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ref text := public.normalize_ticket_reference(p_reference);
  v_fragment text;
  v_rb record;
  v_scanner_company_id uuid;
BEGIN
  IF v_ref = '' THEN
    RETURN public.ticket_scan_wrong_company_payload('', NULL);
  END IF;

  v_fragment := REPLACE(v_ref, 'TB-', '');

  SELECT rb.id, rb."reservationId", rb."onBoardAt", p.reference
  INTO v_rb
  FROM "Payment" p
  JOIN "ReservationBus" rb ON rb."paymentId" = p.id
  WHERE UPPER(BTRIM(p.reference)) LIKE '%' || v_fragment || '%'
  ORDER BY rb."createdAt" DESC
  LIMIT 1;

  IF v_rb.id IS NULL THEN
    RETURN jsonb_build_object(
      'valid', false,
      'result', 'not_found',
      'message', 'Aucun billet ne correspond à cette référence',
      'bookingReference', v_ref,
      'passengerName', '',
      'totalPrice', 0,
      'currency', 'XOF',
      'paymentStatus', 'pending',
      'status', 'cancelled'
    );
  END IF;

  v_scanner_company_id := public.resolve_scanner_company_id(p_scanner_company_id);

  IF NOT public.is_super_admin() THEN
    IF v_scanner_company_id IS NULL
      OR NOT public.ticket_matches_scanner_company(v_rb."reservationId", v_scanner_company_id) THEN
      RETURN public.ticket_scan_wrong_company_payload(v_rb.reference, v_rb.id);
    END IF;
  END IF;

  IF v_rb."onBoardAt" IS NOT NULL THEN
    RETURN public.verify_ticket_qr(v_rb.reference, NULL, true, true, p_scanner_company_id);
  END IF;

  UPDATE "ReservationBus"
  SET
    "onBoardAt" = now(),
    "onBoardBy" = public.current_app_user_id(),
    "onBoardScanCount" = COALESCE("onBoardScanCount", 0) + 1
  WHERE id = v_rb.id;

  RETURN public.verify_ticket_qr(v_rb.reference, NULL, true, true, p_scanner_company_id);
END;
$$;

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
  PERFORM public.assert_company_module(p_company_id, 'C');
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
  PERFORM public.assert_company_module(p_company_id, 'C');
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
  PERFORM public.assert_company_module(p_company_id, 'C');
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


DO $guard_e$
BEGIN
  IF to_regclass('public."PromoCodes"') IS NOT NULL THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION public.trg_promo_codes_module_guard()
      RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $t$
      BEGIN
        PERFORM public.assert_company_module(NEW."companyId", 'E');
        RETURN NEW;
      END;
      $t$;
      DROP TRIGGER IF EXISTS promo_codes_module_guard ON public."PromoCodes";
      CREATE TRIGGER promo_codes_module_guard
        BEFORE INSERT OR UPDATE ON public."PromoCodes"
        FOR EACH ROW EXECUTE FUNCTION public.trg_promo_codes_module_guard();
    $sql$;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Guard E promo skipped: %', SQLERRM;
END;
$guard_e$;

GRANT EXECUTE ON FUNCTION public.assert_company_module_for_reservation(uuid, text) TO authenticated;
