import { supabase } from "@/lib/supabase";
import {
  formatTechnicalAnnexText,
  getDefaultTechnicalAnnex,
  normalizeTechnicalAnnexRpc,
  type CommercialOfferTechnicalAnnex,
} from "@/lib/commercial-offer-annex.ts";

export type CompanyOwnerContractStatus = {
  companyId: string;
  ownerContractAcceptedAt: string | null;
  liveAuthorizedByAdmin: boolean;
  liveAuthorizedAt: string | null;
  isActive: boolean;
  arretReservation: boolean;
  canEnableLive: boolean;
};

export async function getCommercialOfferTechnicalAnnexSupabase(
  countryId: string,
  locale: string,
): Promise<CommercialOfferTechnicalAnnex | null> {
  const { data, error } = await supabase.rpc("get_commercial_offer_technical_annex", {
    p_country_id: countryId,
    p_locale: locale,
  });
  if (error) throw error;
  return normalizeTechnicalAnnexRpc(data) ?? null;
}

export async function resolveTechnicalAnnexForCountry(
  countryId: string | null | undefined,
  locale: string,
): Promise<{ annex: CommercialOfferTechnicalAnnex; annexText: string }> {
  if (countryId) {
    try {
      const remote = await getCommercialOfferTechnicalAnnexSupabase(countryId, locale);
      if (remote) {
        return { annex: remote, annexText: formatTechnicalAnnexText(remote) };
      }
    } catch {
      // fallback to defaults
    }
  }
  const annex = getDefaultTechnicalAnnex(locale);
  return { annex, annexText: formatTechnicalAnnexText(annex) };
}

export async function getCompanyOwnerContractStatusSupabase(
  companyId: string,
): Promise<CompanyOwnerContractStatus> {
  const { data, error } = await supabase.rpc("get_company_owner_contract_status", {
    p_company_id: companyId,
  });
  if (error) throw error;
  const row = data as Record<string, unknown>;
  return {
    companyId,
    ownerContractAcceptedAt: row.ownerContractAcceptedAt
      ? String(row.ownerContractAcceptedAt)
      : null,
    liveAuthorizedByAdmin: Boolean(row.liveAuthorizedByAdmin),
    liveAuthorizedAt: row.liveAuthorizedAt ? String(row.liveAuthorizedAt) : null,
    isActive: Boolean(row.isActive),
    arretReservation: Boolean(row.arretReservation),
    canEnableLive: Boolean(row.canEnableLive),
  };
}

export async function acceptCompanyOwnerContractSupabase(companyId: string): Promise<void> {
  const { error } = await supabase.rpc("accept_company_owner_contract", {
    p_company_id: companyId,
  });
  if (error) throw error;
}

export async function setCompanyArretReservationSupabase(
  companyId: string,
  enabled: boolean,
): Promise<void> {
  const { error } = await supabase.rpc("set_company_arret_reservation", {
    p_company_id: companyId,
    p_enabled: enabled,
  });
  if (error) throw error;
}

export async function setCompanyLiveAuthorizationSupabase(
  companyId: string,
  authorized: boolean,
): Promise<void> {
  const { error } = await supabase.rpc("set_company_live_authorization", {
    p_company_id: companyId,
    p_authorized: authorized,
  });
  if (error) throw error;
}

export async function setCompanyActiveAdminSupabase(
  companyId: string,
  isActive: boolean,
): Promise<void> {
  const { error } = await supabase.rpc("set_company_active_admin", {
    p_company_id: companyId,
    p_is_active: isActive,
  });
  if (error) throw error;
}
