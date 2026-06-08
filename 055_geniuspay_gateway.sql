-- Lot 55: GeniusPay + sélection gateway active (super_admin)

CREATE TABLE IF NOT EXISTS "PlatformPaymentGateway" (
  "id" smallint PRIMARY KEY DEFAULT 1 CHECK ("id" = 1),
  "gateway" text NOT NULL DEFAULT 'fedapay'
    CHECK (lower("gateway") IN ('fedapay', 'geniuspay')),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users"(id)
);

INSERT INTO "PlatformPaymentGateway" ("id", "gateway")
VALUES (1, 'fedapay')
ON CONFLICT ("id") DO NOTHING;

ALTER TABLE "PlatformPaymentGateway" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform_payment_gateway_select" ON "PlatformPaymentGateway";
CREATE POLICY "platform_payment_gateway_select" ON "PlatformPaymentGateway"
  FOR SELECT TO authenticated, anon
  USING (true);

DROP POLICY IF EXISTS "platform_payment_gateway_write" ON "PlatformPaymentGateway";
CREATE POLICY "platform_payment_gateway_write" ON "PlatformPaymentGateway"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

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
      'fedapay'
    ),
    'updatedAt', (SELECT g."updatedAt" FROM "PlatformPaymentGateway" g WHERE g.id = 1)
  );
$$;

CREATE OR REPLACE FUNCTION public.set_active_payment_gateway(p_gateway text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gateway text := lower(trim(p_gateway));
  v_user uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Accès réservé au super_admin';
  END IF;

  IF v_gateway NOT IN ('fedapay', 'geniuspay') THEN
    RAISE EXCEPTION 'Gateway invalide: %', p_gateway;
  END IF;

  v_user := public.current_app_user_id();

  INSERT INTO "PlatformPaymentGateway" ("id", "gateway", "updatedAt", "updatedBy")
  VALUES (1, v_gateway, now(), v_user)
  ON CONFLICT ("id") DO UPDATE
  SET
    "gateway" = EXCLUDED."gateway",
    "updatedAt" = now(),
    "updatedBy" = EXCLUDED."updatedBy";

  RETURN public.get_active_payment_gateway();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_active_payment_gateway() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_active_payment_gateway(text) TO authenticated, service_role;
