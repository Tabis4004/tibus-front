-- Security Advisor: anon/authenticated_security_definer_function_executable
--
-- Audit of the 283 SECURITY DEFINER functions flagged as executable by
-- `anon` and `authenticated` found that most enforce authorization
-- internally (is_super_admin(), current_app_user_id(), has_company_role(),
-- etc.) and are safe to leave broadly grantable.
--
-- These specific functions do NOT check the caller's identity/ownership
-- internally, and per supabase/functions/partner-itinerary-api/index.ts and
-- supabase/functions/_shared/issue-ticket.ts, are only ever meant to be
-- called by trusted server-side code using the service_role key:
--   - partner_* family: real auth happens in the edge function
--     (resolvePartnerAuth -> partner_resolve_api_key), never in the RPC
--     itself. Leaving them anon/authenticated-callable let anyone hit
--     /rest/v1/rpc/partner_create_booking (etc.) directly, completely
--     bypassing the X-Api-Key check.
--   - _platform_loyalty_credit / process_loyalty_on_ticket /
--     process_platform_loyalty_on_ticket: credit/debit loyalty points for
--     an arbitrary p_user_id with no check -> point-minting fraud vector.
--   - capture_booking_platform_commission: rewrites commission fields on
--     an arbitrary booking id, can trigger a real charge.
--   - create_user_notification / _upsert_scaling_notification: inject
--     arbitrary content into any user's (or superadmin's) notifications.
--   - increment_promo_usage: lets anyone exhaust a promo code's usage cap.
--   - deduct_company_guarantee_fund / check_company_guarantee_sufficient:
--     guarantee fund ledger mutation, service_role-only in practice.
--   - _seed_company_expense_categories / ensure_company_cash_hub_gare /
--     ensure_user_referral_code: lower impact, but still no ownership
--     check on the target company/user id passed in.
--
-- service_role is unaffected by this revoke (it bypasses grants), so the
-- edge functions that legitimately call these continue to work.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(ARRAY[
        -- partner integration API family (gated by X-Api-Key in the edge function only)
        'partner_cancel_booking','partner_company_owner_user_id','partner_confirm_booking',
        'partner_create_booking','partner_get_booking','partner_get_departure_availability',
        'partner_list_departures','partner_list_webhook_deliveries','partner_resolve_api_key',
        'partner_resolve_gare_id','partner_upsert_departure','partner_upsert_gare_mapping',
        'partner_upsert_webhook_endpoint',
        -- loyalty / commission / promo / notification mutators with no internal auth check
        '_platform_loyalty_credit','process_loyalty_on_ticket','process_platform_loyalty_on_ticket',
        'capture_booking_platform_commission','create_user_notification',
        '_upsert_scaling_notification','increment_promo_usage','deduct_company_guarantee_fund',
        'check_company_guarantee_sufficient',
        -- low-impact but still missing ownership checks
        '_seed_company_expense_categories','ensure_company_cash_hub_gare','ensure_user_referral_code'
      ])
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END $$;
