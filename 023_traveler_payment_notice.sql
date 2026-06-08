-- Lot 23: message popup paiement voyageur (éditable super_admin).

CREATE TABLE IF NOT EXISTS "TravelerPaymentNotice" (
  "id" uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid NOT NULL,
  "title" text NOT NULL,
  "paragraph1" text NOT NULL,
  "paragraph2" text NOT NULL,
  "networkIntro" text NOT NULL,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users" ("id") DEFERRABLE INITIALLY IMMEDIATE
);

CREATE TABLE IF NOT EXISTS "TravelerPaymentNoticeCountryHints" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "countryId" uuid NOT NULL REFERENCES "Countries" ("id") ON DELETE CASCADE,
  "countryCode" text NOT NULL,
  "cheapestNetwork" text NOT NULL,
  "sortOrder" integer NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true,
  CONSTRAINT "TravelerPaymentNoticeCountryHints_code_check"
    CHECK (char_length(trim("countryCode")) > 0),
  CONSTRAINT "TravelerPaymentNoticeCountryHints_network_check"
    CHECK (char_length(trim("cheapestNetwork")) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS "TravelerPaymentNoticeCountryHints_country_key"
  ON "TravelerPaymentNoticeCountryHints" ("countryId");

CREATE INDEX IF NOT EXISTS "TravelerPaymentNoticeCountryHints_sort_idx"
  ON "TravelerPaymentNoticeCountryHints" ("sortOrder", "countryCode");

ALTER TABLE "TravelerPaymentNotice" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "TravelerPaymentNoticeCountryHints" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "traveler_payment_notice_select" ON "TravelerPaymentNotice";
CREATE POLICY "traveler_payment_notice_select" ON "TravelerPaymentNotice"
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "traveler_payment_notice_hints_select" ON "TravelerPaymentNoticeCountryHints";
CREATE POLICY "traveler_payment_notice_hints_select" ON "TravelerPaymentNoticeCountryHints"
  FOR SELECT TO anon, authenticated
  USING ("isActive" = true);

DROP POLICY IF EXISTS "traveler_payment_notice_write" ON "TravelerPaymentNotice";
CREATE POLICY "traveler_payment_notice_write" ON "TravelerPaymentNotice"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "traveler_payment_notice_hints_write" ON "TravelerPaymentNoticeCountryHints";
CREATE POLICY "traveler_payment_notice_hints_write" ON "TravelerPaymentNoticeCountryHints"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

INSERT INTO "TravelerPaymentNotice" ("id", "title", "paragraph1", "paragraph2", "networkIntro")
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Confirmer avant paiement',
  'Des places sont encore disponibles, mais votre siège n''est pas garanti tant que le paiement n''est pas confirmé.',
  'Vous pouvez payer maintenant ou revenir plus tard (vos informations seront conservées sur cet appareil uniquement).',
  'Le montant total dépendra des frais du réseau que vous choisirez. Voici les moins chers par pays :'
)
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "TravelerPaymentNoticeCountryHints" ("countryId", "countryCode", "cheapestNetwork", "sortOrder")
SELECT co.id, 'CI', 'wave', 1
FROM "Countries" co
WHERE co.name = 'Côte d''Ivoire'
ON CONFLICT ("countryId") DO NOTHING;

INSERT INTO "TravelerPaymentNoticeCountryHints" ("countryId", "countryCode", "cheapestNetwork", "sortOrder")
SELECT co.id, 'BN', 'mtn', 2
FROM "Countries" co
WHERE co.name = 'Bénin'
ON CONFLICT ("countryId") DO NOTHING;

INSERT INTO "TravelerPaymentNoticeCountryHints" ("countryId", "countryCode", "cheapestNetwork", "sortOrder")
SELECT co.id, 'BF', 'orange', 3
FROM "Countries" co
WHERE co.name IN ('Burkina Faso', 'Burkina')
ON CONFLICT ("countryId") DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_traveler_payment_notice()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'title', n.title,
    'paragraph1', n.paragraph1,
    'paragraph2', n.paragraph2,
    'networkIntro', n."networkIntro",
    'updatedAt', n."updatedAt",
    'hints', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', h.id,
          'countryId', h."countryId",
          'countryCode', h."countryCode",
          'countryName', c.name,
          'cheapestNetwork', h."cheapestNetwork",
          'sortOrder', h."sortOrder",
          'isActive', h."isActive"
        )
        ORDER BY h."sortOrder", h."countryCode"
      )
      FROM "TravelerPaymentNoticeCountryHints" h
      JOIN "Countries" c ON c.id = h."countryId"
      WHERE h."isActive" = true
    ), '[]'::jsonb)
  )
  FROM "TravelerPaymentNotice" n
  WHERE n.id = '00000000-0000-0000-0000-000000000001'::uuid;
$$;

CREATE OR REPLACE FUNCTION public.upsert_traveler_payment_notice(
  p_title text,
  p_paragraph1 text,
  p_paragraph2 text,
  p_network_intro text,
  p_hints jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  hint jsonb;
  v_country_id uuid;
  v_country_code text;
  v_network text;
  v_sort integer;
  v_active boolean;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acces refuse';
  END IF;

  v_user_id := public.current_app_user_id();

  IF p_title IS NULL OR trim(p_title) = '' THEN
    RAISE EXCEPTION 'Titre requis';
  END IF;
  IF p_paragraph1 IS NULL OR trim(p_paragraph1) = '' THEN
    RAISE EXCEPTION 'Paragraphe 1 requis';
  END IF;
  IF p_paragraph2 IS NULL OR trim(p_paragraph2) = '' THEN
    RAISE EXCEPTION 'Paragraphe 2 requis';
  END IF;
  IF p_network_intro IS NULL OR trim(p_network_intro) = '' THEN
    RAISE EXCEPTION 'Introduction reseaux requise';
  END IF;

  INSERT INTO "TravelerPaymentNotice" ("id", "title", "paragraph1", "paragraph2", "networkIntro", "updatedBy")
  VALUES (
    '00000000-0000-0000-0000-000000000001',
    trim(p_title),
    trim(p_paragraph1),
    trim(p_paragraph2),
    trim(p_network_intro),
    v_user_id
  )
  ON CONFLICT ("id") DO UPDATE SET
    "title" = EXCLUDED."title",
    "paragraph1" = EXCLUDED."paragraph1",
    "paragraph2" = EXCLUDED."paragraph2",
    "networkIntro" = EXCLUDED."networkIntro",
    "updatedBy" = EXCLUDED."updatedBy",
    "updatedAt" = now();

  DELETE FROM "TravelerPaymentNoticeCountryHints";

  IF p_hints IS NOT NULL AND jsonb_typeof(p_hints) = 'array' THEN
    FOR hint IN SELECT value FROM jsonb_array_elements(p_hints)
    LOOP
      v_country_id := NULLIF(hint->>'countryId', '')::uuid;
      v_country_code := upper(trim(COALESCE(hint->>'countryCode', '')));
      v_network := lower(trim(COALESCE(hint->>'cheapestNetwork', '')));
      v_sort := COALESCE(NULLIF(hint->>'sortOrder', '')::integer, 0);
      v_active := COALESCE((hint->>'isActive')::boolean, true);

      IF v_country_id IS NULL OR v_country_code = '' OR v_network = '' THEN
        CONTINUE;
      END IF;

      INSERT INTO "TravelerPaymentNoticeCountryHints" (
        "countryId", "countryCode", "cheapestNetwork", "sortOrder", "isActive"
      )
      VALUES (v_country_id, v_country_code, v_network, v_sort, v_active);
    END LOOP;
  END IF;

  RETURN public.get_traveler_payment_notice();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_traveler_payment_notice() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_traveler_payment_notice(text, text, text, text, jsonb) TO authenticated;
