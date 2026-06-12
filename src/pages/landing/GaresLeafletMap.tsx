import { useEffect, useRef } from "react";
import L from "leaflet";
import type { GareMapPoint } from "@/lib/supabase/gares-map.ts";
import "leaflet/dist/leaflet.css";

import markerIcon2x from "leaflet/dist/images/marker-icon-2x.png";
import markerIcon from "leaflet/dist/images/marker-icon.png";
import markerShadow from "leaflet/dist/images/marker-shadow.png";

const defaultMarkerIcon = L.icon({
  iconUrl: markerIcon,
  iconRetinaUrl: markerIcon2x,
  shadowUrl: markerShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
});

function buildPopupHtml(gare: GareMapPoint) {
  const location = [gare.cityName, gare.countryName].filter(Boolean).join(", ");
  const company = gare.companyName
    ? `<p style="margin:4px 0 0;font-size:12px;color:#666">${gare.companyName}</p>`
    : "";
  const place = location
    ? `<p style="margin:4px 0 0;font-size:12px;color:#666">${location}</p>`
    : "";
  return `<div style="max-width:220px;font-family:sans-serif">
    <strong>${gare.name}</strong>
    ${place}
    ${company}
    <p style="margin:8px 0 0"><a href="${gare.googleMapsLink}" target="_blank" rel="noopener noreferrer">Ouvrir dans Google Maps</a></p>
  </div>`;
}

type GaresLeafletMapProps = {
  gares: GareMapPoint[];
  className?: string;
};

export default function GaresLeafletMap({ gares, className }: GaresLeafletMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);

  useEffect(() => {
    if (!containerRef.current || gares.length === 0) return;

    const map = L.map(containerRef.current, {
      scrollWheelZoom: false,
    });
    mapRef.current = map;

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 19,
    }).addTo(map);

    const bounds = L.latLngBounds([]);
    for (const gare of gares) {
      if (gare.lat == null || gare.lng == null) continue;
      const position = L.latLng(gare.lat, gare.lng);
      bounds.extend(position);
      L.marker(position, { icon: defaultMarkerIcon, title: gare.name })
        .addTo(map)
        .bindPopup(buildPopupHtml(gare));
    }

    if (bounds.isValid()) {
      if (gares.length === 1) {
        map.setView(bounds.getCenter(), 14);
      } else {
        map.fitBounds(bounds, { padding: [48, 48], maxZoom: 12 });
      }
    }

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, [gares]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    map.invalidateSize();
  }, [gares]);

  return <div ref={containerRef} className={className} />;
}
