-- Lot 53: CGU / pages légales éditables par super_admin

CREATE TABLE IF NOT EXISTS "LegalPages" (
  "slug" text PRIMARY KEY,
  "title" text NOT NULL,
  "content" text NOT NULL DEFAULT '',
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users" ("id") ON DELETE SET NULL,
  CONSTRAINT "LegalPages_slug_check" CHECK (char_length(trim("slug")) > 0),
  CONSTRAINT "LegalPages_title_check" CHECK (char_length(trim("title")) > 0)
);

ALTER TABLE "LegalPages" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "legal_pages_select" ON "LegalPages";
CREATE POLICY "legal_pages_select" ON "LegalPages"
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "legal_pages_write" ON "LegalPages";
CREATE POLICY "legal_pages_write" ON "LegalPages"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

INSERT INTO "LegalPages" ("slug", "title", "content")
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
Vos données sont traitées conformément à la réglementation applicable et à la politique de confidentialité de Tibus.

5. Responsabilité
Tibus agit en tant qu''intermédiaire technique. La compagnie de transport reste responsable de l''exécution du service de transport.

6. Modification
Ces conditions peuvent être mises à jour par l''administrateur de la plateforme. La version publiée sur cette page fait foi.

Pour toute question : contactez le support Tibus.'
)
ON CONFLICT ("slug") DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_legal_page(p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row "LegalPages"%ROWTYPE;
BEGIN
  SELECT *
  INTO v_row
  FROM "LegalPages"
  WHERE "slug" = trim(p_slug)
  LIMIT 1;

  IF v_row."slug" IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'slug', v_row."slug",
    'title', v_row."title",
    'content', v_row."content",
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
  v_row "LegalPages"%ROWTYPE;
  v_user uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  v_user := public.current_app_user_id();

  INSERT INTO "LegalPages" ("slug", "title", "content", "updatedBy", "updatedAt")
  VALUES (trim(p_slug), trim(p_title), COALESCE(p_content, ''), v_user, now())
  ON CONFLICT ("slug") DO UPDATE SET
    "title" = EXCLUDED."title",
    "content" = EXCLUDED."content",
    "updatedBy" = EXCLUDED."updatedBy",
    "updatedAt" = now()
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'slug', v_row."slug",
    'title', v_row."title",
    'content', v_row."content",
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_legal_page(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_legal_page(text, text, text) TO authenticated;
