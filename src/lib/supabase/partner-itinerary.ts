import { supabase } from "@/lib/supabase";
import { resolveOwnerCompanyId } from "@/lib/supabase/owner-company";

export type PartnerApiKeyRow = {
  id: string;
  name: string;
  externalSystem: string;
  keyPrefix: string;
  isActive: boolean;
  createdAt: string;
  lastUsedAt: string | null;
};

export type PartnerGareMappingRow = {
  id: string;
  externalGareId: string;
  gareId: string;
  externalName: string | null;
  createdAt: string;
};

export type CreatedPartnerApiKey = {
  id: string;
  apiKey: string;
  keyPrefix: string;
  externalSystem: string;
};

export type PartnerWebhookRow = {
  id: string;
  url: string;
  externalSystem: string;
  events: string[];
  isActive: boolean;
  createdAt: string;
};

export type CreatedPartnerWebhook = {
  id: string;
  url: string;
  secret: string;
  events: string[];
  externalSystem: string;
};

export type PartnerWebhookDeliveryRow = {
  id: string;
  eventType: string;
  responseStatus: number | null;
  deliveredAt: string;
  endpointUrl: string;
};

export function partnerItineraryApiBaseUrl(): string {
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
  if (!supabaseUrl) return "";
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/partner-itinerary-api`;
}

export async function createPartnerApiKeySupabase(input: {
  appUserId: string;
  companyId?: string | null;
  name: string;
  externalSystem?: string;
}): Promise<CreatedPartnerApiKey> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const { data, error } = await supabase.rpc("create_partner_api_key", {
    p_name: input.name.trim(),
    p_external_system: input.externalSystem?.trim() || "default",
    p_company_id: companyId,
  });

  if (error) throw error;

  const row = Array.isArray(data) ? data[0] : null;
  if (!row?.api_key) throw new Error("Création de clé API impossible");

  return {
    id: row.id as string,
    apiKey: row.api_key as string,
    keyPrefix: row.key_prefix as string,
    externalSystem: row.external_system as string,
  };
}

export async function listPartnerApiKeysSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<PartnerApiKeyRow[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("PartnerApiKeys")
    .select("id, name, externalSystem, keyPrefix, isActive, createdAt, lastUsedAt")
    .eq("companyId", resolvedCompanyId)
    .order("createdAt", { ascending: false });

  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id as string,
    name: row.name as string,
    externalSystem: row.externalSystem as string,
    keyPrefix: row.keyPrefix as string,
    isActive: row.isActive as boolean,
    createdAt: row.createdAt as string,
    lastUsedAt: (row.lastUsedAt as string | null) ?? null,
  }));
}

export async function listPartnerGareMappingsSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<PartnerGareMappingRow[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("PartnerGareMappings")
    .select("id, externalGareId, gareId, externalName, createdAt")
    .eq("companyId", resolvedCompanyId)
    .order("createdAt", { ascending: false });

  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id as string,
    externalGareId: row.externalGareId as string,
    gareId: row.gareId as string,
    externalName: (row.externalName as string | null) ?? null,
    createdAt: row.createdAt as string,
  }));
}

export async function createPartnerWebhookSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  url: string;
  externalSystem?: string;
  events?: string[];
}): Promise<CreatedPartnerWebhook> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const { data, error } = await supabase.rpc("partner_upsert_webhook_endpoint", {
    p_company_id: companyId,
    p_external_system: input.externalSystem?.trim() || "default",
    p_url: input.url.trim(),
    p_events: input.events ?? ["booking.created", "booking.confirmed", "booking.cancelled"],
    p_endpoint_id: null,
  });

  if (error) throw error;

  const row = Array.isArray(data) ? data[0] : null;
  if (!row?.secret) throw new Error("Création webhook impossible");

  return {
    id: row.id as string,
    url: row.url as string,
    secret: row.secret as string,
    events: (row.events as string[]) ?? [],
    externalSystem: row.external_system as string,
  };
}

export async function listPartnerWebhooksSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<PartnerWebhookRow[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("PartnerWebhookEndpoints")
    .select("id, url, externalSystem, events, isActive, createdAt")
    .eq("companyId", resolvedCompanyId)
    .order("createdAt", { ascending: false });

  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id as string,
    url: row.url as string,
    externalSystem: row.externalSystem as string,
    events: (row.events as string[]) ?? [],
    isActive: row.isActive as boolean,
    createdAt: row.createdAt as string,
  }));
}

export async function listPartnerWebhookDeliveriesSupabase(
  appUserId: string,
  companyId?: string | null,
  limit = 30,
): Promise<PartnerWebhookDeliveryRow[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase.rpc("partner_list_webhook_deliveries", {
    p_company_id: resolvedCompanyId,
    p_limit: limit,
  });

  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id as string,
    eventType: row.event_type as string,
    responseStatus: (row.response_status as number | null) ?? null,
    deliveredAt: row.delivered_at as string,
    endpointUrl: row.endpoint_url as string,
  }));
}
