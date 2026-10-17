-- ============================================================================
-- Patch du 2026-10-17 (4) : option Comptabilité — dépenses et bilan SYSCOHADA
-- dans l'app courrier.
--
-- Crée la table des dépenses (CompanyExpense) et les fonctions de saisie,
-- ainsi que le bilan SYSCOHADA (get_company_bilan). Les catégories de
-- dépenses (CompanyExpenseCategory) existent déjà sur cette base.
-- Prérequis : patchs du 2026-10-08 et du 2026-10-17c (abonnements).
-- Idempotent : sans risque à rejouer.
--
--   psql "$HOSTINGER_DB_URL" -f 00_patch_2026-10-17d.sql
-- ============================================================================

CREATE TABLE IF NOT EXISTS public."CompanyExpense" (
  id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
  "companyId" uuid NOT NULL REFERENCES public."Companies"(id) ON DELETE CASCADE,
  "categoryId" uuid NOT NULL REFERENCES public."CompanyExpenseCategory"(id) ON DELETE RESTRICT,
  amount double precision NOT NULL CHECK (amount > 0),
  currency text DEFAULT 'XOF' NOT NULL,
  "expenseDate" date NOT NULL,
  description text,
  "teamMemberUserId" uuid REFERENCES public."Users"(id) ON DELETE SET NULL,
  "busId" uuid REFERENCES public."Bus"(id) ON DELETE SET NULL,
  "gareId" uuid REFERENCES public."Gares"(id) ON DELETE SET NULL,
  "createdByUserId" uuid REFERENCES public."Users"(id) ON DELETE SET NULL,
  "createdAt" timestamptz DEFAULT now() NOT NULL,
  "updatedAt" timestamptz DEFAULT now() NOT NULL,
  CONSTRAINT company_expense_imputation_xor CHECK (
    ("teamMemberUserId" IS NOT NULL AND "busId" IS NULL AND "gareId" IS NULL)
    OR ("teamMemberUserId" IS NULL AND "gareId" IS NOT NULL)
  )
);
CREATE INDEX IF NOT EXISTS company_expense_company_date_idx ON public."CompanyExpense" ("companyId", "expenseDate" DESC);
CREATE INDEX IF NOT EXISTS company_expense_category_idx ON public."CompanyExpense" ("categoryId");
ALTER TABLE public."CompanyExpense" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."CompanyExpense" FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.tg_company_expense_touch_updated_at()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  NEW."updatedAt" := now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER company_expense_touch_updated_at
  BEFORE UPDATE ON public."CompanyExpense"
  FOR EACH ROW EXECUTE FUNCTION public.tg_company_expense_touch_updated_at();

-- Lecture seule si l'abonnement Comptabilité est expiré (patch 2026-10-17c).
CREATE OR REPLACE TRIGGER app_writable_comptabilite
  BEFORE INSERT OR UPDATE OR DELETE ON public."CompanyExpense"
  FOR EACH ROW EXECUTE FUNCTION public._trg_app_writable('comptabilite');

CREATE OR REPLACE FUNCTION public._company_expense_team_member_valid(p_company_id uuid, p_user_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."companyId" = p_company_id
      AND ur."userId" = p_user_id
      AND r.name IN ('owner', 'comptable_compagnie', 'controleur', 'vendeur', 'chauffeur', 'gestionnaire_gare')
  );
$function$;

CREATE OR REPLACE FUNCTION public.assert_company_expense_access(p_company_id uuid, p_write boolean DEFAULT false)
 RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "Companies" c WHERE c.id = p_company_id) THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;
  IF p_write THEN
    IF NOT (public.is_super_admin() OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])) THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.ensure_company_expense_categories(p_company_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, false);
  PERFORM public._seed_company_expense_categories(p_company_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_company_expense_categories(p_company_id uuid)
 RETURNS SETOF jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.upsert_company_expense_category(p_company_id uuid, p_id uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_ohada_account_code text DEFAULT '622'::text, p_ohada_account_label text DEFAULT 'Services extérieurs'::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
  IF v_code IS NULL THEN v_code := '622'; END IF;
  IF v_label IS NULL THEN v_label := 'Services extérieurs'; END IF;

  IF p_id IS NOT NULL THEN
    UPDATE "CompanyExpenseCategory" c
    SET name = v_name, "ohadaAccountCode" = v_code, "ohadaAccountLabel" = v_label
    WHERE c.id = p_id AND c."companyId" = p_company_id
    RETURNING c.id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Categorie introuvable';
    END IF;
  ELSE
    INSERT INTO "CompanyExpenseCategory" ("companyId", name, "ohadaAccountCode", "ohadaAccountLabel", "sortOrder", "isPreset")
    VALUES (
      p_company_id, v_name, v_code, v_label,
      COALESCE((SELECT MAX("sortOrder") + 1 FROM "CompanyExpenseCategory" WHERE "companyId" = p_company_id), 100),
      false
    )
    RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_company_expense_category(p_company_id uuid, p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, true);
  IF EXISTS (
    SELECT 1 FROM "CompanyExpense" e
    WHERE e."categoryId" = p_id AND e."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Impossible de supprimer: des depenses utilisent cette categorie';
  END IF;
  DELETE FROM "CompanyExpenseCategory" c
  WHERE c.id = p_id AND c."companyId" = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Categorie introuvable';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_company_expenses(p_company_id uuid, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS SETOF jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.upsert_company_expense(p_company_id uuid, p_id uuid DEFAULT NULL::uuid, p_category_id uuid DEFAULT NULL::uuid, p_amount double precision DEFAULT NULL::double precision, p_expense_date date DEFAULT NULL::date, p_description text DEFAULT NULL::text, p_team_member_user_id uuid DEFAULT NULL::uuid, p_bus_id uuid DEFAULT NULL::uuid, p_gare_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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

  IF p_category_id IS NULL THEN RAISE EXCEPTION 'Categorie requise'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF p_expense_date IS NULL THEN RAISE EXCEPTION 'Date de depense requise'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "CompanyExpenseCategory" c
    WHERE c.id = p_category_id AND c."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Categorie introuvable';
  END IF;

  IF v_team IS NOT NULL AND (v_bus IS NOT NULL OR v_gare IS NOT NULL) THEN
    RAISE EXCEPTION 'Imputation invalide: membre equipe OU bus+gare';
  END IF;
  IF v_team IS NULL AND v_gare IS NULL THEN
    RAISE EXCEPTION 'Imputation requise: membre equipe OU gare';
  END IF;

  IF v_team IS NOT NULL THEN
    IF NOT public._company_expense_team_member_valid(p_company_id, v_team) THEN
      RAISE EXCEPTION 'Membre equipe invalide pour cette compagnie';
    END IF;
    v_bus := NULL;
    v_gare := NULL;
  ELSE
    IF v_bus IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM "Bus" b WHERE b.id = v_bus AND b."companyId" = p_company_id
    ) THEN
      RAISE EXCEPTION 'Bus invalide pour cette compagnie';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM "Gares" g WHERE g.id = v_gare AND g."companyId" = p_company_id
    ) THEN
      RAISE EXCEPTION 'Gare invalide pour cette compagnie';
    END IF;
    v_team := NULL;
  END IF;

  SELECT COALESCE(cn.currency, 'XOF') INTO v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" cn ON cn.id = c."countryId"
  WHERE c.id = p_company_id;

  IF p_id IS NOT NULL THEN
    UPDATE "CompanyExpense" e
    SET "categoryId" = p_category_id, amount = p_amount, currency = v_currency,
        "expenseDate" = p_expense_date, description = NULLIF(btrim(p_description), ''),
        "teamMemberUserId" = v_team, "busId" = v_bus, "gareId" = v_gare
    WHERE e.id = p_id AND e."companyId" = p_company_id
    RETURNING e.id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Depense introuvable'; END IF;
  ELSE
    INSERT INTO "CompanyExpense" ("companyId", "categoryId", amount, currency, "expenseDate", description,
                                  "teamMemberUserId", "busId", "gareId", "createdByUserId")
    VALUES (p_company_id, p_category_id, p_amount, v_currency, p_expense_date, NULLIF(btrim(p_description), ''),
            v_team, v_bus, v_gare, v_user_id)
    RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_company_expense(p_company_id uuid, p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_company_expense_access(p_company_id, true);
  DELETE FROM "CompanyExpense" e
  WHERE e.id = p_id AND e."companyId" = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Depense introuvable';
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.list_company_expense_categories(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_company_expense_category(uuid, uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_company_expense_category(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_expenses(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_company_expense(uuid, uuid, uuid, double precision, date, text, uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_company_expense(uuid, uuid) TO authenticated;

-- Bilan SYSCOHADA (identique à la migration 223 de Tibus).
CREATE OR REPLACE FUNCTION public.get_company_bilan(p_company_id uuid, p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_from date := COALESCE(p_from, date_trunc('year', current_date)::date);
  v_to date := COALESCE(p_to, current_date);
  v_company_name text;
  v_tickets double precision := 0;
  v_commissions double precision := 0;
  v_gare_shares double precision := 0;
  v_colis double precision := 0;
  v_embarquement double precision := 0;
  v_achats double precision := 0;
  v_charges jsonb := '[]'::jsonb;
  v_total_charges double precision := 0;
  v_caisse double precision := 0;
  v_coffre double precision := 0;
  v_ventes double precision := 0;
BEGIN
  PERFORM public.assert_company_module(p_company_id, 'C');
  PERFORM public.assert_company_expense_access(p_company_id, false);
  IF v_from > v_to THEN RAISE EXCEPTION 'Periode invalide'; END IF;

  SELECT name INTO v_company_name FROM "Companies" WHERE id = p_company_id;

  -- 706 — Colis : date réelle de la vente (hors ligne comprise), hors annulés.
  SELECT COALESCE(SUM(ca.montant_fret), 0) INTO v_colis
  FROM public.colis_autonomes ca
  WHERE ca.company_id = p_company_id
    AND ca.statut_colis <> 'annule'
    AND COALESCE(ca.offline_created_at, ca.created_at)::date BETWEEN v_from AND v_to;

  -- 706 — Billets émis (billetterie Tibus), commissions et parts gares.
  BEGIN
    SELECT COALESCE(SUM(rb.price), 0),
           COALESCE(SUM(COALESCE(rb."sellerCommissionAmount", 0)), 0),
           COALESCE(SUM(COALESCE(rb."gareManagerShareAmount", 0)), 0)
    INTO v_tickets, v_commissions, v_gare_shares
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    WHERE g."companyId" = p_company_id
      AND rb."type" = 'voyage'
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND rb."createdAt"::date BETWEEN v_from AND v_to;
  EXCEPTION WHEN undefined_table OR undefined_column THEN
    v_tickets := 0; v_commissions := 0; v_gare_shares := 0;
  END;

  -- 706 — Embarquement hors-Tibus (montant figé par scan valide).
  IF to_regclass('public.embarquement_scans') IS NOT NULL THEN
    EXECUTE $q$
      SELECT COALESCE(SUM(s.amount), 0)
      FROM public.embarquement_scans s
      JOIN public.embarquement_sessions es ON es.id = s.session_id
      WHERE es.company_id = $1 AND es.reservation_id IS NULL
        AND s.status = 'valid' AND s.deleted_at IS NULL
        AND s.scanned_at::date BETWEEN $2 AND $3
    $q$ INTO v_embarquement USING p_company_id, v_from, v_to;
  END IF;

  v_ventes := v_colis + v_tickets + v_embarquement;

  -- 60 — Achats.
  SELECT COALESCE(SUM(e.amount), 0) INTO v_achats
  FROM "CompanyExpense" e
  JOIN "CompanyExpenseCategory" c ON c.id = e."categoryId"
  WHERE e."companyId" = p_company_id
    AND e."expenseDate" BETWEEN v_from AND v_to
    AND c."ohadaAccountCode" LIKE '60%';

  -- Autres charges d'exploitation, par catégorie.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'codeOhada', s.code, 'libelle', s.libelle, 'total', s.total)
         ORDER BY s.code, s.libelle), '[]'::jsonb)
  INTO v_charges
  FROM (
    SELECT c."ohadaAccountCode" AS code, c.name AS libelle, SUM(e.amount) AS total
    FROM "CompanyExpense" e
    JOIN "CompanyExpenseCategory" c ON c.id = e."categoryId"
    WHERE e."companyId" = p_company_id
      AND e."expenseDate" BETWEEN v_from AND v_to
      AND c."ohadaAccountCode" NOT LIKE '60%'
    GROUP BY c."ohadaAccountCode", c.name
    HAVING SUM(e.amount) > 0
  ) s;
  IF v_commissions > 0 THEN
    v_charges := v_charges || jsonb_build_array(jsonb_build_object(
      'codeOhada', '6612', 'libelle', 'Commissions sur ventes', 'total', v_commissions));
  END IF;
  IF v_gare_shares > 0 THEN
    v_charges := v_charges || jsonb_build_array(jsonb_build_object(
      'codeOhada', '6227', 'libelle', 'Parts gares', 'total', v_gare_shares));
  END IF;
  SELECT COALESCE(SUM((x->>'total')::double precision), 0) INTO v_total_charges
  FROM jsonb_array_elements(v_charges) x;

  -- 521 — Caisses des agents : solde des caisses encore ouvertes.
  SELECT COALESCE(SUM(cg.solde_especes_actuel), 0) INTO v_caisse
  FROM public.caisses_gares cg
  JOIN "Gares" g ON g.id = cg.gare_id
  WHERE g."companyId" = p_company_id AND cg.statut <> 'cloturee';

  -- 531 — Coffre : reversements validés par la comptabilité sur la période.
  SELECT COALESCE(SUM(r.montant_reverse), 0) INTO v_coffre
  FROM public.reversements_comptables r
  JOIN public.caisses_gares cg ON cg.id = r.caisse_id
  JOIN "Gares" g ON g.id = cg.gare_id
  WHERE g."companyId" = p_company_id
    AND r.statut_validation = 'approuve_recu'
    AND COALESCE(r.validated_at, r.created_at)::date BETWEEN v_from AND v_to;

  RETURN jsonb_build_object(
    'companyName', v_company_name,
    'from', v_from,
    'to', v_to,
    'produits', jsonb_build_array(
      jsonb_build_object('codeOhada', '706', 'libelle', 'Colis (courrier)', 'total', v_colis),
      jsonb_build_object('codeOhada', '706', 'libelle', 'Billets', 'total', v_tickets),
      jsonb_build_object('codeOhada', '706', 'libelle', 'Embarquement', 'total', v_embarquement)
    ),
    'totalVentes', v_ventes,
    'totalAchats', v_achats,
    'charges', v_charges,
    'totalCharges', v_total_charges,
    'resultat', v_ventes - v_achats - v_total_charges,
    'tresorerieCaisse', v_caisse,
    'tresorerieCoffre', v_coffre,
    'tresorerieBanque', 0
  );
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.get_company_bilan(uuid, date, date) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_company_bilan(uuid, date, date) FROM anon, public;
