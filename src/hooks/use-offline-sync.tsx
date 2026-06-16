import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { toast } from "sonner";
import {
  countPendingCounterSales,
  syncPendingCounterSales,
} from "@/lib/offline/counter-sale-offline.ts";
import { isBrowserOnline, subscribeNetworkStatus } from "@/lib/offline/network.ts";

type OfflineSyncContextValue = {
  online: boolean;
  syncing: boolean;
  pendingCount: number;
  refreshPendingCount: () => Promise<void>;
  syncNow: () => Promise<void>;
};

const OfflineSyncContext = createContext<OfflineSyncContextValue | null>(null);

export function OfflineSyncProvider({ children }: { children: ReactNode }) {
  const [online, setOnline] = useState(isBrowserOnline());
  const [syncing, setSyncing] = useState(false);
  const [pendingCount, setPendingCount] = useState(0);

  const refreshPendingCount = useCallback(async () => {
    const count = await countPendingCounterSales();
    setPendingCount(count);
  }, []);

  const syncNow = useCallback(async () => {
    if (!isBrowserOnline()) return;
    setSyncing(true);
    try {
      const result = await syncPendingCounterSales();
      await refreshPendingCount();
      if (result.synced > 0) {
        toast.success(
          `${result.synced} vente(s) guichet synchronisée(s)${result.failed > 0 ? ` — ${result.failed} échec(s)` : ""}`,
        );
      } else if (result.failed > 0) {
        toast.error(`${result.failed} vente(s) en attente n'ont pas pu être synchronisées`);
      }
    } finally {
      setSyncing(false);
    }
  }, [refreshPendingCount]);

  useEffect(() => {
    void refreshPendingCount();
    return subscribeNetworkStatus((nextOnline) => {
      setOnline(nextOnline);
      if (nextOnline) {
        void syncNow();
      }
    });
  }, [refreshPendingCount, syncNow]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      if (isBrowserOnline()) void syncNow();
    }, 60_000);
    return () => window.clearInterval(interval);
  }, [syncNow]);

  const value = useMemo(
    () => ({
      online,
      syncing,
      pendingCount,
      refreshPendingCount,
      syncNow,
    }),
    [online, syncing, pendingCount, refreshPendingCount, syncNow],
  );

  return <OfflineSyncContext.Provider value={value}>{children}</OfflineSyncContext.Provider>;
}

export function useOfflineSync() {
  const ctx = useContext(OfflineSyncContext);
  if (!ctx) {
    return {
      online: isBrowserOnline(),
      syncing: false,
      pendingCount: 0,
      refreshPendingCount: async () => {},
      syncNow: async () => {},
    };
  }
  return ctx;
}
