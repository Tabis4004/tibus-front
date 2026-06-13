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

export type PaymentNetworkOption = {
  value: PaymentNetwork;
  labelFr: string;
  labelEn: string;
};

const NETWORK_LABELS: Record<Exclude<PaymentNetwork, "unknown">, PaymentNetworkOption> = {
  orange: { value: "orange", labelFr: "Orange Money", labelEn: "Orange Money" },
  mtn: { value: "mtn", labelFr: "MTN Mobile Money", labelEn: "MTN Mobile Money" },
  moov: { value: "moov", labelFr: "Moov Money", labelEn: "Moov Money" },
  wave: { value: "wave", labelFr: "Wave", labelEn: "Wave" },
  free: { value: "free", labelFr: "Free Money", labelEn: "Free Money" },
  mpesa: { value: "mpesa", labelFr: "M-Pesa", labelEn: "M-Pesa" },
  airtel: { value: "airtel", labelFr: "Airtel Money", labelEn: "Airtel Money" },
  vodacom: { value: "vodacom", labelFr: "Vodacom M-Pesa", labelEn: "Vodacom M-Pesa" },
  mobicash: { value: "mobicash", labelFr: "Mobicash", labelEn: "Mobicash" },
  togocel: { value: "togocel", labelFr: "Togocel / Moov TG", labelEn: "Togocel / Moov TG" },
  tigo: { value: "tigo", labelFr: "Tigo Pesa", labelEn: "Tigo Pesa" },
  zamtel: { value: "zamtel", labelFr: "Zamtel Kwacha", labelEn: "Zamtel Kwacha" },
};

/** Fallback CI — historique FedaPay. */
export const PAYMENT_NETWORK_OPTIONS: PaymentNetworkOption[] = [
  NETWORK_LABELS.orange,
  NETWORK_LABELS.mtn,
  NETWORK_LABELS.moov,
  NETWORK_LABELS.wave,
  {
    value: "unknown",
    labelFr: "Je ne sais pas (taux le plus élevé)",
    labelEn: "I don't know (highest rate)",
  },
];

/** Réseaux mobile money par pays (aligné seed GeniusPay lot 057). */
const COUNTRY_PAYMENT_NETWORKS: Record<string, PaymentNetwork[]> = {
  "Côte d'Ivoire": ["wave", "orange", "mtn", "moov"],
  "Burkina Faso": ["orange", "wave", "moov", "mobicash"],
  "Sénégal": ["wave", "orange", "free"],
  "Bénin": ["mtn", "moov"],
  "Mali": ["orange", "mobicash"],
  "Togo": ["moov", "togocel"],
  "Cameroun": ["mtn", "orange"],
  "Gabon": ["airtel"],
  "Ghana": ["mtn"],
  "Guinée": ["orange"],
  "Guinée-Bissau": ["orange"],
  "Niger": ["airtel"],
  "Nigeria": [],
  "Kenya": ["mpesa"],
  "Tanzanie": ["mpesa", "airtel", "tigo"],
  "Ouganda": ["mtn", "airtel"],
  "Rwanda": ["mtn", "airtel"],
  "RD Congo": ["orange", "airtel", "vodacom"],
  "République du Congo": ["mtn", "orange", "airtel", "mpesa"],
  "Sierra Leone": ["orange"],
  "Mozambique": ["mpesa", "vodacom"],
  "Malawi": ["airtel"],
  "Zambie": ["mtn", "zamtel"],
};

const UNKNOWN_OPTION: PaymentNetworkOption = {
  value: "unknown",
  labelFr: "Je ne sais pas (taux le plus élevé)",
  labelEn: "I don't know (highest rate)",
};

function normalizeCountryName(name: string): string {
  return name.trim();
}

function networkOption(value: PaymentNetwork): PaymentNetworkOption {
  if (value === "unknown") return UNKNOWN_OPTION;
  return (
    NETWORK_LABELS[value] ?? {
      value,
      labelFr: value.charAt(0).toUpperCase() + value.slice(1),
      labelEn: value.charAt(0).toUpperCase() + value.slice(1),
    }
  );
}

export function getPaymentNetworksForCountryName(
  countryName: string | null | undefined,
): PaymentNetwork[] {
  const key = normalizeCountryName(countryName ?? "");
  if (!key) return [];
  return COUNTRY_PAYMENT_NETWORKS[key] ?? [];
}

export function getPaymentNetworkOptionsForCountry(
  countryName: string | null | undefined,
  networks?: readonly string[] | null,
): PaymentNetworkOption[] {
  const countryOrder = getPaymentNetworksForCountryName(countryName);
  const resolved = (networks?.length ? networks : countryOrder)
    .map((network) => network.trim().toLowerCase())
    .filter((network) => network && network !== "default") as PaymentNetwork[];

  const unique = Array.from(new Set(resolved));
  if (unique.length === 0) {
    return [];
  }

  const sorted = countryOrder.length
    ? unique.sort((a, b) => {
        const indexA = countryOrder.indexOf(a);
        const indexB = countryOrder.indexOf(b);
        if (indexA === -1 && indexB === -1) return a.localeCompare(b);
        if (indexA === -1) return 1;
        if (indexB === -1) return -1;
        return indexA - indexB;
      })
    : unique.sort((a, b) => a.localeCompare(b));

  return [...sorted.map(networkOption), UNKNOWN_OPTION];
}

export function isPaymentNetwork(value: string): value is PaymentNetwork {
  return (
    value === "unknown" ||
    value in NETWORK_LABELS ||
    getPaymentNetworksForCountryName("").includes(value as PaymentNetwork)
  );
}

const PHONE_COUNTRY_PREFIXES: Array<{ prefix: string; country: string }> = [
  { prefix: "225", country: "Côte d'Ivoire" },
  { prefix: "226", country: "Burkina Faso" },
  { prefix: "221", country: "Sénégal" },
  { prefix: "229", country: "Bénin" },
  { prefix: "223", country: "Mali" },
  { prefix: "228", country: "Togo" },
  { prefix: "237", country: "Cameroun" },
  { prefix: "241", country: "Gabon" },
  { prefix: "233", country: "Ghana" },
  { prefix: "224", country: "Guinée" },
  { prefix: "245", country: "Guinée-Bissau" },
  { prefix: "254", country: "Kenya" },
  { prefix: "265", country: "Malawi" },
  { prefix: "227", country: "Niger" },
  { prefix: "234", country: "Nigeria" },
  { prefix: "256", country: "Ouganda" },
  { prefix: "243", country: "RD Congo" },
  { prefix: "242", country: "République du Congo" },
  { prefix: "250", country: "Rwanda" },
  { prefix: "232", country: "Sierra Leone" },
  { prefix: "255", country: "Tanzanie" },
  { prefix: "260", country: "Zambie" },
  { prefix: "258", country: "Mozambique" },
];

/** Pays Tibus déduit du préfixe international (ex. +225 → Côte d'Ivoire). */
export function inferCountryNameFromPhone(phone: string): string | null {
  const digits = phone.replace(/\D/g, "");
  if (!digits) return null;

  const sorted = [...PHONE_COUNTRY_PREFIXES].sort(
    (a, b) => b.prefix.length - a.prefix.length,
  );
  for (const entry of sorted) {
    if (digits.startsWith(entry.prefix)) {
      return entry.country;
    }
  }
  return null;
}

/** Indication CI à partir du préfixe — non fiable à 100 %, sert de pré-sélection UX. */
export function inferCiNetworkFromPhone(phone: string): PaymentNetwork | null {
  return inferNetworkFromPhone(phone, "Côte d'Ivoire");
}

export function inferNetworkFromPhone(
  phone: string,
  countryName?: string | null,
): PaymentNetwork | null {
  const country = normalizeCountryName(countryName ?? "Côte d'Ivoire");
  const digits = phone.replace(/\D/g, "");

  if (country === "Côte d'Ivoire" || !countryName) {
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
    if (
      [
        "07", "08", "09", "47", "48", "49", "57", "58", "59", "67", "68", "69",
        "77", "78", "79", "87", "88", "89",
      ].includes(prefix)
    ) {
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

  if (country === "Burkina Faso") {
    let local = digits;
    if (local.startsWith("226")) local = local.slice(3);
    if (local.length === 8) local = `0${local}`;
    if (!/^0[567]\d{7}$/.test(local)) return null;
    const prefix = local.slice(0, 2);
    if (["07", "57", "67", "77"].includes(prefix)) return "orange";
    if (["06", "56", "66", "76"].includes(prefix)) return "moov";
    if (["05", "55", "65", "75"].includes(prefix)) return "mobicash";
    return null;
  }

  if (country === "Sénégal") {
    let local = digits;
    if (local.startsWith("221")) local = local.slice(3);
    if (local.length === 9) local = `0${local}`;
    if (!/^0[7]\d{8}$/.test(local)) return null;
    const prefix = local.slice(1, 3);
    if (["77", "78"].includes(prefix)) return "orange";
    if (["76"].includes(prefix)) return "free";
    return null;
  }

  return null;
}

export function paymentNetworkLabel(
  network: PaymentNetwork | string,
  locale: string,
): string {
  const normalized = String(network).toLowerCase();
  if (normalized === "unknown") {
    return locale.startsWith("fr") ? UNKNOWN_OPTION.labelFr : UNKNOWN_OPTION.labelEn;
  }
  const option =
    NETWORK_LABELS[normalized as Exclude<PaymentNetwork, "unknown">] ??
    PAYMENT_NETWORK_OPTIONS.find((item) => item.value === normalized);
  if (!option) {
    return normalized.charAt(0).toUpperCase() + normalized.slice(1);
  }
  return locale.startsWith("fr") ? option.labelFr : option.labelEn;
}
