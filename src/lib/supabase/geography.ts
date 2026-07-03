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

// ─── CRUD admin (super_admin ou droit manage_country — RLS côté DB) ─────────

export type AdminCityRow = {
  _id: string;
  name: string;
  countryId: string;
  countryName: string | null;
};

function joinedCountryName(
  value: { name: string } | { name: string }[] | null,
): string | null {
  if (!value) return null;
  return Array.isArray(value) ? (value[0]?.name ?? null) : value.name;
}

// Recherche paginée côté serveur (la table Cities dépasse la limite de
// 1000 lignes par requête de Supabase).
export async function adminSearchCitiesSupabase(opts: {
  countryId?: string | null;
  search?: string;
  limit?: number;
}): Promise<{ rows: AdminCityRow[]; total: number }> {
  let query = supabase
    .from("Cities")
    .select("id, name, countryId, Countries(name)", { count: "exact" })
    .order("name")
    .limit(opts.limit ?? 100);

  if (opts.countryId) query = query.eq("countryId", opts.countryId);
  const search = opts.search?.trim();
  if (search) query = query.ilike("name", `%${search}%`);

  const { data, error, count } = await query;
  if (error) throw error;

  return {
    rows: (data ?? []).map((row) => ({
      _id: row.id as string,
      name: row.name as string,
      countryId: row.countryId as string,
      countryName: joinedCountryName(
        row.Countries as { name: string } | { name: string }[] | null,
      ),
    })),
    total: count ?? 0,
  };
}

export async function createCountrySupabase(input: {
  name: string;
  currency?: string | null;
}): Promise<void> {
  const { error } = await supabase.from("Countries").insert({
    name: input.name.trim(),
    currency: input.currency?.trim() || null,
  });
  if (error) throw error;
}

export async function updateCountrySupabase(
  countryId: string,
  input: { name: string; currency?: string | null },
): Promise<void> {
  const { data, error } = await supabase
    .from("Countries")
    .update({ name: input.name.trim(), currency: input.currency?.trim() || null })
    .eq("id", countryId)
    .select("id");
  if (error) throw error;
  if (!data?.length) throw new Error("Modification refusée (droits insuffisants).");
}

export async function deleteCountrySupabase(countryId: string): Promise<void> {
  const { error } = await supabase.from("Countries").delete().eq("id", countryId);
  if (error) throw error;
}

export async function createCitySupabase(input: {
  name: string;
  countryId: string;
}): Promise<void> {
  const { error } = await supabase.from("Cities").insert({
    name: input.name.trim(),
    countryId: input.countryId,
  });
  if (error) throw error;
}

export async function updateCitySupabase(
  cityId: string,
  input: { name: string; countryId: string },
): Promise<void> {
  const { data, error } = await supabase
    .from("Cities")
    .update({ name: input.name.trim(), countryId: input.countryId })
    .eq("id", cityId)
    .select("id");
  if (error) throw error;
  if (!data?.length) throw new Error("Modification refusée (droits insuffisants).");
}

export async function deleteCitySupabase(cityId: string): Promise<void> {
  const { error } = await supabase.from("Cities").delete().eq("id", cityId);
  if (error) throw error;
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

// Normalisation côté client pour l'autocomplete ville : minuscules + sans
// accents, afin que « Bohìcon », « BOHICON » et « bohicon » se retrouvent.
export function normalizeCityName(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

// Trouve une ville (insensible casse/accents) ou la crée pour le pays donné.
// Réservé aux owners avec le droit manage_stations (ou super admin) via la
// RPC find_or_create_city. La ville créée est partagée entre compagnies.
export async function findOrCreateCitySupabase(
  companyId: string,
  countryId: string,
  name: string,
): Promise<{ id: string; name: string; created: boolean }> {
  const { data, error } = await supabase.rpc("find_or_create_city", {
    p_company_id: companyId,
    p_country_id: countryId,
    p_name: name,
  });
  if (error) throw error;
  const row = ((data ?? []) as { cityId: string; cityName: string; created: boolean }[])[0];
  if (!row) throw new Error("Création de la ville impossible.");
  return { id: row.cityId, name: row.cityName, created: row.created };
}

// Vérification externe (OpenStreetMap Nominatim, sans clé API) qu'une ville
// existe réellement dans le pays donné. Renvoie false en cas de doute ou
// d'erreur réseau — l'appelant décide alors d'avertir sans bloquer.
export async function verifyCityExistsExternally(
  cityName: string,
  countryName: string | null,
): Promise<boolean> {
  try {
    const params = new URLSearchParams({
      city: cityName,
      format: "jsonv2",
      limit: "1",
      "accept-language": "fr",
    });
    if (countryName) params.set("country", countryName);
    const res = await fetch(
      `https://nominatim.openstreetmap.org/search?${params.toString()}`,
      { headers: { Accept: "application/json" } },
    );
    if (!res.ok) return false;
    const results = (await res.json()) as unknown[];
    return Array.isArray(results) && results.length > 0;
  } catch {
    return false;
  }
}

// Super admin uniquement : autorise une compagnie à opérer (créer des gares)
// dans un pays autre que son pays d'origine.
export async function adminGrantCompanyOperatingCountrySupabase(
  companyId: string,
  countryId: string,
): Promise<void> {
  const { error } = await supabase.rpc("admin_grant_company_operating_country", {
    p_company_id: companyId,
    p_country_id: countryId,
  });
  if (error) throw error;
}

// Super admin uniquement : révoque l'autorisation d'opérer dans un pays.
export async function adminRevokeCompanyOperatingCountrySupabase(
  companyId: string,
  countryId: string,
): Promise<void> {
  const { error } = await supabase.rpc("admin_revoke_company_operating_country", {
    p_company_id: companyId,
    p_country_id: countryId,
  });
  if (error) throw error;
}
