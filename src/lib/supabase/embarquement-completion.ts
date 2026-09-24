import { supabase } from "@/lib/supabase";

export type WrongRoutePassenger = {
  scan_id: string;
  passenger_name: string | null;
  ticket_number: string | null;
  ticket_from: string | null;
  ticket_to: string | null;
  // autre_depart : billet d'un autre départ ; autre_gare : billet qui ne part pas de cette gare
  reason: "autre_depart" | "autre_gare" | null;
};

export type GareDoneResult = {
  ok: boolean;
  needs_ack?: boolean;
  id?: string;
  declared_count?: number;
  scanned_count: number;
  count_mismatch?: boolean;
  wrong_route_count: number;
  wrong_route: WrongRoutePassenger[];
};

export type GareCompletion = {
  id: string;
  gare_id: string | null;
  gare_name: string | null;
  declared_count: number;
  scanned_count: number;
  wrong_route_count: number;
  declared_at: string;
};

export async function listWrongRoutePassengers(
  sessionId: string,
): Promise<WrongRoutePassenger[]> {
  const { data, error } = await supabase.rpc("embarquement_wrong_route_passengers", {
    p_session_id: sessionId,
  });
  if (error) throw error;
  return (data ?? []) as WrongRoutePassenger[];
}

// Déclare la fin d'embarquement de la gare. Ne ferme PAS la session : les gares
// suivantes (escales) peuvent continuer. Si des passagers scannés sont dans le
// mauvais car, le serveur répond needs_ack=true sans rien enregistrer ; on
// rappelle alors avec ackWrong=true une fois l'embarqueur informé.
export async function declareGareBoardingDone(input: {
  sessionId: string;
  passengerCount: number;
  ackWrong?: boolean;
}): Promise<GareDoneResult> {
  const { data, error } = await supabase.rpc("embarquement_declare_gare_done", {
    p_session_id: input.sessionId,
    p_passenger_count: input.passengerCount,
    p_ack_wrong: input.ackWrong ?? false,
  });
  if (error) throw error;
  return data as GareDoneResult;
}

export async function listGareCompletions(sessionId: string): Promise<GareCompletion[]> {
  const { data, error } = await supabase.rpc("embarquement_list_gare_completions", {
    p_session_id: sessionId,
  });
  if (error) throw error;
  return (data ?? []) as GareCompletion[];
}
