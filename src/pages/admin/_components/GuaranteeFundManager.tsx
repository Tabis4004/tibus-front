import { useCallback, useEffect, useRef, useState } from "react";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import {
  ExternalLinkIcon,
  LandmarkIcon,
  PaperclipIcon,
  PlusIcon,
  RefreshCwIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  getCompanyGuaranteeFundSupabase,
  getGuaranteeDepositReceiptUrl,
  GUARANTEE_DEPOSIT_STATUS_LABELS,
  GUARANTEE_LEDGER_TYPE_LABELS,
  listCompanyGuaranteeDepositsSupabase,
  listCompanyGuaranteeLedgerSupabase,
  submitCompanyGuaranteeDepositSupabase,
  uploadGuaranteeDepositReceipt,
  type CompanyGuaranteeFund,
  type GuaranteeDepositRow,
  type GuaranteeLedgerRow,
} from "@/lib/supabase/guarantee-fund.ts";

type CompanyOption = { id: string; name: string; currency: string | null; countryName?: string | null };

const POLL_MS = 20_000;

function fmtDate(iso: string) {
  try {
    return format(parseISO(iso), "dd/MM/yyyy HH:mm");
  } catch {
    return iso;
  }
}

export default function GuaranteeFundManager({
  companies,
}: {
  companies: CompanyOption[];
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [companyId, setCompanyId] = useState(companies[0]?.id ?? "");
  const [fund, setFund] = useState<CompanyGuaranteeFund | undefined>(undefined);
  const [ledger, setLedger] = useState<GuaranteeLedgerRow[] | undefined>(undefined);
  const [deposits, setDeposits] = useState<GuaranteeDepositRow[] | undefined>(undefined);
  const [amount, setAmount] = useState("");
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");
  const [receiptFile, setReceiptFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [lastSyncedAt, setLastSyncedAt] = useState<Date | null>(null);

  const load = useCallback(async (silent = false) => {
    if (!companyId) {
      setFund(undefined);
      setLedger(undefined);
      setDeposits(undefined);
      return;
    }
    if (!silent) {
      setFund(undefined);
      setLedger(undefined);
      setDeposits(undefined);
    } else {
      setRefreshing(true);
    }

    try {
      const [nextFund, nextLedger, nextDeposits] = await Promise.all([
        getCompanyGuaranteeFundSupabase(companyId),
        listCompanyGuaranteeLedgerSupabase(companyId, 200),
        listCompanyGuaranteeDepositsSupabase(companyId),
      ]);
      setFund(nextFund);
      setLedger(nextLedger);
      setDeposits(nextDeposits);
      setLastSyncedAt(new Date());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Chargement impossible");
      if (!silent) {
        setFund(undefined);
        setLedger([]);
        setDeposits([]);
      }
    } finally {
      setRefreshing(false);
    }
  }, [companyId]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (!companyId) return;
    const timer = window.setInterval(() => {
      void load(true);
    }, POLL_MS);
    return () => window.clearInterval(timer);
  }, [companyId, load]);

  useEffect(() => {
    if (!companies.length) return;
    if (!companies.some((company) => company.id === companyId)) {
      setCompanyId(companies[0]?.id ?? "");
    }
  }, [companies, companyId]);

  const openReceipt = async (path: string) => {
    try {
      const url = await getGuaranteeDepositReceiptUrl(path);
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Relevé inaccessible");
    }
  };

  const handleSubmit = async () => {
    const parsed = Number(amount);
    if (!companyId || !Number.isFinite(parsed) || parsed <= 0) {
      toast.error("Montant de dépôt invalide");
      return;
    }
    if (!receiptFile) {
      toast.error("Joignez le relevé de dépôt avant soumission");
      return;
    }
    setSaving(true);
    try {
      const uploaded = await uploadGuaranteeDepositReceipt(companyId, receiptFile);
      await submitCompanyGuaranteeDepositSupabase({
        companyId,
        amount: parsed,
        receiptPath: uploaded.path,
        receiptFileName: uploaded.fileName,
        reference: reference.trim() || undefined,
        note: note.trim() || undefined,
      });
      toast.success("Dépôt soumis — en attente de validation owner/comptable");
      setAmount("");
      setReference("");
      setNote("");
      setReceiptFile(null);
      if (fileRef.current) fileRef.current.value = "";
      await load(true);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Soumission impossible");
    } finally {
      setSaving(false);
    }
  };

  if (!companies.length) {
    return <p className="text-sm text-muted-foreground">Aucune compagnie disponible.</p>;
  }

  const selectedCompany = companies.find((company) => company.id === companyId);

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <CardTitle className="text-base flex items-center gap-2">
              <LandmarkIcon className="w-4 h-4" />
              Fond de garantie — plateforme
            </CardTitle>
            <div className="flex items-center gap-2">
              {lastSyncedAt && (
                <span className="text-[11px] text-muted-foreground">
                  MAJ {format(lastSyncedAt, "HH:mm:ss")}
                </span>
              )}
              <Button
                size="sm"
                variant="outline"
                className="h-8 cursor-pointer"
                disabled={refreshing}
                onClick={() => void load(true)}
              >
                <RefreshCwIcon className={`w-3.5 h-3.5 mr-1.5 ${refreshing ? "animate-spin" : ""}`} />
                Actualiser
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-1.5">
            <Label>Compagnie</Label>
            <Select value={companyId} onValueChange={setCompanyId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {companies.map((company) => (
                  <SelectItem key={company.id} value={company.id}>
                    {company.name}
                    {company.countryName ? ` (${company.countryName})` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {fund === undefined || ledger === undefined || deposits === undefined ? (
            <Skeleton className="h-32 w-full" />
          ) : (
            <>
              <div className="rounded-xl border bg-muted/30 p-4">
                <p className="text-xs text-muted-foreground">
                  Solde actuel — {selectedCompany?.name}
                </p>
                <p className={`text-3xl font-black ${fund.balance < 0 ? "text-destructive" : ""}`}>
                  {fund.balance.toLocaleString()} {fund.currency}
                </p>
                <p className="text-xs text-muted-foreground mt-2">
                  Crédit cumulatif après validation owner/comptable. Rafraîchissement automatique
                  toutes les {POLL_MS / 1000}s.
                </p>
                {fund.allowNegative && (
                  <Badge className="mt-2" variant="outline">
                    Solde négatif autorisé par l&apos;owner
                  </Badge>
                )}
                {fund.pendingDeposits > 0 && (
                  <Badge className="mt-2 ml-2" variant="secondary">
                    {fund.pendingDeposits} dépôt(s) en attente de validation
                  </Badge>
                )}
              </div>

              <div className="rounded-xl border border-dashed p-4 space-y-3">
                <p className="text-sm font-semibold">Soumettre un dépôt (+X)</p>
                <p className="text-xs text-muted-foreground">
                  Relevé de virement obligatoire. Le solde est crédité uniquement après validation
                  par le owner ou le comptable de la compagnie.
                </p>
                <div className="grid gap-3 sm:grid-cols-3">
                  <div className="space-y-1.5">
                    <Label>Montant</Label>
                    <Input
                      type="number"
                      min={1}
                      value={amount}
                      onChange={(e) => setAmount(e.target.value)}
                      placeholder="500000"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label>Référence virement</Label>
                    <Input
                      value={reference}
                      onChange={(e) => setReference(e.target.value)}
                      placeholder="VIR-2026-001"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label>Note</Label>
                    <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Optionnel" />
                  </div>
                </div>
                <div className="space-y-1.5">
                  <Label>Relevé de dépôt (PDF ou image) *</Label>
                  <Input
                    ref={fileRef}
                    type="file"
                    accept="application/pdf,image/jpeg,image/png,image/webp"
                    onChange={(e) => setReceiptFile(e.target.files?.[0] ?? null)}
                  />
                  {receiptFile && (
                    <p className="text-xs text-muted-foreground flex items-center gap-1">
                      <PaperclipIcon className="w-3.5 h-3.5" />
                      {receiptFile.name}
                    </p>
                  )}
                </div>
                <Button onClick={handleSubmit} disabled={saving || !receiptFile} className="cursor-pointer">
                  <PlusIcon className="w-4 h-4 mr-1.5" />
                  {saving ? "Envoi…" : "Soumettre pour validation"}
                </Button>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      {deposits && deposits.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Mes dépôts soumis</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-muted/60 text-left">
                  <tr>
                    <th className="px-3 py-2">Date</th>
                    <th className="px-3 py-2">Montant</th>
                    <th className="px-3 py-2">Statut</th>
                    <th className="px-3 py-2">Réf.</th>
                    <th className="px-3 py-2">Validé par</th>
                    <th className="px-3 py-2">Relevé</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {deposits.map((row) => (
                    <tr key={row.id}>
                      <td className="px-3 py-2 whitespace-nowrap">{fmtDate(row.createdAt)}</td>
                      <td className="px-3 py-2 font-medium">+{row.amount.toLocaleString()}</td>
                      <td className="px-3 py-2">
                        <Badge
                          variant={
                            row.status === "approved"
                              ? "secondary"
                              : row.status === "rejected"
                                ? "destructive"
                                : "outline"
                          }
                        >
                          {GUARANTEE_DEPOSIT_STATUS_LABELS[row.status]}
                        </Badge>
                      </td>
                      <td className="px-3 py-2 font-mono text-xs">{row.reference ?? "—"}</td>
                      <td className="px-3 py-2">{row.validatedByName ?? "—"}</td>
                      <td className="px-3 py-2">
                        <Button
                          size="sm"
                          variant="ghost"
                          className="h-7 cursor-pointer"
                          onClick={() => void openReceipt(row.receiptPath)}
                        >
                          <ExternalLinkIcon className="w-3.5 h-3.5 mr-1" />
                          Voir
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}

      {ledger && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Mouvements du fond (temps réel)</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-muted/60 text-left">
                  <tr>
                    <th className="px-3 py-2">Date</th>
                    <th className="px-3 py-2">Type</th>
                    <th className="px-3 py-2">Montant</th>
                    <th className="px-3 py-2">Solde après</th>
                    <th className="px-3 py-2">Auteur</th>
                    <th className="px-3 py-2">Réf.</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {ledger.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-3 py-4 text-muted-foreground">
                        Aucun mouvement pour cette compagnie.
                      </td>
                    </tr>
                  ) : (
                    ledger.map((row) => (
                      <tr key={row.id}>
                        <td className="px-3 py-2 whitespace-nowrap">{fmtDate(row.createdAt)}</td>
                        <td className="px-3 py-2">{GUARANTEE_LEDGER_TYPE_LABELS[row.type]}</td>
                        <td className="px-3 py-2 font-medium">
                          {row.type === "reservation" ? "−" : "+"}
                          {row.amount.toLocaleString()}
                        </td>
                        <td
                          className={`px-3 py-2 ${
                            row.balanceAfter < 0 ? "text-destructive font-medium" : ""
                          }`}
                        >
                          {row.balanceAfter.toLocaleString()}
                        </td>
                        <td className="px-3 py-2">{row.authorName ?? "—"}</td>
                        <td className="px-3 py-2 font-mono text-xs">{row.reference ?? "—"}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
