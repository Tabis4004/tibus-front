import { useEffect, useMemo, useRef, useState, lazy, Suspense } from "react";
import { useTranslation } from "react-i18next";
import { ExternalLinkIcon, MapPinIcon } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { listGaresMapPointsSupabase, groupGaresByCountryAndCity, type GareMapPoint } from "@/lib/supabase/gares-map.ts";
import {
  CITY_MAP_ZOOM_THRESHOLD_KM,
  cityOptionsFromGares,
  garesSpreadKm,
} from "@/lib/gare-map-utils.ts";
import { Badge } from "@/components/ui/badge.tsx";
import { cn } from "@/lib/utils.ts";

const GaresLeafletMap = lazy(() => import("@/pages/landing/GaresLeafletMap.tsx"));

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
    gm_authFailure?: () => void;
  }
}

const DEFAULT_CENTER: GoogleLatLng = { lat: 5.36, lng: -4.0083 };
const MAPS_SCRIPT_ID = "tibus-google-maps-script";

function useInteractiveGoogleMap(): boolean {
  return import.meta.env.VITE_GOOGLE_MAPS_USE_JS === "true";
}

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
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}&v=weekly`;
    script.onload = () => {
      if (window.google?.maps) resolve(window.google.maps);
      else reject(new Error("Google Maps indisponible"));
    };
    script.onerror = () => reject(new Error("Chargement Google Maps impossible"));
    document.head.appendChild(script);
  });
}

function buildInfoContent(gare: GareMapPoint) {
  const location = [gare.cityName, gare.countryName].filter(Boolean).join(", ");
  const company = gare.companyName ? `<p style="margin:4px 0 0;font-size:12px;color:#666">${gare.companyName}</p>` : "";
  const place = location ? `<p style="margin:4px 0 0;font-size:12px;color:#666">${location}</p>` : "";
  return `<div style="max-width:220px;font-family:sans-serif">
    <strong>${gare.name}</strong>
    ${place}
    ${company}
    <p style="margin:8px 0 0"><a href="${gare.googleMapsLink}" target="_blank" rel="noopener noreferrer">Ouvrir dans Google Maps</a></p>
  </div>`;
}

export default function HomeStationsMap({ embedded = false }: { embedded?: boolean }) {
  const { t } = useTranslation("common");
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const [gares, setGares] = useState<GareMapPoint[] | undefined>(undefined);
  const [mapError, setMapError] = useState<string | null>(null);
  const [selectedCountry, setSelectedCountry] = useState<string>("all");
  const [selectedCity, setSelectedCity] = useState<string>("all");
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string | undefined;
  const interactiveMap = useInteractiveGoogleMap() && Boolean(apiKey?.trim());

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

  useEffect(() => {
    if (!gares?.length) return;
    const coteIvoire = gares.find((gare) => /ivoire/i.test(gare.countryName))?.countryName;
    if (coteIvoire) setSelectedCountry(coteIvoire);
  }, [gares]);

  const groupedGares = useMemo(
    () => groupGaresByCountryAndCity(gares ?? []),
    [gares],
  );

  const countryOptions = useMemo(
    () => groupedGares.map((group) => group.countryName),
    [groupedGares],
  );

  const visibleGares = useMemo(() => {
    if (selectedCountry === "all") return gares ?? [];
    return (gares ?? []).filter((gare) => gare.countryName === selectedCountry);
  }, [gares, selectedCountry]);

  const mappableGares = useMemo(
    () => visibleGares.filter((gare) => gare.lat != null && gare.lng != null),
    [visibleGares],
  );

  const cityOptions = useMemo(
    () => cityOptionsFromGares(mappableGares),
    [mappableGares],
  );
  const cityOptionsKey = cityOptions.join("|");

  const needsCityZoom = useMemo(
    () => garesSpreadKm(mappableGares) > CITY_MAP_ZOOM_THRESHOLD_KM,
    [mappableGares],
  );

  useEffect(() => {
    if (!needsCityZoom || cityOptions.length <= 1) {
      setSelectedCity("all");
      return;
    }
    setSelectedCity((current) =>
      current !== "all" && cityOptions.includes(current) ? current : cityOptions[0],
    );
  }, [selectedCountry, needsCityZoom, cityOptionsKey, cityOptions]);

  const mapGares = useMemo(() => {
    if (!needsCityZoom || selectedCity === "all") return mappableGares;
    return mappableGares.filter((gare) => gare.cityName === selectedCity);
  }, [mappableGares, needsCityZoom, selectedCity]);

  useEffect(() => {
    if (!interactiveMap || !apiKey || !mapContainerRef.current || mapGares.length === 0) {
      return;
    }

    let markers: GoogleMarkerInstance[] = [];
    let map: GoogleMapInstance | null = null;
    let cancelled = false;

    const previousAuthFailure = window.gm_authFailure;
    window.gm_authFailure = () => {
      if (!cancelled) setMapError("Google Maps API refusée");
    };

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

        for (const gare of mapGares) {
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

        if (mapGares.length === 1) {
          activeMap.setCenter({ lat: mapGares[0].lat as number, lng: mapGares[0].lng as number });
          activeMap.setZoom(17);
        } else if (needsCityZoom) {
          activeMap.setCenter({ lat: mapGares[0].lat as number, lng: mapGares[0].lng as number });
          activeMap.setZoom(17);
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
      window.gm_authFailure = previousAuthFailure;
      for (const marker of markers) marker.setMap(null);
      markers = [];
      map = null;
    };
  }, [apiKey, interactiveMap, mapGares, needsCityZoom]);

  if (gares === undefined) {
    const skeleton = <Skeleton className="h-80 w-full rounded-2xl" />;
    if (embedded) return skeleton;
    return (
      <section className="border-b bg-background">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8">{skeleton}</div>
      </section>
    );
  }

  if (!gares.length) {
    return null;
  }

  const body = (
    <div className={embedded ? "space-y-4" : "max-w-6xl mx-auto px-4 sm:px-6 py-8 md:py-10 space-y-4"}>
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

        {countryOptions.length > 1 && (
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setSelectedCountry("all")}
              className={cn(
                "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                selectedCountry === "all"
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-border bg-background hover:border-primary/40",
              )}
            >
              {t("landing.stations_map_all_countries", { defaultValue: "Tous les pays" })}
            </button>
            {countryOptions.map((countryName) => (
              <button
                key={countryName}
                type="button"
                onClick={() => setSelectedCountry(countryName)}
                className={cn(
                  "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                  selectedCountry === countryName
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-border bg-background hover:border-primary/40",
                )}
              >
                {countryName}
              </button>
            ))}
          </div>
        )}

        {needsCityZoom && cityOptions.length > 1 && (
          <div className="space-y-2">
            <p className="text-xs text-muted-foreground">
              {t("landing.stations_map_city_hint", {
                defaultValue: "Les gares sont éloignées — zoomez par ville pour voir chaque station.",
              })}
            </p>
            <div className="flex flex-wrap gap-2">
              {cityOptions.map((cityName) => (
                <button
                  key={cityName}
                  type="button"
                  onClick={() => setSelectedCity(cityName)}
                  className={cn(
                    "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                    selectedCity === cityName
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-border bg-background hover:border-primary/40",
                  )}
                >
                  {cityName}
                </button>
              ))}
            </div>
          </div>
        )}

        {interactiveMap && mapGares.length > 0 && !mapError ? (
          <div
            ref={mapContainerRef}
            className="h-[360px] md:h-[420px] w-full rounded-2xl border overflow-hidden bg-muted"
          />
        ) : mapGares.length > 0 ? (
          <div className="space-y-2">
            <Suspense fallback={<Skeleton className="h-[360px] md:h-[420px] w-full rounded-2xl" />}>
              <GaresLeafletMap
                key={`${selectedCountry}-${selectedCity}-${mapGares.map((g) => g.id).join(",")}`}
                gares={mapGares}
                fixedZoom={needsCityZoom ? 17 : undefined}
                className="h-[360px] md:h-[420px] w-full rounded-2xl border overflow-hidden bg-muted z-0"
              />
            </Suspense>
            {mapError && (
              <p className="text-xs text-muted-foreground">
                {t("landing.stations_map_embed_fallback", {
                  defaultValue: "Carte OpenStreetMap — chaque pin correspond à une gare Tibus.",
                })}
              </p>
            )}
          </div>
        ) : (
          <div className="rounded-2xl border border-dashed bg-muted/30 p-6 text-sm text-muted-foreground">
            {t("landing.stations_map_links_only", {
              defaultValue:
                "Les gares ont un lien Google Maps mais pas de coordonnées extractibles. Ouvrez chaque gare ci-dessous.",
            })}
          </div>
        )}

        <div className="space-y-8">
          {(selectedCountry === "all" ? groupedGares : groupedGares.filter((g) => g.countryName === selectedCountry)).map(
            (countryGroup) => (
              <div key={countryGroup.countryName} className="space-y-4">
                <div className="flex items-center gap-2">
                  <h3 className="text-lg font-bold">{countryGroup.countryName}</h3>
                  <Badge variant="secondary">
                    {countryGroup.cities.reduce((sum, city) => sum + city.gares.length, 0)}
                  </Badge>
                </div>

                <div className="space-y-5 pl-1 border-l-2 border-primary/20">
                  {countryGroup.cities.map((cityGroup) => (
                    <div key={`${countryGroup.countryName}-${cityGroup.cityName}`} className="space-y-3 pl-4">
                      <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
                        {cityGroup.cityName}
                      </h4>
                      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                        {cityGroup.gares.map((gare) => (
                          <button
                            key={gare.id}
                            type="button"
                            onClick={() => {
                              if (needsCityZoom) setSelectedCity(gare.cityName);
                              document.getElementById("home-stations-map")?.scrollIntoView({ behavior: "smooth", block: "start" });
                            }}
                            className="group rounded-xl border bg-card p-3 hover:border-primary/40 hover:shadow-sm transition-all text-left"
                          >
                            <div className="flex items-start justify-between gap-2">
                              <div className="min-w-0">
                                <p className="font-semibold text-sm truncate">{gare.name}</p>
                                {gare.companyName && (
                                  <p className="text-xs text-muted-foreground truncate">{gare.companyName}</p>
                                )}
                              </div>
                              <a
                                href={gare.googleMapsLink}
                                target="_blank"
                                rel="noopener noreferrer"
                                onClick={(event) => event.stopPropagation()}
                                className="shrink-0 text-muted-foreground hover:text-primary"
                                aria-label="Ouvrir dans Google Maps"
                              >
                                <ExternalLinkIcon className="w-4 h-4" />
                              </a>
                            </div>
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ),
          )}
        </div>
      </div>
  );

  if (embedded) {
    return <div id="home-stations-map">{body}</div>;
  }

  return (
    <section id="home-stations-map" className="border-b bg-background scroll-mt-16">
      {body}
    </section>
  );
}
