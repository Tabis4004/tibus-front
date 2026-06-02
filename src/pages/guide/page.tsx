import { useParams, Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { motion } from "motion/react";
import { Button } from "@/components/ui/button.tsx";
import {
  SearchIcon,
  TicketIcon,
  SmartphoneIcon,
  StarIcon,
  BuildingIcon,
  BusIcon,
  MapPinIcon,
  UsersIcon,
  BarChart3Icon,
  TagIcon,
  ArrowRightIcon,
  BookOpenIcon,
} from "lucide-react";

// ─── Traveler Guide ──────────────────────────────────────────────────────────

function TravelerGuide() {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const locale = lng ?? "en";

  const steps = [
    {
      icon: SearchIcon,
      title: t("guide.traveler_step1_title", { defaultValue: "Search for a trip" }),
      desc: t("guide.traveler_step1_desc", { defaultValue: "Enter your departure city, destination, and travel date to find available trips." }),
      image: "https://images.unsplash.com/photo-1610484099426-41b2a747277e?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: TicketIcon,
      title: t("guide.traveler_step2_title", { defaultValue: "Choose and book" }),
      desc: t("guide.traveler_step2_desc", { defaultValue: "Compare prices, companies, and departure times. Select your seat and confirm your booking." }),
      image: "https://images.unsplash.com/photo-1607424064879-708250e57647?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: SmartphoneIcon,
      title: t("guide.traveler_step3_title", { defaultValue: "Get your ticket" }),
      desc: t("guide.traveler_step3_desc", { defaultValue: "Receive your digital ticket with a QR code. Show it at the station to board the bus." }),
      image: "https://images.unsplash.com/photo-1582848891416-b64a7e6ef07f?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: StarIcon,
      title: t("guide.traveler_step4_title", { defaultValue: "Travel and review" }),
      desc: t("guide.traveler_step4_desc", { defaultValue: "Enjoy your trip! After traveling, leave a review to help other travelers choose the best company." }),
      image: "https://images.unsplash.com/photo-1547505685-f404cce705f7?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
  ];

  return (
    <section className="space-y-12">
      {/* Hero */}
      <div className="relative rounded-3xl overflow-hidden">
        <img
          src="https://images.unsplash.com/photo-1720343331040-1f53c47460ba?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=1000"
          alt="Bus traveler"
          className="w-full h-48 sm:h-64 object-cover"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/30 to-transparent" />
        <div className="absolute bottom-6 left-6 right-6">
          <h2 className="text-2xl sm:text-3xl font-extrabold text-white tracking-tight">
            {t("guide.traveler_title", { defaultValue: "Traveler Guide" })}
          </h2>
          <p className="text-white/80 text-sm mt-1">
            {t("guide.traveler_subtitle", { defaultValue: "Book your bus ticket in a few simple steps" })}
          </p>
        </div>
      </div>

      {/* Steps */}
      {steps.map((step, i) => (
        <motion.div
          key={step.title}
          className="grid md:grid-cols-2 gap-6 items-center"
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5, delay: 0.1 * i }}
        >
          <div className={`space-y-3 ${i % 2 === 1 ? "md:order-2" : ""}`}>
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                <step.icon className="w-5 h-5 text-primary" />
              </div>
              <span className="text-xs font-bold text-primary uppercase tracking-wider">
                {t("guide.step_label", { defaultValue: "Step" })} {i + 1}
              </span>
            </div>
            <h3 className="text-xl font-bold">{step.title}</h3>
            <p className="text-muted-foreground text-sm leading-relaxed">{step.desc}</p>
          </div>
          <div className={`${i % 2 === 1 ? "md:order-1" : ""}`}>
            <div className="rounded-2xl overflow-hidden border shadow-sm">
              <img src={step.image} alt={step.title} className="w-full h-44 sm:h-52 object-cover" />
            </div>
          </div>
        </motion.div>
      ))}

      {/* CTA */}
      <div className="text-center pt-4">
        <Link to={`/${locale}/traveler/search`}>
          <Button size="lg" className="cursor-pointer gap-2 h-12 px-6">
            {t("guide.start_booking", { defaultValue: "Start Booking" })}
            <ArrowRightIcon className="w-4 h-4" />
          </Button>
        </Link>
      </div>
    </section>
  );
}

// ─── Company Guide ───────────────────────────────────────────────────────────

function CompanyGuide() {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const locale = lng ?? "en";

  const steps = [
    {
      icon: BuildingIcon,
      title: t("guide.company_step1_title", { defaultValue: "Register your company" }),
      desc: t("guide.company_step1_desc", { defaultValue: "Create your account and register your bus company. Add your company name, logo, and contact details." }),
      image: "https://images.unsplash.com/photo-1632276536839-84cad7fd03b0?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: BusIcon,
      title: t("guide.company_step2_title", { defaultValue: "Add your fleet and routes" }),
      desc: t("guide.company_step2_desc", { defaultValue: "Add your buses with their seat capacity. Create stations and define routes between cities." }),
      image: "https://images.unsplash.com/photo-1571046314604-e32adfc8e11e?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: MapPinIcon,
      title: t("guide.company_step3_title", { defaultValue: "Create trips" }),
      desc: t("guide.company_step3_desc", { defaultValue: "Schedule trips by assigning a bus to a route with departure date, time, and price." }),
      image: "https://images.unsplash.com/photo-1726273858078-cb94feb4cf53?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: UsersIcon,
      title: t("guide.company_step4_title", { defaultValue: "Add sellers" }),
      desc: t("guide.company_step4_desc", { defaultValue: "Invite station agents to sell tickets on your behalf. Track their sales and manage commissions." }),
      image: "https://images.unsplash.com/photo-1509749837427-ac94a2553d0e?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: BarChart3Icon,
      title: t("guide.company_step5_title", { defaultValue: "Track performance" }),
      desc: t("guide.company_step5_desc", { defaultValue: "Monitor revenue, bookings, and occupancy rates in real-time from your analytics dashboard." }),
      image: "https://images.unsplash.com/photo-1544214643-652d421190f8?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
    {
      icon: TagIcon,
      title: t("guide.company_step6_title", { defaultValue: "Promote and grow" }),
      desc: t("guide.company_step6_desc", { defaultValue: "Create promo codes, collect traveler reviews, and grow your customer base." }),
      image: "https://images.unsplash.com/photo-1605068263928-dc295689add1?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600",
    },
  ];

  return (
    <section className="space-y-12">
      {/* Hero */}
      <div className="relative rounded-3xl overflow-hidden">
        <img
          src="https://images.unsplash.com/photo-1632276536839-84cad7fd03b0?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=1000"
          alt="Bus fleet"
          className="w-full h-48 sm:h-64 object-cover"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/30 to-transparent" />
        <div className="absolute bottom-6 left-6 right-6">
          <h2 className="text-2xl sm:text-3xl font-extrabold text-white tracking-tight">
            {t("guide.company_title", { defaultValue: "Company Guide" })}
          </h2>
          <p className="text-white/80 text-sm mt-1">
            {t("guide.company_subtitle", { defaultValue: "Manage your bus company and grow your business" })}
          </p>
        </div>
      </div>

      {/* Steps */}
      {steps.map((step, i) => (
        <motion.div
          key={step.title}
          className="grid md:grid-cols-2 gap-6 items-center"
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5, delay: 0.1 * i }}
        >
          <div className={`space-y-3 ${i % 2 === 1 ? "md:order-2" : ""}`}>
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                <step.icon className="w-5 h-5 text-primary" />
              </div>
              <span className="text-xs font-bold text-primary uppercase tracking-wider">
                {t("guide.step_label", { defaultValue: "Step" })} {i + 1}
              </span>
            </div>
            <h3 className="text-xl font-bold">{step.title}</h3>
            <p className="text-muted-foreground text-sm leading-relaxed">{step.desc}</p>
          </div>
          <div className={`${i % 2 === 1 ? "md:order-1" : ""}`}>
            <div className="rounded-2xl overflow-hidden border shadow-sm">
              <img src={step.image} alt={step.title} className="w-full h-44 sm:h-52 object-cover" />
            </div>
          </div>
        </motion.div>
      ))}

      {/* CTA */}
      <div className="text-center pt-4">
        <Link to={`/${locale}/become-owner`}>
          <Button size="lg" className="cursor-pointer gap-2 h-12 px-6">
            {t("guide.register_company", { defaultValue: "Register Your Company" })}
            <ArrowRightIcon className="w-4 h-4" />
          </Button>
        </Link>
      </div>
    </section>
  );
}

// ─── Main Guide Page ─────────────────────────────────────────────────────────

export default function GuidePage() {
  const { t } = useTranslation("common");

  return (
    <div className="max-w-4xl mx-auto px-4 sm:px-6 py-10 space-y-16">
      {/* Page header */}
      <motion.div
        className="text-center space-y-3"
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease: "easeOut" }}
      >
        <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto">
          <BookOpenIcon className="w-7 h-7 text-primary" />
        </div>
        <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
          {t("guide.page_title", { defaultValue: "User Guide" })}
        </h1>
        <p className="text-muted-foreground max-w-lg mx-auto">
          {t("guide.page_desc", { defaultValue: "Learn how to use Tibus as a traveler or as a bus company." })}
        </p>
      </motion.div>

      {/* Traveler section */}
      <TravelerGuide />

      {/* Divider */}
      <div className="border-t" />

      {/* Company section */}
      <CompanyGuide />
    </div>
  );
}
