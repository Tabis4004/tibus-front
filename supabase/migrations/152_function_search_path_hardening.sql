-- Security Advisor: function_search_path_mutable
-- Pins search_path on functions that didn't have it set, to prevent
-- search_path hijacking (schema injection) attacks.
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
        '_is_gare_scoped_role','compute_cancellation_penalty',
        'is_guarantee_reservation_channel','fcfa_to_int',
        'normalize_ticket_reference','get_company_pay_at_station',
        'normalize_phone_digits','build_colis_sms_message',
        '_stakeholder_commission_roles','_stakeholder_role_sort',
        'tg_company_expense_touch_updated_at',
        'tg_validate_gare_city_in_company_country',
        '_stakeholder_commission_base_amount','_company_can_enable_live',
        '_booking_platform_commission_source',
        'ticket_scan_wrong_company_payload','_resolve_scaling_tier',
        '_scaling_tier_thresholds','_company_module_flag',
        'colis_public_reference_sql'
      ])
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END $$;
