import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { NavLink, useParams } from "react-router-dom";
import { HomeIcon, TicketIcon, LayoutDashboardIcon, ShieldIcon } from "lucide-react";
import { cn } from "@/lib/utils.ts";
import { useTranslation } from "react-i18next";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useAppUser } from "@/hooks/use-app-user.ts";

export default function BottomNav() {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const appUser = useAppUser();
  const convexUser = useQuery(api.users.getCurrentUser, isSupabaseAuth() ? "skip" : {});

  const role = isSupabaseAuth()
    ? appUser.isSuperAdmin
      ? "superadmin"
      : appUser.roles.includes("owner")
        ? "owner"
        : appUser.hasSellerRole
          ? "seller"
          : "traveler"
    : (convexUser?.role ?? "traveler");

  const travelerLinks = [
    { to: `/${lng}`, icon: HomeIcon, label: t("nav.home") },
    { to: `/${lng}/traveler`, icon: TicketIcon, label: t("nav.trips") },
  ];

  const ownerLinks = [
    { to: `/${lng}`, icon: HomeIcon, label: t("nav.home") },
    { to: `/${lng}/owner`, icon: LayoutDashboardIcon, label: t("nav.dashboard") },
  ];

  const sellerLinks = [
    { to: `/${lng}`, icon: HomeIcon, label: t("nav.home") },
    { to: `/${lng}/seller`, icon: TicketIcon, label: t("nav.sell") },
  ];

  const adminLinks = [
    { to: `/${lng}`, icon: HomeIcon, label: t("nav.home") },
    { to: `/${lng}/admin`, icon: ShieldIcon, label: t("nav.admin") },
  ];

  const links =
    role === "superadmin"
      ? adminLinks
      : role === "owner"
        ? ownerLinks
        : role === "seller"
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
            end={to === `/${lng}`}
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
