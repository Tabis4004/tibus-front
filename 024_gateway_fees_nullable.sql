-- Lot 24: frais gateway nullable (Z/F optionnels) + correctif réseau si lot 22 incomplet.
-- Exécuter après 019 et 020 (remplace/complète 021-022 si besoin).

ALTER TABLE "GatewayPaymentFees"
  ADD COLUMN IF NOT EXISTS "network" text NOT NULL DEFAULT 'default';

ALTER TABLE "GatewayPaymentFees"
  ALTER COLUMN "yPercent" DROP NOT NULL,
  ALTER COLUMN "zPercent" DROP NOT NULL,
  ALTER COLUMN "fFixed" DROP NOT NULL;

ALTER TABLE "GatewayPaymentFees"
  DROP CONSTRAINT IF EXISTS "GatewayPaymentFees_y_check";
ALTER TABLE "GatewayPaymentFees"
  ADD CONSTRAINT "GatewayPaymentFees_y_check"
    CHECK ("yPercent" IS NULL OR ("yPercent" >= 0 AND "yPercent" < 100));

ALTER TABLE "GatewayPaymentFees"
  DROP CONSTRAINT IF EXISTS "GatewayPaymentFees_z_check";
ALTER TABLE "GatewayPaymentFees"
  ADD CONSTRAINT "GatewayPaymentFees_z_check"
    CHECK ("zPercent" IS NULL OR ("zPercent" >= 0 AND "zPercent" < 100));

ALTER TABLE "GatewayPaymentFees"
  DROP CONSTRAINT IF EXISTS "GatewayPaymentFees_f_check";
ALTER TABLE "GatewayPaymentFees"
  ADD CONSTRAINT "GatewayPaymentFees_f_check"
    CHECK ("fFixed" IS NULL OR "fFixed" >= 0);

ALTER TABLE "GatewayPaymentFees"
  DROP CONSTRAINT IF EXISTS "GatewayPaymentFees_combo_check";
ALTER TABLE "GatewayPaymentFees"
  ADD CONSTRAINT "GatewayPaymentFees_combo_check"
    CHECK (COALESCE("yPercent", 0) + COALESCE("zPercent", 0) < 100);

DROP INDEX IF EXISTS "GatewayPaymentFees_active_combo_key";
CREATE UNIQUE INDEX IF NOT EXISTS "GatewayPaymentFees_active_combo_key"
  ON "GatewayPaymentFees" ("gateway", "countryId", "method", "network")
  WHERE "isActive" = true;

DROP FUNCTION IF EXISTS public.resolve_gateway_payment_fee(text, uuid, text);
DROP FUNCTION IF EXISTS public.resolve_gateway_payment_fee(text, uuid, text, text);
DROP FUNCTION IF EXISTS public.upsert_gateway_payment_fee(text, uuid, text, double precision, double precision, double precision, boolean);
DROP FUNCTION IF EXISTS public.upsert_gateway_payment_fee(text, uuid, text, text, double precision, double precision, double precision, boolean);
DROP FUNCTION IF EXISTS public.calculate_traveler_payment_total(double precision, uuid, text, text, double precision);
DROP FUNCTION IF EXISTS public.calculate_traveler_payment_total(double precision, uuid, text, text, text, double precision);

CREATE OR REPLACE FUNCTION public.resolve_gateway_payment_fee(
  p_gateway text,
  p_country_id uuid,
  p_method text,
  p_network text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  gateway text,
  country_id uuid,
  method text,
  network text,
  y_percent double precision,
  z_percent double precision,
  f_fixed double precision,
  used_max_fallback boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_network text;
BEGIN
  IF p_gateway IS NULL OR trim(p_gateway) = '' THEN RAISE EXCEPTION 'gateway requis'; END IF;
  IF p_country_id IS NULL THEN RAISE EXCEPTION 'country_id requis'; END IF;
  IF p_method IS NULL OR trim(p_method) = '' THEN RAISE EXCEPTION 'method requise'; END IF;

  v_network := lower(trim(COALESCE(p_network, '')));
  IF v_network IN ('', 'unknown', 'max', 'default') THEN v_network := NULL; END IF;

  IF v_network IS NOT NULL THEN
    RETURN QUERY
    SELECT gpf.id, gpf.gateway, gpf."countryId", gpf.method, gpf.network,
      COALESCE(gpf."yPercent", 0), gpf."zPercent", gpf."fFixed", false
    FROM "GatewayPaymentFees" gpf
    WHERE gpf."isActive" = true
      AND lower(gpf.gateway) = lower(trim(p_gateway))
      AND gpf."countryId" = p_country_id
      AND lower(gpf.method) = lower(trim(p_method))
      AND lower(gpf.network) = v_network
    ORDER BY gpf."updatedAt" DESC LIMIT 1;
    IF FOUND THEN RETURN; END IF;
  END IF;

  RETURN QUERY
  SELECT gpf.id, gpf.gateway, gpf."countryId", gpf.method, gpf.network,
    COALESCE(gpf."yPercent", 0), gpf."zPercent", gpf."fFixed", true
  FROM "GatewayPaymentFees" gpf
  WHERE gpf."isActive" = true
    AND lower(gpf.gateway) = lower(trim(p_gateway))
    AND gpf."countryId" = p_country_id
    AND lower(gpf.method) = lower(trim(p_method))
    AND lower(gpf.network) <> 'default'
  ORDER BY COALESCE(gpf."yPercent", 0) DESC, COALESCE(gpf."fFixed", 0) DESC, gpf."updatedAt" DESC
  LIMIT 1;
  IF FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT gpf.id, gpf.gateway, gpf."countryId", gpf.method, gpf.network,
    COALESCE(gpf."yPercent", 0), gpf."zPercent", gpf."fFixed", true
  FROM "GatewayPaymentFees" gpf
  WHERE gpf."isActive" = true
      AND lower(gpf.gateway) = lower(trim(p_gateway))
      AND gpf."countryId" = p_country_id
      AND lower(gpf.method) = lower(trim(p_method))
  ORDER BY COALESCE(gpf."yPercent", 0) DESC, COALESCE(gpf."fFixed", 0) DESC, gpf."updatedAt" DESC
  LIMIT 1;
END;
$$;

DROP FUNCTION IF EXISTS public.list_gateway_payment_fees();
CREATE OR REPLACE FUNCTION public.list_gateway_payment_fees()
RETURNS TABLE(
  id uuid, gateway text, country_id uuid, country_name text, method text, network text,
  y_percent double precision, z_percent double precision, f_fixed double precision,
  is_active boolean, updated_at timestamptz, updated_by_name text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT gpf.id, gpf.gateway, gpf."countryId", c.name::text, gpf.method, gpf.network,
    gpf."yPercent", gpf."zPercent", gpf."fFixed", gpf."isActive", gpf."updatedAt",
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')
  FROM "GatewayPaymentFees" gpf
  JOIN "Countries" c ON c.id = gpf."countryId"
  LEFT JOIN "Users" u ON u.id = gpf."updatedBy"
  WHERE public.is_super_admin() OR public.has_country_role(gpf."countryId", ARRAY['admin_pays'])
  ORDER BY c.name, gpf.gateway, gpf.method, gpf.network;
$$;

CREATE OR REPLACE FUNCTION public.upsert_gateway_payment_fee(
  p_gateway text,
  p_country_id uuid,
  p_method text,
  p_y_percent double precision,
  p_z_percent double precision DEFAULT NULL,
  p_network text DEFAULT 'default',
  p_f_fixed double precision DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS TABLE(
  id uuid, gateway text, country_id uuid, country_name text, method text, network text,
  y_percent double precision, z_percent double precision, f_fixed double precision,
  is_active boolean, updated_at timestamptz, updated_by_name text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_existing_id uuid;
  v_network text;
  v_y double precision;
  v_z double precision;
  v_f double precision;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF p_gateway IS NULL OR trim(p_gateway) = '' THEN RAISE EXCEPTION 'gateway requis'; END IF;
  IF p_country_id IS NULL THEN RAISE EXCEPTION 'country_id requis'; END IF;
  IF p_method IS NULL OR trim(p_method) = '' THEN RAISE EXCEPTION 'method requise'; END IF;

  v_network := lower(trim(COALESCE(p_network, 'default')));
  IF v_network = '' THEN v_network := 'default'; END IF;

  v_y := COALESCE(p_y_percent, 0);
  v_z := p_z_percent;
  v_f := p_f_fixed;

  IF v_y < 0 OR v_y >= 100 THEN RAISE EXCEPTION 'Y doit etre entre 0 et 100 (ou vide=0)'; END IF;
  IF v_z IS NOT NULL AND (v_z < 0 OR v_z >= 100) THEN RAISE EXCEPTION 'Z doit etre entre 0 et 100'; END IF;
  IF COALESCE(v_y, 0) + COALESCE(v_z, 0) >= 100 THEN RAISE EXCEPTION 'Y + Z doit etre < 100'; END IF;
  IF v_f IS NOT NULL AND v_f < 0 THEN RAISE EXCEPTION 'F doit etre >= 0'; END IF;
  IF NOT public.can_manage_commission_country(p_country_id) THEN RAISE EXCEPTION 'Acces frais gateway refuse pour ce pays'; END IF;

  SELECT gpf.id INTO v_existing_id
  FROM "GatewayPaymentFees" gpf
  WHERE lower(gpf.gateway) = lower(trim(p_gateway))
    AND gpf."countryId" = p_country_id
    AND lower(gpf.method) = lower(trim(p_method))
    AND lower(gpf.network) = v_network
  ORDER BY gpf."isActive" DESC, gpf."updatedAt" DESC LIMIT 1;

  IF v_existing_id IS NULL THEN
    INSERT INTO "GatewayPaymentFees" (
      "gateway", "countryId", "method", "network", "yPercent", "zPercent", "fFixed", "isActive", "updatedBy"
    ) VALUES (
      lower(trim(p_gateway)), p_country_id, lower(trim(p_method)), v_network,
      v_y, v_z, v_f, COALESCE(p_is_active, true), v_user_id
    ) RETURNING "GatewayPaymentFees".id INTO v_existing_id;
  ELSE
    UPDATE "GatewayPaymentFees" SET
      "gateway" = lower(trim(p_gateway)), "method" = lower(trim(p_method)), "network" = v_network,
      "yPercent" = v_y, "zPercent" = v_z, "fFixed" = v_f,
      "isActive" = COALESCE(p_is_active, true), "updatedBy" = v_user_id, "updatedAt" = now()
    WHERE id = v_existing_id;
  END IF;

  RETURN QUERY SELECT * FROM public.list_gateway_payment_fees() l WHERE l.id = v_existing_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_traveler_payment_total(
  p_nominal_amount double precision,
  p_company_id uuid,
  p_gateway text DEFAULT 'fedapay',
  p_method text DEFAULT 'mobile_money',
  p_network text DEFAULT NULL,
  p_trip_margin_percent double precision DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
  v_country_name text;
  v_company_name text;
  v_margin record;
  v_fees record;
  v_x double precision;
  v_y double precision;
  v_z double precision;
  v_f double precision;
  v_denom double precision;
  v_raw double precision;
  v_total double precision;
  v_configured text;
BEGIN
  IF p_nominal_amount IS NULL OR p_nominal_amount < 0 THEN RAISE EXCEPTION 'Montant nominal invalide'; END IF;
  IF p_company_id IS NULL THEN RAISE EXCEPTION 'company_id requis'; END IF;

  SELECT c."countryId", c.name INTO v_country_id, v_company_name FROM "Companies" c WHERE c.id = p_company_id;
  IF v_country_id IS NULL THEN RAISE EXCEPTION 'Compagnie sans pays (countryId NULL) pour %', COALESCE(v_company_name, p_company_id::text); END IF;
  SELECT co.name INTO v_country_name FROM "Countries" co WHERE co.id = v_country_id;

  SELECT * INTO v_margin FROM public.resolve_seller_commission_setting(p_company_id) LIMIT 1;
  v_x := COALESCE(p_trip_margin_percent, v_margin.rate, 0);

  SELECT * INTO v_fees FROM public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method, p_network) LIMIT 1;
  IF NOT FOUND THEN
    SELECT string_agg(lower(gpf.gateway)||'/'||lower(gpf.method)||'/'||lower(gpf.network), ', ')
    INTO v_configured FROM "GatewayPaymentFees" gpf WHERE gpf."countryId" = v_country_id;
    RAISE EXCEPTION 'Configuration frais gateway manquante pour gateway=% pays=% methode=% reseau=%. Config: %',
      lower(p_gateway), COALESCE(v_country_name,'?'), lower(p_method), lower(COALESCE(p_network,'max')), COALESCE(v_configured,'aucune');
  END IF;

  v_y := COALESCE(v_fees.y_percent, 0) / 100.0;
  v_z := COALESCE(v_fees.z_percent, 0) / 100.0;
  v_f := COALESCE(v_fees.f_fixed, 0);
  v_denom := 1 - v_z - v_y;
  IF v_denom <= 0 THEN RAISE EXCEPTION 'Taux gateway invalides: Y+Z >= 100%%'; END IF;

  v_raw := (p_nominal_amount * (1 + v_x / 100.0) + v_f) / v_denom;
  v_total := CEIL(v_raw);

  RETURN jsonb_build_object(
    'nominalAmount', p_nominal_amount,
    'platformMarginPercent', v_x,
    'platformNetAmount', p_nominal_amount * (1 + v_x / 100.0),
    'gatewayFeePercent', COALESCE(v_fees.y_percent, 0),
    'geniusPayFeePercent', COALESCE(v_fees.z_percent, 0),
    'fixedFee', v_f,
    'rawTotalAmount', v_raw,
    'totalAmount', v_total,
    'paidBy', COALESCE(v_margin.paid_by, 'company'),
    'marginScope', COALESCE(v_margin.setting_scope, 'unset'),
    'gateway', lower(p_gateway),
    'method', lower(v_fees.method),
    'network', lower(v_fees.network),
    'requestedNetwork', lower(COALESCE(NULLIF(trim(p_network), ''), 'unknown')),
    'usedMaxFallback', COALESCE(v_fees.used_max_fallback, false),
    'countryId', v_country_id,
    'countryName', v_country_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_gateway_payment_fee(text, uuid, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_gateway_payment_fees() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_gateway_payment_fee(text, uuid, text, double precision, double precision, text, double precision, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_traveler_payment_total(double precision, uuid, text, text, text, double precision) TO anon, authenticated;
