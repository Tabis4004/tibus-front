import { supabase } from "@/lib/supabase";

export type DemarcheurCompanyRow = {
  companyId: string;
  name: string;
  isActive: boolean;
  managerName: string | null;
  countryId: string | null;
  countryName: string | null;
  currency: string;
  ticketCount: number;
  salesTotal: number;
  commissionEarned: number;
  commissionTickets: number;
};

export type DemarcheurDashboard = {
  dateFrom: string;
  dateTo: string;
  countryId: string | null;
  companies: DemarcheurCompanyRow[];
  commissions: Record<string, unknown>;
};

export async function getDemarcheurDashboardSupabase(input?: {
  dateFrom?: string | null;
  dateTo?: string | null;
}): Promise<DemarcheurDashboard> {
  const { data, error } = await supabase.rpc("get_demarcheur_dashboard", {
    p_date_from: input?.dateFrom ?? null,
    p_date_to: input?.dateTo ?? null,
  });
  if (error) throw error;

  const payload = (data ?? {}) as Record<string, unknown>;
  const companies = Array.isArray(payload.companies) ? payload.companies : [];

  return {
    dateFrom: String(payload.dateFrom ?? ""),
    dateTo: String(payload.dateTo ?? ""),
    countryId: payload.countryId ? String(payload.countryId) : null,
    companies: companies.map((row) => {
      const item = row as Record<string, unknown>;
      return {
        companyId: String(item.companyId ?? ""),
        name: String(item.name ?? ""),
        isActive: Boolean(item.isActive),
        managerName: item.managerName ? String(item.managerName) : null,
        countryId: item.countryId ? String(item.countryId) : null,
        countryName: item.countryName ? String(item.countryName) : null,
        currency: String(item.currency ?? "XOF"),
        ticketCount: Number(item.ticketCount ?? 0),
        salesTotal: Number(item.salesTotal ?? 0),
        commissionEarned: Number(item.commissionEarned ?? 0),
        commissionTickets: Number(item.commissionTickets ?? 0),
      };
    }),
    commissions: (payload.commissions ?? {}) as Record<string, unknown>,
  };
}
