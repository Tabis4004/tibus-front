import { useCallback, useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { formatDistanceToNow } from "date-fns";
import { fr, enUS } from "date-fns/locale";
import {
  BellIcon,
  CheckCheckIcon,
  PackageIcon,
  PackageCheckIcon,
  TruckIcon,
  XCircleIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  countUnreadStaffNotificationsSupabase,
  listStaffNotificationsSupabase,
  markAllStaffNotificationsReadSupabase,
  markStaffNotificationReadSupabase,
  STAFF_NOTIFICATIONS_REFRESH_EVENT,
  STAFF_NOTIFICATION_LABELS,
  type StaffNotificationRow,
} from "@/lib/supabase/staff-notifications.ts";

const TYPE_ICONS: Record<string, typeof BellIcon> = {
  colis_vente: PackageIcon,
  colis_statut: TruckIcon,
  lot_charge: TruckIcon,
  lot_arrive: PackageCheckIcon,
  colis_annule: XCircleIcon,
};

const TYPE_COLORS: Record<string, string> = {
  colis_vente: "text-primary",
  colis_statut: "text-amber-600",
  lot_charge: "text-amber-600",
  lot_arrive: "text-green-600",
  colis_annule: "text-destructive",
};

/**
 * Cloche de notifications "métier" (ventes/statuts colis, lots, annulations)
 * pour les rôles staff d'une compagnie (owner, comptable_compagnie,
 * gerant_gare) — pendant côté web du bouton absent signalé par l'utilisateur,
 * en miroir du template SupabaseSuperAdminNotificationCenter.
 */
export default function SupabaseStaffNotificationCenter() {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [unreadCount, setUnreadCount] = useState(0);
  const [items, setItems] = useState<StaffNotificationRow[]>([]);

  const dateLocale = lng === "fr" ? fr : enUS;

  const refresh = useCallback(async () => {
    try {
      const [count, list] = await Promise.all([
        countUnreadStaffNotificationsSupabase(),
        listStaffNotificationsSupabase(20),
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
    void refresh();
  }, [refresh]);

  useEffect(() => {
    const onRefresh = () => {
      void refresh();
    };
    window.addEventListener(STAFF_NOTIFICATIONS_REFRESH_EVENT, onRefresh);
    const interval = window.setInterval(() => {
      void refresh();
    }, 60_000);
    return () => {
      window.removeEventListener(STAFF_NOTIFICATIONS_REFRESH_EVENT, onRefresh);
      window.clearInterval(interval);
    };
  }, [refresh]);

  useEffect(() => {
    if (open) void refresh();
  }, [open, refresh]);

  const handleMarkAllRead = async () => {
    await markAllStaffNotificationsReadSupabase();
    await refresh();
  };

  const handleClick = async (row: StaffNotificationRow) => {
    if (!row.isRead) {
      await markStaffNotificationReadSupabase(row.id);
      await refresh();
    }
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          className="relative cursor-pointer p-2 rounded-full hover:bg-muted transition-colors"
          aria-label={t("notifications.title")}
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
          <h3 className="font-semibold text-sm">{t("notifications.title")}</h3>
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
              {t("notifications.empty")}
            </div>
          ) : (
            <div>
              {items.map((row) => {
                const Icon = TYPE_ICONS[row.type] ?? BellIcon;
                const colorClass = TYPE_COLORS[row.type] ?? "text-muted-foreground";
                const label = STAFF_NOTIFICATION_LABELS[row.type] ?? row.title;

                return (
                  <button
                    key={row.id}
                    type="button"
                    className={`w-full text-left px-4 py-3 border-b last:border-b-0 hover:bg-muted/50 transition-colors cursor-pointer flex items-start gap-3 ${
                      !row.isRead ? "bg-primary/5" : ""
                    }`}
                    onClick={() => void handleClick(row)}
                  >
                    <div className={`mt-0.5 ${colorClass}`}>
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span
                          className={`text-xs font-semibold truncate ${!row.isRead ? "text-foreground" : "text-muted-foreground"}`}
                        >
                          {label}
                        </span>
                        {!row.isRead && (
                          <span className="w-2 h-2 rounded-full bg-primary flex-shrink-0" />
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground line-clamp-3 mt-0.5">
                        {row.message}
                      </p>
                      <p className="text-[10px] text-muted-foreground/60 mt-1">
                        {formatDistanceToNow(new Date(row.createdAt), {
                          addSuffix: true,
                          locale: dateLocale,
                        })}
                      </p>
                    </div>
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
