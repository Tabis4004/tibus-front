-- Diagnostic rapide : pourquoi les frais gateway ne matchent pas ?
-- Collez dans Supabase SQL Editor et exécutez.

SELECT
  c.name AS company_name,
  c.id AS company_id,
  c."countryId" AS company_country_id,
  co.name AS company_country_name
FROM "Companies" c
LEFT JOIN "Countries" co ON co.id = c."countryId"
ORDER BY c.name;

SELECT
  co.name AS country_name,
  co.id AS country_id,
  gpf.gateway,
  gpf.method,
  gpf."yPercent",
  gpf."zPercent",
  gpf."fFixed",
  gpf."isActive"
FROM "GatewayPaymentFees" gpf
JOIN "Countries" co ON co.id = gpf."countryId"
ORDER BY co.name, gpf.gateway, gpf.method;

SELECT
  c.name AS company_name,
  co.name AS country_name,
  f.*
FROM "Companies" c
JOIN "Countries" co ON co.id = c."countryId"
LEFT JOIN LATERAL public.resolve_gateway_payment_fee('fedapay', c."countryId", 'mobile_money') f ON true
ORDER BY c.name;
