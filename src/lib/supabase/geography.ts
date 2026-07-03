import { supabase } from "@/lib/supabase";

export type CountryRow = { _id: string; name: string; currency: string | null };
export type CityRow = { _id: string; name: string; countryId: string };

export async function listCountriesSupabase(): Promise<CountryRow[]> {
  const { data, error } = await supabase
    .from("Countries")
    .select("id, name, currency")
    .order("name");

  if (error) throw error;

  return (data ?? []).map((row) => ({
    _id: row.id as string,
    name: row.name as string,
    currency: row.currency as string | null,
  }));
}

export async function listCitiesSupabase(
  countryId?: string,
): Promise<CityRow[]> {
  let query = supabase.from("Cities").select("id, name, countryId").order("name");

  if (countryId) {
    query = query.eq("countryId", countryId);
  }

  const { data, error } = await query;
  if (error) throw error;

  return (data ?? []).map((row) => ({
    _id: row.id as string,
    name: row.name as string,
    countryId: row.countryId as string,
  }));
}

export async function getCityCountryIdSupabase(cityId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from("Cities")
    .select("countryId")
    .eq("id", cityId)
    .maybeSingle();
  if (error) throw error;
  return (data?.countryId as string | undefined) ?? null;
}

// Pays où une compagnie peut créer des gares : son pays d'origine + tout
// pays autorisé par un super_admin via CompanyOperatingCountries
// (itinéraires transfrontaliers). Voir admin_grant_company_operating_country.
export async function listCompanyAvailableCountriesSupabase(
  companyId: string,
): Promise<CountryRow[]> {
  const { data, error } = await supabase.rpc("list_company_available_countries", {
    p_company_id: companyId,
  });
  if (error) throw error;

  return ((data ?? []) as { countryId: string; countryName: string }[]).map((row) => ({
    _id: row.countryId,
    name: row.countryName,
    currency: null,
  }));
}
