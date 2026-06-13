-- Lot 090: réseaux mobile money voyageur par pays (lecture publique)
-- PRÉREQUIS: GatewayPaymentFees (019/022), geniuspay actif

CREATE OR REPLACE FUNCTION public.list_traveler_payment_networks(
  p_country_id uuid,
  p_gateway text DEFAULT 'geniuspay',
  p_method text DEFAULT 'mobile_money'
)
RETURNS TABLE (network text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT lower(g."network") AS network
  FROM "GatewayPaymentFees" g
  WHERE g."countryId" = p_country_id
    AND g."isActive" = true
    AND lower(g.gateway) = lower(coalesce(p_gateway, 'geniuspay'))
    AND lower(g.method) = lower(coalesce(p_method, 'mobile_money'))
    AND lower(g."network") <> 'default'
  ORDER BY network;
$$;

REVOKE ALL ON FUNCTION public.list_traveler_payment_networks(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_traveler_payment_networks(uuid, text, text) TO anon, authenticated;
