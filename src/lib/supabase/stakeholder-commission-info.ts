import { supabase } from "@/lib/supabase";

export type StakeholderCommissionInfo = {
  infoLine: string;
  updatedAt: string | null;
  updatedByName: string | null;
};

export const DEFAULT_STAKEHOLDER_COMMISSION_INFO_LINE =
  "La répartition s'effectue sur la commission plateforme (M×X%) de chaque ligne ReservationBus, selon CommissionSettings pays/compagnie. La compagnie (owner) et tout utilisateur lié à une compagnie sont exclus.";

function mapInfo(payload: Record<string, unknown>): StakeholderCommissionInfo {
  return {
    infoLine: String(payload.infoLine ?? DEFAULT_STAKEHOLDER_COMMISSION_INFO_LINE),
    updatedAt: payload.updatedAt ? String(payload.updatedAt) : null,
    updatedByName: payload.updatedByName ? String(payload.updatedByName) : null,
  };
}

export async function getStakeholderCommissionInfoSupabase(): Promise<StakeholderCommissionInfo> {
  const { data, error } = await supabase.rpc("get_stakeholder_commission_info");
  if (error) throw error;
  return mapInfo((data ?? {}) as Record<string, unknown>);
}

export async function upsertStakeholderCommissionInfoSupabase(
  infoLine: string,
): Promise<StakeholderCommissionInfo> {
  const { data, error } = await supabase.rpc("upsert_stakeholder_commission_info", {
    p_info_line: infoLine,
  });
  if (error) throw error;
  return mapInfo((data ?? {}) as Record<string, unknown>);
}
