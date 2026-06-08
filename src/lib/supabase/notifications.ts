import { supabase } from "@/lib/supabase";

export type SupabaseNotification = {
  id: string;
  type: string;
  title: string;
  message: string;
  isRead: boolean;
  metadata: Record<string, unknown> | null;
  createdAt: string;
};

function mapNotification(row: Record<string, unknown>): SupabaseNotification {
  return {
    id: String(row.id),
    type: String(row.type),
    title: String(row.title),
    message: String(row.message),
    isRead: Boolean(row.is_read ?? row.isRead),
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
    createdAt: String(row.created_at ?? row.createdAt ?? ""),
  };
}

export async function listUserNotificationsSupabase(
  limit = 20,
  offset = 0,
): Promise<SupabaseNotification[]> {
  const { data, error } = await supabase.rpc("list_user_notifications", {
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map(mapNotification);
}

export async function getNotificationUnreadCountSupabase(): Promise<number> {
  const { data, error } = await supabase.rpc("get_notification_unread_count");
  if (error) throw error;
  return Number(data ?? 0);
}

export async function markNotificationReadSupabase(notificationId: string): Promise<void> {
  const { error } = await supabase.rpc("mark_notification_read", {
    p_notification_id: notificationId,
  });
  if (error) throw error;
}

export async function markAllNotificationsReadSupabase(): Promise<void> {
  const { error } = await supabase.rpc("mark_all_notifications_read");
  if (error) throw error;
}
