import { useEffect, useState } from "react";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { CheckIcon, ExternalLinkIcon, LandmarkIcon, XIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  approveCompanyGuaranteeDepositSupabase,
  getCompanyGuaranteeFundSupabase,
  getGuaranteeDepositReceiptUrl,
  GUARANTEE_DEPOSIT_STATUS_LABELS,
  GUARANTEE_LEDGER_TYPE_LABELS,
  listCompanyGuaranteeDepositsSupabase,
  listCompanyGuaranteeLedgerSupabase,
  rejectCompanyGuaranteeDepositSupabase,
  upsertCompanyGuaranteeSettingsSupabase,
  type CompanyGuaranteeFund,
  type GuaranteeDepositRow,
  type GuaranteeLedgerRow,
} from "@/lib/supabase/guarantee-fund.ts";

function fmtDate(iso: string) {
  try {
    return format(parseISO(iso), "dd/MM/yyyy HH:mm");
  } catch {
    return iso;
  }
}

export default function GuaranteeFundPanel({
  companyId,
  canValidateDeposits = false,
  canConfigureNegative = false,
}: {
  companyId: string;
  canValidateDeposits?: boolean;
  canConfigureNegative?: boolean;
}) {
  const [fund, setFund] = useState<CompanyGuaranteeFund | null | undefined>(undefined);
  const [ledger, setLedger] = useState<GuaranteeLedgerRow[] | undefined>(undefined);
  const [deposits, setDeposits] = useState<GuaranteeDepositRow[] | undefined>(undefined);
  const [allowNegative, setAllowNegative] = useState(false);
  const [savingSettings, setSavingSettings] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);

  const load = () => {
    setFund(undefined);
    setLedger(undefined);
    setDeposits(undefined);
    void Promise.all([
      getCompanyGuaranteeFundSupabase(companyId),
      listCompanyGuaranteeLedgerSupabase(companyId, 200),
      listCompanyGuaranteeDepositsSupabase(companyId),
    ])
      .then(([nextFund, nextLedger, nextDeposits]) => {
        setFund(nextFund);
        setLedger(nextLedger);
        setDeposits(nextDeposits);
        setAllowNegative(nextFund.allowNegative);
      })
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : "Chargement impossible");
        setFund(null);
        setLedger([]);
        setDeposits([]);
      });
  };

  useEffect(() => {
    load();
  }, [companyId]);

  const openReceipt = async (path: string) => {
    try {
      const url = await getGuaranteeDepositReceiptUrl(path);
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Relevé inaccessible");
    }
  };

  const handleApprove = async (depositId: string) => {
    setActingId(depositId);
    try {
      await approveCompanyGuaranteeDepositSupabase(depositId);
      toast.success("Dépôt validé — solde crédité");
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Validation impossible");
    } finally {
      setActingId(null);
    }
  };

  const handleReject = async (deposit: GuaranteeDepositRow) => {
    const reason = window.prompt("Motif du rejet (optionnel)") ?? "";
    setActingId(deposit.id);
    try {
      await rejectCompanyGuaranteeDepositSupabase(deposit.id, reason || undefined);
      toast.success("Dépôt rejeté");
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Rejet impossible");
    } finally {
      setActingId(null);
    }
  };

  const handleAllowNegativeChange = async (checked: boolean) => {
    setAllowNegative(checked);
    setSavingSettings(true);
    try {
      await upsertCompanyGuaranteeSettingsSupabase(companyId, checked);
      toast.success(
        checked
          ? "Solde négatif autorisé — les réservations ne seront plus bloquées par le solde"
          : "Solde négatif désactivé",
      );
      load();
    } catch (err) {
      setAllowNegative(!checked);
      toast.error(err instanceof Error ? err.message : "Enregistrement impossible");
    } finally {
      setSavingSettings(false);
    }
  };

  if (fund === undefined || ledger === undefined || deposits === undefined) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-48 w-full" />
      </div>
    );
  }

  if (!fund) {
    return (
      <p className="text-sm text-muted-foreground">
        Fond de garantie indisponible. Exécutez les scripts SQL 028 et 029.
      </p>
    );
  }

  const pendingDeposits = deposits.filter((row) => row.status === "pending");

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="p-4 flex flex-wrap items-center gap-4 justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
              <LandmarkIcon className="w-5 h-5 text-primary" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Solde fond de garantie</p>
              <p
                className={`text-2xl font-black ${
                  fund.balance < 0 ? "text-destructive" : ""
                }`}
              >
                {fund.balance.toLocaleString()} {fund.currency}
              </p>
            </div>
          </div>
          {fund.pendingDeposits > 0 && (
            <Badge variant="secondary">{fund.pendingDeposits} dépôt(s) en attente</Badge>
          )}
        </CardContent>
      </Card>

      {canConfigureNegative && (
        <div className="rounded-xl border p-4 flex items-center justify-between gap-3">
          <div>
            <Label>Autoriser solde négatif</Label>
            <p className="text-xs text-muted-foreground mt-1">
              Permet de continuer les réservations en ligne même si un dépôt plateforme est en
              retard (problème réseau). Le solde pourra passer sous zéro.
            </p>
          </div>
          <Switch
            checked={allowNegative}
            disabled={savingSettings}
            onCheckedChange={handleAllowNegativeChange}
          />
        </div>
      )}

      {canValidateDeposits && pendingDeposits.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-bold">Dépôts à valider</h3>
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">Date</th>
                  <th className="px-3 py-2">Montant</th>
                  <th className="px-3 py-2">Réf.</th>
                  <th className="px-3 py-2">Relevé</th>
                  <th className="px-3 py-2">Soumis par</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y">
                {pendingDeposits.map((row) => (
                  <tr key={row.id}>
                    <td className="px-3 py-2 whitespace-nowrap">{fmtDate(row.createdAt)}</td>
                    <td className="px-3 py-2 font-medium">+{row.amount.toLocaleString()}</td>
                    <td className="px-3 py-2 font-mono text-xs">{row.reference ?? "—"}</td>
                    <td className="px-3 py-2">
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => openReceipt(row.receiptPath)}
                      >
                        <ExternalLinkIcon className="w-4 h-4 mr-1" />
                        {row.receiptFileName ?? "Relevé"}
                      </Button>
                    </td>
                    <td className="px-3 py-2">{row.submittedByName ?? "—"}</td>
                    <td className="px-3 py-2">
                      <div className="flex gap-1">
                        <Button
                          size="sm"
                          disabled={actingId === row.id}
                          onClick={() => handleApprove(row.id)}
                        >
                          <CheckIcon className="w-4 h-4 mr-1" />
                          Valider
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={actingId === row.id}
                          onClick={() => handleReject(row)}
                        >
                          <XIcon className="w-4 h-4 mr-1" />
                          Rejeter
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {deposits.some((row) => row.status !== "pending") && (
        <div className="space-y-2">
          <h3 className="text-sm font-bold">Historique des dépôts</h3>
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">Date</th>
                  <th className="px-3 py-2">Montant</th>
                  <th className="px-3 py-2">Statut</th>
                  <th className="px-3 py-2">Validé par</th>
                  <th className="px-3 py-2">Relevé</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {deposits
                  .filter((row) => row.status !== "pending")
                  .map((row) => (
                    <tr key={row.id}>
                      <td className="px-3 py-2">{fmtDate(row.createdAt)}</td>
                      <td className="px-3 py-2">+{row.amount.toLocaleString()}</td>
                      <td className="px-3 py-2">
                        <Badge
                          variant={row.status === "approved" ? "secondary" : "destructive"}
                        >
                          {GUARANTEE_DEPOSIT_STATUS_LABELS[row.status]}
                        </Badge>
                      </td>
                      <td className="px-3 py-2">{row.validatedByName ?? "—"}</td>
                      <td className="px-3 py-2">
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => openReceipt(row.receiptPath)}
                        >
                          Voir
                        </Button>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div className="space-y-2">
        <h3 className="text-sm font-bold">Mouvements du fond</h3>
        <div className="overflow-x-auto rounded-xl border">
          <table className="min-w-full text-sm">
            <thead className="bg-muted/60 text-left">
              <tr>
                <th className="px-3 py-2">Date</th>
                <th className="px-3 py-2">Type</th>
                <th className="px-3 py-2">Montant</th>
                <th className="px-3 py-2">Solde</th>
                <th className="px-3 py-2">Auteur</th>
                <th className="px-3 py-2">Réf.</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {ledger.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-3 py-4 text-muted-foreground">
                    Aucun mouvement.
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
      </div>
    </div>
  );
}
