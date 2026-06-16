import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { formatDistanceToNow } from "date-fns";
import { fr, enUS } from "date-fns/locale";
import {
  ActivityIcon,
  AlertTriangleIcon,
  BellIcon,
  CheckCheckIcon,
  ShieldAlertIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  countUnreadSuperAdminNotificationsSupabase,
  listSuperAdminNotificationsSupabase,
  markAllSuperAdminNotificationsReadSupabase,
  markSuperAdminNotificationReadSupabase,
  SUPERADMIN_NOTIFICATIONS_REFRESH_EVENT,
  syncPlatformScalingAlertsSupabase,
  type SuperAdminNotificationRow,
  type SuperAdminNotificationSeverity,
} from "@/lib/supabase/superadmin-notifications.ts";

const SEVERITY_ICONS: Record<SuperAdminNotificationSeverity, typeof BellIcon> = {
  info: ActivityIcon,
  warning: AlertTriangleIcon,
  critical: ShieldAlertIcon,
};

const SEVERITY_COLORS: Record<SuperAdminNotificationSeverity, string> = {
  info: "text-primary",
  warning: "text-amber-600",
  critical: "text-destructive",
};

function resolveNotificationCopy(
  row: SuperAdminNotificationRow,
  t: (key: string, opts?: Record<string, unknown>) => string,
  tAdmin: (key: string, opts?: Record<string, unknown>) => string,
): { title: string; message: string } {
  const kind = row.metadata?.kind;
  if (kind === "tier_changed") {
    const previousTier = String(row.metadata?.previousTier ?? "");
    const newTier = String(row.metadata?.newTier ?? "");
    return {
      title: t("superadmin_notifications.tier_changed_title"),
      message: t("superadmin_notifications.tier_changed_message", {
        previous: tAdmin(`scaling_metrics.tiers.${previousTier}`, { defaultValue: previousTier }),
        next: tAdmin(`scaling_metrics.tiers.${newTier}`, { defaultValue: newTier }),
      }),
    };
  }
  if (kind === "threshold_warning") {
    const metric = String(row.metadata?.metric ?? "");
    const value = row.metadata?.value;
    const max = row.metadata?.max;
    return {
      title: t(`superadmin_notifications.threshold_${metric}_title`, {
        defaultValue: row.title,
      }),
      message: t(`superadmin_notifications.threshold_${metric}_message`, {
        value,
        max,
        defaultValue: row.message,
      }),
    };
  }
  return { title: row.title, message: row.message };
}

export default function SupabaseSuperAdminNotificationCenter() {
  const { t } = useTranslation("common");
  const { t: tAdmin } = useTranslation("admin");
  const { lng } = useParams<{ lng: string }>();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [unreadCount, setUnreadCount] = useState(0);
  const [items, setItems] = useState<SuperAdminNotificationRow[]>([]);

  const dateLocale = lng === "fr" ? fr : enUS;

  const refresh = useCallback(async () => {
    try {
      const [count, list] = await Promise.all([
        countUnreadSuperAdminNotificationsSupabase(),
        listSuperAdminNotificationsSupabase(20),
      ]);
      setUnreadCount(count);
      setItems(list);
    } catch {
      setUnreadCount(0);
      setItems([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void syncPlatformScalingAlertsSupabase()
      .catch(() => undefined)
      .finally(() => {
        void refresh();
      });
  }, [refresh]);

  useEffect(() => {
    const onRefresh = () => {
      void refresh();
    };
    window.addEventListener(SUPERADMIN_NOTIFICATIONS_REFRESH_EVENT, onRefresh);
    const interval = window.setInterval(() => {
      void refresh();
    }, 120_000);
    return () => {
      window.removeEventListener(SUPERADMIN_NOTIFICATIONS_REFRESH_EVENT, onRefresh);
      window.clearInterval(interval);
    };
  }, [refresh]);

  useEffect(() => {
    if (open) void refresh();
  }, [open, refresh]);

  const handleMarkAllRead = async () => {
    await markAllSuperAdminNotificationsReadSupabase();
    await refresh();
  };

  const handleClick = async (row: SuperAdminNotificationRow) => {
    if (!row.isRead) {
      await markSuperAdminNotificationReadSupabase(row.id);
      await refresh();
    }
    if (row.actionTab) {
      setOpen(false);
    }
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          className="relative cursor-pointer p-2 rounded-full hover:bg-muted transition-colors"
          aria-label={t("superadmin_notifications.title")}
        >
          <BellIcon className="w-5 h-5 text-muted-foreground" />
          {unreadCount > 0 && (
            <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] flex items-center justify-center rounded-full bg-destructive text-destructive-foreground text-[10px] font-bold px-1">
              {unreadCount > 99 ? "99+" : unreadCount}
            </span>
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80 sm:w-96 p-0 max-h-[70vh] flex flex-col">
        <div className="flex items-center justify-between px-4 py-3 border-b">
          <h3 className="font-semibold text-sm">{t("superadmin_notifications.title")}</h3>
          {unreadCount > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="text-xs h-7 cursor-pointer gap-1"
              onClick={() => void handleMarkAllRead()}
            >
              <CheckCheckIcon className="w-3.5 h-3.5" />
              {t("notifications.mark_all_read")}
            </Button>
          )}
        </div>

        <div className="px-4 py-2 border-b bg-muted/30 text-xs text-muted-foreground">
          {t("superadmin_notifications.hint")}
        </div>

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-4 space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-14 w-full" />
              ))}
            </div>
          ) : items.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground text-sm">
              <BellIcon className="w-8 h-8 mx-auto mb-2 opacity-40" />
              {t("superadmin_notifications.empty")}
            </div>
          ) : (
            <div>
              {items.map((row) => {
                const Icon = SEVERITY_ICONS[row.severity] ?? BellIcon;
                const colorClass = SEVERITY_COLORS[row.severity] ?? "text-muted-foreground";
                const copy = resolveNotificationCopy(row, t, tAdmin);
                const href = row.actionTab
                  ? `/${lng ?? "fr"}/admin?tab=${encodeURIComponent(row.actionTab)}`
                  : undefined;

                const content = (
                  <>
                    <div className={`mt-0.5 ${colorClass}`}>
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span
                          className={`text-xs font-semibold truncate ${!row.isRead ? "text-foreground" : "text-muted-foreground"}`}
                        >
                          {copy.title}
                        </span>
                        {!row.isRead && (
                          <span className="w-2 h-2 rounded-full bg-primary flex-shrink-0" />
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground line-clamp-3 mt-0.5">
                        {copy.message}
                      </p>
                      <p className="text-[10px] text-muted-foreground/60 mt-1">
                        {formatDistanceToNow(new Date(row.createdAt), {
                          addSuffix: true,
                          locale: dateLocale,
                        })}
                      </p>
                    </div>
                  </>
                );

                if (href) {
                  return (
                    <Link
                      key={row.id}
                      to={href}
                      className={`w-full text-left px-4 py-3 border-b last:border-b-0 hover:bg-muted/50 transition-colors flex items-start gap-3 ${
                        !row.isRead ? "bg-primary/5" : ""
                      }`}
                      onClick={() => void handleClick(row)}
                    >
                      {content}
                    </Link>
                  );
                }

                return (
                  <button
                    key={row.id}
                    type="button"
                    className={`w-full text-left px-4 py-3 border-b last:border-b-0 hover:bg-muted/50 transition-colors cursor-pointer flex items-start gap-3 ${
                      !row.isRead ? "bg-primary/5" : ""
                    }`}
                    onClick={() => void handleClick(row)}
                  >
                    {content}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}
