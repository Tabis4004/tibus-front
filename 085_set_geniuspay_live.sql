-- =============================================================================
-- Tibus — Passerelle de paiement live : GeniusPay (remplace FedaPay par défaut)
-- Exécuter dans Supabase SQL Editor après 055 et 057.
-- =============================================================================

UPDATE "PlatformPaymentGateway"
SET
  "gateway" = 'geniuspay',
  "updatedAt" = now()
WHERE "id" = 1;

INSERT INTO "PlatformPaymentGateway" ("id", "gateway")
VALUES (1, 'geniuspay')
ON CONFLICT ("id") DO UPDATE
SET
  "gateway" = 'geniuspay',
  "updatedAt" = now();

ALTER TABLE "PlatformPaymentGateway"
  ALTER COLUMN "gateway" SET DEFAULT 'geniuspay';

CREATE OR REPLACE FUNCTION public.get_active_payment_gateway()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'gateway', COALESCE(
      (SELECT lower(g.gateway) FROM "PlatformPaymentGateway" g WHERE g.id = 1),
      'geniuspay'
    ),
    'updatedAt', (SELECT g."updatedAt" FROM "PlatformPaymentGateway" g WHERE g.id = 1)
  );
$$;

SELECT public.get_active_payment_gateway() AS active_gateway;
