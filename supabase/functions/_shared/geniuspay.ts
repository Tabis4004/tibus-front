/** Même URL pour sandbox et live — le mode dépend des clés pk_live_/sk_live_ vs pk_sandbox_/sk_sandbox_. */
const GENIUSPAY_BASE =
  Deno.env.get("GENIUSPAY_BASE_URL") ?? "https://pay.genius.ci/api/v1/merchant";

export type GeniusPayPayment = {
  id?: number;
  reference?: string;
  status?: string;
  metadata?: Record<string, string>;
};

const PHONE_COUNTRY_PREFIXES = [
  "225", "226", "221", "229", "223", "228", "237", "241", "233", "224", "245",
  "254", "265", "227", "234", "256", "243", "242", "250", "232", "255", "260", "258",
].sort((a, b) => b.length - a.length);

function apiHeaders() {
  const publicKey =
    Deno.env.get("GENIUSPAY_PUBLIC_KEY") ??
    Deno.env.get("VITE_GENIUSPAY_PUBLIC_KEY");
  const secretKey = Deno.env.get("GENIUSPAY_SECRET_KEY");
  if (!publicKey || !secretKey) {
    throw new Error("GENIUSPAY_PUBLIC_KEY et GENIUSPAY_SECRET_KEY requis");
  }
  return {
    "X-API-Key": publicKey,
    "X-API-Secret": secretKey,
    "Content-Type": "application/json",
  };
}

/** Téléphone international — ne force pas la Côte d'Ivoire ; GeniusPay gère le pays au checkout. */
export function normalizeGeniusPayPhone(raw: string): string {
  const trimmed = raw.trim();
  const digits = trimmed.replace(/\D/g, "");
  if (!digits) {
    throw new Error(
      "Numéro de téléphone requis — format international (+225…) ou local",
    );
  }

  if (trimmed.startsWith("+")) {
    return `+${digits}`;
  }

  for (const prefix of PHONE_COUNTRY_PREFIXES) {
    if (digits.startsWith(prefix) && digits.length >= prefix.length + 8) {
      return `+${digits}`;
    }
  }

  if (/^0[1-9]\d{8}$/.test(digits)) {
    return `+225${digits.slice(1)}`;
  }

  if (/^0\d{7,9}$/.test(digits)) {
    return `+226${digits.replace(/^0/, "")}`;
  }

  if (digits.length >= 10) {
    return `+${digits}`;
  }

  throw new Error(
    "Numéro invalide — utilisez le format international (+225, +226…) ou un numéro local valide",
  );
}

function flattenMetadata(metadata: Record<string, string>): Record<string, string> {
  const flat: Record<string, string> = {};
  for (const [key, value] of Object.entries(metadata)) {
    flat[key] = String(value ?? "");
  }
  return flat;
}

function parsePayment(json: Record<string, unknown>): GeniusPayPayment | null {
  const data = json.data as GeniusPayPayment | undefined;
  if (!data?.reference) return null;
  const metadata = data.metadata;
  return {
    id: data.id,
    reference: data.reference,
    status: data.status,
    metadata:
      metadata && typeof metadata === "object"
        ? (metadata as Record<string, string>)
        : {},
  };
}

export type GeniusPayRouting = {
  paymentMethod: string;
  gateway?: string;
  mmoProvider?: string;
};

/** Codes PawaPay par pays/réseau (doc GeniusPay). */
const PAWAPAY_MMO_PROVIDERS: Record<string, Partial<Record<string, string>>> = {
  CI: {
    orange: "ORANGE_CIV",
    mtn: "MTN_MOMO_CIV",
    moov: "MOOV_CIV",
    wave: "WAVE_CIV",
  },
  BF: {
    orange: "ORANGE_BFA",
    moov: "MOOV_BFA",
    mobicash: "MOOV_BFA",
    wave: "WAVE_BFA",
  },
  SN: {
    orange: "ORANGE_SEN",
    free: "FREE_SEN",
    wave: "WAVE_SEN",
  },
  BJ: {
    mtn: "MTN_MOMO_BEN",
    moov: "MOOV_BEN",
  },
  TG: {
    moov: "MOOV_TGO",
    togocel: "MOOV_TGO",
  },
  ML: {
    orange: "ORANGE_MLI",
    mobicash: "ORANGE_MLI",
  },
  CM: {
    mtn: "MTN_MOMO_CMR",
    orange: "ORANGE_CMR",
  },
  GH: {
    mtn: "MTN_GHA",
  },
  KE: {
    mpesa: "MPESA_KEN",
    airtel: "AIRTEL_KEN",
  },
};

export function mapNetworkToGeniusPayMmo(
  network?: string,
  countryCode?: string,
): GeniusPayRouting | null {
  return mapNetworkToGeniusPayRouting(network, countryCode);
}

/** Route GeniusPay — PawaPay + mmo_provider quand disponible (évite checkout Wave par défaut en CI). */
export function mapNetworkToGeniusPayRouting(
  network?: string,
  countryCode?: string,
): GeniusPayRouting | null {
  const normalized = (network ?? "unknown").trim().toLowerCase();
  if (!normalized || normalized === "unknown") return null;

  const country = (countryCode ?? "CI").trim().toUpperCase();
  const pawapayProvider = PAWAPAY_MMO_PROVIDERS[country]?.[normalized];

  if (pawapayProvider) {
    return {
      paymentMethod: "pawapay",
      mmoProvider: pawapayProvider,
    };
  }

  switch (normalized) {
    case "wave":
      return { paymentMethod: "wave" };
    case "orange":
      return { paymentMethod: "orange_money" };
    case "mtn":
      return { paymentMethod: "mtn_money" };
    case "moov":
    case "togocel":
      return { paymentMethod: "moov_money" };
    case "free":
      return { paymentMethod: "pawapay" };
    case "airtel":
      return { paymentMethod: "airtel_money" };
    case "mpesa":
    case "vodacom":
    case "tigo":
    case "zamtel":
    case "mobicash":
      return { paymentMethod: "pawapay" };
    default:
      return null;
  }
}

function formatGeniusPayError(raw: string): string {
  try {
    const json = JSON.parse(raw) as {
      error?: {
        message?: string;
        failureReason?: { message?: string; code?: string };
      };
      message?: string;
    };
    const detail =
      json.error?.failureReason?.message ??
      json.error?.message ??
      json.message;
    if (detail) return `Paiement GeniusPay : ${detail}`;
  } catch {
    // ignore
  }
  return `GeniusPay payment failed: ${raw.slice(0, 300)}`;
}

function isGeniusPayHostedUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return (
      host === "pay.genius.ci" ||
      host.endsWith(".genius.ci") ||
      host === "geniuspay.ci" ||
      host.endsWith(".geniuspay.ci")
    );
  } catch {
    return false;
  }
}

export async function createGeniusPayCheckout(args: {
  amount: number;
  description: string;
  successUrl: string;
  errorUrl: string;
  customer: {
    name: string;
    email: string;
    phone?: string;
  };
  metadata: Record<string, string>;
  paymentNetwork?: string;
  paymentCountryCode?: string;
}) {
  const network = (args.paymentNetwork ?? "").trim().toLowerCase();
  if (!network || network === "unknown") {
    throw new Error(
      "Réseau Mobile Money requis avant redirection vers GeniusPay.",
    );
  }

  const phone = args.customer.phone?.trim();
  if (!args.paymentCountryCode?.trim()) {
    throw new Error("Pays de paiement requis pour GeniusPay.");
  }

  const countryCode = args.paymentCountryCode.trim().toUpperCase();

  // Checkout hébergé : ne pas envoyer le téléphone (sinon GeniusPay auto-route vers Wave/opérateur direct).
  const customer: Record<string, string> = {
    name: args.customer.name,
    email: args.customer.email,
  };

  const body: Record<string, unknown> = {
    amount: Math.ceil(args.amount),
    currency: "XOF",
    description: args.description,
    success_url: args.successUrl,
    error_url: args.errorUrl,
    customer,
    metadata: flattenMetadata({
      ...args.metadata,
      feeModel: args.metadata.feeModel ?? "additive",
      tibusPaymentNetwork: network,
      tibusPaymentCountry: countryCode,
      passengerPhone: phone ? normalizeGeniusPayPhone(phone) : "",
    }),
  };

  const res = await fetch(`${GENIUSPAY_BASE}/payments`, {
    method: "POST",
    headers: apiHeaders(),
    body: JSON.stringify(body),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(formatGeniusPayError(text));
  }

  let json: Record<string, unknown>;
  try {
    json = JSON.parse(text) as Record<string, unknown>;
  } catch {
    throw new Error(
      "GeniusPay a renvoyé une réponse invalide (HTML). Réessayez ou choisissez un autre réseau.",
    );
  }
  const data = json.data as {
    reference?: string;
    id?: number;
    checkout_url?: string;
    payment_url?: string;
    gateway?: string;
    payment_method?: string;
  } | undefined;

  const hostedCheckout = data?.checkout_url?.trim();
  const paymentUrl = data?.payment_url?.trim();
  const redirectUrl =
    (hostedCheckout && isGeniusPayHostedUrl(hostedCheckout) ? hostedCheckout : undefined) ??
    (paymentUrl && isGeniusPayHostedUrl(paymentUrl) ? paymentUrl : undefined);

  if (!redirectUrl || !data?.reference) {
    const external = paymentUrl && !isGeniusPayHostedUrl(paymentUrl)
      ? ` (URL opérateur reçue: ${paymentUrl.slice(0, 80)}…)`
      : "";
    throw new Error(
      `GeniusPay n'a pas fourni de page checkout hébergée${external}. Réessayez.`,
    );
  }

  return {
    checkoutUrl: redirectUrl,
    reference: data.reference,
    transactionId: String(data.id ?? data.reference),
    gateway: data.gateway,
    paymentMethod: data.payment_method,
  };
}

export async function fetchGeniusPayPayment(
  reference: string,
): Promise<GeniusPayPayment | null> {
  const res = await fetch(
    `${GENIUSPAY_BASE}/payments/${encodeURIComponent(reference)}`,
    { headers: apiHeaders() },
  );
  const text = await res.text();
  if (!res.ok) return null;
  try {
    const json = JSON.parse(text) as Record<string, unknown>;
    return parsePayment(json);
  } catch {
    return null;
  }
}

export function isGeniusPayApproved(status?: string) {
  return status === "completed" || status === "success";
}

export async function verifyGeniusPayWebhookSignature(
  req: Request,
  rawBody: string,
): Promise<boolean> {
  const secret = Deno.env.get("GENIUSPAY_WEBHOOK_SECRET");
  if (!secret) return true;

  const signature = req.headers.get("X-Webhook-Signature");
  const timestamp = req.headers.get("X-Webhook-Timestamp");
  if (!signature || !timestamp) return false;

  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(Math.floor(Date.now() / 1000) - ts) > 300) {
    return false;
  }

  const data = `${timestamp}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data),
  );
  const expected = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return expected === signature.toLowerCase();
}
