// src/lib/supabase/pay-at-station.ts
// Fonctions Supabase pour l'option "Payer en gare"

import { supabase } from "@/lib/supabase";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import type { PaymentGateway, PaymentMethod, PaymentNetwork } from "@/config/commission.ts";

// ─────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────

export type PayAtStationFeeType = "percent" | "fixed";

export type PayAtStationConfig = {
  payAtStation: boolean;
  payAtStationFeeType: PayAtStationFeeType;
  payAtStationFeeValue: number;
};

export type StationBookingFee = {
  nominalAmount: number;       // M — prix billet, à payer en gare
  platformFeeType: PayAtStationFeeType;
  platformFeeValue: number;    // X brut (% ou fixe)
  platformFeeAmount: number;   // X calculé en XOF/devise
  totalOnlineAmount: number;   // Ce que le voyageur paie en ligne
  stationDueAmount: number;    // M à régler en gare
  isStationBooking: true;
};

// ─────────────────────────────────────────────
// Normalisation
// ─────────────────────────────────────────────

function normalizeConfig(raw: unknown): PayAtStationConfig {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    payAtStation: Boolean(r.payAtStation),
    payAtStationFeeType:
      r.payAtStationFeeType === "fixed" ? "fixed" : "percent",
    payAtStationFeeValue: Number(r.payAtStationFeeValue ?? 0),
  };
}

function numberVal(v: unknown): number {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function normalizeStationFee(raw: unknown): StationBookingFee {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    nominalAmount:     numberVal(r.nominalAmount),
    platformFeeType:   r.platformFeeType === "fixed" ? "fixed" : "percent",
    platformFeeValue:  numberVal(r.platformFeeValue),
    platformFeeAmount: numberVal(r.platformFeeAmount),
    totalOnlineAmount: numberVal(r.totalOnlineAmount),
    stationDueAmount:  numberVal(r.stationDueAmount),
    isStationBooking:  true,
  };
}

// ─────────────────────────────────────────────
// Lecture config (voyageur + admin)
// ─────────────────────────────────────────────

export async function getPayAtStationConfigSupabase(
  companyId: string,
): Promise<PayAtStationConfig> {
  const { data, error } = await supabase.rpc("get_company_pay_at_station", {
    p_company_id: companyId,
  });
  if (error) throw error;
  return normalizeConfig(data);
}

// ─────────────────────────────────────────────
// Calcul des frais en ligne (sans M)
// ─────────────────────────────────────────────

export async function calculateStationBookingFeeSupabase(input: {
  nominalAmount: number;
  companyId: string;
  gateway?: PaymentGateway;
  method?: PaymentMethod;
  network?: PaymentNetwork | null;
  countryId?: string | null;
}): Promise<StationBookingFee> {
  const { data, error } = await supabase.rpc("calculate_station_booking_fee", {
    p_nominal_amount: input.nominalAmount,
    p_company_id:     input.companyId,
    p_gateway:        input.gateway  ?? "geniuspay",
    p_method:         input.method   ?? "mobile_money",
    p_network:        input.network  ?? "unknown",
    p_country_id:     input.countryId ?? null,
  });
  if (error) throw error;
  return normalizeStationFee(data);
}

// ─────────────────────────────────────────────
// Mise à jour par l'admin (direct update Companies)
// ─────────────────────────────────────────────

export async function setPayAtStationConfigSupabase(
  companyId: string,
  config: PayAtStationConfig,
): Promise<void> {
  const { error } = await supabase
    .from("Companies")
    .update({
      payAtStation:        config.payAtStation,
      payAtStationFeeType: config.payAtStationFeeType,
      payAtStationFeeValue: config.payAtStationFeeValue,
    })
    .eq("id", companyId);
  if (error) throw error;

  void recordPlatformAuditSupabase({
    moduleKey: "admin.companies",
    action:    "toggle",
    summary:   config.payAtStation
      ? `Option "Payer en gare" activée (${config.payAtStationFeeType === "percent" ? config.payAtStationFeeValue + "%" : config.payAtStationFeeValue + " XOF fixe"})`
      : `Option "Payer en gare" désactivée`,
    metadata: { companyId, config },
  }).catch(() => undefined);
}
