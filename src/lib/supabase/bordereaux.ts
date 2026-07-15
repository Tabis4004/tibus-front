import { supabase } from "@/lib/supabase";
import { mapColisRow, type ColisAutonomeRow, type ColisSmsPayload, type ColisStatut } from "@/lib/supabase/colis-autonomes.ts";

export type BordereauListRow = {
  id: string;
  reference: string;
  statut: "ouvert" | "clos";
  gareDepart: string;
  gareDestination: string | null;
  busPlateNumber: string | null;
  colisCount: number;
  createdAt: string;
  closedAt: string | null;
};

export type BordereauColisRow = {
  id: string;
  statutColis: ColisStatut;
  nomExpediteur: string;
  telephoneExpediteur: string;
  nomDestinataire: string;
  telephoneDestinataire: string;
  descriptionContenu: string | null;
  poidsKg: number | null;
  nombrePieces: number;
  montantFret: number;
  gareDepart: string;
  gareDestination: string;
  natures: string[];
  addedAt: string;
};

export type BordereauDetail = {
  id: string;
  reference: string;
  statut: "ouvert" | "clos";
  companyId: string;
  companyName: string;
  gareDepart: string;
  gareDestination: string | null;
  busPlateNumber: string | null;
  createdAt: string;
  closedAt: string | null;
  colis: BordereauColisRow[];
};

function mapDetail(data: Record<string, unknown>): BordereauDetail {
  const colis = Array.isArray(data.colis) ? (data.colis as Record<string, unknown>[]) : [];
  return {
    id: String(data.id),
    reference: String(data.reference ?? ""),
    statut: data.statut === "clos" ? "clos" : "ouvert",
    companyId: String(data.companyId ?? ""),
    companyName: String(data.companyName ?? ""),
    gareDepart: String(data.gareDepart ?? ""),
    gareDestination: data.gareDestination ? String(data.gareDestination) : null,
    busPlateNumber: data.busPlateNumber ? String(data.busPlateNumber) : null,
    createdAt: String(data.createdAt ?? ""),
    closedAt: data.closedAt ? String(data.closedAt) : null,
    colis: colis.map((row) => ({
      id: String(row.id),
      statutColis: String(row.statutColis) as ColisStatut,
      nomExpediteur: String(row.nomExpediteur ?? ""),
      telephoneExpediteur: String(row.telephoneExpediteur ?? ""),
      nomDestinataire: String(row.nomDestinataire ?? ""),
      telephoneDestinataire: String(row.telephoneDestinataire ?? ""),
      descriptionContenu: row.descriptionContenu ? String(row.descriptionContenu) : null,
      poidsKg: row.poidsKg != null ? Number(row.poidsKg) : null,
      nombrePieces: Number(row.nombrePieces ?? 1),
      montantFret: Number(row.montantFret ?? 0),
      gareDepart: String(row.gareDepart ?? ""),
      gareDestination: String(row.gareDestination ?? ""),
      natures: Array.isArray(row.natures) ? row.natures.map((n) => String(n)) : [],
      addedAt: String(row.addedAt ?? ""),
    })),
  };
}

export async function createBordereauSupabase(input: {
  companyId: string;
  gareDepartId: string;
  gareDestinationId?: string | null;
  busId?: string | null;
}): Promise<BordereauDetail> {
  const { data, error } = await supabase.rpc("create_bordereau_livraison", {
    p_company_id: input.companyId,
    p_gare_depart_id: input.gareDepartId,
    p_gare_destination_id: input.gareDestinationId ?? null,
    p_bus_id: input.busId ?? null,
  });
  if (error) throw error;
  return mapDetail((data ?? {}) as Record<string, unknown>);
}

export async function addColisToBordereauSupabase(
  bordereauId: string,
  colisId: string,
): Promise<{ id: string; statutColis: ColisStatut; sms: ColisSmsPayload }> {
  const { data, error } = await supabase.rpc("add_colis_to_bordereau", {
    p_bordereau_id: bordereauId,
    p_colis_id: colisId,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  const sms = (row.sms ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id),
    statutColis: String(row.statutColis) as ColisStatut,
    sms: {
      send: Boolean(sms.send),
      message: sms.message ? String(sms.message) : undefined,
      expediteurPhone: sms.expediteurPhone ? String(sms.expediteurPhone) : undefined,
      destinatairePhone: sms.destinatairePhone ? String(sms.destinatairePhone) : undefined,
      skipReason:
        sms.skipReason === "admin_gate" || sms.skipReason === "owner_disabled"
          ? (sms.skipReason as "admin_gate" | "owner_disabled")
          : null,
    },
  };
}

export async function removeColisFromBordereauSupabase(
  bordereauId: string,
  colisId: string,
): Promise<void> {
  const { error } = await supabase.rpc("remove_colis_from_bordereau", {
    p_bordereau_id: bordereauId,
    p_colis_id: colisId,
  });
  if (error) throw error;
}

export async function closeBordereauSupabase(bordereauId: string): Promise<BordereauDetail> {
  const { data, error } = await supabase.rpc("close_bordereau_livraison", {
    p_bordereau_id: bordereauId,
  });
  if (error) throw error;
  return mapDetail((data ?? {}) as Record<string, unknown>);
}

export async function listBordereauxSupabase(
  companyId: string,
  limit = 50,
): Promise<BordereauListRow[]> {
  const { data, error } = await supabase.rpc("list_bordereaux_livraison", {
    p_company_id: companyId,
    p_limit: limit,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    reference: String(row.reference ?? ""),
    statut: row.statut === "clos" ? "clos" : "ouvert",
    gareDepart: String(row.gareDepart ?? ""),
    gareDestination: row.gareDestination ? String(row.gareDestination) : null,
    busPlateNumber: row.busPlateNumber ? String(row.busPlateNumber) : null,
    colisCount: Number(row.colisCount ?? 0),
    createdAt: String(row.createdAt ?? ""),
    closedAt: row.closedAt ? String(row.closedAt) : null,
  }));
}

export async function getBordereauSupabase(bordereauId: string): Promise<BordereauDetail> {
  const { data, error } = await supabase.rpc("get_bordereau_livraison", {
    p_bordereau_id: bordereauId,
  });
  if (error) throw error;
  return mapDetail((data ?? {}) as Record<string, unknown>);
}

/**
 * Colis déjà enregistrés (gare de départ/destination du bordereau, même
 * compagnie, pas livrés, pas déjà sur un bordereau ouvert) pouvant être
 * ajoutés au bordereau en un clic — alternative au scan / à la saisie
 * manuelle de la référence CL-… (plus user-friendly au guichet).
 */
export async function listColisDisponiblesBordereauSupabase(
  bordereauId: string,
  limit = 200,
): Promise<ColisAutonomeRow[]> {
  const { data, error } = await supabase.rpc("list_colis_disponibles_bordereau", {
    p_bordereau_id: bordereauId,
    p_limit: limit,
  });
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  return rows
    .filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === "object")
    .map(mapColisRow);
}
