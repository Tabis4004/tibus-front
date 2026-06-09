import { supabase } from "@/lib/supabase";

export type TravelerPaymentNoticeHint = {
  id?: string;
  countryId: string;
  countryCode: string;
  countryName?: string;
  cheapestNetwork: string;
  sortOrder: number;
  isActive: boolean;
};

export type TravelerPaymentNotice = {
  title: string;
  infoLine: string;
  paragraph1: string;
  paragraph2: string;
  networkIntro: string;
  updatedAt?: string | null;
  hints: TravelerPaymentNoticeHint[];
};

export const DEFAULT_TRAVELER_PAYMENT_NOTICE: TravelerPaymentNotice = {
  title: "Confirmer avant paiement",
  infoLine:
    "Redirection vers le paiement sécurisé. Aucune place n'est réservée et aucun billet n'est émis tant que le paiement n'est pas confirmé.",
  paragraph1:
    "Des places sont encore disponibles, mais votre siège n'est pas garanti tant que le paiement n'est pas confirmé.",
  paragraph2:
    "Vous pouvez payer maintenant ou revenir plus tard (vos informations seront conservées sur cet appareil uniquement).",
  networkIntro:
    "Le montant total dépendra des frais du réseau que vous choisirez. Voici les moins chers par pays :",
  hints: [
    { countryId: "", countryCode: "CI", cheapestNetwork: "wave", sortOrder: 1, isActive: true },
    { countryId: "", countryCode: "BN", cheapestNetwork: "mtn", sortOrder: 2, isActive: true },
    { countryId: "", countryCode: "BF", cheapestNetwork: "orange", sortOrder: 3, isActive: true },
  ],
};

type NoticeJson = {
  title?: unknown;
  infoLine?: unknown;
  paragraph1?: unknown;
  paragraph2?: unknown;
  networkIntro?: unknown;
  updatedAt?: unknown;
  hints?: unknown;
};

function normalizeHint(value: unknown): TravelerPaymentNoticeHint | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  const countryId = String(row.countryId ?? "");
  const countryCode = String(row.countryCode ?? "").trim();
  const cheapestNetwork = String(row.cheapestNetwork ?? "").trim();
  if (!countryCode || !cheapestNetwork) return null;
  return {
    id: row.id ? String(row.id) : undefined,
    countryId,
    countryCode,
    countryName: row.countryName ? String(row.countryName) : undefined,
    cheapestNetwork,
    sortOrder: Number(row.sortOrder ?? 0) || 0,
    isActive: row.isActive == null ? true : Boolean(row.isActive),
  };
}

function normalizeNotice(payload: NoticeJson | null): TravelerPaymentNotice {
  if (!payload) return DEFAULT_TRAVELER_PAYMENT_NOTICE;
  const hints = Array.isArray(payload.hints)
    ? payload.hints
        .map(normalizeHint)
        .filter((hint): hint is TravelerPaymentNoticeHint => Boolean(hint))
        .sort((a, b) => a.sortOrder - b.sortOrder || a.countryCode.localeCompare(b.countryCode))
    : [];

  return {
    title: String(payload.title ?? DEFAULT_TRAVELER_PAYMENT_NOTICE.title),
    infoLine: String(payload.infoLine ?? DEFAULT_TRAVELER_PAYMENT_NOTICE.infoLine),
    paragraph1: String(payload.paragraph1 ?? DEFAULT_TRAVELER_PAYMENT_NOTICE.paragraph1),
    paragraph2: String(payload.paragraph2 ?? DEFAULT_TRAVELER_PAYMENT_NOTICE.paragraph2),
    networkIntro: String(payload.networkIntro ?? DEFAULT_TRAVELER_PAYMENT_NOTICE.networkIntro),
    updatedAt: payload.updatedAt ? String(payload.updatedAt) : null,
    hints,
  };
}

export async function getTravelerPaymentNoticeSupabase(): Promise<TravelerPaymentNotice> {
  const { data, error } = await supabase.rpc("get_traveler_payment_notice");
  if (error) throw error;
  return normalizeNotice((data ?? null) as NoticeJson | null);
}

export async function upsertTravelerPaymentNoticeSupabase(
  notice: TravelerPaymentNotice,
): Promise<TravelerPaymentNotice> {
  const { data, error } = await supabase.rpc("upsert_traveler_payment_notice", {
    p_title: notice.title,
    p_info_line: notice.infoLine,
    p_paragraph1: notice.paragraph1,
    p_paragraph2: notice.paragraph2,
    p_network_intro: notice.networkIntro,
    p_hints: notice.hints
      .filter((hint) => hint.countryId && hint.countryCode && hint.cheapestNetwork)
      .map((hint) => ({
        countryId: hint.countryId,
        countryCode: hint.countryCode,
        cheapestNetwork: hint.cheapestNetwork,
        sortOrder: hint.sortOrder,
        isActive: hint.isActive,
      })),
  });
  if (error) throw error;
  return normalizeNotice((data ?? null) as NoticeJson | null);
}
