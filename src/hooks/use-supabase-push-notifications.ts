import { useCallback, useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import {
  getStoredPushEndpoint,
  getVapidPublicKeySupabase,
  registerPushSubscriptionSupabase,
  unregisterPushSubscriptionSupabase,
} from "@/lib/supabase/push.ts";
import type { NotificationStatus } from "./use-push-notifications.ts";

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

function isInIframe(): boolean {
  try {
    return window.self !== window.top;
  } catch {
    return true;
  }
}

export function useSupabasePushNotifications(isAuthenticated?: boolean) {
  const [endpoint, setEndpoint] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission | null>(null);

  useEffect(() => {
    if ("Notification" in window) {
      setPermission(Notification.permission);
    }
    setEndpoint(getStoredPushEndpoint());
  }, []);

  const status: NotificationStatus = useMemo(() => {
    if (!("Notification" in window) || !("serviceWorker" in navigator)) {
      return "unsupported";
    }
    if (isInIframe()) {
      return "iframe";
    }
    if (permission === "denied") {
      return "denied";
    }
    if (isLoading) {
      return "loading";
    }
    if (endpoint !== null) {
      return "subscribed";
    }
    return "unsubscribed";
  }, [permission, isLoading, endpoint]);

  const subscribe = useCallback(async () => {
    if (status === "unsupported" || status === "iframe" || status === "denied") {
      return { error: `Cannot subscribe: ${status}` };
    }
    if (!isAuthenticated) {
      return { error: "Connectez-vous pour activer les notifications" };
    }

    setIsLoading(true);
    try {
      const vapidPublicKey = await getVapidPublicKeySupabase();

      const perm = await Notification.requestPermission();
      setPermission(perm);
      if (perm !== "granted") {
        return { permission: "denied" };
      }

      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey) as BufferSource,
      });

      await registerPushSubscriptionSupabase(subscription);
      setEndpoint(subscription.endpoint);

      return { permission: "granted", subscribed: true };
    } catch (error) {
      toast.error("Impossible d'activer les notifications push.");
      return { error: String(error) };
    } finally {
      setIsLoading(false);
    }
  }, [status, isAuthenticated]);

  const identify = useCallback(async () => {
    return { success: true };
  }, []);

  const unsubscribe = useCallback(async () => {
    const currentEndpoint = endpoint ?? getStoredPushEndpoint();
    if (!currentEndpoint) {
      return { error: "No subscription to remove" };
    }

    setIsLoading(true);
    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();
      if (subscription) {
        await subscription.unsubscribe();
      }

      await unregisterPushSubscriptionSupabase(currentEndpoint);
      setEndpoint(null);

      return { success: true };
    } catch (error) {
      return { error: String(error) };
    } finally {
      setIsLoading(false);
    }
  }, [endpoint]);

  return { status, subscribe, identify, unsubscribe };
}
