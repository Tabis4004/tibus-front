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
import { auditModuleKeyMatchesFilter } from "./admin-audit-module-keys.ts";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
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
  scopeLabel,
  className,
  compact = false,
}: {
  moduleKey: string;
  scopeLabel?: string;
  className?: string;
  compact?: boolean;
}) {
  const { t } = useTranslation("admin");
  const appUser = useAppUser();
  const canView =
    hasPlatformScope(appUser.roles, appUser.isSuperAdmin) ||
    appUser.isSuperAdmin ||
    appUser.roles.includes("admin_pays");
  const isPrefixFilter = moduleKey.endsWith(".*");
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
      if (detail?.moduleKey && auditModuleKeyMatchesFilter(moduleKey, detail.moduleKey)) {
        void load(true);
      }
    };
    window.addEventListener(PLATFORM_AUDIT_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(PLATFORM_AUDIT_REFRESH_EVENT, onRefresh);
  }, [load, moduleKey]);

  if (!canView) return null;

  const scopeText = scopeLabel
    ? t(`tabs.${scopeLabel}`, { defaultValue: scopeLabel })
    : moduleKey.replace(/^admin\./, "").replace(/\.\*$/, "");

  const body = (
    <>
      {rows === undefined ? (
        <Skeleton className="h-14 w-full" />
      ) : error ? (
        <div className="space-y-1 text-xs text-muted-foreground">
          <p>
            {t("audit_hub.unavailable", {
              defaultValue: "Journal indisponible. Appliquez le script 061_platform_audit_log.sql.",
            })}
          </p>
          <p className="text-destructive break-words">{error}</p>
          {appUser.isAdminSandbox && (
            <p className="text-amber-600">
              {t("audit_hub.sandbox_db_role", {
                defaultValue:
                  "Le mode sandbox admin est UI seulement : votre compte doit aussi avoir un rôle plateforme en base (super_admin, admin_pays…).",
              })}
            </p>
          )}
        </div>
      ) : rows.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          {t("audit_hub.empty", {
            defaultValue: "Aucune action enregistrée pour cette page. Les modifications apparaîtront ici.",
          })}
        </p>
      ) : (
        <ul className="divide-y rounded-md border bg-background/60 max-h-72 overflow-y-auto">
          {rows.map((row) => (
            <li key={row.id} className="px-3 py-2 text-xs space-y-0.5">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="outline" className="text-[10px] h-5">
                  {ACTION_LABELS[row.action] ?? row.action}
                </Badge>
                {isPrefixFilter && (
                  <Badge variant="secondary" className="text-[10px] h-5 font-normal">
                    {row.moduleKey.replace(/^admin\./, "")}
                  </Badge>
                )}
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
    </>
  );

  if (compact) {
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
        {body}
      </div>
    );
  }

  return (
    <Card className={cn("border-primary/20 shadow-sm", className)}>
      <CardHeader className="py-3 px-4">
        <div className="flex items-center justify-between gap-2">
          <CardTitle className="text-sm flex items-center gap-2">
            <HistoryIcon className="w-4 h-4 text-primary" />
            {t("audit_hub.title", { defaultValue: "Journal HUB" })}
            <Badge variant="secondary" className="text-[10px] font-normal">
              {scopeText}
            </Badge>
          </CardTitle>
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="h-7 px-2 cursor-pointer"
            onClick={() => void load(true)}
            disabled={refreshing || rows === undefined}
          >
            <RefreshCwIcon className={cn("w-3.5 h-3.5", refreshing && "animate-spin")} />
          </Button>
        </div>
        <p className="text-[11px] text-muted-foreground">
          {t("audit_hub.page_desc", {
            defaultValue: "Actions enregistrées sur cette page uniquement.",
          })}
        </p>
      </CardHeader>
      <CardContent className="px-4 pb-4 pt-0">{body}</CardContent>
    </Card>
  );
}
