import { supabase } from "@/lib/supabase";
import { isGoogleMapsLink, parseGoogleMapsCoordinates } from "@/lib/google-maps-link.ts";

export type GareMapPoint = {
  id: string;
  name: string;
  companyName: string;
  googleMapsLink: string;
  lat: number | null;
  lng: number | null;
};

function companyNameFromJoin(
  value: { name: string } | { name: string }[] | null | undefined,
): string {
  if (!value) return "";
  if (Array.isArray(value)) return value[0]?.name ?? "";
  return value.name ?? "";
}

export async function listGaresMapPointsSupabase(): Promise<GareMapPoint[]> {
  const { data, error } = await supabase
    .from("Gares")
    .select("id, name, googleMapsLink, Companies(name)")
    .not("googleMapsLink", "is", null)
    .order("name");

  if (error) throw error;

  return (data ?? [])
    .map((row) => {
      const link = String(row.googleMapsLink ?? "").trim();
      if (!isGoogleMapsLink(link)) return null;
      const coords = parseGoogleMapsCoordinates(link);
      return {
        id: String(row.id),
        name: String(row.name),
        companyName: companyNameFromJoin(
          row.Companies as { name: string } | { name: string }[] | null,
        ),
        googleMapsLink: link,
        lat: coords?.lat ?? null,
        lng: coords?.lng ?? null,
      };
    })
    .filter((row): row is GareMapPoint => Boolean(row));
}
