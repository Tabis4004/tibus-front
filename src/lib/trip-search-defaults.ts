import type { CountryRow } from "@/lib/supabase/geography";

const BURKINA_COUNTRY_PATTERN = /burkina/i;
const COTE_IVOIRE_COUNTRY_PATTERN = /côte|cote|ivoire|ivory/i;

export function findBurkinaCountryId(
  countries: readonly Pick<CountryRow, "_id" | "name">[],
): string | null {
  return countries.find((country) => BURKINA_COUNTRY_PATTERN.test(country.name))?._id ?? null;
}

/** Pays avec données démo / gares cartographiées (landing Tibus). */
export function findCoteDIvoireCountryId(
  countries: readonly Pick<CountryRow, "_id" | "name">[],
): string | null {
  return countries.find((country) => COTE_IVOIRE_COUNTRY_PATTERN.test(country.name))?._id ?? null;
}

export function resolveLandingCountryDefault(
  countries: readonly Pick<CountryRow, "_id" | "name">[],
  embedded: boolean,
): string {
  if (!embedded) {
    return findBurkinaCountryId(countries) ?? "all";
  }
  return findCoteDIvoireCountryId(countries) ?? "all";
}
