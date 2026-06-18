-- Contrat propriétaire obligatoire avant mise en live + autorisation admin pays (période test).

ALTER TABLE public."Companies"
  ADD COLUMN IF NOT EXISTS "ownerContractAcceptedAt" timestamptz,
  ADD COLUMN IF NOT EXISTS "ownerContractAcceptedBy" uuid REFERENCES public."Users"(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS "liveAuthorizedByAdmin" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "liveAuthorizedAt" timestamptz,
  ADD COLUMN IF NOT EXISTS "liveAuthorizedBy" uuid REFERENCES public."Users"(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public._company_can_enable_live(p_row public."Companies")
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    p_row."ownerContractAcceptedAt" IS NOT NULL
    OR COALESCE(p_row."liveAuthorizedByAdmin", false) = true;
$$;

CREATE OR REPLACE FUNCTION public.get_commercial_offer_technical_annex(
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
    RETURN NULL;
  END IF;

  IF v_locale NOT IN ('fr', 'en') THEN
    v_locale := 'fr';
  END IF;

  SELECT c.document
  INTO v_document
  FROM public."CommercialOfferCustomization" c
  WHERE c."countryId" = p_country_id
    AND c.locale = v_locale;

  IF v_document IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'heading', '2. Architecture technique (incluse dans l''abonnement)',
    'architectureTable', v_document #> '{technical,architectureTable}',
    'modules', v_document #> '{technical,modules}'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_commercial_offer_technical_annex(uuid, text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_company_owner_contract_status(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."Companies"%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public."Companies" WHERE id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(v_row."countryId", ARRAY['admin_pays'])
    OR public.has_company_role(p_company_id, ARRAY['owner'])
  ) THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  RETURN jsonb_build_object(
    'ownerContractAcceptedAt', v_row."ownerContractAcceptedAt",
    'liveAuthorizedByAdmin', COALESCE(v_row."liveAuthorizedByAdmin", false),
    'liveAuthorizedAt', v_row."liveAuthorizedAt",
    'isActive', COALESCE(v_row."isActive", false),
    'arretReservation', COALESCE(v_row."arretReservation", false),
    'canEnableLive', public._company_can_enable_live(v_row)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_owner_contract_status(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_company_owner_contract(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['owner']) THEN
    RAISE EXCEPTION 'Seul le propriétaire peut accepter le contrat';
  END IF;

  SELECT id INTO v_user FROM public."Users" WHERE "authUserId" = auth.uid() LIMIT 1;

  UPDATE public."Companies"
  SET
    "ownerContractAcceptedAt" = now(),
    "ownerContractAcceptedBy" = v_user
  WHERE id = p_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_company_owner_contract(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_company_arret_reservation(
  p_company_id uuid,
  p_enabled boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."Companies"%ROWTYPE;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['owner']) THEN
    RAISE EXCEPTION 'Seul le propriétaire peut modifier la mise en ligne';
  END IF;

  SELECT * INTO v_row FROM public."Companies" WHERE id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF p_enabled AND NOT public._company_can_enable_live(v_row) THEN
    RAISE EXCEPTION 'Acceptez le contrat propriétaire (avec annexe technique) avant la mise en live';
  END IF;

  UPDATE public."Companies"
  SET "arretReservation" = p_enabled
  WHERE id = p_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_company_arret_reservation(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_company_live_authorization(
  p_company_id uuid,
  p_authorized boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."Companies"%ROWTYPE;
  v_user uuid;
BEGIN
  SELECT * INTO v_row FROM public."Companies" WHERE id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(v_row."countryId", ARRAY['admin_pays'])
  ) THEN
    RAISE EXCEPTION 'Accès réservé à l''administrateur pays';
  END IF;

  SELECT id INTO v_user FROM public."Users" WHERE "authUserId" = auth.uid() LIMIT 1;

  UPDATE public."Companies"
  SET
    "liveAuthorizedByAdmin" = p_authorized,
    "liveAuthorizedAt" = CASE WHEN p_authorized THEN now() ELSE NULL END,
    "liveAuthorizedBy" = CASE WHEN p_authorized THEN v_user ELSE NULL END
  WHERE id = p_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_company_live_authorization(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_company_active_admin(
  p_company_id uuid,
  p_is_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."Companies"%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public."Companies" WHERE id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(v_row."countryId", ARRAY['admin_pays'])
  ) THEN
    RAISE EXCEPTION 'Accès réservé à l''administrateur pays';
  END IF;

  IF p_is_active AND NOT public._company_can_enable_live(v_row) AND NOT COALESCE(v_row."liveAuthorizedByAdmin", false) THEN
    RAISE EXCEPTION 'Autorisez d''abord la mise en live test ou attendez l''acceptation du contrat';
  END IF;

  UPDATE public."Companies"
  SET "isActive" = p_is_active
  WHERE id = p_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_company_active_admin(uuid, boolean) TO authenticated;
