-- Lot 42: Fidélisation voyageurs (points par compagnie).

CREATE TABLE IF NOT EXISTS "CompanyLoyaltySettings" (
  "companyId" uuid PRIMARY KEY REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "isActive" boolean NOT NULL DEFAULT false,
  "spendUnitAmount" double precision NOT NULL DEFAULT 1000,
  "pointsPerSpendUnit" integer NOT NULL DEFAULT 1,
  "discountPerPoint" double precision NOT NULL DEFAULT 50,
  "minRedeemPoints" integer NOT NULL DEFAULT 10,
  "maxRedeemPercent" double precision NOT NULL DEFAULT 50,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users" ("id") ON DELETE SET NULL,
  CONSTRAINT "CompanyLoyaltySettings_spend_unit_check" CHECK ("spendUnitAmount" > 0),
  CONSTRAINT "CompanyLoyaltySettings_points_per_unit_check" CHECK ("pointsPerSpendUnit" > 0),
  CONSTRAINT "CompanyLoyaltySettings_discount_per_point_check" CHECK ("discountPerPoint" > 0),
  CONSTRAINT "CompanyLoyaltySettings_min_redeem_check" CHECK ("minRedeemPoints" >= 0),
  CONSTRAINT "CompanyLoyaltySettings_max_redeem_percent_check"
    CHECK ("maxRedeemPercent" >= 0 AND "maxRedeemPercent" <= 100)
);

CREATE TABLE IF NOT EXISTS "TravelerLoyaltyBalance" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "userId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "pointsBalance" integer NOT NULL DEFAULT 0,
  "lifetimeEarned" integer NOT NULL DEFAULT 0,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "TravelerLoyaltyBalance_points_balance_check" CHECK ("pointsBalance" >= 0),
  CONSTRAINT "TravelerLoyaltyBalance_lifetime_earned_check" CHECK ("lifetimeEarned" >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS "TravelerLoyaltyBalance_user_company_key"
  ON "TravelerLoyaltyBalance" ("userId", "companyId");

CREATE TABLE IF NOT EXISTS "LoyaltyPointLedger" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "userId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "bookingId" uuid REFERENCES "ReservationBus" ("id") ON DELETE SET NULL,
  "entryType" text NOT NULL,
  "pointsDelta" integer NOT NULL,
  "balanceAfter" integer NOT NULL,
  "note" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "LoyaltyPointLedger_entry_type_check"
    CHECK ("entryType" IN ('earn', 'redeem', 'adjust'))
);

CREATE INDEX IF NOT EXISTS "LoyaltyPointLedger_user_company_idx"
  ON "LoyaltyPointLedger" ("userId", "companyId", "createdAt" DESC);

ALTER TABLE "CompanyLoyaltySettings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "TravelerLoyaltyBalance" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "LoyaltyPointLedger" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_loyalty_settings_select" ON "CompanyLoyaltySettings";
CREATE POLICY "company_loyalty_settings_select" ON "CompanyLoyaltySettings"
  FOR SELECT TO authenticated
  USING (public.is_company_role_user(public.current_app_user_id(), "companyId") OR public.is_super_admin());

DROP POLICY IF EXISTS "company_loyalty_settings_write" ON "CompanyLoyaltySettings";
CREATE POLICY "company_loyalty_settings_write" ON "CompanyLoyaltySettings"
  FOR ALL TO authenticated
  USING (public.has_company_role("companyId", ARRAY['owner']) OR public.is_super_admin())
  WITH CHECK (public.has_company_role("companyId", ARRAY['owner']) OR public.is_super_admin());

DROP POLICY IF EXISTS "traveler_loyalty_balance_select" ON "TravelerLoyaltyBalance";
CREATE POLICY "traveler_loyalty_balance_select" ON "TravelerLoyaltyBalance"
  FOR SELECT TO authenticated
  USING (
    "userId" = public.current_app_user_id()
    OR public.is_company_role_user(public.current_app_user_id(), "companyId")
    OR public.is_super_admin()
  );

DROP POLICY IF EXISTS "loyalty_ledger_select" ON "LoyaltyPointLedger";
CREATE POLICY "loyalty_ledger_select" ON "LoyaltyPointLedger"
  FOR SELECT TO authenticated
  USING (
    "userId" = public.current_app_user_id()
    OR public.is_company_role_user(public.current_app_user_id(), "companyId")
    OR public.is_super_admin()
  );

CREATE OR REPLACE FUNCTION public.get_company_loyalty_settings(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row "CompanyLoyaltySettings"%ROWTYPE;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), p_company_id)
  ) THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  SELECT * INTO v_row
  FROM "CompanyLoyaltySettings"
  WHERE "companyId" = p_company_id;

  IF v_row."companyId" IS NULL THEN
    RETURN jsonb_build_object(
      'companyId', p_company_id,
      'isActive', false,
      'spendUnitAmount', 1000,
      'pointsPerSpendUnit', 1,
      'discountPerPoint', 50,
      'minRedeemPoints', 10,
      'maxRedeemPercent', 50
    );
  END IF;

  RETURN jsonb_build_object(
    'companyId', v_row."companyId",
    'isActive', v_row."isActive",
    'spendUnitAmount', v_row."spendUnitAmount",
    'pointsPerSpendUnit', v_row."pointsPerSpendUnit",
    'discountPerPoint', v_row."discountPerPoint",
    'minRedeemPoints', v_row."minRedeemPoints",
    'maxRedeemPercent', v_row."maxRedeemPercent",
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_company_loyalty_settings(
  p_company_id uuid,
  p_is_active boolean,
  p_spend_unit_amount double precision,
  p_points_per_spend_unit integer,
  p_discount_per_point double precision,
  p_min_redeem_points integer,
  p_max_redeem_percent double precision
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.has_company_role(p_company_id, ARRAY['owner']) OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_spend_unit_amount <= 0 OR p_points_per_spend_unit <= 0 OR p_discount_per_point <= 0 THEN
    RAISE EXCEPTION 'Paramètres invalides';
  END IF;
  IF p_min_redeem_points < 0 OR p_max_redeem_percent < 0 OR p_max_redeem_percent > 100 THEN
    RAISE EXCEPTION 'Paramètres invalides';
  END IF;

  INSERT INTO "CompanyLoyaltySettings" (
    "companyId", "isActive", "spendUnitAmount", "pointsPerSpendUnit",
    "discountPerPoint", "minRedeemPoints", "maxRedeemPercent", "updatedBy", "updatedAt"
  )
  VALUES (
    p_company_id, COALESCE(p_is_active, false), p_spend_unit_amount, p_points_per_spend_unit,
    p_discount_per_point, p_min_redeem_points, p_max_redeem_percent, v_user_id, now()
  )
  ON CONFLICT ("companyId") DO UPDATE
  SET
    "isActive" = EXCLUDED."isActive",
    "spendUnitAmount" = EXCLUDED."spendUnitAmount",
    "pointsPerSpendUnit" = EXCLUDED."pointsPerSpendUnit",
    "discountPerPoint" = EXCLUDED."discountPerPoint",
    "minRedeemPoints" = EXCLUDED."minRedeemPoints",
    "maxRedeemPercent" = EXCLUDED."maxRedeemPercent",
    "updatedBy" = v_user_id,
    "updatedAt" = now();

  RETURN public.get_company_loyalty_settings(p_company_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_traveler_loyalty_context(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_settings "CompanyLoyaltySettings"%ROWTYPE;
  v_balance integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('active', false, 'pointsBalance', 0);
  END IF;

  SELECT * INTO v_settings FROM "CompanyLoyaltySettings" WHERE "companyId" = p_company_id;
  IF v_settings."companyId" IS NULL OR NOT v_settings."isActive" THEN
    RETURN jsonb_build_object('active', false, 'pointsBalance', 0);
  END IF;

  SELECT COALESCE(tlb."pointsBalance", 0)
  INTO v_balance
  FROM "TravelerLoyaltyBalance" tlb
  WHERE tlb."userId" = v_user_id AND tlb."companyId" = p_company_id;

  RETURN jsonb_build_object(
    'active', true,
    'pointsBalance', COALESCE(v_balance, 0),
    'spendUnitAmount', v_settings."spendUnitAmount",
    'pointsPerSpendUnit', v_settings."pointsPerSpendUnit",
    'discountPerPoint', v_settings."discountPerPoint",
    'minRedeemPoints', v_settings."minRedeemPoints",
    'maxRedeemPercent', v_settings."maxRedeemPercent"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_loyalty_redemption(
  p_company_id uuid,
  p_ticket_price double precision,
  p_points integer,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := COALESCE(p_user_id, public.current_app_user_id());
  v_settings "CompanyLoyaltySettings"%ROWTYPE;
  v_balance integer := 0;
  v_discount double precision := 0;
  v_max_discount double precision := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Connexion requise');
  END IF;
  IF p_ticket_price <= 0 THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Montant invalide');
  END IF;
  IF COALESCE(p_points, 0) <= 0 THEN
    RETURN jsonb_build_object('valid', true, 'discountAmount', 0, 'pointsRedeemed', 0);
  END IF;

  SELECT * INTO v_settings FROM "CompanyLoyaltySettings" WHERE "companyId" = p_company_id;
  IF v_settings."companyId" IS NULL OR NOT v_settings."isActive" THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Programme fidélité inactif');
  END IF;
  IF p_points < v_settings."minRedeemPoints" THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Minimum de points non atteint');
  END IF;

  SELECT COALESCE(tlb."pointsBalance", 0)
  INTO v_balance
  FROM "TravelerLoyaltyBalance" tlb
  WHERE tlb."userId" = v_user_id AND tlb."companyId" = p_company_id;

  IF p_points > COALESCE(v_balance, 0) THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Solde de points insuffisant');
  END IF;

  v_discount := p_points * v_settings."discountPerPoint";
  v_max_discount := p_ticket_price * (v_settings."maxRedeemPercent" / 100.0);
  v_discount := LEAST(v_discount, v_max_discount, p_ticket_price);
  v_discount := GREATEST(0, ROUND(v_discount)::double precision);

  RETURN jsonb_build_object(
    'valid', true,
    'discountAmount', v_discount,
    'pointsRedeemed', p_points
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.process_loyalty_on_ticket(
  p_user_id uuid,
  p_company_id uuid,
  p_booking_id uuid,
  p_cash_paid double precision,
  p_points_redeemed integer DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings "CompanyLoyaltySettings"%ROWTYPE;
  v_balance_row "TravelerLoyaltyBalance"%ROWTYPE;
  v_points_earned integer := 0;
  v_new_balance integer := 0;
  v_redeem integer := GREATEST(COALESCE(p_points_redeemed, 0), 0);
BEGIN
  SELECT * INTO v_settings FROM "CompanyLoyaltySettings" WHERE "companyId" = p_company_id;
  IF v_settings."companyId" IS NULL OR NOT v_settings."isActive" THEN
    RETURN;
  END IF;

  SELECT * INTO v_balance_row
  FROM "TravelerLoyaltyBalance"
  WHERE "userId" = p_user_id AND "companyId" = p_company_id
  FOR UPDATE;

  IF v_balance_row."id" IS NULL THEN
    INSERT INTO "TravelerLoyaltyBalance" ("userId", "companyId", "pointsBalance", "lifetimeEarned")
    VALUES (p_user_id, p_company_id, 0, 0)
    RETURNING * INTO v_balance_row;
  END IF;

  IF v_redeem > 0 THEN
    IF v_redeem > v_balance_row."pointsBalance" THEN
      RAISE EXCEPTION 'Solde de points insuffisant';
    END IF;
    v_new_balance := v_balance_row."pointsBalance" - v_redeem;
    UPDATE "TravelerLoyaltyBalance"
    SET "pointsBalance" = v_new_balance, "updatedAt" = now()
    WHERE "id" = v_balance_row."id";

    INSERT INTO "LoyaltyPointLedger" (
      "userId", "companyId", "bookingId", "entryType", "pointsDelta", "balanceAfter", "note"
    )
    VALUES (
      p_user_id, p_company_id, p_booking_id, 'redeem', -v_redeem, v_new_balance,
      'Utilisation points billet'
    );

    SELECT * INTO v_balance_row FROM "TravelerLoyaltyBalance" WHERE "id" = v_balance_row."id";
  END IF;

  IF p_cash_paid > 0 AND v_settings."spendUnitAmount" > 0 THEN
    v_points_earned := FLOOR(p_cash_paid / v_settings."spendUnitAmount")::integer * v_settings."pointsPerSpendUnit";
  END IF;

  IF v_points_earned > 0 THEN
    v_new_balance := v_balance_row."pointsBalance" + v_points_earned;
    UPDATE "TravelerLoyaltyBalance"
    SET
      "pointsBalance" = v_new_balance,
      "lifetimeEarned" = "lifetimeEarned" + v_points_earned,
      "updatedAt" = now()
    WHERE "id" = v_balance_row."id";

    INSERT INTO "LoyaltyPointLedger" (
      "userId", "companyId", "bookingId", "entryType", "pointsDelta", "balanceAfter", "note"
    )
    VALUES (
      p_user_id, p_company_id, p_booking_id, 'earn', v_points_earned, v_new_balance,
      'Points gagnés sur billet'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_loyalty_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_company_loyalty_settings(uuid, boolean, double precision, integer, double precision, integer, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_traveler_loyalty_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_loyalty_redemption(uuid, double precision, integer, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_loyalty_on_ticket(uuid, uuid, uuid, double precision, integer) TO service_role;
