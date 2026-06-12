import { useParams, Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { Authenticated, Unauthenticated, AuthLoading } from "@/components/auth/AuthBoundary.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Button } from "@/components/ui/button.tsx";
import { SignInButton } from "@/components/ui/signin.tsx";
import {
  SearchIcon,
  MapPinIcon,
  ShieldCheckIcon,
  SmartphoneIcon,
  UsersIcon,
  BuildingIcon,
  TicketIcon,
  BarChart3Icon,
  ArrowRightIcon,
  BusIcon,
  ZapIcon,
  GlobeIcon,
  StarIcon,
  QuoteIcon,
  CheckCircleIcon,
} from "lucide-react";
import { motion } from "motion/react";
import LocaleSwitcher from "@/components/ui/locale-switcher.tsx";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useAuth } from "@/hooks/use-auth.ts";
import SupabaseHome from "./home/SupabaseHome.tsx";
import HomeDashboard from "./home/Dashboard.tsx";
import SupabaseTripSearch from "./traveler/SupabaseTripSearch.tsx";
import HomeStationsMap from "./landing/HomeStationsMap.tsx";

// ─── Landing Page (public / unauthenticated) ─────────────────────────────────

function LandingPage() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const locale = lng ?? "en";
  const cmsEnabled = !isSupabaseAuth();

  // CMS data (Convex — skipped in Supabase production to avoid Suspense hang)
  const cmsData = useQuery(api.landingContent.getAll, cmsEnabled ? {} : "skip");
  const liveStats = useQuery(
    api.landingContent.getLiveStats,
    cmsEnabled ? {} : "skip",
  );

  // Parse CMS content with fallback defaults
  const heroContent = cmsData?.hero
    ? (JSON.parse(cmsData.hero) as { badge: string; title: string; description: string; ctaSearch: string; ctaRegister: string; heroCardTitle: string; heroCardDesc: string })
    : null;

  const statsConfig = cmsData?.stats
    ? (JSON.parse(cmsData.stats) as { useAutoStats: boolean; overrides: { label: string; value: string }[] })
    : null;

  const featuresTravelersContent = cmsData?.features_travelers
    ? (JSON.parse(cmsData.features_travelers) as { title: string; desc: string }[])
    : null;

  const featuresCompaniesContent = cmsData?.features_companies
    ? (JSON.parse(cmsData.features_companies) as { title: string; desc: string }[])
    : null;

  const testimonialsContent = cmsData?.testimonials
    ? (JSON.parse(cmsData.testimonials) as { name: string; role: string; text: string; rating: number; city: string }[])
    : null;

  const trustSignalsContent = cmsData?.trust_signals
    ? (JSON.parse(cmsData.trust_signals) as { text: string }[])
    : null;

  const howItWorksContent = cmsData?.how_it_works
    ? (JSON.parse(cmsData.how_it_works) as { step: string; title: string; desc: string }[])
    : null;

  const ctaContent = cmsData?.cta
    ? (JSON.parse(cmsData.cta) as { title: string; description: string; ctaButton: string })
    : null;

  const TRAVELER_ICONS = [SearchIcon, SmartphoneIcon, ShieldCheckIcon, MapPinIcon];
  const features = (featuresTravelersContent ?? [
    {
      title: t("landing.feature_search", { defaultValue: "Search & Book" }),
      desc: t("landing.feature_search_desc", { defaultValue: "Find bus trips by route, date, and price. Book your seat in seconds." }),
    },
    {
      title: t("landing.feature_mobile", { defaultValue: "Mobile Tickets" }),
      desc: t("landing.feature_mobile_desc", { defaultValue: "Get your ticket on your phone. Show the QR code to board." }),
    },
    {
      title: t("landing.feature_secure", { defaultValue: "Secure Payments" }),
      desc: t("landing.feature_secure_desc", { defaultValue: "Pay safely with mobile money. Your transaction is protected." }),
    },
    {
      title: t("landing.feature_track", { defaultValue: "Real-Time Info" }),
      desc: t("landing.feature_track_desc", { defaultValue: "See available seats, departure times, and trip details live." }),
    },
  ]).map((f, i) => ({
    ...f,
    icon: TRAVELER_ICONS[i % TRAVELER_ICONS.length],
  }));

  const COMPANY_ICONS = [TicketIcon, UsersIcon, BarChart3Icon, BuildingIcon];
  const companyFeatures = (featuresCompaniesContent ?? [
    {
      title: t("landing.company_sell", { defaultValue: "Sell Tickets Online" }),
      desc: t("landing.company_sell_desc", { defaultValue: "Reach more customers. Sell tickets 24/7 without extra staff." }),
    },
    {
      title: t("landing.company_manage", { defaultValue: "Manage Sellers" }),
      desc: t("landing.company_manage_desc", { defaultValue: "Add station agents, track their sales, and manage commissions." }),
    },
    {
      title: t("landing.company_analytics", { defaultValue: "Analytics & Reports" }),
      desc: t("landing.company_analytics_desc", { defaultValue: "See revenue, bookings, and occupancy rates in real-time dashboards." }),
    },
    {
      title: t("landing.company_fleet", { defaultValue: "Fleet & Routes" }),
      desc: t("landing.company_fleet_desc", { defaultValue: "Manage buses, stations, routes, and trip schedules all in one place." }),
    },
  ]).map((f, i) => ({
    ...f,
    icon: COMPANY_ICONS[i % COMPANY_ICONS.length],
  }));

  // Build stats - use auto-calculated or manual overrides
  const defaultStatLabels = [
    t("landing.stat_trips", { defaultValue: "Trips completed" }),
    t("landing.stat_companies", { defaultValue: "Bus companies" }),
    t("landing.stat_travelers", { defaultValue: "Happy travelers" }),
    t("landing.stat_cities", { defaultValue: "Cities connected" }),
  ];
  const autoValues = liveStats
    ? [`${liveStats.trips}+`, `${liveStats.companies}+`, `${liveStats.travelers}+`, `${liveStats.cities}+`]
    : ["500+", "10+", "5K+", "20+"];

  const stats = (() => {
    if (statsConfig && !statsConfig.useAutoStats) {
      return statsConfig.overrides.map((o, i) => ({
        value: o.value || autoValues[i] || "0",
        label: o.label || defaultStatLabels[i] || "",
      }));
    }
    return defaultStatLabels.map((label, i) => ({
      value: autoValues[i],
      label,
    }));
  })();

  const testimonials = testimonialsContent ?? [
    {
      name: "Aminata K.",
      role: t("landing.testimonial1_role", { defaultValue: "Frequent traveler" }),
      text: t("landing.testimonial1_text", { defaultValue: "I used to spend hours at the station waiting for a bus. Now I book online and just show up. Tibus saved me so much time!" }),
      rating: 5,
      city: "Abidjan",
    },
    {
      name: "Kouadio M.",
      role: t("landing.testimonial2_role", { defaultValue: "Bus company owner" }),
      text: t("landing.testimonial2_text", { defaultValue: "Since joining Tibus, our ticket sales increased by 40%. The analytics dashboard helps us optimize our routes." }),
      rating: 5,
      city: "Yamoussoukro",
    },
    {
      name: "Fatou D.",
      role: t("landing.testimonial3_role", { defaultValue: "Student" }),
      text: t("landing.testimonial3_text", { defaultValue: "The mobile ticket is so convenient. No more paper tickets to lose. I just scan my QR code and board." }),
      rating: 5,
      city: "Daloa",
    },
  ];

  const trustSignals = (trustSignalsContent ?? [
    { text: t("landing.trust1", { defaultValue: "Verified bus companies only" }) },
    { text: t("landing.trust2", { defaultValue: "Secure mobile money payments" }) },
    { text: t("landing.trust3", { defaultValue: "24/7 customer support via WhatsApp" }) },
    { text: t("landing.trust4", { defaultValue: "Digital tickets with QR verification" }) },
  ]).map((s) => s.text);

  return (
    <div className="min-h-screen bg-background">
      {/* Navigation */}
      <header className="sticky top-0 z-50 bg-background/80 backdrop-blur-lg border-b">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-9 h-9 rounded-xl bg-primary flex items-center justify-center">
              <span className="text-primary-foreground font-extrabold text-lg">T</span>
            </div>
            <span className="font-bold text-lg tracking-tight">Tibus</span>
          </div>
          <div className="flex items-center gap-3">
            <LocaleSwitcher />
            {isSupabaseAuth() ? (
              <a href="#home-trip-search">
                <Button variant="ghost" size="sm" className="cursor-pointer hidden sm:flex">
                  {t("landing.nav_search", { defaultValue: "Search trips" })}
                </Button>
              </a>
            ) : (
              <Link to={`/${locale}/traveler/search`}>
                <Button variant="ghost" size="sm" className="cursor-pointer hidden sm:flex">
                  {t("landing.nav_search", { defaultValue: "Search trips" })}
                </Button>
              </Link>
            )}
            <SignInButton signInText={t("auth.sign_in", { defaultValue: "Sign In" })} signOutText={t("auth.sign_out", { defaultValue: "Sign Out" })} />
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="relative overflow-hidden">
        {/* Background gradient */}
        <div className="absolute inset-0 bg-gradient-to-br from-primary/5 via-transparent to-accent/5 pointer-events-none" />
        <div className="absolute top-20 right-0 w-96 h-96 bg-primary/8 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 w-80 h-80 bg-accent/8 rounded-full blur-3xl pointer-events-none" />

        <div className="relative max-w-6xl mx-auto px-4 sm:px-6 pt-16 pb-12 sm:pt-24 sm:pb-16">
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Left: text content */}
            <div className="space-y-6 text-center lg:text-left">
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5 }}
              >
                <span className="inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full bg-primary/10 text-primary border border-primary/20 mb-4">
                  <ZapIcon className="w-3 h-3" />
                  {heroContent?.badge ?? t("landing.badge", { defaultValue: "Bus travel made simple" })}
                </span>
              </motion.div>

              <motion.h1
                className="text-4xl sm:text-5xl md:text-6xl font-extrabold tracking-tight text-balance leading-tight"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: 0.1 }}
              >
                {heroContent?.title ?? t("landing.hero_title", { defaultValue: "Book Your Bus Ticket in Seconds" })}
              </motion.h1>

              <motion.p
                className="text-lg sm:text-xl text-muted-foreground max-w-2xl text-balance"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: 0.2 }}
              >
                {heroContent?.description ?? t("landing.hero_desc", { defaultValue: "Search routes, compare prices, and book seats instantly. Travel across West Africa with confidence." })}
              </motion.p>

              <motion.div
                className="flex flex-col sm:flex-row items-center lg:items-start justify-center lg:justify-start gap-3 pt-4"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: 0.3 }}
              >
                {isSupabaseAuth() ? (
                  <a href="#home-trip-search">
                    <Button size="lg" className="h-14 px-8 text-base cursor-pointer gap-2 shadow-lg shadow-primary/20">
                      <SearchIcon className="w-5 h-5" />
                      {heroContent?.ctaSearch ?? t("landing.cta_search", { defaultValue: "Search Trips" })}
                    </Button>
                  </a>
                ) : (
                  <Link to={`/${locale}/traveler/search`}>
                    <Button size="lg" className="h-14 px-8 text-base cursor-pointer gap-2 shadow-lg shadow-primary/20">
                      <SearchIcon className="w-5 h-5" />
                      {heroContent?.ctaSearch ?? t("landing.cta_search", { defaultValue: "Search Trips" })}
                    </Button>
                  </Link>
                )}
                <Link to={`/${locale}/become-owner`}>
                  <Button size="lg" variant="secondary" className="h-14 px-8 text-base cursor-pointer gap-2">
                    <BuildingIcon className="w-5 h-5" />
                    {heroContent?.ctaRegister ?? t("landing.cta_register", { defaultValue: "Register Your Company" })}
                  </Button>
                </Link>
              </motion.div>
            </div>

            {/* Right: hero image */}
            <motion.div
              className="hidden lg:block"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.6, delay: 0.2 }}
            >
              <div className="relative rounded-3xl overflow-hidden shadow-2xl shadow-primary/10 border">
                <img
                  src="https://images.unsplash.com/photo-1549972888-1f9d6fac4a95?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=800"
                  alt="Happy travelers on a bus"
                  className="w-full h-80 object-cover"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/30 to-transparent" />
                <div className="absolute bottom-4 left-4 right-4">
                  <div className="bg-background/90 backdrop-blur-sm rounded-xl p-3 flex items-center gap-3">
                    <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                      <BusIcon className="w-5 h-5 text-primary" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-semibold truncate">{heroContent?.heroCardTitle ?? t("landing.hero_card_title", { defaultValue: "Abidjan → Yamoussoukro" })}</p>
                      <p className="text-xs text-muted-foreground">{heroContent?.heroCardDesc ?? t("landing.hero_card_desc", { defaultValue: "15 seats available · 5,000 XAF" })}</p>
                    </div>
                  </div>
                </div>
              </div>
            </motion.div>
          </div>
        </div>
      </section>

      <section id="home-trip-search" className="border-y bg-muted/30 scroll-mt-16">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8 md:py-10">
          <SupabaseTripSearch embedded />
        </div>
      </section>

      {/* Trust signals bar */}
      <section className="border-y bg-primary/5">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-6">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
            {trustSignals.map((signal, i) => (
              <motion.div
                key={signal}
                className="flex items-center gap-2 text-sm"
                initial={{ opacity: 0, x: -10 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.3, delay: 0.05 * i }}
              >
                <CheckCircleIcon className="w-4 h-4 text-primary shrink-0" />
                <span className="text-foreground/80">{signal}</span>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* Stats */}
      <section className="border-b bg-muted/30">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-12">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
            {stats.map((stat, i) => (
              <motion.div
                key={stat.label}
                className="text-center"
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: 0.1 * i }}
              >
                <div className="text-3xl sm:text-4xl font-extrabold text-primary">{stat.value}</div>
                <div className="text-sm text-muted-foreground mt-1">{stat.label}</div>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* Features for Travelers */}
      <section className="max-w-6xl mx-auto px-4 sm:px-6 py-20">
        <div className="text-center mb-12 space-y-3">
          <span className="inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full bg-primary/10 text-primary">
            <BusIcon className="w-3 h-3" />
            {t("landing.for_travelers", { defaultValue: "For Travelers" })}
          </span>
          <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
            {t("landing.travelers_title", { defaultValue: "Travel Smarter, Not Harder" })}
          </h2>
          <p className="text-muted-foreground max-w-xl mx-auto">
            {t("landing.travelers_desc", { defaultValue: "Everything you need to plan and book your bus journey in one app." })}
          </p>
        </div>
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {features.map((f, i) => (
            <motion.div
              key={f.title}
              className="rounded-2xl border bg-card p-6 space-y-3 hover:shadow-lg hover:border-primary/20 transition-all"
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4, delay: 0.1 * i }}
            >
              <div className="w-11 h-11 rounded-xl bg-primary/10 flex items-center justify-center">
                <f.icon className="w-5 h-5 text-primary" />
              </div>
              <h3 className="font-bold text-sm">{f.title}</h3>
              <p className="text-xs text-muted-foreground leading-relaxed">{f.desc}</p>
            </motion.div>
          ))}
        </div>
      </section>

      {/* Features for Companies */}
      <section className="bg-muted/30 border-y">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-20">
          <div className="text-center mb-12 space-y-3">
            <span className="inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full bg-accent/20 text-accent-foreground">
              <BuildingIcon className="w-3 h-3" />
              {t("landing.for_companies", { defaultValue: "For Bus Companies" })}
            </span>
            <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
              {t("landing.companies_title", { defaultValue: "Grow Your Business with Tibus" })}
            </h2>
            <p className="text-muted-foreground max-w-xl mx-auto">
              {t("landing.companies_desc", { defaultValue: "Manage your fleet, sell tickets, and track performance — all from one dashboard." })}
            </p>
          </div>
          <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {companyFeatures.map((f, i) => (
              <motion.div
                key={f.title}
                className="rounded-2xl border bg-card p-6 space-y-3 hover:shadow-lg hover:border-accent/30 transition-all"
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: 0.1 * i }}
              >
                <div className="w-11 h-11 rounded-xl bg-accent/15 flex items-center justify-center">
                  <f.icon className="w-5 h-5 text-accent-foreground" />
                </div>
                <h3 className="font-bold text-sm">{f.title}</h3>
                <p className="text-xs text-muted-foreground leading-relaxed">{f.desc}</p>
              </motion.div>
            ))}
          </div>
          <div className="text-center mt-10">
            <Link to={`/${locale}/become-owner`}>
              <Button size="lg" className="cursor-pointer gap-2 h-12 px-6">
                {t("landing.cta_start", { defaultValue: "Get Started Free" })}
                <ArrowRightIcon className="w-4 h-4" />
              </Button>
            </Link>
          </div>
        </div>
      </section>

      {/* How it works */}
      <section className="max-w-6xl mx-auto px-4 sm:px-6 py-20">
        <div className="text-center mb-12 space-y-3">
          <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
            {t("landing.how_title", { defaultValue: "How It Works" })}
          </h2>
          <p className="text-muted-foreground">
            {t("landing.how_desc", { defaultValue: "Three simple steps to your next trip" })}
          </p>
        </div>
        <div className="grid md:grid-cols-3 gap-8 max-w-4xl mx-auto">
          {(howItWorksContent ?? [
            {
              step: "1",
              title: t("landing.step1_title", { defaultValue: "Search" }),
              desc: t("landing.step1_desc", { defaultValue: "Enter your origin, destination, and travel date." }),
            },
            {
              step: "2",
              title: t("landing.step2_title", { defaultValue: "Choose" }),
              desc: t("landing.step2_desc", { defaultValue: "Compare companies, prices, and departure times." }),
            },
            {
              step: "3",
              title: t("landing.step3_title", { defaultValue: "Travel" }),
              desc: t("landing.step3_desc", { defaultValue: "Pay securely and receive your digital ticket instantly." }),
            },
          ]).map((item, i) => {
            const colors = ["bg-primary text-primary-foreground", "bg-destructive text-white", "bg-accent text-accent-foreground"];
            return (
            <motion.div
              key={item.step}
              className="text-center space-y-4"
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4, delay: 0.15 * i }}
            >
              <div className={`w-14 h-14 rounded-2xl ${colors[i % colors.length]} flex items-center justify-center mx-auto text-xl font-extrabold`}>
                {item.step}
              </div>
              <h3 className="font-bold text-lg">{item.title}</h3>
              <p className="text-sm text-muted-foreground">{item.desc}</p>
            </motion.div>
            );
          })}
        </div>
      </section>

      {/* Testimonials */}
      <section className="bg-muted/30 border-y">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-20">
          <div className="text-center mb-12 space-y-3">
            <span className="inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full bg-primary/10 text-primary">
              <StarIcon className="w-3 h-3" />
              {t("landing.testimonials_badge", { defaultValue: "Testimonials" })}
            </span>
            <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
              {t("landing.testimonials_title", { defaultValue: "Trusted by Travelers & Companies" })}
            </h2>
            <p className="text-muted-foreground max-w-xl mx-auto">
              {t("landing.testimonials_desc", { defaultValue: "See what our users are saying about their Tibus experience." })}
            </p>
          </div>
          <div className="grid md:grid-cols-3 gap-6">
            {testimonials.map((review, i) => (
              <motion.div
                key={review.name}
                className="rounded-2xl border bg-card p-6 space-y-4 relative"
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: 0.1 * i }}
              >
                <QuoteIcon className="w-8 h-8 text-primary/15 absolute top-4 right-4" />
                {/* Stars */}
                <div className="flex gap-0.5">
                  {Array.from({ length: review.rating }).map((_, si) => (
                    <StarIcon key={si} className="w-4 h-4 fill-amber-400 text-amber-400" />
                  ))}
                </div>
                <p className="text-sm text-foreground/80 leading-relaxed italic">
                  {`"${review.text}"`}
                </p>
                <div className="flex items-center gap-3 pt-2 border-t">
                  <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center">
                    <span className="text-primary font-bold text-sm">{review.name[0]}</span>
                  </div>
                  <div>
                    <p className="text-sm font-semibold">{review.name}</p>
                    <p className="text-xs text-muted-foreground">{review.role} · {review.city}</p>
                  </div>
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      <HomeStationsMap />

      {/* CTA */}
      <section className="bg-primary text-primary-foreground">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 py-16 text-center space-y-6">
          <GlobeIcon className="w-10 h-10 mx-auto opacity-80" />
          <h2 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
            {ctaContent?.title ?? t("landing.cta_title", { defaultValue: "Ready to Travel?" })}
          </h2>
          <p className="text-primary-foreground/80 max-w-lg mx-auto">
            {ctaContent?.description ?? t("landing.cta_desc", { defaultValue: "Join thousands of travelers who book their bus tickets with Tibus every day." })}
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
            <Link to={`/${locale}/traveler/search`}>
              <Button size="lg" variant="secondary" className="h-14 px-8 text-base cursor-pointer gap-2">
                <SearchIcon className="w-5 h-5" />
                {ctaContent?.ctaButton ?? t("landing.cta_book", { defaultValue: "Book a Ticket" })}
              </Button>
            </Link>
            <SignInButton signInText={t("auth.sign_in", { defaultValue: "Sign In" })} signOutText={t("auth.sign_out", { defaultValue: "Sign Out" })} />
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t bg-muted/30">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8">
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="flex items-center gap-2">
              <div className="w-7 h-7 rounded-lg bg-primary flex items-center justify-center">
                <span className="text-primary-foreground font-bold text-xs">T</span>
              </div>
              <span className="font-semibold text-sm">Tibus</span>
            </div>
            <div className="flex items-center gap-4 text-sm text-muted-foreground">
              <Link to={`/${locale}/contact`} className="hover:text-foreground transition-colors cursor-pointer">
                {t("contact_us", { defaultValue: "Contact Us" })}
              </Link>
              <Link to={`/${locale}/become-owner`} className="hover:text-foreground transition-colors cursor-pointer">
                {t("landing.nav_register", { defaultValue: "Register Company" })}
              </Link>
            </div>
            <p className="text-xs text-muted-foreground">
              {`© ${new Date().getFullYear()} Tibus. ${t("landing.footer_rights", { defaultValue: "All rights reserved." })}`}
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}

function SupabaseIndex() {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="flex flex-col gap-4 p-6 max-w-2xl mx-auto mt-8">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-4 w-full" />
      </div>
    );
  }

  if (isAuthenticated) {
    return <SupabaseHome />;
  }

  return <LandingPage />;
}


// ─── Main export ─────────────────────────────────────────────────────────────

export default function Index() {
  if (isSupabaseAuth()) {
    return <SupabaseIndex />;
  }

  return (
    <>
      <AuthLoading>
        <div className="flex flex-col gap-4 p-6 max-w-2xl mx-auto mt-8">
          <Skeleton className="h-10 w-64" />
          <Skeleton className="h-4 w-full" />
        </div>
      </AuthLoading>
      <Unauthenticated>
        <LandingPage />
      </Unauthenticated>
      <Authenticated>
        <HomeDashboard />
      </Authenticated>
    </>
  );
}
