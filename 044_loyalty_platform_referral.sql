-- Lot 44: Fidélité plateforme (parrainage + points Tibus) et liaison compagnie par téléphone/email.

-- ---------------------------------------------------------------------------
-- Users: parrainage
-- ---------------------------------------------------------------------------

ALTER TABLE "Users"
  ADD COLUMN IF NOT EXISTS "referralCode" varchar,
  ADD COLUMN IF NOT EXISTS "referredByUserId" uuid REFERENCES "Users" ("id") ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "Users_referral_code_key"
  ON "Users" ("referralCode")
  WHERE "referralCode" IS NOT NULL;

CREATE INDEX IF NOT EXISTS "Users_referred_by_idx"
  ON "Users" ("referredByUserId")
  WHERE "referredByUserId" IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Tables plateforme
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "PlatformLoyaltySettings" (
  "scope" text PRIMARY KEY DEFAULT 'platform',
  "isActive" boolean NOT NULL DEFAULT false,
  "spendUnitAmount" double precision NOT NULL DEFAULT 1000,
  "pointsPerSpendUnit" integer NOT NULL DEFAULT 1,
  "discountPerPoint" double precision NOT NULL DEFAULT 50,
  "minRedeemPoints" integer NOT NULL DEFAULT 10,
  "maxRedeemPercent" double precision NOT NULL DEFAULT 50,
  "referralSignupReferrerPoints" integer NOT NULL DEFAULT 50,
  "referralSignupNewUserPoints" integer NOT NULL DEFAULT 0,
  "referralSharePoints" integer NOT NULL DEFAULT 5,
  "referralShareDailyLimit" integer NOT NULL DEFAULT 3,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users" ("id") ON DELETE SET NULL,
  CONSTRAINT "PlatformLoyaltySettings_scope_check" CHECK ("scope" = 'platform'),
  CONSTRAINT "PlatformLoyaltySettings_spend_unit_check" CHECK ("spendUnitAmount" > 0),
  CONSTRAINT "PlatformLoyaltySettings_points_per_unit_check" CHECK ("pointsPerSpendUnit" > 0),
  CONSTRAINT "PlatformLoyaltySettings_discount_per_point_check" CHECK ("discountPerPoint" > 0),
  CONSTRAINT "PlatformLoyaltySettings_min_redeem_check" CHECK ("minRedeemPoints" >= 0),
  CONSTRAINT "PlatformLoyaltySettings_max_redeem_percent_check"
    CHECK ("maxRedeemPercent" >= 0 AND "maxRedeemPercent" <= 100),
  CONSTRAINT "PlatformLoyaltySettings_referral_signup_referrer_check"
    CHECK ("referralSignupReferrerPoints" >= 0),
  CONSTRAINT "PlatformLoyaltySettings_referral_signup_new_user_check"
    CHECK ("referralSignupNewUserPoints" >= 0),
  CONSTRAINT "PlatformLoyaltySettings_referral_share_points_check"
    CHECK ("referralSharePoints" >= 0),
  CONSTRAINT "PlatformLoyaltySettings_referral_share_daily_limit_check"
    CHECK ("referralShareDailyLimit" >= 0)
);

CREATE TABLE IF NOT EXISTS "PlatformLoyaltyBalance" (
  "userId" uuid PRIMARY KEY REFERENCES "Users" ("id") ON DELETE CASCADE,
  "pointsBalance" integer NOT NULL DEFAULT 0,
  "lifetimeEarned" integer NOT NULL DEFAULT 0,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "PlatformLoyaltyBalance_points_balance_check" CHECK ("pointsBalance" >= 0),
  CONSTRAINT "PlatformLoyaltyBalance_lifetime_earned_check" CHECK ("lifetimeEarned" >= 0)
);

CREATE TABLE IF NOT EXISTS "PlatformLoyaltyLedger" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "userId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "companyId" uuid REFERENCES "Companies" ("id") ON DELETE SET NULL,
  "bookingId" uuid REFERENCES "ReservationBus" ("id") ON DELETE SET NULL,
  "relatedUserId" uuid REFERENCES "Users" ("id") ON DELETE SET NULL,
  "entryType" text NOT NULL,
  "pointsDelta" integer NOT NULL,
  "balanceAfter" integer NOT NULL,
  "note" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "PlatformLoyaltyLedger_entry_type_check"
    CHECK ("entryType" IN ('earn', 'redeem', 'adjust', 'referral_signup', 'referral_share'))
);

CREATE INDEX IF NOT EXISTS "PlatformLoyaltyLedger_user_created_idx"
  ON "PlatformLoyaltyLedger" ("userId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "ReferralShareDaily" (
  "userId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "shareDate" date NOT NULL DEFAULT (timezone('utc', now()))::date,
  "shareCount" integer NOT NULL DEFAULT 0,
  PRIMARY KEY ("userId", "shareDate"),
  CONSTRAINT "ReferralShareDaily_share_count_check" CHECK ("shareCount" >= 0)
);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

ALTER TABLE "PlatformLoyaltySettings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PlatformLoyaltyBalance" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PlatformLoyaltyLedger" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ReferralShareDaily" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform_loyalty_settings_select" ON "PlatformLoyaltySettings";
CREATE POLICY "platform_loyalty_settings_select" ON "PlatformLoyaltySettings"
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "platform_loyalty_settings_write" ON "PlatformLoyaltySettings";
CREATE POLICY "platform_loyalty_settings_write" ON "PlatformLoyaltySettings"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "platform_loyalty_balance_select" ON "PlatformLoyaltyBalance";
CREATE POLICY "platform_loyalty_balance_select" ON "PlatformLoyaltyBalance"
  FOR SELECT TO authenticated
  USING (
    "userId" = public.current_app_user_id()
    OR public.is_super_admin()
  );

DROP POLICY IF EXISTS "platform_loyalty_ledger_select" ON "PlatformLoyaltyLedger";
CREATE POLICY "platform_loyalty_ledger_select" ON "PlatformLoyaltyLedger"
  FOR SELECT TO authenticated
  USING (
    "userId" = public.current_app_user_id()
    OR public.is_super_admin()
  );

DROP POLICY IF EXISTS "referral_share_daily_select" ON "ReferralShareDaily";
CREATE POLICY "referral_share_daily_select" ON "ReferralShareDaily"
  FOR SELECT TO authenticated
  USING (
    "userId" = public.current_app_user_id()
    OR public.is_super_admin()
  );

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_phone_digits(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g'), '');
$$;

CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_attempt integer := 0;
BEGIN
  LOOP
    v_attempt := v_attempt + 1;
    IF v_attempt > 50 THEN
      RAISE EXCEPTION 'Impossible de générer un code parrain';
    END IF;
    v_code := upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM "Users" u WHERE u."referralCode" = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_user_referral_code(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT u."referralCode" INTO v_code FROM "Users" u WHERE u.id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  IF v_code IS NOT NULL AND btrim(v_code) <> '' THEN
    RETURN v_code;
  END IF;

  v_code := public.generate_referral_code();
  UPDATE "Users" SET "referralCode" = v_code WHERE id = p_user_id;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_user_by_phone_or_email(
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone_digits text := public.normalize_phone_digits(p_phone);
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_user_id uuid;
BEGIN
  IF v_email <> '' THEN
    SELECT u.id INTO v_user_id
    FROM "Users" u
    WHERE lower(btrim(COALESCE(u.email, ''))) = v_email
    LIMIT 1;
    IF v_user_id IS NOT NULL THEN
      RETURN v_user_id;
    END IF;
  END IF;

  IF v_phone_digits IS NOT NULL THEN
    SELECT u.id INTO v_user_id
    FROM "Users" u
    WHERE public.normalize_phone_digits(u.phone) = v_phone_digits
    LIMIT 1;
    RETURN v_user_id;
  END IF;

  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC paramétrage plateforme
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_platform_loyalty_settings()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row "PlatformLoyaltySettings"%ROWTYPE;
BEGIN
  IF NOT (public.is_super_admin() OR public.current_app_user_id() IS NOT NULL) THEN
    RAISE EXCEPTION 'Connexion requise';
  END IF;

  SELECT * INTO v_row FROM "PlatformLoyaltySettings" WHERE "scope" = 'platform';

  IF v_row."scope" IS NULL THEN
    RETURN jsonb_build_object(
      'scope', 'platform',
      'isActive', false,
      'spendUnitAmount', 1000,
      'pointsPerSpendUnit', 1,
      'discountPerPoint', 50,
      'minRedeemPoints', 10,
      'maxRedeemPercent', 50,
      'referralSignupReferrerPoints', 50,
      'referralSignupNewUserPoints', 0,
      'referralSharePoints', 5,
      'referralShareDailyLimit', 3
    );
  END IF;

  RETURN jsonb_build_object(
    'scope', v_row."scope",
    'isActive', v_row."isActive",
    'spendUnitAmount', v_row."spendUnitAmount",
    'pointsPerSpendUnit', v_row."pointsPerSpendUnit",
    'discountPerPoint', v_row."discountPerPoint",
    'minRedeemPoints', v_row."minRedeemPoints",
    'maxRedeemPercent', v_row."maxRedeemPercent",
    'referralSignupReferrerPoints', v_row."referralSignupReferrerPoints",
    'referralSignupNewUserPoints', v_row."referralSignupNewUserPoints",
    'referralSharePoints', v_row."referralSharePoints",
    'referralShareDailyLimit', v_row."referralShareDailyLimit",
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_platform_loyalty_settings(
  p_is_active boolean,
  p_spend_unit_amount double precision,
  p_points_per_spend_unit integer,
  p_discount_per_point double precision,
  p_min_redeem_points integer,
  p_max_redeem_percent double precision,
  p_referral_signup_referrer_points integer,
  p_referral_signup_new_user_points integer,
  p_referral_share_points integer,
  p_referral_share_daily_limit integer
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
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_spend_unit_amount <= 0 OR p_points_per_spend_unit <= 0 OR p_discount_per_point <= 0 THEN
    RAISE EXCEPTION 'Paramètres invalides';
  END IF;
  IF p_min_redeem_points < 0 OR p_max_redeem_percent < 0 OR p_max_redeem_percent > 100 THEN
    RAISE EXCEPTION 'Paramètres invalides';
  END IF;
  IF COALESCE(p_referral_signup_referrer_points, 0) < 0
     OR COALESCE(p_referral_signup_new_user_points, 0) < 0
     OR COALESCE(p_referral_share_points, 0) < 0
     OR COALESCE(p_referral_share_daily_limit, 0) < 0 THEN
    RAISE EXCEPTION 'Paramètres parrainage invalides';
  END IF;

  INSERT INTO "PlatformLoyaltySettings" (
    "scope", "isActive", "spendUnitAmount", "pointsPerSpendUnit",
    "discountPerPoint", "minRedeemPoints", "maxRedeemPercent",
    "referralSignupReferrerPoints", "referralSignupNewUserPoints",
    "referralSharePoints", "referralShareDailyLimit",
    "updatedBy", "updatedAt"
  )
  VALUES (
    'platform', COALESCE(p_is_active, false), p_spend_unit_amount, p_points_per_spend_unit,
    p_discount_per_point, p_min_redeem_points, p_max_redeem_percent,
    COALESCE(p_referral_signup_referrer_points, 0), COALESCE(p_referral_signup_new_user_points, 0),
    COALESCE(p_referral_share_points, 0), COALESCE(p_referral_share_daily_limit, 0),
    v_user_id, now()
  )
  ON CONFLICT ("scope") DO UPDATE
  SET
    "isActive" = EXCLUDED."isActive",
    "spendUnitAmount" = EXCLUDED."spendUnitAmount",
    "pointsPerSpendUnit" = EXCLUDED."pointsPerSpendUnit",
    "discountPerPoint" = EXCLUDED."discountPerPoint",
    "minRedeemPoints" = EXCLUDED."minRedeemPoints",
    "maxRedeemPercent" = EXCLUDED."maxRedeemPercent",
    "referralSignupReferrerPoints" = EXCLUDED."referralSignupReferrerPoints",
    "referralSignupNewUserPoints" = EXCLUDED."referralSignupNewUserPoints",
    "referralSharePoints" = EXCLUDED."referralSharePoints",
    "referralShareDailyLimit" = EXCLUDED."referralShareDailyLimit",
    "updatedBy" = v_user_id,
    "updatedAt" = now();

  RETURN public.get_platform_loyalty_settings();
END;
$$;

CREATE OR REPLACE FUNCTION public._platform_loyalty_credit(
  p_user_id uuid,
  p_entry_type text,
  p_points integer,
  p_booking_id uuid DEFAULT NULL,
  p_company_id uuid DEFAULT NULL,
  p_related_user_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance_row "PlatformLoyaltyBalance"%ROWTYPE;
  v_new_balance integer;
  v_points integer := COALESCE(p_points, 0);
BEGIN
  IF p_user_id IS NULL OR v_points = 0 THEN
    RETURN COALESCE((
      SELECT plb."pointsBalance" FROM "PlatformLoyaltyBalance" plb WHERE plb."userId" = p_user_id
    ), 0);
  END IF;

  SELECT * INTO v_balance_row
  FROM "PlatformLoyaltyBalance"
  WHERE "userId" = p_user_id
  FOR UPDATE;

  IF v_balance_row."userId" IS NULL THEN
    INSERT INTO "PlatformLoyaltyBalance" ("userId", "pointsBalance", "lifetimeEarned")
    VALUES (p_user_id, 0, 0)
    RETURNING * INTO v_balance_row;
  END IF;

  v_new_balance := v_balance_row."pointsBalance" + v_points;
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Solde de points plateforme insuffisant';
  END IF;

  UPDATE "PlatformLoyaltyBalance"
  SET
    "pointsBalance" = v_new_balance,
    "lifetimeEarned" = CASE WHEN v_points > 0 THEN "lifetimeEarned" + v_points ELSE "lifetimeEarned" END,
    "updatedAt" = now()
  WHERE "userId" = p_user_id;

  INSERT INTO "PlatformLoyaltyLedger" (
    "userId", "companyId", "bookingId", "relatedUserId",
    "entryType", "pointsDelta", "balanceAfter", "note"
  )
  VALUES (
    p_user_id, p_company_id, p_booking_id, p_related_user_id,
    p_entry_type, v_points, v_new_balance, p_note
  );

  RETURN v_new_balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_referral_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_code text;
  v_referred_by uuid;
  v_referrer_name text;
  v_balance integer := 0;
  v_settings "PlatformLoyaltySettings"%ROWTYPE;
  v_share_count integer := 0;
  v_share_date date := (timezone('utc', now()))::date;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('authenticated', false);
  END IF;

  v_code := public.ensure_user_referral_code(v_user_id);

  SELECT u."referredByUserId" INTO v_referred_by FROM "Users" u WHERE u.id = v_user_id;

  IF v_referred_by IS NOT NULL THEN
    SELECT btrim(coalesce(ref."firstName", '') || ' ' || coalesce(ref."lastName", ''))
    INTO v_referrer_name
    FROM "Users" ref
    WHERE ref.id = v_referred_by;
  END IF;

  SELECT COALESCE(plb."pointsBalance", 0)
  INTO v_balance
  FROM "PlatformLoyaltyBalance" plb
  WHERE plb."userId" = v_user_id;

  SELECT * INTO v_settings FROM "PlatformLoyaltySettings" WHERE "scope" = 'platform';

  SELECT COALESCE(rsd."shareCount", 0)
  INTO v_share_count
  FROM "ReferralShareDaily" rsd
  WHERE rsd."userId" = v_user_id AND rsd."shareDate" = v_share_date;

  RETURN jsonb_build_object(
    'authenticated', true,
    'userId', v_user_id,
    'referralCode', v_code,
    'referredByUserId', v_referred_by,
    'referredByName', NULLIF(btrim(v_referrer_name), ''),
    'platformPointsBalance', COALESCE(v_balance, 0),
    'platformActive', COALESCE(v_settings."isActive", false),
    'referralSignupReferrerPoints', COALESCE(v_settings."referralSignupReferrerPoints", 0),
    'referralSharePoints', COALESCE(v_settings."referralSharePoints", 0),
    'referralShareDailyLimit', COALESCE(v_settings."referralShareDailyLimit", 0),
    'sharesToday', COALESCE(v_share_count, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_referral_signup(p_referral_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_code text := upper(btrim(COALESCE(p_referral_code, '')));
  v_referrer_id uuid;
  v_settings "PlatformLoyaltySettings"%ROWTYPE;
  v_referrer_balance integer;
  v_new_user_balance integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Connexion requise');
  END IF;
  IF v_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code parrain invalide');
  END IF;

  IF EXISTS (
    SELECT 1 FROM "Users" u
    WHERE u.id = v_user_id AND u."referredByUserId" IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Parrainage déjà enregistré');
  END IF;

  SELECT u.id INTO v_referrer_id
  FROM "Users" u
  WHERE upper(btrim(u."referralCode")) = v_code
  LIMIT 1;

  IF v_referrer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code parrain introuvable');
  END IF;
  IF v_referrer_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez pas utiliser votre propre code');
  END IF;

  SELECT * INTO v_settings FROM "PlatformLoyaltySettings" WHERE "scope" = 'platform';

  UPDATE "Users"
  SET "referredByUserId" = v_referrer_id
  WHERE id = v_user_id AND "referredByUserId" IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Parrainage déjà enregistré');
  END IF;

  IF COALESCE(v_settings."isActive", false) AND COALESCE(v_settings."referralSignupReferrerPoints", 0) > 0 THEN
    v_referrer_balance := public._platform_loyalty_credit(
      v_referrer_id,
      'referral_signup',
      v_settings."referralSignupReferrerPoints",
      NULL,
      NULL,
      v_user_id,
      'Parrainage inscription'
    );
  END IF;

  IF COALESCE(v_settings."isActive", false) AND COALESCE(v_settings."referralSignupNewUserPoints", 0) > 0 THEN
    v_new_user_balance := public._platform_loyalty_credit(
      v_user_id,
      'referral_signup',
      v_settings."referralSignupNewUserPoints",
      NULL,
      NULL,
      v_referrer_id,
      'Bonus inscription parrainée'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'referredByUserId', v_referrer_id,
    'referrerPointsCredited', CASE
      WHEN COALESCE(v_settings."isActive", false) THEN COALESCE(v_settings."referralSignupReferrerPoints", 0)
      ELSE 0
    END,
    'newUserPointsCredited', CASE
      WHEN COALESCE(v_settings."isActive", false) THEN COALESCE(v_settings."referralSignupNewUserPoints", 0)
      ELSE 0
    END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_referral_share()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_settings "PlatformLoyaltySettings"%ROWTYPE;
  v_share_date date := (timezone('utc', now()))::date;
  v_share_count integer := 0;
  v_daily_limit integer := 0;
  v_points integer := 0;
  v_balance integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Connexion requise');
  END IF;

  PERFORM public.ensure_user_referral_code(v_user_id);

  SELECT * INTO v_settings FROM "PlatformLoyaltySettings" WHERE "scope" = 'platform';
  IF v_settings."scope" IS NULL OR NOT v_settings."isActive" THEN
    RETURN jsonb_build_object('success', false, 'error', 'Programme plateforme inactif');
  END IF;

  v_daily_limit := COALESCE(v_settings."referralShareDailyLimit", 0);
  v_points := COALESCE(v_settings."referralSharePoints", 0);

  IF v_daily_limit <= 0 OR v_points <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Partage de parrainage désactivé');
  END IF;

  INSERT INTO "ReferralShareDaily" ("userId", "shareDate", "shareCount")
  VALUES (v_user_id, v_share_date, 0)
  ON CONFLICT ("userId", "shareDate") DO NOTHING;

  SELECT rsd."shareCount"
  INTO v_share_count
  FROM "ReferralShareDaily" rsd
  WHERE rsd."userId" = v_user_id AND rsd."shareDate" = v_share_date
  FOR UPDATE;

  IF COALESCE(v_share_count, 0) >= v_daily_limit THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Limite quotidienne de partage atteinte',
      'sharesToday', v_share_count,
      'dailyLimit', v_daily_limit
    );
  END IF;

  UPDATE "ReferralShareDaily"
  SET "shareCount" = "shareCount" + 1
  WHERE "userId" = v_user_id AND "shareDate" = v_share_date;

  v_balance := public._platform_loyalty_credit(
    v_user_id,
    'referral_share',
    v_points,
    NULL,
    NULL,
    NULL,
    'Partage lien parrainage'
  );

  RETURN jsonb_build_object(
    'success', true,
    'pointsCredited', v_points,
    'platformPointsBalance', v_balance,
    'sharesToday', COALESCE(v_share_count, 0) + 1,
    'dailyLimit', v_daily_limit
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.lookup_company_loyalty_users(
  p_company_id uuid,
  p_query text,
  p_limit integer DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_q text := btrim(COALESCE(p_query, ''));
  v_phone_digits text;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 15), 1), 30);
  v_rows jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_super_admin() OR public.is_company_role_user(v_user_id, p_company_id)) THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;
  IF char_length(v_q) < 2 THEN
    RETURN '[]'::jsonb;
  END IF;

  v_phone_digits := public.normalize_phone_digits(v_q);

  SELECT COALESCE(
    jsonb_agg(row_data ORDER BY row_data->>'label'),
    '[]'::jsonb
  )
  INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'userId', u.id,
      'firstName', u."firstName",
      'lastName', u."lastName",
      'email', u.email,
      'phone', u.phone,
      'referralCode', u."referralCode",
      'label', btrim(u."firstName" || ' ' || u."lastName")
        || CASE WHEN u.phone IS NOT NULL THEN ' · ' || u.phone ELSE '' END
        || CASE WHEN u.email IS NOT NULL THEN ' · ' || u.email ELSE '' END,
      'companyPointsBalance', COALESCE(tlb."pointsBalance", 0),
      'companyLoyaltyActive', COALESCE(cls."isActive", false)
    ) AS row_data
    FROM "Users" u
    LEFT JOIN "CompanyLoyaltySettings" cls ON cls."companyId" = p_company_id
    LEFT JOIN "TravelerLoyaltyBalance" tlb
      ON tlb."userId" = u.id AND tlb."companyId" = p_company_id
    WHERE (
      u."firstName" ILIKE '%' || v_q || '%'
      OR u."lastName" ILIKE '%' || v_q || '%'
      OR (u."firstName" || ' ' || u."lastName") ILIKE '%' || v_q || '%'
      OR lower(COALESCE(u.email, '')) LIKE '%' || lower(v_q) || '%'
      OR (
        v_phone_digits IS NOT NULL
        AND public.normalize_phone_digits(u.phone) LIKE '%' || v_phone_digits || '%'
      )
    )
    ORDER BY u."lastName", u."firstName"
    LIMIT v_limit
  ) sub;

  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_loyalty_booking_context(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_company jsonb;
  v_platform jsonb;
  v_company_settings "CompanyLoyaltySettings"%ROWTYPE;
  v_company_balance integer := 0;
  v_platform_settings "PlatformLoyaltySettings"%ROWTYPE;
  v_platform_balance integer := 0;
BEGIN
  v_company := jsonb_build_object('active', false, 'pointsBalance', 0);
  v_platform := jsonb_build_object('active', false, 'pointsBalance', 0);

  IF v_user_id IS NOT NULL THEN
    SELECT * INTO v_company_settings FROM "CompanyLoyaltySettings" WHERE "companyId" = p_company_id;
    IF v_company_settings."companyId" IS NOT NULL AND v_company_settings."isActive" THEN
      SELECT COALESCE(tlb."pointsBalance", 0)
      INTO v_company_balance
      FROM "TravelerLoyaltyBalance" tlb
      WHERE tlb."userId" = v_user_id AND tlb."companyId" = p_company_id;

      v_company := jsonb_build_object(
        'active', true,
        'pointsBalance', COALESCE(v_company_balance, 0),
        'spendUnitAmount', v_company_settings."spendUnitAmount",
        'pointsPerSpendUnit', v_company_settings."pointsPerSpendUnit",
        'discountPerPoint', v_company_settings."discountPerPoint",
        'minRedeemPoints', v_company_settings."minRedeemPoints",
        'maxRedeemPercent', v_company_settings."maxRedeemPercent"
      );
    END IF;

    SELECT * INTO v_platform_settings FROM "PlatformLoyaltySettings" WHERE "scope" = 'platform';
    IF v_platform_settings."scope" IS NOT NULL AND v_platform_settings."isActive" THEN
      SELECT COALESCE(plb."pointsBalance", 0)
      INTO v_platform_balance
      FROM "PlatformLoyaltyBalance" plb
      WHERE plb."userId" = v_user_id;

      v_platform := jsonb_build_object(
        'active', true,
        'pointsBalance', COALESCE(v_platform_balance, 0),
        'spendUnitAmount', v_platform_settings."spendUnitAmount",
        'pointsPerSpendUnit', v_platform_settings."pointsPerSpendUnit",
        'discountPerPoint', v_platform_settings."discountPerPoint",
        'minRedeemPoints', v_platform_settings."minRedeemPoints",
        'maxRedeemPercent', v_platform_settings."maxRedeemPercent"
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('company', v_company, 'platform', v_platform);
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_platform_loyalty_redemption(
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
  v_settings "PlatformLoyaltySettings"%ROWTYPE;
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

  SELECT * INTO v_settings FROM "PlatformLoyaltySettings" WHERE "scope" = 'platform';
  IF v_settings."scope" IS NULL OR NOT v_settings."isActive" THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Programme fidélité plateforme inactif');
  END IF;
  IF p_points < v_settings."minRedeemPoints" THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Minimum de points non atteint');
  END IF;

  SELECT COALESCE(plb."pointsBalance", 0)
  INTO v_balance
  FROM "PlatformLoyaltyBalance" plb
  WHERE plb."userId" = v_user_id;

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

CREATE OR REPLACE FUNCTION public.process_platform_loyalty_on_ticket(
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
  v_settings "PlatformLoyaltySettings"%ROWTYPE;
  v_balance integer := 0;
  v_points_earned integer := 0;
  v_redeem integer := GREATEST(COALESCE(p_points_redeemed, 0), 0);
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_settings FROM "PlatformLoyaltySettings" WHERE "scope" = 'platform';
  IF v_settings."scope" IS NULL OR NOT v_settings."isActive" THEN
    RETURN;
  END IF;

  IF v_redeem > 0 THEN
    v_balance := public._platform_loyalty_credit(
      p_user_id,
      'redeem',
      -v_redeem,
      p_booking_id,
      p_company_id,
      NULL,
      'Utilisation points plateforme billet'
    );
  END IF;

  IF p_cash_paid > 0 AND v_settings."spendUnitAmount" > 0 THEN
    v_points_earned := FLOOR(p_cash_paid / v_settings."spendUnitAmount")::integer * v_settings."pointsPerSpendUnit";
  END IF;

  IF v_points_earned > 0 THEN
    PERFORM public._platform_loyalty_credit(
      p_user_id,
      'earn',
      v_points_earned,
      p_booking_id,
      p_company_id,
      NULL,
      'Points plateforme gagnés sur billet'
    );
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Compagnie: bénéficiaire optionnel des points
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.process_loyalty_on_ticket(uuid, uuid, uuid, double precision, integer);

CREATE OR REPLACE FUNCTION public.process_loyalty_on_ticket(
  p_user_id uuid,
  p_company_id uuid,
  p_booking_id uuid,
  p_cash_paid double precision,
  p_points_redeemed integer DEFAULT 0,
  p_loyalty_user_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_loyalty_user_id uuid := COALESCE(p_loyalty_user_id, p_user_id);
  v_settings "CompanyLoyaltySettings"%ROWTYPE;
  v_balance_row "TravelerLoyaltyBalance"%ROWTYPE;
  v_points_earned integer := 0;
  v_new_balance integer := 0;
  v_redeem integer := GREATEST(COALESCE(p_points_redeemed, 0), 0);
BEGIN
  IF v_loyalty_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_settings FROM "CompanyLoyaltySettings" WHERE "companyId" = p_company_id;
  IF v_settings."companyId" IS NULL OR NOT v_settings."isActive" THEN
    RETURN;
  END IF;

  SELECT * INTO v_balance_row
  FROM "TravelerLoyaltyBalance"
  WHERE "userId" = v_loyalty_user_id AND "companyId" = p_company_id
  FOR UPDATE;

  IF v_balance_row."id" IS NULL THEN
    INSERT INTO "TravelerLoyaltyBalance" ("userId", "companyId", "pointsBalance", "lifetimeEarned")
    VALUES (v_loyalty_user_id, p_company_id, 0, 0)
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
      v_loyalty_user_id, p_company_id, p_booking_id, 'redeem', -v_redeem, v_new_balance,
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
      v_loyalty_user_id, p_company_id, p_booking_id, 'earn', v_points_earned, v_new_balance,
      'Points gagnés sur billet'
    );
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Vente guichet: fidélité compagnie + plateforme si voyageur identifié
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.seller_counter_sale(
  p_reservation_id uuid,
  p_passenger_name text,
  p_passenger_phone text DEFAULT NULL,
  p_seat_number text DEFAULT NULL,
  p_parcel_count integer DEFAULT 0,
  p_parcel_weight double precision DEFAULT 0,
  p_parcel_amount double precision DEFAULT 0
)
RETURNS TABLE(
  booking_id uuid,
  reference text,
  verify_token text,
  total_price double precision,
  currency text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid; v_company_id uuid; v_trajet_id uuid; v_depart uuid; v_final uuid;
  v_arret_id uuid; v_ticket_price double precision; v_parcel_amount double precision := COALESCE(p_parcel_amount, 0);
  v_total_price double precision; v_capacity integer; v_booked integer; v_payment_id uuid; v_reference text;
  v_currency text; v_seat text := NULLIF(BTRIM(COALESCE(p_seat_number, '')), '');
  v_booking_id uuid; v_caisse_id uuid; v_ticket_fcfa integer; v_parcel_fcfa integer; v_verify_token text;
  v_traveler_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF NULLIF(BTRIM(COALESCE(p_passenger_name, '')), '') IS NULL THEN RAISE EXCEPTION 'Nom voyageur requis'; END IF;

  SELECT r."capacity", r."trajetId" INTO v_capacity, v_trajet_id FROM "Reservations" r WHERE r.id = p_reservation_id;
  IF v_trajet_id IS NULL THEN RAISE EXCEPTION 'Depart introuvable'; END IF;
  v_company_id := public.reservation_company_id(p_reservation_id);

  IF NOT public.is_super_admin() AND NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ur."userId" = v_user_id AND ur."companyId" = v_company_id AND ro.name IN ('vendeur', 'owner')
  ) THEN RAISE EXCEPTION 'Vente directe reservee aux vendeurs de la compagnie'; END IF;

  SELECT pt.depart, pt.final INTO v_depart, v_final FROM "ProgrammationTrajets" pt WHERE pt.id = v_trajet_id;

  SELECT c.id INTO v_caisse_id FROM caisses_gares c
  WHERE c.gestionnaire_id = v_user_id AND c.gare_id = v_depart AND c.statut = 'ouverte'
  ORDER BY c.opened_at DESC LIMIT 1;
  IF v_caisse_id IS NULL THEN RAISE EXCEPTION 'Ouvrez votre caisse a la gare de depart avant une vente cash'; END IF;

  SELECT a.id, a.price INTO v_arret_id, v_ticket_price FROM "ProgrammationTrajetArrets" a
  WHERE a."trajetId" = v_trajet_id AND a."fromGareId" = v_depart AND a."toGareId" = v_final LIMIT 1;
  IF v_arret_id IS NULL THEN RAISE EXCEPTION 'Segment introuvable'; END IF;

  SELECT COUNT(*)::integer INTO v_booked FROM "ReservationBus" rb JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb."reservationId" = p_reservation_id AND rb."type" = 'voyage'
    AND COALESCE(rb."ticketStatus", 'issued') = 'issued' AND (rb."isReservation" = false OR p."txID" IS NOT NULL);
  IF v_booked >= v_capacity THEN RAISE EXCEPTION 'Plus de places disponibles'; END IF;

  IF v_seat IS NOT NULL AND EXISTS (
    SELECT 1 FROM "ReservationBus" rb JOIN "Payment" p ON p.id = rb."paymentId"
    WHERE rb."reservationId" = p_reservation_id AND rb."seatNumber" = v_seat AND rb."type" = 'voyage'
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued' AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
  ) THEN RAISE EXCEPTION 'Siege deja vendu'; END IF;

  SELECT COALESCE(cn.currency, 'XOF') INTO v_currency FROM "Companies" c
  LEFT JOIN "Countries" cn ON cn.id = c."countryId" WHERE c.id = v_company_id;

  v_total_price := v_ticket_price + GREATEST(v_parcel_amount, 0);
  v_ticket_fcfa := public.fcfa_to_int(v_ticket_price);
  v_parcel_fcfa := public.fcfa_to_int(v_parcel_amount);
  v_reference := 'TB-' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', '') FROM 1 FOR 8));

  INSERT INTO "Payment" (reference, phone, amount, "txID")
  VALUES (v_reference, COALESCE(NULLIF(BTRIM(p_passenger_phone), ''), '0000000000'), v_total_price, 'counter-' || gen_random_uuid()::text)
  RETURNING id INTO v_payment_id;

  INSERT INTO "ReservationBus" (
    type, "createdBy", "reservationId", "arretId", price, "isReservation", "paymentId",
    "exceedColisAmount", "passengerName", "seatNumber", "parcelCount", "parcelWeight", "parcelAmount", "saleChannel"
  ) VALUES (
    'voyage', v_user_id, p_reservation_id, v_arret_id, v_total_price, false, v_payment_id,
    NULLIF(v_parcel_amount, 0), BTRIM(p_passenger_name), v_seat,
    NULLIF(GREATEST(COALESCE(p_parcel_count, 0), 0), 0), NULLIF(GREATEST(COALESCE(p_parcel_weight, 0), 0), 0),
    NULLIF(v_parcel_amount, 0), 'counter_sale'
  ) RETURNING id, "verifyToken" INTO v_booking_id, v_verify_token;

  PERFORM public.record_counter_sale_cash_movements(v_caisse_id, v_booking_id, v_ticket_fcfa, v_parcel_fcfa, v_user_id);

  v_traveler_user_id := public.resolve_user_by_phone_or_email(p_passenger_phone, NULL);
  IF v_traveler_user_id IS NOT NULL THEN
    PERFORM public.process_loyalty_on_ticket(
      v_traveler_user_id,
      v_company_id,
      v_booking_id,
      v_ticket_price,
      0,
      v_traveler_user_id
    );
    PERFORM public.process_platform_loyalty_on_ticket(
      v_traveler_user_id,
      v_company_id,
      v_booking_id,
      v_ticket_price,
      0
    );
  END IF;

  booking_id := v_booking_id;
  reference := v_reference;
  verify_token := v_verify_token;
  total_price := v_total_price;
  currency := COALESCE(v_currency, 'XOF');
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- Backfill codes parrain existants
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT u.id FROM "Users" u WHERE u."referralCode" IS NULL LOOP
    PERFORM public.ensure_user_referral_code(r.id);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- GRANTs
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.normalize_phone_digits(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.generate_referral_code() TO service_role;
GRANT EXECUTE ON FUNCTION public.ensure_user_referral_code(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_user_by_phone_or_email(text, text) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_platform_loyalty_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_platform_loyalty_settings(
  boolean, double precision, integer, double precision, integer, double precision,
  integer, integer, integer, integer
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_referral_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_referral_signup(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_referral_share() TO authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_company_loyalty_users(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_loyalty_booking_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_platform_loyalty_redemption(double precision, integer, uuid) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.process_platform_loyalty_on_ticket(uuid, uuid, uuid, double precision, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_loyalty_on_ticket(uuid, uuid, uuid, double precision, integer, uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.seller_counter_sale(uuid, text, text, text, integer, double precision, double precision) TO authenticated;
