import { supabase } from "@/lib/supabase";
import { resolveOwnerCompanyId } from "@/lib/supabase/owner-company";

export type OwnerSubscriptionPlan = {
  id: string;
  name: string;
  currency: string;
  features: string[];
  durations: { id: string; price: number; duration: number }[];
};

export type OwnerActiveSubscription = {
  id: string;
  planName: string;
  price: number | null;
  duration: number | null;
  endDate: string;
  isActive: boolean;
};

function joinedOne<T>(value: T | T[] | null | undefined): T | null {
  if (!value) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export async function listOwnerSubscriptionPlansSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerSubscriptionPlan[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data: company, error: companyError } = await supabase
    .from("Companies")
    .select("countryId")
    .eq("id", resolvedCompanyId)
    .maybeSingle();

  if (companyError) throw companyError;
  if (!company?.countryId) return [];

  const [{ data: plans, error: plansError }, { data: durations, error: durationsError }] =
    await Promise.all([
      supabase
        .from("SubscriptionPlans")
        .select("id, name, features, Countries(currency)")
        .eq("countryId", company.countryId as string)
        .order("createdAt", { ascending: false }),
      supabase
        .from("SubscriptionPlanDurations")
        .select("id, planId, price, duration")
        .order("duration"),
    ]);

  if (plansError) throw plansError;
  if (durationsError) throw durationsError;

  const durationsByPlan = new Map<string, { id: string; price: number; duration: number }[]>();
  for (const row of durations ?? []) {
    const planId = row.planId as string;
    durationsByPlan.set(planId, [
      ...(durationsByPlan.get(planId) ?? []),
      {
        id: row.id as string,
        price: Number(row.price ?? 0),
        duration: Number(row.duration ?? 0),
      },
    ]);
  }

  return (plans ?? []).map((plan) => {
    const country = joinedOne(
      plan.Countries as { currency: string | null } | { currency: string | null }[] | null,
    );
    return {
      id: plan.id as string,
      name: plan.name as string,
      currency: country?.currency ?? "XOF",
      features: (plan.features as string[] | null) ?? [],
      durations: durationsByPlan.get(plan.id as string) ?? [],
    };
  });
}

export async function getOwnerActiveSubscriptionSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerActiveSubscription | null> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return null;

  const { data, error } = await supabase
    .from("Subscriptions")
    .select(
      "id, endDate, SubscriptionPlans(name), SubscriptionPlanDurations(price, duration)",
    )
    .eq("companyId", resolvedCompanyId)
    .order("endDate", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  const plan = joinedOne(
    data.SubscriptionPlans as { name: string } | { name: string }[] | null,
  );
  const durationRow = joinedOne(
    data.SubscriptionPlanDurations as
      | { price: number | null; duration: number | null }
      | { price: number | null; duration: number | null }[]
      | null,
  );

  const endDate = data.endDate as string;
  return {
    id: data.id as string,
    planName: plan?.name ?? "Abonnement",
    price: durationRow?.price == null ? null : Number(durationRow.price),
    duration: durationRow?.duration == null ? null : Number(durationRow.duration),
    endDate,
    isActive: new Date(endDate).getTime() >= Date.now(),
  };
}
