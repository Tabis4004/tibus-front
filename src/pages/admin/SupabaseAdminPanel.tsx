import { useEffect, useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  ArrowLeftIcon,
  BuildingIcon,
  CircleDollarSignIcon,
  CreditCardIcon,
  GlobeIcon,
  KeyIcon,
  LandmarkIcon,
  MapPinIcon,
  MessageCircleIcon,
  PercentIcon,
  PencilIcon,
  PlusIcon,
  ShieldIcon,
  SettingsIcon,
  TrashIcon,
  UsersIcon,
  GiftIcon,
  FileTextIcon,
  ActivityIcon,
  type LucideIcon,
} from "lucide-react";
import { toast } from "sonner";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { supabase } from "@/lib/supabase";
import {
  deleteCommissionSettingSupabase,
  getSellerCommissionSummarySupabase,
  listCommissionSettingsSupabase,
  upsertCommissionSettingSupabase,
  type CommissionSetting,
  type SellerCommissionSummary,
} from "@/lib/supabase/accounting.ts";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { cn } from "@/lib/utils.ts";
import GatewayFeeSettingsPanel from "./_components/GatewayFeeSettingsPanel.tsx";
import PaymentGatewaySettingsPanel from "./_components/PaymentGatewaySettingsPanel.tsx";
import TravelerBookingNoticePanel from "./_components/TravelerBookingNoticePanel.tsx";
import GuaranteeFundManager from "./_components/GuaranteeFundManager.tsx";
import ContactSettingsPanel from "./_components/ContactSettingsPanel.tsx";
import PlatformLoyaltySettingsPanel from "./_components/PlatformLoyaltySettingsPanel.tsx";
import LegalPagesPanel from "./_components/LegalPagesPanel.tsx";
import PlatformScalingMetricsPanel from "./_components/PlatformScalingMetricsPanel.tsx";
import TpePosDiagnosticsPanel from "./_components/TpePosDiagnosticsPanel.tsx";
import SupabasePlansTab from "./_components/SupabasePlansTab.tsx";
import SupabaseSubscriptionsTab from "./_components/SupabaseSubscriptionsTab.tsx";

type SupabaseUserRow = {
  id: string;
  email: string | null;
  firstName: string;
  lastName: string;
  username: string;
};

type SupabaseCompanyRow = {
  id: string;
  name: string;
  countryId: string | null;
  countryName: string | null;
  isActive: boolean;
  commissionRate: number;
  managerName: string | null;
  currency: string | null;
};

type SupabaseCountryRow = {
  id: string;
  name: string;
  currency: string | null;
};

type SupabaseCityRow = {
  id: string;
  name: string;
  countryName: string | null;
};

type SupabaseRoleRow = {
  id: string;
  name: string;
  scope: string | null;
  description: string | null;
  droits: string[];
};

type SupabasePlanRow = {
  id: string;
  name: string;
  countryName: string | null;
  currency: string | null;
  durations: { id: string; price: number; duration: number }[];
};

type SupabaseSubscriptionRow = {
  id: string;
  companyName: string;
  planName: string;
  price: number | null;
  duration: number | null;
  endDate: string;
};

type TabId =
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
  | "landing";

const TAB_IDS: TabId[] = [
  "users",
  "companies",
  "subscriptions",
  "plans",
  "commissions",
  "guarantee_fund",
  "geography",
  "roles",
  "contact",
  "loyalty",
  "legal",
  "scaling_metrics",
  "landing",
];

function isTabId(value: string | null): value is TabId {
  return value !== null && TAB_IDS.includes(value as TabId);
}

type AdminData = {
  users: SupabaseUserRow[];
  rolesByUser: Record<string, string[]>;
  companies: SupabaseCompanyRow[];
  countries: SupabaseCountryRow[];
  cities: SupabaseCityRow[];
  roles: SupabaseRoleRow[];
  plans: SupabasePlanRow[];
  subscriptions: SupabaseSubscriptionRow[];
  commissions: SellerCommissionSummary | null;
  commissionSettings: CommissionSetting[];
};

type ModuleErrorKey = Exclude<keyof AdminData, "rolesByUser">;

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

function errorMessage(err: unknown) {
  return err instanceof Error ? err.message : "Erreur chargement";
}

function isActiveSubscription(endDate: string) {
  return new Date(endDate).getTime() >= Date.now();
}

function initialData(): AdminData {
  return {
    users: [],
    rolesByUser: {},
    companies: [],
    countries: [],
    cities: [],
    roles: [],
    plans: [],
    subscriptions: [],
    commissions: null,
    commissionSettings: [],
  };
}

export default function SupabaseAdminPanel() {
  const { t: tc } = useTranslation("common");
  const { t } = useTranslation("admin");
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const appUser = useAppUser();
  const [tab, setTab] = useState<TabId>(() => {
    const tabParam = searchParams.get("tab");
    return isTabId(tabParam) ? tabParam : "users";
  });
  const [data, setData] = useState<AdminData>(() => initialData());
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<Partial<Record<ModuleErrorKey, string>>>({});
  const [refreshKey, setRefreshKey] = useState(0);
  const canAccessAdminPanel = appUser.isSuperAdmin || appUser.roles.includes("admin_pays");

  useEffect(() => {
    if (appUser.isReady && !appUser.isSuperAdmin && appUser.roles.includes("admin_pays")) {
      setTab("commissions");
    }
  }, [appUser.isReady, appUser.isSuperAdmin, appUser.roles]);

  useEffect(() => {
    if (!appUser.isReady) return;

    const tabParam = searchParams.get("tab");
    if (!isTabId(tabParam)) return;

    if (!appUser.isSuperAdmin) {
      if (tabParam === "commissions" || tabParam === "guarantee_fund") {
        setTab(tabParam);
      }
      return;
    }

    setTab(tabParam);
  }, [appUser.isReady, appUser.isSuperAdmin, searchParams]);

  const selectTab = (id: TabId) => {
    setTab(id);
    setSearchParams({ tab: id }, { replace: true });
  };

  useEffect(() => {
    if (!appUser.isReady) return;

    if (!canAccessAdminPanel) {
      navigate(`/${lng ?? "en"}`, { replace: true });
      return;
    }

    let cancelled = false;

    void (async () => {
      setIsLoading(true);
      setErrors({});

      const loadFullAdmin = appUser.isSuperAdmin;

      const usersPromise = loadFullAdmin ? supabase
        .from("Users")
        .select("id, email, firstName, lastName, username")
        .order("createdAt", { ascending: false })
        .limit(50)
        .then(({ data: rows, error }) => {
          if (error) throw error;
          return (rows ?? []) as SupabaseUserRow[];
        }) : Promise.resolve([] as SupabaseUserRow[]);

      const userRolesPromise = loadFullAdmin ? supabase
        .from("UserRoles")
        .select("userId, roleId, Role(name)")
        .then(({ data: rows, error }) => {
          if (error) throw error;
          const grouped: Record<string, string[]> = {};
          for (const row of rows ?? []) {
            const name = roleNameFromJoin(
              row.Role as { name: string } | { name: string }[] | null,
            );
            if (!name) continue;
            const userId = row.userId as string;
            grouped[userId] ??= [];
            grouped[userId].push(name);
          }
          return grouped;
        }) : Promise.resolve({} as Record<string, string[]>);

      const companiesPromise = supabase
        .from("Companies")
        .select("id, name, countryId, isActive, commissionRate, managerName, Countries(name, currency)")
        .order("createdAt", { ascending: false })
        .then(({ data: rows, error }) => {
          if (error) throw error;
          return (rows ?? []).map((row) => {
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
            };
          });
        });

      const countriesPromise = supabase
        .from("Countries")
        .select("id, name, currency")
        .order("name")
        .then(({ data: rows, error }) => {
          if (error) throw error;
          return (rows ?? []) as SupabaseCountryRow[];
        });

      const citiesPromise = loadFullAdmin ? supabase
        .from("Cities")
        .select("id, name, Countries(name)")
        .order("name")
        .then(({ data: rows, error }) => {
          if (error) throw error;
          return (rows ?? []).map((row) => {
            const country = joinedOne(row.Countries as { name: string } | { name: string }[] | null);
            return {
              id: row.id as string,
              name: row.name as string,
              countryName: country?.name ?? null,
            };
          });
        }) : Promise.resolve([] as SupabaseCityRow[]);

      const rolesPromise = loadFullAdmin ? supabase
        .from("Role")
        .select("id, name, scope, level, isSystem, description, droits")
        .order("level", { ascending: false })
        .then(({ data: rows, error }) => {
          if (error) throw error;
          return (rows ?? []).map((row) => ({
            id: row.id as string,
            name: row.name as string,
            scope: (row.scope as string | null) ?? null,
            description: (row.description as string | null) ?? null,
            droits: (row.droits as string[] | null) ?? [],
          }));
        }) : Promise.resolve([] as SupabaseRoleRow[]);

      const plansPromise = loadFullAdmin ? Promise.all([
        supabase
          .from("SubscriptionPlans")
          .select("id, name, countryId, features, Countries(name, currency)")
          .order("createdAt", { ascending: false }),
        supabase
          .from("SubscriptionPlanDurations")
          .select("id, planId, price, duration")
          .order("duration"),
      ]).then(([plansResult, durationsResult]) => {
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

        return (plansResult.data ?? []).map((plan) => {
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
        });
      }) : Promise.resolve([] as SupabasePlanRow[]);

      const subscriptionsPromise = loadFullAdmin ? supabase
        .from("Subscriptions")
        .select(
          "id, endDate, Companies(name), SubscriptionPlans(name), SubscriptionPlanDurations(price, duration)",
        )
        .order("createdAt", { ascending: false })
        .limit(50)
        .then(({ data: rows, error }) => {
          if (error) throw error;
          return (rows ?? []).map((row) => {
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
          });
        }) : Promise.resolve([] as SupabaseSubscriptionRow[]);

      const commissionSettingsPromise = listCommissionSettingsSupabase();

      const results = await Promise.allSettled([
        usersPromise,
        userRolesPromise,
        companiesPromise,
        countriesPromise,
        citiesPromise,
        rolesPromise,
        plansPromise,
        subscriptionsPromise,
        getSellerCommissionSummarySupabase(),
        commissionSettingsPromise,
      ]);

      const nextErrors: Partial<Record<ModuleErrorKey, string>> = {};
      const [
        usersResult,
        userRolesResult,
        companiesResult,
        countriesResult,
        citiesResult,
        rolesResult,
        plansResult,
        subscriptionsResult,
        commissionsResult,
        commissionSettingsResult,
      ] = results;

      if (usersResult.status === "rejected") nextErrors.users = errorMessage(usersResult.reason);
      if (userRolesResult.status === "rejected") nextErrors.users = errorMessage(userRolesResult.reason);
      if (companiesResult.status === "rejected") nextErrors.companies = errorMessage(companiesResult.reason);
      if (countriesResult.status === "rejected") nextErrors.countries = errorMessage(countriesResult.reason);
      if (citiesResult.status === "rejected") nextErrors.cities = errorMessage(citiesResult.reason);
      if (rolesResult.status === "rejected") nextErrors.roles = errorMessage(rolesResult.reason);
      if (plansResult.status === "rejected") nextErrors.plans = errorMessage(plansResult.reason);
      if (subscriptionsResult.status === "rejected") {
        nextErrors.subscriptions = errorMessage(subscriptionsResult.reason);
      }
      if (commissionsResult.status === "rejected") {
        nextErrors.commissions = errorMessage(commissionsResult.reason);
      }
      if (commissionSettingsResult.status === "rejected") {
        nextErrors.commissions = errorMessage(commissionSettingsResult.reason);
      }

      if (!cancelled) {
        setData({
          users: usersResult.status === "fulfilled" ? usersResult.value : [],
          rolesByUser: userRolesResult.status === "fulfilled" ? userRolesResult.value : {},
          companies: companiesResult.status === "fulfilled" ? companiesResult.value : [],
          countries: countriesResult.status === "fulfilled" ? countriesResult.value : [],
          cities: citiesResult.status === "fulfilled" ? citiesResult.value : [],
          roles: rolesResult.status === "fulfilled" ? rolesResult.value : [],
          plans: plansResult.status === "fulfilled" ? plansResult.value : [],
          subscriptions: subscriptionsResult.status === "fulfilled" ? subscriptionsResult.value : [],
          commissions: commissionsResult.status === "fulfilled" ? commissionsResult.value : null,
          commissionSettings: commissionSettingsResult.status === "fulfilled" ? commissionSettingsResult.value : [],
        });
        setErrors(nextErrors);
      }
    })()
      .catch((err) => {
        if (!cancelled) setErrors({ users: errorMessage(err) });
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [appUser.isReady, appUser.isSuperAdmin, appUser.roles, canAccessAdminPanel, lng, navigate, refreshKey]);

  if (!appUser.isReady || appUser.isLoading) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (!canAccessAdminPanel) return null;

  const tabs: { id: TabId; label: string; icon: LucideIcon }[] = [
    { id: "users", label: t("tabs.users"), icon: UsersIcon },
    { id: "companies", label: t("tabs.companies"), icon: BuildingIcon },
    { id: "subscriptions", label: t("tabs.subscriptions"), icon: CreditCardIcon },
    { id: "plans", label: t("tabs.plans"), icon: SettingsIcon },
    { id: "commissions", label: t("tabs.commissions"), icon: PercentIcon },
    { id: "guarantee_fund", label: t("tabs.guarantee_fund", { defaultValue: "Fond garantie" }), icon: LandmarkIcon },
    { id: "geography", label: t("tabs.geography"), icon: GlobeIcon },
    { id: "roles", label: t("tabs.roles"), icon: KeyIcon },
    { id: "contact", label: t("tabs.contact", { defaultValue: "Contact" }), icon: MessageCircleIcon },
    { id: "loyalty", label: t("tabs.loyalty", { defaultValue: "Fidélité" }), icon: GiftIcon },
    { id: "legal", label: t("tabs.legal", { defaultValue: "CGU" }), icon: FileTextIcon },
    { id: "scaling_metrics", label: t("tabs.scaling_metrics"), icon: ActivityIcon },
    { id: "landing", label: t("tabs.landing", { defaultValue: "Landing Page" }), icon: PencilIcon },
  ];
  const visibleTabs = appUser.isSuperAdmin
    ? tabs
    : tabs.filter((item) => item.id === "commissions" || item.id === "guarantee_fund");
  const activeSubscriptions = data.subscriptions.filter((sub) => isActiveSubscription(sub.endDate));

  return (
    <div className="max-w-6xl mx-auto px-4 py-8 space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
            <ShieldIcon className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">
              {t("title", { defaultValue: "Admin Panel" })}
            </h1>
            <p className="text-sm text-muted-foreground">
              {t("supabase_admin.subtitle", {
                defaultValue: "Mode Supabase - modules migrés et modules en cours de migration.",
              })}
            </p>
            {appUser.isAdminSandbox && (
              <Badge variant="outline" className="mt-2 text-[10px] border-amber-500/40 text-amber-600">
                {t("supabase_admin.sandbox_badge", {
                  defaultValue: "Sandbox admin (utilisateur authentifié)",
                })}
              </Badge>
            )}
          </div>
        </div>
        <Link to={`/${lng}`}>
          <Button variant="outline" size="sm" className="gap-2">
            <ArrowLeftIcon className="w-4 h-4" />
            {tc("buttons.back", { defaultValue: "Back" })}
          </Button>
        </Link>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard icon={UsersIcon} label={t("total_users")} value={data.users.length} />
        <StatCard icon={BuildingIcon} label={t("total_companies")} value={data.companies.length} />
        <StatCard icon={CreditCardIcon} label={t("active_subs")} value={activeSubscriptions.length} />
        <StatCard icon={GlobeIcon} label={t("geo.cities", { defaultValue: "Villes" })} value={data.cities.length} />
      </div>

      <div className="rounded-xl bg-muted p-1">
        <div className="flex gap-1 overflow-x-auto pb-1 [-webkit-overflow-scrolling:touch]">
          {visibleTabs.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              type="button"
              onClick={() => selectTab(id)}
              className={cn(
                "flex min-w-max shrink-0 items-center justify-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-colors cursor-pointer",
                tab === id
                  ? "bg-background text-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground",
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              <span>{label}</span>
            </button>
          ))}
        </div>
      </div>

      {tab === "users" && (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between gap-3">
            <CardTitle className="text-base flex items-center gap-2">
              <UsersIcon className="w-4 h-4" />
              {t("supabase_admin.users_title", { defaultValue: "Utilisateurs (Supabase)" })}
            </CardTitle>
            {appUser.isSuperAdmin && (
              <Button size="sm" asChild>
                <Link to={`/${lng ?? "fr"}/admin/users/new`}>
                  <PlusIcon className="w-4 h-4 mr-1.5" />
                  {t("users.create_btn", { defaultValue: "Créer un utilisateur" })}
                </Link>
              </Button>
            )}
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <LoadingRows />
            ) : errors.users ? (
              <p className="text-sm text-destructive">{errors.users}</p>
            ) : data.users.length === 0 ? (
              <EmptyState icon={UsersIcon} title={t("no_users")} description={t("supabase_admin.no_users", { defaultValue: "Aucun utilisateur." })} />
            ) : (
              <div className="divide-y">
                {data.users.map((user) => (
                  <div key={user.id} className="py-3 flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-medium truncate">
                        {user.firstName} {user.lastName}
                      </p>
                      <p className="text-xs text-muted-foreground truncate">
                        {user.email ?? user.username}
                      </p>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <RoleBadges roles={data.rolesByUser[user.id] ?? []} />
                      {appUser.isSuperAdmin && (
                        <Button size="icon" variant="ghost" className="h-8 w-8" asChild>
                          <Link to={`/${lng ?? "fr"}/admin/users/${user.id}/edit`}>
                            <PencilIcon className="h-3.5 w-3.5" />
                          </Link>
                        </Button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {tab === "companies" && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <BuildingIcon className="w-4 h-4" />
              {t("tabs.companies")}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <LoadingRows />
            ) : errors.companies ? (
              <p className="text-sm text-destructive">{errors.companies}</p>
            ) : data.companies.length === 0 ? (
              <EmptyState icon={BuildingIcon} title={t("no_companies")} description={t("no_companies_desc", { defaultValue: "Aucune entreprise Supabase trouvée." })} />
            ) : (
              <div className="divide-y">
                {data.companies.map((company) => (
                  <div key={company.id} className="py-3 flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-medium truncate">{company.name}</p>
                      <p className="text-xs text-muted-foreground truncate">
                        {company.managerName ?? t("owner_label")} · {company.countryName ?? t("geo.countries")}
                      </p>
                    </div>
                    <div className="flex flex-wrap justify-end gap-1">
                      <Badge variant={company.isActive ? "default" : "secondary"}>
                        {company.isActive ? tc("status.active") : tc("status.inactive")}
                      </Badge>
                      <Badge variant="secondary">{company.commissionRate}%</Badge>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {tab === "subscriptions" && (
        <SupabaseSubscriptionsTab
          companies={data.companies.map((company) => ({
            id: company.id,
            name: company.name,
            countryId: company.countryId,
            countryName: company.countryName,
          }))}
          onDataChanged={() => setRefreshKey((key) => key + 1)}
        />
      )}

      {tab === "plans" && (
        <SupabasePlansTab
          countries={data.countries}
          onDataChanged={() => setRefreshKey((key) => key + 1)}
        />
      )}

      {tab === "commissions" && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <PercentIcon className="w-4 h-4" />
              {t("commissions.title")}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {isLoading ? (
              <LoadingRows />
            ) : (
              <>
                <div className="grid gap-3 md:grid-cols-3">
                  <StatCard icon={CircleDollarSignIcon} label={t("commissions.pending")} value={data.commissions?.pendingTotal ?? 0} suffix={` ${data.commissions?.currency ?? ""}`} />
                  <StatCard icon={CircleDollarSignIcon} label={t("commissions.paid")} value={data.commissions?.paidTotal ?? 0} suffix={` ${data.commissions?.currency ?? ""}`} />
                  <StatCard icon={PercentIcon} label={t("commissions.no_entries")} value={data.commissions?.totalTickets ?? 0} />
                </div>
                {errors.commissions && (
                  <p className="rounded-lg bg-muted p-3 text-sm text-muted-foreground">
                    {t("supabase_admin.commissions_rpc_missing", {
                      defaultValue: "Les commissions Supabase ne sont pas disponibles. Appliquez les derniers scripts SQL.",
                    })}{" "}
                    <span className="text-destructive">{errors.commissions}</span>
                  </p>
                )}
                <CommissionSettingsManager
                  settings={data.commissionSettings}
                  companies={data.companies}
                  onChanged={() => setRefreshKey((key) => key + 1)}
                />
                {appUser.isSuperAdmin && <PaymentGatewaySettingsPanel />}
                <GatewayFeeSettingsPanel countries={data.countries.map((country) => ({
                  id: country.id,
                  name: country.name,
                }))} />
                {appUser.isSuperAdmin && (
                  <TravelerBookingNoticePanel countries={data.countries.map((country) => ({
                    id: country.id,
                    name: country.name,
                  }))} />
                )}
              </>
            )}
          </CardContent>
        </Card>
      )}

      {tab === "guarantee_fund" && (
        <div className="space-y-3">
          <div className="flex justify-end">
            <Link to={`/${lng}/admin/guarantee-fund`}>
              <Button variant="outline" size="sm" className="cursor-pointer gap-2">
                <LandmarkIcon className="w-4 h-4" />
                {t("guarantee_fund.open_full_page", { defaultValue: "Ouvrir la page dédiée" })}
              </Button>
            </Link>
          </div>
          <GuaranteeFundManager
            companies={data.companies.map((company) => ({
              id: company.id,
              name: company.name,
              currency: company.currency,
              countryName: company.countryName,
            }))}
          />
        </div>
      )}

      {tab === "geography" && (
        <div className="grid gap-4 md:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2">
                <GlobeIcon className="w-4 h-4" />
                {t("geo.countries")}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {isLoading ? <LoadingRows /> : errors.countries ? <p className="text-sm text-destructive">{errors.countries}</p> : (
                <SimpleList
                  emptyIcon={GlobeIcon}
                  emptyTitle={t("geo.no_countries")}
                  items={data.countries.map((country) => ({
                    id: country.id,
                    title: country.name,
                    meta: country.currency ?? "",
                  }))}
                />
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2">
                <MapPinIcon className="w-4 h-4" />
                {t("geo.add_cities")}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {isLoading ? <LoadingRows /> : errors.cities ? <p className="text-sm text-destructive">{errors.cities}</p> : (
                <SimpleList
                  emptyIcon={MapPinIcon}
                  emptyTitle={t("geo.no_cities", { defaultValue: "Aucune ville." })}
                  items={data.cities.map((city) => ({
                    id: city.id,
                    title: city.name,
                    meta: city.countryName ?? "",
                  }))}
                />
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {tab === "roles" && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <KeyIcon className="w-4 h-4" />
              {t("tabs.roles")}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <LoadingRows />
            ) : errors.roles ? (
              <p className="text-sm text-destructive">{errors.roles}</p>
            ) : data.roles.length === 0 ? (
              <EmptyState icon={KeyIcon} title={t("roles.no_custom")} description={t("roles.builtin_desc")} />
            ) : (
              <div className="grid gap-3 md:grid-cols-2">
                {data.roles.map((role) => (
                  <div key={role.id} className="rounded-xl border p-4 space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <p className="font-semibold">{tc(`roles.${role.name}`, { defaultValue: role.name })}</p>
                      <Badge variant={role.scope === "platform" ? "default" : "secondary"}>{role.scope ?? "role"}</Badge>
                    </div>
                    {role.description && <p className="text-xs text-muted-foreground">{role.description}</p>}
                    <div className="flex flex-wrap gap-1">
                      {role.droits.slice(0, 6).map((permission) => (
                        <Badge key={permission} variant="outline">{permission}</Badge>
                      ))}
                      {role.droits.length > 6 && <Badge variant="secondary">+{role.droits.length - 6}</Badge>}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {tab === "contact" && (
        <ContactSettingsPanel
          companies={data.companies.map((company) => ({ id: company.id, name: company.name }))}
        />
      )}

      {tab === "loyalty" && <PlatformLoyaltySettingsPanel />}

      {tab === "legal" && appUser.isSuperAdmin && <LegalPagesPanel />}

      {tab === "scaling_metrics" && appUser.isSuperAdmin && (
        <div className="space-y-6">
          <TpePosDiagnosticsPanel />
          <PlatformScalingMetricsPanel />
        </div>
      )}

      {tab === "landing" && (
        <ComingSoon
          icon={PencilIcon}
          title={t("tabs.landing", { defaultValue: "Landing Page" })}
          description={t("supabase_admin.landing_placeholder", {
            defaultValue: "Le CMS Landing Page est encore branché sur Convex. Le panneau Supabase affiche ce statut au lieu d'un onglet vide.",
          })}
        />
      )}
    </div>
  );
}

function LoadingRows() {
  return (
    <div className="space-y-2">
      <Skeleton className="h-10 w-full" />
      <Skeleton className="h-10 w-full" />
      <Skeleton className="h-10 w-full" />
    </div>
  );
}

function RoleBadges({ roles }: { roles: string[] }) {
  const { t } = useTranslation("common");
  return (
    <div className="flex flex-wrap gap-1 justify-end">
      {roles.length > 0 ? (
        roles.map((role) => {
          const uiRole = role === "super_admin" ? "superadmin" : role;
          return (
            <Badge key={role} variant={uiRole === "superadmin" ? "default" : "secondary"}>
              {t(`roles.${uiRole}`, { defaultValue: uiRole })}
            </Badge>
          );
        })
      ) : (
        <Badge variant="secondary">
          {t("roles.traveler", { defaultValue: "traveler" })}
        </Badge>
      )}
    </div>
  );
}

function StatCard({
  icon: Icon,
  label,
  value,
  suffix = "",
}: {
  icon: LucideIcon;
  label: string;
  value: number;
  suffix?: string;
}) {
  return (
    <Card className="p-4">
      <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center mb-2">
        <Icon className="w-4 h-4 text-primary" />
      </div>
      <div className="text-2xl font-bold">
        {value.toLocaleString()}{suffix}
      </div>
      <div className="text-xs text-muted-foreground">{label}</div>
    </Card>
  );
}

function CommissionSettingsManager({
  settings,
  companies,
  onChanged,
}: {
  settings: CommissionSetting[];
  companies: SupabaseCompanyRow[];
  onChanged: () => void;
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const countrySettings = settings.filter((setting) => setting.scope === "country");
  const companySettings = settings.filter((setting) => setting.scope === "company");
  const [drafts, setDrafts] = useState<Record<string, { rate: string; paidBy: "company" | "traveler" }>>({});
  const [companyId, setCompanyId] = useState<string>("__none");
  const [companyRate, setCompanyRate] = useState("0");
  const [companyPaidBy, setCompanyPaidBy] = useState<"company" | "traveler">("company");
  const [savingKey, setSavingKey] = useState<string | null>(null);

  const settingKey = (setting: CommissionSetting) =>
    `${setting.scope}:${setting.companyId ?? setting.countryId}`;

  const draftFor = (setting: CommissionSetting) =>
    drafts[settingKey(setting)] ?? {
      rate: String(setting.rate),
      paidBy: setting.paidBy,
    };

  const setDraft = (
    setting: CommissionSetting,
    patch: Partial<{ rate: string; paidBy: "company" | "traveler" }>,
  ) => {
    const key = settingKey(setting);
    setDrafts((current) => ({
      ...current,
      [key]: {
        ...draftFor(setting),
        ...patch,
      },
    }));
  };

  const handleSave = async (setting: CommissionSetting) => {
    const key = settingKey(setting);
    const draft = draftFor(setting);
    const rate = Number(draft.rate);

    if (!Number.isFinite(rate) || rate < 0 || rate > 100) {
      toast.error(t("commissions.invalid_rate", { defaultValue: "Le taux doit etre entre 0 et 100." }));
      return;
    }

    setSavingKey(key);
    try {
      await upsertCommissionSettingSupabase({
        scope: setting.scope,
        countryId: setting.scope === "country" ? setting.countryId : null,
        companyId: setting.scope === "company" ? setting.companyId : null,
        rate,
        paidBy: draft.paidBy,
      });
      toast.success(t("commissions.updated"));
      setDrafts((current) => {
        const next = { ...current };
        delete next[key];
        return next;
      });
      onChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("commissions.update_error"));
    } finally {
      setSavingKey(null);
    }
  };

  const handleDelete = async (setting: CommissionSetting) => {
    if (!setting.id) return;

    const key = settingKey(setting);
    setSavingKey(key);
    try {
      await deleteCommissionSettingSupabase(setting.id);
      toast.success(t("commissions.deleted", { defaultValue: "Commission supprimée." }));
      onChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("commissions.update_error"));
    } finally {
      setSavingKey(null);
    }
  };

  const handleAddCompanyOverride = async () => {
    if (companyId === "__none") return;
    const rate = Number(companyRate);

    if (!Number.isFinite(rate) || rate < 0 || rate > 100) {
      toast.error(t("commissions.invalid_rate", { defaultValue: "Le taux doit etre entre 0 et 100." }));
      return;
    }

    setSavingKey("company:new");
    try {
      await upsertCommissionSettingSupabase({
        scope: "company",
        countryId: null,
        companyId,
        rate,
        paidBy: companyPaidBy,
      });
      toast.success(t("commissions.updated"));
      setCompanyId("__none");
      setCompanyRate("0");
      setCompanyPaidBy("company");
      onChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("commissions.update_error"));
    } finally {
      setSavingKey(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="rounded-xl border p-4 space-y-3">
        <div>
          <h3 className="font-semibold text-sm">
            {t("commissions.country_settings", { defaultValue: "Taux par pays" })}
          </h3>
          <p className="text-xs text-muted-foreground">
            {t("commissions.country_settings_desc", {
              defaultValue: "Le taux pays s'applique par défaut aux ventes tiers de toutes les compagnies du pays.",
            })}
          </p>
        </div>

        {countrySettings.length === 0 ? (
          <EmptyState
            icon={GlobeIcon}
            title={t("geo.no_countries")}
            description={t("commissions.apply_migration", {
              defaultValue: "Appliquez le script 018 pour charger les pays autorisés.",
            })}
          />
        ) : (
          <div className="divide-y">
            {countrySettings.map((setting) => {
              const draft = draftFor(setting);
              const key = settingKey(setting);
              return (
                <div key={key} className="grid gap-3 py-3 md:grid-cols-[1fr_120px_160px_auto] md:items-end">
                  <div className="min-w-0">
                    <p className="font-medium truncate">{setting.countryName}</p>
                    <p className="text-xs text-muted-foreground">
                      {setting.source === "unset"
                        ? t("commissions.unset", { defaultValue: "Aucun taux configure" })
                        : t("commissions.configured", { defaultValue: "Configure" })}
                      {setting.updatedByName ? ` · ${setting.updatedByName}` : ""}
                    </p>
                  </div>
                  <div className="space-y-1">
                    <Label>{t("commissions.rate")}</Label>
                    <Input
                      type="number"
                      min={0}
                      max={100}
                      step={0.1}
                      value={draft.rate}
                      onChange={(event) => setDraft(setting, { rate: event.target.value })}
                    />
                  </div>
                  <div className="space-y-1">
                    <Label>{t("commissions.paid_by")}</Label>
                    <Select
                      value={draft.paidBy}
                      onValueChange={(value) => setDraft(setting, { paidBy: value === "traveler" ? "traveler" : "company" })}
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="company">{t("commissions.paid_by_company")}</SelectItem>
                        <SelectItem value="traveler">{t("commissions.paid_by_traveler")}</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="flex gap-2 md:justify-end">
                    <Button
                      size="sm"
                      onClick={() => handleSave(setting)}
                      disabled={savingKey === key}
                    >
                      {savingKey === key ? tc("buttons.saving") : tc("buttons.save")}
                    </Button>
                    {setting.id && (
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => handleDelete(setting)}
                        disabled={savingKey === key}
                        aria-label={t("commissions.delete", { defaultValue: "Supprimer" })}
                      >
                        <TrashIcon className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="rounded-xl border p-4 space-y-3">
        <div>
          <h3 className="font-semibold text-sm">
            {t("commissions.company_overrides", { defaultValue: "Exceptions par compagnie" })}
          </h3>
          <p className="text-xs text-muted-foreground">
            {t("commissions.company_overrides_desc", {
              defaultValue: "A utiliser seulement quand une compagnie doit remplacer le taux de son pays.",
            })}
          </p>
        </div>

        <div className="grid gap-3 rounded-lg bg-muted/50 p-3 md:grid-cols-[1fr_120px_160px_auto] md:items-end">
          <div className="space-y-1">
            <Label>{t("commissions.company")}</Label>
            <Select value={companyId} onValueChange={setCompanyId}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="__none">{t("commissions.select_company")}</SelectItem>
                {companies.map((company) => (
                  <SelectItem key={company.id} value={company.id}>
                    {company.name} · {company.countryName ?? ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>{t("commissions.rate")}</Label>
            <Input
              type="number"
              min={0}
              max={100}
              step={0.1}
              value={companyRate}
              onChange={(event) => setCompanyRate(event.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label>{t("commissions.paid_by")}</Label>
            <Select
              value={companyPaidBy}
              onValueChange={(value) => setCompanyPaidBy(value === "traveler" ? "traveler" : "company")}
            >
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="company">{t("commissions.paid_by_company")}</SelectItem>
                <SelectItem value="traveler">{t("commissions.paid_by_traveler")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button
            size="sm"
            className="gap-2"
            onClick={handleAddCompanyOverride}
            disabled={companyId === "__none" || savingKey === "company:new"}
          >
            <PlusIcon className="h-4 w-4" />
            {t("commissions.add_override", { defaultValue: "Ajouter" })}
          </Button>
        </div>

        {companySettings.length === 0 ? (
          <p className="text-xs text-muted-foreground">
            {t("commissions.no_company_overrides", { defaultValue: "Aucune exception compagnie." })}
          </p>
        ) : (
          <div className="divide-y">
            {companySettings.map((setting) => {
              const draft = draftFor(setting);
              const key = settingKey(setting);
              return (
                <div key={key} className="grid gap-3 py-3 md:grid-cols-[1fr_120px_160px_auto] md:items-end">
                  <div className="min-w-0">
                    <p className="font-medium truncate">{setting.companyName}</p>
                    <p className="text-xs text-muted-foreground">{setting.countryName}</p>
                  </div>
                  <Input
                    type="number"
                    min={0}
                    max={100}
                    step={0.1}
                    value={draft.rate}
                    onChange={(event) => setDraft(setting, { rate: event.target.value })}
                  />
                  <Select
                    value={draft.paidBy}
                    onValueChange={(value) => setDraft(setting, { paidBy: value === "traveler" ? "traveler" : "company" })}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="company">{t("commissions.paid_by_company")}</SelectItem>
                      <SelectItem value="traveler">{t("commissions.paid_by_traveler")}</SelectItem>
                    </SelectContent>
                  </Select>
                  <div className="flex gap-2 md:justify-end">
                    <Button size="sm" onClick={() => handleSave(setting)} disabled={savingKey === key}>
                      {savingKey === key ? tc("buttons.saving") : tc("buttons.save")}
                    </Button>
                    {setting.id && (
                      <Button size="sm" variant="outline" onClick={() => handleDelete(setting)} disabled={savingKey === key}>
                        <TrashIcon className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function EmptyState({
  icon: Icon,
  title,
  description,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
}) {
  return (
    <div className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
      <Icon className="mx-auto mb-2 h-6 w-6 opacity-50" />
      <p className="font-medium text-foreground">{title}</p>
      {description && <p className="mt-1">{description}</p>}
    </div>
  );
}

function SimpleList({
  emptyIcon,
  emptyTitle,
  items,
}: {
  emptyIcon: LucideIcon;
  emptyTitle: string;
  items: { id: string; title: string; meta: string }[];
}) {
  if (items.length === 0) {
    return <EmptyState icon={emptyIcon} title={emptyTitle} description="" />;
  }
  return (
    <div className="divide-y">
      {items.map((item) => (
        <div key={item.id} className="py-3">
          <p className="font-medium">{item.title}</p>
          {item.meta && <p className="text-xs text-muted-foreground">{item.meta}</p>}
        </div>
      ))}
    </div>
  );
}

function ComingSoon({
  icon: Icon,
  title,
  description,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
}) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Icon className="w-4 h-4" />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <EmptyState icon={Icon} title={title} description={description} />
      </CardContent>
    </Card>
  );
}
