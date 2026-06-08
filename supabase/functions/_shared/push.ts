import webpush from "npm:web-push@3.6.7";

export type PushSubscriptionRow = {
  endpoint: string;
  p256dh: string;
  auth: string;
};

export function configureWebPush() {
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@tibus.app";

  if (!publicKey || !privateKey) {
    throw new Error("VAPID_PUBLIC_KEY ou VAPID_PRIVATE_KEY manquant");
  }

  webpush.setVapidDetails(subject, publicKey, privateKey);
  return publicKey;
}

export async function sendPushToSubscriptions(
  subscriptions: PushSubscriptionRow[],
  payload: { title: string; body: string; url?: string },
) {
  configureWebPush();

  const options = {
    body: payload.body,
    icon: "/icon/icon-192.png",
    badge: "/icon/icon-192.png",
    data: { url: payload.url ?? "/" },
  };

  let sent = 0;
  const staleEndpoints: string[] = [];

  await Promise.all(
    subscriptions.map(async (sub) => {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          },
          JSON.stringify({ title: payload.title, options }),
        );
        sent += 1;
      } catch (error) {
        const status = (error as { statusCode?: number }).statusCode;
        if (status === 404 || status === 410) {
          staleEndpoints.push(sub.endpoint);
        }
        console.error("Push failed:", sub.endpoint, error);
      }
    }),
  );

  return { sent, staleEndpoints };
}
