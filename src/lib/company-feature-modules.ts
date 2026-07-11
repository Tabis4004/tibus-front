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
  /** Admin : l'owner peut configurer les SMS colis (module D). */
  moduleDColisSmsConfig: boolean;
  /** Étapes SMS colis incluses dans l'offre (choisies par la plateforme). */
  smsEnregistreAllowed: boolean;
  smsChargeAllowed: boolean;
  smsArriveAllowed: boolean;
  smsLivreAllowed: boolean;
  updatedAt?: string;
};

export const DEFAULT_COMPANY_FEATURE_MODULES: Omit<CompanyFeatureModules, "companyId"> = {
  moduleA: true,
  moduleB: true,
  moduleC: true,
  moduleD: true,
  moduleE: true,
  moduleF: false,
  moduleDColisSmsConfig: false,
  smsEnregistreAllowed: false,
  smsChargeAllowed: false,
  smsArriveAllowed: false,
  smsLivreAllowed: false,
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
  // B, C et E s'appuient sur les briques partagées (gares, caisse, journal) :
  // disponibles avec la billetterie (A) OU les colis autonomes (D).
  if (module === "B" || module === "C" || module === "E") {
    return modules.moduleA || modules.moduleD;
  }
  return true;
}

/**
 * Une fonctionnalité peut être ouverte par PLUSIEURS modules (any-of) :
 * ex. les gares et la caisse servent la billetterie (A) et les colis (D).
 */
export function companyFeatureEnabled(
  modules: CompanyFeatureModules,
  requirement: CompanyFeatureModuleId | readonly CompanyFeatureModuleId[],
): boolean {
  const list = Array.isArray(requirement) ? requirement : [requirement];
  return list.some((module) => companyModuleEnabled(modules, module));
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

export function colisSmsOwnerConfigEnabled(
  modules: CompanyFeatureModules | null | undefined,
): boolean {
  if (!modules) return false;
  return modules.moduleD && modules.moduleDColisSmsConfig;
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
    moduleDColisSmsConfig: row.moduleDColisSmsConfig === true,
    smsEnregistreAllowed: row.smsEnregistreAllowed === true,
    smsChargeAllowed: row.smsChargeAllowed === true,
    smsArriveAllowed: row.smsArriveAllowed === true,
    smsLivreAllowed: row.smsLivreAllowed === true,
    updatedAt: row.updatedAt ? String(row.updatedAt) : undefined,
  };
}
