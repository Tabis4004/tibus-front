-- Orange Money CI via Paystack = 5% (aligné dashboard GeniusPay).

UPDATE "GatewayPaymentFees"
SET "yPercent" = 5
WHERE gateway = 'geniuspay'
  AND method = 'mobile_money'
  AND network = 'orange'
  AND "countryId" = '3df7050d-5285-40b5-b552-75bc84d4216b'
  AND "isActive" = true;
