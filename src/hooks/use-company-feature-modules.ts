import { useEffect, useMemo, useState } from "react";
import {
  companyModuleEnabled,
  DEFAULT_COMPANY_FEATURE_MODULES,
  normalizeCompanyFeatureModules,
  type CompanyFeatureModuleId,
  type CompanyFeatureModules,
} from "@/lib/company-feature-modules.ts";
import { getCompanyFeatureModulesSupabase } from "@/lib/supabase/company-feature-modules.ts";

export function useCompanyFeatureModules(companyId: string | null | undefined) {
  const [modules, setModules] = useState<CompanyFeatureModules | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!companyId) {
      setModules(null);
      setError(null);
      setIsLoading(false);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setError(null);

    void getCompanyFeatureModulesSupabase(companyId)
      .then((row) => {
        if (!cancelled) setModules(row);
      })
      .catch((err) => {
        if (!cancelled) {
          setModules(
            normalizeCompanyFeatureModules(companyId, {
              companyId,
              ...DEFAULT_COMPANY_FEATURE_MODULES,
            }),
          );
          setError(err instanceof Error ? err.message : "Chargement modules impossible");
        }
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [companyId]);

  const hasModule = useMemo(
    () => (module: CompanyFeatureModuleId) => {
      if (!modules) return true;
      return companyModuleEnabled(modules, module);
    },
    [modules],
  );

  return { modules, isLoading, error, hasModule };
}
