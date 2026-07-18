import { supabase } from "@/lib/supabase";

export type CompanyAccountingKPIs = {
  totalBookings: number;
  confirmedBookings: number;
  totalRevenue: number;
  todayRevenue: number;
  currency: string;
  totalTrips: number;
  upcomingTrips: number;
  todayTrips: number;
  completedTrips: number;
  totalTravelers: number;
  totalSellers: number;
  totalBuses: number;
  caisseRevenue: number;
  onlineRevenue: number;
  sellerCommissionsPending: number;
};

export type CompanyRevenuePoint = {
  date: string;
  revenue: number;
  tickets: number;
};

export type CompanyRecentBooking = {
  _id: string;
  _creationTime: number;
  passengerName: string;
  passengerPhone: string | null;
  status: string;
  totalPrice: number;
  currency: string;
  bookingReference: string;
  sellerName: string | null;
  originCity: string;
  destinationCity: string;
  departureTime: string;
  busName: string;
};

export type CompanyAccountingDashboard = {
  company: {
    id: string;
    name: string;
    currency: string;
    commissionRate: number;
    commissionPaidBy: string;
    commissionScope: string;
  };
  kpis: CompanyAccountingKPIs;
  revenueChart: CompanyRevenuePoint[];
  recentBookings: CompanyRecentBooking[];
};

export type SellerCommissionEntry = {
  bookingId: string;
  createdAt: string;
  companyId: string;
  companyName: string;
  reference: string;
  passengerName: string;
  ticketAmount: number;
  commissionRate: number;
  commissionAmount: number;
  commissionStatus: string;
  currency: string;
  routeLabel: string;
  departureTime: string;
  sellerUserId: string;
  sellerName: string | null;
  networkMasterUserId: string | null;
  networkMasterName: string | null;
};

export type SellerCommissionSummary = {
  entries: SellerCommissionEntry[];
  pendingTotal: number;
  paidTotal: number;
  totalTickets: number;
  currency: string;
};

export type PlatformCommissionSummary = {
  capturedTotal: number;
  travelerOnlineCaptured: number;
  counterCompanyCaptured: number;
  travelerNominalTotal: number;
  counterNominalTotal: number;
  ticketCount: number;
  counterTicketCount: number;
  stakeholderPending: number;
  stakeholderPaid: number;
  currency: string;
};

export type CommissionSettingScope = "country" | "company";
export type CommissionAmountType = "percentage" | "fixed";

export type ResolvedPlatformCommission = {
  rate: number;
  paidBy: "company" | "traveler";
  source: "company_setting" | "company_profile" | "default";
  amountType: CommissionAmountType;
  fixedAmount: number;
};

/**
 * Taux commission plateforme pour le revenue sharing : toujours celui de la compagnie.
 * Le réglage pays (CommissionSettings scope country) n'est pas utilisé ici.
 */
export function resolveCompanyPlatformCommission(
  company: { id: string; commissionRate?: number | null },
  settings: CommissionSetting[],
): ResolvedPlatformCommission {
  const companySetting = settings.find(
    (setting) =>
      setting.scope === "company" &&
      setting.companyId === company.id &&
      setting.isActive !== false,
  );
  if (companySetting) {
    return {
      rate: companySetting.rate,
      paidBy: companySetting.paidBy,
      source: "company_setting",
      amountType: companySetting.amountType,
      fixedAmount: companySetting.fixedAmount,
    };
  }
  if (company.commissionRate != null && Number.isFinite(company.commissionRate)) {
    return {
      rate: company.commissionRate,
      paidBy: "traveler",
      source: "company_profile",
      amountType: "percentage",
      fixedAmount: 0,
    };
  }
  return {
    rate: 5,
    paidBy: "traveler",
    source: "default",
    amountType: "percentage",
    fixedAmount: 0,
  };
}

export type CommissionSetting = {
  id: string | null;
  scope: CommissionSettingScope;
  countryId: string;
  countryName: string;
  companyId: string | null;
  companyName: string | null;
  rate: number;
  paidBy: "company" | "traveler";
  isActive: boolean;
  amountType: CommissionAmountType;
  fixedAmount: number;
  source: string;
  updatedAt: string | null;
  updatedByName: string | null;
};

type SellerCommissionRpcRow = {
  booking_id: unknown;
  created_at: unknown;
  company_id: unknown;
  company_name: unknown;
  reference: unknown;
  passenger_name: unknown;
  ticket_amount: unknown;
  commission_rate: unknown;
  commission_amount: unknown;
  commission_status: unknown;
  currency: unknown;
  route_label: unknown;
  departure_time: unknown;
  seller_user_id: unknown;
  seller_name: unknown;
  network_master_user_id: unknown;
  network_master_name: unknown;
};

type CommissionSettingRpcRow = {
  id: unknown;
  scope: unknown;
  country_id: unknown;
  country_name: unknown;
  company_id: unknown;
  company_name: unknown;
  rate: unknown;
  paid_by: unknown;
  is_active: unknown;
  amount_type: unknown;
  fixed_amount: unknown;
  source: unknown;
  updated_at: unknown;
  updated_by_name: unknown;
};

function numberValue(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeDashboard(payload: unknown): CompanyAccountingDashboard {
  const data = payload as Partial<CompanyAccountingDashboard> | null;
  const company = data?.company ?? {
    id: "",
    name: "",
    currency: "XOF",
    commissionRate: 0,
    commissionPaidBy: "company",
    commissionScope: "legacy_company",
  };
  const kpis = data?.kpis ?? ({} as Partial<CompanyAccountingKPIs>);

  return {
    company: {
      id: String(company.id ?? ""),
      name: String(company.name ?? ""),
      currency: String(company.currency ?? "XOF"),
      commissionRate: numberValue(company.commissionRate),
      commissionPaidBy: String(company.commissionPaidBy ?? "company"),
      commissionScope: String(company.commissionScope ?? "legacy_company"),
    },
    kpis: {
      totalBookings: numberValue(kpis.totalBookings),
      confirmedBookings: numberValue(kpis.confirmedBookings),
      totalRevenue: numberValue(kpis.totalRevenue),
      todayRevenue: numberValue(kpis.todayRevenue),
      currency: String(kpis.currency ?? company.currency ?? "XOF"),
      totalTrips: numberValue(kpis.totalTrips),
      upcomingTrips: numberValue(kpis.upcomingTrips),
      todayTrips: numberValue(kpis.todayTrips),
      completedTrips: numberValue(kpis.completedTrips),
      totalTravelers: numberValue(kpis.totalTravelers),
      totalSellers: numberValue(kpis.totalSellers),
      totalBuses: numberValue(kpis.totalBuses),
      caisseRevenue: numberValue(kpis.caisseRevenue),
      onlineRevenue: numberValue(kpis.onlineRevenue),
      sellerCommissionsPending: numberValue(kpis.sellerCommissionsPending),
    },
    revenueChart: (data?.revenueChart ?? []).map((point) => ({
      date: String(point.date),
      revenue: numberValue(point.revenue),
      tickets: numberValue(point.tickets),
    })),
    recentBookings: (data?.recentBookings ?? []).map((booking) => ({
      _id: String(booking._id),
      _creationTime: numberValue(booking._creationTime),
      passengerName: String(booking.passengerName ?? ""),
      passengerPhone: booking.passengerPhone ?? null,
      status: String(booking.status ?? "confirmed"),
      totalPrice: numberValue(booking.totalPrice),
      currency: String(booking.currency ?? company.currency ?? "XOF"),
      bookingReference: String(booking.bookingReference ?? ""),
      sellerName: booking.sellerName ?? null,
      originCity: String(booking.originCity ?? ""),
      destinationCity: String(booking.destinationCity ?? ""),
      departureTime: String(booking.departureTime ?? ""),
      busName: String(booking.busName ?? ""),
    })),
  };
}

function normalizeCommissionSetting(row: CommissionSettingRpcRow): CommissionSetting {
  const paidBy = String(row.paid_by ?? "company");

  return {
    id: row.id ? String(row.id) : null,
    scope: String(row.scope) === "company" ? "company" : "country",
    countryId: String(row.country_id),
    countryName: String(row.country_name ?? ""),
    companyId: row.company_id ? String(row.company_id) : null,
    companyName: row.company_name ? String(row.company_name) : null,
    rate: numberValue(row.rate),
    paidBy: paidBy === "traveler" ? "traveler" : "company",
    isActive: Boolean(row.is_active),
    amountType: String(row.amount_type) === "fixed" ? "fixed" : "percentage",
    fixedAmount: numberValue(row.fixed_amount),
    source: String(row.source ?? "unset"),
    updatedAt: row.updated_at ? String(row.updated_at) : null,
    updatedByName: row.updated_by_name ? String(row.updated_by_name) : null,
  };
}

export async function getCompanyAccountingDashboardSupabase(
  companyId?: string | null,
): Promise<CompanyAccountingDashboard> {
  const { data, error } = await supabase.rpc("get_company_accounting_dashboard", {
    p_company_id: companyId ?? null,
  });

  if (error) throw error;
  return normalizeDashboard(data);
}

export type CompanyGareRevenue = {
  gareId: string;
  gareName: string;
  ticketRevenue: number;
  colisRevenue: number;
  totalRevenue: number;
  openCaisseBalance: number;
  currency: string;
};

/** Récapitulatif des montants PAR AGENCE (voir migration 182) — le
 * dashboard global (get_company_accounting_dashboard) n'expose qu'un
 * montant unique pour toute la compagnie, sans détail par gare ni les
 * ventes colis. */
export async function getCompanyRevenueByGareSupabase(
  companyId: string,
): Promise<CompanyGareRevenue[]> {
  const { data, error } = await supabase.rpc("get_company_revenue_by_gare", {
    p_company_id: companyId,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    gareId: String(row.gareId),
    gareName: String(row.gareName ?? ""),
    ticketRevenue: numberValue(row.ticketRevenue),
    colisRevenue: numberValue(row.colisRevenue),
    totalRevenue: numberValue(row.totalRevenue),
    openCaisseBalance: numberValue(row.openCaisseBalance),
    currency: String(row.currency ?? "XOF"),
  }));
}

export async function getSellerCommissionSummarySupabase(): Promise<SellerCommissionSummary> {
  const { data, error } = await supabase.rpc("get_seller_commission_summary");

  if (error) throw error;

  const entries: SellerCommissionEntry[] = ((data ?? []) as SellerCommissionRpcRow[]).map((row) => ({
    bookingId: String(row.booking_id),
    createdAt: String(row.created_at),
    companyId: String(row.company_id),
    companyName: String(row.company_name ?? ""),
    reference: String(row.reference ?? ""),
    passengerName: String(row.passenger_name ?? ""),
    ticketAmount: numberValue(row.ticket_amount),
    commissionRate: numberValue(row.commission_rate),
    commissionAmount: numberValue(row.commission_amount),
    commissionStatus: String(row.commission_status ?? "pending"),
    currency: String(row.currency ?? "XOF"),
    routeLabel: String(row.route_label ?? ""),
    departureTime: String(row.departure_time ?? ""),
    sellerUserId: String(row.seller_user_id),
    sellerName: row.seller_name ? String(row.seller_name) : null,
    networkMasterUserId: row.network_master_user_id
      ? String(row.network_master_user_id)
      : null,
    networkMasterName: row.network_master_name
      ? String(row.network_master_name)
      : null,
  }));

  return {
    entries,
    pendingTotal: entries
      .filter((entry) => entry.commissionStatus === "pending")
      .reduce((sum, entry) => sum + entry.commissionAmount, 0),
    paidTotal: entries
      .filter((entry) => entry.commissionStatus === "paid")
      .reduce((sum, entry) => sum + entry.commissionAmount, 0),
    totalTickets: entries.length,
    currency: entries[0]?.currency ?? "XOF",
  };
}

export async function getPlatformCommissionSummarySupabase(
  countryId?: string | null,
): Promise<PlatformCommissionSummary> {
  const { data, error } = await supabase.rpc("get_platform_commission_summary", {
    p_country_id: countryId ?? null,
  });

  if (error) throw error;

  const payload = (data ?? {}) as Record<string, unknown>;
  return {
    capturedTotal: numberValue(payload.capturedTotal),
    travelerOnlineCaptured: numberValue(payload.travelerOnlineCaptured),
    counterCompanyCaptured: numberValue(payload.counterCompanyCaptured),
    travelerNominalTotal: numberValue(payload.travelerNominalTotal),
    counterNominalTotal: numberValue(payload.counterNominalTotal),
    ticketCount: Number(payload.ticketCount ?? 0),
    counterTicketCount: Number(payload.counterTicketCount ?? 0),
    stakeholderPending: numberValue(payload.stakeholderPending),
    stakeholderPaid: numberValue(payload.stakeholderPaid),
    currency: String(payload.currency ?? "XOF"),
  };
}

export async function listCommissionSettingsSupabase(): Promise<CommissionSetting[]> {
  const { data, error } = await supabase.rpc("list_commission_settings");

  if (error) throw error;
  return ((data ?? []) as CommissionSettingRpcRow[]).map(normalizeCommissionSetting);
}

export async function upsertCommissionSettingSupabase(params: {
  scope: CommissionSettingScope;
  countryId: string | null;
  companyId: string | null;
  rate: number;
  paidBy: "company" | "traveler";
  isActive?: boolean;
  amountType?: CommissionAmountType;
  fixedAmount?: number;
}): Promise<CommissionSetting | null> {
  const { data, error } = await supabase.rpc("upsert_commission_setting", {
    p_scope: params.scope,
    p_country_id: params.countryId,
    p_company_id: params.companyId,
    p_rate: params.rate,
    p_paid_by: params.paidBy,
    p_is_active: params.isActive ?? true,
    p_amount_type: params.amountType ?? "percentage",
    p_fixed_amount: params.fixedAmount ?? 0,
  });

  if (error) throw error;
  const rows = (data ?? []) as CommissionSettingRpcRow[];
  return rows[0] ? normalizeCommissionSetting(rows[0]) : null;
}

export async function deleteCommissionSettingSupabase(settingId: string): Promise<void> {
  const { error } = await supabase.rpc("delete_commission_setting", {
    p_setting_id: settingId,
  });

  if (error) throw error;
}

export type SellerCommissionDashboardEntry = {
  bookingId: string;
  createdAt: string;
  commissionAmount: number;
  commissionStatus: string;
  companyName: string;
  reference: string;
  currency: string;
};

export type SellerCommissionDashboard = {
  sellerUserId: string;
  dateFrom: string;
  dateTo: string;
  currency: string;
  totalAmount: number;
  pendingAmount: number;
  paymentRequestedAmount: number;
  paidAmount: number;
  ticketCount: number;
  entries: SellerCommissionDashboardEntry[];
};

export async function getSellerCommissionDashboardSupabase(input?: {
  dateFrom?: string | null;
  dateTo?: string | null;
  sellerUserId?: string | null;
}): Promise<SellerCommissionDashboard> {
  const { data, error } = await supabase.rpc("get_seller_commission_dashboard", {
    p_date_from: input?.dateFrom ?? null,
    p_date_to: input?.dateTo ?? null,
    p_seller_user_id: input?.sellerUserId ?? null,
  });
  if (error) throw error;
  const payload = (data ?? {}) as Record<string, unknown>;
  const entries = Array.isArray(payload.entries) ? payload.entries : [];
  return {
    sellerUserId: String(payload.sellerUserId ?? ""),
    dateFrom: String(payload.dateFrom ?? ""),
    dateTo: String(payload.dateTo ?? ""),
    currency: String(payload.currency ?? "XOF"),
    totalAmount: numberValue(payload.totalAmount),
    pendingAmount: numberValue(payload.pendingAmount),
    paymentRequestedAmount: numberValue(payload.paymentRequestedAmount),
    paidAmount: numberValue(payload.paidAmount),
    ticketCount: Number(payload.ticketCount ?? 0),
    entries: entries.map((row) => {
      const item = row as Record<string, unknown>;
      return {
        bookingId: String(item.bookingId ?? ""),
        createdAt: String(item.createdAt ?? ""),
        commissionAmount: numberValue(item.commissionAmount),
        commissionStatus: String(item.commissionStatus ?? "pending"),
        companyName: String(item.companyName ?? ""),
        reference: String(item.reference ?? ""),
        currency: String(item.currency ?? "XOF"),
      };
    }),
  };
}

export async function requestSellerCommissionPaymentSupabase(input?: {
  dateFrom?: string | null;
  dateTo?: string | null;
  note?: string | null;
}): Promise<string> {
  const { data, error } = await supabase.rpc("request_seller_commission_payment", {
    p_date_from: input?.dateFrom ?? null,
    p_date_to: input?.dateTo ?? null,
    p_note: input?.note ?? null,
  });
  if (error) throw error;
  return String(data);
}

export async function confirmSellerCommissionPaymentSupabase(requestId: string): Promise<void> {
  const { error } = await supabase.rpc("confirm_seller_commission_payment", {
    p_request_id: requestId,
  });
  if (error) throw error;
}

export async function updateCompanyRecruitedBySupabase(
  companyId: string,
  recruitedByUserId: string | null,
): Promise<void> {
  const { error } = await supabase.rpc("update_company_recruited_by", {
    p_company_id: companyId,
    p_recruited_by_user_id: recruitedByUserId,
  });
  if (error) throw error;
}
