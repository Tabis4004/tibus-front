import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { motion, AnimatePresence } from "motion/react";
import { Button } from "@/components/ui/button.tsx";
import {
  Dialog,
  DialogContent,
} from "@/components/ui/dialog.tsx";
import {
  SearchIcon,
  TicketIcon,
  SmartphoneIcon,
  StarIcon,
  BuildingIcon,
  BusIcon,
  UsersIcon,
  BarChart3Icon,
  ArrowRightIcon,
  ArrowLeftIcon,
  BookOpenIcon,
  XIcon,
} from "lucide-react";

type OnboardingStep = {
  icon: React.ElementType;
  title: string;
  desc: string;
  image: string;
};

function OnboardingSlide({ step, index, total }: { step: OnboardingStep; index: number; total: number }) {
  return (
    <motion.div
      key={step.title}
      initial={{ opacity: 0, x: 40 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: -40 }}
      transition={{ duration: 0.3, ease: "easeOut" }}
      className="space-y-4"
    >
      {/* Image */}
      <div className="rounded-2xl overflow-hidden border">
        <img src={step.image} alt={step.title} className="w-full h-40 sm:h-48 object-cover" />
      </div>
      {/* Content */}
      <div className="space-y-2 text-center px-2">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center mx-auto">
          <step.icon className="w-5 h-5 text-primary" />
        </div>
        <h3 className="text-lg font-bold">{step.title}</h3>
        <p className="text-sm text-muted-foreground leading-relaxed">{step.desc}</p>
      </div>
      {/* Progress dots */}
      <div className="flex items-center justify-center gap-1.5 pt-2">
        {Array.from({ length: total }).map((_, i) => (
          <div
            key={i}
            className={`h-2 rounded-full transition-all ${
              i === index ? "w-6 bg-primary" : "w-2 bg-muted-foreground/20"
            }`}
          />
        ))}
      </div>
    </motion.div>
  );
}

export default function OnboardingDialog({
  open,
  onClose,
  userRole,
}: {
  open: boolean;
  onClose: () => void;
  userRole: string;
}) {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const markOnboarded = useMutation(api.users.markOnboarded);
  const [currentStep, setCurrentStep] = useState(0);
  const locale = lng ?? "en";

  const travelerSteps: OnboardingStep[] = [
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

  const companySteps: OnboardingStep[] = [
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
  ];

  const steps = userRole === "owner" || userRole === "seller" ? companySteps : travelerSteps;
  const isLast = currentStep === steps.length - 1;

  const handleFinish = async () => {
    try {
      await markOnboarded({});
    } catch {
      // Silent - still close
    }
    onClose();
  };

  const handleNext = () => {
    if (isLast) {
      handleFinish();
    } else {
      setCurrentStep((s) => s + 1);
    }
  };

  const handlePrev = () => {
    setCurrentStep((s) => Math.max(0, s - 1));
  };

  const handleViewGuide = async () => {
    await handleFinish();
    navigate(`/${locale}/guide`);
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) handleFinish(); }}>
      <DialogContent className="max-w-md p-0 gap-0 overflow-hidden">
        {/* Close button */}
        <button
          onClick={handleFinish}
          className="absolute top-3 right-3 z-10 p-1.5 rounded-full bg-muted/80 hover:bg-muted transition-colors cursor-pointer"
          aria-label="Close"
        >
          <XIcon className="w-4 h-4" />
        </button>

        <div className="p-6 space-y-4">
          {/* Welcome header on first slide */}
          {currentStep === 0 && (
            <div className="text-center space-y-1 pb-2">
              <p className="text-xs font-semibold text-primary uppercase tracking-wider">
                {t("guide.onboarding_welcome", { defaultValue: "Welcome to Tibus" })}
              </p>
            </div>
          )}

          {/* Slide */}
          <AnimatePresence mode="wait">
            <OnboardingSlide
              step={steps[currentStep]}
              index={currentStep}
              total={steps.length}
            />
          </AnimatePresence>

          {/* Buttons */}
          <div className="flex items-center justify-between gap-3 pt-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={handlePrev}
              disabled={currentStep === 0}
              className="cursor-pointer gap-1"
            >
              <ArrowLeftIcon className="w-4 h-4" />
              {t("guide.prev", { defaultValue: "Back" })}
            </Button>

            <Button
              size="sm"
              onClick={handleNext}
              className="cursor-pointer gap-1"
            >
              {isLast
                ? t("guide.finish", { defaultValue: "Got it!" })
                : t("guide.next", { defaultValue: "Next" })}
              {!isLast && <ArrowRightIcon className="w-4 h-4" />}
            </Button>
          </div>

          {/* View full guide link */}
          <div className="text-center">
            <button
              onClick={handleViewGuide}
              className="text-xs text-muted-foreground hover:text-primary transition-colors underline cursor-pointer"
            >
              <BookOpenIcon className="w-3 h-3 inline mr-1" />
              {t("guide.view_full_guide", { defaultValue: "View full guide" })}
            </button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
