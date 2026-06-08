import { supabase } from "@/lib/supabase";

export type LegalPage = {
  slug: string;
  title: string;
  content: string;
  updatedAt?: string | null;
};

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

function normalizeLegalPage(data: unknown, slug: string): LegalPage {
  if (!data || typeof data !== "object") {
    return slug === "cgu" ? DEFAULT_CGU_PAGE : { slug, title: slug, content: "" };
  }
  const row = data as Record<string, unknown>;
  return {
    slug: String(row.slug ?? slug),
    title: String(row.title ?? DEFAULT_CGU_PAGE.title),
    content: String(row.content ?? ""),
    updatedAt: row.updatedAt ? String(row.updatedAt) : null,
  };
}

export async function getLegalPageSupabase(slug: string): Promise<LegalPage> {
  const { data, error } = await supabase.rpc("get_legal_page", { p_slug: slug });
  if (error) throw error;
  if (!data) return slug === "cgu" ? DEFAULT_CGU_PAGE : { slug, title: slug, content: "" };
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
