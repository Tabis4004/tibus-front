import { supabase } from "@/lib/supabase";

export type ColisSalesJournalLine = {
  id: string;
  numeroRecu: string | null;
  createdAt: string;
  nomExpediteur: string;
  nomDestinataire: string;
  montantFret: number;
  valeurMarchandise: number | null;
  gareDestination: string;
};

export type ColisSalesJournalGroup = {
  vendeurId: string | null;
  vendeurName: string;
  vendeurUsername: string | null;
  colis: ColisSalesJournalLine[];
  count: number;
  totalFrais: number;
  totalValeur: number;
};

export type ColisSalesJournal = {
  groups: ColisSalesJournalGroup[];
  grandCount: number;
  grandTotalFrais: number;
  grandTotalValeur: number;
  fullAccess: boolean;
  gareScope: boolean;
};

export type ColisVendeurOption = {
  id: string;
  name: string;
};

export async function getColisSalesJournalSupabase(input: {
  companyId: string;
  dateFrom: string;
  dateTo?: string | null;
  vendeurId?: string | null;
}): Promise<ColisSalesJournal> {
  const { data, error } = await supabase.rpc("get_colis_sales_journal", {
    p_company_id: input.companyId,
    p_date_from: input.dateFrom,
    p_date_to: input.dateTo ?? null,
    p_vendeur_id: input.vendeurId ?? null,
  });
  if (error) throw error;
  const raw = (data ?? {}) as Record<string, unknown>;
  const groups = Array.isArray(raw.groups) ? (raw.groups as Record<string, unknown>[]) : [];
  return {
    groups: groups.map((g) => ({
      vendeurId: (g.vendeurId as string | null) ?? null,
      vendeurName: String(g.vendeurName ?? "Agent inconnu"),
      vendeurUsername: (g.vendeurUsername as string | null) ?? null,
      colis: (Array.isArray(g.colis) ? (g.colis as Record<string, unknown>[]) : []).map((c) => ({
        id: String(c.id),
        numeroRecu: (c.numeroRecu as string | null) ?? null,
        createdAt: String(c.createdAt),
        nomExpediteur: String(c.nomExpediteur ?? ""),
        nomDestinataire: String(c.nomDestinataire ?? ""),
        montantFret: Number(c.montantFret ?? 0),
        valeurMarchandise: c.valeurMarchandise != null ? Number(c.valeurMarchandise) : null,
        gareDestination: String(c.gareDestination ?? ""),
      })),
      count: Number(g.count ?? 0),
      totalFrais: Number(g.totalFrais ?? 0),
      totalValeur: Number(g.totalValeur ?? 0),
    })),
    grandCount: Number(raw.grandCount ?? 0),
    grandTotalFrais: Number(raw.grandTotalFrais ?? 0),
    grandTotalValeur: Number(raw.grandTotalValeur ?? 0),
    fullAccess: Boolean(raw.fullAccess),
    gareScope: Boolean(raw.gareScope),
  };
}

export async function listCompanyColisVendeursSupabase(companyId: string): Promise<ColisVendeurOption[]> {
  const { data, error } = await supabase.rpc("list_company_colis_vendeurs", { p_company_id: companyId });
  if (error) throw error;
  const rows = Array.isArray(data) ? (data as Record<string, unknown>[]) : [];
  return rows.map((row) => ({ id: String(row.id), name: String(row.name ?? "") }));
}
