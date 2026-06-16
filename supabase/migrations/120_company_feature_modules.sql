-- Lot 120: Modules commerciaux A–F activables par compagnie (offre Tibus).

CREATE TABLE IF NOT EXISTS public."CompanyFeatureModules" (
  "companyId" uuid PRIMARY KEY REFERENCES public."Companies"(id) ON DELETE CASCADE,
  "moduleA" boolean NOT NULL DEFAULT true,
  "moduleB" boolean NOT NULL DEFAULT true,
  "moduleC" boolean NOT NULL DEFAULT true,
  "moduleD" boolean NOT NULL DEFAULT true,
  "moduleE" boolean NOT NULL DEFAULT false,
  "moduleF" boolean NOT NULL DEFAULT false,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES public."Users"(id)
);

CREATE INDEX IF NOT EXISTS company_feature_modules_updated_idx
  ON public."CompanyFeatureModules" ("updatedAt" DESC);

ALTER TABLE public."CompanyFeatureModules" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_feature_modules_read ON public."CompanyFeatureModules";
CREATE POLICY company_feature_modules_read ON public."CompanyFeatureModules"
  FOR SELECT
  USING (
    public.is_super_admin()
    OR public.has_company_role("companyId", ARRAY['owner', 'comptable_compagnie'])
    OR EXISTS (
      SELECT 1 FROM public."Companies" c
      WHERE c.id = "companyId"
        AND public.has_country_role(c."countryId", ARRAY['admin_pays'])
    )
  );

DROP POLICY IF EXISTS company_feature_modules_write ON public."CompanyFeatureModules";
CREATE POLICY company_feature_modules_write ON public."CompanyFeatureModules"
  FOR ALL
  USING (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public."Companies" c
      WHERE c.id = "companyId"
        AND public.has_country_role(c."countryId", ARRAY['admin_pays'])
    )
  )
  WITH CHECK (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public."Companies" c
      WHERE c.id = "companyId"
        AND public.has_country_role(c."countryId", ARRAY['admin_pays'])
    )
  );

INSERT INTO public."CompanyFeatureModules" (
  "companyId", "moduleA", "moduleB", "moduleC", "moduleD", "moduleE", "moduleF"
)
SELECT c.id, true, true, true, true, true, false
FROM public."Companies" c
ON CONFLICT ("companyId") DO NOTHING;

CREATE OR REPLACE FUNCTION public._company_module_flag(
  p_row public."CompanyFeatureModules",
  p_module text
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN CASE upper(trim(p_module))
    WHEN 'A' THEN p_row."moduleA"
    WHEN 'B' THEN p_row."moduleB"
    WHEN 'C' THEN p_row."moduleC"
    WHEN 'D' THEN p_row."moduleD"
    WHEN 'E' THEN p_row."moduleE"
    WHEN 'F' THEN p_row."moduleF"
    ELSE false
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.company_has_module(
  p_company_id uuid,
  p_module text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."CompanyFeatureModules"%ROWTYPE;
  v_enabled boolean;
  v_module text := upper(trim(p_module));
BEGIN
  IF p_company_id IS NULL OR v_module = '' THEN
    RETURN false;
  END IF;

  SELECT * INTO v_row
  FROM public."CompanyFeatureModules"
  WHERE "companyId" = p_company_id;

  IF NOT FOUND THEN
  -- Rétrocompatibilité : compagnies sans ligne = pack quasi complet hors TPE.
    RETURN v_module <> 'F';
  END IF;

  v_enabled := public._company_module_flag(v_row, v_module);
  IF NOT v_enabled THEN
    RETURN false;
  END IF;

  IF v_module IN ('B', 'C', 'E') AND NOT v_row."moduleA" THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_company_module(
  p_company_id uuid,
  p_module text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_super_admin() THEN
    RETURN;
  END IF;

  IF NOT public.company_has_module(p_company_id, p_module) THEN
    RAISE EXCEPTION 'Module % non activé pour cette compagnie', upper(trim(p_module));
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_company_feature_modules(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public."CompanyFeatureModules"%ROWTYPE;
  v_country_id uuid;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id requis';
  END IF;

  SELECT c."countryId" INTO v_country_id
  FROM public."Companies" c
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT * INTO v_row
  FROM public."CompanyFeatureModules"
  WHERE "companyId" = p_company_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'companyId', p_company_id,
      'moduleA', true,
      'moduleB', true,
      'moduleC', true,
      'moduleD', true,
      'moduleE', true,
      'moduleF', false,
      'updatedAt', now()
    );
  END IF;

  RETURN jsonb_build_object(
    'companyId', v_row."companyId",
    'moduleA', v_row."moduleA",
    'moduleB', v_row."moduleB",
    'moduleC', v_row."moduleC",
    'moduleD', v_row."moduleD",
    'moduleE', v_row."moduleE",
    'moduleF', v_row."moduleF",
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_company_feature_modules(
  p_company_id uuid,
  p_module_a boolean,
  p_module_b boolean,
  p_module_c boolean,
  p_module_d boolean,
  p_module_e boolean,
  p_module_f boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
  v_a boolean := COALESCE(p_module_a, true);
  v_b boolean := COALESCE(p_module_b, false);
  v_c boolean := COALESCE(p_module_c, false);
  v_d boolean := COALESCE(p_module_d, false);
  v_e boolean := COALESCE(p_module_e, false);
  v_f boolean := COALESCE(p_module_f, false);
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id requis';
  END IF;

  SELECT c."countryId" INTO v_country_id
  FROM public."Companies" c
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_country_role(v_country_id, ARRAY['admin_pays'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF NOT v_a AND (v_b OR v_c OR v_e) THEN
    RAISE EXCEPTION 'Le module A (billetterie) est requis pour B, C ou E';
  END IF;

  IF v_b AND NOT v_a THEN v_b := false; END IF;
  IF v_c AND NOT v_a THEN v_c := false; END IF;
  IF v_e AND NOT v_a THEN v_e := false; END IF;

  INSERT INTO public."CompanyFeatureModules" (
    "companyId", "moduleA", "moduleB", "moduleC", "moduleD", "moduleE", "moduleF", "updatedBy"
  ) VALUES (
    p_company_id, v_a, v_b, v_c, v_d, v_e, v_f, public.current_app_user_id()
  )
  ON CONFLICT ("companyId") DO UPDATE SET
    "moduleA" = EXCLUDED."moduleA",
    "moduleB" = EXCLUDED."moduleB",
    "moduleC" = EXCLUDED."moduleC",
    "moduleD" = EXCLUDED."moduleD",
    "moduleE" = EXCLUDED."moduleE",
    "moduleF" = EXCLUDED."moduleF",
    "updatedAt" = now(),
    "updatedBy" = EXCLUDED."updatedBy";

  RETURN public.get_company_feature_modules(p_company_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.company_has_module(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assert_company_module(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_feature_modules(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_company_feature_modules(uuid, boolean, boolean, boolean, boolean, boolean, boolean) TO authenticated;
