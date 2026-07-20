import { useCallback, useEffect, useMemo, useState } from "react";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { PrinterIcon, RefreshCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  getColisSalesJournalSupabase,
  listCompanyColisVendeursSupabase,
  type ColisSalesJournal,
  type ColisVendeurOption,
} from "@/lib/supabase/colis-sales-journal.ts";
import { getSellerCompanyReceiptInfoSupabase } from "@/lib/supabase/seller-counter.ts";
import type { SellerCompanyReceiptInfo } from "@/lib/ticket-receipt-print.ts";

function todayInputValue(): string {
  return format(new Date(), "yyyy-MM-dd");
}

function fmtDateTime(iso: string) {
  try {
    return format(parseISO(iso), "dd/MM/yyyy HH:mm");
  } catch {
    return iso;
  }
}

export default function ColisSalesJournalPanel({
  companyId,
  companyName,
}: {
  companyId: string;
  companyName: string;
}) {
  const [dateFrom, setDateFrom] = useState(todayInputValue());
  const [dateTo, setDateTo] = useState(todayInputValue());
  const [vendeurId, setVendeurId] = useState<string>("all");
  const [vendeurs, setVendeurs] = useState<ColisVendeurOption[]>([]);
  const [journal, setJournal] = useState<ColisSalesJournal | null>(null);
  const [loading, setLoading] = useState(false);
  const [companyInfo, setCompanyInfo] = useState<SellerCompanyReceiptInfo | null>(null);
  const [showPrintView, setShowPrintView] = useState(false);

  useEffect(() => {
    void getSellerCompanyReceiptInfoSupabase(companyId)
      .then(setCompanyInfo)
      .catch(() => setCompanyInfo(null));
  }, [companyId]);

  useEffect(() => {
    void listCompanyColisVendeursSupabase(companyId)
      .then(setVendeurs)
      .catch(() => setVendeurs([]));
  }, [companyId]);

  const load = useCallback(() => {
    if (!dateFrom) return;
    setLoading(true);
    const isoFrom = `${dateFrom}T00:00:00`;
    const isoTo = `${dateTo || dateFrom}T23:59:59.999`;
    void getColisSalesJournalSupabase({
      companyId,
      dateFrom: isoFrom,
      dateTo: isoTo,
      vendeurId: vendeurId === "all" ? null : vendeurId,
    })
      .then(setJournal)
      .catch((err) => toast.error(err instanceof Error ? err.message : "Chargement impossible"))
      .finally(() => setLoading(false));
  }, [companyId, dateFrom, dateTo, vendeurId]);

  useEffect(() => {
    load();
  }, [load]);

  const canFilterVendeur = (journal?.fullAccess || journal?.gareScope) ?? vendeurs.length > 0;

  const periodLabel = useMemo(() => {
    if (dateFrom === dateTo || !dateTo) {
      try {
        return format(parseISO(dateFrom), "dd/MM/yyyy");
      } catch {
        return dateFrom;
      }
    }
    try {
      return `${format(parseISO(dateFrom), "dd/MM/yyyy")} au ${format(parseISO(dateTo), "dd/MM/yyyy")}`;
    } catch {
      return `${dateFrom} au ${dateTo}`;
    }
  }, [dateFrom, dateTo]);

  const handlePrint = () => {
    setShowPrintView(true);
    window.setTimeout(() => window.print(), 60);
  };

  useEffect(() => {
    if (!showPrintView) return;
    const onAfterPrint = () => setShowPrintView(false);
    window.addEventListener("afterprint", onAfterPrint);
    return () => window.removeEventListener("afterprint", onAfterPrint);
  }, [showPrintView]);

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <CardTitle className="text-base flex items-center gap-2">
            <PrinterIcon className="w-4 h-4" />
            Journal de vente (colis)
          </CardTitle>
          <div className="flex gap-2">
            <Button size="sm" variant="outline" className="h-8 cursor-pointer" onClick={load} disabled={loading}>
              <RefreshCwIcon className={`w-3.5 h-3.5 mr-1.5 ${loading ? "animate-spin" : ""}`} />
              Actualiser
            </Button>
            <Button
              size="sm"
              className="h-8 cursor-pointer"
              onClick={handlePrint}
              disabled={loading || !journal || journal.groups.length === 0}
            >
              <PrinterIcon className="w-3.5 h-3.5 mr-1.5" />
              Imprimer
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="space-y-1.5">
            <Label className="text-xs">Du</Label>
            <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs">Au</Label>
            <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          </div>
          {canFilterVendeur && (
            <div className="space-y-1.5">
              <Label className="text-xs">Agent</Label>
              <Select value={vendeurId} onValueChange={setVendeurId}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">Tous les agents</SelectItem>
                  {vendeurs.map((v) => (
                    <SelectItem key={v.id} value={v.id}>
                      {v.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>

        {loading ? (
          <Skeleton className="h-40 w-full" />
        ) : !journal || journal.groups.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucune vente de colis sur cette période.</p>
        ) : (
          <div className="space-y-4">
            <p className="text-xs text-muted-foreground">
              {journal.grandCount} colis · Frais {journal.grandTotalFrais.toLocaleString()} · Valeur{" "}
              {journal.grandTotalValeur.toLocaleString()}
            </p>
            <div className="space-y-3">
              {journal.groups.map((g) => (
                <div key={g.vendeurId ?? "inconnu"} className="rounded-xl border overflow-hidden">
                  <div className="px-4 py-2 bg-muted/40 flex items-center justify-between">
                    <p className="font-semibold text-sm">{g.vendeurName}</p>
                    <p className="text-xs text-muted-foreground">
                      {g.count} colis · Frais {g.totalFrais.toLocaleString()} · Valeur{" "}
                      {g.totalValeur.toLocaleString()}
                    </p>
                  </div>
                  <div className="overflow-x-auto">
                    <table className="min-w-full text-xs">
                      <thead>
                        <tr className="text-left text-muted-foreground">
                          <th className="py-1.5 px-3">Réf.</th>
                          <th className="py-1.5 px-3">Date</th>
                          <th className="py-1.5 px-3">Expéditeur</th>
                          <th className="py-1.5 px-3">Destinataire</th>
                          <th className="py-1.5 px-3">Frais</th>
                          <th className="py-1.5 px-3">Valeur</th>
                          <th className="py-1.5 px-3">Destination</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y">
                        {g.colis.map((c) => (
                          <tr key={c.id}>
                            <td className="py-1.5 px-3 font-mono">{c.numeroRecu ?? "—"}</td>
                            <td className="py-1.5 px-3 whitespace-nowrap">{fmtDateTime(c.createdAt)}</td>
                            <td className="py-1.5 px-3">{c.nomExpediteur}</td>
                            <td className="py-1.5 px-3">{c.nomDestinataire}</td>
                            <td className="py-1.5 px-3">{c.montantFret.toLocaleString()}</td>
                            <td className="py-1.5 px-3">{(c.valeurMarchandise ?? 0).toLocaleString()}</td>
                            <td className="py-1.5 px-3">{c.gareDestination}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>

      {showPrintView && journal && (
        <div
          id="printable-sales-journal"
          className="bg-white text-black"
          style={{ fontFamily: '"Courier New", Courier, monospace' }}
        >
          <div className="text-center" style={{ borderBottom: "1px dashed #000", paddingBottom: "2mm", marginBottom: "2mm" }}>
            {companyInfo?.logoUrl && (
              <img src={companyInfo.logoUrl} alt="Logo" style={{ height: "10mm", margin: "0 auto 1mm" }} />
            )}
            <div style={{ fontWeight: "bold", fontSize: "13px" }}>{companyInfo?.name || companyName}</div>
            {(companyInfo?.address || companyInfo?.phone) && (
              <div style={{ fontSize: "9px", color: "#333" }}>
                {companyInfo?.address}
                {companyInfo?.address && companyInfo?.phone ? " | " : ""}
                {companyInfo?.phone}
              </div>
            )}
            <div style={{ fontSize: "12px", fontWeight: "bold", marginTop: "1.5mm", letterSpacing: "1px" }}>
              JOURNAL DE VENTE
            </div>
            <div style={{ fontSize: "10px" }}>{periodLabel}</div>
          </div>

          {journal.groups.map((g) => (
            <div key={g.vendeurId ?? "inconnu"} style={{ marginBottom: "3mm" }}>
              <div
                style={{
                  fontWeight: "bold",
                  fontSize: "11px",
                  borderBottom: "1px dashed #000",
                  marginBottom: "1mm",
                  paddingBottom: "0.5mm",
                }}
              >
                Agent: {g.vendeurUsername ?? g.vendeurName}
              </div>
              {g.colis.map((c) => (
                <div key={c.id} style={{ fontSize: "10px", marginBottom: "1.5mm" }}>
                  <div style={{ display: "flex", justifyContent: "space-between" }}>
                    <span>{c.numeroRecu ?? "—"}</span>
                    <span>{fmtDateTime(c.createdAt)}</span>
                  </div>
                  <div>Exp: {c.nomExpediteur}</div>
                  <div>Dest: {c.nomDestinataire}</div>
                  <div style={{ display: "flex", justifyContent: "space-between" }}>
                    <span>Frais: {c.montantFret.toLocaleString()}</span>
                    <span>Valeur: {(c.valeurMarchandise ?? 0).toLocaleString()}</span>
                  </div>
                  <div>Destination: {c.gareDestination}</div>
                </div>
              ))}
              <div
                style={{
                  border: "1px solid #000",
                  padding: "1mm 2mm",
                  fontSize: "10px",
                  fontWeight: "bold",
                  display: "flex",
                  justifyContent: "space-between",
                  marginTop: "1mm",
                }}
              >
                <span>Total {g.vendeurUsername ?? g.vendeurName} ({g.count})</span>
                <span>
                  Frais {g.totalFrais.toLocaleString()} · Valeur {g.totalValeur.toLocaleString()}
                </span>
              </div>
            </div>
          ))}

          <div
            style={{
              borderTop: "2px solid #000",
              marginTop: "2mm",
              paddingTop: "1.5mm",
              fontSize: "11px",
              fontWeight: "bold",
              textAlign: "center",
            }}
          >
            TOTAL GENERAL: {journal.grandCount} colis
            <br />
            Frais {journal.grandTotalFrais.toLocaleString()} · Valeur {journal.grandTotalValeur.toLocaleString()}
          </div>
        </div>
      )}
    </Card>
  );
}
