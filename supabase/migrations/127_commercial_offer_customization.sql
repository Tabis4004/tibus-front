-- 127 — Offre commerciale personnalisée par pays (admin_pays)

CREATE TABLE IF NOT EXISTS public."CommercialOfferCustomization" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "countryId" uuid NOT NULL REFERENCES public."Countries"(id) ON DELETE CASCADE,
  locale text NOT NULL CHECK (locale IN ('fr', 'en')),
  document jsonb NOT NULL,
  "updatedBy" uuid REFERENCES public."Users"(id) ON DELETE SET NULL,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commercial_offer_customization_country_locale_key UNIQUE ("countryId", locale)
);

CREATE INDEX IF NOT EXISTS idx_commercial_offer_customization_country
  ON public."CommercialOfferCustomization" ("countryId");

ALTER TABLE public."CommercialOfferCustomization" ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.can_manage_commercial_offer_customization(p_country_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_super_admin()
    OR public.has_country_role(p_country_id, ARRAY['admin_pays']);
$$;

CREATE OR REPLACE FUNCTION public.get_commercial_offer_customization(
  p_country_id uuid,
  p_locale text DEFAULT 'fr'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_locale text := COALESCE(NULLIF(TRIM(p_locale), ''), 'fr');
  v_document jsonb;
BEGIN
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  IF v_locale NOT IN ('fr', 'en') THEN
    RAISE EXCEPTION 'Locale invalide';
  END IF;

  IF NOT public.can_manage_commercial_offer_customization(p_country_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT c.document
  INTO v_document
  FROM public."CommercialOfferCustomization" c
  WHERE c."countryId" = p_country_id
    AND c.locale = v_locale;

  RETURN v_document;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_commercial_offer_customization(
  p_country_id uuid,
  p_locale text,
  p_document jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_locale text := COALESCE(NULLIF(TRIM(p_locale), ''), 'fr');
  v_id uuid;
BEGIN
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  IF v_locale NOT IN ('fr', 'en') THEN
    RAISE EXCEPTION 'Locale invalide';
  END IF;

  IF p_document IS NULL OR p_document = 'null'::jsonb THEN
    RAISE EXCEPTION 'Document requis';
  END IF;

  IF NOT public.can_manage_commercial_offer_customization(p_country_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  INSERT INTO public."CommercialOfferCustomization" (
    "countryId",
    locale,
    document,
    "updatedBy",
    "updatedAt"
  )
  VALUES (
    p_country_id,
    v_locale,
    p_document,
    public.current_app_user_id(),
    now()
  )
  ON CONFLICT ON CONSTRAINT commercial_offer_customization_country_locale_key
  DO UPDATE SET
    document = EXCLUDED.document,
    "updatedBy" = EXCLUDED."updatedBy",
    "updatedAt" = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_commercial_offer_customization(
  p_country_id uuid,
  p_locale text DEFAULT 'fr'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_locale text := COALESCE(NULLIF(TRIM(p_locale), ''), 'fr');
BEGIN
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  IF v_locale NOT IN ('fr', 'en') THEN
    RAISE EXCEPTION 'Locale invalide';
  END IF;

  IF NOT public.can_manage_commercial_offer_customization(p_country_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  DELETE FROM public."CommercialOfferCustomization"
  WHERE "countryId" = p_country_id
    AND locale = v_locale;

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_commercial_offer_customization(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_commercial_offer_customization(uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_commercial_offer_customization(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
