import { useParams } from "react-router-dom";
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
  ClipboardListIcon,
} from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { motion } from "motion/react";
import AppHeader from "../layout/_components/AppHeader.tsx";
import BottomNav from "../layout/_components/BottomNav.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useAuth } from "@/hooks/use-auth.ts";
import OnboardingGate from "@/components/onboarding/OnboardingGate.tsx";
import ExploreFeaturesButton from "@/components/onboarding/ExploreFeaturesButton.tsx";
import { HomeActionBlock, HomeBlockSection } from "./_components/HomeActionBlock.tsx";
import SupabaseTripSearch from "../traveler/SupabaseTripSearch.tsx";
import HomeStationsMap from "../landing/HomeStationsMap.tsx";

export default function SupabaseHome() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const { t: ts } = useTranslation("seller");
  const { user } = useAuth();
  const appUser = useAppUser();
  const locale = lng ?? "fr";

  const firstName =
    appUser.profile?.firstName ??
    user?.profile.name?.split(" ")[0] ??
    user?.email?.split("@")[0] ??
    "Tibus";

  const showOwnerDashboard = appUser.roles.includes("owner") || appUser.roles.includes("super_admin");
  const showCountryAdminPanel =
    appUser.isSuperAdmin || appUser.roles.includes("admin_pays");
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
          <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
            <Skeleton className="h-10 w-64" />
            <Skeleton className="h-20 w-full rounded-xl" />
            <Skeleton className="h-20 w-full rounded-xl" />
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
        <div className="max-w-2xl mx-auto px-4 pt-6 pb-4">
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.25 }}
          >
            <h1 className="text-2xl font-extrabold tracking-tight">
              {t("greeting", { defaultValue: "Welcome" })}, {firstName}!
            </h1>
            <p className="text-muted-foreground text-sm mt-1">
              {t("homepage_subtitle", {
                defaultValue: "Book bus tickets or sell tickets for your company",
              })}
            </p>
          </motion.div>
        </div>

        <section id="home-trip-search" className="border-y bg-muted/30 scroll-mt-16">
          <div className="max-w-6xl mx-auto px-4 py-6 md:py-8">
            <SupabaseTripSearch embedded />
          </div>
        </section>

        <HomeStationsMap />

        <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
          <HomeBlockSection title={t("home.section_discover", { defaultValue: "Découverte" })}>
            <ExploreFeaturesButton variant="block" />
          </HomeBlockSection>

          <HomeBlockSection title={t("home.section_travel", { defaultValue: "Voyage" })}>
            <HomeActionBlock
              to={`/${locale}/traveler/search`}
              title={t("book_reserve", { defaultValue: "Book / Reserve a Ticket" })}
              description={t("home.book_desc", {
                defaultValue: "Rechercher un trajet et réserver votre siège",
              })}
              icon={SearchIcon}
              highlighted
              tour="travel-book"
            />
            <HomeActionBlock
              to={`/${locale}/traveler/bookings`}
              title={t("my_bookings", { defaultValue: "My Bookings" })}
              description={t("my_bookings_desc", { defaultValue: "View your tickets" })}
              icon={ClipboardListIcon}
            />
            <HomeActionBlock
              to={`/${locale}/traveler/referral`}
              title={t("referral_cta", { defaultValue: "Parrainage & points Tibus" })}
              description={t("home.referral_desc", {
                defaultValue: "Parrainez vos proches et cumulez des points",
              })}
              icon={GiftIcon}
              tour="travel-referral"
            />
          </HomeBlockSection>

          {(showTicketScanner ||
            !appUser.shouldHideMerchantAgentCta ||
            showOwnerDashboard ||
            showSellerDashboard ||
            showThirdPartyBooking ||
            showCountryAdminPanel ||
            appUser.isSuperAdmin) && (
            <HomeBlockSection title={t("home.section_pro", { defaultValue: "Espace pro" })}>
              {showTicketScanner && (
                <HomeActionBlock
                  to={`/${locale}/verify/scan`}
                  title={t("home.scan_tickets", { defaultValue: "Scanner les billets" })}
                  description={t("home.scan_desc", {
                    defaultValue: "Contrôler les billets à l'embarquement",
                  })}
                  icon={ScanLineIcon}
                />
              )}

              {!appUser.shouldHideMerchantAgentCta && (
                <HomeActionBlock
                  to={`/${locale}/agent-marchand`}
                  title={t("home.merchant_agent", { defaultValue: "Devenir Agent Marchand" })}
                  description={t("home.merchant_desc", {
                    defaultValue: "Rejoindre le réseau d'agents marchands Tibus",
                  })}
                  icon={StoreIcon}
                />
              )}

              {showOwnerDashboard && (
                <HomeActionBlock
                  to={`/${locale}/owner`}
                  title={t("owner_dashboard", { defaultValue: "Owner Dashboard" })}
                  description={t("owner_dashboard_desc", { defaultValue: "Manage your company" })}
                  icon={LayoutDashboardIcon}
                  tour="home-owner-dashboard"
                />
              )}

              {showSellerDashboard && (
                <HomeActionBlock
                  to={`/${locale}/seller`}
                  title={
                    showThirdPartyBooking
                      ? ts("seller_dashboard", { defaultValue: "Seller Dashboard" })
                      : ts("counter_sale", { defaultValue: "Counter sale" })
                  }
                  description={t("home.seller_desc", {
                    defaultValue: "Vendre des billets depuis votre guichet",
                  })}
                  icon={TicketIcon}
                  tour="home-seller-dashboard"
                />
              )}

              {showThirdPartyBooking && (
                <HomeActionBlock
                  to={`/${locale}/seller#third-party-booking`}
                  title={ts("third_party_reservation", { defaultValue: "Third-party reservation" })}
                  description={t("home.third_party_desc", {
                    defaultValue: "Réserver pour le compte d'un voyageur",
                  })}
                  icon={TicketIcon}
                />
              )}

              {(appUser.isSuperAdmin || appUser.roles.includes("admin_pays")) && (
                <HomeActionBlock
                  to={`/${locale}/admin`}
                  title={t("admin_panel", { defaultValue: "Admin Panel" })}
                  description={t("home.admin_desc", {
                    defaultValue: "Administration de la plateforme Tibus",
                  })}
                  icon={ShieldIcon}
                />
              )}

              {showCountryAdminPanel && (
                <HomeActionBlock
                  to={`/${locale}/manual/admin-pays`}
                  title={t("manual.country_admin_nav_title", {
                    defaultValue: "Manuel admin pays",
                  })}
                  description={t("manual.country_admin_nav_desc", {
                    defaultValue: "Comprendre votre rôle, les commissions et le fond de garantie",
                  })}
                  icon={BookOpenIcon}
                />
              )}

              {(showOwnerDashboard || appUser.isSuperAdmin) && (
                <HomeActionBlock
                  to={`/${locale}/manual/compagnie`}
                  title={t("manual.nav_title", { defaultValue: "Manuel compagnie" })}
                  description={t("manual.nav_desc", {
                    defaultValue: "Guide complet avec captures d'écran pour former vos équipes",
                  })}
                  icon={BookOpenIcon}
                />
              )}
            </HomeBlockSection>
          )}

          <HomeBlockSection title={t("home.section_help", { defaultValue: "Aide" })}>
            <HomeActionBlock
              to={`/${locale}/guide`}
              title={t("guide.nav_guide", { defaultValue: "User Guide" })}
              description={t("guide.nav_guide_desc", { defaultValue: "Learn how to use Tibus" })}
              icon={BookOpenIcon}
              tour="travel-guide"
            />
            <HomeActionBlock
              to={`/${locale}/contact`}
              title={t("contact_us", { defaultValue: "Contact Us" })}
              description={t("contact_us_desc", { defaultValue: "Get help or send a message" })}
              icon={MessageCircleIcon}
            />
          </HomeBlockSection>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
