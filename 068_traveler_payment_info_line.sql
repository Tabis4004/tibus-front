-- 068 — Ligne d'information voyageur (éditable super admin, popup paiement)
-- Exécuter après 023_traveler_payment_notice.sql

ALTER TABLE "TravelerPaymentNotice"
  ADD COLUMN IF NOT EXISTS "infoLine" text;

UPDATE "TravelerPaymentNotice"
SET "infoLine" = COALESCE(
  NULLIF(trim("infoLine"), ''),
  'Redirection vers le paiement sécurisé. Aucune place n''est réservée et aucun billet n''est émis tant que le paiement n''est pas confirmé.'
)
WHERE id = '00000000-0000-0000-0000-000000000001'::uuid;

ALTER TABLE "TravelerPaymentNotice"
  ALTER COLUMN "infoLine" SET NOT NULL;

ALTER TABLE "TravelerPaymentNotice"
  ALTER COLUMN "infoLine" SET DEFAULT
    'Redirection vers le paiement sécurisé. Aucune place n''est réservée et aucun billet n''est émis tant que le paiement n''est pas confirmé.';

CREATE OR REPLACE FUNCTION public.get_traveler_payment_notice()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'title', n.title,
    'infoLine', n."infoLine",
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
  p_info_line text,
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
  IF p_info_line IS NULL OR trim(p_info_line) = '' THEN
    RAISE EXCEPTION 'Ligne d''information requise';
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

  INSERT INTO "TravelerPaymentNotice" (
    "id", "title", "infoLine", "paragraph1", "paragraph2", "networkIntro", "updatedBy"
  ) VALUES (
    '00000000-0000-0000-0000-000000000001',
    trim(p_title),
    trim(p_info_line),
    trim(p_paragraph1),
    trim(p_paragraph2),
    trim(p_network_intro),
    v_user_id
  )
  ON CONFLICT ("id") DO UPDATE SET
    "title" = EXCLUDED."title",
    "infoLine" = EXCLUDED."infoLine",
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

DROP FUNCTION IF EXISTS public.upsert_traveler_payment_notice(text, text, text, text, jsonb);

DROP TABLE IF EXISTS "StakeholderCommissionInfo" CASCADE;
DROP FUNCTION IF EXISTS public.get_stakeholder_commission_info();
DROP FUNCTION IF EXISTS public.upsert_stakeholder_commission_info(text);

GRANT EXECUTE ON FUNCTION public.get_traveler_payment_notice() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_traveler_payment_notice(text, text, text, text, text, jsonb) TO authenticated;
