const AT_MESSAGING_URL = "https://api.africastalking.com/version1/messaging";

const PHONE_COUNTRY_PREFIXES = [
  "225", "226", "221", "229", "223", "228", "237", "241", "233", "224", "245",
  "254", "265", "227", "234", "256", "243", "242", "250", "232", "255", "260", "258",
].sort((a, b) => b.length - a.length);

const DEFAULT_DIAL_BY_COUNTRY: Record<string, string> = {
  CI: "225",
  BF: "226",
  SN: "221",
  BJ: "229",
  ML: "223",
  TG: "228",
  CM: "237",
  GA: "241",
  GH: "233",
  GN: "224",
  GW: "245",
};

const AT_SUCCESS_STATUSES = new Set(["Success", "Sent", "Buffered", "Submitted"]);

export type AfricasTalkingSendResult = {
  ok: boolean;
  statusCode: number;
  body: unknown;
  errorMessage?: string;
};

function dialCodeForCountry(countryCode?: string | null): string {
  const code = (countryCode ?? Deno.env.get("AT_DEFAULT_COUNTRY") ?? "CI")
    .trim()
    .toUpperCase();
  return DEFAULT_DIAL_BY_COUNTRY[code] ?? "225";
}

/** Normalise vers E.164 pour l'API Africa's Talking (Afrique de l'Ouest). */
export function normalizePhoneForAt(
  phone: string,
  defaultCountryCode?: string | null,
): string | null {
  const trimmed = phone.trim();
  const cleaned = trimmed.replace(/[^\d+]/g, "");
  if (!cleaned) return null;

  if (cleaned.startsWith("+")) {
    const digits = cleaned.slice(1).replace(/\D/g, "");
    if (!digits) return null;
    // +22507… → +2257… (double zéro après indicatif pays)
    const fixed = digits.replace(/^(225|226|221|229|223|228)0(\d+)$/, "$1$2");
    const normalized = fixed.length >= 9 && fixed.length <= 15 ? fixed : digits;
    return normalized.length >= 9 && normalized.length <= 15 ? `+${normalized}` : null;
  }

  const digits = cleaned.replace(/\D/g, "");
  if (!digits) return null;

  for (const prefix of PHONE_COUNTRY_PREFIXES) {
    if (digits.startsWith(prefix) && digits.length >= prefix.length + 8) {
      return `+${digits}`;
    }
  }

  const dial = dialCodeForCountry(defaultCountryCode);

  // Côte d'Ivoire : 07 00 00 00 00 (10 chiffres)
  if (dial === "225" && /^0[1-9]\d{8}$/.test(digits)) {
    return `+225${digits.slice(1)}`;
  }

  // Numéro local avec 0 initial (8–9 chiffres après le 0)
  if (/^0\d{7,9}$/.test(digits)) {
    return `+${dial}${digits.slice(1)}`;
  }

  if (digits.length >= 8 && digits.length <= 15) {
    return `+${digits}`;
  }

  return null;
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
  const recipientOk =
    !recipients?.length ||
    recipients.some((r) => AT_SUCCESS_STATUSES.has(String(r.status ?? "")));

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
