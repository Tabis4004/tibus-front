import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import {
  claimReferralSignupSupabase,
  clearStoredReferralCode,
  readStoredReferralCode,
  storeReferralCode,
} from "@/lib/supabase/platform-loyalty.ts";

/** Capture ?ref= dans l’URL et enregistre le parrainage après connexion. */
export default function ReferralBootstrap() {
  const { session, appUserId, isLoading, isBootstrapping } = useSupabaseAuth();
  const claimAttemptedRef = useRef(false);

  useEffect(() => {
    const ref = new URLSearchParams(window.location.search).get("ref");
    if (ref?.trim()) {
      storeReferralCode(ref);
    }
  }, []);

  useEffect(() => {
    if (isLoading || isBootstrapping || !session || !appUserId || claimAttemptedRef.current) {
      return;
    }

    const code = readStoredReferralCode();
    if (!code) return;

    claimAttemptedRef.current = true;

    void claimReferralSignupSupabase(code)
      .then((result) => {
        clearStoredReferralCode();
        if (result.success) {
          toast.success("Parrainage enregistré — vos points Tibus ont été crédités.");
          return;
        }
        if (result.error && !/déjà|deja|already|own code|votre propre/i.test(result.error)) {
          toast.message(result.error);
        }
      })
      .catch(() => {
        clearStoredReferralCode();
      });
  }, [session, appUserId, isLoading, isBootstrapping]);

  return null;
}
