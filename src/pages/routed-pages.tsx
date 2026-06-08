import { Navigate, useParams } from "react-router-dom";
import { isSupabaseAuth } from "@/lib/auth/config";
import { SupabaseMigrationNotice } from "@/components/SupabaseMigrationNotice.tsx";
import AdminPanelPage from "./admin/AdminPanel.tsx";
import SupabaseAdminPanel from "./admin/SupabaseAdminPanel.tsx";
import AdminCompanyManagerPage from "./admin/AdminCompanyManager.tsx";
import BecomeOwnerPage from "./BecomeOwner.tsx";
import ContactPageConvex from "./contact/page.tsx";
import SupabaseContactPage from "./contact/SupabaseContactPage.tsx";
import GuidePage from "./guide/page.tsx";
import CompleteProfilePage from "./profile/CompleteProfile.tsx";
import SellerDashboardPage from "./seller/SellerDashboard.tsx";
import SupabaseSellerDashboard from "./seller/SupabaseSellerDashboard.tsx";
import OwnerOverviewPage from "./owner/OwnerOverview.tsx";
import SupabaseOwnerOverview from "./owner/SupabaseOwnerOverview.tsx";
import CompanySettingsPage from "./owner/CompanySettings.tsx";
import SupabaseCompanySettings from "./owner/SupabaseCompanySettings.tsx";
import FleetManagerPage from "./owner/FleetManager.tsx";
import StationsManagerPage from "./owner/StationsManager.tsx";
import RoutesManagerPage from "./owner/RoutesManager.tsx";
import TripsManagerPage from "./owner/TripsManager.tsx";
import SupabaseTripsManager from "./owner/SupabaseTripsManager.tsx";
import SellersManagerPage from "./owner/SellersManager.tsx";
import SubscriptionPlansPage from "./owner/SubscriptionPlans.tsx";
import SubscriptionSuccessPage from "./owner/SubscriptionSuccess.tsx";
import AnalyticsDashboardPage from "./owner/analytics/page.tsx";
import SupabaseAnalyticsDashboard from "./owner/analytics/SupabaseAnalyticsDashboard.tsx";
import TicketReportsPage from "./owner/analytics/tickets/page.tsx";
import TripReportsPage from "./owner/analytics/trips/page.tsx";
import TravelersPageConvex from "./owner/analytics/travelers/page.tsx";
import OwnerReviewsPage from "./owner/OwnerReviews.tsx";
import PromoCodesPageConvex from "./owner/promo-codes/page.tsx";
import SupabasePromoCodesPage from "./owner/promo-codes/SupabasePromoCodesPage.tsx";
import TravelerHomePage from "./traveler/TravelerHome.tsx";
import TripSearchPage from "./traveler/TripSearch.tsx";
import SupabaseTripSearch from "./traveler/SupabaseTripSearch.tsx";
import TripDetailPage from "./traveler/TripDetail.tsx";
import SupabaseTripDetail from "./traveler/SupabaseTripDetail.tsx";
import MyBookingsPage from "./traveler/MyBookings.tsx";
import SupabaseMyBookings from "./traveler/SupabaseMyBookings.tsx";
import BookingConfirmationPage from "./traveler/BookingConfirmation.tsx";
import SupabaseBookingConfirmation from "./traveler/SupabaseBookingConfirmation.tsx";
import PaymentVerifyPage from "./traveler/PaymentVerify.tsx";
import SupabasePaymentVerify from "./traveler/SupabasePaymentVerify.tsx";
import CompanyProfilePage from "./traveler/CompanyProfile.tsx";
import TicketVerifyPage from "./verify/TicketVerify.tsx";
import ReferralPage from "./traveler/ReferralPage.tsx";

function useSupabaseBranch<T>(supabase: T, convex: T): T {
  return isSupabaseAuth() ? supabase : convex;
}

function SupabaseTravelerHomeRedirect() {
  const { lng } = useParams<{ lng: string }>();
  return <Navigate to={`/${lng ?? "fr"}/traveler/search`} replace />;
}

export function AdminPanel() {
  return useSupabaseBranch(<SupabaseAdminPanel />, <AdminPanelPage />);
}

export function AdminCompanyManager() {
  if (isSupabaseAuth()) {
    return (
      <SupabaseMigrationNotice title="Gestion compagnie admin" />
    );
  }
  return <AdminCompanyManagerPage />;
}

export function BecomeOwner() {
  if (isSupabaseAuth()) {
    return (
      <SupabaseMigrationNotice
        title="Devenir transporteur"
        description="L'inscription compagnie via Supabase arrive bientôt. Contactez le support Tibus en attendant."
      />
    );
  }
  return <BecomeOwnerPage />;
}

export function ContactPage() {
  return useSupabaseBranch(<SupabaseContactPage />, <ContactPageConvex />);
}

export function GuidePageRoute() {
  return <GuidePage />;
}

export function CompleteProfile() {
  if (isSupabaseAuth()) {
    return (
      <SupabaseMigrationNotice
        title="Compléter le profil"
        description="Utilisez la page de connexion Supabase puis complétez votre profil depuis les paramètres utilisateur."
      />
    );
  }
  return <CompleteProfilePage />;
}

export function SellerDashboard() {
  return useSupabaseBranch(<SupabaseSellerDashboard />, <SellerDashboardPage />);
}

export function OwnerOverview() {
  return useSupabaseBranch(<SupabaseOwnerOverview />, <OwnerOverviewPage />);
}

export function CompanySettings() {
  return useSupabaseBranch(<SupabaseCompanySettings />, <CompanySettingsPage />);
}

export function FleetManager() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Flotte / bus" />;
  }
  return <FleetManagerPage />;
}

export function StationsManager() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Gares et stations" />;
  }
  return <StationsManagerPage />;
}

export function RoutesManager() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Lignes et routes" />;
  }
  return <RoutesManagerPage />;
}

export function TripsManager() {
  return useSupabaseBranch(<SupabaseTripsManager />, <TripsManagerPage />);
}

export function SellersManager() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Vendeurs et agents" />;
  }
  return <SellersManagerPage />;
}

export function SubscriptionPlans() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Abonnement compagnie" />;
  }
  return <SubscriptionPlansPage />;
}

export function SubscriptionSuccess() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Abonnement confirmé" />;
  }
  return <SubscriptionSuccessPage />;
}

export function AnalyticsDashboard() {
  return useSupabaseBranch(
    <SupabaseAnalyticsDashboard />,
    <AnalyticsDashboardPage />,
  );
}

export function TicketReports() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Rapports billets" />;
  }
  return <TicketReportsPage />;
}

export function TripReports() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Rapports trajets" />;
  }
  return <TripReportsPage />;
}

export function TravelersPage() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Rapports voyageurs" />;
  }
  return <TravelersPageConvex />;
}

export function OwnerReviews() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Avis clients" />;
  }
  return <OwnerReviewsPage />;
}

export function PromoCodesPage() {
  return useSupabaseBranch(<SupabasePromoCodesPage />, <PromoCodesPageConvex />);
}

export function TravelerHome() {
  if (isSupabaseAuth()) {
    return <SupabaseTravelerHomeRedirect />;
  }
  return <TravelerHomePage />;
}

export function TripSearch() {
  return useSupabaseBranch(<SupabaseTripSearch />, <TripSearchPage />);
}

export function TripDetail() {
  return useSupabaseBranch(<SupabaseTripDetail />, <TripDetailPage />);
}

export function MyBookings() {
  return useSupabaseBranch(<SupabaseMyBookings />, <MyBookingsPage />);
}

export function BookingConfirmation() {
  return useSupabaseBranch(
    <SupabaseBookingConfirmation />,
    <BookingConfirmationPage />,
  );
}

export function PaymentVerify() {
  return useSupabaseBranch(<SupabasePaymentVerify />, <PaymentVerifyPage />);
}

export function CompanyProfile() {
  if (isSupabaseAuth()) {
    return <SupabaseMigrationNotice title="Profil compagnie voyageur" />;
  }
  return <CompanyProfilePage />;
}

export function TicketVerify() {
  return <TicketVerifyPage />;
}

export function ReferralPageRoute() {
  return <ReferralPage />;
}
