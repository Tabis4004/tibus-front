const AT_MESSAGING_URL = "https://api.africastalking.com/version1/messaging";

export type AfricasTalkingSendResult = {
  ok: boolean;
  statusCode: number;
  body: unknown;
  errorMessage?: string;
};

/** Normalise vers E.164 pour l'API Africa's Talking. */
export function normalizePhoneForAt(phone: string): string | null {
  const cleaned = phone.trim().replace(/[^\d+]/g, "");
  if (!cleaned) return null;

  if (cleaned.startsWith("+")) {
    const digits = cleaned.slice(1).replace(/\D/g, "");
    return digits.length >= 9 && digits.length <= 15 ? `+${digits}` : null;
  }

  const digits = cleaned.replace(/\D/g, "");
  return digits.length >= 10 && digits.length <= 15 ? `+${digits}` : null;
}

export async function sendAfricasTalkingSms(
  to: string,
  message: string,
): Promise<AfricasTalkingSendResult> {
  const username = Deno.env.get("AT_USERNAME")?.trim();
  const apiKey = Deno.env.get("AT_API_KEY")?.trim();
  const senderId = Deno.env.get("AT_SENDER_ID")?.trim();

  if (!username || !apiKey) {
    return {
      ok: false,
      statusCode: 500,
      body: null,
      errorMessage: "AT_USERNAME ou AT_API_KEY manquant",
    };
  }

  const body = new URLSearchParams({
    username,
    to,
    message: message.replace(/\r?\n/g, "\r\n"),
    ...(senderId ? { from: senderId } : {}),
  });

  const response = await fetch(AT_MESSAGING_URL, {
    method: "POST",
    headers: {
      Apikey: apiKey,
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  const rawText = await response.text();
  let parsed: unknown = rawText;
  try {
    parsed = JSON.parse(rawText);
  } catch {
    // keep raw text
  }

  const recipients = (parsed as { SMSMessageData?: { Recipients?: Array<{ status?: string }> } })
    ?.SMSMessageData?.Recipients;
  const recipientOk = recipients?.some((r) => r.status === "Success") ?? false;

  if (!response.ok || !recipientOk) {
    const apiMessage =
      typeof parsed === "object" && parsed !== null && "SMSMessageData" in parsed
        ? String((parsed as { SMSMessageData?: { Message?: string } }).SMSMessageData?.Message ?? "")
        : String(parsed);

    return {
      ok: false,
      statusCode: response.status || 500,
      body: parsed,
      errorMessage: apiMessage || "Échec envoi SMS Africa's Talking",
    };
  }

  return { ok: true, statusCode: response.status, body: parsed };
}
