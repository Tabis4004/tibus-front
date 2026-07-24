import { supabase } from "@/lib/supabase";
import {
  countPlatformUsersForAdminSupabase,
  isAdminUsersPermissionError,
  isAdminUsersRpcMissingError,
  listPlatformUsersForAdminSupabase,
  type PlatformAdminUserRow,
} from "@/lib/supabase/admin-users.ts";
import {
  getPlatformCommissionSummarySupabase,
  getSellerCommissionSummarySupabase,
  listCommissionSettingsSupabase,
  type CommissionSetting,
  type PlatformCommissionSummary,
  type SellerCommissionSummary,
} from "@/lib/supabase/accounting.ts";

export type SupabaseUserRow = {
  id: string;
  email: string | null;
  firstName: string;
  lastName: string;
  username: string;
};

export type SupabaseCompanyRow = {
  id: string;
  name: string;
  countryId: string | null;
  countryName: string | null;
  isActive: boolean;
  commissionRate: number;
  managerName: string | null;
  currency: string | null;
  recruitedByUserId: string | null;
};

export type SupabaseCountryRow = {
  id: string;
  name: string;
  currency: string | null;
};

export type SupabaseCityRow = {
  id: string;
  name: string;
  countryName: string | null;
};

export type SupabaseRoleRow = {
  id: string;
  name: string;
  scope: string | null;
  description: string | null;
  droits: string[];
  isSystem: boolean;
};

export type SupabasePlanRow = {
  id: string;
  name: string;
  countryName: string | null;
  currency: string | null;
  durations: { id: string; price: number; duration: number }[];
};

export type SupabaseSubscriptionRow = {
  id: string;
  companyName: string;
  planName: string;
  price: number | null;
  duration: number | null;
  endDate: string;
};

export type AdminTabId =
  | "users"
  | "companies"
  | "subscriptions"
  | "plans"
  | "commissions"
  | "guarantee_fund"
  | "geography"
  | "roles"
  | "contact"
  | "loyalty"
  | "legal"
  | "scaling_metrics"
  | "investor_plan"
  | "landing";

export type AdminDataSlice = {
  users: SupabaseUserRow[];
  rolesByUser: Record<string, string[]>;
  companies: SupabaseCompanyRow[];
  countries: SupabaseCountryRow[];
  cities: SupabaseCityRow[];
  roles: SupabaseRoleRow[];
  plans: SupabasePlanRow[];
  subscriptions: SupabaseSubscriptionRow[];
  commissions: SellerCommissionSummary | null;
  platformCommissions: PlatformCommissionSummary | null;
  commissionSettings: CommissionSetting[];
};

export type AdminStats = {
  users: number;
  companies: number;
  activeSubscriptions: number;
  cities: number;
};

export type AdminDataKey = Exclude<keyof AdminDataSlice, "rolesByUser"> | "rolesByUser";

function roleNameFromJoin(
  role: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!role) return null;
  if (Array.isArray(role)) return role[0]?.name ?? null;
  return role.name ?? null;
}

function joinedOne<T>(value: T | T[] | null | undefined): T | null {
  if (!value) return null;
  return Array.isArray(value) ? value[0] ?? null : value;
}

export function adminTabDataKeys(tab: AdminTabId, isSuperAdmin: boolean): AdminDataKey[] {
  if (!isSuperAdmin) {
    if (tab === "commissions" || tab === "companies") {
      return ["countries", "companies", "commissions", "platformCommissions", "commissionSettings"];
    }
    if (tab === "guarantee_fund") {
      return ["companies"];
    }
    return [];
  }

  switch (tab) {
    case "users":
      return ["users"];
    case "companies":
      return ["companies"];
    case "subscriptions":
      return ["subscriptions"];
    case "plans":
      return ["plans", "countries"];
    case "commissions":
      return ["countries", "companies", "commissions", "platformCommissions", "commissionSettings"];
    case "guarantee_fund":
      return ["companies"];
    case "geography":
      // Le CRUD Pays & Villes (GeographyManagerPanel) charge ses propres
      // données avec recherche côté serveur (Cities > 1000 lignes).
      return [];
    case "roles":
      return ["roles"];
    case "contact":
      return ["companies"];
    default:
      return [];
  }
}

export async function loadAdminStats(
  isSuperAdmin: boolean,
  hasDbSuperAdmin: boolean,
): Promise<AdminStats> {
  if (!isSuperAdmin) {
    return { users: 0, companies: 0, activeSubscriptions: 0, cities: 0 };
  }

  const now = new Date().toISOString();
  const usersCountPromise = hasDbSuperAdmin
    ? countPlatformUsersForAdminSupabase()
        .then((count) => ({ count, error: null as null }))
        .catch(async (err) => {
          const message = err instanceof Error ? err.message : String(err);
          if (isAdminUsersRpcMissingError(message)) {
            return supabase.from("users").select("id", { count: "exact", head: true });
          }
          return { count: 0, error: err };
        })
    : supabase.from("users").select("id", { count: "exact", head: true });

  const [usersRes, companiesRes, subsRes, citiesRes] = await Promise.all([
    usersCountPromise,
    supabase.from("Companies").select("id", { count: "exact", head: true }),
    supabase
      .from("Subscriptions")
      .select("id", { count: "exact", head: true })
      .gte("endDate", now),
    supabase.from("Cities").select("id", { count: "exact", head: true }),
  ]);

  return {
    users: usersRes.count ?? 0,
    companies: companiesRes.count ?? 0,
    activeSubscriptions: subsRes.count ?? 0,
    cities: citiesRes.count ?? 0,
  };
}

function extractErrorMessage(err: unknown) {
  if (err instanceof Error) return err.message;
  if (typeof err === "object" && err !== null && "message" in err) {
    return String((err as { message: unknown }).message);
  }
  return "Erreur chargement";
}

async function loadUsersDirect(): Promise<Pick<AdminDataSlice, "users" | "rolesByUser">> {
  const { data: rows, error } = await supabase
    .from("users")
    .select("id, email, firstName, lastName, username")
    .order("createdAt", { ascending: false })
    .limit(200);

  if (error) throw error;
  const users = (rows ?? []) as SupabaseUserRow[];
  const userIds = users.map((user) => user.id);

  if (userIds.length === 0) {
    return { users, rolesByUser: {} };
  }

  const { data: roleRows, error: rolesError } = await supabase
    .from("UserRoles")
    .select("userId, roleId, Role(name)")
    .in("userId", userIds);

  if (rolesError) throw rolesError;

  const rolesByUser: Record<string, string[]> = {};
  for (const row of roleRows ?? []) {
    const name = roleNameFromJoin(row.Role as { name: string } | { name: string }[] | null);
    if (!name) continue;
    const userId = row.userId as string;
    rolesByUser[userId] ??= [];
    rolesByUser[userId].push(name);
  }

  return { users, rolesByUser };
}

async function loadUsers(hasDbSuperAdmin: boolean): Promise<Pick<AdminDataSlice, "users" | "rolesByUser">> {
  if (!hasDbSuperAdmin) {
    return loadUsersDirect();
  }

  try {
    const platformUsers = await listPlatformUsersForAdminSupabase(500);
    const rolesByUser: Record<string, string[]> = {};
    const users: SupabaseUserRow[] = platformUsers.map((row: PlatformAdminUserRow) => {
      rolesByUser[row.id] = row.roles;
      return {
        id: row.id,
        email: row.email,
        firstName: row.firstName,
        lastName: row.lastName,
        username: row.username,
      };
    });
    return { users, rolesByUser };
  } catch (rpcError) {
    const message = extractErrorMessage(rpcError);
    if (isAdminUsersPermissionError(message)) {
      throw new Error(
        "Rôle super_admin manquant en base. Exécutez 071_grant_super_admin_accounts.sql dans Supabase, puis reconnectez-vous.",
      );
    }
    if (isAdminUsersRpcMissingError(message)) {
      return loadUsersDirect();
    }
    throw rpcError;
  }
}

async function loadCompanies(scope?: {
  countryId?: string | null;
  recruitedByUserId?: string | null;
  enforce?: "country" | "recruiter" | null;
}): Promise<Pick<AdminDataSlice, "companies">> {
  // Fail-closed : un admin pays sans pays (ou un démarcheur sans profil)
  // ne doit voir AUCUNE compagnie, plutôt que toutes.
  if (scope?.enforce === "country" && !scope.countryId) {
    return { companies: [] };
  }
  if (scope?.enforce === "recruiter" && !scope.recruitedByUserId) {
    return { companies: [] };
  }

  let query = supabase
    .from("Companies")
    .select("id, name, countryId, isActive, commissionRate, managerName, recruitedByUserId, Countries(name, currency)")
    .order("createdAt", { ascending: false });

  if (scope?.countryId) {
    query = query.eq("countryId", scope.countryId);
  }
  if (scope?.recruitedByUserId) {
    query = query.eq("recruitedByUserId", scope.recruitedByUserId);
  }

  const { data: rows, error } = await query;

  if (error) throw error;

  return {
    companies: (rows ?? []).map((row) => {
      const country = joinedOne(
        row.Countries as
          | { name: string; currency: string | null }
          | { name: string; currency: string | null }[]
          | null,
      );
      return {
        id: row.id as string,
        name: row.name as string,
        countryId: (row.countryId as string | null) ?? null,
        countryName: country?.name ?? null,
        isActive: Boolean(row.isActive),
        commissionRate: Number(row.commissionRate ?? 0),
        managerName: (row.managerName as string | null) ?? null,
        currency: country?.currency ?? null,
        recruitedByUserId: (row.recruitedByUserId as string | null) ?? null,
      };
    }),
  };
}

async function loadCountries(): Promise<Pick<AdminDataSlice, "countries">> {
  const { data: rows, error } = await supabase
    .from("Countries")
    .select("id, name, currency")
    .order("name");

  if (error) throw error;
  return { countries: (rows ?? []) as SupabaseCountryRow[] };
}

async function loadCities(): Promise<Pick<AdminDataSlice, "cities">> {
  const { data: rows, error } = await supabase
    .from("Cities")
    .select("id, name, Countries(name)")
    .order("name");

  if (error) throw error;

  return {
    cities: (rows ?? []).map((row) => {
      const country = joinedOne(row.Countries as { name: string } | { name: string }[] | null);
      return {
        id: row.id as string,
        name: row.name as string,
        countryName: country?.name ?? null,
      };
    }),
  };
}

async function loadRoles(): Promise<Pick<AdminDataSlice, "roles">> {
  const { data: rows, error } = await supabase
    .from("Role")
    .select("id, name, scope, level, isSystem, description, droits")
    .order("level", { ascending: false });

  if (error) throw error;

  return {
    roles: (rows ?? []).map((row) => ({
      id: row.id as string,
      name: row.name as string,
      scope: (row.scope as string | null) ?? null,
      description: (row.description as string | null) ?? null,
      droits: (row.droits as string[] | null) ?? [],
      isSystem: Boolean(row.isSystem),
    })),
  };
}

async function loadPlans(): Promise<Pick<AdminDataSlice, "plans">> {
  const [plansResult, durationsResult] = await Promise.all([
    supabase
      .from("SubscriptionPlans")
      .select("id, name, countryId, features, Countries(name, currency)")
      .order("createdAt", { ascending: false }),
    supabase.from("SubscriptionPlanDurations").select("id, planId, price, duration").order("duration"),
  ]);

  if (plansResult.error) throw plansResult.error;
  if (durationsResult.error) throw durationsResult.error;

  const durationsByPlan = new Map<string, { id: string; price: number; duration: number }[]>();
  for (const duration of durationsResult.data ?? []) {
    const planId = duration.planId as string;
    durationsByPlan.set(planId, [
      ...(durationsByPlan.get(planId) ?? []),
      {
        id: duration.id as string,
        price: Number(duration.price ?? 0),
        duration: Number(duration.duration ?? 0),
      },
    ]);
  }

  return {
    plans: (plansResult.data ?? []).map((plan) => {
      const country = joinedOne(
        plan.Countries as
          | { name: string; currency: string | null }
          | { name: string; currency: string | null }[]
          | null,
      );
      return {
        id: plan.id as string,
        name: plan.name as string,
        countryName: country?.name ?? null,
        currency: country?.currency ?? null,
        durations: durationsByPlan.get(plan.id as string) ?? [],
      };
    }),
  };
}

async function loadSubscriptions(): Promise<Pick<AdminDataSlice, "subscriptions">> {
  const { data: rows, error } = await supabase
    .from("Subscriptions")
    .select(
      "id, endDate, Companies(name), SubscriptionPlans(name), SubscriptionPlanDurations(price, duration)",
    )
    .order("createdAt", { ascending: false })
    .limit(50);

  if (error) throw error;

  return {
    subscriptions: (rows ?? []).map((row) => {
      const company = joinedOne(row.Companies as { name: string } | { name: string }[] | null);
      const plan = joinedOne(row.SubscriptionPlans as { name: string } | { name: string }[] | null);
      const duration = joinedOne(
        row.SubscriptionPlanDurations as
          | { price: number; duration: number }
          | { price: number; duration: number }[]
          | null,
      );
      return {
        id: row.id as string,
        companyName: company?.name ?? "Company",
        planName: plan?.name ?? "Plan",
        price: duration ? Number(duration.price ?? 0) : null,
        duration: duration ? Number(duration.duration ?? 0) : null,
        endDate: row.endDate as string,
      };
    }),
  };
}

async function loadCommissions(): Promise<
  Pick<AdminDataSlice, "commissions" | "platformCommissions" | "commissionSettings">
> {
  const [commissions, platformCommissions, commissionSettings] = await Promise.all([
    getSellerCommissionSummarySupabase().catch(() => null),
    getPlatformCommissionSummarySupabase().catch(() => null),
    listCommissionSettingsSupabase(),
  ]);
  return { commissions, platformCommissions, commissionSettings };
}

type LoaderContext = {
  hasDbSuperAdmin: boolean;
  countryId?: string | null;
  recruitedByUserId?: string | null;
  enforce?: "country" | "recruiter" | null;
};

const LOADER_BY_KEY: Record<
  AdminDataKey,
  (context: LoaderContext) => Promise<Partial<AdminDataSlice>>
> = {
  users: (context) => loadUsers(context.hasDbSuperAdmin),
  rolesByUser: (context) => loadUsers(context.hasDbSuperAdmin),
  companies: (context) =>
    loadCompanies({
      countryId: context.countryId,
      recruitedByUserId: context.recruitedByUserId,
      enforce: context.enforce,
    }),
  countries: () => loadCountries(),
  cities: () => loadCities(),
  roles: () => loadRoles(),
  plans: () => loadPlans(),
  subscriptions: () => loadSubscriptions(),
  commissions: () => loadCommissions(),
  platformCommissions: () => loadCommissions(),
  commissionSettings: () => loadCommissions(),
};

export async function loadAdminTabData(
  tab: AdminTabId,
  isSuperAdmin: boolean,
  hasDbSuperAdmin: boolean,
  scope?: {
    countryId?: string | null;
    recruitedByUserId?: string | null;
    enforce?: "country" | "recruiter" | null;
  },
): Promise<{ data: Partial<AdminDataSlice>; errors: Partial<Record<AdminDataKey, string>> }> {
  const keys = [...new Set(adminTabDataKeys(tab, isSuperAdmin))];
  const data: Partial<AdminDataSlice> = {};
  const errors: Partial<Record<AdminDataKey, string>> = {};
  const context: LoaderContext = {
    hasDbSuperAdmin,
    countryId: scope?.countryId,
    recruitedByUserId: scope?.recruitedByUserId,
    enforce: scope?.enforce,
  };

  await Promise.all(
    keys.map(async (key) => {
      try {
        const slice = await LOADER_BY_KEY[key](context);
        Object.assign(data, slice);
      } catch (err) {
        errors[key] = extractErrorMessage(err);
      }
    }),
  );

  return { data, errors };
}
