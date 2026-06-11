import { supabase } from "@/lib/supabase";

export type GareManagerRevenueRow = {
  gareId: string;
  gareName: string;
  managerUserId: string | null;
  managerName: string | null;
  sharePct: number;
  sharePctReservation: number;
  counterSalesGmv: number;
  counterShareCollected: number;
  reservationShareTotal: number;
  paidTotal: number;
  pendingTotal: number;
};

export type GareManagerRevenueSummary = {
  currency: string;
  rows: GareManagerRevenueRow[];
  totals: {
    counterSalesGmv: number;
    counterShareCollected: number;
    reservationShareTotal: number;
    paidTotal: number;
    pendingTotal: number;
  };
};

function num(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

export async function getGareManagerCounterRevenueSummarySupabase(
  companyId?: string | null,
): Promise<GareManagerRevenueSummary> {
  const { data, error } = await supabase.rpc("get_gare_manager_counter_revenue_summary", {
    p_company_id: companyId ?? null,
  });

  if (error) throw error;

  const payload = (data ?? {}) as Record<string, unknown>;
  const totals = (payload.totals ?? {}) as Record<string, unknown>;
  const rows = Array.isArray(payload.rows) ? payload.rows : [];

  return {
    currency: String(payload.currency ?? "XOF"),
    totals: {
      counterSalesGmv: num(totals.counterSalesGmv),
      counterShareCollected: num(totals.counterShareCollected),
      reservationShareTotal: num(totals.reservationShareTotal),
      paidTotal: num(totals.paidTotal),
      pendingTotal: num(totals.pendingTotal),
    },
    rows: rows.map((row) => {
      const r = row as Record<string, unknown>;
      return {
        gareId: String(r.gareId),
        gareName: String(r.gareName ?? ""),
        managerUserId: r.managerUserId ? String(r.managerUserId) : null,
        managerName: r.managerName ? String(r.managerName) : null,
        sharePct: num(r.sharePct),
        sharePctReservation: num(r.sharePctReservation),
        counterSalesGmv: num(r.counterSalesGmv),
        counterShareCollected: num(r.counterShareCollected),
        reservationShareTotal: num(r.reservationShareTotal),
        paidTotal: num(r.paidTotal),
        pendingTotal: num(r.pendingTotal),
      };
    }),
  };
}

export async function setGareManagerRevenueShareSupabase(input: {
  gareId: string;
  sharePct: number;
  sharePctReservation?: number;
  gestionnaireUserId?: string | null;
}) {
  const { data, error } = await supabase.rpc("set_gare_manager_revenue_share", {
    p_gare_id: input.gareId,
    p_share_pct: input.sharePct,
    p_share_pct_reservation: input.sharePctReservation ?? input.sharePct,
    p_gestionnaire_user_id: input.gestionnaireUserId ?? null,
  });

  if (error) throw error;
  return data;
}

export async function markGareManagerSharesPaidSupabase(gareId: string) {
  const { data, error } = await supabase.rpc("mark_gare_manager_shares_paid", {
    p_gare_id: gareId,
    p_booking_ids: null,
  });

  if (error) throw error;
  return Number(data ?? 0);
}
