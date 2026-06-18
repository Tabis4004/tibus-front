import type { CommercialOfferDocument, CommercialOfferModule } from "@/data/commercial-offer-content.ts";
import { getCommercialOfferDocument, resolveCommercialOfferLocale } from "@/data/commercial-offer-content.ts";

export type CommercialOfferTechnicalAnnex = {
  heading: string;
  architectureTable: CommercialOfferDocument["technical"]["architectureTable"];
  modules: CommercialOfferModule[];
};

export function resolveTechnicalAnnexFromDocument(
  doc: CommercialOfferDocument,
  locale: string,
): CommercialOfferTechnicalAnnex {
  const resolved = resolveCommercialOfferLocale(locale);
  const heading =
    resolved === "en"
      ? "2. Technical architecture (included in subscription)"
      : "2. Architecture technique (incluse dans l'abonnement)";

  return {
    heading,
    architectureTable: doc.technical.architectureTable,
    modules: doc.technical.modules,
  };
}

export function getDefaultTechnicalAnnex(locale: string): CommercialOfferTechnicalAnnex {
  return resolveTechnicalAnnexFromDocument(getCommercialOfferDocument(locale), locale);
}

export function formatTechnicalAnnexText(annex: CommercialOfferTechnicalAnnex): string {
  const lines: string[] = [
    "",
    "—".repeat(40),
    "ANNEXE — OFFRE TECHNIQUE",
    annex.heading,
    "",
  ];

  for (const row of annex.architectureTable.rows) {
    lines.push(`• ${row[0]} : ${row[1]}`);
  }

  lines.push("", "Modules fonctionnels :", "");
  for (const module of annex.modules) {
    const requires = module.requires ? ` (requiert module ${module.requires})` : "";
    lines.push(`Module ${module.code} — ${module.title}${requires}`);
    lines.push(`  ${module.description}`);
    lines.push("");
  }

  return lines.join("\n").trimEnd();
}

export function normalizeTechnicalAnnexRpc(data: unknown): CommercialOfferTechnicalAnnex | null {
  if (!data || typeof data !== "object") return null;
  const row = data as Record<string, unknown>;
  const architectureTable = row.architectureTable as CommercialOfferTechnicalAnnex["architectureTable"] | undefined;
  const modules = row.modules as CommercialOfferModule[] | undefined;
  if (!architectureTable?.headers?.length || !Array.isArray(modules)) return null;
  return {
    heading: String(row.heading ?? ""),
    architectureTable,
    modules,
  };
}
