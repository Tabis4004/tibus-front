import { useEffect, useRef } from "react";
import { toast } from "sonner";

export function useServiceWorker() {
  const toastShown = useRef(false);

  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

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
        void registration.update();

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

    const onControllerChange = () => {
      window.location.reload();
    };

    navigator.serviceWorker.addEventListener("controllerchange", onControllerChange);
    return () => {
      navigator.serviceWorker.removeEventListener("controllerchange", onControllerChange);
    };
  }, []);
}
