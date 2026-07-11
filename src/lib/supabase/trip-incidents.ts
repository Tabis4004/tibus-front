import { supabase } from "@/lib/supabase";

export const TRIP_INCIDENT_CATEGORIES = [
  "retard",
  "panne",
  "securite",
  "confort",
  "conduite",
  "objet_perdu",
  "autre",
] as const;

export type TripIncidentCategory = (typeof TRIP_INCIDENT_CATEGORIES)[number];

export const TRIP_INCIDENT_CATEGORY_LABELS: Record<TripIncidentCategory, string> = {
  retard: "Retard",
  panne: "Panne / véhicule",
  securite: "Sécurité",
  confort: "Confort / propreté",
  conduite: "Conduite dangereuse",
  objet_perdu: "Objet perdu",
  autre: "Autre",
};

export type TripIncident = {
  id: string;
  category: string;
  message: string;
  status: "nouveau" | "traite";
  createdAt: string;
  reporterName: string;
  reporterPhone: string | null;
  ticketReference: string | null;
};

export type TripIncidentCount = {
  reservationId: string;
  total: number;
  nouveaux: number;
};

// Voyageur : signale un incident sur son billet (notifie les owners).
export async function reportTripIncidentSupabase(input: {
  bookingId: string;
  category: string;
  message: string;
}): Promise<void> {
  const { error } = await supabase.rpc("report_trip_incident", {
    p_booking_id: input.bookingId,
    p_category: input.category,
    p_message: input.message.trim(),
  });
  if (error) throw error;
}

// Owner / staff : incidents d'un voyage.
export async function listTripIncidentsSupabase(
  reservationId: string,
): Promise<TripIncident[]> {
  const { data, error } = await supabase.rpc("list_trip_incidents", {
    p_reservation_id: reservationId,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    category: String(row.category ?? "autre"),
    message: String(row.message ?? ""),
    status: (row.status === "traite" ? "traite" : "nouveau") as "nouveau" | "traite",
    createdAt: String(row.createdAt ?? ""),
    reporterName: String(row.reporterName ?? "").trim() || "Voyageur",
    reporterPhone: row.reporterPhone ? String(row.reporterPhone) : null,
    ticketReference: row.ticketReference ? String(row.ticketReference) : null,
  }));
}

// Owner / staff : compteurs d'incidents par voyage de la compagnie.
export async function listTripIncidentCountsSupabase(
  companyId: string,
): Promise<Map<string, TripIncidentCount>> {
  const { data, error } = await supabase.rpc("list_trip_incident_counts", {
    p_company_id: companyId,
  });
  if (error) throw error;
  const map = new Map<string, TripIncidentCount>();
  for (const row of (data ?? []) as Record<string, unknown>[]) {
    const reservationId = String(row.reservationId);
    map.set(reservationId, {
      reservationId,
      total: Number(row.total ?? 0),
      nouveaux: Number(row.nouveaux ?? 0),
    });
  }
  return map;
}

export async function setTripIncidentStatusSupabase(
  incidentId: string,
  status: "nouveau" | "traite",
): Promise<void> {
  const { error } = await supabase.rpc("set_trip_incident_status", {
    p_incident_id: incidentId,
    p_status: status,
  });
  if (error) throw error;
}
