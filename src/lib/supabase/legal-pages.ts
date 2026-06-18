import { supabase } from "@/lib/supabase";

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

export const DEFAULT_COMPANY_OWNER_CONTRACT_PAGE: LegalPage = {
  slug: COMPANY_OWNER_CONTRACT_SLUG,
  title: "Contrat propriétaire de compagnie",
  content: `CONTRAT DE SOUSCRIPTION — PROPRIÉTAIRE DE COMPAGNIE

TIBUS TECHNOLOGY

Le Prestataire développe et exploite un Logiciel mis en ligne.

Ce logiciel est destiné à être utilisé par des utilisateurs itinérants ou sédentaires et est dénommé ci-après « le Logiciel ».

La plateforme Tibus est accessible à distance selon le mode SaaS, et rend dans ce cadre des prestations de service, notamment d'hébergement et de gestion des données des clients des utilisateurs de ce logiciel.

1. Objet
Le présent contrat régit les conditions dans lesquelles l'Utilisateur, en sa qualité de propriétaire d'une compagnie de transport, accède au Logiciel et crée une entreprise sur la plateforme Tibus.

2. Engagements du propriétaire
L'Utilisateur s'engage à fournir des informations exactes concernant sa compagnie, à respecter la réglementation applicable au transport de voyageurs et à préserver la confidentialité de ses identifiants d'accès.

3. Prestations SaaS
Le Prestataire assure l'hébergement, la maintenance et la disponibilité du Logiciel dans les limites des présentes conditions et du plan d'abonnement souscrit.

4. Données
Les données relatives à la compagnie, aux voyageurs et aux ventes sont traitées conformément à la politique de confidentialité de Tibus.

5. Rémunération
L'utilisation du Logiciel peut être soumise à un abonnement et à des commissions sur les ventes, selon les barèmes en vigueur au moment de la souscription.

6. Responsabilité
Le Prestataire agit en tant que fournisseur de solution technique. Le propriétaire de compagnie demeure responsable de l'exécution du service de transport et des obligations légales liées à son activité.

7. Résiliation
En cas de manquement grave aux présentes conditions ou de non-paiement, le Prestataire pourra suspendre l'accès au Logiciel après notification.

8. Modification
Le contenu de ce contrat peut être mis à jour par l'administrateur de la plateforme. La version publiée sur Tibus fait foi. La création ou le maintien d'une compagnie vaut acceptation de la version en vigueur.`,
};

function defaultLegalPage(slug: string): LegalPage {
  if (slug === "cgu") return DEFAULT_CGU_PAGE;
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
