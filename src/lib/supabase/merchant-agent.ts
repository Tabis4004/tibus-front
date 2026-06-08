import { refreshAppUser } from "@/hooks/use-app-user";
import { supabase } from "@/lib/supabase";

export type MerchantAgentCountry = {
  id: string;
  name: string;
};

export type MerchantAgentCity = {
  id: string;
  name: string;
  countryId: string;
};

export type MerchantAgentApplicationInput = {
  commercialName: string;
  fullName: string;
  phone: string;
  email?: string;
  countryId: string;
  countryName?: string;
  cityId: string;
  city: string;
  physicalAddress: string;
  googleMapsUrl: string;
};

export async function listMerchantAgentCountries(): Promise<MerchantAgentCountry[]> {
  const { data, error } = await supabase
    .from("Countries")
    .select("id, name")
    .order("name");

  if (error) throw error;

  return (data ?? []).map((country) => ({
    id: country.id as string,
    name: country.name as string,
  }));
}

export async function listMerchantAgentCities(
  countryId: string,
): Promise<MerchantAgentCity[]> {
  const { data, error } = await supabase
    .from("Cities")
    .select("id, name, countryId")
    .eq("countryId", countryId)
    .order("name");

  if (error) throw error;

  return (data ?? []).map((city) => ({
    id: city.id as string,
    name: city.name as string,
    countryId: city.countryId as string,
  }));
}

export async function getMyMerchantAgentApplication(appUserId: string) {
  const { data, error } = await supabase
    .from("MerchantAgentApplications")
    .select("id, status, commercialName, createdAt")
    .eq("createdBy", appUserId)
    .order("createdAt", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  return data;
}

export async function submitMerchantAgentApplication(
  input: MerchantAgentApplicationInput,
): Promise<string> {
  const { data, error } = await supabase.rpc("submit_merchant_agent_application", {
    p_commercial_name: input.commercialName.trim(),
    p_full_name: input.fullName.trim(),
    p_phone: input.phone.trim(),
    p_email: input.email?.trim() || null,
    p_country_id: input.countryId,
    p_country_name: input.countryName?.trim() || null,
    p_city_id: input.cityId,
    p_city: input.city.trim(),
    p_physical_address: input.physicalAddress.trim(),
    p_google_maps_url: input.googleMapsUrl.trim(),
  });

  if (error) throw error;
  refreshAppUser();
  return data as string;
}
