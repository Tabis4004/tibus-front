import { NavLink, Outlet, useNavigate, useParams } from "react-router-dom";
import { useEffect, useState } from "react";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import {
  LayoutDashboardIcon,
  BusIcon,
  MapPinIcon,
  RouteIcon,
  CalendarIcon,
  UsersIcon,
  BuildingIcon,
  MenuIcon,
  XIcon,
  CreditCardIcon,
  BarChart3Icon,
  FileTextIcon,
  MapIcon,
  UserCheckIcon,
  MessageSquareIcon,
  TagIcon,
  LandmarkIcon,
  WalletIcon,
  PackageIcon,
  ReceiptTextIcon,
  PercentIcon,
  ScanLineIcon,
  BookOpenIcon,
} from "lucide-react";
import { cn } from "@/lib/utils.ts";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { canAccessGuaranteeFund } from "@/lib/owner-console-modules.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { getMyCompanySupabase, type OwnerCompany } from "@/lib/supabase/owner-company";
import { OwnerCompanyProvider, useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import OwnerCompanySwitcher from "./_components/OwnerCompanySwitcher.tsx";
import ExploreFeaturesButton from "@/components/onboarding/ExploreFeaturesButton.tsx";

type NavItem = {
  toSuffix: string;
  labelKey: string;
  icon: typeof LayoutDashboardIcon;
  end?: boolean;
};

type NavSection = {
  titleKey: string;
  items: NavItem[];
};

const CONVEX_NAV_SECTIONS: NavSection[] = [
  {
    titleKey: "sidebar.section_main",
    items: [
      { toSuffix: "/owner", labelKey: "sidebar.overview", icon: LayoutDashboardIcon, end: true },
      { toSuffix: "/owner/company", labelKey: "sidebar.my_company", icon: BuildingIcon },
      { toSuffix: "/owner/reviews", labelKey: "sidebar.reviews", icon: MessageSquareIcon },
      { toSuffix: "/owner/promo-codes", labelKey: "sidebar.promo_codes", icon: TagIcon },
      { toSuffix: "/owner/subscription", labelKey: "sidebar.subscription", icon: CreditCardIcon },
    ],
  },
  {
    titleKey: "sidebar.section_analytics",
    items: [
      { toSuffix: "/owner/analytics", labelKey: "sidebar.analytics", icon: BarChart3Icon, end: true },
      { toSuffix: "/owner/analytics/tickets", labelKey: "sidebar.ticket_reports", icon: FileTextIcon },
      { toSuffix: "/owner/analytics/trips", labelKey: "sidebar.trip_reports", icon: MapIcon },
      { toSuffix: "/owner/analytics/travelers", labelKey: "sidebar.travelers", icon: UserCheckIcon },
    ],
  },
  {
    titleKey: "sidebar.section_operations",
    items: [
      { toSuffix: "/owner/buses", labelKey: "sidebar.fleet", icon: BusIcon },
      { toSuffix: "/owner/stations", labelKey: "sidebar.stations", icon: MapPinIcon },
      { toSuffix: "/owner/routes", labelKey: "sidebar.routes", icon: RouteIcon },
      { toSuffix: "/owner/trips", labelKey: "sidebar.trips", icon: CalendarIcon },
      { toSuffix: "/owner/sellers", labelKey: "sidebar.sellers", icon: UsersIcon },
    ],
  },
];

const SUPABASE_NAV_SECTIONS: NavSection[] = [
  {
    titleKey: "sidebar.section_console",
    items: [
      { toSuffix: "/owner", labelKey: "sidebar.overview", icon: LayoutDashboardIcon, end: true },
      { toSuffix: "/owner/sales", labelKey: "sidebar.sales", icon: ReceiptTextIcon },
      { toSuffix: "/owner/guarantee-fund", labelKey: "sidebar.guarantee_fund", icon: LandmarkIcon },
      { toSuffix: "/owner/cash-register", labelKey: "sidebar.cash_register", icon: WalletIcon },
      { toSuffix: "/owner/colis", labelKey: "sidebar.colis", icon: PackageIcon },
      { toSuffix: "/verify/scan", labelKey: "sidebar.scanner", icon: ScanLineIcon },
    ],
  },
  {
    titleKey: "sidebar.section_main",
    items: [
      { toSuffix: "/owner/company", labelKey: "sidebar.my_company", icon: BuildingIcon },
      { toSuffix: "/owner/trips", labelKey: "sidebar.trips", icon: CalendarIcon },
      { toSuffix: "/owner/promo-codes", labelKey: "sidebar.promo_codes", icon: TagIcon },
      { toSuffix: "/owner/loyalty", labelKey: "sidebar.loyalty", icon: PercentIcon },
      { toSuffix: "/owner/cancellation", labelKey: "sidebar.cancellation", icon: FileTextIcon },
      { toSuffix: "/owner/messages", labelKey: "sidebar.messages", icon: MessageSquareIcon },
    ],
  },
  {
    titleKey: "sidebar.section_analytics",
    items: [
      { toSuffix: "/owner/analytics", labelKey: "sidebar.analytics", icon: BarChart3Icon, end: true },
    ],
  },
  {
    titleKey: "sidebar.section_operations",
    items: [
      { toSuffix: "/owner/buses", labelKey: "sidebar.fleet", icon: BusIcon },
      { toSuffix: "/owner/stations", labelKey: "sidebar.stations", icon: MapPinIcon },
      { toSuffix: "/owner/routes", labelKey: "sidebar.routes", icon: RouteIcon },
      { toSuffix: "/owner/sellers", labelKey: "sidebar.sellers", icon: UsersIcon },
    ],
  },
  {
    titleKey: "sidebar.section_help",
    items: [
      { toSuffix: "/manual/compagnie", labelKey: "sidebar.company_manual", icon: BookOpenIcon },
    ],
  },
];

function getNavSections(): NavSection[] {
  return isSupabaseAuth() ? SUPABASE_NAV_SECTIONS : CONVEX_NAV_SECTIONS;
}

function SidebarCompanyCard({
  name,
  logoUrl,
  planLabel,
  noPlanLabel,
}: {
  name?: string;
  logoUrl?: string | null;
  planLabel?: string | null;
  noPlanLabel: string;
}) {
  return (
    <div className="px-3 mb-5">
      <div className="flex items-center gap-3 p-3 rounded-xl border bg-muted/30">
        <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
          {logoUrl ? (
            <img src={logoUrl} alt="logo" className="w-9 h-9 rounded-lg object-cover" />
          ) : (
            <BuildingIcon className="w-4 h-4 text-primary" />
          )}
        </div>
        <div className="min-w-0">
          <div className="font-semibold text-sm truncate">{name ?? "—"}</div>
          {planLabel ? (
            <Badge className="text-[9px] h-3.5 px-1 mt-0.5">{planLabel}</Badge>
          ) : (
            <span className="text-[10px] text-muted-foreground">{noPlanLabel}</span>
          )}
        </div>
      </div>
    </div>
  );
}

function ConvexSidebarContent({ onClose }: { onClose?: () => void }) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const company = useQuery(api.companies.getMyCompany, {});
  const appUser = useAppUser();

  return (
    <div className="flex flex-col h-full py-4">
      <SidebarCompanyCard
        name={company?.name ?? t("sidebar.my_company")}
        logoUrl={company?.logoUrl}
        planLabel={company?.subscriptionStatus && company.subscriptionStatus !== "none" ? company.planId?.toUpperCase() ?? null : null}
        noPlanLabel={t("labels.no_active_plan", { ns: "common" })}
      />
      <div className="px-3 mb-4">
        <ExploreFeaturesButton variant="sidebar" onTriggered={onClose} />
      </div>
      <OwnerSidebarNav
        onClose={onClose}
        lng={lng}
        t={t}
        roles={appUser.roles}
        isSuperAdmin={appUser.isSuperAdmin}
      />
    </div>
  );
}

function SupabaseSidebarContent({ onClose }: { onClose?: () => void }) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const { selectedCompany, isLoading } = useOwnerCompany();
  const appUser = useAppUser();

  return (
    <div className="flex flex-col h-full py-4">
      <OwnerCompanySwitcher />
      {isLoading ? (
        <div className="px-3 mb-5">
          <Skeleton className="h-16 w-full rounded-xl" />
        </div>
      ) : selectedCompany ? (
        <SidebarCompanyCard
          name={selectedCompany.name}
          logoUrl={selectedCompany.logo}
          planLabel={selectedCompany.countryName ?? null}
          noPlanLabel={t("labels.no_active_plan", { ns: "common" })}
        />
      ) : (
        <SidebarCompanyCard
          name={t("sidebar.my_company")}
          logoUrl={null}
          planLabel={null}
          noPlanLabel={t("labels.no_active_plan", { ns: "common" })}
        />
      )}
      <div className="px-3 mb-4">
        <ExploreFeaturesButton variant="sidebar" onTriggered={onClose} />
      </div>
      <OwnerSidebarNav
        onClose={onClose}
        lng={lng}
        t={t}
        roles={appUser.roles}
        isSuperAdmin={appUser.isSuperAdmin}
      />
    </div>
  );
}

function OwnerSidebarNav({
  onClose,
  lng,
  t,
  roles,
  isSuperAdmin,
}: {
  onClose?: () => void;
  lng?: string;
  t: (key: string, options?: Record<string, string>) => string;
  roles?: string[];
  isSuperAdmin?: boolean;
}) {
  const canSeeGuaranteeFund =
    roles && isSuperAdmin !== undefined
      ? canAccessGuaranteeFund(roles, isSuperAdmin)
      : true;

  return (
    <nav className="flex-1 px-3 space-y-5 overflow-y-auto">
      {getNavSections().map((section) => {
        const items = section.items.filter((item) => {
          if (item.toSuffix === "/owner/guarantee-fund") return canSeeGuaranteeFund;
          if (item.toSuffix === "/owner/cash-register") return canSeeGuaranteeFund;
          if (item.toSuffix === "/manual/compagnie") {
            return Boolean(isSuperAdmin || roles?.includes("owner"));
          }
          return true;
        });
        if (items.length === 0) return null;

        return (
        <div key={section.titleKey}>
          <p className="text-[10px] uppercase font-semibold tracking-wider text-muted-foreground px-3 mb-1.5">
            {t(section.titleKey, { defaultValue: section.titleKey.split(".")[1] })}
          </p>
          <div className="space-y-0.5">
            {items.map(({ toSuffix, labelKey, icon: Icon, end }) => (
              <NavLink
                key={toSuffix}
                to={`/${lng}${toSuffix}`}
                end={end}
                onClick={onClose}
                className={({ isActive }) =>
                  cn(
                    "flex items-center gap-3 px-3 py-2 rounded-lg text-[13px] font-medium transition-all duration-150",
                    isActive
                      ? "bg-primary text-primary-foreground shadow-sm"
                      : "text-muted-foreground hover:bg-muted/50 hover:text-foreground",
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    <div
                      className={cn(
                        "w-7 h-7 rounded-md flex items-center justify-center shrink-0 transition-colors",
                        isActive ? "bg-primary-foreground/15" : "bg-primary/10",
                      )}
                    >
                      <Icon className={cn("w-3.5 h-3.5", isActive ? "" : "text-primary")} />
                    </div>
                    <span className="truncate">{t(labelKey)}</span>
                    {isActive && (
                      <div className="ml-auto w-1.5 h-1.5 rounded-full bg-primary-foreground/80" />
                    )}
                  </>
                )}
              </NavLink>
            ))}
          </div>
        </div>
        );
      })}
    </nav>
  );
}

function SidebarContent({ onClose }: { onClose?: () => void }) {
  if (isSupabaseAuth()) {
    return <SupabaseSidebarContent onClose={onClose} />;
  }
  return <ConvexSidebarContent onClose={onClose} />;
}

function OwnerLayoutShell({ children }: { children: React.ReactNode }) {
  const { t } = useTranslation("owner");
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <div className="flex h-[calc(100vh-3.5rem)]">
      <aside className="hidden md:flex flex-col w-60 bg-background border-r border-border shrink-0">
        <SidebarContent />
      </aside>

      {mobileOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div
            className="absolute inset-0 bg-black/50 backdrop-blur-sm"
            onClick={() => setMobileOpen(false)}
          />
          <aside className="absolute left-0 top-0 bottom-0 w-72 bg-background border-r border-border flex flex-col shadow-2xl">
            <div className="flex items-center justify-between px-4 pt-4">
              <span className="font-bold text-sm">{t("header.menu", { ns: "common" })}</span>
              <button
                onClick={() => setMobileOpen(false)}
                className="cursor-pointer text-muted-foreground hover:text-foreground transition-colors"
              >
                <XIcon className="w-5 h-5" />
              </button>
            </div>
            <SidebarContent onClose={() => setMobileOpen(false)} />
          </aside>
        </div>
      )}

      <div className="flex-1 overflow-auto">
        <div className="md:hidden flex items-center gap-3 px-4 py-3 border-b border-border bg-background/80 backdrop-blur-sm sticky top-0 z-10">
          <button onClick={() => setMobileOpen(true)} className="cursor-pointer p-1.5 rounded-lg hover:bg-muted transition-colors">
            <MenuIcon className="w-5 h-5" />
          </button>
          <span className="font-semibold text-sm">{t("header.owner_dashboard", { ns: "common" })}</span>
        </div>
        {children}
      </div>
    </div>
  );
}

function ConvexOwnerLayout() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const user = useQuery(api.users.getCurrentUser, {});

  if (user === undefined) {
    return (
      <OwnerLayoutShell>
        <div className="p-6 space-y-4">
          <Skeleton className="h-8 w-48" />
          <Skeleton className="h-28 w-full rounded-xl" />
        </div>
      </OwnerLayoutShell>
    );
  }

  if (user?.role !== "owner" && user?.role !== "superadmin") {
    navigate(`/${lng}`, { replace: true });
    return null;
  }

  return (
    <OwnerLayoutShell>
      <Outlet />
    </OwnerLayoutShell>
  );
}

function SupabaseOwnerLayout() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const appUser = useAppUser();
  const canAccess =
    appUser.roles.includes("owner") ||
    appUser.roles.includes("super_admin") ||
    appUser.roles.includes("comptable_compagnie");

  useEffect(() => {
    if (!appUser.isLoading && appUser.isReady && !canAccess) {
      navigate(`/${lng}`, { replace: true });
    }
  }, [appUser.isLoading, appUser.isReady, canAccess, lng, navigate]);

  if (!appUser.isLoading && appUser.isReady && !canAccess) {
    return null;
  }

  return (
    <OwnerCompanyProvider>
      {appUser.isLoading || !appUser.isReady ? (
        <OwnerLayoutShell>
          <div className="p-6 space-y-4">
            <Skeleton className="h-8 w-48" />
            <Skeleton className="h-28 w-full rounded-xl" />
          </div>
        </OwnerLayoutShell>
      ) : (
        <OwnerLayoutShell>
          <Outlet />
        </OwnerLayoutShell>
      )}
    </OwnerCompanyProvider>
  );
}

export default function OwnerLayout() {
  if (isSupabaseAuth()) {
    return <SupabaseOwnerLayout />;
  }
  return <ConvexOwnerLayout />;
}
