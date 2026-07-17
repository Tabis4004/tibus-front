import { supabase } from "@/lib/supabase";
import { throwSupabaseError } from "@/lib/supabase/errors.ts";

export type ColisStatut = "enregistre" | "charge" | "arrive" | "livre";

export type ColisNature = {
  id: string;
  libelle: string;
  isActive: boolean;
  createdAt?: string;
  /** Prix minimum fixe (XOF) pour cette nature ; prioritaire sur le taux si renseigné. */
  prixMinFixe?: number | null;
  /** Taux minimum (XOF / kg) pour cette nature, appliqué au poids du colis. */
  prixMinTaux?: number | null;
};

export type CompanyColisSettings = {
  companyId: string;
  colisAutonomeEnabled: boolean;
  colisSmsConfigEnabled: boolean;
  /** Étapes incluses dans l'offre de la compagnie (décidées par la plateforme). */
  smsAllowedEnregistre: boolean;
  smsAllowedCharge: boolean;
  smsAllowedArrive: boolean;
  smsAllowedLivre: boolean;
  smsOnEnregistre: boolean;
  smsOnCharge: boolean;
  smsOnArrive: boolean;
  smsOnLivre: boolean;
  /**
   * Override général du prix minimum (fixe XOF), toutes natures confondues.
   * S'applique à la place des règles par nature dès qu'il est non NULL.
   */
  colisPrixMinFixeGeneral?: number | null;
  /** Override général du taux minimum (XOF / kg), toutes natures confondues. */
  colisPrixMinTauxGeneral?: number | null;
  /**
   * Pourcentage perçu par défaut (0-100), pré-rempli dans le formulaire
   * d'envoi quand l'agent choisit le calcul automatique du montant fret à
   * partir de la valeur marchandise déclarée.
   */
  colisPourcentagePercuGeneral?: number | null;
};

export type ColisAutonomeRow = {
  id: string;
  /**
   * Numéro de reçu séquentiel par gare de départ (migration 180) :
   * 4 premiers caractères du nom de la gare + ordre sur 6 chiffres
   * (ex. ABOI000001). Null pour un colis antérieur non synchronisé.
   */
  numeroRecu?: string | null;
  statutColis: ColisStatut;
  nomExpediteur: string;
  telephoneExpediteur: string;
  nomDestinataire: string;
  telephoneDestinataire: string;
  descriptionContenu?: string | null;
  poidsKg?: number | null;
  nombrePieces: number;
  montantFret: number;
  /** Valeur déclarée de la marchandise (XOF) — sert de base au remboursement en cas de perte. */
  valeurMarchandise?: number | null;
  /** Pourcentage de la valeur marchandise utilisé pour calculer montantFret, si mode automatique. */
  pourcentagePercu?: number | null;
  /** Bus qui effectue le convoi — assignable à l'enregistrement ou au chargement. */
  busId?: string | null;
  /** Immatriculation du bus (affichage), voir busId. */
  busPlateNumber?: string | null;
  createdAt: string;
  updatedAt: string;
  gareDepart: string;
  /** Téléphone de la gare de départ — imprimé sur le reçu, distinct du téléphone de la compagnie. */
  gareDepartPhone?: string | null;
  gareDestination: string;
  natures: string[];
};

export type ColisAutonomeDetail = ColisAutonomeRow & {
  companyId: string;
  companyName: string;
  /** Téléphone de la compagnie — affiché en en-tête du reçu, sous le nom. */
  companyPhone?: string | null;
  gareDepartId: string;
  gareDestinationId: string;
  /** Téléphone de la gare de destination — affiché sous le champ Destination du reçu. */
  gareDestinationPhone?: string | null;
  sourceVente: string;
  natureIds: string[];
};

export type ColisSmsPayload = {
  send: boolean;
  message?: string;
  expediteurPhone?: string;
  destinatairePhone?: string;
  skipReason?: "admin_gate" | "owner_disabled" | null;
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
    smsAllowedEnregistre: Boolean(data.smsAllowedEnregistre ?? data.colisSmsConfigEnabled),
    smsAllowedCharge: Boolean(data.smsAllowedCharge ?? data.colisSmsConfigEnabled),
    smsAllowedArrive: Boolean(data.smsAllowedArrive ?? data.colisSmsConfigEnabled),
    smsAllowedLivre: Boolean(data.smsAllowedLivre ?? data.colisSmsConfigEnabled),
    smsOnEnregistre: Boolean(data.smsOnEnregistre),
    smsOnCharge: Boolean(data.smsOnCharge),
    smsOnArrive: Boolean(data.smsOnArrive),
    smsOnLivre: Boolean(data.smsOnLivre),
    colisPrixMinFixeGeneral:
      data.colisPrixMinFixeGeneral != null ? Number(data.colisPrixMinFixeGeneral) : null,
    colisPrixMinTauxGeneral:
      data.colisPrixMinTauxGeneral != null ? Number(data.colisPrixMinTauxGeneral) : null,
    colisPourcentagePercuGeneral:
      data.colisPourcentagePercuGeneral != null ? Number(data.colisPourcentagePercuGeneral) : null,
  };
}

export function mapColisRow(row: Record<string, unknown>): ColisAutonomeRow {
  const natures = Array.isArray(row.natures)
    ? row.natures.map((n) => String(n))
    : [];
  return {
    id: String(row.id),
    numeroRecu: row.numeroRecu ? String(row.numeroRecu) : null,
    statutColis: String(row.statutColis) as ColisStatut,
    nomExpediteur: String(row.nomExpediteur ?? ""),
    telephoneExpediteur: String(row.telephoneExpediteur ?? ""),
    nomDestinataire: String(row.nomDestinataire ?? ""),
    telephoneDestinataire: String(row.telephoneDestinataire ?? ""),
    descriptionContenu: row.descriptionContenu ? String(row.descriptionContenu) : null,
    poidsKg: row.poidsKg != null ? Number(row.poidsKg) : null,
    nombrePieces: Number(row.nombrePieces ?? 1),
    montantFret: Number(row.montantFret ?? 0),
    valeurMarchandise: row.valeurMarchandise != null ? Number(row.valeurMarchandise) : null,
    pourcentagePercu: row.pourcentagePercu != null ? Number(row.pourcentagePercu) : null,
    busId: row.busId ? String(row.busId) : null,
    busPlateNumber: row.busPlateNumber ? String(row.busPlateNumber) : null,
    createdAt: String(row.createdAt ?? ""),
    updatedAt: String(row.updatedAt ?? ""),
    gareDepart: String(row.gareDepart ?? ""),
    gareDepartPhone: row.gareDepartPhone ? String(row.gareDepartPhone) : null,
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

/**
 * Met à jour l'override général du prix minimum (fixe ou taux/kg) de la
 * compagnie. Passer `null` pour désactiver l'override et retomber sur les
 * règles par nature de colis.
 */
export async function updateCompanyColisPriceSettingsSupabase(
  companyId: string,
  input: {
    prixMinFixeGeneral: number | null;
    prixMinTauxGeneral: number | null;
    pourcentagePercuGeneral?: number | null;
  },
): Promise<CompanyColisSettings> {
  const { data, error } = await supabase.rpc("update_company_colis_price_settings", {
    p_company_id: companyId,
    p_prix_min_fixe_general: input.prixMinFixeGeneral,
    p_prix_min_taux_general: input.prixMinTauxGeneral,
    p_pourcentage_percu_general: input.pourcentagePercuGeneral ?? null,
  });
  if (error) throw error;
  return mapSettings((data ?? {}) as Record<string, unknown>);
}

/** Calcule (côté serveur) le prix minimum requis pour un envoi donné — pour affichage indicatif avant enregistrement. */
export async function getColisPrixMinSupabase(
  companyId: string,
  natureIds: string[],
  poidsKg: number | null,
): Promise<number> {
  if (!natureIds.length) return 0;
  const { data, error } = await supabase.rpc("get_colis_prix_min", {
    p_company_id: companyId,
    p_nature_ids: natureIds,
    p_poids_kg: poidsKg ?? null,
  });
  if (error) throw error;
  return Number(data ?? 0);
}

export type ColisBusOption = {
  id: string;
  plateNumber: string;
  model: string;
};

/** Bus actifs de la compagnie, pour le sélecteur "bus du convoi" (chargement colis). */
export async function listCompanyBusesSupabase(companyId: string): Promise<ColisBusOption[]> {
  const { data, error } = await supabase
    .from("Bus")
    .select("id, model, registrationNumber")
    .eq("companyId", companyId)
    .eq("isActive", true)
    .order("registrationNumber");
  if (error) throw error;
  return (data ?? []).map((b) => ({
    id: String(b.id),
    plateNumber: String(b.registrationNumber ?? ""),
    model: b.model ? String(b.model) : "",
  }));
}

export async function listColisNaturesSupabase(companyId: string): Promise<ColisNature[]> {
  const { data, error } = await supabase
    .from("colis_natures")
    .select("id, libelle, is_active, created_at, prix_min_fixe, prix_min_taux")
    .eq("company_id", companyId)
    .order("libelle");
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: String(row.id),
    libelle: String(row.libelle),
    isActive: Boolean(row.is_active),
    createdAt: row.created_at ? String(row.created_at) : undefined,
    prixMinFixe: row.prix_min_fixe != null ? Number(row.prix_min_fixe) : null,
    prixMinTaux: row.prix_min_taux != null ? Number(row.prix_min_taux) : null,
  }));
}

export async function upsertColisNatureSupabase(
  companyId: string,
  libelle: string,
  natureId?: string,
  isActive = true,
  prixMinFixe?: number | null,
  prixMinTaux?: number | null,
): Promise<ColisNature> {
  const { data, error } = await supabase.rpc("upsert_colis_nature", {
    p_company_id: companyId,
    p_libelle: libelle.trim(),
    p_nature_id: natureId ?? null,
    p_is_active: isActive,
    p_prix_min_fixe: prixMinFixe ?? null,
    p_prix_min_taux: prixMinTaux ?? null,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id),
    libelle: String(row.libelle),
    isActive: Boolean(row.isActive),
    prixMinFixe: row.prixMinFixe != null ? Number(row.prixMinFixe) : null,
    prixMinTaux: row.prixMinTaux != null ? Number(row.prixMinTaux) : null,
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
  /** Valeur déclarée de la marchandise (XOF) — obligatoire, sert de base au remboursement en cas de perte. */
  valeurMarchandise: number;
  /** Pourcentage de la valeur marchandise utilisé pour calculer montantFret, si mode automatique. */
  pourcentagePercu?: number;
  /** Bus qui effectue le convoi, si déjà connu à l'enregistrement (optionnel). */
  busId?: string | null;
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
    p_valeur_marchandise: input.valeurMarchandise,
    p_pourcentage_percu: input.pourcentagePercu ?? null,
    p_bus_id: input.busId ?? null,
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
      skipReason:
        sms.skipReason === "admin_gate" || sms.skipReason === "owner_disabled"
          ? sms.skipReason
          : undefined,
    },
  };
}

export async function listColisAutonomesSupabase(
  companyId: string,
  statut?: ColisStatut | null,
  limit = 100,
): Promise<ColisAutonomeRow[]> {
  const { data, error } = await supabase.rpc("list_colis_autonomes", {
    p_company_id: companyId,
    p_statut: statut ?? null,
    p_limit: limit,
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
    companyPhone: row.companyPhone ? String(row.companyPhone) : null,
    gareDepartId: String(row.gareDepartId ?? ""),
    gareDestinationId: String(row.gareDestinationId ?? ""),
    gareDestinationPhone: row.gareDestinationPhone ? String(row.gareDestinationPhone) : null,
    sourceVente: String(row.sourceVente ?? "guichet_cash"),
    natureIds,
  };
}

export async function updateColisStatutSupabase(
  colisId: string,
  statut: ColisStatut,
  busId?: string | null,
): Promise<{ id: string; statutColis: ColisStatut; sms: ColisSmsPayload }> {
  const { data, error } = await supabase.rpc("update_colis_autonome_statut", {
    p_colis_id: colisId,
    p_new_statut: statut,
    p_bus_id: busId ?? null,
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
          ? sms.skipReason
          : undefined,
    },
  };
}

export async function resolveColisRetraitCodeSupabase(code: string): Promise<string | null> {
  const { data, error } = await supabase.rpc("resolve_colis_retrait_code", {
    p_code: code.trim(),
  });
  if (error) throw error;
  return data ? String(data) : null;
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
      skipReason:
        sms.skipReason === "admin_gate" || sms.skipReason === "owner_disabled"
          ? sms.skipReason
          : undefined,
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
    const message = detail ?? body.error ?? `Envoi SMS impossible (${response.status})`;
    console.error("[colis-sms-client] HTTP error", response.status, body);
    throw new Error(message);
  }

  const sent = Number(body.sent ?? 0);
  const failed = Number(body.failed ?? 0);
  if (sent === 0) {
    const detail = body.failures?.[0]?.error ?? body.error ?? "Aucun SMS délivré";
    console.error("[colis-sms-client] zero sent", body);
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
