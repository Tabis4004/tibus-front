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

function mapAuditRow(row: Record<string, unknown>): PlatformAuditLogRow {
  return {
    id: row.id as string,
    moduleKey: row.moduleKey as string,
    action: row.action as string,
    summary: row.summary as string,
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
    actorName: (row.actorName as string | null) ?? null,
    actorEmail: (row.actorEmail as string | null) ?? null,
    createdAt: row.createdAt as string,
  };
}

function mapAuditRowFromJoin(row: Record<string, unknown>): PlatformAuditLogRow {
  const user = row.Users as
    | { firstName?: string | null; lastName?: string | null; email?: string | null }
    | { firstName?: string | null; lastName?: string | null; email?: string | null }[]
    | null
    | undefined;
  const actor = Array.isArray(user) ? user[0] : user;
  const actorName = actor
    ? [actor.firstName, actor.lastName].filter(Boolean).join(" ").trim() || null
    : null;

  return {
    id: row.id as string,
    moduleKey: row.moduleKey as string,
    action: row.action as string,
    summary: row.summary as string,
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
    actorName,
    actorEmail: (actor?.email as string | null) ?? null,
    createdAt: row.createdAt as string,
  };
}

async function listPlatformAuditLogsByPrefixSupabase(
  prefix: string,
  limit = 15,
): Promise<PlatformAuditLogRow[]> {
  const capped = Math.min(Math.max(limit, 1), 50);
  const withActor = await supabase
    .from("PlatformAuditLogs")
    .select("id, moduleKey, action, summary, metadata, createdAt, Users(firstName, lastName, email)")
    .like("moduleKey", `${prefix}%`)
    .order("createdAt", { ascending: false })
    .limit(capped);

  if (!withActor.error) {
    return (withActor.data ?? []).map((row) => mapAuditRowFromJoin(row as Record<string, unknown>));
  }

  const plain = await supabase
    .from("PlatformAuditLogs")
    .select("id, moduleKey, action, summary, metadata, createdAt")
    .like("moduleKey", `${prefix}%`)
    .order("createdAt", { ascending: false })
    .limit(capped);

  if (plain.error) throw withActor.error ?? plain.error;

  return (plain.data ?? []).map((row) => ({
    id: row.id as string,
    moduleKey: row.moduleKey as string,
    action: row.action as string,
    summary: row.summary as string,
    metadata: (row.metadata as Record<string, unknown> | null) ?? null,
    actorName: null,
    actorEmail: null,
    createdAt: row.createdAt as string,
  }));
}

export async function listPlatformAuditLogsSupabase(
  moduleKey: string,
  limit = 15,
): Promise<PlatformAuditLogRow[]> {
  if (moduleKey.endsWith(".*")) {
    return listPlatformAuditLogsByPrefixSupabase(moduleKey.slice(0, -2), limit);
  }

  const { data, error } = await supabase.rpc("list_platform_audit_logs", {
    p_module_key: moduleKey,
    p_limit: limit,
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => mapAuditRow(row));
}
