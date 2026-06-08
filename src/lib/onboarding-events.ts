import type { OnboardingAudience } from "@/lib/onboarding-audience.ts";
import {
  getDefaultTourPath,
  resolveOnboardingTour,
} from "@/lib/onboarding-tours.ts";

export const EXPLORE_FEATURES_EVENT = "tibus:explore-features";

export function dispatchExploreFeaturesTour() {
  window.dispatchEvent(new CustomEvent(EXPLORE_FEATURES_EVENT));
}

export function startExploreTour(input: {
  pathname: string;
  audience: OnboardingAudience;
  lng: string;
  navigate: (path: string) => void;
}) {
  const tour = resolveOnboardingTour(input.pathname, input.audience);
  if (!tour) {
    input.navigate(getDefaultTourPath(input.audience, input.lng));
    window.setTimeout(() => dispatchExploreFeaturesTour(), 600);
    return;
  }
  dispatchExploreFeaturesTour();
}
