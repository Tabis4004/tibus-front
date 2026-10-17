-- 223 — Bilan SYSCOHADA pour l'app courrier (option Comptabilité)
--
-- Même présentation que Gestabis : résultat net (produits 706, achats 60,
-- charges classe 6), trésorerie classe 5 (caisses des agents, coffre). Les
-- ventes colis comptent à la date réelle de la vente, hors colis annulés.
-- Réservé au owner / comptable compagnie, module C activé.

-- Bilan SYSCOHADA d'une compagnie sur une période (même présentation que
-- Gestabis) : compte de résultat (produits classe 7, achats 60, charges
-- classe 6) et trésorerie classe 5 (caisses des agents, coffre, banques).
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
