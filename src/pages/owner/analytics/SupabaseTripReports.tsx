import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { format } from "date-fns";
import { BusIcon, FileSpreadsheetIcon, FileTextIcon, PackageIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";
import { errorMessage } from "@/lib/utils";
import {
  getOwnerTripReportSupabase,
  getTripManifestSupabase,
  type OwnerTripReport,
} from "@/lib/supabase/owner-reports";
import {
  exportTripManifestExcel,
  exportTripManifestPDF,
} from "@/lib/trip-manifest-export";
import {
  listColisAutonomesSupabase,
  COLIS_STATUT_LABELS,
  type ColisAutonomeRow,
  type ColisStatut,
} from "@/lib/supabase/colis-autonomes";
import {
  exportColisManifestExcel,
  exportColisManifestPDF,
} from "@/lib/colis-manifest-export";

const COLIS_STATUTS: ColisStatut[] = ["enregistre", "charge", "arrive", "livre"];

export default function SupabaseTripReports() {
  const { t } = useTranslation("analytics");
  const { appUserId } = useSupabaseAuth();
  const { companyId, selectedCompany } = useOwnerCompany();
  const [report, setReport] = useState<OwnerTripReport | undefined>(undefined);
  const [routeFilter, setRouteFilter] = useState("all");
  const [manifestBusyId, setManifestBusyId] = useState<string | null>(null);
  const [colisRows, setColisRows] = useState<ColisAutonomeRow[] | undefined>(undefined);
  const [colisStatutFilter, setColisStatutFilter] = useState<string>("all");
  const [colisGareFilter, setColisGareFilter] = useState<string>("all");
  const [colisGareDestFilter, setColisGareDestFilter] = useState<string>("all");
  const [colisDateFrom, setColisDateFrom] = useState<string>("");
  const [colisDateTo, setColisDateTo] = useState<string>("");
  // Ouverture directe de l'onglet colis via /owner/analytics/trips?tab=colis
  // (lien depuis la page Colis autonomes).
  const [searchParams] = useSearchParams();
  const initialTab = searchParams.get("tab") === "colis" ? "colis" : "trips";

  const loadReport = useCallback(() => {
    if (!appUserId || !companyId) return;
    setReport(undefined);
    void getOwnerTripReportSupabase(appUserId, companyId)
      .then(setReport)
      .catch(() =>
        setReport({
          trips: [],
          filters: { buses: [], routes: [], departureCities: [], departureStations: [] },
        }),
      );
  }, [appUserId, companyId]);

  const loadColis = useCallback(() => {
    if (!companyId) return;
    setColisRows(undefined);
    void listColisAutonomesSupabase(companyId, null, 500)
      .then(setColisRows)
      .catch((err) => {
        // Module colis désactivé ou droits insuffisants : liste vide, message discret.
        console.info("[colis-manifest]", errorMessage(err, "chargement impossible"));
        setColisRows([]);
      });
  }, [companyId]);

  useEffect(() => {
    loadReport();
    loadColis();
  }, [loadReport, loadColis]);

  useEffect(() => {
    const onRefresh = () => {
      loadReport();
      loadColis();
    };
    window.addEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
  }, [loadReport, loadColis]);

  const filteredTrips = useMemo(() => {
    const trips = report?.trips ?? [];
    if (routeFilter === "all") return trips;
    return trips.filter((trip) => trip.routeId === routeFilter);
  }, [report, routeFilter]);

  const totalRevenue = filteredTrips.reduce((sum, trip) => sum + trip.revenue, 0);

  const colisGares = useMemo(() => {
    const set = new Set<string>();
    for (const row of colisRows ?? []) {
      if (row.gareDepart) set.add(row.gareDepart);
    }
    return [...set].sort((a, b) => a.localeCompare(b, "fr"));
  }, [colisRows]);

  const colisGaresDest = useMemo(() => {
    const set = new Set<string>();
    for (const row of colisRows ?? []) {
      if (row.gareDestination) set.add(row.gareDestination);
    }
    return [...set].sort((a, b) => a.localeCompare(b, "fr"));
  }, [colisRows]);

  const filteredColis = useMemo(() => {
    let rows = colisRows ?? [];
    if (colisStatutFilter !== "all") {
      rows = rows.filter((row) => row.statutColis === colisStatutFilter);
    }
    if (colisGareFilter !== "all") {
      rows = rows.filter((row) => row.gareDepart === colisGareFilter);
    }
    if (colisGareDestFilter !== "all") {
      rows = rows.filter((row) => row.gareDestination === colisGareDestFilter);
    }
    if (colisDateFrom) {
      rows = rows.filter((row) => format(new Date(row.createdAt), "yyyy-MM-dd") >= colisDateFrom);
    }
    if (colisDateTo) {
      rows = rows.filter((row) => format(new Date(row.createdAt), "yyyy-MM-dd") <= colisDateTo);
    }
    return rows;
  }, [colisRows, colisStatutFilter, colisGareFilter, colisGareDestFilter, colisDateFrom, colisDateTo]);

  const totalFret = filteredColis.reduce((sum, row) => sum + row.montantFret, 0);

  const handleTripManifest = async (tripId: string, kind: "pdf" | "csv") => {
    if (!appUserId) return;
    setManifestBusyId(tripId);
    try {
      const manifest = await getTripManifestSupabase(tripId, appUserId);
      if (kind === "pdf") exportTripManifestPDF(manifest);
      else exportTripManifestExcel(manifest);
    } catch (err) {
      toast.error(errorMessage(err, t("report.manifest_error", { defaultValue: "Manifeste indisponible pour ce départ." })));
    } finally {
      setManifestBusyId(null);
    }
  };

  const colisFilterLabel = [
    colisStatutFilter === "all"
      ? "Tous les statuts"
      : COLIS_STATUT_LABELS[colisStatutFilter as ColisStatut],
    colisGareFilter === "all" ? "toutes gares de départ" : `départ ${colisGareFilter}`,
    colisGareDestFilter === "all" ? "toutes destinations" : `destination ${colisGareDestFilter}`,
    colisDateFrom || colisDateTo
      ? `du ${colisDateFrom ? format(new Date(colisDateFrom), "dd/MM/yyyy") : "…"} au ${colisDateTo ? format(new Date(colisDateTo), "dd/MM/yyyy") : "…"}`
      : "toutes dates",
  ].join(" · ");

  const handleColisManifest = (kind: "pdf" | "csv") => {
    if (!filteredColis.length) {
      toast.error(t("report.colis_empty", { defaultValue: "Aucun colis à imprimer avec ce filtre." }));
      return;
    }
    const meta = {
      companyName: selectedCompany?.name ?? "Compagnie",
      filterLabel: colisFilterLabel,
    };
    if (kind === "pdf") exportColisManifestPDF(filteredColis, meta);
    else exportColisManifestExcel(filteredColis, meta);
  };

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("report.trips_title", { defaultValue: "Rapport trajets" })}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          {t("report.trips_manifests_desc", {
            defaultValue: "Performance par départ, manifestes passagers et manifeste colis.",
          })}
        </p>
      </div>

      <Tabs defaultValue={initialTab}>
        <TabsList>
          <TabsTrigger value="trips">
            <BusIcon className="w-4 h-4 mr-1.5" />
            {t("report.tab_trips", { defaultValue: "Voyages" })}
          </TabsTrigger>
          <TabsTrigger value="colis">
            <PackageIcon className="w-4 h-4 mr-1.5" />
            {t("report.tab_colis", { defaultValue: "Colis autonomes" })}
          </TabsTrigger>
        </TabsList>

        {/* ── Manifestes voyages ─────────────────────────────────────── */}
        <TabsContent value="trips" className="space-y-4 mt-4">
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-muted-foreground">Départs</p>
                <p className="text-2xl font-bold">{filteredTrips.length}</p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-muted-foreground">Revenus</p>
                <p className="text-2xl font-bold">{totalRevenue.toLocaleString()}</p>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader className="pb-3">
              <Select value={routeFilter} onValueChange={setRouteFilter}>
                <SelectTrigger className="w-full sm:w-64">
                  <SelectValue placeholder="Route" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">Toutes les routes</SelectItem>
                  {(report?.filters.routes ?? []).map((route) => (
                    <SelectItem key={route.routeId} value={route.routeId}>
                      {route.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </CardHeader>
            <CardContent>
              {report === undefined ? (
                <Skeleton className="h-48 w-full" />
              ) : filteredTrips.length === 0 ? (
                <Empty>
                  <EmptyHeader>
                    <EmptyMedia variant="icon">
                      <BusIcon />
                    </EmptyMedia>
                    <EmptyTitle>Aucun trajet</EmptyTitle>
                    <EmptyDescription>Planifiez des départs pour voir les rapports.</EmptyDescription>
                  </EmptyHeader>
                </Empty>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b text-left">
                        <th className="pb-2 px-2">Route</th>
                        <th className="pb-2 px-2">Départ</th>
                        <th className="pb-2 px-2">Bus</th>
                        <th className="pb-2 px-2">Résa</th>
                        <th className="pb-2 px-2">Taux</th>
                        <th className="pb-2 px-2">Revenus</th>
                        <th className="pb-2 px-2">Statut</th>
                        <th className="pb-2 px-2">Manifeste</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredTrips.map((trip) => (
                        <tr key={trip._id} className="border-b last:border-0 hover:bg-muted/30">
                          <td className="py-2 px-2">
                            {trip.originCity} → {trip.destinationCity}
                          </td>
                          <td className="py-2 px-2 whitespace-nowrap">
                            {format(new Date(trip.departureTime), "dd/MM/yy HH:mm")}
                          </td>
                          <td className="py-2 px-2">{trip.busName}</td>
                          <td className="py-2 px-2">
                            {trip.bookingCount}/{trip.totalSeats}
                          </td>
                          <td className="py-2 px-2">{trip.occupancyRate}%</td>
                          <td className="py-2 px-2 font-medium">
                            {trip.revenue.toLocaleString()} {trip.currency}
                          </td>
                          <td className="py-2 px-2">
                            <Badge variant="secondary" className="text-[10px] capitalize">
                              {trip.status}
                            </Badge>
                          </td>
                          <td className="py-2 px-2">
                            <div className="flex items-center gap-1">
                              <Button
                                size="icon"
                                variant="ghost"
                                className="h-7 w-7"
                                title={t("report.manifest_pdf", { defaultValue: "Manifeste passagers (PDF)" })}
                                disabled={manifestBusyId === trip._id}
                                onClick={() => void handleTripManifest(trip._id, "pdf")}
                              >
                                <FileTextIcon className="w-3.5 h-3.5" />
                              </Button>
                              <Button
                                size="icon"
                                variant="ghost"
                                className="h-7 w-7"
                                title={t("report.manifest_csv", { defaultValue: "Manifeste passagers (Excel/CSV)" })}
                                disabled={manifestBusyId === trip._id}
                                onClick={() => void handleTripManifest(trip._id, "csv")}
                              >
                                <FileSpreadsheetIcon className="w-3.5 h-3.5" />
                              </Button>
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* ── Manifeste colis autonomes ──────────────────────────────── */}
        <TabsContent value="colis" className="space-y-4 mt-4">
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-muted-foreground">Envois</p>
                <p className="text-2xl font-bold">{filteredColis.length}</p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <p className="text-xs text-muted-foreground">Total fret</p>
                <p className="text-2xl font-bold">{totalFret.toLocaleString()}</p>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader className="pb-3">
              <div className="flex flex-wrap gap-2 items-end">
                <Select value={colisStatutFilter} onValueChange={setColisStatutFilter}>
                  <SelectTrigger className="w-full sm:w-44">
                    <SelectValue placeholder="Statut" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Tous les statuts</SelectItem>
                    {COLIS_STATUTS.map((statut) => (
                      <SelectItem key={statut} value={statut}>
                        {COLIS_STATUT_LABELS[statut]}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={colisGareFilter} onValueChange={setColisGareFilter}>
                  <SelectTrigger className="w-full sm:w-48">
                    <SelectValue placeholder="Gare de départ" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Toutes gares de départ</SelectItem>
                    {colisGares.map((gare) => (
                      <SelectItem key={gare} value={gare}>
                        {gare}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={colisGareDestFilter} onValueChange={setColisGareDestFilter}>
                  <SelectTrigger className="w-full sm:w-48">
                    <SelectValue placeholder="Gare d'arrivée" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Toutes destinations</SelectItem>
                    {colisGaresDest.map((gare) => (
                      <SelectItem key={gare} value={gare}>
                        {gare}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <div className="flex items-center gap-1.5">
                  <label className="text-xs text-muted-foreground" htmlFor="colis-date-from">
                    Du
                  </label>
                  <input
                    id="colis-date-from"
                    type="date"
                    value={colisDateFrom}
                    onChange={(e) => setColisDateFrom(e.target.value)}
                    className="h-9 rounded-md border bg-transparent px-2 text-xs"
                  />
                  <label className="text-xs text-muted-foreground" htmlFor="colis-date-to">
                    au
                  </label>
                  <input
                    id="colis-date-to"
                    type="date"
                    value={colisDateTo}
                    onChange={(e) => setColisDateTo(e.target.value)}
                    className="h-9 rounded-md border bg-transparent px-2 text-xs"
                  />
                </div>
                <div className="flex gap-2 ml-auto">
                  <Button size="sm" variant="outline" onClick={() => handleColisManifest("pdf")}>
                    <FileTextIcon className="w-3.5 h-3.5 mr-1.5" />
                    {t("report.colis_manifest_pdf", { defaultValue: "Imprimer (PDF)" })}
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => handleColisManifest("csv")}>
                    <FileSpreadsheetIcon className="w-3.5 h-3.5 mr-1.5" />
                    Excel/CSV
                  </Button>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              {colisRows === undefined ? (
                <Skeleton className="h-48 w-full" />
              ) : filteredColis.length === 0 ? (
                <Empty>
                  <EmptyHeader>
                    <EmptyMedia variant="icon">
                      <PackageIcon />
                    </EmptyMedia>
                    <EmptyTitle>{t("report.colis_none", { defaultValue: "Aucun colis" })}</EmptyTitle>
                    <EmptyDescription>
                      {t("report.colis_none_desc", {
                        defaultValue: "Aucun envoi ne correspond au filtre (ou module colis désactivé).",
                      })}
                    </EmptyDescription>
                  </EmptyHeader>
                </Empty>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b text-left">
                        <th className="pb-2 px-2">Date</th>
                        <th className="pb-2 px-2">Trajet</th>
                        <th className="pb-2 px-2">Expéditeur</th>
                        <th className="pb-2 px-2">Destinataire</th>
                        <th className="pb-2 px-2">Nature</th>
                        <th className="pb-2 px-2">Poids</th>
                        <th className="pb-2 px-2">Pièces</th>
                        <th className="pb-2 px-2">Montant</th>
                        <th className="pb-2 px-2">Statut</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredColis.map((row) => (
                        <tr key={row.id} className="border-b last:border-0 hover:bg-muted/30">
                          <td className="py-2 px-2 whitespace-nowrap">
                            {format(new Date(row.createdAt), "dd/MM/yy HH:mm")}
                          </td>
                          <td className="py-2 px-2">
                            {row.gareDepart} → {row.gareDestination}
                          </td>
                          <td className="py-2 px-2">
                            {row.nomExpediteur}
                            <span className="block text-muted-foreground">{row.telephoneExpediteur}</span>
                          </td>
                          <td className="py-2 px-2">
                            {row.nomDestinataire}
                            <span className="block text-muted-foreground">{row.telephoneDestinataire}</span>
                          </td>
                          <td className="py-2 px-2">{row.natures.join(", ")}</td>
                          <td className="py-2 px-2">{row.poidsKg ?? "—"}</td>
                          <td className="py-2 px-2">{row.nombrePieces}</td>
                          <td className="py-2 px-2 font-medium">{row.montantFret.toLocaleString()}</td>
                          <td className="py-2 px-2">
                            <Badge variant="secondary" className="text-[10px]">
                              {COLIS_STATUT_LABELS[row.statutColis]}
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
        </TabsContent>
      </Tabs>
    </div>
  );
}
