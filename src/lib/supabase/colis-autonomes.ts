import { supabase } from "@/lib/supabase";
import { throwSupabaseError } from "@/lib/supabase/errors.ts";

export type ColisStatut = "enregistre" | "charge" | "arrive" | "livre";

export type ColisNature = {
  id: string;
  libelle: string;
  isActive: boolean;
  createdAt?: string;
};

export type CompanyColisSettings = {
  companyId: string;
  colisAutonomeEnabled: boolean;
  colisSmsConfigEnabled: boolean;
  smsOnEnregistre: boolean;
  smsOnCharge: boolean;
  smsOnArrive: boolean;
  smsOnLivre: boolean;
};

export type ColisAutonomeRow = {
  id: string;
  statutColis: ColisStatut;
  nomExpediteur: string;
  telephoneExpediteur: string;
  nomDestinataire: string;
  telephoneDestinataire: string;
  descriptionContenu?: string | null;
  poidsKg?: number | null;
  nombrePieces: number;
  montantFret: number;
  createdAt: string;
  updatedAt: string;
  gareDepart: string;
  gareDestination: string;
  natures: string[];
};

export type ColisAutonomeDetail = ColisAutonomeRow & {
  companyId: string;
  companyName: string;
  gareDepartId: string;
  gareDestinationId: string;
  sourceVente: string;
  natureIds: string[];
};

export type ColisSmsPayload = {
  send: boolean;
  message?: string;
  expediteurPhone?: string;
  destinatairePhone?: string;
};

export type RegisterColisResult = {
  id: string;
  statutColis: ColisStatut;
  montantFret: number;
  sms: ColisSmsPayload;
};

function mapSettings(data: Record<string, unknown>): CompanyColisSettings {
  return {
    companyId: String(data.companyId ?? ""),
    colisAutonomeEnabled: Boolean(data.colisAutonomeEnabled),
    colisSmsConfigEnabled: Boolean(data.colisSmsConfigEnabled),
    smsOnEnregistre: Boolean(data.smsOnEnregistre),
    smsOnCharge: Boolean(data.smsOnCharge),
    smsOnArrive: Boolean(data.smsOnArrive),
    smsOnLivre: Boolean(data.smsOnLivre),
  };
}

function mapColisRow(row: Record<string, unknown>): ColisAutonomeRow {
  const natures = Array.isArray(row.natures)
    ? row.natures.map((n) => String(n))
    : [];
  return {
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
    createdAt: String(row.createdAt ?? ""),
    updatedAt: String(row.updatedAt ?? ""),
    gareDepart: String(row.gareDepart ?? ""),
    gareDestination: String(row.gareDestination ?? ""),
    natures,
  };
}

export async function getCompanyColisSettingsSupabase(
  companyId: string,
): Promise<CompanyColisSettings> {
  const { data, error } = await supabase.rpc("get_company_colis_settings", {
    p_company_id: companyId,
  });
  if (error) throw error;
  return mapSettings((data ?? {}) as Record<string, unknown>);
}

export async function updateCompanyColisSmsSettingsSupabase(
  companyId: string,
  input: Pick<
    CompanyColisSettings,
    "smsOnEnregistre" | "smsOnCharge" | "smsOnArrive" | "smsOnLivre"
  >,
): Promise<CompanyColisSettings> {
  const { data, error } = await supabase.rpc("update_company_colis_sms_settings", {
    p_company_id: companyId,
    p_sms_on_enregistre: input.smsOnEnregistre,
    p_sms_on_charge: input.smsOnCharge,
    p_sms_on_arrive: input.smsOnArrive,
    p_sms_on_livre: input.smsOnLivre,
  });
  if (error) throw error;
  return mapSettings((data ?? {}) as Record<string, unknown>);
}

export async function listColisNaturesSupabase(companyId: string): Promise<ColisNature[]> {
  const { data, error } = await supabase
    .from("colis_natures")
    .select("id, libelle, is_active, created_at")
    .eq("company_id", companyId)
    .order("libelle");
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: String(row.id),
    libelle: String(row.libelle),
    isActive: Boolean(row.is_active),
    createdAt: row.created_at ? String(row.created_at) : undefined,
  }));
}

export async function upsertColisNatureSupabase(
  companyId: string,
  libelle: string,
  natureId?: string,
  isActive = true,
): Promise<ColisNature> {
  const { data, error } = await supabase.rpc("upsert_colis_nature", {
    p_company_id: companyId,
    p_libelle: libelle.trim(),
    p_nature_id: natureId ?? null,
    p_is_active: isActive,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id),
    libelle: String(row.libelle),
    isActive: Boolean(row.isActive),
  };
}

export async function deleteColisNatureSupabase(natureId: string): Promise<void> {
  const { error } = await supabase.rpc("delete_colis_nature", { p_nature_id: natureId });
  if (error) throw error;
}

export type RegisterColisInput = {
  companyId: string;
  gareDepartId: string;
  gareDestinationId: string;
  nomExpediteur: string;
  telephoneExpediteur: string;
  nomDestinataire: string;
  telephoneDestinataire: string;
  descriptionContenu?: string;
  poidsKg?: number;
  nombrePieces: number;
  montantFret: number;
  natureIds: string[];
};

export async function registerColisAutonomeSupabase(
  input: RegisterColisInput,
): Promise<RegisterColisResult> {
  const { data, error } = await supabase.rpc("register_colis_autonome", {
    p_company_id: input.companyId,
    p_gare_depart_id: input.gareDepartId,
    p_gare_destination_id: input.gareDestinationId,
    p_nom_expediteur: input.nomExpediteur,
    p_telephone_expediteur: input.telephoneExpediteur,
    p_nom_destinataire: input.nomDestinataire,
    p_telephone_destinataire: input.telephoneDestinataire,
    p_description_contenu: input.descriptionContenu ?? null,
    p_poids_kg: input.poidsKg ?? null,
    p_nombre_pieces: input.nombrePieces,
    p_montant_fret: input.montantFret,
    p_nature_ids: input.natureIds,
  });
  if (error) throwSupabaseError(error, "Enregistrement colis impossible");
  const row = (data ?? {}) as Record<string, unknown>;
  const sms = (row.sms ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id),
    statutColis: String(row.statutColis) as ColisStatut,
    montantFret: Number(row.montantFret ?? 0),
    sms: {
      send: Boolean(sms.send),
      message: sms.message ? String(sms.message) : undefined,
      expediteurPhone: sms.expediteurPhone ? String(sms.expediteurPhone) : undefined,
      destinatairePhone: sms.destinatairePhone ? String(sms.destinatairePhone) : undefined,
    },
  };
}

export async function listColisAutonomesSupabase(
  companyId: string,
  statut?: ColisStatut | null,
): Promise<ColisAutonomeRow[]> {
  const { data, error } = await supabase.rpc("list_colis_autonomes", {
    p_company_id: companyId,
    p_statut: statut ?? null,
    p_limit: 100,
  });
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  return rows
    .filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === "object")
    .map(mapColisRow);
}

export async function getColisAutonomeDetailSupabase(
  colisId: string,
): Promise<ColisAutonomeDetail | null> {
  const { data, error } = await supabase.rpc("get_colis_autonome_detail", {
    p_colis_id: colisId,
  });
  if (error) throw error;
  if (!data) return null;
  const row = data as Record<string, unknown>;
  const base = mapColisRow(row);
  const natureIds = Array.isArray(row.natureIds)
    ? row.natureIds.map((id) => String(id))
    : [];
  return {
    ...base,
    companyId: String(row.companyId ?? ""),
    companyName: String(row.companyName ?? ""),
    gareDepartId: String(row.gareDepartId ?? ""),
    gareDestinationId: String(row.gareDestinationId ?? ""),
    sourceVente: String(row.sourceVente ?? "guichet_cash"),
    natureIds,
  };
}

export async function updateColisStatutSupabase(
  colisId: string,
  statut: ColisStatut,
): Promise<{ id: string; statutColis: ColisStatut; sms: ColisSmsPayload }> {
  const { data, error } = await supabase.rpc("update_colis_autonome_statut", {
    p_colis_id: colisId,
    p_new_statut: statut,
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
    },
  };
}

export async function deliverColisAutonomeSupabase(retraitCode: string): Promise<{
  id: string;
  statutColis: ColisStatut;
  nomDestinataire: string;
  nomExpediteur: string;
  sms: ColisSmsPayload;
}> {
  const { data, error } = await supabase.rpc("deliver_colis_autonome", {
    p_retrait_code: retraitCode.trim(),
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  const sms = (row.sms ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id),
    statutColis: String(row.statutColis) as ColisStatut,
    nomDestinataire: String(row.nomDestinataire ?? ""),
    nomExpediteur: String(row.nomExpediteur ?? ""),
    sms: {
      send: Boolean(sms.send),
      message: sms.message ? String(sms.message) : undefined,
      expediteurPhone: sms.expediteurPhone ? String(sms.expediteurPhone) : undefined,
      destinatairePhone: sms.destinatairePhone ? String(sms.destinatairePhone) : undefined,
    },
  };
}

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

export type ColisSmsSendResult = {
  sent: number;
  failed: number;
  failures?: Array<{ phone: string; error?: string }>;
};

export async function sendColisSmsSupabase(payload: {
  colisId: string;
  statut: ColisStatut;
  message: string;
  phones: string[];
}): Promise<ColisSmsSendResult> {
  const { data: sessionData } = await supabase.auth.getSession();
  const token = sessionData.session?.access_token;
  if (!token) {
    throw new Error("Session expirée — reconnectez-vous");
  }

  const uniquePhones = [...new Set(payload.phones.map((p) => p.trim()).filter(Boolean))];
  if (!uniquePhones.length) {
    throw new Error("Aucun numéro de téléphone renseigné");
  }

  const response = await fetch(`${supabaseUrl}/functions/v1/colis-sms-notify`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      apikey: supabaseAnonKey,
    },
    body: JSON.stringify({
      colisId: payload.colisId,
      statut: payload.statut,
      message: payload.message,
      phones: uniquePhones,
    }),
  });

  const body = (await response.json().catch(() => ({}))) as {
    error?: string;
    sent?: number;
    failed?: number;
    failures?: Array<{ phone: string; error?: string }>;
  };

  if (!response.ok) {
    const detail = body.failures?.[0]?.error;
    throw new Error(detail ?? body.error ?? `Envoi SMS impossible (${response.status})`);
  }

  const sent = Number(body.sent ?? 0);
  const failed = Number(body.failed ?? 0);
  if (sent === 0) {
    const detail = body.failures?.[0]?.error ?? body.error ?? "Aucun SMS délivré";
    throw new Error(detail);
  }

  return { sent, failed, failures: body.failures };
}

export const COLIS_STATUT_LABELS: Record<ColisStatut, string> = {
  enregistre: "Enregistré",
  charge: "Chargé",
  arrive: "Arrivé",
  livre: "Livré",
};

export const COLIS_NEXT_STATUT: Partial<Record<ColisStatut, ColisStatut>> = {
  enregistre: "charge",
  charge: "arrive",
  arrive: "livre",
};
