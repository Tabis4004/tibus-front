import type { CountryRow } from "@/lib/supabase/geography";

const BURKINA_COUNTRY_PATTERN = /burkina/i;

export function findBurkinaCountryId(
  countries: readonly Pick<CountryRow, "_id" | "name">[],
): string | null {
  return countries.find((country) => BURKINA_COUNTRY_PATTERN.test(country.name))?._id ?? null;
}
