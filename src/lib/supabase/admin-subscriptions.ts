import { supabase } from "@/lib/supabase";

export type AdminSubscriptionPlan = {
  id: string;
  name: string;
  countryId: string;
  countryName: string | null;
  currency: string | null;
  features: string[];
  isDefault: boolean;
  durations: { id: string; price: number; duration: number }[];
};

export type AdminCompanySubscriptionRow = {
  companyId: string;
  companyName: string;
  countryName: string | null;
  subscriptionId: string | null;
  planName: string | null;
  duration: number | null;
  price: number | null;
  endDate: string | null;
  isActive: boolean;
};

function joinedOne<T>(value: T | T[] | null | undefined): T | null {
  if (!value) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export async function listAdminSubscriptionPlansSupabase(): Promise<AdminSubscriptionPlan[]> {
  const [{ data: plans, error: plansError }, { data: durations, error: durationsError }] =
    await Promise.all([
      supabase
        .from("SubscriptionPlans")
        .select("id, name, countryId, features, isDefault, Countries(name, currency)")
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
      plan.Countries as { name: string; currency: string | null } | { name: string; currency: string | null }[] | null,
    );
    return {
      id: plan.id as string,
      name: plan.name as string,
      countryId: plan.countryId as string,
      countryName: country?.name ?? null,
      currency: country?.currency ?? null,
      features: (plan.features as string[] | null) ?? [],
      isDefault: Boolean(plan.isDefault),
      durations: durationsByPlan.get(plan.id as string) ?? [],
    };
  });
}

export async function createAdminSubscriptionPlanSupabase(input: {
  name: string;
  countryId: string;
  features?: string[];
  isDefault?: boolean;
  price: number;
  durationDays: number;
}): Promise<void> {
  const { data: planId, error: planError } = await supabase.rpc("admin_create_subscription_plan", {
    p_name: input.name.trim(),
    p_country_id: input.countryId,
    p_features: input.features ?? [],
    p_is_default: input.isDefault ?? false,
  });

  if (planError) throw planError;
  if (!planId) throw new Error("Plan non créé");

  const { error: durationError } = await supabase.rpc("admin_upsert_plan_duration", {
    p_plan_id: planId as string,
    p_price: input.price,
    p_duration: input.durationDays,
    p_duration_id: null,
  });

  if (durationError) throw durationError;
}

export async function updateAdminSubscriptionPlanSupabase(input: {
  planId: string;
  name?: string;
  features?: string[];
  isDefault?: boolean;
}): Promise<void> {
  const { error } = await supabase.rpc("admin_update_subscription_plan", {
    p_plan_id: input.planId,
    p_name: input.name ?? null,
    p_features: input.features ?? null,
    p_is_default: input.isDefault ?? null,
  });
  if (error) throw error;
}

export async function deleteAdminSubscriptionPlanSupabase(planId: string): Promise<void> {
  const { error } = await supabase.rpc("admin_delete_subscription_plan", {
    p_plan_id: planId,
  });
  if (error) throw error;
}

export async function upsertAdminPlanDurationSupabase(input: {
  planId: string;
  price: number;
  durationDays: number;
  durationId?: string | null;
}): Promise<void> {
  const { error } = await supabase.rpc("admin_upsert_plan_duration", {
    p_plan_id: input.planId,
    p_price: input.price,
    p_duration: input.durationDays,
    p_duration_id: input.durationId ?? null,
  });
  if (error) throw error;
}

export async function deleteAdminPlanDurationSupabase(durationId: string): Promise<void> {
  const { error } = await supabase.rpc("admin_delete_plan_duration", {
    p_duration_id: durationId,
  });
  if (error) throw error;
}

export async function assignCompanySubscriptionSupabase(input: {
  companyId: string;
  durationId: string;
}): Promise<void> {
  const { error } = await supabase.rpc("admin_assign_company_subscription", {
    p_company_id: input.companyId,
    p_duration_id: input.durationId,
  });
  if (error) throw error;
}

export async function listAdminCompanySubscriptionsSupabase(): Promise<AdminCompanySubscriptionRow[]> {
  const { data: companies, error: companiesError } = await supabase
    .from("Companies")
    .select("id, name, Countries(name)")
    .order("name");

  if (companiesError) throw companiesError;

  const { data: subscriptions, error: subscriptionsError } = await supabase
    .from("Subscriptions")
    .select(
      "id, companyId, endDate, SubscriptionPlans(name), SubscriptionPlanDurations(price, duration)",
    )
    .order("endDate", { ascending: false });

  if (subscriptionsError) throw subscriptionsError;

  const latestByCompany = new Map<string, (typeof subscriptions)[number]>();
  for (const row of subscriptions ?? []) {
    const companyId = row.companyId as string;
    if (!latestByCompany.has(companyId)) {
      latestByCompany.set(companyId, row);
    }
  }

  const now = Date.now();

  return (companies ?? []).map((company) => {
    const sub = latestByCompany.get(company.id as string);
    const country = joinedOne(
      company.Countries as { name: string } | { name: string }[] | null,
    );
    const plan = sub
      ? joinedOne(sub.SubscriptionPlans as { name: string } | { name: string }[] | null)
      : null;
    const durationRow = sub
      ? joinedOne(
          sub.SubscriptionPlanDurations as
            | { price: number | null; duration: number | null }
            | { price: number | null; duration: number | null }[]
            | null,
        )
      : null;
    const endDate = (sub?.endDate as string | undefined) ?? null;

    return {
      companyId: company.id as string,
      companyName: company.name as string,
      countryName: country?.name ?? null,
      subscriptionId: (sub?.id as string | undefined) ?? null,
      planName: plan?.name ?? null,
      duration: durationRow?.duration == null ? null : Number(durationRow.duration),
      price: durationRow?.price == null ? null : Number(durationRow.price),
      endDate,
      isActive: endDate ? new Date(endDate).getTime() >= now : false,
    };
  });
}
