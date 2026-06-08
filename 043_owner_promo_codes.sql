-- Lot 43: Codes promo owner (CRUD Supabase) + incrément usage à l'émission.

CREATE OR REPLACE FUNCTION public._owner_company_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT ur."companyId"
  INTO v_company_id
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = public.current_app_user_id()
    AND r.name = 'owner'
    AND ur."companyId" IS NOT NULL
  LIMIT 1;
  RETURN v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_owner_promo_codes()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := public._owner_company_id();
  v_rows jsonb;
BEGIN
  IF v_company_id IS NULL AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Compagnie propriétaire introuvable';
  END IF;
  IF v_company_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pc.id,
        'code', pc.code,
        'discountType', pc."discountType",
        'discountValue', pc."discountValue",
        'currency', pc.currency,
        'validFrom', pc."validFrom",
        'validUntil', pc."validUntil",
        'maxUsage', pc."maxUsage",
        'usageCount', pc."usageCount",
        'trajetId', pc."trajetId",
        'isActive', pc."isActive",
        'routeLabel', CASE
          WHEN pc."trajetId" IS NULL THEN NULL
          ELSE CONCAT(COALESCE(g_from.name, '?'), ' → ', COALESCE(g_to.name, '?'))
        END
      )
      ORDER BY pc."validUntil" DESC, pc.code
    ),
    '[]'::jsonb
  )
  INTO v_rows
  FROM "PromoCodes" pc
  LEFT JOIN "ProgrammationTrajets" t ON t.id = pc."trajetId"
  LEFT JOIN "Gares" g_from ON g_from.id = t.depart
  LEFT JOIN "Gares" g_to ON g_to.id = t.final
  WHERE pc."companyId" = v_company_id;

  RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_owner_promo_code(
  p_code text,
  p_discount_type text,
  p_discount_value double precision,
  p_valid_from timestamptz,
  p_valid_until timestamptz,
  p_currency text DEFAULT NULL,
  p_max_usage integer DEFAULT NULL,
  p_trajet_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := public._owner_company_id();
  v_code text := upper(trim(COALESCE(p_code, '')));
  v_type text := lower(trim(COALESCE(p_discount_type, '')));
  v_id uuid;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie propriétaire introuvable';
  END IF;
  IF char_length(v_code) < 3 THEN
    RAISE EXCEPTION 'Le code doit contenir au moins 3 caractères';
  END IF;
  IF v_type NOT IN ('percentage', 'fixed') THEN
    RAISE EXCEPTION 'Type de réduction invalide';
  END IF;
  IF p_discount_value IS NULL OR p_discount_value <= 0 THEN
    RAISE EXCEPTION 'Valeur de réduction invalide';
  END IF;
  IF v_type = 'percentage' AND p_discount_value > 100 THEN
    RAISE EXCEPTION 'Le pourcentage ne peut pas dépasser 100';
  END IF;
  IF p_valid_from IS NULL OR p_valid_until IS NULL OR p_valid_until < p_valid_from THEN
    RAISE EXCEPTION 'Période de validité invalide';
  END IF;
  IF p_max_usage IS NOT NULL AND p_max_usage <= 0 THEN
    RAISE EXCEPTION 'Limite d''usage invalide';
  END IF;
  IF p_trajet_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM "ProgrammationTrajets" t
    JOIN "Gares" g ON g.id = t.depart
    WHERE t.id = p_trajet_id AND g."companyId" = v_company_id
  ) THEN
    RAISE EXCEPTION 'Trajet invalide pour cette compagnie';
  END IF;
  IF EXISTS (
    SELECT 1 FROM "PromoCodes"
    WHERE "companyId" = v_company_id AND code = v_code
  ) THEN
    RAISE EXCEPTION 'Ce code promo existe déjà';
  END IF;

  INSERT INTO "PromoCodes" (
    "companyId", code, "discountType", "discountValue", currency,
    "validFrom", "validUntil", "maxUsage", "usageCount", "trajetId", "isActive"
  )
  VALUES (
    v_company_id, v_code, v_type::"DiscountType", p_discount_value, NULLIF(trim(p_currency), ''),
    p_valid_from, p_valid_until, p_max_usage, 0, p_trajet_id, true
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_owner_promo_code(
  p_promo_id uuid,
  p_is_active boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := public._owner_company_id();
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie propriétaire introuvable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "PromoCodes"
    WHERE id = p_promo_id AND "companyId" = v_company_id
  ) THEN
    RAISE EXCEPTION 'Code promo introuvable';
  END IF;
  IF p_is_active IS NULL THEN
    RAISE EXCEPTION 'Aucune modification demandée';
  END IF;

  UPDATE "PromoCodes"
  SET "isActive" = p_is_active
  WHERE id = p_promo_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_owner_promo_code(p_promo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := public._owner_company_id();
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie propriétaire introuvable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "PromoCodes"
    WHERE id = p_promo_id AND "companyId" = v_company_id
  ) THEN
    RAISE EXCEPTION 'Code promo introuvable';
  END IF;

  DELETE FROM "PromoCodes" WHERE id = p_promo_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_promo_usage(p_promo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE "PromoCodes"
  SET "usageCount" = "usageCount" + 1
  WHERE id = p_promo_id
    AND "isActive" = true
    AND ( "maxUsage" IS NULL OR "usageCount" < "maxUsage" );
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Code promo invalide ou limite atteinte';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_owner_promo_codes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_owner_promo_code(text, text, double precision, timestamptz, timestamptz, text, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_owner_promo_code(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_owner_promo_code(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_promo_usage(uuid) TO service_role;
