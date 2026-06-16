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
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  listOwnerCompaniesSupabase,
  ownerCompanyStorageKey,
  setOwnerActiveCompanySupabase,
  type OwnerCompanyOption,
} from "@/lib/supabase/owner-company";
import { useCompanyFeatureModules } from "@/hooks/use-company-feature-modules.ts";
import type { CompanyFeatureModules } from "@/lib/company-feature-modules.ts";

export const OWNER_COMPANY_REFRESH_EVENT = "tibus:owner-company-refresh";

function storageKey(userId: string) {
  return ownerCompanyStorageKey(userId);
}

type OwnerCompanyContextValue = {
  companies: OwnerCompanyOption[];
  selectedCompanyId: string | null;
  selectedCompany: OwnerCompanyOption | null;
  companyId: string | null;
  featureModules: CompanyFeatureModules | null;
  featureModulesLoading: boolean;
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
  const { isSuperAdmin } = useAppUser();
  const [companies, setCompanies] = useState<OwnerCompanyOption[]>([]);
  const [selectedCompanyId, setSelectedCompanyIdState] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isReady, setIsReady] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const refresh = useCallback(() => {
    setRefreshKey((key) => key + 1);
  }, []);

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

    void (async () => {
      const rows = await listOwnerCompaniesSupabase(appUserId, { isSuperAdmin });
      if (cancelled) return;

      setCompanies(rows);

      setSelectedCompanyIdState((current) => {
        const stored = localStorage.getItem(storageKey(appUserId));
        if (stored && rows.some((row) => row.id === stored)) return stored;
        if (current && rows.some((row) => row.id === current)) return current;
        return rows[0]?.id ?? null;
      });

      const preferred =
        localStorage.getItem(storageKey(appUserId)) &&
        rows.some((row) => row.id === localStorage.getItem(storageKey(appUserId)))
          ? (localStorage.getItem(storageKey(appUserId)) as string)
          : rows[0]?.id ?? null;

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
  }, [appUserId, refreshKey, isSuperAdmin]);

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

      window.dispatchEvent(new Event(OWNER_COMPANY_REFRESH_EVENT));
    },
    [appUserId, companies],
  );

  const selectedCompany = useMemo(
    () => companies.find((row) => row.id === selectedCompanyId) ?? null,
    [companies, selectedCompanyId],
  );

  const {
    modules: featureModules,
    isLoading: featureModulesLoading,
  } = useCompanyFeatureModules(selectedCompanyId);

  const value = useMemo<OwnerCompanyContextValue>(
    () => ({
      companies,
      selectedCompanyId,
      selectedCompany,
      companyId: selectedCompanyId,
      featureModules,
      featureModulesLoading,
      isReady,
      isLoading,
      setSelectedCompanyId,
      refresh,
    }),
    [
      companies,
      selectedCompanyId,
      selectedCompany,
      featureModules,
      featureModulesLoading,
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

export function useOwnerCompanyOptional() {
  return useContext(OwnerCompanyContext);
}
