import { supabase } from "@/lib/supabase";

export type PlatformAuditLogRow = {
  id: string;
  moduleKey: string;
  action: string;
  summary: string;
  metadata: Record<string, unknown> | null;
  actorName: string | null;
  actorEmail: string | null;
  createdAt: string;
};

export const PLATFORM_AUDIT_REFRESH_EVENT = "tibus:platform-audit-refresh";

export function refreshPlatformAuditHub(moduleKey: string) {
  window.dispatchEvent(
    new CustomEvent(PLATFORM_AUDIT_REFRESH_EVENT, { detail: { moduleKey } }),
  );
}

export async function recordPlatformAuditSupabase(input: {
  moduleKey: string;
  action: "create" | "update" | "delete" | "assign" | "toggle";
  summary: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  try {
    const { error } = await supabase.rpc("log_platform_audit", {
      p_module_key: input.moduleKey,
      p_action: input.action,
      p_summary: input.summary.slice(0, 500),
      p_metadata: input.metadata ?? {},
    });
    if (error) throw error;
    refreshPlatformAuditHub(input.moduleKey);
  } catch {
    // Migration SQL may not be applied yet — do not block CRUD flows.
  }
}

export async function listPlatformAuditLogsSupabase(
  moduleKey: string,
  limit = 15,
): Promise<PlatformAuditLogRow[]> {
  const { data, error } = await supabase.rpc("list_platform_audit_logs", {
    p_module_key: moduleKey,
    p_limit: limit,
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: row.id as string,
    moduleKey: row.moduleKey as string,
    action: row.action as string,
    summary: row.summary as string,
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
    actorName: (row.actorName as string | null) ?? null,
    actorEmail: (row.actorEmail as string | null) ?? null,
    createdAt: row.createdAt as string,
  }));
}
