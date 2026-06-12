/** Même URL pour sandbox et live — le mode dépend des clés pk_live_/sk_live_ vs pk_sandbox_/sk_sandbox_. */
const GENIUSPAY_BASE =
  Deno.env.get("GENIUSPAY_BASE_URL") ?? "https://pay.genius.ci/api/v1/merchant";

export type GeniusPayPayment = {
  id?: number;
  reference?: string;
  status?: string;
  metadata?: Record<string, string>;
};

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

/** Téléphone international (+225…) pour GeniusPay / PawaPay */
export function normalizeGeniusPayPhone(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  if (!digits) {
    throw new Error(
      "Numéro de téléphone requis — format: 07 00 00 00 00 ou +225 07...",
    );
  }

  if (raw.trim().startsWith("+")) {
    return `+${digits}`;
  }

  let local = digits;
  if (local.startsWith("225") && local.length >= 12) {
    return `+${local}`;
  }
  if (local.length === 9 && /^[1-9]/.test(local)) {
    local = `0${local}`;
  }
  if (!/^0[1-9]\d{8}$/.test(local)) {
    throw new Error(
      "Numéro invalide — utilisez 10 chiffres ivoiriens (ex: 07 00 00 00 00)",
    );
  }
  return `+225${local.slice(1)}`;
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

export function mapNetworkToGeniusPayMmo(
  network?: string,
): { payment_method?: string; gateway?: string; mmo_provider?: string } {
  switch ((network ?? "unknown").toLowerCase()) {
    case "orange":
      return { payment_method: "orange_money", gateway: "orange_money" };
    case "mtn":
      return { payment_method: "mtn_money", gateway: "mtn_momo" };
    case "moov":
      return { payment_method: "pawapay", mmo_provider: "MOOV_CIV" };
    case "wave":
      return { payment_method: "wave", gateway: "wave" };
    default:
      return {};
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
    phone: string;
    country?: string;
  };
  metadata: Record<string, string>;
  paymentNetwork?: string;
}) {
  const phone = normalizeGeniusPayPhone(args.customer.phone);
  const routing = mapNetworkToGeniusPayMmo(args.paymentNetwork);

  const body: Record<string, unknown> = {
    amount: Math.ceil(args.amount),
    currency: "XOF",
    description: args.description,
    success_url: args.successUrl,
    error_url: args.errorUrl,
    customer: {
      name: args.customer.name,
      email: args.customer.email,
      phone,
      country: args.customer.country ?? "CI",
    },
    metadata: flattenMetadata(args.metadata),
  };

  if (routing.payment_method) {
    body.payment_method = routing.payment_method;
    if (routing.gateway) body.gateway = routing.gateway;
    if (routing.mmo_provider) body.mmo_provider = routing.mmo_provider;
  }

  const res = await fetch(`${GENIUSPAY_BASE}/payments`, {
    method: "POST",
    headers: apiHeaders(),
    body: JSON.stringify(body),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`GeniusPay payment failed: ${text.slice(0, 400)}`);
  }

  const json = JSON.parse(text) as Record<string, unknown>;
  const data = json.data as {
    reference?: string;
    id?: number;
    checkout_url?: string;
    payment_url?: string;
  } | undefined;

  const checkoutUrl = data?.checkout_url ?? data?.payment_url;
  if (!checkoutUrl || !data?.reference) {
    throw new Error(`GeniusPay checkout invalide: ${text.slice(0, 400)}`);
  }

  return {
    checkoutUrl,
    reference: data.reference,
    transactionId: String(data.id ?? data.reference),
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
