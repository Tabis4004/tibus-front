/** Modules commerciaux Tibus (offre A–F) activables par compagnie. */
export type CompanyFeatureModuleId = "A" | "B" | "C" | "D" | "E" | "F";

export type CompanyFeatureModules = {
  companyId: string;
  moduleA: boolean;
  moduleB: boolean;
  moduleC: boolean;
  moduleD: boolean;
  moduleE: boolean;
  moduleF: boolean;
  updatedAt?: string;
};

export const DEFAULT_COMPANY_FEATURE_MODULES: Omit<CompanyFeatureModules, "companyId"> = {
  moduleA: true,
  moduleB: true,
  moduleC: true,
  moduleD: true,
  moduleE: true,
  moduleF: false,
};

export function companyModuleEnabled(
  modules: CompanyFeatureModules,
  module: CompanyFeatureModuleId,
): boolean {
  const flags: Record<CompanyFeatureModuleId, boolean> = {
    A: modules.moduleA,
    B: modules.moduleB,
    C: modules.moduleC,
    D: modules.moduleD,
    E: modules.moduleE,
    F: modules.moduleF,
  };
  const enabled = flags[module];
  if (!enabled) return false;
  if (module === "B" || module === "C" || module === "E") {
    return modules.moduleA;
  }
  return true;
}

/** Colis autonomes : module commercial D (source admin) ou legacy `colis_autonome_enabled`. */
export function isColisAutonomeModuleActive(
  colisSettings: { colisAutonomeEnabled: boolean },
  featureModules: CompanyFeatureModules | null | undefined,
): boolean {
  if (featureModules) {
    return companyModuleEnabled(featureModules, "D");
  }
  return colisSettings.colisAutonomeEnabled;
}

export function normalizeCompanyFeatureModules(
  companyId: string,
  data: unknown,
): CompanyFeatureModules {
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    companyId,
    moduleA: row.moduleA !== false,
    moduleB: row.moduleB !== false,
    moduleC: row.moduleC !== false,
    moduleD: row.moduleD !== false,
    moduleE: row.moduleE === true,
    moduleF: row.moduleF === true,
    updatedAt: row.updatedAt ? String(row.updatedAt) : undefined,
  };
}
