import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { NavLink, useParams } from "react-router-dom";
import { HomeIcon, TicketIcon, LayoutDashboardIcon, ShieldIcon, TrendingUpIcon, ScanLineIcon } from "lucide-react";
import { cn } from "@/lib/utils.ts";
import { useTranslation } from "react-i18next";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { resolveUserHomePath } from "@/lib/auth/role-routing.ts";
import { resolveGareBottomNavDashboardPath } from "@/lib/gare-role-routing.ts";
import {
  hasGareComptableDashboardAccess,
  hasGareControleurScanAccess,
  hasGareManagerDashboardAccess,
} from "@/lib/owner-team-roles.ts";

export default function BottomNav() {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const locale = lng ?? "fr";
  const homePath = resolveUserHomePath(locale);
  const appUser = useAppUser();
  const convexUser = useQuery(api.users.getCurrentUser, isSupabaseAuth() ? "skip" : {});

  const dashboardRole = isSupabaseAuth()
    ? appUser.dashboardRole
    : (convexUser?.role ?? "traveler");

  const travelerLinks = [
    { to: homePath, icon: HomeIcon, label: t("nav.home") },
    { to: `/${locale}/traveler`, icon: TicketIcon, label: t("nav.trips") },
  ];

  const ownerLinks = [
    { to: homePath, icon: HomeIcon, label: t("nav.home") },
    { to: `/${locale}/owner`, icon: LayoutDashboardIcon, label: t("nav.dashboard") },
  ];

  const sellerLinks = [
    { to: homePath, icon: HomeIcon, label: t("nav.home") },
    { to: `/${locale}/seller`, icon: TicketIcon, label: t("nav.sell") },
  ];

  const adminLinks = [
    { to: homePath, icon: HomeIcon, label: t("nav.home") },
    { to: `/${locale}/admin`, icon: ShieldIcon, label: t("nav.admin") },
  ];

  const hasSellerNav = isSupabaseAuth()
    ? appUser.hasSellerRole
    : dashboardRole === "seller";

  const demarcheurLinks = [
    { to: homePath, icon: HomeIcon, label: t("nav.home") },
    { to: `/${locale}/admin/demarcheur`, icon: TrendingUpIcon, label: t("nav.demarcheur", { defaultValue: "Démarcheur" }) },
    { to: `/${locale}/admin`, icon: ShieldIcon, label: t("nav.admin") },
  ];

  const gareLinks = [
    { to: homePath, icon: HomeIcon, label: t("nav.home") },
    {
      to: resolveGareBottomNavDashboardPath(locale, appUser.roles),
      icon: LayoutDashboardIcon,
      label: t("nav.dashboard"),
    },
  ];

  const controleurGareLinks = [
    { to: homePath, icon: HomeIcon, label: t("nav.home") },
    {
      to: resolveGareBottomNavDashboardPath(locale, appUser.roles),
      icon: ScanLineIcon,
      label: t("nav.scan", { defaultValue: "Contrôle" }),
    },
  ];

  const hasGareNav =
    isSupabaseAuth() &&
    (hasGareManagerDashboardAccess(appUser.roles) ||
      hasGareComptableDashboardAccess(appUser.roles) ||
      hasGareControleurScanAccess(appUser.roles));

  const links =
    dashboardRole === "owner"
      ? ownerLinks
      : dashboardRole === "demarcheur"
        ? demarcheurLinks
      : dashboardRole === "super_admin" ||
          dashboardRole === "admin_pays" ||
          dashboardRole === "superadmin"
        ? adminLinks
        : dashboardRole === "controleur_gare"
          ? controleurGareLinks
        : hasGareNav
          ? gareLinks
        : hasSellerNav
          ? sellerLinks
          : travelerLinks;

  if (isSupabaseAuth() && appUser.isLoading) {
    return null;
  }

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 md:hidden border-t border-border bg-background/95 backdrop-blur-md">
      <div className="flex justify-around items-center h-16 max-w-md mx-auto px-4">
        {links.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            end={to === homePath}
            className={({ isActive }) =>
              cn(
                "flex flex-col items-center gap-1 py-2 px-4 rounded-xl transition-all",
                isActive ? "text-primary" : "text-muted-foreground",
              )
            }
          >
            {({ isActive }) => (
              <>
                <div
                  className={cn(
                    "w-10 h-7 rounded-full flex items-center justify-center transition-all",
                    isActive ? "bg-primary/15" : "",
                  )}
                >
                  <Icon className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-medium">{label}</span>
              </>
            )}
          </NavLink>
        ))}
      </div>
    </nav>
  );
}
