import { supabase } from "@/lib/supabase";
import type { CommercialOfferDocument } from "@/data/commercial-offer-content.ts";

export async function getCommercialOfferCustomizationSupabase(
  countryId: string,
  locale: string,
): Promise<CommercialOfferDocument | null> {
  const { data, error } = await supabase.rpc("get_commercial_offer_customization", {
    p_country_id: countryId,
    p_locale: locale,
  });
  if (error) throw error;
  if (!data || typeof data !== "object") return null;
  return data as CommercialOfferDocument;
}

export async function upsertCommercialOfferCustomizationSupabase(input: {
  countryId: string;
  locale: string;
  document: CommercialOfferDocument;
}): Promise<string> {
  const { data, error } = await supabase.rpc("upsert_commercial_offer_customization", {
    p_country_id: input.countryId,
    p_locale: input.locale,
    p_document: input.document,
  });
  if (error) throw error;
  return String(data);
}

export async function deleteCommercialOfferCustomizationSupabase(
  countryId: string,
  locale: string,
): Promise<void> {
  const { error } = await supabase.rpc("delete_commercial_offer_customization", {
    p_country_id: countryId,
    p_locale: locale,
  });
  if (error) throw error;
}

export async function resolveAdminPaysCountryIdSupabase(userId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from("UserRoles")
    .select("countryId, Role(name)")
    .eq("userId", userId);

  if (error) throw error;

  const row = (data ?? []).find((entry) => {
    const role = Array.isArray(entry.Role) ? entry.Role[0] : entry.Role;
    return (role as { name?: string } | null)?.name === "admin_pays";
  });

  return (row?.countryId as string | null) ?? null;
}
