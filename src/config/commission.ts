/**
 * Moteur de calcul voyageur — formule pure, sans taux codés en dur.
 * Les taux X/Y/Z/F viennent de Supabase :
 * - X : CommissionSettings / resolve_seller_commission_setting (caisse existante)
 * - Y/Z/F : GatewayPaymentFees (lot 019)
 *
 * V = M × (1 + X%)
 * T = (M(1 + X) + F) / (1 - Z - Y)
 */

export type PaymentGateway = "fedapay" | "geniuspay" | "cinetpay" | "paystack" | "paiementpro";

export type PaymentMethod =
  | "mobile_money"
  | "card"
  | "bank_transfer"
  | "wallet";

/** Réseau mobile money — voir payment-networks.ts pour les libellés par pays */
export type PaymentNetwork =
  | "orange"
  | "mtn"
  | "moov"
  | "wave"
  | "free"
  | "mpesa"
  | "airtel"
  | "vodacom"
  | "mobicash"
  | "togocel"
  | "tigo"
  | "zamtel"
  | "unknown";

export type GatewayFeeRates = {
  yPercent: number;
  zPercent: number;
  fFixed: number;
};

export type ResolvedPlatformMargin = {
  ratePercent: number;
  paidBy: "company" | "traveler";
  scope: string;
};

export class MissingGatewayFeeConfigError extends Error {
  constructor(gateway: string, countryId: string, method: string) {
    super(
      `Configuration frais gateway manquante pour gateway="${gateway}", pays="${countryId}", méthode="${method}".`,
    );
    this.name = "MissingGatewayFeeConfigError";
  }
}

export class InvalidGatewayFeeRatesError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidGatewayFeeRatesError";
  }
}

export type PaymentBreakdown = {
  nominalAmount: number;
  platformMarginPercent: number;
  platformNetAmount: number;
  gatewayFeePercent: number;
  geniusPayFeePercent: number;
  fixedFee: number;
  rawTotalAmount: number;
  totalAmount: number;
  paidBy: "company" | "traveler";
  marginScope: string;
  network?: string;
  requestedNetwork?: string;
  usedMaxFallback?: boolean;
  gatewayAmount?: number;
  feeMode?: "on_top" | "deducted";
};

function assertFiniteAmount(value: number, label: string) {
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${label} doit être un nombre fini >= 0.`);
  }
}

function percentToRate(percent: number): number {
  return percent / 100;
}

/** Priorité : marge trajet > marge résolue Supabase > 0 */
export function resolvePlatformMarginPercent(
  resolved: ResolvedPlatformMargin | null | undefined,
  tripMarginPercent?: number | null,
): number {
  if (tripMarginPercent != null && Number.isFinite(tripMarginPercent)) {
    return tripMarginPercent;
  }
  return resolved?.ratePercent ?? 0;
}

/**
 * Calcule T à partir des taux déjà résolus (pas de lookup local).
 * Arrondi à l'entier supérieur pour l'encaissement voyageur.
 */
export function calculateTotalPayment(
  M: number,
  X: number,
  rates: GatewayFeeRates,
): number {
  return calculatePaymentBreakdown(M, X, rates).totalAmount;
}

export function calculatePaymentBreakdown(
  M: number,
  X: number,
  rates: GatewayFeeRates,
  options?: {
    paidBy?: "company" | "traveler";
    marginScope?: string;
  },
): PaymentBreakdown {
  assertFiniteAmount(M, "M");
  assertFiniteAmount(X, "X");

  const y = percentToRate(rates.yPercent);
  const z = percentToRate(rates.zPercent);
  const x = percentToRate(X);
  const f = rates.fFixed;

  assertFiniteAmount(f, "F");

  const denominator = 1 - z - y;
  if (denominator <= 0) {
    throw new InvalidGatewayFeeRatesError(
      `Taux invalides: Y (${rates.yPercent}%) + Z (${rates.zPercent}%) doivent être < 100%.`,
    );
  }

  const platformNetAmount = M * (1 + x);
  const rawTotalAmount = (platformNetAmount + f) / denominator;
  const totalAmount = Math.ceil(rawTotalAmount);

  return {
    nominalAmount: M,
    platformMarginPercent: X,
    platformNetAmount,
    gatewayFeePercent: rates.yPercent,
    geniusPayFeePercent: rates.zPercent,
    fixedFee: f,
    rawTotalAmount,
    totalAmount,
    paidBy: options?.paidBy ?? "company",
    marginScope: options?.marginScope ?? "unset",
  };
}
