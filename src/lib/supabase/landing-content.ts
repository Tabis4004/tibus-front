import { supabase } from "@/lib/supabase";

// CMS "Landing Page" — migré de Convex vers Supabase (voir migration
// 161_landing_content_supabase). Même forme clé/valeur que l'ancien Convex
// landingContent : une ligne par section, contenu stocké en JSON string.
// Lecture publique (page d'accueil non authentifiée), écriture super_admin.

export type LandingContentMap = Record<string, string>;

export type LandingLiveStats = {
  companies: number;
  trips: number;
  travelers: number;
  cities: number;
};

export async function getAllLandingContentSupabase(): Promise<LandingContentMap> {
  const { data, error } = await supabase.rpc("get_all_landing_content");
  if (error) throw error;
  return (data as LandingContentMap | null) ?? {};
}

export async function getLandingLiveStatsSupabase(): Promise<LandingLiveStats> {
  const { data, error } = await supabase.rpc("get_landing_live_stats");
  if (error) throw error;
  const row = (data as Partial<LandingLiveStats> | null) ?? {};
  return {
    companies: Number(row.companies ?? 0),
    trips: Number(row.trips ?? 0),
    travelers: Number(row.travelers ?? 0),
    cities: Number(row.cities ?? 0),
  };
}

export async function upsertLandingContentSupabase(
  section: string,
  content: string,
): Promise<void> {
  const { error } = await supabase.rpc("upsert_landing_content", {
    p_section: section,
    p_content: content,
  });
  if (error) throw error;
}
