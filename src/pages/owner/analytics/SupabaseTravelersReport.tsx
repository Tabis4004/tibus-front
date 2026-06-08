import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { format } from "date-fns";
import { UsersIcon } from "lucide-react";
import { Card, CardContent, CardHeader } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";
import {
  getOwnerTravelersSupabase,
  type OwnerTravelerReportRow,
} from "@/lib/supabase/owner-reports";

export default function SupabaseTravelersReport() {
  const { t } = useTranslation("analytics");
  const { appUserId } = useSupabaseAuth();
  const { companyId } = useOwnerCompany();
  const [travelers, setTravelers] = useState<OwnerTravelerReportRow[] | undefined>(undefined);
  const [search, setSearch] = useState("");

  useEffect(() => {
    if (!appUserId || !companyId) return;
    let cancelled = false;
    void getOwnerTravelersSupabase(appUserId, companyId)
      .then((rows) => {
        if (!cancelled) setTravelers(rows);
      })
      .catch(() => {
        if (!cancelled) setTravelers([]);
      });
    return () => {
      cancelled = true;
    };
  }, [appUserId, companyId]);

  useEffect(() => {
    if (!appUserId || !companyId) return;
    const onRefresh = () => {
      setTravelers(undefined);
      void getOwnerTravelersSupabase(appUserId, companyId).then(setTravelers).catch(() => setTravelers([]));
    };
    window.addEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
  }, [appUserId, companyId]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return travelers ?? [];
    return (travelers ?? []).filter(
      (row) =>
        row.name.toLowerCase().includes(q) ||
        (row.phone ?? "").includes(q) ||
        (row.email ?? "").toLowerCase().includes(q),
    );
  }, [travelers, search]);

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("report.travelers_title", { defaultValue: "Rapport voyageurs" })}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          {t("report.travelers_desc", { defaultValue: "Clients récurrents et dépenses." })}
        </p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <Input
            placeholder="Nom, téléphone, email..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </CardHeader>
        <CardContent>
          {travelers === undefined ? (
            <Skeleton className="h-48 w-full" />
          ) : filtered.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <UsersIcon />
                </EmptyMedia>
                <EmptyTitle>Aucun voyageur</EmptyTitle>
                <EmptyDescription>Les voyageurs apparaîtront après les ventes.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-2 px-2">Voyageur</th>
                    <th className="pb-2 px-2">Contact</th>
                    <th className="pb-2 px-2">Réservations</th>
                    <th className="pb-2 px-2">Total dépensé</th>
                    <th className="pb-2 px-2">Dernier trajet</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((row) => (
                    <tr key={row._id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="py-2 px-2 font-medium">{row.name}</td>
                      <td className="py-2 px-2 text-muted-foreground">
                        {row.phone ?? row.email ?? "—"}
                      </td>
                      <td className="py-2 px-2">{row.totalBookings}</td>
                      <td className="py-2 px-2 font-medium">
                        {row.totalSpent.toLocaleString()} {row.currency}
                      </td>
                      <td className="py-2 px-2">
                        {row.lastTripDate
                          ? format(new Date(row.lastTripDate), "dd/MM/yy")
                          : "—"}
                        {row.lastRoute && (
                          <div className="text-[10px] text-muted-foreground">{row.lastRoute}</div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
