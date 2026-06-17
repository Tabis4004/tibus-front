import { Suspense, useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  ArrowLeftIcon,
  BuildingIcon,
  CircleDollarSignIcon,
  CreditCardIcon,
  GlobeIcon,
  KeyIcon,
  LayoutDashboardIcon,
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
  LayersIcon,
  TrendingUpIcon,
  type LucideIcon,
  BookOpenIcon,
} from "lucide-react";
import { toast } from "sonner";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { canAccessCommercialOffer } from "@/lib/auth/commercial-offer-access.ts";
import {
  canAccessPlatformAdminPanel,
  canMutateCompanyOperationalData,
  isDemarcheurRole,
  isAdminPaysRole,
} from "@/lib/auth/company-access.ts";
import {
  deleteCommissionSettingSupabase,
  resolveCompanyPlatformCommission,
  upsertCommissionSettingSupabase,
  type CommissionSetting,
} from "@/lib/supabase/accounting.ts";
import {
  loadAdminStats,
  loadAdminTabData,
  type AdminDataKey,
  type AdminDataSlice,
  type AdminStats,
  type AdminTabId,
  type SupabaseCompanyRow,
} from "./admin-data-loaders.ts";
import {
  ContactSettingsPanel,
  GatewayFeeSettingsPanel,
  GuaranteeFundManager,
  InvestorPlanPanel,
  LegalPagesPanel,
  PaymentGatewaySettingsPanel,
  PlatformLoyaltySettingsPanel,
  PlatformScalingMetricsPanel,
  StakeholderCommissionPanel,
  StakeholderPayoutDashboardPanel,
  SellerCommissionDashboardPanel,
  SupabasePlansTab,
  SupabaseSubscriptionsTab,
  TpePosDiagnosticsPanel,
  TravelerBookingNoticePanel,
} from "./admin-lazy-panels.tsx";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import { enterSuperAdminOwnerCompanyContext } from "@/lib/supabase/owner-company.ts";
import { refreshOwnerCompanyContext } from "@/hooks/use-owner-company.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import ConsoleGridTile from "@/components/console/ConsoleGridTile.tsx";
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
import {
  Accordion,
} from "@/components/ui/accordion.tsx";
import { cn } from "@/lib/utils.ts";
import AdminCollapsibleSection from "./_components/AdminCollapsibleSection.tsx";
import AdminAccessGate from "./_components/AdminAccessGate.tsx";
import AdminTabAuditHub from "./_components/AdminTabAuditHub.tsx";

function resolveCompanyCommissionDisplay(
  company: SupabaseCompanyRow,
  settings: CommissionSetting[],
) {
  const resolved = resolveCompanyPlatformCommission(company, settings);
  return { rate: resolved.rate, paidBy: resolved.paidBy };
}

type TabId = AdminTabId;

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
  "investor_plan",
  "landing",
];

function isTabId(value: string | null): value is TabId {
  return value !== null && TAB_IDS.includes(value as TabId);
}

type AdminData = AdminDataSlice;

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
  platformCommissions: null,
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
  const [errors, setErrors] = useState<Partial<Record<AdminDataKey, string>>>({});
  const [stats, setStats] = useState<AdminStats>({
    users: 0,
    companies: 0,
    activeSubscriptions: 0,
    cities: 0,
  });
  const [tabRefreshNonce, setTabRefreshNonce] = useState(0);
  const [managingCompanyId, setManagingCompanyId] = useState<string | null>(null);
  const reloadCurrentTab = useCallback(() => {
    setTabRefreshNonce((nonce) => nonce + 1);
  }, []);
  const [commissionAccordionSections, setCommissionAccordionSections] = useState<string[]>([]);
  const canAccessAdminPanel = canAccessPlatformAdminPanel(appUser.roles, appUser.isSuperAdmin);

  const isAdminPays = isAdminPaysRole(appUser.roles);
  const isDemarcheur = isDemarcheurRole(appUser.roles);
  const adminCountryId = appUser.profile?.countryId ?? null;

  const adminDataScope = useMemo(() => {
    if (appUser.isSuperAdmin) {
      return { countryId: null as string | null, recruitedByUserId: null as string | null };
    }
    if (isDemarcheur) {
      return {
        countryId: null as string | null,
        recruitedByUserId: appUser.profile?.id ?? null,
      };
    }
    if (isAdminPays) {
      return { countryId: adminCountryId, recruitedByUserId: null as string | null };
    }
    return { countryId: null as string | null, recruitedByUserId: null as string | null };
  }, [adminCountryId, appUser.isSuperAdmin, appUser.profile?.id, isAdminPays, isDemarcheur]);

  useEffect(() => {
    if (appUser.isReady && !appUser.isSuperAdmin && (isAdminPays || isDemarcheur)) {
      setTab((current) => (current === "companies" ? "companies" : "commissions"));
    }
  }, [appUser.isReady, appUser.isSuperAdmin, isAdminPays, isDemarcheur]);

  useEffect(() => {
    if (!appUser.isReady) return;

    const tabParam = searchParams.get("tab");
    if (!isTabId(tabParam)) return;

    if (!appUser.isSuperAdmin) {
      if (tabParam === "commissions" || tabParam === "guarantee_fund" || tabParam === "companies") {
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

  const handleManageCompanyAsOwner = async (companyId: string) => {
    const appUserId = appUser.profile?.id;
    if (!appUserId) return;
    setManagingCompanyId(companyId);
    try {
      await enterSuperAdminOwnerCompanyContext(appUserId, companyId, {
        isSuperAdmin: appUser.isSuperAdmin,
        ownedCompanyIds: appUser.ownedCompanyIds,
      });
      refreshOwnerCompanyContext();
      navigate(`/${lng ?? "fr"}/owner`);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Impossible d'ouvrir la console owner.",
      );
    } finally {
      setManagingCompanyId(null);
    }
  };

  useEffect(() => {
    if (!appUser.isReady || !canAccessAdminPanel) return;

    let cancelled = false;
    void loadAdminStats(appUser.isSuperAdmin, appUser.hasDbSuperAdmin)
      .then((nextStats) => {
        if (!cancelled) setStats(nextStats);
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
    };
  }, [appUser.hasDbSuperAdmin, appUser.isReady, appUser.isSuperAdmin, canAccessAdminPanel, tabRefreshNonce]);

  useEffect(() => {
    if (!appUser.isReady) return;

    if (!canAccessAdminPanel) {
      navigate(`/${lng ?? "en"}`, { replace: true });
      return;
    }

    let cancelled = false;
    setIsLoading(true);

    void loadAdminTabData(
      tab,
      appUser.isSuperAdmin,
      appUser.hasDbSuperAdmin,
      adminDataScope,
    )
      .then((result) => {
        if (cancelled) return;
        setData((current) => ({ ...current, ...result.data }));
        setErrors((current) => ({ ...current, ...result.errors }));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [
    adminDataScope,
    appUser.hasDbSuperAdmin,
    appUser.isReady,
    appUser.isSuperAdmin,
    canAccessAdminPanel,
    lng,
    navigate,
    tab,
    tabRefreshNonce,
  ]);

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
    { id: "investor_plan", label: t("tabs.investor_plan"), icon: TrendingUpIcon },
    { id: "landing", label: t("tabs.landing", { defaultValue: "Landing Page" }), icon: PencilIcon },
  ];
  const visibleTabs = appUser.isSuperAdmin
    ? tabs
    : tabs.filter((item) => item.id === "commissions" || item.id === "guarantee_fund" || item.id === "companies");
  return (
    <AdminAccessGate>
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
        <div className="flex flex-wrap items-center justify-end gap-2">
          {canAccessCommercialOffer(appUser.roles, appUser.isSuperAdmin) && (
            <Link to={`/${lng ?? "fr"}/admin/commercial-offer`}>
              <Button variant="outline" size="sm" className="gap-2">
                <FileTextIcon className="w-4 h-4" />
                {t("commercial_offer.nav_title", { defaultValue: "Offre commerciale" })}
              </Button>
            </Link>
          )}
          {(appUser.isSuperAdmin || appUser.roles.includes("admin_pays")) && (
            <Link to={`/${lng ?? "fr"}/manual/admin-pays`}>
              <Button variant="outline" size="sm" className="gap-2">
                <BookOpenIcon className="w-4 h-4" />
                {tc("manual.country_admin_nav_title", { defaultValue: "Manuel admin pays" })}
              </Button>
            </Link>
          )}
          <Link to={`/${lng}`}>
            <Button variant="outline" size="sm" className="gap-2">
              <ArrowLeftIcon className="w-4 h-4" />
              {tc("buttons.back", { defaultValue: "Back" })}
            </Button>
          </Link>
        </div>
      </div>

      {appUser.isSuperAdmin ? (
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <ConsoleGridTile
            tileIndex={0}
            icon={UsersIcon}
            label={t("total_users")}
            value={stats.users.toLocaleString()}
          />
          <ConsoleGridTile
            tileIndex={1}
            icon={BuildingIcon}
            label={t("total_companies")}
            value={stats.companies.toLocaleString()}
          />
          <ConsoleGridTile
            tileIndex={2}
            icon={CreditCardIcon}
            label={t("active_subs")}
            value={stats.activeSubscriptions.toLocaleString()}
          />
          <ConsoleGridTile
            tileIndex={3}
            icon={GlobeIcon}
            label={t("geo.cities", { defaultValue: "Villes" })}
            value={stats.cities.toLocaleString()}
          />
        </div>
      ) : null}

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
            {appUser.isAdminSandbox && (
              <p className="mb-4 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
                {t("supabase_admin.sandbox_users_hint", {
                  defaultValue:
                    "Mode sandbox UI : vous voyez l'admin sans super_admin en base. Exécutez 084_grant_platform_roles_live.sql dans Supabase SQL Editor, puis déconnectez-vous et reconnectez-vous.",
                })}
              </p>
            )}
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

      {tab === "users" && <AdminTabAuditHub tab="users" />}

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
                {data.companies.map((company) => {
                  const commission = resolveCompanyCommissionDisplay(
                    company,
                    data.commissionSettings ?? [],
                  );
                  return (
                  <div key={company.id} className="py-3 flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <Link
                        to={`/${lng ?? "fr"}/admin/company/${company.id}`}
                        className="font-medium truncate block hover:text-primary"
                      >
                        {company.name}
                      </Link>
                      <p className="text-xs text-muted-foreground truncate">
                        {company.managerName ?? t("owner_label")} · {company.countryName ?? t("geo.countries")}
                      </p>
                    </div>
                    <div className="flex flex-wrap justify-end items-center gap-1">
                      {(appUser.isSuperAdmin ||
                        canMutateCompanyOperationalData(
                          appUser.roles,
                          appUser.isSuperAdmin,
                          company.id,
                          appUser.ownedCompanyIds,
                        )) && (
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          className="h-7 text-xs"
                          asChild
                        >
                          <Link to={`/${lng ?? "fr"}/admin/company/${company.id}`}>
                            <LayersIcon className="w-3.5 h-3.5 mr-1" />
                            {t("feature_modules.configure", { defaultValue: "Modules" })}
                          </Link>
                        </Button>
                      )}
                      {appUser.isSuperAdmin ? (
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          className="h-7 text-xs"
                          disabled={managingCompanyId === company.id}
                          onClick={() => void handleManageCompanyAsOwner(company.id)}
                        >
                          <LayoutDashboardIcon className="w-3.5 h-3.5 mr-1" />
                          {t("manage_resources")}
                        </Button>
                      ) : null}
                      <Badge variant={company.isActive ? "default" : "secondary"}>
                        {company.isActive ? tc("status.active") : tc("status.inactive")}
                      </Badge>
                      <Badge variant="secondary">
                        {commission.rate}% ·{" "}
                        {commission.paidBy === "traveler"
                          ? t("commissions.paid_by_traveler_short", { defaultValue: "voyageur" })
                          : t("commissions.paid_by_company_short", { defaultValue: "compagnie" })}
                      </Badge>
                    </div>
                  </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {tab === "companies" && <AdminTabAuditHub tab="companies" />}

      {tab === "subscriptions" && (
        <>
        <AdminTabSuspense>
        <SupabaseSubscriptionsTab
          companies={data.companies.map((company) => ({
            id: company.id,
            name: company.name,
            countryId: company.countryId,
            countryName: company.countryName,
          }))}
          onDataChanged={reloadCurrentTab}
        />
        </AdminTabSuspense>
        <AdminTabAuditHub tab="subscriptions" />
        </>
      )}

      {tab === "plans" && (
        <>
        <AdminTabSuspense>
        <SupabasePlansTab
          countries={data.countries}
          onDataChanged={reloadCurrentTab}
        />
        </AdminTabSuspense>
        <AdminTabAuditHub tab="plans" />
        </>
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
                <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
                  <ConsoleGridTile
                    tileIndex={0}
                    icon={CircleDollarSignIcon}
                    label={t("commissions.traveler_online_captured", {
                      defaultValue: "Commissions voyageur en ligne",
                    })}
                    value={`${(data.platformCommissions?.travelerOnlineCaptured ?? data.platformCommissions?.capturedTotal ?? 0).toLocaleString()} ${data.platformCommissions?.currency ?? data.commissions?.currency ?? "XOF"}`}
                  />
                  <ConsoleGridTile
                    tileIndex={1}
                    icon={CircleDollarSignIcon}
                    label={t("commissions.counter_company_captured", {
                      defaultValue: "Commissions guichet (compagnie)",
                    })}
                    value={`${(data.platformCommissions?.counterCompanyCaptured ?? 0).toLocaleString()} ${data.platformCommissions?.currency ?? "XOF"}`}
                  />
                  <ConsoleGridTile
                    tileIndex={2}
                    icon={CircleDollarSignIcon}
                    label={t("commissions.stakeholder_due", { defaultValue: "Solde stakeholders" })}
                    value={`${(data.platformCommissions?.stakeholderPending ?? 0).toLocaleString()} ${data.platformCommissions?.currency ?? "XOF"}`}
                  />
                  <ConsoleGridTile
                    tileIndex={3}
                    icon={PercentIcon}
                    label={t("commissions.traveler_tickets", { defaultValue: "Billets voyageur payés" })}
                    value={(data.platformCommissions?.ticketCount ?? 0).toLocaleString()}
                  />
                </div>
                <div className="grid gap-2 text-xs text-muted-foreground md:grid-cols-2">
                  <p>
                    {t("commissions.traveler_nominal_hint", {
                      defaultValue: "Montant nominal réservations en ligne : {{amount}} {{currency}} ({{count}} billet(s)).",
                      amount: data.platformCommissions?.travelerNominalTotal ?? 0,
                      currency: data.platformCommissions?.currency ?? "XOF",
                      count: data.platformCommissions?.ticketCount ?? 0,
                    })}
                  </p>
                  {(data.platformCommissions?.counterCompanyCaptured ?? 0) > 0 && (
                    <p>
                      {t("commissions.counter_nominal_hint", {
                        defaultValue:
                          "Guichet : {{commission}} {{currency}} sur {{nominal}} {{currency}} ({{count}} vente(s)) — à imputer au fonds de garantie compagnie.",
                        commission: data.platformCommissions?.counterCompanyCaptured ?? 0,
                        nominal: data.platformCommissions?.counterNominalTotal ?? 0,
                        currency: data.platformCommissions?.currency ?? "XOF",
                        count: data.platformCommissions?.counterTicketCount ?? 0,
                      })}
                    </p>
                  )}
                </div>
                <p className="text-xs text-muted-foreground">
                  {t("commissions.traveler_paid_hint", {
                    defaultValue:
                      "Les commissions en ligne ne peuvent pas dépasser la marge sur les réservations voyageur. Les ventes au guichet (payées par la compagnie) sont comptabilisées séparément.",
                  })}
                </p>
                {errors.commissions && (
                  <p className="rounded-lg bg-muted p-3 text-sm text-muted-foreground">
                    {t("supabase_admin.commissions_rpc_missing", {
                      defaultValue: "Les commissions Supabase ne sont pas disponibles. Appliquez les derniers scripts SQL.",
                    })}{" "}
                    <span className="text-destructive">{errors.commissions}</span>
                  </p>
                )}
                {canAccessCommercialOffer(appUser.roles, appUser.isSuperAdmin) ? (
                  <div className="flex justify-end print:hidden">
                    <Button variant="outline" size="sm" asChild>
                      <Link to={`/${lng ?? "fr"}/admin/commercial-offer`}>
                        <FileTextIcon className="w-4 h-4 mr-1.5" />
                        {t("commercial_offer.nav_title", { defaultValue: "Offre commerciale" })}
                      </Link>
                    </Button>
                  </div>
                ) : null}
                <AdminTabSuspense>
                  <StakeholderPayoutDashboardPanel
                    embedded
                    alwaysVisible
                    countryId={
                      appUser.isSuperAdmin
                        ? null
                        : adminCountryId ?? data.countries[0]?.id ?? null
                    }
                  />
                </AdminTabSuspense>
                <Accordion type="multiple" value={commissionAccordionSections} onValueChange={setCommissionAccordionSections} className="flex flex-col gap-2">
                  <CommissionSettingsManager
                    settings={data.commissionSettings}
                    companies={data.companies}
                    onChanged={reloadCurrentTab}
                  />
                  {appUser.isSuperAdmin && (
                    <AdminCollapsibleSection
                      value="payment-gateway"
                      title={t("payment_gateway.title", { defaultValue: "Passerelle de paiement" })}
                      auditModuleKey="admin.commissions.payment_gateway"
                    >
                      {commissionAccordionSections.includes("payment-gateway") ? (
                        <AdminTabSuspense>
                          <PaymentGatewaySettingsPanel embedded />
                        </AdminTabSuspense>
                      ) : null}
                    </AdminCollapsibleSection>
                  )}
                  <AdminCollapsibleSection
                    value="stakeholder-commissions"
                    title={t("stakeholder_commissions.title", { defaultValue: "Attribution stakeholders" })}
                    auditModuleKey="admin.commissions.stakeholder_attribution"
                  >
                    {commissionAccordionSections.includes("stakeholder-commissions") ? (
                      <AdminTabSuspense>
                        <StakeholderCommissionPanel
                          embedded
                          enabled
                          countries={data.countries.map((country) => ({
                            id: country.id,
                            name: country.name,
                          }))}
                          companies={data.companies.map((company) => ({
                            id: company.id,
                            name: company.name,
                            countryId: company.countryId,
                            recruitedByUserId: company.recruitedByUserId,
                            commissionRate: company.commissionRate,
                          }))}
                          commissionSettings={data.commissionSettings ?? []}
                          onCommissionSettingsChanged={reloadCurrentTab}
                        />
                      </AdminTabSuspense>
                    ) : (
                      <p className="text-xs text-muted-foreground">
                        {t("stakeholder_commissions.realtime_hint")}
                      </p>
                    )}
                  </AdminCollapsibleSection>
                  <AdminCollapsibleSection
                    value="seller-commissions"
                    title={t("seller_commissions.title", { defaultValue: "Commissions vendeurs indépendants / master" })}
                    auditModuleKey="admin.commissions.seller_dashboard"
                  >
                    {commissionAccordionSections.includes("seller-commissions") ? (
                      <AdminTabSuspense>
                        <SellerCommissionDashboardPanel embedded />
                      </AdminTabSuspense>
                    ) : null}
                  </AdminCollapsibleSection>
                  <AdminCollapsibleSection
                    value="gateway-fees"
                    title={t("gateway_fees.title", { defaultValue: "Frais passerelle" })}
                    auditModuleKey="admin.commissions.gateway_fees"
                  >
                    {commissionAccordionSections.includes("gateway-fees") ? (
                      <AdminTabSuspense>
                        <GatewayFeeSettingsPanel
                          embedded
                          countries={data.countries.map((country) => ({
                            id: country.id,
                            name: country.name,
                          }))}
                        />
                      </AdminTabSuspense>
                    ) : null}
                  </AdminCollapsibleSection>
                  {appUser.isSuperAdmin && (
                    <AdminCollapsibleSection
                      value="booking-notice"
                      title={t("booking_notice.title", { defaultValue: "Message voyageur au paiement" })}
                      auditModuleKey="admin.commissions.booking_notice"
                    >
                      {commissionAccordionSections.includes("booking-notice") ? (
                        <AdminTabSuspense>
                          <TravelerBookingNoticePanel
                            embedded
                            countries={data.countries.map((country) => ({
                              id: country.id,
                              name: country.name,
                            }))}
                          />
                        </AdminTabSuspense>
                      ) : null}
                    </AdminCollapsibleSection>
                  )}
                </Accordion>
                <AdminTabAuditHub tab="commissions" />
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
          <AdminTabSuspense>
            <GuaranteeFundManager
              companies={data.companies.map((company) => ({
                id: company.id,
                name: company.name,
                currency: company.currency,
                countryName: company.countryName,
              }))}
            />
          </AdminTabSuspense>
          <AdminTabAuditHub tab="guarantee_fund" />
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

      {tab === "geography" && <AdminTabAuditHub tab="geography" />}

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

      {tab === "roles" && <AdminTabAuditHub tab="roles" />}

      {tab === "contact" && (
        <>
        <AdminTabSuspense>
          <ContactSettingsPanel
            companies={data.companies.map((company) => ({ id: company.id, name: company.name }))}
          />
        </AdminTabSuspense>
        <AdminTabAuditHub tab="contact" />
        </>
      )}

      {tab === "loyalty" && (
        <>
          <AdminTabSuspense>
            <PlatformLoyaltySettingsPanel />
          </AdminTabSuspense>
          <AdminTabAuditHub tab="loyalty" />
        </>
      )}

      {tab === "legal" && appUser.isSuperAdmin && (
        <>
          <AdminTabSuspense>
            <LegalPagesPanel />
          </AdminTabSuspense>
          <AdminTabAuditHub tab="legal" />
        </>
      )}

      {tab === "scaling_metrics" && appUser.isSuperAdmin && (
        <>
        <AdminTabSuspense>
          <div className="space-y-6">
            <TpePosDiagnosticsPanel />
            <PlatformScalingMetricsPanel />
          </div>
        </AdminTabSuspense>
        <AdminTabAuditHub tab="scaling_metrics" />
        </>
      )}

      {tab === "investor_plan" && appUser.isSuperAdmin && (
        <>
          <AdminTabSuspense>
            <InvestorPlanPanel />
          </AdminTabSuspense>
          <AdminTabAuditHub tab="investor_plan" />
        </>
      )}

      {tab === "landing" && (
        <>
        <ComingSoon
          icon={PencilIcon}
          title={t("tabs.landing", { defaultValue: "Landing Page" })}
          description={t("supabase_admin.landing_placeholder", {
            defaultValue: "Le CMS Landing Page est encore branché sur Convex. Le panneau Supabase affiche ce statut au lieu d'un onglet vide.",
          })}
        />
        <AdminTabAuditHub tab="landing" />
        </>
      )}
    </div>
    </AdminAccessGate>
  );
}

function AdminTabSuspense({ children }: { children: ReactNode }) {
  return <Suspense fallback={<LoadingRows />}>{children}</Suspense>;
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
      void recordPlatformAuditSupabase({
        moduleKey:
          setting.scope === "country"
            ? "admin.commissions.country_rates"
            : "admin.commissions.company_overrides",
        action: "update",
        summary: `Commission ${setting.countryName ?? setting.companyName ?? ""} → ${rate}% (${draft.paidBy})`,
        metadata: { scope: setting.scope, rate, paidBy: draft.paidBy },
      });
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
      void recordPlatformAuditSupabase({
        moduleKey:
          setting.scope === "country"
            ? "admin.commissions.country_rates"
            : "admin.commissions.company_overrides",
        action: "delete",
        summary: `Commission supprimée : ${setting.countryName ?? setting.companyName ?? ""}`,
        metadata: { scope: setting.scope, settingId: setting.id },
      });
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
      const company = companies.find((row) => row.id === companyId);
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.company_overrides",
        action: "create",
        summary: `Exception compagnie ${company?.name ?? companyId} → ${rate}% (${companyPaidBy})`,
        metadata: { companyId, rate, paidBy: companyPaidBy },
      });
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
    <>
      <AdminCollapsibleSection
        value="commission-country-rates"
        title={t("commissions.country_settings", { defaultValue: "Taux par pays" })}
        count={countrySettings.length}
        auditModuleKey="admin.commissions.country_rates"
      >
        <p className="text-xs text-muted-foreground">
          {t("commissions.country_settings_desc", {
            defaultValue: "Le taux pays s'applique par défaut aux ventes tiers de toutes les compagnies du pays.",
          })}
        </p>

        {countrySettings.length === 0 ? (
            <EmptyState
              icon={GlobeIcon}
              title={t("geo.no_countries")}
              description={t("commissions.apply_migration", {
                defaultValue: "Appliquez le script 018 pour charger les pays autorisés.",
              })}
            />
          ) : (
            <div className="divide-y rounded-lg border">
              {countrySettings.map((setting) => {
                const draft = draftFor(setting);
                const key = settingKey(setting);
                return (
                  <div key={key} className="grid gap-3 p-3 md:grid-cols-[1fr_120px_160px_auto] md:items-end">
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
      </AdminCollapsibleSection>

      <AdminCollapsibleSection
        value="commission-company-overrides"
        title={t("commissions.company_overrides", { defaultValue: "Exceptions par compagnie" })}
        count={companySettings.length}
        auditModuleKey="admin.commissions.company_overrides"
      >
        <p className="text-xs text-muted-foreground">
            {t("commissions.company_overrides_desc", {
              defaultValue: "A utiliser seulement quand une compagnie doit remplacer le taux de son pays.",
            })}
          </p>

          <div className="grid gap-3 rounded-lg border bg-muted/50 p-3 md:grid-cols-[1fr_120px_160px_auto] md:items-end">
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
            <div className="divide-y rounded-lg border">
              {companySettings.map((setting) => {
                const draft = draftFor(setting);
                const key = settingKey(setting);
                return (
                  <div key={key} className="grid gap-3 p-3 md:grid-cols-[1fr_120px_160px_auto] md:items-end">
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
      </AdminCollapsibleSection>
    </>
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
