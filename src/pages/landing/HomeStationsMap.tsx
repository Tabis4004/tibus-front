import { useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { ExternalLinkIcon, MapPinIcon } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { listGaresMapPointsSupabase, type GareMapPoint } from "@/lib/supabase/gares-map.ts";

type GoogleLatLng = { lat: number; lng: number };
type GoogleMapInstance = {
  fitBounds: (bounds: unknown, padding?: number) => void;
  setCenter: (center: GoogleLatLng) => void;
  setZoom: (zoom: number) => void;
};
type GoogleMarkerInstance = {
  setMap: (map: GoogleMapInstance | null) => void;
  addListener: (eventName: string, handler: () => void) => void;
};
type GoogleInfoWindow = {
  setContent: (content: string) => void;
  open: (options: { map: GoogleMapInstance; anchor?: GoogleMarkerInstance }) => void;
};
type GoogleMapsApi = {
  Map: new (
    element: HTMLElement,
    options: { center: GoogleLatLng; zoom: number; mapTypeControl?: boolean; streetViewControl?: boolean; fullscreenControl?: boolean },
  ) => GoogleMapInstance;
  Marker: new (options: {
    map: GoogleMapInstance;
    position: GoogleLatLng;
    title?: string;
  }) => GoogleMarkerInstance;
  InfoWindow: new () => GoogleInfoWindow;
  LatLngBounds: new () => { extend: (position: GoogleLatLng) => void };
  event: {
    trigger: (map: GoogleMapInstance, eventName: string) => void;
    addListener: (instance: GoogleMarkerInstance, eventName: string, handler: () => void) => void;
  };
};

declare global {
  interface Window {
    google?: { maps: GoogleMapsApi };
  }
}

const DEFAULT_CENTER: GoogleLatLng = { lat: 12.3714, lng: -1.5197 };
const MAPS_SCRIPT_ID = "tibus-google-maps-script";

function loadGoogleMapsScript(apiKey: string): Promise<GoogleMapsApi> {
  if (window.google?.maps) {
    return Promise.resolve(window.google.maps);
  }

  const existing = document.getElementById(MAPS_SCRIPT_ID) as HTMLScriptElement | null;
  if (existing) {
    return new Promise((resolve, reject) => {
      existing.addEventListener("load", () => {
        if (window.google?.maps) resolve(window.google.maps);
        else reject(new Error("Google Maps indisponible"));
      });
      existing.addEventListener("error", () => reject(new Error("Chargement Google Maps impossible")));
    });
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.id = MAPS_SCRIPT_ID;
    script.async = true;
    script.defer = true;
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}&loading=async`;
    script.onload = () => {
      if (window.google?.maps) resolve(window.google.maps);
      else reject(new Error("Google Maps indisponible"));
    };
    script.onerror = () => reject(new Error("Chargement Google Maps impossible"));
    document.head.appendChild(script);
  });
}

function buildInfoContent(gare: GareMapPoint) {
  const company = gare.companyName ? `<p style="margin:4px 0 0;font-size:12px;color:#666">${gare.companyName}</p>` : "";
  return `<div style="max-width:220px;font-family:sans-serif">
    <strong>${gare.name}</strong>
    ${company}
    <p style="margin:8px 0 0"><a href="${gare.googleMapsLink}" target="_blank" rel="noopener noreferrer">Ouvrir dans Google Maps</a></p>
  </div>`;
}

export default function HomeStationsMap() {
  const { t } = useTranslation("common");
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const [gares, setGares] = useState<GareMapPoint[] | undefined>(undefined);
  const [mapError, setMapError] = useState<string | null>(null);
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined;

  useEffect(() => {
    let cancelled = false;
    void listGaresMapPointsSupabase()
      .then((rows) => {
        if (!cancelled) setGares(rows);
      })
      .catch(() => {
        if (!cancelled) setGares([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const mappableGares = useMemo(
    () => (gares ?? []).filter((gare) => gare.lat != null && gare.lng != null),
    [gares],
  );

  const embedCenter = useMemo(() => {
    if (!mappableGares.length) return DEFAULT_CENTER;
    const lat =
      mappableGares.reduce((sum, gare) => sum + (gare.lat as number), 0) / mappableGares.length;
    const lng =
      mappableGares.reduce((sum, gare) => sum + (gare.lng as number), 0) / mappableGares.length;
    return { lat, lng };
  }, [mappableGares]);

  useEffect(() => {
    if (!apiKey || !mapContainerRef.current || mappableGares.length === 0) return;

    let markers: GoogleMarkerInstance[] = [];
    let map: GoogleMapInstance | null = null;
    let cancelled = false;

    void loadGoogleMapsScript(apiKey)
      .then((maps) => {
        if (cancelled || !mapContainerRef.current) return;

        const activeMap = new maps.Map(mapContainerRef.current, {
          center: DEFAULT_CENTER,
          zoom: 6,
          mapTypeControl: false,
          streetViewControl: false,
          fullscreenControl: true,
        });
        map = activeMap;

        const bounds = new maps.LatLngBounds();
        const infoWindow = new maps.InfoWindow();

        for (const gare of mappableGares) {
          const position = { lat: gare.lat as number, lng: gare.lng as number };
          const marker = new maps.Marker({
            map: activeMap,
            position,
            title: gare.name,
          });
          const openInfo = () => {
            infoWindow.setContent(buildInfoContent(gare));
            infoWindow.open({ map: activeMap, anchor: marker });
          };
          if (typeof marker.addListener === "function") {
            marker.addListener("click", openInfo);
          } else {
            maps.event.addListener(marker, "click", openInfo);
          }
          markers.push(marker);
          bounds.extend(position);
        }

        if (mappableGares.length === 1) {
          activeMap.setCenter({ lat: mappableGares[0].lat as number, lng: mappableGares[0].lng as number });
          activeMap.setZoom(13);
        } else {
          activeMap.fitBounds(bounds, 48);
          maps.event.trigger(activeMap, "resize");
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setMapError(err instanceof Error ? err.message : "Carte indisponible");
        }
      });

    return () => {
      cancelled = true;
      for (const marker of markers) marker.setMap(null);
      markers = [];
      map = null;
    };
  }, [apiKey, mappableGares]);

  if (gares === undefined) {
    return (
      <section className="border-b bg-background">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8">
          <Skeleton className="h-80 w-full rounded-2xl" />
        </div>
      </section>
    );
  }

  if (!gares.length) {
    return null;
  }

  return (
    <section id="home-stations-map" className="border-b bg-background scroll-mt-16">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8 md:py-10 space-y-4">
        <div className="space-y-1">
          <div className="inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-full bg-primary/10 text-primary">
            <MapPinIcon className="w-3 h-3" />
            {t("landing.stations_map_badge", { defaultValue: "Réseau Tibus" })}
          </div>
          <h2 className="text-2xl md:text-3xl font-extrabold tracking-tight">
            {t("landing.stations_map_title", { defaultValue: "Nos gares sur la carte" })}
          </h2>
          <p className="text-sm text-muted-foreground">
            {t("landing.stations_map_desc", {
              defaultValue:
                "Toutes les gares enregistrées avec un lien Google Maps. Cliquez sur un point pour ouvrir l'emplacement.",
            })}
          </p>
        </div>

        {apiKey && mappableGares.length > 0 && !mapError ? (
          <div
            ref={mapContainerRef}
            className="h-[360px] md:h-[420px] w-full rounded-2xl border overflow-hidden bg-muted"
          />
        ) : mappableGares.length > 0 ? (
          <div className="space-y-3">
            <iframe
              title={t("landing.stations_map_title", { defaultValue: "Nos gares sur la carte" })}
              className="h-[360px] md:h-[420px] w-full rounded-2xl border bg-muted"
              loading="lazy"
              referrerPolicy="no-referrer-when-downgrade"
              src={`https://maps.google.com/maps?q=${embedCenter.lat},${embedCenter.lng}&hl=fr&z=7&output=embed`}
            />
            {!apiKey && (
              <p className="text-xs text-muted-foreground">
                {t("landing.stations_map_no_api_key", {
                  defaultValue:
                    "Ajoutez VITE_GOOGLE_MAPS_API_KEY pour afficher tous les points sur une carte interactive.",
                })}
              </p>
            )}
            {mapError && <p className="text-xs text-destructive">{mapError}</p>}
          </div>
        ) : (
          <div className="rounded-2xl border border-dashed bg-muted/30 p-6 text-sm text-muted-foreground">
            {t("landing.stations_map_links_only", {
              defaultValue:
                "Les gares ont un lien Google Maps mais pas de coordonnées extractibles. Ouvrez chaque gare ci-dessous.",
            })}
          </div>
        )}

        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {gares.map((gare) => (
            <a
              key={gare.id}
              href={gare.googleMapsLink}
              target="_blank"
              rel="noopener noreferrer"
              className="group rounded-xl border bg-card p-3 hover:border-primary/40 hover:shadow-sm transition-all"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-semibold text-sm truncate">{gare.name}</p>
                  {gare.companyName && (
                    <p className="text-xs text-muted-foreground truncate">{gare.companyName}</p>
                  )}
                </div>
                <ExternalLinkIcon className="w-4 h-4 shrink-0 text-muted-foreground group-hover:text-primary" />
              </div>
            </a>
          ))}
        </div>
      </div>
    </section>
  );
}
