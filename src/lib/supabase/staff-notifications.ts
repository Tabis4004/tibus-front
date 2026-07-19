import { supabase } from "@/lib/supabase";

/**
 * Notifications "métier" (ventes de colis, changements de statut, lots
 * chargés/arrivés, annulations) pour les utilisateurs staff d'une compagnie
 * (owner, comptable_compagnie, gerant_gare). Alimentées par les RPC colis
 * (register_colis_autonome, update_colis_autonome_statut, mark_bordereau_*,
 * cancel_colis_autonome — migration 190) sur la table "Notifications"
 * générique, lues via les RPC list_my_notifications / count_unread_my_notifications
 * / mark_my_notification_read / mark_all_my_notifications_read (migration 191).
 */

export type StaffNotificationType =
  | "colis_vente"
  | "colis_statut"
  | "lot_charge"
  | "lot_arrive"
  | "colis_annule"
  | string;

export type StaffNotificationRow = {
  id: string;
  type: StaffNotificationType;
  title: string;
  message: string;
  isRead: boolean;
  metadata: Record<string, unknown> | null;
  createdAt: string;
};

export const STAFF_NOTIFICATIONS_REFRESH_EVENT = "tibus:staff-notifications-refresh";

export function refreshStaffNotificationsHub() {
  window.dispatchEvent(new CustomEvent(STAFF_NOTIFICATIONS_REFRESH_EVENT));
}

function mapRow(row: Record<string, unknown>): StaffNotificationRow {
  return {
    id: String(row.id ?? ""),
    type: String(row.type ?? ""),
    title: String(row.title ?? ""),
    message: String(row.message ?? ""),
    isRead: Boolean(row.isRead),
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
    createdAt: String(row.createdAt ?? new Date().toISOString()),
  };
}

export async function countUnreadStaffNotificationsSupabase(): Promise<number> {
  const { data, error } = await supabase.rpc("count_unread_my_notifications");
  if (error) throw error;
  return typeof data === "number" ? data : Number(data ?? 0);
}

export async function listStaffNotificationsSupabase(
  limit = 20,
): Promise<StaffNotificationRow[]> {
  const { data, error } = await supabase.rpc("list_my_notifications", { p_limit: limit });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map(mapRow);
}

export async function markStaffNotificationReadSupabase(id: string): Promise<void> {
  const { error } = await supabase.rpc("mark_my_notification_read", {
    p_notification_id: id,
  });
  if (error) throw error;
  refreshStaffNotificationsHub();
}

export async function markAllStaffNotificationsReadSupabase(): Promise<void> {
  const { error } = await supabase.rpc("mark_all_my_notifications_read");
  if (error) throw error;
  refreshStaffNotificationsHub();
}

export const STAFF_NOTIFICATION_LABELS: Record<string, string> = {
  colis_vente: "Nouveau colis",
  colis_statut: "Changement de statut",
  lot_charge: "Lot chargé",
  lot_arrive: "Lot arrivé",
  colis_annule: "Colis annulé",
};

/**
 * Déclenche (best-effort) le push FCM natif vers les destinataires déjà
 * calculés côté RPC (notifyRecipients/notifyTitle/notifyMessage — voir
 * register_colis_autonome / update_colis_autonome_statut / mark_bordereau_* /
 * cancel_colis_autonome, migration 190) via l'edge function send-staff-push.
 * N'échoue jamais bruyamment : l'in-app (table "Notifications", déjà écrite
 * par le RPC) reste la source de vérité même si le push natif ne part pas
 * (pas d'appareil enregistré, secret FCM absent, etc.).
 */
export async function triggerStaffPushSupabase(params: {
  companyId: string;
  userIds: string[];
  title: string;
  message: string;
  data?: Record<string, string>;
}): Promise<void> {
  if (!params.userIds.length) return;
  try {
    await supabase.functions.invoke("send-staff-push", {
      body: {
        companyId: params.companyId,
        userIds: params.userIds,
        title: params.title,
        message: params.message,
        data: params.data,
      },
    });
  } catch {
    // Best-effort — voir docstring.
  }
}
