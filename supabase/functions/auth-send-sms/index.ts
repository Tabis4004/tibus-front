import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { sendAfricasTalkingSms } from "../_shared/africastalking-sms.ts";

type HookPayload = {
  user?: { phone?: string };
  sms?: { otp?: string };
};

function hookSecretBase64(): string {
  const raw = Deno.env.get("SEND_SMS_HOOK_SECRET")?.trim();
  if (!raw) {
    throw new Error("SEND_SMS_HOOK_SECRET manquant");
  }
  return raw.replace(/^v1,whsec_/, "");
}

function jsonError(message: string, httpCode = 500) {
  return new Response(
    JSON.stringify({ error: { http_code: httpCode, message } }),
    {
      status: httpCode,
      headers: { "Content-Type": "application/json" },
    },
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonError("Méthode non autorisée", 405);
  }

  try {
    const payload = await req.text();
    const wh = new Webhook(hookSecretBase64());
    const { user, sms } = wh.verify(payload, Object.fromEntries(req.headers)) as HookPayload;

    const phone = user?.phone?.trim() ?? "";
    const otp = sms?.otp?.trim() ?? "";

    if (!phone || !otp) {
      return jsonError("Téléphone ou OTP manquant dans le hook", 400);
    }

    const message = `Votre code Tibus : ${otp}. Valide 60 secondes.`;
    const result = await sendAfricasTalkingSms(phone, message);

    if (!result.ok) {
      console.error("[auth-send-sms]", result.body);
      return jsonError(result.errorMessage ?? "Échec envoi SMS", result.statusCode || 500);
    }

    return new Response("{}", {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[auth-send-sms]", err);
    const message = err instanceof Error ? err.message : "Erreur hook SMS";
    return jsonError(message, 500);
  }
});
