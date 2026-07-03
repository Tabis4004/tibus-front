-- Security Advisor: rls_disabled_in_public
-- StakeholderCommissionPayoutMinimums was public with RLS disabled.
-- Enable RLS with no policy yet (fail-closed): only service_role can
-- access it until a specific policy is written for legitimate callers.
ALTER TABLE public."StakeholderCommissionPayoutMinimums" ENABLE ROW LEVEL SECURITY;
