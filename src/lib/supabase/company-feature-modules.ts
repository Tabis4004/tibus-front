import { supabase } from "@/lib/supabase";
import {
  normalizeCompanyFeatureModules,
  type CompanyFeatureModules,
} from "@/lib/company-feature-modules.ts";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";

export async function getCompanyFeatureModulesSupabase(
  companyId: string,
): Promise<CompanyFeatureModules> {
  const { data, error } = await supabase.rpc("get_company_feature_modules", {
    p_company_id: companyId,
  });
  if (error) throw error;
  return normalizeCompanyFeatureModules(companyId, data);
}

export async function setCompanyFeatureModulesSupabase(
  companyId: string,
  modules: Pick<
    CompanyFeatureModules,
    "moduleA" | "moduleB" | "moduleC" | "moduleD" | "moduleE" | "moduleF"
  >,
): Promise<CompanyFeatureModules> {
  const { data, error } = await supabase.rpc("set_company_feature_modules", {
    p_company_id: companyId,
    p_module_a: modules.moduleA,
    p_module_b: modules.moduleB,
    p_module_c: modules.moduleC,
    p_module_d: modules.moduleD,
    p_module_e: modules.moduleE,
    p_module_f: modules.moduleF,
  });
  if (error) throw error;

  const enabled = ["A", "B", "C", "D", "E", "F"].filter((key) => {
    const map: Record<string, boolean> = {
      A: modules.moduleA,
      B: modules.moduleB,
      C: modules.moduleC,
      D: modules.moduleD,
      E: modules.moduleE,
      F: modules.moduleF,
    };
    return map[key];
  });

  void recordPlatformAuditSupabase({
    moduleKey: "admin.companies",
    action: "update",
    summary: `Modules compagnie mis à jour (${enabled.join(", ") || "aucun"})`,
    metadata: { companyId, modules },
  }).catch(() => undefined);

  return normalizeCompanyFeatureModules(companyId, data);
}
