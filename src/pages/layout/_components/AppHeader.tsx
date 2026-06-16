import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { Authenticated, Unauthenticated } from "@/components/auth/AuthBoundary.tsx";
import { SignInButton } from "@/components/ui/signin.tsx";
import { useAuth } from "@/hooks/use-auth.ts";
import { Link, useParams } from "react-router-dom";
import { BusIcon, LogOutIcon, UserIcon, ShieldIcon, Share2Icon, PlusIcon, LayoutDashboardIcon } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
  DropdownMenuLabel,
} from "@/components/ui/dropdown-menu.tsx";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { useTranslation } from "react-i18next";
import LocaleSwitcher from "@/components/ui/locale-switcher.tsx";
import { toast } from "sonner";
import NotificationCenter from "./NotificationCenter.tsx";
import { isSupabaseAuth } from "@/lib/auth/config";
import ExploreFeaturesButton from "@/components/onboarding/ExploreFeaturesButton.tsx";
import ManualNavLinks from "@/components/manual/ManualNavLinks.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { resolveUserHomePath } from "@/lib/auth/role-routing.ts";

async function shareApp(t: (key: string, opts?: Record<string, string>) => string) {
  const url = "https://www.tibusafrica.com";
  const shareData = {
    title: "Tibus",
    text: t("share.message", { defaultValue: "Download Tibus — book bus tickets easily!" }),
    url,
  };

  // Try Web Share API first (works on mobile and some desktop browsers)
  if (typeof navigator.share === "function") {
    try {
      await navigator.share(shareData);
      return;
    } catch {
      // User cancelled or API not available in this context — fall through
    }
  }

  // Fallback: try clipboard
  try {
    await navigator.clipboard.writeText(url);
    toast.success(t("share.link_copied", { defaultValue: "Link copied to clipboard!" }));
    return;
  } catch {
    // Clipboard also blocked (e.g. in iframe) — use manual fallback
  }

  // Final fallback: prompt user with the URL
  toast(t("share.copy_manually", { defaultValue: "Copy this link: " }) + url, { duration: 8000 });
}

function UserMenu() {
  const { signout, user } = useAuth();
  const dbUser = useQuery(api.users.getCurrentUser, isSupabaseAuth() ? "skip" : {});
  const appUser = useAppUser();
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();

  const role = isSupabaseAuth()
    ? appUser.dashboardRoleUi
    : (dbUser?.role ?? "traveler");
  const roleLabel = t(`roles.${role}`);
  const hasOwnerDashboard = isSupabaseAuth() && appUser.roles.includes("owner");
  const hasPlatformAdmin =
    isSupabaseAuth() &&
    (appUser.isSuperAdmin || appUser.roles.includes("admin_pays"));
  const hasDemarcheurDashboard =
    isSupabaseAuth() &&
    (appUser.roles.includes("demarcheur") || appUser.isSuperAdmin);
  const canCreateCompany =
    isSupabaseAuth() &&
    appUser.isReady &&
    (appUser.roles.includes("traveler") || appUser.roles.includes("owner"));

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="cursor-pointer flex items-center gap-2 rounded-full">
          <Avatar className="h-8 w-8 ring-2 ring-primary/20">
            <AvatarImage src={typeof user?.profile.avatar === "string" ? user.profile.avatar : undefined} />
            <AvatarFallback className="bg-primary/20 text-primary text-xs font-bold">
              {user?.profile.name?.charAt(0) ?? "U"}
            </AvatarFallback>
          </Avatar>
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel>
          <div className="font-semibold truncate">{user?.profile.name ?? "User"}</div>
          <div className="flex items-center gap-1 mt-1">
            <Badge
              variant={role === "superadmin" ? "default" : "secondary"}
              className="text-[10px] h-4 px-1.5"
            >
              {roleLabel}
            </Badge>
          </div>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        {hasOwnerDashboard && (
          <DropdownMenuItem asChild>
            <Link to={`/${lng}/owner`} className="cursor-pointer">
              <LayoutDashboardIcon className="w-4 h-4 mr-2 text-primary" />
              {t("owner_dashboard", { defaultValue: "Tableau de bord propriétaire" })}
            </Link>
          </DropdownMenuItem>
        )}
        {hasPlatformAdmin && (
          <DropdownMenuItem asChild>
            <Link to={`/${lng}/admin`} className="cursor-pointer">
              <ShieldIcon className="w-4 h-4 mr-2 text-primary" />
              {t("header.admin_panel")}
            </Link>
          </DropdownMenuItem>
        )}
        {hasDemarcheurDashboard && !hasPlatformAdmin && (
          <DropdownMenuItem asChild>
            <Link to={`/${lng}/admin/demarcheur`} className="cursor-pointer">
              <LayoutDashboardIcon className="w-4 h-4 mr-2 text-primary" />
              {t("header.demarcheur_dashboard", { defaultValue: "Espace démarcheur" })}
            </Link>
          </DropdownMenuItem>
        )}
        {role === "traveler" && !isSupabaseAuth() && (
          <DropdownMenuItem asChild>
            <Link to={`/${lng}/become-owner`} className="cursor-pointer">
              <UserIcon className="w-4 h-4 mr-2" />
              {t("header.become_owner")}
            </Link>
          </DropdownMenuItem>
        )}
        {canCreateCompany && (
          <DropdownMenuItem asChild>
            <Link
              to={
                appUser.roles.includes("owner")
                  ? `/${lng}/owner/company?new=1`
                  : `/${lng}/create-company`
              }
              className="cursor-pointer"
            >
              <PlusIcon className="w-4 h-4 mr-2" />
              {appUser.roles.includes("owner")
                ? t("header.create_company", { defaultValue: "Créer une compagnie" })
                : t("header.become_owner")}
            </Link>
          </DropdownMenuItem>
        )}
        {isSupabaseAuth() && (
          <DropdownMenuItem asChild>
            <Link to={`/${lng}/account/profile`} className="cursor-pointer">
              <UserIcon className="w-4 h-4 mr-2" />
              {t("profile.edit_title", { defaultValue: "Mon profil" })}
            </Link>
          </DropdownMenuItem>
        )}
        <DropdownMenuSeparator />
        <ExploreFeaturesButton variant="menu-item" />
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={() => shareApp(t)} className="cursor-pointer">
          <Share2Icon className="w-4 h-4 mr-2 text-primary" />
          {t("share.share_app", { defaultValue: "Share App" })}
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={signout} className="cursor-pointer text-destructive">
          <LogOutIcon className="w-4 h-4 mr-2" />
          {t("header.sign_out")}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

export default function AppHeader() {
  const { lng } = useParams<{ lng: string }>();
  const homePath = resolveUserHomePath(lng ?? "fr");

  return (
    <header className="sticky top-0 z-50 bg-background/80 backdrop-blur-md border-b border-border">
      <div className="max-w-5xl mx-auto px-4 h-14 flex items-center justify-between">
        <Link to={homePath} className="flex items-center gap-2 font-bold text-lg">
          <div className="w-8 h-8 rounded-lg bg-primary flex items-center justify-center">
            <BusIcon className="w-4 h-4 text-primary-foreground" />
          </div>
          <span className="font-extrabold tracking-tight">Tibus</span>
        </Link>
        <div className="flex items-center gap-2">
          <LocaleSwitcher />
          <ManualNavLinks />
          <Unauthenticated>
            <SignInButton />
          </Unauthenticated>
          <Authenticated>
            {isSupabaseAuth() && <ExploreFeaturesButton variant="button" />}
            <NotificationCenter />
            <UserMenu />
          </Authenticated>
        </div>
      </div>
    </header>
  );
}
