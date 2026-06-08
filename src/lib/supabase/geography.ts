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
