import { useState, useEffect } from "react";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useParams, Link } from "react-router-dom";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Button } from "@/components/ui/button.tsx";
import { TicketIcon, SearchIcon, ShieldIcon, BusIcon, MapPinIcon, ClockIcon, Share2Icon, BookOpenIcon } from "lucide-react";
import { useTranslation } from "react-i18next";
import { format } from "date-fns";
import { toast } from "sonner";
import { motion } from "motion/react";
import AppHeader from "../layout/_components/AppHeader.tsx";
import BottomNav from "../layout/_components/BottomNav.tsx";
import OnboardingDialog from "../guide/_components/OnboardingDialog.tsx";

// ─── Seat occupancy helpers ──────────────────────────────────────────────────

function getOccupancyPercent(seatsAvailable: number, totalSeats: number): number {
  if (totalSeats === 0) return 100;
  const occupied = totalSeats - seatsAvailable;
  return Math.round((occupied / totalSeats) * 100);
}

function getOccupancyColor(percent: number): {
  bar: string;
  bg: string;
  text: string;
  label: string;
} {
  if (percent <= 30) {
    return { bar: "bg-emerald-500", bg: "bg-emerald-500/15", text: "text-emerald-700 dark:text-emerald-400", label: "Available" };
  }
  if (percent <= 75) {
    return { bar: "bg-amber-500", bg: "bg-amber-500/15", text: "text-amber-700 dark:text-amber-400", label: "Filling up" };
  }
  return { bar: "bg-red-500", bg: "bg-red-500/15", text: "text-red-700 dark:text-red-400", label: "Almost full" };
}

// ─── Upcoming trips with seat bars ───────────────────────────────────────────

function UpcomingTripsSection() {
  const trips = useQuery(api.trips.listUpcomingTripsPublic, {});
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");

  if (trips === undefined) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-28 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (trips.length === 0) {
    return (
      <div className="rounded-xl border border-dashed p-6 text-center">
        <BusIcon className="w-8 h-8 mx-auto text-muted-foreground/50 mb-2" />
        <p className="text-sm text-muted-foreground">
          {t("no_upcoming_trips", { defaultValue: "No upcoming trips at the moment" })}
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <h2 className="text-base font-bold tracking-tight px-1">
        {t("upcoming_trips", { defaultValue: "Upcoming Trips" })}
      </h2>
      {trips.map((trip) => {
        const percent = getOccupancyPercent(trip.seatsAvailable, trip.totalSeats);
        const color = getOccupancyColor(percent);
        const departure = new Date(trip.departureTime);

        return (
          <Link
            key={trip._id}
            to={`/${lng}/trip/${trip._id}`}
            className="block"
          >
            <div className="rounded-xl border bg-card p-4 space-y-3 hover:shadow-md transition-shadow cursor-pointer">
              {/* Header: route + company */}
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5 text-sm font-semibold truncate">
                    <MapPinIcon className="w-3.5 h-3.5 text-primary shrink-0" />
                    <span className="truncate">{trip.originCity}</span>
                    <span className="text-muted-foreground mx-0.5">{"→"}</span>
                    <span className="truncate">{trip.destinationCity}</span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5 truncate">
                    {trip.companyName} {trip.busName ? `· ${trip.busName}` : ""}
                  </p>
                </div>
                <div className="text-right shrink-0">
                  <p className="text-sm font-bold text-primary">
                    {trip.priceAmount.toLocaleString()} {trip.currency}
                  </p>
                </div>
              </div>

              {/* Time */}
              <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <ClockIcon className="w-3.5 h-3.5" />
                <span>{format(departure, "EEE dd MMM · HH:mm")}</span>
              </div>

              {/* Seat occupancy bar */}
              <div className="space-y-1.5">
                <div className="flex items-center justify-between text-xs">
                  <span className={`font-medium ${color.text}`}>
                    {trip.seatsAvailable} / {trip.totalSeats} {t("seats_left", { defaultValue: "seats left" })}
                  </span>
                  <span className={`text-[11px] font-medium px-1.5 py-0.5 rounded-full ${color.bg} ${color.text}`}>
                    {percent}%{" "}{t(`occupancy_${color.label.toLowerCase().replace(" ", "_")}`, { defaultValue: color.label })}
                  </span>
                </div>
                <div className="h-2.5 w-full rounded-full bg-muted overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all duration-500 ${color.bar}`}
                    style={{ width: `${percent}%` }}
                  />
                </div>
              </div>
            </div>
          </Link>
        );
      })}
    </div>
  );
}

// ─── Home Dashboard (authenticated users) ───────────────────────────────────

export default function HomeDashboard() {
  const user = useQuery(api.users.getCurrentUser, {});
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");

  // Onboarding dialog state - only show for new users (onboardingCompleted === false)
  // undefined means existing user who hasn't been migrated, don't show for those
  const [showOnboarding, setShowOnboarding] = useState(false);
  useEffect(() => {
    if (user && user.onboardingCompleted === false) {
      setShowOnboarding(true);
    }
  }, [user]);

  if (user === undefined) {
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

  const isSeller = user?.role === "seller" || user?.role === "owner";
  const isAdmin = user?.role === "superadmin";
  const greeting = user?.name ? `${t("greeting", { defaultValue: "Welcome" })}, ${user.name.split(" ")[0]}!` : "Tibus";

  return (
    <div className="flex flex-col min-h-screen">
      <AppHeader />
      <main className="flex-1 pb-20 md:pb-0">
        <div className="max-w-lg mx-auto px-4 py-10 space-y-8">
          {/* Onboarding dialog for first-time users */}
          <OnboardingDialog
            open={showOnboarding}
            onClose={() => setShowOnboarding(false)}
            userRole={user?.role ?? "traveler"}
          />
          {/* Logo / greeting */}
          <motion.div
            className="space-y-2 text-center"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, ease: "easeOut" }}
          >
            <div className="w-16 h-16 rounded-2xl bg-primary flex items-center justify-center mx-auto shadow-lg shadow-primary/20">
              <span className="text-primary-foreground font-extrabold text-2xl">T</span>
            </div>
            <h1 className="text-2xl font-extrabold tracking-tight">{greeting}</h1>
            <p className="text-muted-foreground text-sm">
              {t("homepage_subtitle", { defaultValue: "Book bus tickets or sell tickets for your company" })}
            </p>
          </motion.div>

          {/* Quick action buttons */}
          <motion.div
            className="space-y-3"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, delay: 0.1, ease: "easeOut" }}
          >
            <Link to={`/${lng}/traveler/search`} className="block">
              <Button size="lg" className="w-full h-14 text-base cursor-pointer gap-3">
                <SearchIcon className="w-5 h-5" />
                {t("book_reserve", { defaultValue: "Book / Reserve a Ticket" })}
              </Button>
            </Link>

            {(isSeller || isAdmin) && (
              <Link to={`/${lng}/seller`} className="block">
                <Button size="lg" variant="secondary" className="w-full h-14 text-base cursor-pointer gap-3 border-2 border-primary/20">
                  <TicketIcon className="w-5 h-5" />
                  {t("sell_ticket", { defaultValue: "Sell a Ticket" })}
                </Button>
              </Link>
            )}

            {isAdmin && (
              <Link to={`/${lng}/admin`} className="block">
                <Button size="lg" variant="secondary" className="w-full h-14 text-base cursor-pointer gap-3">
                  <ShieldIcon className="w-5 h-5" />
                  {t("admin_panel", { defaultValue: "Admin Panel" })}
                </Button>
              </Link>
            )}

            <Button
              size="lg"
              variant="ghost"
              className="w-full h-14 text-base cursor-pointer gap-3 border border-dashed border-primary/30 text-primary hover:bg-primary/5"
              onClick={async () => {
                const url = "https://www.tibusafrica.com";
                const shareData = {
                  title: "Tibus",
                  text: t("share.message", { defaultValue: "Download Tibus — book bus tickets easily!" }),
                  url,
                };
                if (typeof navigator.share === "function") {
                  try {
                    await navigator.share(shareData);
                    return;
                  } catch { /* fall through */ }
                }
                try {
                  await navigator.clipboard.writeText(url);
                  toast.success(t("share.link_copied", { defaultValue: "Link copied to clipboard!" }));
                  return;
                } catch { /* fall through */ }
                toast(t("share.copy_manually", { defaultValue: "Copy this link: " }) + url, { duration: 8000 });
              }}
            >
              <Share2Icon className="w-5 h-5" />
              {t("share.share_app", { defaultValue: "Share App" })}
            </Button>
          </motion.div>

          {/* Upcoming trips with seat occupancy bars */}
          <UpcomingTripsSection />

          {/* Secondary navigation */}
          <motion.div
            className="grid grid-cols-2 gap-3"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, delay: 0.2, ease: "easeOut" }}
          >
            <Link to={`/${lng}/traveler`}>
              <div className="rounded-xl border p-4 hover:bg-muted/50 hover:shadow-sm hover:border-primary/30 transition-all cursor-pointer text-center">
                <p className="text-sm font-semibold">{t("browse_companies", { defaultValue: "Browse Companies" })}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{t("browse_companies_desc", { defaultValue: "Find bus companies" })}</p>
              </div>
            </Link>
            <Link to={`/${lng}/traveler/bookings`}>
              <div className="rounded-xl border p-4 hover:bg-muted/50 hover:shadow-sm hover:border-primary/30 transition-all cursor-pointer text-center">
                <p className="text-sm font-semibold">{t("my_bookings", { defaultValue: "My Bookings" })}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{t("my_bookings_desc", { defaultValue: "View your tickets" })}</p>
              </div>
            </Link>
            <Link to={`/${lng}/guide`}>
              <div className="rounded-xl border p-4 hover:bg-muted/50 hover:shadow-sm hover:border-primary/30 transition-all cursor-pointer text-center">
                <BookOpenIcon className="w-4 h-4 mx-auto text-primary mb-1" />
                <p className="text-sm font-semibold">{t("guide.nav_guide", { defaultValue: "User Guide" })}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{t("guide.nav_guide_desc", { defaultValue: "Learn how to use Tibus" })}</p>
              </div>
            </Link>
            <Link to={`/${lng}/contact`}>
              <div className="rounded-xl border p-4 hover:bg-muted/50 hover:shadow-sm hover:border-primary/30 transition-all cursor-pointer text-center">
                <p className="text-sm font-semibold">{t("contact_us", { defaultValue: "Contact Us" })}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{t("contact_us_desc", { defaultValue: "Get help or send a message" })}</p>
              </div>
            </Link>
          </motion.div>

          {user?.role === "owner" && (
            <Link to={`/${lng}/owner`}>
              <div className="rounded-xl border border-dashed border-primary/30 p-4 hover:bg-primary/5 transition-colors cursor-pointer text-center">
                <p className="text-sm font-semibold text-primary">{t("owner_dashboard", { defaultValue: "Owner Dashboard" })}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{t("owner_dashboard_desc", { defaultValue: "Manage your company" })}</p>
              </div>
            </Link>
          )}
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
