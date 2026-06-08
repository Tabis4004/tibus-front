-- Lot 20: calcul voyageur T = (M(1+X)+F)/(1-Z-Y) via CommissionSettings + GatewayPaymentFees.

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
  v_margin record;
  v_fees record;
  v_x double precision;
  v_y double precision;
  v_z double precision;
  v_f double precision;
  v_denom double precision;
  v_raw double precision;
  v_total double precision;
BEGIN
  IF p_nominal_amount IS NULL OR p_nominal_amount < 0 THEN
    RAISE EXCEPTION 'Montant nominal invalide';
  END IF;
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id requis';
  END IF;

  SELECT c."countryId" INTO v_country_id
  FROM "Companies" c
  WHERE c.id = p_company_id;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  SELECT * INTO v_margin
  FROM public.resolve_seller_commission_setting(p_company_id)
  LIMIT 1;

  v_x := COALESCE(p_trip_margin_percent, v_margin.rate, 0);

  SELECT * INTO v_fees
  FROM public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method)
  LIMIT 1;

  IF v_fees IS NULL THEN
    RAISE EXCEPTION 'Configuration frais gateway manquante pour gateway=% pays=% methode=%', p_gateway, v_country_id, p_method;
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
    'method', lower(p_method),
    'countryId', v_country_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.calculate_traveler_payment_total(double precision, uuid, text, text, double precision) TO anon, authenticated;
