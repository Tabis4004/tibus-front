import { supabase } from "@/lib/supabase";

export type CompanyRow = { _id: string; name: string; countryId: string };

export async function listActiveCompaniesSupabase(): Promise<CompanyRow[]> {
  const { data, error } = await supabase
    .from("Companies")
    .select("id, name, countryId")
    .eq("isActive", true)
    .order("name");

  if (error) throw error;

  return (data ?? []).map((row) => ({
    _id: row.id as string,
    name: row.name as string,
    countryId: row.countryId as string,
  }));
}
