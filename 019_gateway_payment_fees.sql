-- Lot 19: frais gateway / GeniusPay pour le calcul voyageur T = (M(1+X)+F)/(1-Z-Y)
-- Suit le meme modele que CommissionSettings (super_admin + admin_pays).

CREATE TABLE IF NOT EXISTS "GatewayPaymentFees" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "gateway" text NOT NULL,
  "countryId" uuid NOT NULL,
  "method" text NOT NULL,
  "yPercent" double precision NOT NULL DEFAULT 0,
  "zPercent" double precision NOT NULL DEFAULT 0,
  "fFixed" double precision NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid,
  CONSTRAINT "GatewayPaymentFees_y_check" CHECK ("yPercent" >= 0 AND "yPercent" < 100),
  CONSTRAINT "GatewayPaymentFees_z_check" CHECK ("zPercent" >= 0 AND "zPercent" < 100),
  CONSTRAINT "GatewayPaymentFees_f_check" CHECK ("fFixed" >= 0),
  CONSTRAINT "GatewayPaymentFees_combo_check"
    CHECK ("yPercent" + "zPercent" < 100)
);

ALTER TABLE "GatewayPaymentFees"
  DROP CONSTRAINT IF EXISTS "GatewayPaymentFees_countryId_fkey";
ALTER TABLE "GatewayPaymentFees"
  ADD CONSTRAINT "GatewayPaymentFees_countryId_fkey"
  FOREIGN KEY ("countryId") REFERENCES "Countries" ("id")
  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "GatewayPaymentFees"
  DROP CONSTRAINT IF EXISTS "GatewayPaymentFees_updatedBy_fkey";
ALTER TABLE "GatewayPaymentFees"
  ADD CONSTRAINT "GatewayPaymentFees_updatedBy_fkey"
  FOREIGN KEY ("updatedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

CREATE UNIQUE INDEX IF NOT EXISTS "GatewayPaymentFees_active_combo_key"
  ON "GatewayPaymentFees" ("gateway", "countryId", "method")
  WHERE "isActive" = true;

CREATE INDEX IF NOT EXISTS "GatewayPaymentFees_country_idx"
  ON "GatewayPaymentFees" ("countryId", "gateway", "method", "isActive");

ALTER TABLE "GatewayPaymentFees" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "gateway_payment_fees_select" ON "GatewayPaymentFees";
CREATE POLICY "gateway_payment_fees_select" ON "GatewayPaymentFees"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_country_role("countryId", ARRAY['admin_pays'])
  );

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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
    AND lower(gpf.gateway) = lower(p_gateway)
    AND gpf."countryId" = p_country_id
    AND lower(gpf.method) = lower(p_method)
  ORDER BY gpf."updatedAt" DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.list_gateway_payment_fees()
RETURNS TABLE(
  id uuid,
  gateway text,
  country_id uuid,
  country_name text,
  method text,
  y_percent double precision,
  z_percent double precision,
  f_fixed double precision,
  is_active boolean,
  updated_at timestamptz,
  updated_by_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    gpf.id,
    gpf.gateway,
    gpf."countryId" AS country_id,
    c.name::text AS country_name,
    gpf.method,
    gpf."yPercent" AS y_percent,
    gpf."zPercent" AS z_percent,
    gpf."fFixed" AS f_fixed,
    gpf."isActive" AS is_active,
    gpf."updatedAt" AS updated_at,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '') AS updated_by_name
  FROM "GatewayPaymentFees" gpf
  JOIN "Countries" c ON c.id = gpf."countryId"
  LEFT JOIN "Users" u ON u.id = gpf."updatedBy"
  WHERE public.is_super_admin()
    OR public.has_country_role(gpf."countryId", ARRAY['admin_pays'])
  ORDER BY c.name, gpf.gateway, gpf.method;
$$;

CREATE OR REPLACE FUNCTION public.upsert_gateway_payment_fee(
  p_gateway text,
  p_country_id uuid,
  p_method text,
  p_y_percent double precision,
  p_z_percent double precision,
  p_f_fixed double precision DEFAULT 0,
  p_is_active boolean DEFAULT true
)
RETURNS TABLE(
  id uuid,
  gateway text,
  country_id uuid,
  country_name text,
  method text,
  y_percent double precision,
  z_percent double precision,
  f_fixed double precision,
  is_active boolean,
  updated_at timestamptz,
  updated_by_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_existing_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  IF p_gateway IS NULL OR trim(p_gateway) = '' THEN
    RAISE EXCEPTION 'gateway requis';
  END IF;
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'country_id requis';
  END IF;
  IF p_method IS NULL OR trim(p_method) = '' THEN
    RAISE EXCEPTION 'method requise';
  END IF;
  IF p_y_percent < 0 OR p_y_percent >= 100 OR p_z_percent < 0 OR p_z_percent >= 100 THEN
    RAISE EXCEPTION 'Y et Z doivent etre entre 0 et 100';
  END IF;
  IF p_y_percent + p_z_percent >= 100 THEN
    RAISE EXCEPTION 'Y + Z doit etre < 100';
  END IF;
  IF COALESCE(p_f_fixed, 0) < 0 THEN
    RAISE EXCEPTION 'F doit etre >= 0';
  END IF;
  IF NOT public.can_manage_commission_country(p_country_id) THEN
    RAISE EXCEPTION 'Acces frais gateway refuse';
  END IF;

  SELECT gpf.id INTO v_existing_id
  FROM "GatewayPaymentFees" gpf
  WHERE lower(gpf.gateway) = lower(p_gateway)
    AND gpf."countryId" = p_country_id
    AND lower(gpf.method) = lower(p_method)
  ORDER BY gpf."isActive" DESC, gpf."updatedAt" DESC
  LIMIT 1;

  IF v_existing_id IS NULL THEN
    INSERT INTO "GatewayPaymentFees" (
      "gateway", "countryId", "method", "yPercent", "zPercent", "fFixed", "isActive", "updatedBy"
    )
    VALUES (
      lower(trim(p_gateway)),
      p_country_id,
      lower(trim(p_method)),
      p_y_percent,
      p_z_percent,
      COALESCE(p_f_fixed, 0),
      COALESCE(p_is_active, true),
      v_user_id
    )
    RETURNING "GatewayPaymentFees".id INTO v_existing_id;
  ELSE
    UPDATE "GatewayPaymentFees"
    SET
      "gateway" = lower(trim(p_gateway)),
      "method" = lower(trim(p_method)),
      "yPercent" = p_y_percent,
      "zPercent" = p_z_percent,
      "fFixed" = COALESCE(p_f_fixed, 0),
      "isActive" = COALESCE(p_is_active, true),
      "updatedBy" = v_user_id,
      "updatedAt" = now()
    WHERE id = v_existing_id;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.list_gateway_payment_fees() l
  WHERE l.id = v_existing_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_gateway_payment_fee(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
BEGIN
  SELECT gpf."countryId" INTO v_country_id
  FROM "GatewayPaymentFees" gpf
  WHERE gpf.id = p_fee_id;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Configuration introuvable';
  END IF;
  IF NOT public.can_manage_commission_country(v_country_id) THEN
    RAISE EXCEPTION 'Acces frais gateway refuse';
  END IF;

  DELETE FROM "GatewayPaymentFees" WHERE id = p_fee_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_gateway_payment_fee(text, uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_gateway_payment_fees() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_gateway_payment_fee(text, uuid, text, double precision, double precision, double precision, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_gateway_payment_fee(uuid) TO authenticated;
