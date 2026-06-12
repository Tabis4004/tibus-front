import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  isGoogleMapsLink,
  parseGoogleMapsCoordinates,
  resolveGoogleMapsLinkCoordinates,
} from "../_shared/google-maps-resolve.ts";

type ResolveRequest = {
  links?: string[];
};

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

  const links = Array.isArray(body.links) ? body.links : [];
  if (!links.length) {
    return jsonResponse({ results: [] });
  }

  const uniqueLinks = [...new Set(links.map((link) => String(link ?? "").trim()).filter(Boolean))].slice(
    0,
    25,
  );

  const results = [];
  for (const link of uniqueLinks) {
    if (!isGoogleMapsLink(link)) {
      results.push({ link, lat: null, lng: null, expandedUrl: null });
      continue;
    }

    const direct = parseGoogleMapsCoordinates(link);
    if (direct) {
      results.push({ link, lat: direct.lat, lng: direct.lng, expandedUrl: link });
      continue;
    }

    const resolved = await resolveGoogleMapsLinkCoordinates(link);
    results.push({
      link,
      lat: resolved?.lat ?? null,
      lng: resolved?.lng ?? null,
      expandedUrl: resolved?.expandedUrl ?? null,
    });
  }

  return jsonResponse({ results });
});
