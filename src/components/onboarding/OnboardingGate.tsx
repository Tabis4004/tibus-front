import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocation } from "react-router-dom";
import { useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useQuery } from "convex/react";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useAppUser, refreshAppUserAsync } from "@/hooks/use-app-user.ts";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { markOnboardingCompleted } from "@/lib/supabase/onboarding.ts";
import { getOnboardingAudience } from "@/lib/onboarding-audience.ts";
import { EXPLORE_FEATURES_EVENT } from "@/lib/onboarding-events.ts";
import {
  filterTourSteps,
  resolveOnboardingTour,
  type TourStepConfig,
} from "@/lib/onboarding-tours.ts";
import SpotlightTour from "@/components/onboarding/SpotlightTour.tsx";

const EXCLUDED_PATH =
  /\/(trip\/|booking\/|payment\/|verify\/|agent-marchand|complete-profile|auth\/|manual\/)/;

function useTourReady(steps: TourStepConfig[], enabled: boolean) {
  const [readySteps, setReadySteps] = useState<TourStepConfig[]>([]);

  useEffect(() => {
    if (!enabled || steps.length === 0) {
      setReadySteps([]);
      return;
    }

    let cancelled = false;
    let attempts = 0;

    const tick = () => {
      if (cancelled) return;
      const available = filterTourSteps(steps);
      if (available.length > 0) {
        setReadySteps(available);
        return;
      }
      attempts += 1;
      if (attempts < 80) {
        window.setTimeout(tick, 150);
      } else {
        setReadySteps(steps);
      }
    };

    tick();
    const interval = window.setInterval(() => {
      if (cancelled) return;
      const available = filterTourSteps(steps);
      if (available.length > 0) {
        setReadySteps((prev) =>
          available.length > prev.length ? available : prev,
        );
      }
    }, 500);

    return () => {
      cancelled = true;
      window.clearInterval(interval);
      setReadySteps([]);
    };
  }, [enabled, steps]);

  return readySteps;
}

function tourArmDelay(pathname: string) {
  const isSellerRoute = /\/seller(\/|$)/.test(pathname);
  const isCompanyRoute = /\/company(\/|$)/.test(pathname);
  if (isSellerRoute) return { leadMs: 900, tailMs: 900 };
  if (isCompanyRoute) return { leadMs: 400, tailMs: 500 };
  return { leadMs: 300, tailMs: 500 };
}

function useTourArming(
  shouldAutoArm: boolean,
  manualRequest: number,
  pathname: string,
  tour: ReturnType<typeof resolveOnboardingTour>,
) {
  const [armed, setArmed] = useState(false);
  const manualReplayRef = useRef(false);

  const armTour = useCallback(
    (manual: boolean) => {
      if (!tour) return;
      manualReplayRef.current = manual;
      let cancelled = false;
      const { leadMs, tailMs } = tourArmDelay(pathname);
      const timer = window.setTimeout(() => {
        tour.onStart?.();
        window.setTimeout(() => {
          if (!cancelled) setArmed(true);
        }, tailMs);
      }, leadMs);
      return () => {
        cancelled = true;
        window.clearTimeout(timer);
      };
    },
    [pathname, tour],
  );

  useEffect(() => {
    if (!shouldAutoArm) return;
    return armTour(false);
  }, [shouldAutoArm, armTour]);

  useEffect(() => {
    if (manualRequest === 0) return;
    setArmed(false);
    return armTour(true);
  }, [manualRequest, armTour]);

  useEffect(() => {
    if (!shouldAutoArm && manualRequest === 0) {
      setArmed(false);
    }
  }, [shouldAutoArm, manualRequest]);

  return {
    armed,
    setArmed,
    isManualReplay: () => manualReplayRef.current,
  };
}

function SupabaseOnboardingGate() {
  const location = useLocation();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [manualRequest, setManualRequest] = useState(0);

  const audience = useMemo(
    () => getOnboardingAudience(appUser.roles),
    [appUser.roles],
  );

  const tour = useMemo(
    () => resolveOnboardingTour(location.pathname, audience),
    [location.pathname, audience],
  );

  const shouldAutoArm =
    !EXCLUDED_PATH.test(location.pathname) &&
    appUser.isReady &&
    !appUser.isLoading &&
    appUser.profileCompleted &&
    !appUser.onboardingCompleted &&
    tour !== null;

  useEffect(() => {
    const onExplore = () => {
      if (!tour || EXCLUDED_PATH.test(location.pathname)) return;
      setManualRequest((count) => count + 1);
    };
    window.addEventListener(EXPLORE_FEATURES_EVENT, onExplore);
    return () => window.removeEventListener(EXPLORE_FEATURES_EVENT, onExplore);
  }, [location.pathname, tour]);

  const { armed, setArmed, isManualReplay } = useTourArming(
    shouldAutoArm,
    manualRequest,
    location.pathname,
    tour,
  );

  const readySteps = useTourReady(tour?.steps ?? [], armed);

  const handleStepChange = useCallback(
    (step: TourStepConfig) => {
      if (step.target.includes('data-tour="owner-')) {
        window.dispatchEvent(
          new CustomEvent("tibus:owner-sidebar", { detail: { open: true } }),
        );
      }
      tour?.onStart?.();
    },
    [tour],
  );

  const handleComplete = async () => {
    const manual = isManualReplay();
    if (!manual && appUserId && !appUser.onboardingCompleted) {
      try {
        await markOnboardingCompleted(appUserId);
        await refreshAppUserAsync();
      } catch {
        // localStorage déjà posé dans markOnboardingCompleted
      }
    }
    setArmed(false);
  };

  if (!tour || !armed || readySteps.length === 0) return null;

  return (
    <SpotlightTour
      open
      steps={readySteps}
      onStart={tour.onStart}
      onStepChange={handleStepChange}
      onComplete={handleComplete}
    />
  );
}

function ConvexOnboardingGate() {
  const location = useLocation();
  const user = useQuery(api.users.getCurrentUser, {});
  const markOnboarded = useMutation(api.users.markOnboarded);
  const [manualRequest, setManualRequest] = useState(0);

  const audience = useMemo(() => {
    const role = user?.role ?? "traveler";
    if (role === "owner" || role === "superadmin") return "owner" as const;
    if (role === "seller") return "seller" as const;
    return "traveler" as const;
  }, [user?.role]);

  const tour = useMemo(
    () => resolveOnboardingTour(location.pathname, audience),
    [location.pathname, audience],
  );

  const shouldAutoArm = Boolean(
    !EXCLUDED_PATH.test(location.pathname) &&
    user != null &&
    user.profileCompleted &&
    user.onboardingCompleted === false &&
    tour !== null,
  );

  useEffect(() => {
    const onExplore = () => {
      if (!tour || EXCLUDED_PATH.test(location.pathname)) return;
      setManualRequest((count) => count + 1);
    };
    window.addEventListener(EXPLORE_FEATURES_EVENT, onExplore);
    return () => window.removeEventListener(EXPLORE_FEATURES_EVENT, onExplore);
  }, [location.pathname, tour]);

  const { armed, setArmed, isManualReplay } = useTourArming(
    shouldAutoArm,
    manualRequest,
    location.pathname,
    tour,
  );

  const readySteps = useTourReady(tour?.steps ?? [], armed);

  const handleStepChange = useCallback(
    (step: TourStepConfig) => {
      if (step.target.includes('data-tour="owner-')) {
        window.dispatchEvent(
          new CustomEvent("tibus:owner-sidebar", { detail: { open: true } }),
        );
      }
      tour?.onStart?.();
    },
    [tour],
  );

  const handleComplete = async () => {
    const manual = isManualReplay();
    if (!manual && user?.onboardingCompleted === false) {
      try {
        await markOnboarded({});
      } catch {
        // still close
      }
    }
    setArmed(false);
  };

  if (!tour || !armed || readySteps.length === 0) return null;

  return (
    <SpotlightTour
      open
      steps={readySteps}
      onStart={tour.onStart}
      onStepChange={handleStepChange}
      onComplete={handleComplete}
    />
  );
}

export default function OnboardingGate() {
  if (isSupabaseAuth()) return <SupabaseOnboardingGate />;
  return <ConvexOnboardingGate />;
}
