import { normalizePhoneForAt } from "./africastalking-sms.ts";

export type InfobipSendResult = {
  ok: boolean;
  statusCode: number;
  body: unknown;
  errorMessage?: string;
  messageId?: string;
};

/** Infobip attend le numéro sans « + » (ex. 225712960000). */
export function normalizePhoneForInfobip(
  phone: string,
  defaultCountryCode?: string | null,
): string | null {
  const e164 = normalizePhoneForAt(phone, defaultCountryCode);
  if (!e164) return null;
  return e164.replace(/^\+/, "");
}

function infobipBaseUrl(): string {
  const raw = Deno.env.get("INFOBIP_BASE_URL")?.trim();
  if (!raw) return "https://api.infobip.com";
  return raw.replace(/\/$/, "");
}

/** Statuts Infobip acceptés à l'envoi (PENDING_* ou DELIVERED_*). */
function isInfobipSendAccepted(status: { groupId?: number; groupName?: string; name?: string }): boolean {
  const groupId = Number(status.groupId ?? 0);
  const groupName = String(status.groupName ?? "").toUpperCase();
  const name = String(status.name ?? "").toUpperCase();
  if (groupId === 1 || groupId === 3) return true;
  if (groupName.includes("PENDING") || groupName.includes("DELIVERED")) return true;
  if (name.includes("PENDING") || name.includes("DELIVERED")) return true;
  return false;
}

export async function sendInfobipSms(
  to: string,
  message: string,
): Promise<InfobipSendResult> {
  const apiKey = Deno.env.get("INFOBIP_API_KEY")?.trim();
  const sender = Deno.env.get("INFOBIP_SENDER")?.trim() || "ServiceSMS";

  if (!apiKey) {
    return {
      ok: false,
      statusCode: 500,
      body: null,
      errorMessage: "INFOBIP_API_KEY manquant",
    };
  }

  const url = `${infobipBaseUrl()}/sms/3/messages`;
  const payload = {
    messages: [
      {
        sender,
        destinations: [{ to }],
        content: { text: message },
      },
    ],
  };

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `App ${apiKey}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const rawText = await response.text();
  let parsed: unknown = rawText;
  try {
    parsed = JSON.parse(rawText);
  } catch {
    // keep raw text
  }

  const firstMessage = (parsed as {
    messages?: Array<{
      messageId?: string;
      status?: { groupId?: number; groupName?: string; name?: string; description?: string };
    }>;
    requestError?: { serviceException?: { text?: string; messageId?: string } };
  })?.messages?.[0];

  const requestError = (parsed as {
    requestError?: { serviceException?: { text?: string } };
  })?.requestError?.serviceException?.text;

  if (!response.ok) {
    return {
      ok: false,
      statusCode: response.status || 500,
      body: parsed,
      errorMessage: requestError || `Échec envoi SMS Infobip (${response.status})`,
    };
  }

  const status = firstMessage?.status;
  if (status && !isInfobipSendAccepted(status)) {
    return {
      ok: false,
      statusCode: response.status,
      body: parsed,
      errorMessage: status.description || status.name || "SMS rejeté par Infobip",
      messageId: firstMessage?.messageId,
    };
  }

  return {
    ok: true,
    statusCode: response.status,
    body: parsed,
    messageId: firstMessage?.messageId,
  };
}

export function resolveSmsProvider(): "infobip" | "africastalking" {
  const explicit = Deno.env.get("SMS_PROVIDER")?.trim().toLowerCase();
  if (explicit === "infobip") return "infobip";
  if (explicit === "africastalking" || explicit === "at") return "africastalking";
  if (Deno.env.get("INFOBIP_API_KEY")?.trim()) return "infobip";
  return "africastalking";
}
