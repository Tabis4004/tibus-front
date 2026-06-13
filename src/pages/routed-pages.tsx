import type { ComponentType } from "react";
import { Navigate, useParams } from "react-router-dom";
import { isSupabaseAuth } from "@/lib/auth/config";
import { SupabaseMigrationNotice } from "@/components/SupabaseMigrationNotice.tsx";
import AdminPanelRoute from "./admin/AdminPanelRoute.tsx";
import AdminCompanyManagerPage from "./admin/AdminCompanyManager.tsx";
import SupabaseAdminCompanyManager from "./admin/SupabaseAdminCompanyManager.tsx";
import AdminGuaranteeFundPage from "./admin/AdminGuaranteeFundPage.tsx";
import AdminUserFormPage from "./admin/AdminUserFormPage.tsx";
import BecomeOwnerPage from "./BecomeOwner.tsx";
import SupabaseBecomeOwner from "./SupabaseBecomeOwner.tsx";
import ContactPageConvex from "./contact/page.tsx";
import SupabaseContactPage from "./contact/SupabaseContactPage.tsx";
import GuidePage from "./guide/page.tsx";
import CompleteProfilePage from "./profile/CompleteProfile.tsx";
import SupabaseUserProfilePage from "./profile/SupabaseUserProfilePage.tsx";
import SellerDashboardPage from "./seller/SellerDashboard.tsx";
import SupabaseSellerDashboard from "./seller/SupabaseSellerDashboard.tsx";
import OwnerOverviewPage from "./owner/OwnerOverview.tsx";
import SupabaseOwnerOverview from "./owner/SupabaseOwnerOverview.tsx";
import CompanySettingsPage from "./owner/CompanySettings.tsx";
import SupabaseCompanySettings from "./owner/SupabaseCompanySettings.tsx";
import SupabaseCreateCompanyPage from "./owner/SupabaseCreateCompanyPage.tsx";
import FleetManagerPage from "./owner/FleetManager.tsx";
import SupabaseFleetManager from "./owner/SupabaseFleetManager.tsx";
import StationsManagerPage from "./owner/StationsManager.tsx";
import SupabaseStationsManager from "./owner/SupabaseStationsManager.tsx";
import RoutesManagerPage from "./owner/RoutesManager.tsx";
import SupabaseRoutesManager from "./owner/SupabaseRoutesManager.tsx";
import TripsManagerPage from "./owner/TripsManager.tsx";
import SupabaseTripsManager from "./owner/SupabaseTripsManager.tsx";
import SellersManagerPage from "./owner/SellersManager.tsx";
import SupabaseSellersManager from "./owner/SupabaseSellersManager.tsx";
import SubscriptionPlansPage from "./owner/SubscriptionPlans.tsx";
import SupabaseSubscriptionPlans from "./owner/SupabaseSubscriptionPlans.tsx";
import SubscriptionSuccessPage from "./owner/SubscriptionSuccess.tsx";
import SupabaseSubscriptionSuccess from "./owner/SupabaseSubscriptionSuccess.tsx";
import AnalyticsDashboardPage from "./owner/analytics/page.tsx";
import SupabaseAnalyticsDashboard from "./owner/analytics/SupabaseAnalyticsDashboard.tsx";
import TicketReportsPage from "./owner/analytics/tickets/page.tsx";
import SupabaseTicketReports from "./owner/analytics/SupabaseTicketReports.tsx";
import TripReportsPage from "./owner/analytics/trips/page.tsx";
import SupabaseTripReports from "./owner/analytics/SupabaseTripReports.tsx";
import TravelersPageConvex from "./owner/analytics/travelers/page.tsx";
import SupabaseTravelersReport from "./owner/analytics/SupabaseTravelersReport.tsx";
import OwnerReviewsPage from "./owner/OwnerReviews.tsx";
import SupabaseOwnerReviews from "./owner/SupabaseOwnerReviews.tsx";
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
import SupabasePaymentSetup from "./traveler/SupabasePaymentSetup.tsx";
import CompanyProfilePage from "./traveler/CompanyProfile.tsx";
import SupabaseCompanyProfile from "./traveler/SupabaseCompanyProfile.tsx";
import TicketVerifyPage from "./verify/TicketVerify.tsx";
import SupabaseTicketVerify from "./verify/SupabaseTicketVerify.tsx";
import TicketScannerPage from "./verify/TicketScannerPage.tsx";
import ReferralPage from "./traveler/ReferralPage.tsx";
import GuaranteeFundPage from "./owner/GuaranteeFundPage.tsx";
import CompanySalesPage from "./owner/CompanySalesPage.tsx";
import CashRegisterPage from "./owner/CashRegisterPage.tsx";
import GareManagerCommissionsPage from "./owner/GareManagerCommissionsPage.tsx";
import ColisSettingsPage from "./owner/ColisSettingsPage.tsx";
import LoyaltyPage from "./owner/LoyaltyPage.tsx";
import CancellationPolicyPage from "./owner/CancellationPolicyPage.tsx";
import OwnerMessagesPage from "./owner/OwnerMessagesPage.tsx";
import PartnerApiPage from "./owner/PartnerApiPage.tsx";
import CompanyManualPage from "./manual/CompanyManualPage.tsx";
import CountryAdminManualPage from "./manual/CountryAdminManualPage.tsx";

function useSupabaseBranch<T>(supabase: T, convex: T): T {
  return isSupabaseAuth() ? supabase : convex;
}

function SupabaseTravelerHomeRedirect() {
  const { lng } = useParams<{ lng: string }>();
  return <Navigate to={`/${lng ?? "fr"}/traveler/search`} replace />;
}

export function AdminPanel() {
  return <AdminPanelRoute />;
}

export function AdminCompanyManager() {
  return useSupabaseBranch(
    <SupabaseAdminCompanyManager />,
    <AdminCompanyManagerPage />,
  );
}

export function AdminUserForm() {
  return supabaseOnlyPage(
    "Gestion utilisateurs",
    AdminUserFormPage,
    "La création et l'édition des rôles utilisateurs sont disponibles en mode Supabase.",
  );
}

export function AdminGuaranteeFund() {
  return <AdminGuaranteeFundPage />;
}

export function BecomeOwner() {
  return useSupabaseBranch(<SupabaseBecomeOwner />, <BecomeOwnerPage />);
}

export function ContactPage() {
  return useSupabaseBranch(<SupabaseContactPage />, <ContactPageConvex />);
}

export function GuidePageRoute() {
  return <GuidePage />;
}

export function CompanyManual() {
  return <CompanyManualPage />;
}

export function CountryAdminManual() {
  return <CountryAdminManualPage />;
}

export function CompleteProfileRedirect() {
  const { lng } = useParams();
  if (isSupabaseAuth()) {
    return <Navigate to={`/${lng ?? "fr"}/account/profile`} replace />;
  }
  return <CompleteProfilePage />;
}

export function UserProfile() {
  return useSupabaseBranch(<SupabaseUserProfilePage />, <CompleteProfilePage />);
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

export function CreateCompany() {
  return useSupabaseBranch(<SupabaseCreateCompanyPage />, <CompanySettingsPage />);
}

export function FleetManager() {
  return useSupabaseBranch(<SupabaseFleetManager />, <FleetManagerPage />);
}

export function StationsManager() {
  return useSupabaseBranch(<SupabaseStationsManager />, <StationsManagerPage />);
}

export function RoutesManager() {
  return useSupabaseBranch(<SupabaseRoutesManager />, <RoutesManagerPage />);
}

export function TripsManager() {
  return useSupabaseBranch(<SupabaseTripsManager />, <TripsManagerPage />);
}

export function SellersManager() {
  return useSupabaseBranch(<SupabaseSellersManager />, <SellersManagerPage />);
}

export function SubscriptionPlans() {
  return useSupabaseBranch(<SupabaseSubscriptionPlans />, <SubscriptionPlansPage />);
}

export function SubscriptionSuccess() {
  return useSupabaseBranch(
    <SupabaseSubscriptionSuccess />,
    <SubscriptionSuccessPage />,
  );
}

export function AnalyticsDashboard() {
  return useSupabaseBranch(
    <SupabaseAnalyticsDashboard />,
    <AnalyticsDashboardPage />,
  );
}

export function TicketReports() {
  return useSupabaseBranch(<SupabaseTicketReports />, <TicketReportsPage />);
}

export function TripReports() {
  return useSupabaseBranch(<SupabaseTripReports />, <TripReportsPage />);
}

export function TravelersPage() {
  return useSupabaseBranch(<SupabaseTravelersReport />, <TravelersPageConvex />);
}

export function OwnerReviews() {
  return useSupabaseBranch(<SupabaseOwnerReviews />, <OwnerReviewsPage />);
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

export function PaymentSetup() {
  return useSupabaseBranch(<SupabasePaymentSetup />, <PaymentVerifyPage />);
}

export function CompanyProfile() {
  return useSupabaseBranch(<SupabaseCompanyProfile />, <CompanyProfilePage />);
}

export function TicketVerify() {
  return useSupabaseBranch(<SupabaseTicketVerify />, <TicketVerifyPage />);
}

export function ReferralPageRoute() {
  return <ReferralPage />;
}

function supabaseOnlyPage(
  title: string,
  Page: ComponentType,
  description?: string,
) {
  if (!isSupabaseAuth()) {
    return <SupabaseMigrationNotice title={title} description={description} />;
  }
  return <Page />;
}

export function OwnerGuaranteeFund() {
  return supabaseOnlyPage("Fond de garantie", GuaranteeFundPage);
}

export function OwnerSalesLedger() {
  return supabaseOnlyPage("Journal des ventes", CompanySalesPage);
}

export function OwnerCashRegister() {
  return supabaseOnlyPage("Caisse gare", CashRegisterPage);
}

export function OwnerGareManagerCommissions() {
  return supabaseOnlyPage("Commissions gestionnaires gare", GareManagerCommissionsPage);
}

export function OwnerColisSettings() {
  return supabaseOnlyPage("Colis autonomes", ColisSettingsPage);
}

export function OwnerLoyalty() {
  return supabaseOnlyPage("Fidélité compagnie", LoyaltyPage);
}

export function OwnerCancellationPolicy() {
  return supabaseOnlyPage("Politique d'annulation", CancellationPolicyPage);
}

export function OwnerMessages() {
  return supabaseOnlyPage("Messages & contact", OwnerMessagesPage);
}

export function OwnerPartnerApi() {
  return supabaseOnlyPage("API partenaire itinéraires", PartnerApiPage);
}

export function TicketScanner() {
  if (!isSupabaseAuth()) {
    return (
      <SupabaseMigrationNotice
        title="Scanner billets"
        description="Le scanner embarquement Supabase n'est pas disponible en mode Convex."
      />
    );
  }
  return <TicketScannerPage />;
}
