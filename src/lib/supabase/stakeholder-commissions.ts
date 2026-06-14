import { randomUUID } from "@/lib/random-id.ts";
import { supabase } from "@/lib/supabase";

export type StakeholderRole =
  | "platform"
  | "admin_pays"
  | "master"
  | "seller"
  | "company"
  | "recruiter"
  | "custom";

export type StakeholderCommissionBaseType =
  | "platform_commission"
  | "gateway_amount"
  | "total_amount"
  | "platform_net";

export type StakeholderCommissionSetting = {
  id: string | null;
  scope: "global" | "country" | "company";
  countryId: string | null;
  countryName: string | null;
  companyId: string | null;
  companyName: string | null;
  stakeholderRole: StakeholderRole;
  label: string | null;
  beneficiaryUserId: string | null;
  beneficiaryName: string | null;
  rate: number;
  baseType: StakeholderCommissionBaseType;
  sortOrder: number;
  isActive: boolean;
  source: string;
  updatedAt: string | null;
  updatedByName: string | null;
};

export type StakeholderAttributionPreviewItem = {
  stakeholderRole: StakeholderRole;
  rate: number;
  baseType: StakeholderCommissionBaseType;
  baseAmount: number;
  amount: number;
  source: string;
};

export type StakeholderAttributionPreview = {
  platformCommissionAmount: number;
  countryId: string | null;
  totalRatePercent: number;
  items: StakeholderAttributionPreviewItem[];
};

type RpcRow = {
  id: unknown;
  scope: unknown;
  country_id: unknown;
  country_name: unknown;
  company_id: unknown;
  company_name: unknown;
  stakeholder_role: unknown;
  label: unknown;
  beneficiary_user_id: unknown;
  beneficiary_name: unknown;
  rate: unknown;
  base_type: unknown;
  sort_order: unknown;
  is_active: unknown;
  source: unknown;
  updated_at: unknown;
  updated_by_name: unknown;
};

function mapRow(row: RpcRow): StakeholderCommissionSetting {
  return {
    id: row.id ? String(row.id) : null,
    scope: String(row.scope) as "global" | "country" | "company",
    countryId: row.country_id ? String(row.country_id) : null,
    countryName: row.country_name ? String(row.country_name) : null,
    companyId: row.company_id ? String(row.company_id) : null,
    companyName: row.company_name ? String(row.company_name) : null,
    stakeholderRole: String(row.stakeholder_role) as StakeholderRole,
    label: row.label ? String(row.label) : null,
    beneficiaryUserId: row.beneficiary_user_id ? String(row.beneficiary_user_id) : null,
    beneficiaryName: row.beneficiary_name ? String(row.beneficiary_name) : null,
    rate: Number(row.rate ?? 0),
    baseType: String(row.base_type ?? "platform_commission") as StakeholderCommissionBaseType,
    sortOrder: Number(row.sort_order ?? 0),
    isActive: Boolean(row.is_active),
    source: String(row.source ?? "unset"),
    updatedAt: row.updated_at ? String(row.updated_at) : null,
    updatedByName: row.updated_by_name ? String(row.updated_by_name) : null,
  };
}

export async function listStakeholderCommissionSettingsSupabase(
  countryId?: string | null,
): Promise<StakeholderCommissionSetting[]> {
  const { data, error } = await supabase.rpc("list_stakeholder_commission_settings", {
    p_country_id: countryId ?? null,
  });

  if (error) throw error;

  return (data ?? []).map((row: RpcRow) => mapRow(row));
}

export async function upsertStakeholderCommissionSettingSupabase(input: {
  scope: "global" | "country" | "company";
  countryId?: string | null;
  companyId?: string | null;
  stakeholderRole: StakeholderRole;
  rate: number;
  baseType?: StakeholderCommissionBaseType;
  isActive?: boolean;
  label?: string | null;
  beneficiaryUserId?: string | null;
  settingId?: string | null;
}): Promise<string | null> {
  const { data, error } = await supabase.rpc("upsert_stakeholder_commission_setting", {
    p_scope: input.scope,
    p_country_id: input.scope === "global" ? null : input.countryId ?? null,
    p_company_id: input.scope === "company" ? input.companyId ?? null : null,
    p_stakeholder_role: input.stakeholderRole,
    p_rate: input.rate,
    p_base_type: input.baseType ?? "platform_commission",
    p_is_active: input.isActive ?? true,
    p_label: input.label ?? null,
    p_beneficiary_user_id: input.beneficiaryUserId ?? null,
    p_setting_id: input.settingId ?? null,
  });

  if (error) throw error;
  return data ? String(data) : null;
}

export async function deleteStakeholderCommissionSettingSupabase(
  settingId: string,
): Promise<void> {
  const { error } = await supabase.rpc("delete_stakeholder_commission_setting", {
    p_setting_id: settingId,
  });
  if (error) throw error;
}

export async function previewStakeholderCommissionAttributionSupabase(input: {
  platformCommissionAmount: number;
  countryId?: string | null;
}): Promise<StakeholderAttributionPreview> {
  const { data, error } = await supabase.rpc("preview_stakeholder_commission_attribution", {
    p_platform_commission_amount: input.platformCommissionAmount,
    p_country_id: input.countryId ?? null,
  });

  if (error) throw error;

  const payload = data as Record<string, unknown>;
  const items = Array.isArray(payload.items) ? payload.items : [];

  return {
    platformCommissionAmount: Number(payload.platformCommissionAmount ?? 0),
    countryId: payload.countryId ? String(payload.countryId) : null,
    totalRatePercent: Number(payload.totalRatePercent ?? 0),
    items: items.map((item) => {
      const row = item as Record<string, unknown>;
      return {
        stakeholderRole: String(row.stakeholderRole) as StakeholderRole,
        rate: Number(row.rate ?? 0),
        baseType: String(row.baseType ?? "platform_commission") as StakeholderCommissionBaseType,
        baseAmount: Number(row.baseAmount ?? 0),
        amount: Number(row.amount ?? 0),
        source: String(row.source ?? "unset"),
      };
    }),
  };
}

/** Taux fixes au niveau pays (bénéficiaire connu, une ligne par rôle). */
export const STAKEHOLDER_COUNTRY_ROLES: StakeholderRole[] = [
  "platform",
  "admin_pays",
  "master",
  "seller",
];

/** Taux dynamiques par compagnie (ex. recruteur = bénéficiaire lié à la compagnie). */
export const STAKEHOLDER_COMPANY_ROLES: StakeholderRole[] = ["recruiter"];

/** Ordre d'affichage / simulation (pays + dynamiques compagnie). */
export const STAKEHOLDER_SPLIT_ROLES: StakeholderRole[] = [
  ...STAKEHOLDER_COUNTRY_ROLES,
  ...STAKEHOLDER_COMPANY_ROLES,
];

export const STAKEHOLDER_ROLE_ORDER: StakeholderRole[] = [
  ...STAKEHOLDER_SPLIT_ROLES,
  "company",
];

/** Simulation locale à partir des taux saisis (sans RPC). */
export function previewStakeholderCommissionAttributionLocal(input: {
  platformCommissionAmount: number;
  countryId?: string | null;
  roles?: StakeholderRole[];
  rateDrafts: Record<string, string>;
  settings?: StakeholderCommissionSetting[];
}): StakeholderAttributionPreview {
  const roles = input.roles ?? STAKEHOLDER_SPLIT_ROLES;
  const settingsByRole = new Map(
    (input.settings ?? []).map((row) => [row.stakeholderRole, row]),
  );

  let totalRatePercent = 0;
  const items: StakeholderAttributionPreviewItem[] = roles.map((role) => {
    const saved = settingsByRole.get(role);
    const parsedRate = Number(String(input.rateDrafts[role] ?? saved?.rate ?? 0).replace(",", "."));
    const rate = Number.isFinite(parsedRate) ? parsedRate : 0;
    const baseType = saved?.baseType ?? "platform_commission";
    const baseAmount = input.platformCommissionAmount;
    const amount = Math.round((baseAmount * rate) / 100 * 100) / 100;
    totalRatePercent += rate;

    return {
      stakeholderRole: role,
      rate,
      baseType,
      baseAmount,
      amount,
      source: saved?.source ?? "draft",
    };
  });

  return {
    platformCommissionAmount: input.platformCommissionAmount,
    countryId: input.countryId ?? null,
    totalRatePercent,
    items,
  };
}

export type StakeholderTicketSimulation = StakeholderAttributionPreview & {
  ticketCount: number;
  avgTicketAmount: number;
  commissionRatePct: number;
  gmv: number;
  poolPerTicket: number;
};

export function computeStakeholderTicketSimulation(input: {
  ticketCount: number;
  avgTicketAmount: number;
  commissionRatePct: number;
  countryId?: string | null;
  rateDrafts: Record<string, string>;
  settings?: StakeholderCommissionSetting[];
}): StakeholderTicketSimulation | null {
  const { ticketCount, avgTicketAmount, commissionRatePct } = input;
  if (!Number.isFinite(ticketCount) || ticketCount <= 0) return null;
  if (!Number.isFinite(avgTicketAmount) || avgTicketAmount <= 0) return null;
  if (!Number.isFinite(commissionRatePct) || commissionRatePct < 0) return null;

  const gmv = ticketCount * avgTicketAmount;
  const platformCommissionAmount =
    Math.round(((gmv * commissionRatePct) / 100) * 100) / 100;
  const poolPerTicket =
    Math.round(((avgTicketAmount * commissionRatePct) / 100) * 100) / 100;

  const attribution = previewStakeholderCommissionAttributionLocal({
    platformCommissionAmount,
    countryId: input.countryId,
    rateDrafts: input.rateDrafts,
    settings: input.settings,
  });

  return {
    ...attribution,
    ticketCount,
    avgTicketAmount,
    commissionRatePct,
    gmv,
    poolPerTicket,
  };
}

export type StakeholderCommissionBalance = {
  countryId: string;
  countryName: string;
  stakeholderRole: StakeholderRole;
  beneficiaryUserId: string | null;
  beneficiaryName: string | null;
  rate: number;
  baseType: StakeholderCommissionBaseType;
  earnedAmount: number;
  paidAmount: number;
  pendingAmount: number;
  balanceDue: number;
  minimumPayout: number;
  currency: string;
};

export type StakeholderCommissionSettlement = {
  id: string;
  countryId: string;
  countryName: string;
  stakeholderRole: StakeholderRole;
  beneficiaryUserId: string | null;
  beneficiaryName: string | null;
  amount: number;
  currency: string;
  status: "pending_confirmation" | "confirmed" | "rejected" | "cancelled";
  earnedSnapshot: number | null;
  note: string | null;
  initiatedBy: string;
  initiatedByName: string | null;
  initiatedAt: string;
  confirmedBy: string | null;
  confirmedByName: string | null;
  confirmedAt: string | null;
  rejectedBy: string | null;
  rejectedByName: string | null;
  rejectedAt: string | null;
  rejectionReason: string | null;
  approvalNote: string | null;
  paymentProofPath: string | null;
  paymentProofFileName: string | null;
};

type BalanceRpcRow = {
  country_id: unknown;
  country_name: unknown;
  stakeholder_role: unknown;
  beneficiary_user_id: unknown;
  beneficiary_name: unknown;
  rate: unknown;
  base_type: unknown;
  earned_amount: unknown;
  paid_amount: unknown;
  pending_amount: unknown;
  balance_due: unknown;
  minimum_payout: unknown;
  currency: unknown;
};

type SettlementRpcRow = {
  id: unknown;
  country_id: unknown;
  country_name: unknown;
  stakeholder_role: unknown;
  beneficiary_user_id: unknown;
  beneficiary_name: unknown;
  amount: unknown;
  currency: unknown;
  status: unknown;
  earned_snapshot: unknown;
  note: unknown;
  initiated_by: unknown;
  initiated_by_name: unknown;
  initiated_at: unknown;
  confirmed_by: unknown;
  confirmed_by_name: unknown;
  confirmed_at: unknown;
  rejected_by: unknown;
  rejected_by_name: unknown;
  rejected_at: unknown;
  rejection_reason: unknown;
  approval_note: unknown;
  payment_proof_path: unknown;
  payment_proof_file_name: unknown;
};

function mapBalanceRow(row: BalanceRpcRow): StakeholderCommissionBalance {
  return {
    countryId: String(row.country_id),
    countryName: String(row.country_name ?? ""),
    stakeholderRole: String(row.stakeholder_role) as StakeholderRole,
    beneficiaryUserId: row.beneficiary_user_id ? String(row.beneficiary_user_id) : null,
    beneficiaryName: row.beneficiary_name ? String(row.beneficiary_name) : null,
    rate: Number(row.rate ?? 0),
    baseType: String(row.base_type ?? "platform_commission") as StakeholderCommissionBaseType,
    earnedAmount: Number(row.earned_amount ?? 0),
    paidAmount: Number(row.paid_amount ?? 0),
    pendingAmount: Number(row.pending_amount ?? 0),
    balanceDue: Number(row.balance_due ?? 0),
    minimumPayout: Number(row.minimum_payout ?? 0),
    currency: String(row.currency ?? "XOF"),
  };
}

function mapSettlementRow(row: SettlementRpcRow): StakeholderCommissionSettlement {
  return {
    id: String(row.id),
    countryId: String(row.country_id),
    countryName: String(row.country_name ?? ""),
    stakeholderRole: String(row.stakeholder_role) as StakeholderRole,
    beneficiaryUserId: row.beneficiary_user_id ? String(row.beneficiary_user_id) : null,
    beneficiaryName: row.beneficiary_name ? String(row.beneficiary_name) : null,
    amount: Number(row.amount ?? 0),
    currency: String(row.currency ?? "XOF"),
    status: String(row.status ?? "pending_confirmation") as StakeholderCommissionSettlement["status"],
    earnedSnapshot: row.earned_snapshot == null ? null : Number(row.earned_snapshot),
    note: row.note ? String(row.note) : null,
    initiatedBy: String(row.initiated_by),
    initiatedByName: row.initiated_by_name ? String(row.initiated_by_name) : null,
    initiatedAt: String(row.initiated_at),
    confirmedBy: row.confirmed_by ? String(row.confirmed_by) : null,
    confirmedByName: row.confirmed_by_name ? String(row.confirmed_by_name) : null,
    confirmedAt: row.confirmed_at ? String(row.confirmed_at) : null,
    rejectedBy: row.rejected_by ? String(row.rejected_by) : null,
    rejectedByName: row.rejected_by_name ? String(row.rejected_by_name) : null,
    rejectedAt: row.rejected_at ? String(row.rejected_at) : null,
    rejectionReason: row.rejection_reason ? String(row.rejection_reason) : null,
    approvalNote: row.approval_note ? String(row.approval_note) : null,
    paymentProofPath: row.payment_proof_path ? String(row.payment_proof_path) : null,
    paymentProofFileName: row.payment_proof_file_name ? String(row.payment_proof_file_name) : null,
  };
}

export async function listStakeholderCommissionBalancesSupabase(
  countryId?: string | null,
): Promise<StakeholderCommissionBalance[]> {
  const { data, error } = await supabase.rpc("list_stakeholder_commission_balances", {
    p_country_id: countryId ?? null,
  });
  if (error) throw error;
  return (data ?? []).map((row: BalanceRpcRow) => mapBalanceRow(row));
}

export async function initiateStakeholderCommissionSettlementSupabase(input: {
  countryId: string;
  stakeholderRole: StakeholderRole;
  beneficiaryUserId?: string | null;
  note?: string | null;
}): Promise<string> {
  const { data, error } = await supabase.rpc("initiate_stakeholder_commission_settlement", {
    p_country_id: input.countryId,
    p_stakeholder_role: input.stakeholderRole,
    p_beneficiary_user_id: input.beneficiaryUserId ?? null,
    p_note: input.note ?? null,
  });
  if (error) throw error;
  return String(data);
}

export const STAKEHOLDER_PAYMENT_PROOF_BUCKET = "stakeholder-payment-proofs";

export async function uploadStakeholderPaymentProof(
  countryId: string,
  file: File,
): Promise<{ path: string; fileName: string }> {
  const safeName = file.name.replace(/[^\w.\-]+/g, "_");
  const path = `${countryId}/${randomUUID()}-${safeName}`;
  const { error } = await supabase.storage
    .from(STAKEHOLDER_PAYMENT_PROOF_BUCKET)
    .upload(path, file, { upsert: false, contentType: file.type || undefined });
  if (error) throw error;
  return { path, fileName: file.name };
}

export async function getStakeholderPaymentProofUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from(STAKEHOLDER_PAYMENT_PROOF_BUCKET)
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

export async function confirmStakeholderCommissionSettlementSupabase(input: {
  settlementId: string;
  approvalNote: string;
  paymentProofPath: string;
  paymentProofFileName?: string | null;
}): Promise<void> {
  const { error } = await supabase.rpc("confirm_stakeholder_commission_settlement", {
    p_settlement_id: input.settlementId,
    p_approval_note: input.approvalNote,
    p_payment_proof_path: input.paymentProofPath,
    p_payment_proof_file_name: input.paymentProofFileName ?? null,
  });
  if (error) throw error;
}

export async function rejectStakeholderCommissionSettlementSupabase(
  settlementId: string,
  reason?: string | null,
): Promise<void> {
  const { error } = await supabase.rpc("reject_stakeholder_commission_settlement", {
    p_settlement_id: settlementId,
    p_reason: reason ?? null,
  });
  if (error) throw error;
}

export async function cancelStakeholderCommissionSettlementSupabase(
  settlementId: string,
): Promise<void> {
  const { error } = await supabase.rpc("cancel_stakeholder_commission_settlement", {
    p_settlement_id: settlementId,
  });
  if (error) throw error;
}

export async function listStakeholderCommissionSettlementHistorySupabase(input?: {
  countryId?: string | null;
  beneficiaryUserId?: string | null;
  limit?: number;
}): Promise<StakeholderCommissionSettlement[]> {
  const { data, error } = await supabase.rpc("list_stakeholder_commission_settlement_history", {
    p_country_id: input?.countryId ?? null,
    p_beneficiary_user_id: input?.beneficiaryUserId ?? null,
    p_limit: input?.limit ?? 50,
  });
  if (error) throw error;
  return (data ?? []).map((row: SettlementRpcRow) => mapSettlementRow(row));
}

export const STAKEHOLDER_ROLE_LABELS: Record<StakeholderRole, string> = {
  platform: "Plateforme",
  admin_pays: "Admin pays",
  master: "Master",
  seller: "Vendeur",
  company: "Compagnie",
  recruiter: "Recruteur compagnie",
  custom: "Stakeholder",
};

export type StakeholderRevenueSharingRow = {
  countryId: string;
  companyId: string;
  companyName: string;
  stakeholderRole: StakeholderRole;
  stakeholderLabel: string;
  beneficiaryUserId: string | null;
  beneficiaryName: string | null;
  rate: number;
  earnedAmount: number;
  ticketCount: number;
  currency: string;
};

type RevenueSharingRpcRow = {
  country_id: unknown;
  company_id: unknown;
  company_name: unknown;
  stakeholder_role: unknown;
  stakeholder_label: unknown;
  beneficiary_user_id: unknown;
  beneficiary_name: unknown;
  rate: unknown;
  earned_amount: unknown;
  ticket_count: unknown;
  currency: unknown;
};

export async function listStakeholderRevenueSharingSupabase(input: {
  countryId: string;
  companyId?: string | null;
}): Promise<StakeholderRevenueSharingRow[]> {
  const { data, error } = await supabase.rpc("list_stakeholder_revenue_sharing", {
    p_country_id: input.countryId,
    p_company_id: input.companyId ?? null,
  });
  if (error) throw error;
  return (data ?? []).map((row: RevenueSharingRpcRow) => ({
    countryId: String(row.country_id),
    companyId: String(row.company_id),
    companyName: String(row.company_name ?? ""),
    stakeholderRole: String(row.stakeholder_role) as StakeholderRole,
    stakeholderLabel: String(row.stakeholder_label ?? row.stakeholder_role),
    beneficiaryUserId: row.beneficiary_user_id ? String(row.beneficiary_user_id) : null,
    beneficiaryName: row.beneficiary_name ? String(row.beneficiary_name) : null,
    rate: Number(row.rate ?? 0),
    earnedAmount: Number(row.earned_amount ?? 0),
    ticketCount: Number(row.ticket_count ?? 0),
    currency: String(row.currency ?? "XOF"),
  }));
}

export type StakeholderCountryUser = {
  userId: string;
  fullName: string | null;
  email: string | null;
  roles: string[];
};

export type StakeholderCommissionDashboard = {
  countryId: string | null;
  balances: StakeholderCommissionBalance[];
  canApprove: boolean;
  canRequest: boolean;
};

function mapStakeholderCountryUserRow(row: Record<string, unknown>): StakeholderCountryUser {
  const userId = row.user_id ?? row.userId ?? row.id;
  const fullName = row.full_name ?? row.fullName;
  return {
    userId: String(userId),
    fullName: fullName ? String(fullName) : null,
    email: row.email ? String(row.email) : null,
    roles: (row.roles as string[] | null) ?? [],
  };
}

export async function listStakeholderCountryUsersSupabase(
  countryId: string,
): Promise<StakeholderCountryUser[]> {
  const { data, error } = await supabase.rpc("list_stakeholder_country_users", {
    p_country_id: countryId,
  });
  if (error) throw error;
  return (data ?? []).map((row: Record<string, unknown>) => mapStakeholderCountryUserRow(row));
}

export type StakeholderCountryCompany = {
  id: string;
  name: string;
  countryId: string;
  recruitedByUserId: string | null;
};

export async function listStakeholderCountryCompaniesSupabase(
  countryId: string,
): Promise<StakeholderCountryCompany[]> {
  const { data, error } = await supabase.rpc("list_stakeholder_country_companies", {
    p_country_id: countryId,
  });
  if (error) throw error;
  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.company_id ?? row.companyId ?? row.id),
    name: String(row.company_name ?? row.companyName ?? row.name ?? ""),
    countryId: String(row.country_id ?? row.countryId ?? countryId),
    recruitedByUserId: row.recruited_by_user_id
      ? String(row.recruited_by_user_id)
      : row.recruitedByUserId
        ? String(row.recruitedByUserId)
        : null,
  }));
}

export async function upsertStakeholderPayoutMinimumSupabase(input: {
  countryId: string;
  stakeholderRole: StakeholderRole;
  minimumAmount: number;
}): Promise<string> {
  const { data, error } = await supabase.rpc("upsert_stakeholder_payout_minimum", {
    p_country_id: input.countryId,
    p_stakeholder_role: input.stakeholderRole,
    p_minimum_amount: input.minimumAmount,
  });
  if (error) throw error;
  return String(data);
}

export async function getMyStakeholderCommissionDashboardSupabase(
  countryId?: string | null,
): Promise<StakeholderCommissionDashboard> {
  const { data, error } = await supabase.rpc("get_my_stakeholder_commission_dashboard", {
    p_country_id: countryId ?? null,
  });
  if (error) throw error;
  const payload = (data ?? {}) as Record<string, unknown>;
  const balancesRaw = (payload.balances ?? []) as BalanceRpcRow[];
  return {
    countryId: payload.countryId ? String(payload.countryId) : null,
    balances: balancesRaw.map(mapBalanceRow),
    canApprove: Boolean(payload.canApprove),
    canRequest: Boolean(payload.canRequest ?? true),
  };
}
