// Envoi de notifications via Firebase Cloud Messaging, API HTTP v1.
// Nécessite le secret FCM_SERVICE_ACCOUNT (contenu JSON complet du fichier
// clé de compte de service, téléchargé depuis Firebase Console >
// Paramètres du projet > Comptes de service > Générer une nouvelle clé
// privée). À définir avec :
//
//   supabase secrets set FCM_SERVICE_ACCOUNT='<contenu du fichier .json>' --project-ref <ref>
//
// Voir README, section "Notifications push natives (FCM)".
import { GoogleAuth } from "npm:google-auth-library@9.14.1";

export type FcmTarget = { fcmToken: string; platform: "android" | "ios" };

function getServiceAccount(): Record<string, unknown> {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) {
    throw new Error("Secret FCM_SERVICE_ACCOUNT manquant (voir README)");
  }
  return JSON.parse(raw);
}

let cachedAuth: GoogleAuth | null = null;

async function getAccessToken(): Promise<string> {
  if (!cachedAuth) {
    cachedAuth = new GoogleAuth({
      credentials: getServiceAccount(),
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
  }
  const client = await cachedAuth.getClient();
  const token = await client.getAccessToken();
  if (!token.token) throw new Error("Impossible d'obtenir un token FCM");
  return token.token;
}

export async function sendFcmToTokens(
  targets: FcmTarget[],
  payload: { title: string; body: string; data?: Record<string, string> },
): Promise<{ sent: number; staleTokens: string[] }> {
  if (targets.length === 0) return { sent: 0, staleTokens: [] };

  const serviceAccount = getServiceAccount();
  const projectId = serviceAccount.project_id as string;
  const accessToken = await getAccessToken();

  let sent = 0;
  const staleTokens: string[] = [];

  await Promise.all(
    targets.map(async ({ fcmToken }) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: fcmToken,
              notification: { title: payload.title, body: payload.body },
              data: payload.data ?? {},
            },
          }),
        },
      );

      if (res.ok) {
        sent += 1;
        return;
      }

      const body = await res.json().catch(() => ({}));
      const status = body?.error?.status;
      if (status === "NOT_FOUND" || status === "UNREGISTERED" || status === "INVALID_ARGUMENT") {
        staleTokens.push(fcmToken);
      }
    }),
  );

  return { sent, staleTokens };
}
