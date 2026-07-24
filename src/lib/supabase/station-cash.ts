import { supabase } from "@/lib/supabase";

export type StationCashStatus = "ouverte" | "en_reversement" | "cloturee";

export type StationCashMovementType =
  | "encaissement_billet"
  | "encaissement_colis"
  | "decaissement_annulation"
  | "reversement_comptable";

export type ReversalStatus = "en_attente" | "approuve_recu";

export type OpenStationCash = {
  open: boolean;
  pendingReversal?: boolean;
  id?: string;
  gareId?: string;
  gareName?: string;
  sessionLabel?: string;
  balance?: number;
  openingFloat?: number;
  openedAt?: string;
  status?: StationCashStatus;
  companyId?: string;
};

export type StationCashMovement = {
  id: string;
  createdAt: string;
  type: StationCashMovementType;
  amount: number;
  balanceAfter: number;
  ticketId: string | null;
  colisId: string | null;
  authorName: string | null;
  note: string | null;
};

export type StationGareOption = {
  id: string;
  name: string;
};

export type CompanyOpenStationCash = {
  id: string;
  gareId: string;
  gareName: string;
  balance: number;
  openingFloat: number;
  openedAt: string;
  cashierId: string;
  cashierName: string | null;
};

export type StationCashReversal = {
  id: string;
  createdAt: string;
  validatedAt: string | null;
  amount: number;
  status: ReversalStatus;
  caisseId: string;
  gareId: string | null;
  gareName: string;
  cashierName: string | null;
  caisseBalance: number;
  submittedByName: string | null;
  accountantName: string | null;
};

export const STATION_CASH_MOVEMENT_LABELS: Record<StationCashMovementType, string> = {
  encaissement_billet: "Encaissement guichet",
  encaissement_colis: "Encaissement guichet",
  decaissement_annulation: "Décaissement annulation",
  reversement_comptable: "Reversement comptable",
};

export const REVERSAL_STATUS_LABELS: Record<ReversalStatus, string> = {
  en_attente: "En attente",
  approuve_recu: "Approuvé / reçu",
};

function num(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

export async function getOpenStationCashSupabase(
  gareId?: string | null,
): Promise<OpenStationCash> {
  const { data, error } = await supabase.rpc("get_open_station_cash_for_user", {
    p_gare_id: gareId ?? null,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    open: Boolean(row.open),
    pendingReversal: Boolean(row.pendingReversal),
    id: row.id ? String(row.id) : undefined,
    gareId: row.gareId ? String(row.gareId) : undefined,
    gareName: row.gareName ? String(row.gareName) : undefined,
    sessionLabel: row.sessionLabel ? String(row.sessionLabel) : undefined,
    balance: row.balance == null ? undefined : num(row.balance),
    openingFloat: row.openingFloat == null ? undefined : num(row.openingFloat),
    openedAt: row.openedAt ? String(row.openedAt) : undefined,
    status: row.status ? (String(row.status) as StationCashStatus) : undefined,
    companyId: row.companyId ? String(row.companyId) : undefined,
  };
}

export async function openStationCashRegisterSupabase(input: {
  companyId: string;
  gareId: string;
  openingFloat: number;
}): Promise<OpenStationCash> {
  const { data, error } = await supabase.rpc("open_station_cash_register", {
    p_gare_id: input.gareId,
    p_fond_roulement: Math.max(0, Math.round(input.openingFloat)),
    // Compagnie active du dashboard vendeur : indispensable pour un vendeur
    // multi-compagnies (sinon le serveur peut résoudre une autre compagnie).
    p_company_id: input.companyId,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  const sessionLabel = row.sessionLabel
    ? String(row.sessionLabel)
    : row.gareName
      ? String(row.gareName)
      : "Session caisse journalière";
  return {
    open: true,
    id: String(row.id),
    gareId: String(row.gareId),
    gareName: sessionLabel,
    sessionLabel,
    balance: num(row.balance),
    openingFloat: num(row.openingFloat),
    status: String(row.status) as StationCashStatus,
  };
}

export async function listStationCashMovementsSupabase(
  caisseId: string,
  limit = 100,
): Promise<StationCashMovement[]> {
  const { data, error } = await supabase.rpc("list_station_cash_movements", {
    p_caisse_id: caisseId,
    p_limit: limit,
    p_offset: 0,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    createdAt: String(row.created_at ?? row.createdAt ?? ""),
    type: String(row.type_mouvement) as StationCashMovementType,
    amount: num(row.montant),
    balanceAfter: num(row.solde_apres),
    ticketId: row.ticket_id ? String(row.ticket_id) : null,
    colisId: row.colis_id ? String(row.colis_id) : null,
    authorName: row.effectue_par_name ? String(row.effectue_par_name) : null,
    note: row.note ? String(row.note) : null,
  }));
}

export async function submitStationCashReversalSupabase(
  caisseId: string,
  amount: number,
): Promise<void> {
  const { error } = await supabase.rpc("submit_station_cash_reversal", {
    p_caisse_id: caisseId,
    p_montant_reverse: Math.max(1, Math.round(amount)),
  });
  if (error) throw error;
}

export async function validateStationCashReversalSupabase(
  reversalId: string,
): Promise<void> {
  const { error } = await supabase.rpc("validate_station_cash_reversal", {
    p_reversement_id: reversalId,
  });
  if (error) throw error;
}

// Clôture explicite de session, indépendante de la soumission/validation
// d'un reversement (voir migration separate_close_station_cash_from_validation) :
// soumettre un reversement ne bloque plus les ventes, la caisse reste
// ouverte jusqu'à un appel explicite ici. Même RPC partagée par
// courrier_mobile (close_station_cash_register) — un seul modèle de caisse
// pour toute la plateforme Tibus, billetterie comme colis.
export async function closeStationCashRegisterSupabase(
  caisseId: string,
): Promise<void> {
  const { error } = await supabase.rpc("close_station_cash_register", {
    p_caisse_id: caisseId,
  });
  if (error) throw error;
}

export async function listCompanyStationGaresSupabase(
  companyId: string,
): Promise<StationGareOption[]> {
  const { data, error } = await supabase.rpc("list_company_station_gares", {
    p_company_id: companyId,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[])
    .map((row) => ({
      id: String(row.id ?? row.Id ?? ""),
      name: String(row.name ?? row.Name ?? ""),
    }))
    .filter((row) => row.id && row.name && !row.name.startsWith("__"));
}

export async function listCompanyOpenStationCashSupabase(
  companyId: string,
): Promise<CompanyOpenStationCash[]> {
  const gares = await listCompanyStationGaresSupabase(companyId);
  if (!gares.length) return [];

  const gareById = new Map(gares.map((gare) => [gare.id, gare.name]));
  const { data, error } = await supabase
    .from("caisses_gares")
    .select("id, gare_id, gestionnaire_id, solde_especes_actuel, fond_roulement, opened_at, statut")
    .in("gare_id", gares.map((gare) => gare.id))
    .eq("statut", "ouverte")
    .order("opened_at", { ascending: false });

  if (error) throw error;

  const rows = (data ?? []) as Record<string, unknown>[];
  const cashierIds = [...new Set(rows.map((row) => String(row.gestionnaire_id)))];
  const cashierNames = new Map<string, string>();

  if (cashierIds.length) {
    const { data: users, error: usersError } = await supabase
      .from("users")
      .select("id, firstName, lastName, email")
      .in("id", cashierIds);
    if (!usersError && users) {
      for (const user of users as Record<string, unknown>[]) {
        const name =
          `${String(user.firstName ?? "")} ${String(user.lastName ?? "")}`.trim() ||
          String(user.email ?? "");
        if (name) cashierNames.set(String(user.id), name);
      }
    }
  }

  return rows.map((row) => {
    const gareId = String(row.gare_id);
    const cashierId = String(row.gestionnaire_id);
    return {
      id: String(row.id),
      gareId,
      gareName: gareById.get(gareId) ?? "Gare",
      balance: num(row.solde_especes_actuel),
      openingFloat: num(row.fond_roulement),
      openedAt: String(row.opened_at ?? ""),
      cashierId,
      cashierName: cashierNames.get(cashierId) ?? null,
    };
  });
}

export async function listCompanyStationCashReversalsSupabase(
  companyId: string,
  status?: ReversalStatus | null,
): Promise<StationCashReversal[]> {
  const { data, error } = await supabase.rpc("list_company_station_cash_reversals", {
    p_company_id: companyId,
    p_status: status ?? null,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    createdAt: String(row.created_at ?? row.createdAt ?? ""),
    validatedAt: row.validated_at ? String(row.validated_at) : null,
    amount: num(row.montant_reverse),
    status: String(row.statut_validation) as ReversalStatus,
    caisseId: String(row.caisse_id),
    gareId: row.gare_id ? String(row.gare_id) : null,
    gareName: String(row.gare_name ?? ""),
    cashierName: row.gestionnaire_name ? String(row.gestionnaire_name) : null,
    caisseBalance: num(row.solde_caisse),
    submittedByName: row.soumis_par_name ? String(row.soumis_par_name) : null,
    accountantName: row.comptable_name ? String(row.comptable_name) : null,
  }));
}
