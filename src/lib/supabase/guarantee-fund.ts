import { supabase } from "@/lib/supabase";
import { randomUUID } from "@/lib/random-id.ts";
import { sendGuaranteeDepositPushSupabase, type GuaranteePushEvent } from "@/lib/supabase/push.ts";

type GuaranteeDepositActionResult = {
  depositId?: string;
  pushEvent?: GuaranteePushEvent;
};

async function triggerGuaranteeDepositPush(data: unknown): Promise<void> {
  const row = (data ?? {}) as GuaranteeDepositActionResult;
  if (!row.depositId || !row.pushEvent) return;
  await sendGuaranteeDepositPushSupabase({
    depositId: row.depositId,
    event: row.pushEvent,
  });
}

export const GUARANTEE_RECEIPT_BUCKET = "guarantee-deposit-receipts";

export type GuaranteeLedgerType = "deposit" | "reservation" | "release";
export type GuaranteeDepositStatus = "pending" | "approved" | "rejected";

export type GuaranteeLedgerRow = {
  id: string;
  createdAt: string;
  type: GuaranteeLedgerType;
  amount: number;
  balanceAfter: number;
  reference: string | null;
  bookingId: string | null;
  note: string | null;
  authorName: string | null;
};

export type GuaranteeDepositRow = {
  id: string;
  createdAt: string;
  amount: number;
  reference: string | null;
  note: string | null;
  receiptPath: string;
  receiptFileName: string | null;
  status: GuaranteeDepositStatus;
  submittedByName: string | null;
  validatedByName: string | null;
  validatedAt: string | null;
  rejectionReason: string | null;
};

export type CompanyGuaranteeFund = {
  companyId: string;
  balance: number;
  currency: string;
  allowNegative: boolean;
  pendingDeposits: number;
  recent: GuaranteeLedgerRow[];
};

export type GuaranteeSufficiencyCheck = {
  required: boolean;
  sufficient: boolean;
  skipped?: boolean;
  allowNegative?: boolean;
  balance?: number;
  amount?: number;
  currency?: string;
};

function num(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function mapLedgerRow(row: Record<string, unknown>): GuaranteeLedgerRow {
  return {
    id: String(row.id),
    createdAt: String(row.created_at ?? row.createdAt ?? ""),
    type: String(row.type) as GuaranteeLedgerType,
    amount: num(row.amount),
    balanceAfter: num(row.balance_after ?? row.balanceAfter),
    reference: row.reference ? String(row.reference) : null,
    bookingId: row.booking_id || row.bookingId ? String(row.booking_id ?? row.bookingId) : null,
    note: row.note ? String(row.note) : null,
    authorName: row.author_name || row.authorName ? String(row.author_name ?? row.authorName) : null,
  };
}

function mapDepositRow(row: Record<string, unknown>): GuaranteeDepositRow {
  return {
    id: String(row.id),
    createdAt: String(row.created_at ?? row.createdAt ?? ""),
    amount: num(row.amount),
    reference: row.reference ? String(row.reference) : null,
    note: row.note ? String(row.note) : null,
    receiptPath: String(row.receipt_path ?? row.receiptPath ?? ""),
    receiptFileName: row.receipt_file_name || row.receiptFileName
      ? String(row.receipt_file_name ?? row.receiptFileName)
      : null,
    status: String(row.status) as GuaranteeDepositStatus,
    submittedByName: row.submitted_by_name || row.submittedByName
      ? String(row.submitted_by_name ?? row.submittedByName)
      : null,
    validatedByName: row.validated_by_name || row.validatedByName
      ? String(row.validated_by_name ?? row.validatedByName)
      : null,
    validatedAt: row.validated_at || row.validatedAt
      ? String(row.validated_at ?? row.validatedAt)
      : null,
    rejectionReason: row.rejection_reason || row.rejectionReason
      ? String(row.rejection_reason ?? row.rejectionReason)
      : null,
  };
}

export async function uploadGuaranteeDepositReceipt(
  companyId: string,
  file: File,
): Promise<{ path: string; fileName: string }> {
  const safeName = file.name.replace(/[^\w.\-]+/g, "_");
  const path = `${companyId}/${randomUUID()}-${safeName}`;
  const { error } = await supabase.storage
    .from(GUARANTEE_RECEIPT_BUCKET)
    .upload(path, file, { upsert: false, contentType: file.type || undefined });
  if (error) throw error;
  return { path, fileName: file.name };
}

export async function getGuaranteeDepositReceiptUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from(GUARANTEE_RECEIPT_BUCKET)
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

function mapFundPayload(
  payload: Record<string, unknown>,
  companyId: string,
): CompanyGuaranteeFund {
  const recent = Array.isArray(payload.recent)
    ? (payload.recent as Record<string, unknown>[]).map((row) => ({
        id: String(row.id),
        createdAt: String(row.createdAt ?? row.created_at ?? ""),
        type: String(row.type) as GuaranteeLedgerType,
        amount: num(row.amount),
        balanceAfter: num(row.balanceAfter ?? row.balance_after),
        reference: row.reference ? String(row.reference) : null,
        bookingId: row.bookingId || row.booking_id ? String(row.bookingId ?? row.booking_id) : null,
        note: row.note ? String(row.note) : null,
        authorName: row.authorName || row.author_name ? String(row.authorName ?? row.author_name) : null,
      }))
    : [];

  return {
    companyId: String(payload.companyId ?? payload.company_id ?? companyId),
    balance: num(payload.balance),
    currency: String(payload.currency ?? "XOF"),
    allowNegative: Boolean(payload.allowNegative ?? payload.allow_negative),
    pendingDeposits: num(payload.pendingDeposits ?? payload.pending_deposits),
    recent,
  };
}

function countryFromJoin(
  value:
    | { currency?: string | null }
    | { currency?: string | null }[]
    | null
    | undefined,
): string {
  if (!value) return "XOF";
  const row = Array.isArray(value) ? value[0] : value;
  return row?.currency ? String(row.currency) : "XOF";
}

async function fetchCompanyGuaranteeFundFallback(
  companyId: string,
): Promise<CompanyGuaranteeFund | null> {
  const { data, error } = await supabase
    .from("Companies")
    .select("id, guaranteeBalance, guaranteeAllowNegative, Countries(currency)")
    .eq("id", companyId)
    .maybeSingle();

  if (!error && data) {
    return {
      companyId: String(data.id),
      balance: num(data.guaranteeBalance),
      currency: countryFromJoin(
        data.Countries as { currency?: string | null } | { currency?: string | null }[] | null,
      ),
      allowNegative: Boolean(data.guaranteeAllowNegative),
      pendingDeposits: 0,
      recent: [],
    };
  }

  const { data: companyOnly, error: companyError } = await supabase
    .from("Companies")
    .select("id, Countries(currency)")
    .eq("id", companyId)
    .maybeSingle();

  if (companyError || !companyOnly) return null;

  return {
    companyId: String(companyOnly.id),
    balance: 0,
    currency: countryFromJoin(
      companyOnly.Countries as { currency?: string | null } | { currency?: string | null }[] | null,
    ),
    allowNegative: false,
    pendingDeposits: 0,
    recent: [],
  };
}

export async function getCompanyGuaranteeFundSupabase(
  companyId: string,
): Promise<CompanyGuaranteeFund> {
  const { data, error } = await supabase.rpc("get_company_guarantee_fund", {
    p_company_id: companyId,
  });

  if (!error && data) {
    return mapFundPayload((data ?? {}) as Record<string, unknown>, companyId);
  }

  const fallback = await fetchCompanyGuaranteeFundFallback(companyId);
  if (fallback) return fallback;

  if (error) throw error;
  throw new Error("Fond de garantie introuvable");
}

export async function listCompanyGuaranteeLedgerSupabase(
  companyId: string,
  limit = 100,
  offset = 0,
): Promise<GuaranteeLedgerRow[]> {
  const { data, error } = await supabase.rpc("list_company_guarantee_ledger", {
    p_company_id: companyId,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map(mapLedgerRow);
}

export async function listCompanyGuaranteeDepositsSupabase(
  companyId: string,
  status?: GuaranteeDepositStatus | null,
): Promise<GuaranteeDepositRow[]> {
  const { data, error } = await supabase.rpc("list_company_guarantee_deposits", {
    p_company_id: companyId,
    p_status: status ?? null,
  });
  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[]).map(mapDepositRow);
}

export async function submitCompanyGuaranteeDepositSupabase(input: {
  companyId: string;
  amount: number;
  receiptPath: string;
  receiptFileName?: string;
  reference?: string;
  note?: string;
}): Promise<void> {
  const { data, error } = await supabase.rpc("submit_company_guarantee_deposit", {
    p_company_id: input.companyId,
    p_amount: input.amount,
    p_receipt_path: input.receiptPath,
    p_reference: input.reference ?? null,
    p_note: input.note ?? null,
    p_receipt_file_name: input.receiptFileName ?? null,
  });
  if (error) throw error;
  await triggerGuaranteeDepositPush(data);
}

export async function approveCompanyGuaranteeDepositSupabase(depositId: string): Promise<void> {
  const { data, error } = await supabase.rpc("approve_company_guarantee_deposit", {
    p_deposit_id: depositId,
  });
  if (error) throw error;
  await triggerGuaranteeDepositPush(data);
}

export async function rejectCompanyGuaranteeDepositSupabase(
  depositId: string,
  reason?: string,
): Promise<void> {
  const { data, error } = await supabase.rpc("reject_company_guarantee_deposit", {
    p_deposit_id: depositId,
    p_reason: reason ?? null,
  });
  if (error) throw error;
  await triggerGuaranteeDepositPush(data);
}

export async function upsertCompanyGuaranteeSettingsSupabase(
  companyId: string,
  allowNegative: boolean,
): Promise<void> {
  const { error } = await supabase.rpc("upsert_company_guarantee_settings", {
    p_company_id: companyId,
    p_allow_negative: allowNegative,
  });
  if (error) throw error;
}

export async function checkCompanyGuaranteeSufficientSupabase(
  companyId: string,
  amount: number,
  saleChannel: string,
): Promise<GuaranteeSufficiencyCheck> {
  const { data, error } = await supabase.rpc("check_company_guarantee_sufficient", {
    p_company_id: companyId,
    p_amount: amount,
    p_sale_channel: saleChannel,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    required: Boolean(row.required),
    sufficient: Boolean(row.sufficient),
    skipped: row.skipped == null ? undefined : Boolean(row.skipped),
    allowNegative: row.allowNegative == null ? undefined : Boolean(row.allowNegative),
    balance: row.balance == null ? undefined : num(row.balance),
    amount: row.amount == null ? undefined : num(row.amount),
    currency: row.currency ? String(row.currency) : undefined,
  };
}

export const GUARANTEE_LEDGER_TYPE_LABELS: Record<GuaranteeLedgerType, string> = {
  deposit: "Dépôt",
  reservation: "Réservation",
  release: "Libération (annulation)",
};

export const GUARANTEE_DEPOSIT_STATUS_LABELS: Record<GuaranteeDepositStatus, string> = {
  pending: "En attente",
  approved: "Validé",
  rejected: "Rejeté",
};
