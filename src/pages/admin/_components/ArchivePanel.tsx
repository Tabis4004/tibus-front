import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { HistoryIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  listArchivedOperationsSupabase,
  restoreArchivedRecordSupabase,
  summarizeArchivedPayload,
  type ArchivedOperation,
} from "@/lib/supabase/operations-archive.ts";
import { errorMessage } from "@/lib/utils.ts";
import type { SupabaseCompanyRow } from "../admin-data-loaders.ts";

const TABLE_LABELS: Record<string, string> = {
  colis_autonomes: "Colis",
  mouvements_caisse: "Mouvement caisse",
  reversements_comptables: "Reversement",
  Reservations: "Réservation",
  ReservationBus: "Billet",
  ReservationBusColis: "Colis (billet)",
  bordereaux_livraison: "Bordereau",
  bordereau_colis: "Colis (lot)",
};

/**
 * Historique des suppressions (wipe_company_operations / cancel_colis_autonome)
 * avec restauration — filet de sécurité "versionnage" en l'absence de
 * sauvegarde automatique Supabase sur le plan free du projet.
 */
export default function ArchivePanel({ companies }: { companies: SupabaseCompanyRow[] }) {
  const [companyFilter, setCompanyFilter] = useState<string>("all");
  const [rows, setRows] = useState<ArchivedOperation[] | undefined>(undefined);
  const [restoringId, setRestoringId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setRows(undefined);
    try {
      const data = await listArchivedOperationsSupabase({
        companyId: companyFilter === "all" ? null : companyFilter,
      });
      setRows(data);
    } catch (err) {
      toast.error(errorMessage(err, "Chargement de l'historique impossible."));
      setRows([]);
    }
  }, [companyFilter]);

  useEffect(() => {
    void load();
  }, [load]);

  const handleRestore = async (row: ArchivedOperation) => {
    setRestoringId(row.id);
    try {
      await restoreArchivedRecordSupabase(row.id);
      toast.success(`${TABLE_LABELS[row.tableName] ?? row.tableName} restauré.`);
      void load();
    } catch (err) {
      toast.error(errorMessage(err, "Restauration impossible."));
    } finally {
      setRestoringId(null);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <HistoryIcon className="w-4 h-4" />
          Historique des suppressions
        </CardTitle>
        <p className="text-xs text-muted-foreground">
          Instantané conservé avant chaque suppression (vidage compagnie, annulation colis) —
          seul filet de sécurité disponible, ce projet n'a pas de sauvegarde automatique
          Supabase (plan free).
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        <Select value={companyFilter} onValueChange={setCompanyFilter}>
          <SelectTrigger className="w-full sm:w-[260px]">
            <SelectValue placeholder="Toutes les compagnies" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Toutes les compagnies</SelectItem>
            {companies.map((c) => (
              <SelectItem key={c.id} value={c.id}>
                {c.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        {rows === undefined ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-14 rounded-lg" />
            ))}
          </div>
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted-foreground py-4 text-center">
            Aucune suppression archivée{companyFilter !== "all" ? " pour cette compagnie" : ""}.
          </p>
        ) : (
          <div className="space-y-2">
            {rows.map((row) => (
              <div
                key={row.id}
                className="flex items-center justify-between gap-3 rounded-lg border p-3"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <Badge variant="secondary" className="text-[10px]">
                      {TABLE_LABELS[row.tableName] ?? row.tableName}
                    </Badge>
                    {row.restoredAt ? (
                      <Badge variant="outline" className="text-[10px]">
                        Restauré
                      </Badge>
                    ) : null}
                    <span className="text-xs text-muted-foreground">{row.companyName ?? ""}</span>
                  </div>
                  <p className="text-sm font-medium truncate mt-0.5">
                    {summarizeArchivedPayload(row)}
                  </p>
                  <p className="text-[11px] text-muted-foreground">
                    Supprimé {row.deletedByName ? `par ${row.deletedByName} ` : ""}
                    le {new Date(row.deletedAt).toLocaleString()} · via {row.deletedVia}
                  </p>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  className="shrink-0"
                  disabled={Boolean(row.restoredAt) || restoringId === row.id}
                  onClick={() => void handleRestore(row)}
                >
                  {row.restoredAt
                    ? "Restauré"
                    : restoringId === row.id
                      ? "…"
                      : "Restaurer"}
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
