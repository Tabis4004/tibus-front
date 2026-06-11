-- =============================================================================
-- Tibus 073 — Part gestionnaire gare sur ventes guichet (counter_sale)
-- =============================================================================

-- Configuration par gare (définie par le owner)
ALTER TABLE "Gares"
  ADD COLUMN IF NOT EXISTS "gestionnaireUserId" uuid REFERENCES "Users" (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS "gestionnaireSharePct" double precision NOT NULL DEFAULT 0;

ALTER TABLE "Gares" DROP CONSTRAINT IF EXISTS gares_gestionnaire_share_pct_check;
ALTER TABLE "Gares" ADD CONSTRAINT gares_gestionnaire_share_pct_check
  CHECK ("gestionnaireSharePct" >= 0 AND "gestionnaireSharePct" <= 100);

-- Colonnes de part sur billet (guichet uniquement)
ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "gareSaleId" uuid REFERENCES "Gares" (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS "gareManagerUserId" uuid REFERENCES "Users" (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS "gareManagerSharePct" double precision,
  ADD COLUMN IF NOT EXISTS "gareManagerShareAmount" double precision,
  ADD COLUMN IF NOT EXISTS "gareManagerShareStatus" text,
  ADD COLUMN IF NOT EXISTS "gareManagerSharePaidAt" timestamptz;

CREATE INDEX IF NOT EXISTS reservationbus_gare_manager_share_idx
  ON "ReservationBus" ("gareSaleId", "gareManagerShareStatus")
  WHERE "gareManagerShareAmount" IS NOT NULL;

-- Rôle gestionnaire gare (compagnie)
INSERT INTO "Role" ("name", "scope", "level", "isSystem", "description", "droits") VALUES
  ('gestionnaire_gare', 'company', 22, true, 'Gestionnaire de gare — part sur ventes guichet', ARRAY[
    'sell_tickets', 'view_bookings', 'view_reports'
  ])
ON CONFLICT ("name") DO UPDATE SET
  "scope" = EXCLUDED."scope",
  "level" = EXCLUDED."level",
  "description" = EXCLUDED."description",
  "droits" = EXCLUDED."droits";

INSERT INTO "RoleAssignmentRules" ("assignerRoleId", "assignableRoleId")
SELECT a.id, b.id FROM "Role" a CROSS JOIN "Role" b
WHERE a.name = 'owner' AND b.name = 'gestionnaire_gare'
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.resolve_counter_sale_gare_id(
  p_created_by uuid,
  p_reservation_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gare_id uuid;
  v_company_id uuid;
BEGIN
  v_company_id := public.reservation_company_id(p_reservation_id);

  IF p_created_by IS NOT NULL AND v_company_id IS NOT NULL THEN
    SELECT c.gare_id INTO v_gare_id
    FROM caisses_gares c
    WHERE c.gestionnaire_id = p_created_by
      AND c.statut IN ('ouverte', 'en_reversement')
    ORDER BY c.opened_at DESC
    LIMIT 1;

    IF v_gare_id IS NOT NULL THEN
      RETURN v_gare_id;
    END IF;
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
BEGIN
  IF NEW."type" <> 'voyage' OR COALESCE(NEW."saleChannel", 'traveler') <> 'counter_sale' THEN
    NEW."gareSaleId" := NULL;
    NEW."gareManagerUserId" := NULL;
    NEW."gareManagerSharePct" := NULL;
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
    RETURN NEW;
  END IF;

  NEW."gareSaleId" := public.resolve_counter_sale_gare_id(NEW."createdBy", NEW."reservationId");

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
  NEW."gareManagerShareStatus" := CASE
    WHEN NEW."gareManagerShareAmount" > 0 THEN COALESCE(NEW."gareManagerShareStatus", 'pending')
    ELSE NULL
  END;

  IF NEW."gareManagerShareAmount" <= 0 THEN
    NEW."gareManagerShareAmount" := NULL;
    NEW."gareManagerShareStatus" := NULL;
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

-- Owner : configurer gestionnaire + % sur une gare
CREATE OR REPLACE FUNCTION public.set_gare_manager_revenue_share(
  p_gare_id uuid,
  p_share_pct double precision,
  p_gestionnaire_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_pct double precision;
BEGIN
  v_pct := GREATEST(0, LEAST(COALESCE(p_share_pct, 0), 100));

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
    "gestionnaireSharePct" = v_pct,
    "gestionnaireUserId" = p_gestionnaire_user_id
  WHERE id = p_gare_id;

  RETURN jsonb_build_object('gareId', p_gare_id, 'sharePct', v_pct, 'gestionnaireUserId', p_gestionnaire_user_id);
END;
$$;

-- Résumé parts guichet (owner ou gestionnaire)
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
      rb."gareSaleId",
      rb."gareManagerUserId",
      rb."gareManagerShareAmount",
      rb."gareManagerShareStatus",
      rb."gareManagerSharePct"
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
  JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    WHERE g."companyId" = v_company_id
      AND rb."type" = 'voyage'
      AND rb."saleChannel" = 'counter_sale'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued'
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
      COALESCE(SUM(t.price), 0)::double precision AS counter_sales_gmv,
      COALESCE(SUM(t."gareManagerShareAmount"), 0)::double precision AS total_share,
      COALESCE(SUM(t."gareManagerShareAmount") FILTER (WHERE t."gareManagerShareStatus" = 'paid'), 0)::double precision AS paid_total,
      COALESCE(SUM(t."gareManagerShareAmount") FILTER (WHERE t."gareManagerShareStatus" = 'pending'), 0)::double precision AS pending_total
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
      'totalShareAmount', bg.total_share,
      'paidTotal', bg.paid_total,
      'pendingTotal', bg.pending_total
    ) ORDER BY bg.gare_name
  ), '[]'::jsonb) INTO v_rows
  FROM by_gare bg;

  SELECT jsonb_build_object(
    'counterSalesGmv', COALESCE(SUM((elem->>'counterSalesGmv')::double precision), 0),
    'totalShareAmount', COALESCE(SUM((elem->>'totalShareAmount')::double precision), 0),
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
    AND (p_booking_ids IS NULL OR rb.id = ANY(p_booking_ids));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_counter_sale_gare_id(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_gare_manager_revenue_share(uuid, double precision, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_gare_manager_counter_revenue_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_gare_manager_shares_paid(uuid, uuid[]) TO authenticated;

-- Étendre assignation équipe owner
CREATE OR REPLACE FUNCTION public.assign_company_user_role_by_email(
  p_email text,
  p_role_name text DEFAULT 'vendeur'
)
RETURNS TABLE (id uuid, "firstName" varchar, "lastName" varchar, email varchar)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company_id uuid; v_owner_user_id uuid; v_target_user_id uuid; v_role_id uuid;
BEGIN
  v_company_id := public.current_owner_company_id();
  v_owner_user_id := public.current_app_user_id();
  IF v_company_id IS NULL OR v_owner_user_id IS NULL THEN RAISE EXCEPTION 'Compagnie owner introuvable'; END IF;
  IF p_role_name NOT IN ('vendeur', 'controleur', 'comptable_compagnie', 'gestionnaire_gare') THEN
    RAISE EXCEPTION 'Role compagnie non autorise : %', p_role_name;
  END IF;
  SELECT r.id INTO v_role_id FROM "Role" r WHERE r.name = p_role_name AND r.scope = 'company' LIMIT 1;
  IF v_role_id IS NULL THEN RAISE EXCEPTION 'Role introuvable : %', p_role_name; END IF;
  SELECT u.id INTO v_target_user_id FROM "Users" u WHERE lower(u.email) = lower(trim(p_email)) LIMIT 1;
  IF v_target_user_id IS NULL THEN RAISE EXCEPTION 'Aucun utilisateur inscrit avec cet email'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_owner_user_id AND ur."companyId" = v_company_id AND r.name = 'owner'
  ) THEN RAISE EXCEPTION 'Action reservee au proprietaire'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur WHERE ur."userId" = v_target_user_id AND ur."roleId" = v_role_id AND ur."companyId" = v_company_id
  ) THEN
    INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId", "assignedBy")
    VALUES (v_role_id, v_target_user_id, v_company_id, NULL, v_owner_user_id);
  END IF;
  RETURN QUERY SELECT u.id, u."firstName", u."lastName", u.email FROM "Users" u WHERE u.id = v_target_user_id LIMIT 1;
END; $$;

CREATE OR REPLACE FUNCTION public.list_owner_team_members(p_company_id uuid DEFAULT NULL)
RETURNS TABLE (user_id uuid, "firstName" varchar, "lastName" varchar, email varchar, role_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Compagnie owner introuvable'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = public.current_app_user_id() AND ur."companyId" = v_company_id AND r.name = 'owner'
  ) AND NOT public.is_super_admin() THEN RAISE EXCEPTION 'Action reservee au proprietaire'; END IF;
  RETURN QUERY
  SELECT u.id, u."firstName", u."lastName", u.email, r.name
  FROM "UserRoles" ur JOIN "Role" r ON r.id = ur."roleId" JOIN "Users" u ON u.id = ur."userId"
  WHERE ur."companyId" = v_company_id AND r.name IN ('vendeur', 'comptable_compagnie', 'controleur', 'gestionnaire_gare')
  ORDER BY u."lastName", u."firstName", r.name;
END; $$;
