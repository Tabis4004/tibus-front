import { useCallback, useEffect, useState } from "react";
import { format, parseISO } from "date-fns";
import { useTranslation } from "react-i18next";
import { HistoryIcon, RefreshCwIcon } from "lucide-react";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { hasPlatformScope } from "@/lib/auth/platform-scope.ts";
import {
  listPlatformAuditLogsSupabase,
  PLATFORM_AUDIT_REFRESH_EVENT,
  type PlatformAuditLogRow,
} from "@/lib/supabase/platform-audit-log.ts";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { cn } from "@/lib/utils.ts";

function fmtWhen(iso: string) {
  try {
    return format(parseISO(iso), "dd/MM/yyyy HH:mm");
  } catch {
    return iso;
  }
}

const ACTION_LABELS: Record<string, string> = {
  create: "Création",
  update: "Modification",
  delete: "Suppression",
  assign: "Attribution",
  toggle: "Bascule",
};

export default function AdminAuditHub({
  moduleKey,
  className,
}: {
  moduleKey: string;
  className?: string;
}) {
  const { t } = useTranslation("admin");
  const appUser = useAppUser();
  const canView = hasPlatformScope(appUser.roles, appUser.isSuperAdmin);
  const [rows, setRows] = useState<PlatformAuditLogRow[] | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(
    async (silent = false) => {
      if (!canView) return;
      if (!silent) setRows(undefined);
      else setRefreshing(true);
      setError(null);
      try {
        setRows(await listPlatformAuditLogsSupabase(moduleKey));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Erreur journal");
        setRows([]);
      } finally {
        setRefreshing(false);
      }
    },
    [canView, moduleKey],
  );

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const onRefresh = (event: Event) => {
      const detail = (event as CustomEvent<{ moduleKey?: string }>).detail;
      if (detail?.moduleKey === moduleKey) void load(true);
    };
    window.addEventListener(PLATFORM_AUDIT_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(PLATFORM_AUDIT_REFRESH_EVENT, onRefresh);
  }, [load, moduleKey]);

  if (!canView) return null;

  return (
    <div className={cn("rounded-lg border border-dashed bg-muted/20 p-3 space-y-2", className)}>
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          <HistoryIcon className="w-3.5 h-3.5" />
          {t("audit_hub.title", { defaultValue: "Journal HUB" })}
        </div>
        <Button
          type="button"
          size="sm"
          variant="ghost"
          className="h-7 px-2 cursor-pointer"
          onClick={() => void load(true)}
          disabled={refreshing || rows === undefined}
        >
          <RefreshCwIcon className={cn("w-3.5 h-3.5", refreshing && "animate-spin")} />
        </Button>
      </div>

      {rows === undefined ? (
        <Skeleton className="h-12 w-full" />
      ) : error ? (
        <p className="text-xs text-muted-foreground">
          {t("audit_hub.unavailable", {
            defaultValue: "Journal indisponible. Appliquez le script 061_platform_audit_log.sql.",
          })}{" "}
          <span className="text-destructive">{error}</span>
        </p>
      ) : rows.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          {t("audit_hub.empty", { defaultValue: "Aucune action enregistrée pour cette section." })}
        </p>
      ) : (
        <ul className="divide-y rounded-md border bg-background/60">
          {rows.map((row) => (
            <li key={row.id} className="px-3 py-2 text-xs space-y-0.5">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="outline" className="text-[10px] h-5">
                  {ACTION_LABELS[row.action] ?? row.action}
                </Badge>
                <span className="text-muted-foreground tabular-nums">{fmtWhen(row.createdAt)}</span>
              </div>
              <p className="text-foreground">{row.summary}</p>
              <p className="text-muted-foreground">
                {row.actorName ?? t("audit_hub.unknown_actor", { defaultValue: "Utilisateur" })}
                {row.actorEmail ? ` · ${row.actorEmail}` : ""}
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
