import { supabase } from "@/lib/supabase";
import {
  COMMERCIAL_OFFER_ADMIN_URL,
  COMPANY_OWNER_CONTRACT_FULL_TEXT,
} from "@/lib/company-owner-contract-content.ts";

export type LegalPage = {
  slug: string;
  title: string;
  content: string;
  updatedAt?: string | null;
};

export const COMPANY_OWNER_CONTRACT_SLUG = "company-owner-contract";

export const DEFAULT_CGU_PAGE: LegalPage = {
  slug: "cgu",
  title: "Conditions Générales d'Utilisation",
  content: `Bienvenue sur Tibus.

En utilisant la plateforme Tibus, vous acceptez les présentes Conditions Générales d'Utilisation.

1. Objet
Tibus met en relation voyageurs, compagnies de transport et vendeurs pour la recherche, la réservation et la vente de titres de transport.

2. Compte utilisateur
Vous vous engagez à fournir des informations exactes et à préserver la confidentialité de vos identifiants.

3. Réservations et paiements
Les conditions de voyage, d'annulation et de remboursement sont définies par la compagnie de transport concernée.

4. Données personnelles
Vos données sont traitées conformément à la réglementation applicable.

5. Responsabilité
Tibus agit en tant qu'intermédiaire technique. La compagnie de transport reste responsable de l'exécution du service de transport.

6. Modification
Ces conditions peuvent être mises à jour par l'administrateur de la plateforme. La version publiée sur cette page fait foi.`,
};

export const PRIVACY_POLICY_SLUG = "politique-confidentialite";

export const DEFAULT_PRIVACY_POLICY_PAGE: LegalPage = {
  slug: PRIVACY_POLICY_SLUG,
  title: "Politique de Confidentialité",
  content: `Tibus met en relation voyageurs, compagnies de transport et vendeurs pour la recherche, la réservation et la vente de titres de transport.

Pour toute question relative à vos données personnelles : tabistibus@gmail.com — WhatsApp : +225 01 72 96 00 00`,
};

export const DEFAULT_COMPANY_OWNER_CONTRACT_PAGE: LegalPage = {
  slug: COMPANY_OWNER_CONTRACT_SLUG,
  title: "Contrat de souscription — Propriétaire de compagnie",
  content: COMPANY_OWNER_CONTRACT_FULL_TEXT,
};

function defaultLegalPage(slug: string): LegalPage {
  if (slug === "cgu") return DEFAULT_CGU_PAGE;
  if (slug === PRIVACY_POLICY_SLUG) return DEFAULT_PRIVACY_POLICY_PAGE;
  if (slug === COMPANY_OWNER_CONTRACT_SLUG) return DEFAULT_COMPANY_OWNER_CONTRACT_PAGE;
  return { slug, title: slug, content: "" };
}

function normalizeLegalPage(data: unknown, slug: string): LegalPage {
  if (!data || typeof data !== "object") {
    return defaultLegalPage(slug);
  }
  const row = data as Record<string, unknown>;
  return {
    slug: String(row.slug ?? slug),
    title: String(row.title ?? defaultLegalPage(slug).title),
    content: String(row.content ?? ""),
    updatedAt: row.updatedAt ? String(row.updatedAt) : null,
  };
}

export async function getLegalPageSupabase(slug: string): Promise<LegalPage> {
  const { data, error } = await supabase.rpc("get_legal_page", { p_slug: slug });
  if (error) throw error;
  if (!data) return defaultLegalPage(slug);
  return normalizeLegalPage(data, slug);
}

export async function upsertLegalPageSupabase(page: LegalPage): Promise<LegalPage> {
  const { data, error } = await supabase.rpc("upsert_legal_page", {
    p_slug: page.slug,
    p_title: page.title,
    p_content: page.content,
  });
  if (error) throw error;
  return normalizeLegalPage(data, page.slug);
}

export async function getCguPageSupabase(): Promise<LegalPage> {
  return getLegalPageSupabase("cgu");
}

export async function upsertCguPageSupabase(page: Omit<LegalPage, "slug">): Promise<LegalPage> {
  return upsertLegalPageSupabase({ slug: "cgu", ...page });
}

export async function getCompanyOwnerContractPageSupabase(): Promise<LegalPage> {
  return getLegalPageSupabase(COMPANY_OWNER_CONTRACT_SLUG);
}

export async function upsertCompanyOwnerContractPageSupabase(
  page: Omit<LegalPage, "slug">,
): Promise<LegalPage> {
  return upsertLegalPageSupabase({ slug: COMPANY_OWNER_CONTRACT_SLUG, ...page });
}

export const COMPANY_OWNER_CONTRACT_PATH = "contrat-proprietaire-compagnie";

export const PRIVACY_POLICY_PATH = "politique-confidentialite";

export async function getPrivacyPolicyPageSupabase(): Promise<LegalPage> {
  return getLegalPageSupabase(PRIVACY_POLICY_SLUG);
}

export async function upsertPrivacyPolicyPageSupabase(
  page: Omit<LegalPage, "slug">,
): Promise<LegalPage> {
  return upsertLegalPageSupabase({ slug: PRIVACY_POLICY_SLUG, ...page });
}

export { COMMERCIAL_OFFER_ADMIN_URL };
