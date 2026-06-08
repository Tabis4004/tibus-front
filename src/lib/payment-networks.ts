export type PaymentNetwork =
  | "orange"
  | "mtn"
  | "moov"
  | "wave"
  | "unknown";

export type PaymentNetworkOption = {
  value: PaymentNetwork;
  labelFr: string;
  labelEn: string;
};

export const PAYMENT_NETWORK_OPTIONS: PaymentNetworkOption[] = [
  { value: "orange", labelFr: "Orange Money", labelEn: "Orange Money" },
  { value: "mtn", labelFr: "MTN Mobile Money", labelEn: "MTN Mobile Money" },
  { value: "moov", labelFr: "Moov Money", labelEn: "Moov Money" },
  { value: "wave", labelFr: "Wave", labelEn: "Wave" },
  {
    value: "unknown",
    labelFr: "Je ne sais pas (taux le plus élevé)",
    labelEn: "I don't know (highest rate)",
  },
];

/** Indication CI à partir du préfixe — non fiable à 100 %, sert de pré-sélection UX. */
export function inferCiNetworkFromPhone(phone: string): PaymentNetwork | null {
  const digits = phone.replace(/\D/g, "");
  let local = digits;
  if (local.startsWith("225") && local.length >= 12) {
    local = local.slice(3);
  }
  if (local.length === 9 && /^[1-9]/.test(local)) {
    local = `0${local}`;
  }
  if (!/^0[1-9]\d{8}$/.test(local)) {
    return null;
  }

  const prefix = local.slice(0, 2);
  if (["07", "08", "09", "47", "48", "49", "57", "58", "59", "67", "68", "69", "77", "78", "79", "87", "88", "89"].includes(prefix)) {
    return "orange";
  }
  if (["05", "45", "54", "55", "64", "65", "75", "85"].includes(prefix)) {
    return "mtn";
  }
  if (["01", "41", "51"].includes(prefix)) {
    return "moov";
  }
  return null;
}

export function paymentNetworkLabel(
  network: PaymentNetwork,
  locale: string,
): string {
  const option = PAYMENT_NETWORK_OPTIONS.find((item) => item.value === network);
  if (!option) return network;
  return locale.startsWith("fr") ? option.labelFr : option.labelEn;
}
