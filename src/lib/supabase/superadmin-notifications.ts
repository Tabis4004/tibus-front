import { supabase } from "@/lib/supabase";

export type SuperAdminNotificationSeverity = "info" | "warning" | "critical";

export type SuperAdminNotificationRow = {
  id: string;
  category: string;
  severity: SuperAdminNotificationSeverity;
  title: string;
  message: string;
  actionTab: string | null;
  metadata: Record<string, unknown> | null;
  isRead: boolean;
  createdAt: string;
};

export const SUPERADMIN_NOTIFICATIONS_REFRESH_EVENT =
  "tibus:superadmin-notifications-refresh";

export function refreshSuperAdminNotificationsHub() {
  window.dispatchEvent(new CustomEvent(SUPERADMIN_NOTIFICATIONS_REFRESH_EVENT));
}

function mapRow(row: Record<string, unknown>): SuperAdminNotificationRow {
  const severity = row.severity;
  const allowed: SuperAdminNotificationSeverity[] = ["info", "warning", "critical"];
  return {
    id: row.id as string,
    category: String(row.category ?? "scaling"),
    severity:
      typeof severity === "string" && allowed.includes(severity as SuperAdminNotificationSeverity)
        ? (severity as SuperAdminNotificationSeverity)
        : "info",
    title: String(row.title ?? ""),
    message: String(row.message ?? ""),
    actionTab: (row.actionTab as string | null) ?? null,
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
    isRead: Boolean(row.isRead),
    createdAt: String(row.createdAt ?? new Date().toISOString()),
  };
}

export async function countUnreadSuperAdminNotificationsSupabase(): Promise<number> {
  const { data, error } = await supabase.rpc("count_unread_superadmin_notifications");
  if (error) throw error;
  return typeof data === "number" ? data : Number(data ?? 0);
}

export async function listSuperAdminNotificationsSupabase(
  limit = 20,
): Promise<SuperAdminNotificationRow[]> {
  const { data, error } = await supabase.rpc("list_superadmin_notifications", {
    p_limit: limit,
  });
  if (error) throw error;
  return (data ?? []).map((row: Record<string, unknown>) => mapRow(row));
}

export async function markSuperAdminNotificationReadSupabase(id: string): Promise<void> {
  const { error } = await supabase.rpc("mark_superadmin_notification_read", {
    p_notification_id: id,
  });
  if (error) throw error;
  refreshSuperAdminNotificationsHub();
}

export async function markAllSuperAdminNotificationsReadSupabase(): Promise<void> {
  const { error } = await supabase.rpc("mark_all_superadmin_notifications_read");
  if (error) throw error;
  refreshSuperAdminNotificationsHub();
}

export async function syncPlatformScalingAlertsSupabase(): Promise<void> {
  const { error } = await supabase.rpc("sync_platform_scaling_notifications");
  if (error) throw error;
  refreshSuperAdminNotificationsHub();
}
