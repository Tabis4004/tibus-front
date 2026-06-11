-- =============================================================================
-- Tibus 075 — % gestionnaire gare : guichet et réservations séparés par gare
-- =============================================================================
-- PRÉREQUIS : 074_gare_manager_reservation_commission.sql
-- =============================================================================

ALTER TABLE "Gares"
  ADD COLUMN IF NOT EXISTS "gestionnaireSharePctReservation" double precision NOT NULL DEFAULT 0;

ALTER TABLE "Gares" DROP CONSTRAINT IF EXISTS gares_gestionnaire_share_pct_reservation_check;
ALTER TABLE "Gares" ADD CONSTRAINT gares_gestionnaire_share_pct_reservation_check
  CHECK ("gestionnaireSharePctReservation" >= 0 AND "gestionnaireSharePctReservation" <= 100);

UPDATE "Gares"
SET "gestionnaireSharePctReservation" = "gestionnaireSharePct"
WHERE "gestionnaireSharePct" > 0
  AND COALESCE("gestionnaireSharePctReservation", 0) = 0;

CREATE OR REPLACE FUNCTION public.set_reservationbus_gare_manager_share()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gare record;
  v_channel text;
  v_share_pct double precision;
BEGIN
  IF NEW."type" <> 'voyage' THEN
    NEW."gareSaleId" := NULL;
    NEW."gareManagerUserId" := NULL;
    NEW."gareManagerSharePct" := NULL;
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  v_channel := COALESCE(NULLIF(BTRIM(NEW."saleChannel"), ''), 'traveler');

  IF v_channel NOT IN ('counter_sale', 'traveler', 'seller_reservation') THEN
    NEW."gareSaleId" := NULL;
    NEW."gareManagerUserId" := NULL;
    NEW."gareManagerSharePct" := NULL;
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  NEW."gareSaleId" := public.resolve_sale_gare_id(NEW."createdBy", NEW."reservationId", v_channel);

  IF NEW."gareSaleId" IS NULL THEN
    NEW."gareManagerUserId" := NULL;
    NEW."gareManagerSharePct" := NULL;
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  SELECT
    g.id,
    g."gestionnaireUserId",
    g."gestionnaireSharePct",
    g."gestionnaireSharePctReservation",
    g."companyId"
  INTO v_gare
  FROM "Gares" g
  WHERE g.id = NEW."gareSaleId";

  IF v_channel = 'counter_sale' THEN
    v_share_pct := COALESCE(v_gare."gestionnaireSharePct", 0);
  ELSE
    v_share_pct := COALESCE(v_gare."gestionnaireSharePctReservation", 0);
  END IF;

  IF v_gare."gestionnaireUserId" IS NULL OR v_share_pct <= 0 THEN
    NEW."gareManagerUserId" := NULL;
    NEW."gareManagerSharePct" := NULL;
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  NEW."gareManagerUserId" := v_gare."gestionnaireUserId";
  NEW."gareManagerSharePct" := v_share_pct;
  NEW."gareManagerShareAmount" := ROUND(
    (COALESCE(NEW.price, 0) * v_share_pct / 100)::numeric
  )::double precision;

  IF NEW."gareManagerShareAmount" <= 0 THEN
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  IF v_channel = 'counter_sale' THEN
    NEW."gareManagerShareStatus" := 'collected';
    RETURN NEW;
  END IF;

  IF NEW."gareManagerShareStatus" IN ('collected') THEN
    NEW."gareManagerShareStatus" := 'pending';
  ELSE
    NEW."gareManagerShareStatus" := COALESCE(NEW."gareManagerShareStatus", 'pending');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_gare_manager_revenue_share(
  p_gare_id uuid,
  p_share_pct double precision,
  p_gestionnaire_user_id uuid DEFAULT NULL,
  p_share_pct_reservation double precision DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_counter_pct double precision;
  v_reservation_pct double precision;
BEGIN
  v_counter_pct := GREATEST(0, LEAST(COALESCE(p_share_pct, 0), 100));
  v_reservation_pct := GREATEST(0, LEAST(COALESCE(p_share_pct_reservation, p_share_pct, 0), 100));

  SELECT g."companyId" INTO v_company_id FROM "Gares" g WHERE g.id = p_gare_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Gare introuvable'; END IF;

  IF NOT public.is_super_admin() AND NOT public.has_company_role(v_company_id, ARRAY['owner']) THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  IF p_gestionnaire_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = p_gestionnaire_user_id
      AND ur."companyId" = v_company_id
      AND r.name IN ('gestionnaire_gare', 'vendeur', 'owner')
  ) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Utilisateur non eligible comme gestionnaire de gare';
  END IF;

  UPDATE "Gares"
  SET
    "gestionnaireSharePct" = v_counter_pct,
    "gestionnaireSharePctReservation" = v_reservation_pct,
    "gestionnaireUserId" = p_gestionnaire_user_id
  WHERE id = p_gare_id;

  RETURN jsonb_build_object(
    'gareId', p_gare_id,
    'sharePct', v_counter_pct,
    'sharePctReservation', v_reservation_pct,
    'gestionnaireUserId', p_gestionnaire_user_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_gare_manager_counter_revenue_summary(
  p_company_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_currency text;
  v_rows jsonb;
  v_totals jsonb;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  IF v_company_id IS NULL THEN
    SELECT ur."companyId" INTO v_company_id
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id AND r.name = 'gestionnaire_gare'
    LIMIT 1;
  END IF;

  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner', 'comptable_compagnie', 'gestionnaire_gare'])
  THEN
    RAISE EXCEPTION 'Acces refuse';
  END IF;

  SELECT COALESCE(cn.currency, 'XOF') INTO v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" cn ON cn.id = c."countryId"
  WHERE c.id = v_company_id;

  WITH tickets AS (
    SELECT
      rb.id,
      rb.price,
      COALESCE(rb."saleChannel", 'traveler') AS sale_channel,
      rb."gareSaleId",
      rb."gareManagerUserId",
      rb."gareManagerShareAmount",
      rb."gareManagerShareStatus",
      rb."gareManagerSharePct"
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = COALESCE(rb."gareSaleId", pt.depart)
    WHERE g."companyId" = v_company_id
      AND rb."type" = 'voyage'
      AND COALESCE(rb."saleChannel", 'traveler') IN ('counter_sale', 'traveler', 'seller_reservation')
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued'
      AND rb."gareManagerShareAmount" IS NOT NULL
      AND (
        public.has_company_role(v_company_id, ARRAY['owner', 'comptable_compagnie'])
        OR rb."gareManagerUserId" = v_user_id
        OR public.is_super_admin()
      )
  ),
  by_gare AS (
    SELECT
      g.id AS gare_id,
      g.name AS gare_name,
      g."gestionnaireUserId" AS manager_id,
      TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')) AS manager_name,
      COALESCE(g."gestionnaireSharePct", 0) AS share_pct_counter,
      COALESCE(g."gestionnaireSharePctReservation", 0) AS share_pct_reservation,
      COALESCE(SUM(t.price) FILTER (WHERE t.sale_channel = 'counter_sale'), 0)::double precision AS counter_sales_gmv,
      COALESCE(SUM(t."gareManagerShareAmount") FILTER (WHERE t.sale_channel = 'counter_sale'), 0)::double precision AS counter_share_collected,
      COALESCE(SUM(t."gareManagerShareAmount") FILTER (WHERE t.sale_channel IN ('traveler', 'seller_reservation')), 0)::double precision AS reservation_share_total,
      COALESCE(SUM(t."gareManagerShareAmount") FILTER (
        WHERE t.sale_channel IN ('traveler', 'seller_reservation') AND t."gareManagerShareStatus" = 'paid'
      ), 0)::double precision AS reservation_paid_total,
      COALESCE(SUM(t."gareManagerShareAmount") FILTER (
        WHERE t.sale_channel IN ('traveler', 'seller_reservation') AND t."gareManagerShareStatus" = 'pending'
      ), 0)::double precision AS reservation_pending_total
    FROM "Gares" g
    LEFT JOIN tickets t ON t."gareSaleId" = g.id
    LEFT JOIN "Users" u ON u.id = g."gestionnaireUserId"
    WHERE g."companyId" = v_company_id
      AND g.name <> '__CASH_SESSION_HUB__'
    GROUP BY
      g.id,
      g.name,
      g."gestionnaireUserId",
      u."firstName",
      u."lastName",
      g."gestionnaireSharePct",
      g."gestionnaireSharePctReservation"
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'gareId', bg.gare_id,
      'gareName', bg.gare_name,
      'managerUserId', bg.manager_id,
      'managerName', NULLIF(bg.manager_name, ''),
      'sharePct', bg.share_pct_counter,
      'sharePctReservation', bg.share_pct_reservation,
      'counterSalesGmv', bg.counter_sales_gmv,
      'counterShareCollected', bg.counter_share_collected,
      'reservationShareTotal', bg.reservation_share_total,
      'paidTotal', bg.reservation_paid_total,
      'pendingTotal', bg.reservation_pending_total
    ) ORDER BY bg.gare_name
  ), '[]'::jsonb) INTO v_rows
  FROM by_gare bg;

  SELECT jsonb_build_object(
    'counterSalesGmv', COALESCE(SUM((elem->>'counterSalesGmv')::double precision), 0),
    'counterShareCollected', COALESCE(SUM((elem->>'counterShareCollected')::double precision), 0),
    'reservationShareTotal', COALESCE(SUM((elem->>'reservationShareTotal')::double precision), 0),
    'paidTotal', COALESCE(SUM((elem->>'paidTotal')::double precision), 0),
    'pendingTotal', COALESCE(SUM((elem->>'pendingTotal')::double precision), 0)
  ) INTO v_totals
  FROM jsonb_array_elements(v_rows) elem;

  RETURN jsonb_build_object('currency', v_currency, 'rows', v_rows, 'totals', v_totals);
END;
$$;

UPDATE "ReservationBus" rb
SET price = rb.price
WHERE rb."type" = 'voyage'
  AND COALESCE(rb."saleChannel", 'traveler') IN ('traveler', 'seller_reservation');

GRANT EXECUTE ON FUNCTION public.set_gare_manager_revenue_share(uuid, double precision, uuid, double precision) TO authenticated;
