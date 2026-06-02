import type { QueryCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel.d.ts";

export type ResolvedLocation = {
  city: string;
  country: string;
  latitude?: number;
  longitude?: number;
};

/**
 * Resolve city, country, and geolocation for a station, supporting both
 * the new cityId field and the legacy locationId field.
 */
export async function resolveStationLocation(
  ctx: QueryCtx,
  station: Doc<"stations"> | null,
): Promise<ResolvedLocation | null> {
  if (!station) return null;

  const base: Pick<ResolvedLocation, "latitude" | "longitude"> = {
    latitude: station.latitude,
    longitude: station.longitude,
  };

  if (station.cityId) {
    const city = await ctx.db.get(station.cityId);
    if (city) {
      const country = await ctx.db.get(city.countryId);
      return { city: city.name, country: country?.name ?? "", ...base };
    }
  }

  if (station.locationId) {
    const loc = await ctx.db.get(station.locationId);
    if (loc) {
      return { city: loc.city, country: loc.country, ...base };
    }
  }

  return null;
}
