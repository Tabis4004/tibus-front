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

export type CommissionSettingScope = "country" | "company";

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
}): Promise<CommissionSetting | null> {
  const { data, error } = await supabase.rpc("upsert_commission_setting", {
    p_scope: params.scope,
    p_country_id: params.countryId,
    p_company_id: params.companyId,
    p_rate: params.rate,
    p_paid_by: params.paidBy,
    p_is_active: params.isActive ?? true,
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
