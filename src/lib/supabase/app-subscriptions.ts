import { supabase } from "@/lib/supabase";

/** Applications soumises à abonnement (migration 222). */
export type AppSubscriptionKey = "courrier" | "embarquement" | "comptabilite";

export type AppSubscription = {
  appKey: AppSubscriptionKey;
  label: string;
  endDate: string | null;
  daysLeft: number | null;
  state: "active" | "warning" | "expired";
};

export async function getCompanyAppSubscriptionsSupabase(companyId: string): Promise<AppSubscription[]> {
  const { data, error } = await supabase.rpc("get_company_app_subscriptions", { p_company_id: companyId });
  if (error) throw error;
  return (data as AppSubscription[] | null) ?? [];
}

/** Super admin : date de fin d'abonnement (null = illimité). */
export async function setCompanyAppSubscriptionSupabase(
  companyId: string,
  appKey: AppSubscriptionKey,
  endDate: string | null,
): Promise<void> {
  const { error } = await supabase.rpc("admin_set_company_app_subscription", {
    p_company_id: companyId,
    p_app_key: appKey,
    p_end_date: endDate,
  });
  if (error) throw error;
}
