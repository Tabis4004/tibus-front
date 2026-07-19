import { supabase } from "@/lib/supabase";

/**
 * Versionnage léger des suppressions destructives (wipe_company_operations,
 * cancel_colis_autonome) — voir migration 188/189. Ce projet Supabase est
 * sur le plan free (pas de sauvegarde automatique / PITR), donc cette table
 * d'archive est le seul filet de sécurité disponible en cas de suppression
 * par erreur. Réservé au super admin.
 */
export type ArchivedOperation = {
  id: string;
  tableName: string;
  recordId: string;
  companyId: string | null;
  companyName: string | null;
  payload: Record<string, unknown>;
  deletedVia: string;
  deletedAt: string;
  deletedByName: string | null;
  restoredAt: string | null;
  restoredByName: string | null;
};

export async function listArchivedOperationsSupabase(options?: {
  companyId?: string | null;
  tableName?: string | null;
  limit?: number;
}): Promise<ArchivedOperation[]> {
  const { data, error } = await supabase.rpc("list_archived_operations", {
    p_company_id: options?.companyId ?? null,
    p_table_name: options?.tableName ?? null,
    p_limit: options?.limit ?? 200,
  });
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  return rows
    .filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === "object")
    .map((row) => ({
      id: String(row.id),
      tableName: String(row.tableName ?? ""),
      recordId: String(row.recordId ?? ""),
      companyId: row.companyId ? String(row.companyId) : null,
      companyName: row.companyName ? String(row.companyName) : null,
      payload: (row.payload ?? {}) as Record<string, unknown>,
      deletedVia: String(row.deletedVia ?? ""),
      deletedAt: String(row.deletedAt ?? ""),
      deletedByName: row.deletedByName ? String(row.deletedByName) : null,
      restoredAt: row.restoredAt ? String(row.restoredAt) : null,
      restoredByName: row.restoredByName ? String(row.restoredByName) : null,
    }));
}

export async function restoreArchivedRecordSupabase(
  archiveId: string,
): Promise<{ id: string; tableName: string; recordId: string }> {
  const { data, error } = await supabase.rpc("restore_archived_record", {
    p_archive_id: archiveId,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    id: String(row.id ?? archiveId),
    tableName: String(row.tableName ?? ""),
    recordId: String(row.recordId ?? ""),
  };
}

/** Petit résumé lisible du contenu archivé, pour affichage dans la liste — sans avoir à tout dérouler le JSON. */
export function summarizeArchivedPayload(row: ArchivedOperation): string {
  const p = row.payload;
  switch (row.tableName) {
    case "colis_autonomes":
      return `${p.nom_expediteur ?? "?"} → ${p.nom_destinataire ?? "?"} · ${p.montant_fret ?? 0} XOF`;
    case "mouvements_caisse":
      return `${p.type_mouvement ?? ""} · ${p.montant ?? 0}`;
    case "reversements_comptables":
      return `Reversement · ${p.montant ?? p.montant_declare ?? ""}`;
    case "Reservations":
      return `Réservation du ${p.date ?? ""}`;
    case "ReservationBus":
      return `Billet · place ${p.seatNumber ?? p.numeroSiege ?? "?"}`;
    case "ReservationBusColis":
      return `Colis lié à un billet`;
    case "bordereaux_livraison":
      return `Bordereau ${p.reference ?? p.numero_lot ?? ""}`;
    case "bordereau_colis":
      return `Colis dans un lot`;
    default:
      return row.tableName;
  }
}
