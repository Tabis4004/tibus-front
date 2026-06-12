import { createAdminClient } from "./issue-ticket.ts";

export type PartnerWebhookEvent =
  | "departure.synced"
  | "booking.created"
  | "booking.confirmed"
  | "booking.cancelled";

export async function dispatchPartnerWebhooks(input: {
  companyId: string;
  externalSystem: string;
  eventType: PartnerWebhookEvent;
  payload: Record<string, unknown>;
}) {
  const admin = createAdminClient();

  const { data: endpoints, error } = await admin
    .from("PartnerWebhookEndpoints")
    .select("id, url, secret, events")
    .eq("companyId", input.companyId)
    .eq("externalSystem", input.externalSystem)
    .eq("isActive", true);

  if (error || !endpoints?.length) return;

  const body = JSON.stringify({
    id: crypto.randomUUID(),
    type: input.eventType,
    createdAt: new Date().toISOString(),
    data: input.payload,
  });

  for (const endpoint of endpoints) {
    const events = (endpoint.events as string[] | null) ?? [];
    if (!events.includes(input.eventType)) continue;

    const secret = endpoint.secret as string;
    const signature = await signWebhookPayload(secret, body);

    let responseStatus: number | null = null;
    let responseBody: string | null = null;

    try {
      const response = await fetch(endpoint.url as string, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Tibus-Event": input.eventType,
          "X-Tibus-Signature": signature,
          "X-Tibus-Delivery": crypto.randomUUID(),
        },
        body,
      });
      responseStatus = response.status;
      responseBody = (await response.text()).slice(0, 2000);
    } catch (err) {
      responseStatus = 0;
      responseBody = err instanceof Error ? err.message : "fetch failed";
    }

    await admin.from("PartnerWebhookDeliveries").insert({
      endpointId: endpoint.id as string,
      eventType: input.eventType,
      payload: JSON.parse(body),
      responseStatus,
      responseBody,
    });
  }
}

async function signWebhookPayload(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );
  const bytes = new Uint8Array(signature);
  return `sha256=${[...bytes].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}
