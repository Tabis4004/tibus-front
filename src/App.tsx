import { Suspense } from "react";
import { BrowserRouter, Navigate, Outlet, Route, Routes } from "react-router-dom";
import { DefaultProviders } from "./components/providers/default.tsx";
import LocaleWrapper from "./components/providers/locale-wrapper.tsx";
import { SAVED_OR_DEFAULT_LOCALE, setLocaleInPath } from "./i18n";
import "./i18n";
import { useServiceWorker } from "@/hooks/use-service-worker.ts";
import AuthCallback from "./pages/auth/Callback.tsx";
import Index from "./pages/Index.tsx";
import NotFound from "./pages/NotFound.tsx";
import AppLayout from "./pages/layout/AppLayout.tsx";
import TravelerHome from "./pages/traveler/TravelerHome.tsx";
import CompanyProfile from "./pages/traveler/CompanyProfile.tsx";
import OwnerLayout from "./pages/owner/OwnerLayout.tsx";
import OwnerOverview from "./pages/owner/OwnerOverview.tsx";
import CompanySettings from "./pages/owner/CompanySettings.tsx";
import FleetManager from "./pages/owner/FleetManager.tsx";
import StationsManager from "./pages/owner/StationsManager.tsx";
import RoutesManager from "./pages/owner/RoutesManager.tsx";
import TripsManager from "./pages/owner/TripsManager.tsx";
import SellersManager from "./pages/owner/SellersManager.tsx";
import SellerDashboard from "./pages/seller/SellerDashboard.tsx";
import BecomeOwner from "./pages/BecomeOwner.tsx";
import AdminPanel from "./pages/admin/AdminPanel.tsx";
import AdminCompanyManager from "./pages/admin/AdminCompanyManager.tsx";
import SubscriptionPlans from "./pages/owner/SubscriptionPlans.tsx";
import SubscriptionSuccess from "./pages/owner/SubscriptionSuccess.tsx";
import AnalyticsDashboard from "./pages/owner/analytics/page.tsx";
import TicketReports from "./pages/owner/analytics/tickets/page.tsx";
import TripReports from "./pages/owner/analytics/trips/page.tsx";
import TravelersPage from "./pages/owner/analytics/travelers/page.tsx";
import TripSearch from "./pages/traveler/TripSearch.tsx";
import TripDetail from "./pages/traveler/TripDetail.tsx";
import MyBookings from "./pages/traveler/MyBookings.tsx";
import BookingConfirmation from "./pages/traveler/BookingConfirmation.tsx";
import PaymentVerify from "./pages/traveler/PaymentVerify.tsx";
import TicketVerify from "./pages/verify/TicketVerify.tsx";
import CompleteProfile from "./pages/profile/CompleteProfile.tsx";
import ContactPage from "./pages/contact/page.tsx";
import OwnerReviews from "./pages/owner/OwnerReviews.tsx";
import PromoCodesPage from "./pages/owner/promo-codes/page.tsx";
import GuidePage from "./pages/guide/page.tsx";
import LoginPage from "./pages/auth/Login.tsx";

export default function App() {
  useServiceWorker();

  return (
    <DefaultProviders>
      <BrowserRouter>
        <Suspense fallback={<div></div>}>
          <Routes>
            {/* Root: redirect to saved/default locale */}
            <Route
              path="/"
              element={<Navigate to={setLocaleInPath(SAVED_OR_DEFAULT_LOCALE, "/")} replace />}
            />

            {/* Non-localized routes */}
            <Route path="/auth/callback" element={<AuthCallback />} />

            {/* All localized routes under /:lng */}
            <Route
              path="/:lng"
              element={
                <LocaleWrapper>
                  <Outlet />
                </LocaleWrapper>
              }
            >
              {/* Profile completion — outside AppLayout to avoid nav */}
              <Route path="complete-profile" element={<CompleteProfile />} />
              <Route path="auth/login" element={<LoginPage />} />

              {/* Index (landing) is outside AppLayout so unauthenticated users see full landing page */}
              <Route index element={<Index />} />

              <Route element={<AppLayout />}>
                <Route path="become-owner" element={<BecomeOwner />} />
                <Route path="traveler" element={<TravelerHome />} />
                <Route path="traveler/search" element={<TripSearch />} />
                <Route path="traveler/bookings" element={<MyBookings />} />
                <Route path="trip/:tripId" element={<TripDetail />} />
                <Route path="booking/:bookingId" element={<BookingConfirmation />} />
                <Route path="payment/verify" element={<PaymentVerify />} />
                <Route path="verify/:reference" element={<TicketVerify />} />
                <Route path="company/:companyId" element={<CompanyProfile />} />
                {/* Owner routes */}
                <Route path="owner" element={<OwnerLayout />}>
                  <Route index element={<OwnerOverview />} />
                  <Route path="company" element={<CompanySettings />} />
                  <Route path="buses" element={<FleetManager />} />
                  <Route path="stations" element={<StationsManager />} />
                  <Route path="routes" element={<RoutesManager />} />
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
                <Route path="guide" element={<GuidePage />} />
                <Route path="admin" element={<AdminPanel />} />
                <Route path="admin/company/:companyId" element={<AdminCompanyManager />} />
              </Route>
              <Route path="*" element={<NotFound />} />
            </Route>
          </Routes>
        </Suspense>
      </BrowserRouter>
    </DefaultProviders>
  );
}
