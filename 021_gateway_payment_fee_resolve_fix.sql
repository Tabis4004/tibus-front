-- Lot 21: résolution frais gateway plus tolérante + messages d'erreur explicites.
-- À exécuter après 019 et 020.

CREATE OR REPLACE FUNCTION public.resolve_gateway_payment_fee(
  p_gateway text,
  p_country_id uuid,
  p_method text
)
RETURNS TABLE(
  id uuid,
  gateway text,
  country_id uuid,
  method text,
  y_percent double precision,
  z_percent double precision,
  f_fixed double precision
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_gateway IS NULL OR trim(p_gateway) = '' THEN
    RAISE EXCEPTION 'gateway requis';
  END IF;
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'country_id requis';
  END IF;
  IF p_method IS NULL OR trim(p_method) = '' THEN
    RAISE EXCEPTION 'method requise';
  END IF;

  RETURN QUERY
  SELECT
    gpf.id,
    gpf.gateway,
    gpf."countryId" AS country_id,
    gpf.method,
    gpf."yPercent" AS y_percent,
    gpf."zPercent" AS z_percent,
    gpf."fFixed" AS f_fixed
  FROM "GatewayPaymentFees" gpf
  WHERE gpf."isActive" = true
    AND lower(gpf.gateway) = lower(trim(p_gateway))
    AND gpf."countryId" = p_country_id
    AND lower(gpf.method) = lower(trim(p_method))
  ORDER BY gpf."updatedAt" DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    gpf.id,
    gpf.gateway,
    gpf."countryId" AS country_id,
    gpf.method,
    gpf."yPercent" AS y_percent,
    gpf."zPercent" AS z_percent,
    gpf."fFixed" AS f_fixed
  FROM "GatewayPaymentFees" gpf
  WHERE gpf."isActive" = true
    AND lower(gpf.gateway) = lower(trim(p_gateway))
    AND gpf."countryId" = p_country_id
  ORDER BY
    CASE lower(gpf.method)
      WHEN lower(trim(p_method)) THEN 0
      WHEN 'mobile_money' THEN 1
      WHEN 'card' THEN 2
      ELSE 3
    END,
    gpf."updatedAt" DESC
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_traveler_payment_total(
  p_nominal_amount double precision,
  p_company_id uuid,
  p_gateway text DEFAULT 'fedapay',
  p_method text DEFAULT 'mobile_money',
  p_trip_margin_percent double precision DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
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
  IF p_nominal_amount IS NULL OR p_nominal_amount < 0 THEN
    RAISE EXCEPTION 'Montant nominal invalide';
  END IF;
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id requis';
  END IF;

  SELECT c."countryId", c.name
  INTO v_country_id, v_company_name
  FROM "Companies" c
  WHERE c.id = p_company_id;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie sans pays (countryId NULL) pour %', COALESCE(v_company_name, p_company_id::text);
  END IF;

  SELECT co.name INTO v_country_name
  FROM "Countries" co
  WHERE co.id = v_country_id;

  SELECT * INTO v_margin
  FROM public.resolve_seller_commission_setting(p_company_id)
  LIMIT 1;

  v_x := COALESCE(p_trip_margin_percent, v_margin.rate, 0);

  SELECT * INTO v_fees
  FROM public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method)
  LIMIT 1;

  IF NOT FOUND THEN
    SELECT string_agg(
      lower(gpf.gateway) || '/' || lower(gpf.method) || ' (actif=' || gpf."isActive"::text || ')',
      ', ' ORDER BY gpf.gateway, gpf.method
    )
    INTO v_configured
    FROM "GatewayPaymentFees" gpf
    WHERE gpf."countryId" = v_country_id;

    RAISE EXCEPTION
      'Configuration frais gateway manquante pour gateway=% pays=% (id=%) methode=%. Config existante pour ce pays: %',
      lower(p_gateway),
      COALESCE(v_country_name, '?'),
      v_country_id,
      lower(p_method),
      COALESCE(v_configured, 'aucune');
  END IF;

  v_y := v_fees.y_percent / 100.0;
  v_z := v_fees.z_percent / 100.0;
  v_f := COALESCE(v_fees.f_fixed, 0);
  v_denom := 1 - v_z - v_y;

  IF v_denom <= 0 THEN
    RAISE EXCEPTION 'Taux gateway invalides: Y+Z >= 100%%';
  END IF;

  v_raw := (p_nominal_amount * (1 + v_x / 100.0) + v_f) / v_denom;
  v_total := CEIL(v_raw);

  RETURN jsonb_build_object(
    'nominalAmount', p_nominal_amount,
    'platformMarginPercent', v_x,
    'platformNetAmount', p_nominal_amount * (1 + v_x / 100.0),
    'gatewayFeePercent', v_fees.y_percent,
    'geniusPayFeePercent', v_fees.z_percent,
    'fixedFee', v_f,
    'rawTotalAmount', v_raw,
    'totalAmount', v_total,
    'paidBy', COALESCE(v_margin.paid_by, 'company'),
    'marginScope', COALESCE(v_margin.setting_scope, 'unset'),
    'gateway', lower(p_gateway),
    'method', lower(v_fees.method),
    'requestedMethod', lower(p_method),
    'countryId', v_country_id,
    'countryName', v_country_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_gateway_payment_fee(text, uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_traveler_payment_total(double precision, uuid, text, text, double precision) TO anon, authenticated;
