import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  SearchIcon,
  ShieldIcon,
  BookOpenIcon,
  TicketIcon,
  StoreIcon,
  LayoutDashboardIcon,
  ScanLineIcon,
  MessageCircleIcon,
  GiftIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import AppHeader from "../layout/_components/AppHeader.tsx";
import BottomNav from "../layout/_components/BottomNav.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useAuth } from "@/hooks/use-auth.ts";
import OnboardingGate from "@/components/onboarding/OnboardingGate.tsx";

export default function SupabaseHome() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const { user } = useAuth();
  const appUser = useAppUser();

  const firstName =
    appUser.profile?.firstName ??
    user?.profile.name?.split(" ")[0] ??
    user?.email?.split("@")[0] ??
    "Tibus";

  const showOwnerDashboard = appUser.roles.includes("owner") || appUser.roles.includes("super_admin");
  const showSellerDashboard = appUser.hasSellerRole || appUser.hasMerchantAgentApplication;
  const showThirdPartyBooking = appUser.hasThirdPartySellerRole || appUser.hasMerchantAgentApplication;
  const showTicketScanner = ["owner", "controleur", "vendeur", "super_admin"].some((role) =>
    appUser.roles.includes(role),
  );

  if (appUser.isLoading) {
    return (
      <div className="flex flex-col min-h-screen">
        <AppHeader />
        <main className="flex-1 pb-20 md:pb-0">
          <div className="flex flex-col gap-4 p-6 max-w-2xl mx-auto mt-8">
            <Skeleton className="h-10 w-64" />
            <Skeleton className="h-4 w-full" />
          </div>
        </main>
        <BottomNav />
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-screen">
      <OnboardingGate />
      <AppHeader />
      <main className="flex-1 pb-20 md:pb-0">
        <div className="max-w-lg mx-auto px-4 py-10 space-y-8">
          <div className="space-y-2">
            <h1 className="text-2xl font-extrabold tracking-tight">
              {t("greeting", { defaultValue: "Welcome" })}, {firstName}!
            </h1>
            <p className="text-sm text-muted-foreground">
              {t("supabase_home.subtitle", {
                defaultValue:
                  "Connexion Supabase active. Les données métier migrent progressivement depuis Convex.",
              })}
            </p>
          </div>

          <div className="space-y-3">
            <Link to={`/${lng}/traveler/search`} className="block" data-tour="travel-book">
              <Button size="lg" className="w-full h-14 text-base gap-3">
                <SearchIcon className="w-5 h-5" />
                {t("book_reserve", { defaultValue: "Book / Reserve a Ticket" })}
              </Button>
            </Link>

            {showTicketScanner && (
              <Link to={`/${lng}/verify/scan`} className="block">
                <Button
                  size="lg"
                  className="w-full h-14 text-base gap-3 shadow-md shadow-primary/20"
                >
                  <ScanLineIcon className="w-5 h-5" />
                  {t("home.scan_tickets", { defaultValue: "Scanner les billets" })}
                </Button>
              </Link>
            )}

            {!appUser.shouldHideMerchantAgentCta && (
              <Link to={`/${lng}/agent-marchand`} className="block">
                <Button
                  size="lg"
                  variant="secondary"
                  className="w-full h-14 text-base gap-3 border-2 border-primary/20"
                >
                  <StoreIcon className="w-5 h-5" />
                  Devenir Agent Marchand
                </Button>
              </Link>
            )}

            {showOwnerDashboard && (
              <Link to={`/${lng}/owner`} className="block" data-tour="home-owner-dashboard">
                <Button
                  size="lg"
                  variant="secondary"
                  className="w-full h-14 text-base gap-3 border-2 border-primary/20"
                >
                  <LayoutDashboardIcon className="w-5 h-5" />
                  {t("owner_dashboard")}
                </Button>
              </Link>
            )}

            {showSellerDashboard && (
              <Link to={`/${lng}/seller`} className="block" data-tour="home-seller-dashboard">
                <Button
                  size="lg"
                  variant="secondary"
                  className="w-full h-14 text-base gap-3 border-2 border-primary/20"
                >
                  <TicketIcon className="w-5 h-5" />
                  {showThirdPartyBooking
                    ? t("seller_dashboard", { ns: "seller" })
                    : t("counter_sale", { ns: "seller" })}
                </Button>
              </Link>
            )}

            {showThirdPartyBooking && (
              <Link to={`/${lng}/seller#third-party-booking`} className="block">
                <Button
                  size="lg"
                  variant="outline"
                  className="w-full h-14 text-base gap-3 border-2 border-primary/20"
                >
                  <TicketIcon className="w-5 h-5" />
                  {t("third_party_reservation", { ns: "seller" })}
                </Button>
              </Link>
            )}

            {appUser.isSuperAdmin && (
              <Link to={`/${lng}/admin`} className="block">
                <Button
                  size="lg"
                  variant="secondary"
                  className="w-full h-14 text-base gap-3"
                >
                  <ShieldIcon className="w-5 h-5" />
                  {t("admin_panel", { defaultValue: "Admin Panel" })}
                </Button>
              </Link>
            )}

            <Link to={`/${lng}/guide`} className="block" data-tour="travel-guide">
              <Button
                size="lg"
                variant="outline"
                className="w-full h-14 text-base gap-3"
              >
                <BookOpenIcon className="w-5 h-5" />
                {t("guide.nav_guide", { defaultValue: "User Guide" })}
              </Button>
            </Link>

            <Link to={`/${lng}/contact`} className="block">
              <Button
                size="lg"
                variant="outline"
                className="w-full h-14 text-base gap-3"
              >
                <MessageCircleIcon className="w-5 h-5" />
                {t("contact_us", { defaultValue: "Contact Us" })}
              </Button>
            </Link>

            <Link to={`/${lng}/traveler/referral`} className="block" data-tour="travel-referral">
              <Button
                size="lg"
                variant="outline"
                className="w-full h-14 text-base gap-3"
              >
                <GiftIcon className="w-5 h-5" />
                {t("referral_cta", { defaultValue: "Parrainage & points Tibus" })}
              </Button>
            </Link>
          </div>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
