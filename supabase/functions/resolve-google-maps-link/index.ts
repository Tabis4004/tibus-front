import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  geocodeStationNominatim,
  isGoogleMapsLink,
  parseGoogleMapsCoordinates,
  resolveGoogleMapsLinkCoordinates,
} from "../_shared/google-maps-resolve.ts";

type StationInput = {
  link?: string;
  name?: string;
  city?: string;
  country?: string;
};

type ResolveRequest = {
  links?: string[];
  stations?: StationInput[];
};

type ResolveResult = {
  link: string;
  lat: number | null;
  lng: number | null;
  expandedUrl: string | null;
  source: "google_maps_link" | "nominatim" | null;
};

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function resolveStation(input: StationInput): Promise<ResolveResult> {
  const link = String(input.link ?? "").trim();
  if (!link || !isGoogleMapsLink(link)) {
    return { link, lat: null, lng: null, expandedUrl: null, source: null };
  }

  const direct = parseGoogleMapsCoordinates(link);
  if (direct) {
    return { link, lat: direct.lat, lng: direct.lng, expandedUrl: link, source: "google_maps_link" };
  }

  const resolved = await resolveGoogleMapsLinkCoordinates(link);
  if (resolved) {
    return {
      link,
      lat: resolved.lat,
      lng: resolved.lng,
      expandedUrl: resolved.expandedUrl ?? null,
      source: "google_maps_link",
    };
  }

  const nominatim = await geocodeStationNominatim({
    name: input.name ?? link,
    city: input.city,
    country: input.country,
  });

  if (nominatim) {
    return {
      link,
      lat: nominatim.lat,
      lng: nominatim.lng,
      expandedUrl: null,
      source: "nominatim",
    };
  }

  return { link, lat: null, lng: null, expandedUrl: null, source: null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let body: ResolveRequest;
  try {
    body = (await req.json()) as ResolveRequest;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const stations: StationInput[] = Array.isArray(body.stations) && body.stations.length
    ? body.stations
    : (Array.isArray(body.links) ? body.links : []).map((link) => ({ link }));

  if (!stations.length) {
    return jsonResponse({ results: [] });
  }

  const limited = stations.slice(0, 25);
  const results: ResolveResult[] = [];

  for (const station of limited) {
    results.push(await resolveStation(station));
    await sleep(200);
  }

  return jsonResponse({ results });
});
