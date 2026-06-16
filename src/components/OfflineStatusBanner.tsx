import { CloudOffIcon, RefreshCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { useOfflineSync } from "@/hooks/use-offline-sync.tsx";

export default function OfflineStatusBanner() {
  const { online, syncing, pendingCount, syncNow } = useOfflineSync();

  if (online && pendingCount === 0 && !syncing) {
    return null;
  }

  return (
    <div
      className={
        online
          ? "border-b border-amber-300/60 bg-amber-50 px-3 py-2 text-sm text-amber-950"
          : "border-b border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive"
      }
    >
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <CloudOffIcon className="h-4 w-4 shrink-0" />
          {!online ? (
            <span>Mode hors ligne — les ventes guichet sont enregistrées localement.</span>
          ) : syncing ? (
            <span>Synchronisation des ventes guichet en cours…</span>
          ) : (
            <span>
              {pendingCount} vente(s) guichet en attente de synchronisation.
            </span>
          )}
        </div>
        {online && pendingCount > 0 ? (
          <Button size="sm" variant="outline" className="h-8" disabled={syncing} onClick={() => void syncNow()}>
            <RefreshCwIcon className={`mr-1.5 h-3.5 w-3.5 ${syncing ? "animate-spin" : ""}`} />
            Synchroniser
          </Button>
        ) : null}
      </div>
    </div>
  );
}
