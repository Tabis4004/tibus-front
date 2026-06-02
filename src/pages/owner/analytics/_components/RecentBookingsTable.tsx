import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";
import { TicketIcon } from "lucide-react";

function statusVariant(status: string) {
  switch (status) {
    case "confirmed":
    case "collected":
      return "default" as const;
    case "pending_payment":
      return "secondary" as const;
    case "cancelled":
      return "destructive" as const;
    default:
      return "secondary" as const;
  }
}

export default function RecentBookingsTable() {
  const { t } = useTranslation("analytics");
  const bookings = useQuery(api.analytics.getRecentBookings, {});

  if (bookings === undefined) {
    return (
      <Card>
        <CardHeader>
          <Skeleton className="h-5 w-40" />
        </CardHeader>
        <CardContent className="space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-12 w-full" />
          ))}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">{t("recent.title")}</CardTitle>
        <p className="text-xs text-muted-foreground">{t("recent.desc")}</p>
      </CardHeader>
      <CardContent>
        {bookings.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><TicketIcon /></EmptyMedia>
              <EmptyTitle>{t("recent.empty")}</EmptyTitle>
              <EmptyDescription>{t("recent.empty_desc", { defaultValue: "Bookings will appear here once customers start booking." })}</EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left">
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.passenger")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.route")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.bus")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.seller")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.amount")}</th>
                  <th className="pb-2 font-medium text-muted-foreground text-xs">{t("recent.status")}</th>
                </tr>
              </thead>
              <tbody>
                {bookings.map((b) => (
                  <tr key={b._id} className="border-b last:border-0 hover:bg-muted/30">
                    <td className="py-2.5 pr-3">
                      <div className="font-medium">{b.passengerName}</div>
                      <div className="text-xs text-muted-foreground">{b.bookingReference}</div>
                    </td>
                    <td className="py-2.5 pr-3 text-xs">
                      {b.originCity} → {b.destinationCity}
                    </td>
                    <td className="py-2.5 pr-3 text-xs">{b.busName}</td>
                    <td className="py-2.5 pr-3 text-xs">{b.sellerName ?? "—"}</td>
                    <td className="py-2.5 pr-3 font-medium">
                      {b.totalPrice.toLocaleString()} {b.currency}
                    </td>
                    <td className="py-2.5">
                      <Badge variant={statusVariant(b.status)} className="text-[10px]">
                        {b.status}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
