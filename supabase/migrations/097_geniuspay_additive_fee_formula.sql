-- 097_geniuspay_additive_fee_formula.sql
-- GeniusPay : MT = M × (1 + X% + Y%) + F
-- Le réseau MMO est choisi sur le checkout GeniusPay ; Y vient de la ligne "default".

CREATE OR REPLACE FUNCTION public.calculate_traveler_payment_total(
  p_nominal_amount double precision,
  p_company_id uuid,
  p_gateway text DEFAULT 'fedapay',
  p_method text DEFAULT 'mobile_money',
  p_network text DEFAULT NULL,
  p_trip_margin_percent double precision DEFAULT NULL,
  p_country_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  v_v double precision;
  v_raw double precision;
  v_total double precision;
  v_configured text;
  v_fee_mode text;
  v_is_geniuspay boolean;
BEGIN
  IF p_nominal_amount IS NULL OR p_nominal_amount < 0 THEN RAISE EXCEPTION 'Montant nominal invalide'; END IF;
  IF p_company_id IS NULL THEN RAISE EXCEPTION 'company_id requis'; END IF;

  v_is_geniuspay := lower(trim(COALESCE(p_gateway, ''))) = 'geniuspay';

  IF p_country_id IS NOT NULL THEN
    v_country_id := p_country_id;
    SELECT co.name INTO v_country_name FROM "Countries" co WHERE co.id = v_country_id;
    IF v_country_name IS NULL THEN
      RAISE EXCEPTION 'Pays de paiement introuvable (countryId=%)', p_country_id;
    END IF;
  ELSE
    SELECT c."countryId", c.name INTO v_country_id, v_company_name FROM "Companies" c WHERE c.id = p_company_id;
    IF v_country_id IS NULL THEN
      RAISE EXCEPTION 'Compagnie sans pays (countryId NULL) pour %', COALESCE(v_company_name, p_company_id::text);
    END IF;
    SELECT co.name INTO v_country_name FROM "Countries" co WHERE co.id = v_country_id;
  END IF;

  SELECT * INTO v_margin FROM public.resolve_seller_commission_setting(p_company_id) LIMIT 1;
  v_x := COALESCE(p_trip_margin_percent, v_margin.rate, 0);

  IF v_is_geniuspay THEN
    SELECT * INTO v_fees
    FROM public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method, 'default')
    LIMIT 1;
    IF NOT FOUND THEN
      SELECT * INTO v_fees
      FROM public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method, NULL)
      LIMIT 1;
    END IF;
  ELSE
    SELECT * INTO v_fees
    FROM public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method, p_network)
    LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    SELECT string_agg(lower(gpf.gateway)||'/'||lower(gpf.method)||'/'||lower(gpf.network), ', ')
    INTO v_configured FROM "GatewayPaymentFees" gpf WHERE gpf."countryId" = v_country_id;
    RAISE EXCEPTION 'Configuration frais gateway manquante pour gateway=% pays=% methode=% reseau=%. Config: %',
      lower(p_gateway), COALESCE(v_country_name,'?'), lower(p_method), lower(COALESCE(p_network,'max')), COALESCE(v_configured,'aucune');
  END IF;

  v_z := COALESCE(v_fees.z_percent, 0);
  v_f := COALESCE(v_fees.f_fixed, 0);
  v_y := COALESCE(v_fees.y_percent, 0);
  v_v := p_nominal_amount * (1 + v_x / 100.0);

  v_fee_mode := CASE
    WHEN lower(trim(p_gateway)) IN ('fedapay', 'geniuspay') THEN 'on_top'
    ELSE 'deducted'
  END;

  IF v_is_geniuspay THEN
    v_raw := p_nominal_amount * (1 + (v_x + v_y) / 100.0) + v_f;
  ELSIF v_fee_mode = 'on_top' THEN
    v_raw := v_v * (1 + (v_y + v_z) / 100.0) + v_f;
  ELSE
    IF (v_y + v_z) >= 100 THEN RAISE EXCEPTION 'Taux gateway invalides: Y+Z >= 100%%'; END IF;
    v_raw := (v_v + v_f) / (1 - (v_y + v_z) / 100.0);
  END IF;

  v_total := CEIL(v_raw);

  RETURN jsonb_build_object(
    'nominalAmount', p_nominal_amount,
    'platformMarginPercent', v_x,
    'platformNetAmount', v_v,
    'gatewayFeePercent', v_y,
    'geniusPayFeePercent', v_z,
    'fixedFee', v_f,
    'rawTotalAmount', v_raw,
    'totalAmount', v_total,
    'gatewayAmount', CASE
      WHEN v_is_geniuspay THEN v_total
      WHEN v_fee_mode = 'on_top' THEN CEIL(v_v)
      ELSE v_total
    END,
    'feeMode', v_fee_mode,
    'paidBy', COALESCE(v_margin.paid_by, 'company'),
    'marginScope', COALESCE(v_margin.setting_scope, 'unset'),
    'gateway', lower(p_gateway),
    'method', lower(v_fees.method),
    'network', CASE WHEN v_is_geniuspay THEN 'geniuspay' ELSE lower(v_fees.network) END,
    'requestedNetwork', lower(COALESCE(NULLIF(trim(p_network), ''), 'unknown')),
    'usedMaxFallback', CASE WHEN v_is_geniuspay THEN false ELSE COALESCE(v_fees.used_max_fallback, false) END,
    'countryId', v_country_id,
    'countryName', v_country_name
  );
END;
$function$;
