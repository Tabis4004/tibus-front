import { supabase } from "@/lib/supabase";

export type PenaltyType = "percent" | "fixed";

export type CancellationPenaltyTier = {
  id?: string;
  label?: string;
  minHoursBeforeDeparture: number;
  penaltyType: PenaltyType;
  penaltyValue: number;
  sortOrder: number;
};

export type CompanyCancellationPolicy = {
  companyId: string;
  criticalHoursBeforeDeparture: number;
  criticalPenaltyType: PenaltyType;
  criticalPenaltyValue: number;
  isActive: boolean;
};

export type CompanyCancellationConfig = {
  policy: CompanyCancellationPolicy;
  tiers: CancellationPenaltyTier[];
};

export type CompanyTicketSaleRow = {
  bookingId: string;
  createdAt: string;
  reference: string;
  passengerName: string;
  seatNumber: string | null;
  ticketAmount: number;
  currency: string;
  saleChannel: string;
  ticketStatus: string;
  sellerUserId: string;
  sellerName: string | null;
  routeLabel: string;
  departureTime: string;
  hoursBeforeDeparture: number;
  canCancel: boolean;
};

export type CancellationPreview = {
  bookingId: string;
  reference: string;
  nominalAmount: number;
  penaltyAmount: number;
  refundAmount: number;
  hoursBeforeDeparture: number;
  staffOnly: boolean;
  penaltyType: PenaltyType;
  penaltyValue: number;
  tierLabel: string;
  canExecute: boolean;
};

function num(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

export async function getCompanyCancellationPolicySupabase(
  companyId: string,
): Promise<CompanyCancellationConfig> {
  const { data, error } = await supabase.rpc("get_company_cancellation_policy", {
    p_company_id: companyId,
  });
  if (error) throw error;

  const payload = (data ?? {}) as {
    policy?: Record<string, unknown>;
    tiers?: unknown[];
  };

  const policy = payload.policy ?? {};
  return {
    policy: {
      companyId: String(policy.companyId ?? companyId),
      criticalHoursBeforeDeparture: num(policy.criticalHoursBeforeDeparture) || 24,
      criticalPenaltyType: (policy.criticalPenaltyType as PenaltyType) ?? "percent",
      criticalPenaltyValue: num(policy.criticalPenaltyValue),
      isActive: policy.isActive == null ? true : Boolean(policy.isActive),
    },
    tiers: Array.isArray(payload.tiers)
      ? payload.tiers.map((row, index) => {
          const tier = row as Record<string, unknown>;
          return {
            id: tier.id ? String(tier.id) : undefined,
            label: tier.label ? String(tier.label) : undefined,
            minHoursBeforeDeparture: num(tier.minHoursBeforeDeparture),
            penaltyType: (tier.penaltyType as PenaltyType) ?? "percent",
            penaltyValue: num(tier.penaltyValue),
            sortOrder: num(tier.sortOrder) || index,
          };
        })
      : [],
  };
}

export async function upsertCompanyCancellationPolicySupabase(
  companyId: string,
  config: CompanyCancellationConfig,
): Promise<CompanyCancellationConfig> {
  const { data, error } = await supabase.rpc("upsert_company_cancellation_policy", {
    p_company_id: companyId,
    p_critical_hours: config.policy.criticalHoursBeforeDeparture,
    p_critical_penalty_type: config.policy.criticalPenaltyType,
    p_critical_penalty_value: config.policy.criticalPenaltyValue,
    p_is_active: config.policy.isActive,
    p_tiers: config.tiers.map((tier, index) => ({
      label: tier.label ?? "",
      minHoursBeforeDeparture: tier.minHoursBeforeDeparture,
      penaltyType: tier.penaltyType,
      penaltyValue: tier.penaltyValue,
      sortOrder: tier.sortOrder ?? index,
    })),
  });
  if (error) throw error;
  return getCompanyCancellationPolicySupabase(companyId);
}

export type CompanyTicketSalesFilters = {
  saleChannel?: string | null;
  createdFrom?: string | null;
  createdTo?: string | null;
  departureFrom?: string | null;
  departureTo?: string | null;
  search?: string | null;
  limit?: number;
  offset?: number;
};

function mapCompanyTicketSaleRows(data: unknown): CompanyTicketSaleRow[] {
  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    bookingId: String(row.booking_id),
    createdAt: String(row.created_at),
    reference: String(row.reference ?? ""),
    passengerName: String(row.passenger_name ?? ""),
    seatNumber: row.seat_number ? String(row.seat_number) : null,
    ticketAmount: num(row.ticket_amount),
    currency: String(row.currency ?? "XOF"),
    saleChannel: String(row.sale_channel ?? "traveler"),
    ticketStatus: String(row.ticket_status ?? "issued"),
    sellerUserId: String(row.seller_user_id ?? ""),
    sellerName: row.seller_name ? String(row.seller_name) : null,
    routeLabel: String(row.route_label ?? ""),
    departureTime: String(row.departure_time ?? ""),
    hoursBeforeDeparture: num(row.hours_before_departure),
    canCancel: Boolean(row.can_cancel),
  }));
}

function applyClientSalesFilters(
  rows: CompanyTicketSaleRow[],
  filters: CompanyTicketSalesFilters,
): CompanyTicketSaleRow[] {
  const search = filters.search?.trim().toLowerCase();
  return rows.filter((row) => {
    if (filters.saleChannel && row.saleChannel !== filters.saleChannel) return false;
    if (filters.createdFrom && row.createdAt < filters.createdFrom) return false;
    if (filters.createdTo && row.createdAt > filters.createdTo) return false;
    if (filters.departureFrom && row.departureTime < filters.departureFrom) return false;
    if (filters.departureTo && row.departureTime > filters.departureTo) return false;
    if (search) {
      const haystack = `${row.reference} ${row.passengerName}`.toLowerCase();
      if (!haystack.includes(search)) return false;
    }
    return true;
  });
}

export async function listCompanyTicketSalesSupabase(
  companyId: string,
  filters: CompanyTicketSalesFilters = {},
): Promise<CompanyTicketSaleRow[]> {
  const limit = filters.limit ?? 200;
  const offset = filters.offset ?? 0;
  const rpcArgs = {
    p_company_id: companyId,
    p_limit: limit,
    p_offset: offset,
    p_sale_channel: filters.saleChannel ?? null,
    p_created_from: filters.createdFrom ?? null,
    p_created_to: filters.createdTo ?? null,
    p_departure_from: filters.departureFrom ?? null,
    p_departure_to: filters.departureTo ?? null,
    p_search: filters.search?.trim() || null,
  };

  const { data, error } = await supabase.rpc("list_company_ticket_sales", rpcArgs);
  if (!error) return mapCompanyTicketSaleRows(data);

  const { data: legacyData, error: legacyError } = await supabase.rpc("list_company_ticket_sales", {
    p_company_id: companyId,
    p_limit: 500,
    p_offset: 0,
  });
  if (legacyError) throw error;

  const filtered = applyClientSalesFilters(mapCompanyTicketSaleRows(legacyData), filters);
  return filtered.slice(offset, offset + limit);
}

export async function previewTicketCancellationSupabase(
  bookingId: string,
): Promise<CancellationPreview> {
  const { data, error } = await supabase.rpc("preview_ticket_cancellation", {
    p_booking_id: bookingId,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    bookingId: String(row.bookingId ?? bookingId),
    reference: String(row.reference ?? ""),
    nominalAmount: num(row.nominalAmount),
    penaltyAmount: num(row.penaltyAmount),
    refundAmount: num(row.refundAmount),
    hoursBeforeDeparture: num(row.hoursBeforeDeparture),
    staffOnly: Boolean(row.staffOnly),
    penaltyType: (row.penaltyType as PenaltyType) ?? "percent",
    penaltyValue: num(row.penaltyValue),
    tierLabel: String(row.tierLabel ?? ""),
    canExecute: Boolean(row.canExecute),
  };
}

export async function cancelCompanyTicketSupabase(
  bookingId: string,
  reason?: string,
): Promise<CancellationPreview> {
  const { data, error } = await supabase.rpc("cancel_company_ticket", {
    p_booking_id: bookingId,
    p_reason: reason ?? null,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    bookingId: String(row.bookingId ?? bookingId),
    reference: String(row.reference ?? ""),
    nominalAmount: num(row.nominalAmount),
    penaltyAmount: num(row.penaltyAmount),
    refundAmount: num(row.refundAmount),
    hoursBeforeDeparture: num(row.hoursBeforeDeparture),
    staffOnly: Boolean(row.staffOnly),
    penaltyType: (row.penaltyType as PenaltyType) ?? "percent",
    penaltyValue: num(row.penaltyValue),
    tierLabel: String(row.tierLabel ?? ""),
    canExecute: true,
  };
}
