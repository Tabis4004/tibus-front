import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { isTibusPosWebView } from "@/lib/webview-bridge.ts";

export function useServiceWorker() {
  const toastShown = useRef(false);

  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    // Service worker breaks Android TPE WebViews (stale bundles + reload loops).
    if (isTibusPosWebView()) {
      void navigator.serviceWorker.getRegistrations().then((registrations) => {
        for (const registration of registrations) {
          void registration.unregister();
        }
      });
      return;
    }

    const showUpdateToast = (registration: ServiceWorkerRegistration) => {
      if (toastShown.current) return;
      toastShown.current = true;

      toast("Une nouvelle version de Tibus est disponible.", {
        duration: Infinity,
        action: {
          label: "Recharger",
          onClick: () => {
            registration.waiting?.postMessage({ type: "SKIP_WAITING" });
            window.location.reload();
          },
        },
      });
    };

    navigator.serviceWorker
      .register("/sw.js", { updateViaCache: "none" })
      .then((registration) => {
        if (registration.waiting) {
          showUpdateToast(registration);
        }

        registration.addEventListener("updatefound", () => {
          const newWorker = registration.installing;
          if (!newWorker) return;

          newWorker.addEventListener("statechange", () => {
            if (newWorker.state === "installed" && navigator.serviceWorker.controller) {
              showUpdateToast(registration);
            }
          });
        });
      })
      .catch((err) => console.warn("Service Worker registration failed:", err));
  }, []);
}
