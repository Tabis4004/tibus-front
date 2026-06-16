import { usePaginatedQuery, useMutation, useQuery, useConvexAuth } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { BellIcon, BellOffIcon, BellRingIcon, CheckCheckIcon, TicketIcon, XCircleIcon, AlertTriangleIcon, BusIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useTranslation } from "react-i18next";
import { formatDistanceToNow } from "date-fns";
import { fr, enUS } from "date-fns/locale";
import { useParams } from "react-router-dom";
import { useState } from "react";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { usePushNotifications } from "@/hooks/use-push-notifications.ts";
import { toast } from "sonner";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useAppUser } from "@/hooks/use-app-user.ts";
import SupabaseSuperAdminNotificationCenter from "./SupabaseSuperAdminNotificationCenter.tsx";

const NOTIFICATION_ICONS: Record<string, typeof BellIcon> = {
  booking_confirmed: TicketIcon,
  booking_cancelled: XCircleIcon,
  new_booking: TicketIcon,
  trip_reminder: BusIcon,
  trip_cancelled: AlertTriangleIcon,
};

const NOTIFICATION_COLORS: Record<string, string> = {
  booking_confirmed: "text-green-600",
  booking_cancelled: "text-destructive",
  new_booking: "text-primary",
  trip_reminder: "text-amber-600",
  trip_cancelled: "text-amber-600",
};

export default function NotificationCenter() {
  const appUser = useAppUser();

  if (isSupabaseAuth()) {
    if (appUser.isReady && appUser.isSuperAdmin) {
      return <SupabaseSuperAdminNotificationCenter />;
    }
    return null;
  }

  return <ConvexNotificationCenter />;
}

function ConvexNotificationCenter() {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const [open, setOpen] = useState(false);
  const { isAuthenticated } = useConvexAuth();

  const unreadCount = useQuery(api.notifications.unreadCount);
  const { results, status, loadMore } = usePaginatedQuery(
    api.notifications.list,
    {},
    { initialNumItems: 10 }
  );
  const markAsRead = useMutation(api.notifications.markAsRead);
  const markAllAsRead = useMutation(api.notifications.markAllAsRead);
  const { status: pushStatus, subscribe, unsubscribe } = usePushNotifications(isAuthenticated);

  const dateLocale = lng === "fr" ? fr : enUS;

  const handleMarkAllRead = async () => {
    await markAllAsRead();
  };

  const handleNotificationClick = async (notificationId: Id<"notifications">, isRead: boolean) => {
    if (!isRead) {
      await markAsRead({ notificationId });
    }
  };

  const handlePushToggle = async () => {
    if (pushStatus === "subscribed") {
      const result = await unsubscribe();
      if ("success" in result) {
        toast.success(t("notifications.push_disabled"));
      }
    } else if (pushStatus === "unsubscribed") {
      const result = await subscribe();
      if (result && "subscribed" in result && result.subscribed) {
        toast.success(t("notifications.push_enabled"));
      }
    }
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button className="relative cursor-pointer p-2 rounded-full hover:bg-muted transition-colors">
          <BellIcon className="w-5 h-5 text-muted-foreground" />
          {(unreadCount ?? 0) > 0 && (
            <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] flex items-center justify-center rounded-full bg-destructive text-destructive-foreground text-[10px] font-bold px-1">
              {unreadCount && unreadCount > 99 ? "99+" : unreadCount}
            </span>
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80 sm:w-96 p-0 max-h-[70vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b">
          <h3 className="font-semibold text-sm">
            {t("notifications.title")}
          </h3>
          {(unreadCount ?? 0) > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="text-xs h-7 cursor-pointer gap-1"
              onClick={handleMarkAllRead}
            >
              <CheckCheckIcon className="w-3.5 h-3.5" />
              {t("notifications.mark_all_read")}
            </Button>
          )}
        </div>

        {/* Push notification toggle */}
        {pushStatus !== "unsupported" && pushStatus !== "iframe" && (
          <div className="px-4 py-2 border-b bg-muted/30 flex items-center justify-between">
            <span className="text-xs text-muted-foreground flex items-center gap-1.5">
              {pushStatus === "subscribed" ? (
                <BellRingIcon className="w-3.5 h-3.5 text-primary" />
              ) : (
                <BellOffIcon className="w-3.5 h-3.5" />
              )}
              {pushStatus === "subscribed"
                ? t("notifications.disable_push")
                : pushStatus === "denied"
                  ? t("notifications.push_denied")
                  : t("notifications.enable_push")}
            </span>
            {pushStatus !== "denied" && (
              <Button
                variant="ghost"
                size="sm"
                className="h-6 text-[11px] px-2 cursor-pointer"
                onClick={handlePushToggle}
                disabled={pushStatus === "loading"}
              >
                {pushStatus === "subscribed" ? "Off" : "On"}
              </Button>
            )}
          </div>
        )}

        {/* List */}
        <div className="flex-1 overflow-y-auto">
          {results === undefined ? (
            <div className="p-4 space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-14 w-full" />
              ))}
            </div>
          ) : results.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground text-sm">
              <BellIcon className="w-8 h-8 mx-auto mb-2 opacity-40" />
              {t("notifications.empty")}
            </div>
          ) : (
            <div>
              {results.map((notification) => {
                const Icon = NOTIFICATION_ICONS[notification.type] ?? BellIcon;
                const colorClass = NOTIFICATION_COLORS[notification.type] ?? "text-muted-foreground";

                return (
                  <button
                    key={notification._id}
                    className={`w-full text-left px-4 py-3 border-b last:border-b-0 hover:bg-muted/50 transition-colors cursor-pointer flex items-start gap-3 ${
                      !notification.isRead ? "bg-primary/5" : ""
                    }`}
                    onClick={() => handleNotificationClick(notification._id, notification.isRead)}
                  >
                    <div className={`mt-0.5 ${colorClass}`}>
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className={`text-xs font-semibold truncate ${!notification.isRead ? "text-foreground" : "text-muted-foreground"}`}>
                          {notification.title}
                        </span>
                        {!notification.isRead && (
                          <span className="w-2 h-2 rounded-full bg-primary flex-shrink-0" />
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground line-clamp-2 mt-0.5">
                        {notification.message}
                      </p>
                      <p className="text-[10px] text-muted-foreground/60 mt-1">
                        {formatDistanceToNow(new Date(notification._creationTime), {
                          addSuffix: true,
                          locale: dateLocale,
                        })}
                      </p>
                    </div>
                  </button>
                );
              })}

              {status === "CanLoadMore" && (
                <div className="p-3 text-center">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-xs cursor-pointer"
                    onClick={() => loadMore(10)}
                  >
                    {t("buttons.load_more")}
                  </Button>
                </div>
              )}
            </div>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}
