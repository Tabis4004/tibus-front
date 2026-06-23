-- =============================================================================
-- Tibus 150 — Parrainage : get_my_referral_profile ne peut pas être STABLE
-- (ensure_user_referral_code fait SELECT FOR UPDATE + UPDATE sur Users)
-- Erreur prod : "cannot execute SELECT FOR UPDATE in a read-only transaction"
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_my_referral_profile()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
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

GRANT EXECUTE ON FUNCTION public.get_my_referral_profile() TO authenticated;

NOTIFY pgrst, 'reload schema';
