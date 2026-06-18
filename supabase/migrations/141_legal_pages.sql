-- Pages juridiques éditables (CGU, contrat propriétaire compagnie).

CREATE TABLE IF NOT EXISTS public."LegalPages" (
  slug text PRIMARY KEY,
  title text NOT NULL,
  content text NOT NULL DEFAULT '',
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES public."Users"(id)
);

ALTER TABLE public."LegalPages" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS legal_pages_public_read ON public."LegalPages";
CREATE POLICY legal_pages_public_read ON public."LegalPages"
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS legal_pages_super_admin_write ON public."LegalPages";
CREATE POLICY legal_pages_super_admin_write ON public."LegalPages"
  FOR ALL
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE OR REPLACE FUNCTION public.get_legal_page(p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."LegalPages"%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public."LegalPages" WHERE slug = p_slug;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object(
    'slug', v_row.slug,
    'title', v_row.title,
    'content', v_row.content,
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_legal_page(
  p_slug text,
  p_title text,
  p_content text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."LegalPages"%ROWTYPE;
  v_user uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Accès réservé au super administrateur';
  END IF;

  SELECT id INTO v_user FROM public."Users" WHERE "authUserId" = auth.uid() LIMIT 1;

  INSERT INTO public."LegalPages" (slug, title, content, "updatedAt", "updatedBy")
  VALUES (p_slug, trim(p_title), coalesce(p_content, ''), now(), v_user)
  ON CONFLICT (slug) DO UPDATE
  SET
    title = EXCLUDED.title,
    content = EXCLUDED.content,
    "updatedAt" = now(),
    "updatedBy" = v_user
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'slug', v_row.slug,
    'title', v_row.title,
    'content', v_row.content,
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_legal_page(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_legal_page(text, text, text) TO authenticated;

INSERT INTO public."LegalPages" (slug, title, content)
VALUES (
  'cgu',
  'Conditions Générales d''Utilisation',
  'Bienvenue sur Tibus.

En utilisant la plateforme Tibus, vous acceptez les présentes Conditions Générales d''Utilisation.

1. Objet
Tibus met en relation voyageurs, compagnies de transport et vendeurs pour la recherche, la réservation et la vente de titres de transport.

2. Compte utilisateur
Vous vous engagez à fournir des informations exactes et à préserver la confidentialité de vos identifiants.

3. Réservations et paiements
Les conditions de voyage, d''annulation et de remboursement sont définies par la compagnie de transport concernée.

4. Données personnelles
Vos données sont traitées conformément à la réglementation applicable.

5. Responsabilité
Tibus agit en tant qu''intermédiaire technique. La compagnie de transport reste responsable de l''exécution du service de transport.

6. Modification
Ces conditions peuvent être mises à jour par l''administrateur de la plateforme. La version publiée sur cette page fait foi.'
)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public."LegalPages" (slug, title, content)
VALUES (
  'company-owner-contract',
  'Contrat propriétaire de compagnie',
  'CONTRAT DE SOUSCRIPTION — PROPRIÉTAIRE DE COMPAGNIE

TIBUS TECHNOLOGY

Le Prestataire développe et exploite un Logiciel mis en ligne.

Ce logiciel est destiné à être utilisé par des utilisateurs itinérants ou sédentaires et est dénommé ci-après « le Logiciel ».

La plateforme Tibus est accessible à distance selon le mode SaaS, et rend dans ce cadre des prestations de service, notamment d''hébergement et de gestion des données des clients des utilisateurs de ce logiciel.

1. Objet
Le présent contrat régit les conditions dans lesquelles l''Utilisateur, en sa qualité de propriétaire d''une compagnie de transport, accède au Logiciel et crée une entreprise sur la plateforme Tibus.

2. Engagements du propriétaire
L''Utilisateur s''engage à fournir des informations exactes concernant sa compagnie, à respecter la réglementation applicable au transport de voyageurs et à préserver la confidentialité de ses identifiants d''accès.

3. Prestations SaaS
Le Prestataire assure l''hébergement, la maintenance et la disponibilité du Logiciel dans les limites des présentes conditions et du plan d''abonnement souscrit.

4. Données
Les données relatives à la compagnie, aux voyageurs et aux ventes sont traitées conformément à la politique de confidentialité de Tibus.

5. Rémunération
L''utilisation du Logiciel peut être soumise à un abonnement et à des commissions sur les ventes, selon les barèmes en vigueur au moment de la souscription.

6. Responsabilité
Le Prestataire agit en tant que fournisseur de solution technique. Le propriétaire de compagnie demeure responsable de l''exécution du service de transport et des obligations légales liées à son activité.

7. Résiliation
En cas de manquement grave aux présentes conditions ou de non-paiement, le Prestataire pourra suspendre l''accès au Logiciel après notification.

8. Modification
Le contenu de ce contrat peut être mis à jour par l''administrateur de la plateforme. La version publiée sur Tibus fait foi. La création ou le maintien d''une compagnie vaut acceptation de la version en vigueur.'
)
ON CONFLICT (slug) DO NOTHING;
