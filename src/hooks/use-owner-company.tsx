import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import {
  listOwnerCompaniesSupabase,
  setOwnerActiveCompanySupabase,
  type OwnerCompanyOption,
} from "@/lib/supabase/owner-company";

export const OWNER_COMPANY_REFRESH_EVENT = "tibus:owner-company-refresh";

function storageKey(userId: string) {
  return `tibus:owner-company:${userId}`;
}

type OwnerCompanyContextValue = {
  companies: OwnerCompanyOption[];
  selectedCompanyId: string | null;
  selectedCompany: OwnerCompanyOption | null;
  companyId: string | null;
  isReady: boolean;
  isLoading: boolean;
  setSelectedCompanyId: (companyId: string) => Promise<void>;
  refresh: () => void;
};

const OwnerCompanyContext = createContext<OwnerCompanyContextValue | null>(null);

export function refreshOwnerCompanyContext() {
  window.dispatchEvent(new Event(OWNER_COMPANY_REFRESH_EVENT));
}

export function OwnerCompanyProvider({ children }: { children: ReactNode }) {
  const { appUserId } = useSupabaseAuth();
  const [companies, setCompanies] = useState<OwnerCompanyOption[]>([]);
  const [selectedCompanyId, setSelectedCompanyIdState] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isReady, setIsReady] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const refresh = useCallback(() => {
    setRefreshKey((key) => key + 1);
  }, []);

  useEffect(() => {
    const onRefresh = () => refresh();
    window.addEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
  }, [refresh]);

  useEffect(() => {
    if (!appUserId) {
      setCompanies([]);
      setSelectedCompanyIdState(null);
      setIsReady(true);
      setIsLoading(false);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setIsReady(false);

    void (async () => {
      const rows = await listOwnerCompaniesSupabase(appUserId);
      if (cancelled) return;

      setCompanies(rows);

      const stored = localStorage.getItem(storageKey(appUserId));
      const preferred =
        stored && rows.some((row) => row.id === stored) ? stored : rows[0]?.id ?? null;

      setSelectedCompanyIdState(preferred);

      if (preferred) {
        try {
          await setOwnerActiveCompanySupabase(preferred);
          localStorage.setItem(storageKey(appUserId), preferred);
        } catch {
          // Server sync optional until SQL 058 is applied
        }
      }

      if (!cancelled) {
        setIsReady(true);
        setIsLoading(false);
      }
    })().catch(() => {
      if (!cancelled) {
        setCompanies([]);
        setSelectedCompanyIdState(null);
        setIsReady(true);
        setIsLoading(false);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [appUserId, refreshKey]);

  const setSelectedCompanyId = useCallback(
    async (companyId: string) => {
      if (!appUserId) return;
      if (!companies.some((row) => row.id === companyId)) return;

      setSelectedCompanyIdState(companyId);
      localStorage.setItem(storageKey(appUserId), companyId);

      try {
        await setOwnerActiveCompanySupabase(companyId);
      } catch {
        // Keep local selection even if RPC missing
      }

      refreshOwnerCompanyContext();
    },
    [appUserId, companies],
  );

  const selectedCompany = useMemo(
    () => companies.find((row) => row.id === selectedCompanyId) ?? null,
    [companies, selectedCompanyId],
  );

  const value = useMemo<OwnerCompanyContextValue>(
    () => ({
      companies,
      selectedCompanyId,
      selectedCompany,
      companyId: selectedCompanyId,
      isReady,
      isLoading,
      setSelectedCompanyId,
      refresh,
    }),
    [
      companies,
      selectedCompanyId,
      selectedCompany,
      isReady,
      isLoading,
      setSelectedCompanyId,
      refresh,
    ],
  );

  return (
    <OwnerCompanyContext.Provider value={value}>{children}</OwnerCompanyContext.Provider>
  );
}

export function useOwnerCompany() {
  const ctx = useContext(OwnerCompanyContext);
  if (!ctx) {
    throw new Error("useOwnerCompany must be used within OwnerCompanyProvider");
  }
  return ctx;
}
