import { Suspense } from "react";
import { BrowserRouter, Navigate, Outlet, Route, Routes } from "react-router-dom";
import { AuthBridgeProvider } from "./components/providers/auth-bridge.tsx";
import { DefaultProviders } from "./components/providers/default.tsx";
import LocaleWrapper from "./components/providers/locale-wrapper.tsx";
import { SAVED_OR_DEFAULT_LOCALE, setLocaleInPath } from "./i18n";
import "./i18n";
import { useServiceWorker } from "@/hooks/use-service-worker.ts";
import { useTibusWebViewBootstrap } from "@/hooks/use-tibus-webview.ts";
import AuthCallback from "./pages/auth/Callback.tsx";
import Index from "./pages/Index.tsx";
import NotFound from "./pages/NotFound.tsx";
import AppLayout from "./pages/layout/AppLayout.tsx";
import OwnerLayout from "./pages/owner/OwnerLayout.tsx";
import LoginPage from "./pages/auth/Login.tsx";
import {
  AdminCompanyManager,
  AdminPanel,
  AdminUserForm,
  AdminGuaranteeFund,
  AnalyticsDashboard,
  BecomeOwner,
  BookingConfirmation,
  CompanyProfile,
  CompanySettings,
  CreateCompany,
  CompanyManual,
  CountryAdminManual,
  CompleteProfileRedirect,
  UserProfile,
  ContactPage,
  FleetManager,
  GuidePageRoute,
  MyBookings,
  OwnerCancellationPolicy,
  OwnerCashRegister,
  OwnerGareManagerCommissions,
  OwnerColisSettings,
  OwnerGuaranteeFund,
  OwnerLoyalty,
  OwnerMessages,
  OwnerOverview,
  OwnerPartnerApi,
  OwnerReviews,
  OwnerSalesLedger,
  PaymentVerify,
  PromoCodesPage,
  ReferralPageRoute,
  RoutesManager,
  SellerDashboard,
  SellersManager,
  StationsManager,
  SubscriptionPlans,
  SubscriptionSuccess,
  TicketReports,
  TicketScanner,
  TicketVerify,
  TravelerHome,
  TravelersPage,
  TripDetail,
  TripReports,
  TripSearch,
  TripsManager,
} from "./pages/routed-pages.tsx";

function AppShell() {
  useTibusWebViewBootstrap();
  useServiceWorker();

  return (
        <Suspense
          fallback={
            <div className="min-h-screen flex items-center justify-center bg-background">
              <div className="h-8 w-8 rounded-full border-2 border-primary border-t-transparent animate-spin" />
            </div>
          }
        >
          <Routes>
            <Route
              path="/"
              element={<Navigate to={setLocaleInPath(SAVED_OR_DEFAULT_LOCALE, "/")} replace />}
            />

            <Route path="/auth/callback" element={<AuthCallback />} />

            <Route
              path="/:lng"
              element={
                <LocaleWrapper>
                  <Outlet />
                </LocaleWrapper>
              }
            >
              <Route path="complete-profile" element={<CompleteProfileRedirect />} />
              <Route path="auth/login" element={<LoginPage />} />
              <Route index element={<Index />} />

              <Route element={<AppLayout />}>
                <Route path="account/profile" element={<UserProfile />} />
                <Route path="become-owner" element={<BecomeOwner />} />
                <Route path="create-company" element={<CreateCompany />} />
                <Route path="traveler" element={<TravelerHome />} />
                <Route path="traveler/search" element={<TripSearch />} />
                <Route path="traveler/bookings" element={<MyBookings />} />
                <Route path="traveler/referral" element={<ReferralPageRoute />} />
                <Route path="trip/:tripId" element={<TripDetail />} />
                <Route path="booking/:bookingId" element={<BookingConfirmation />} />
                <Route path="payment/verify" element={<PaymentVerify />} />
                <Route path="verify/scan" element={<TicketScanner />} />
                <Route path="verify/:reference" element={<TicketVerify />} />
                <Route path="company/:companyId" element={<CompanyProfile />} />
                <Route path="owner" element={<OwnerLayout />}>
                  <Route index element={<OwnerOverview />} />
                  <Route path="company" element={<CompanySettings />} />
                  <Route path="sales" element={<OwnerSalesLedger />} />
                  <Route path="guarantee-fund" element={<OwnerGuaranteeFund />} />
                  <Route path="cash-register" element={<OwnerCashRegister />} />
                  <Route path="gare-manager-commissions" element={<OwnerGareManagerCommissions />} />
                  <Route path="colis" element={<OwnerColisSettings />} />
                  <Route path="loyalty" element={<OwnerLoyalty />} />
                  <Route path="cancellation" element={<OwnerCancellationPolicy />} />
                  <Route path="messages" element={<OwnerMessages />} />
                  <Route path="buses" element={<FleetManager />} />
                  <Route path="stations" element={<StationsManager />} />
                  <Route path="routes" element={<RoutesManager />} />
                  <Route path="partner-api" element={<OwnerPartnerApi />} />
                  <Route path="trips" element={<TripsManager />} />
                  <Route path="sellers" element={<SellersManager />} />
                  <Route path="subscription" element={<SubscriptionPlans />} />
                  <Route path="subscription/success" element={<SubscriptionSuccess />} />
                  <Route path="analytics" element={<AnalyticsDashboard />} />
                  <Route path="analytics/tickets" element={<TicketReports />} />
                  <Route path="analytics/trips" element={<TripReports />} />
                  <Route path="analytics/travelers" element={<TravelersPage />} />
                  <Route path="reviews" element={<OwnerReviews />} />
                  <Route path="promo-codes" element={<PromoCodesPage />} />
                </Route>
                <Route path="seller" element={<SellerDashboard />} />
                <Route path="contact" element={<ContactPage />} />
                <Route path="guide" element={<GuidePageRoute />} />
                <Route path="manual/compagnie" element={<CompanyManual />} />
                <Route path="manual/admin-pays" element={<CountryAdminManual />} />
                <Route path="admin" element={<AdminPanel />} />
                <Route path="admin/users/new" element={<AdminUserForm />} />
                <Route path="admin/users/:userId/edit" element={<AdminUserForm />} />
                <Route path="admin/guarantee-fund" element={<AdminGuaranteeFund />} />
                <Route path="admin/company/:companyId" element={<AdminCompanyManager />} />
              </Route>
              <Route path="*" element={<NotFound />} />
            </Route>
          </Routes>
        </Suspense>
  );
}

export default function App() {
  return (
    <DefaultProviders>
      <BrowserRouter>
        <AuthBridgeProvider>
          <AppShell />
        </AuthBridgeProvider>
      </BrowserRouter>
    </DefaultProviders>
  );
}
