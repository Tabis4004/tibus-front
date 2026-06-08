-- Tibus — Admin abonnements compagnie (plans, durées, attribution)

ALTER TABLE "SubscriptionPlanDurations"
  DROP CONSTRAINT IF EXISTS "SubscriptionPlanDurations_price_check";

ALTER TABLE "SubscriptionPlanDurations"
  ADD CONSTRAINT "SubscriptionPlanDurations_price_check"
  CHECK (price >= 0);

ALTER TABLE "Subscriptions"
  ALTER COLUMN "paymentId" DROP NOT NULL;

ALTER TABLE "SubscriptionPlans"
  ADD COLUMN IF NOT EXISTS "isDefault" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.admin_create_subscription_plan(
  p_name text,
  p_country_id uuid,
  p_features text[] DEFAULT '{}',
  p_is_default boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF p_is_default THEN
    UPDATE "SubscriptionPlans"
    SET "isDefault" = false
    WHERE "countryId" = p_country_id;
  END IF;

  INSERT INTO "SubscriptionPlans" ("name", "countryId", "features", "isDefault")
  VALUES (trim(p_name), p_country_id, COALESCE(p_features, '{}'), COALESCE(p_is_default, false))
  RETURNING id INTO v_plan_id;

  RETURN v_plan_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_subscription_plan(
  p_plan_id uuid,
  p_name text DEFAULT NULL,
  p_features text[] DEFAULT NULL,
  p_is_default boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT "countryId" INTO v_country_id
  FROM "SubscriptionPlans"
  WHERE id = p_plan_id;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Plan introuvable';
  END IF;

  IF COALESCE(p_is_default, false) THEN
    UPDATE "SubscriptionPlans"
    SET "isDefault" = false
    WHERE "countryId" = v_country_id AND id <> p_plan_id;
  END IF;

  UPDATE "SubscriptionPlans"
  SET
    "name" = COALESCE(NULLIF(trim(p_name), ''), "name"),
    "features" = COALESCE(p_features, "features"),
    "isDefault" = COALESCE(p_is_default, "isDefault")
  WHERE id = p_plan_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_subscription_plan(p_plan_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  DELETE FROM "SubscriptionPlanDurations" WHERE "planId" = p_plan_id;
  DELETE FROM "SubscriptionPlans" WHERE id = p_plan_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_plan_duration(
  p_plan_id uuid,
  p_price double precision,
  p_duration integer,
  p_duration_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF p_duration IS NULL OR p_duration < 1 THEN
    RAISE EXCEPTION 'Duree invalide';
  END IF;

  IF p_duration_id IS NOT NULL THEN
    UPDATE "SubscriptionPlanDurations"
    SET price = p_price, duration = p_duration
    WHERE id = p_duration_id AND "planId" = p_plan_id
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Duree introuvable';
    END IF;
    RETURN v_id;
  END IF;

  INSERT INTO "SubscriptionPlanDurations" ("planId", price, duration)
  VALUES (p_plan_id, p_price, p_duration)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_plan_duration(p_duration_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  DELETE FROM "SubscriptionPlanDurations" WHERE id = p_duration_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_assign_company_subscription(
  p_company_id uuid,
  p_duration_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_assigner_id uuid;
  v_plan_id uuid;
  v_duration integer;
  v_country_id uuid;
  v_plan_country_id uuid;
  v_subscription_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_assigner_id := public.current_app_user_id();
  IF v_assigner_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  SELECT c."countryId" INTO v_country_id
  FROM "Companies" c
  WHERE c.id = p_company_id;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  SELECT d."planId", d.duration, p."countryId"
  INTO v_plan_id, v_duration, v_plan_country_id
  FROM "SubscriptionPlanDurations" d
  JOIN "SubscriptionPlans" p ON p.id = d."planId"
  WHERE d.id = p_duration_id;

  IF v_plan_id IS NULL THEN
    RAISE EXCEPTION 'Duree de plan introuvable';
  END IF;

  IF v_plan_country_id <> v_country_id THEN
    RAISE EXCEPTION 'Le plan ne correspond pas au pays de la compagnie';
  END IF;

  INSERT INTO "Subscriptions" (
    "planId", "companyId", "durationId", "endDate", "createdBy", "paymentId"
  ) VALUES (
    v_plan_id,
    p_company_id,
    p_duration_id,
    now() + (v_duration || ' days')::interval,
    v_assigner_id,
    NULL
  )
  RETURNING id INTO v_subscription_id;

  RETURN v_subscription_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_subscription_plan(text, uuid, text[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_subscription_plan(uuid, text, text[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_subscription_plan(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_plan_duration(uuid, double precision, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_plan_duration(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_assign_company_subscription(uuid, uuid) TO authenticated;
