-- =============================================================================
-- Tibus 074 — Gestionnaire gare : guichet = perçu en caisse, réservations = à payer
-- =============================================================================
-- PRÉREQUIS : 073_gare_manager_counter_revenue.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION public.resolve_sale_gare_id(
  p_created_by uuid,
  p_reservation_id uuid,
  p_sale_channel text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gare_id uuid;
  v_channel text := COALESCE(NULLIF(BTRIM(p_sale_channel), ''), 'traveler');
BEGIN
  IF v_channel = 'counter_sale' THEN
    RETURN public.resolve_counter_sale_gare_id(p_created_by, p_reservation_id);
  END IF;

  SELECT pt.depart INTO v_gare_id
  FROM "Reservations" r
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  WHERE r.id = p_reservation_id;

  RETURN v_gare_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_reservationbus_gare_manager_share()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gare record;
  v_channel text;
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

  SELECT g.id, g."gestionnaireUserId", g."gestionnaireSharePct", g."companyId"
  INTO v_gare
  FROM "Gares" g
  WHERE g.id = NEW."gareSaleId";

  IF v_gare."gestionnaireUserId" IS NULL OR COALESCE(v_gare."gestionnaireSharePct", 0) <= 0 THEN
    NEW."gareManagerUserId" := NULL;
    NEW."gareManagerSharePct" := NULL;
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  NEW."gareManagerUserId" := v_gare."gestionnaireUserId";
  NEW."gareManagerSharePct" := v_gare."gestionnaireSharePct";
  NEW."gareManagerShareAmount" := ROUND(
    (COALESCE(NEW.price, 0) * v_gare."gestionnaireSharePct" / 100)::numeric
  )::double precision;

  IF NEW."gareManagerShareAmount" <= 0 THEN
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  -- Guichet : le gestionnaire encaisse déjà → commission considérée perçue
  IF v_channel = 'counter_sale' THEN
    NEW."gareManagerShareStatus" := 'collected';
    RETURN NEW;
  END IF;

  -- Réservations : la compagnie doit reverser la commission
  IF NEW."gareManagerShareStatus" IN ('collected') THEN
    NEW."gareManagerShareStatus" := 'pending';
  ELSE
    NEW."gareManagerShareStatus" := COALESCE(NEW."gareManagerShareStatus", 'pending');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reservationbus_gare_manager_share_set ON "ReservationBus";
CREATE TRIGGER reservationbus_gare_manager_share_set
  BEFORE INSERT OR UPDATE OF price, "saleChannel", "createdBy", "reservationId"
  ON "ReservationBus"
  FOR EACH ROW
  EXECUTE FUNCTION public.set_reservationbus_gare_manager_share();

-- Backfill : guichet → collected, réservations → recalcul
UPDATE "ReservationBus" rb
SET "gareManagerShareStatus" = 'collected'
WHERE rb."type" = 'voyage'
  AND COALESCE(rb."saleChannel", 'traveler') = 'counter_sale'
  AND rb."gareManagerShareAmount" IS NOT NULL
  AND COALESCE(rb."gareManagerShareStatus", 'pending') <> 'collected';

UPDATE "ReservationBus" rb
SET price = rb.price
WHERE rb."type" = 'voyage'
  AND COALESCE(rb."saleChannel", 'traveler') IN ('traveler', 'seller_reservation');

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
      COALESCE(g."gestionnaireSharePct", 0) AS share_pct,
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
    GROUP BY g.id, g.name, g."gestionnaireUserId", u."firstName", u."lastName", g."gestionnaireSharePct"
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'gareId', bg.gare_id,
      'gareName', bg.gare_name,
      'managerUserId', bg.manager_id,
      'managerName', NULLIF(bg.manager_name, ''),
      'sharePct', bg.share_pct,
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

CREATE OR REPLACE FUNCTION public.mark_gare_manager_shares_paid(
  p_gare_id uuid,
  p_booking_ids uuid[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_count integer;
BEGIN
  SELECT g."companyId" INTO v_company_id FROM "Gares" g WHERE g.id = p_gare_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Gare introuvable'; END IF;

  IF NOT public.is_super_admin() AND NOT public.has_company_role(v_company_id, ARRAY['owner', 'comptable_compagnie']) THEN
    RAISE EXCEPTION 'Action reservee au proprietaire ou comptable';
  END IF;

  UPDATE "ReservationBus" rb
  SET
    "gareManagerShareStatus" = 'paid',
    "gareManagerSharePaidAt" = now()
  WHERE rb."gareSaleId" = p_gare_id
    AND rb."gareManagerShareStatus" = 'pending'
    AND COALESCE(rb."saleChannel", 'traveler') IN ('traveler', 'seller_reservation')
    AND (p_booking_ids IS NULL OR rb.id = ANY(p_booking_ids));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_sale_gare_id(uuid, uuid, text) TO authenticated;
