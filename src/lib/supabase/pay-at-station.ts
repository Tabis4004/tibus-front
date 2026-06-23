// src/lib/supabase/pay-at-station.ts
// Fonctions Supabase pour l'option "Payer en gare"
//
// X (marge plateforme) est résolu via CommissionSettings (admin Tibus).
// La compagnie active seulement le flag payAtStation.
// Le voyageur paie en ligne X + Y + Z + F uniquement.
// M (prix billet) est réglé en gare de départ.
// Le message du reçu est éditable par le superadmin via PlatformSettings.

import { supabase } from "@/lib/supabase";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import type { PaymentGateway, PaymentMethod, PaymentNetwork } from "@/config/commission.ts";

// ─────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────

export type PayAtStationConfig = {
  payAtStation: boolean;
};

export type StationBookingFee = {
  nominalAmount: number;      // M — prix billet, à payer en gare
  totalOnlineAmount: number;  // X + Y + Z + F — payé en ligne maintenant
  stationDueAmount: number;   // Alias de M, pour affichage ticket
  isStationBooking: true;
};

export type PayAtStationReceiptMsg = {
  title: string;
  line1: string;
  line2: string;
  updatedAt?: string | null;
};

export const DEFAULT_STATION_RECEIPT_MSG: PayAtStationReceiptMsg = {
  title: "REÇU DE RÉSERVATION",
  line1: "Ceci est un reçu de réservation à payer dans la gare du départ.",
  line2: "Montant dû à la compagnie :",
};

// ─────────────────────────────────────────────
// Normalisation
// ─────────────────────────────────────────────

function normalizeConfig(raw: unknown): PayAtStationConfig {
  const r = (raw ?? {}) as Record<string, unknown>;
  return { payAtStation: Boolean(r.payAtStation) };
}

function numberVal(v: unknown): number {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function normalizeStationFee(raw: unknown): StationBookingFee {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    nominalAmount:     numberVal(r.nominalAmount),
    totalOnlineAmount: numberVal(r.totalOnlineAmount),
    stationDueAmount:  numberVal(r.stationDueAmount),
    isStationBooking:  true,
  };
}

function normalizeReceiptMsg(raw: unknown): PayAtStationReceiptMsg {
  if (!raw || typeof raw !== "object") return DEFAULT_STATION_RECEIPT_MSG;
  const r = raw as Record<string, unknown>;
  return {
    title:     String(r.title     ?? DEFAULT_STATION_RECEIPT_MSG.title),
    line1:     String(r.line1     ?? DEFAULT_STATION_RECEIPT_MSG.line1),
    line2:     String(r.line2     ?? DEFAULT_STATION_RECEIPT_MSG.line2),
    updatedAt: r.updatedAt ? String(r.updatedAt) : null,
  };
}

// ─────────────────────────────────────────────
// Lecture config compagnie
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
// Calcul des frais en ligne (X+Y+Z+F sans M)
// ─────────────────────────────────────────────

export async function calculateStationBookingFeeSupabase(input: {
  nominalAmount: number;
  companyId: string;
  gateway?: PaymentGateway;
  method?: PaymentMethod;
  network?: PaymentNetwork | null;
  countryId?: string | null;
  tripMarginPercent?: number | null;
}): Promise<StationBookingFee> {
  const { data, error } = await supabase.rpc("calculate_station_booking_fee", {
    p_nominal_amount:      input.nominalAmount,
    p_company_id:          input.companyId,
    p_gateway:             input.gateway          ?? "geniuspay",
    p_method:              input.method           ?? "mobile_money",
    p_network:             input.network          ?? "unknown",
    p_country_id:          input.countryId        ?? null,
    p_trip_margin_percent: input.tripMarginPercent ?? null,
  });
  if (error) throw error;
  return normalizeStationFee(data);
}

// ─────────────────────────────────────────────
// Activation / désactivation (admin plateforme)
// ─────────────────────────────────────────────

export async function setPayAtStationConfigSupabase(
  companyId: string,
  enabled: boolean,
): Promise<void> {
  const { error } = await supabase
    .from("Companies")
    .update({ payAtStation: enabled })
    .eq("id", companyId);
  if (error) throw error;

  void recordPlatformAuditSupabase({
    moduleKey: "admin.companies",
    action:    "toggle",
    summary:   enabled
      ? `Option "Payer en gare" activée`
      : `Option "Payer en gare" désactivée`,
    metadata: { companyId, payAtStation: enabled },
  }).catch(() => undefined);
}

// ─────────────────────────────────────────────
// Message du reçu — éditable par le superadmin
// Stocké dans PlatformSettings key = "pay_at_station_receipt_msg"
// ─────────────────────────────────────────────

export async function getPayAtStationReceiptMsgSupabase(): Promise<PayAtStationReceiptMsg> {
  const { data, error } = await supabase
    .from("PlatformSettings")
    .select("value, updatedAt")
    .eq("key", "pay_at_station_receipt_msg")
    .maybeSingle();
  if (error) throw error;
  if (!data) return DEFAULT_STATION_RECEIPT_MSG;
  const parsed = typeof data.value === "string" ? JSON.parse(data.value) : data.value;
  return normalizeReceiptMsg({ ...parsed, updatedAt: data.updatedAt });
}

export async function upsertPayAtStationReceiptMsgSupabase(
  msg: PayAtStationReceiptMsg,
): Promise<void> {
  const { error } = await supabase
    .from("PlatformSettings")
    .upsert(
      { key: "pay_at_station_receipt_msg", value: JSON.stringify({ title: msg.title, line1: msg.line1, line2: msg.line2 }) },
      { onConflict: "key" },
    );
  if (error) throw error;

  void recordPlatformAuditSupabase({
    moduleKey: "admin.platform-settings",
    action:    "update",
    summary:   `Message reçu "Payer en gare" mis à jour`,
    metadata:  { msg },
  }).catch(() => undefined);
}
