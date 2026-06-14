-- 114 — Pools par rôle (vendeur/master/admin pays sans bénéficiaire fixe) ; seul le recruteur est nominatif

CREATE OR REPLACE FUNCTION public.upsert_stakeholder_commission_setting(
  p_scope text,
  p_country_id uuid DEFAULT NULL::uuid,
  p_stakeholder_role text DEFAULT 'platform'::text,
  p_rate double precision DEFAULT 0,
  p_base_type text DEFAULT 'platform_commission'::text,
  p_is_active boolean DEFAULT true,
  p_company_id uuid DEFAULT NULL::uuid,
  p_label text DEFAULT NULL::text,
  p_beneficiary_user_id uuid DEFAULT NULL::uuid,
  p_setting_id uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_user_id uuid;
  v_active boolean;
  v_beneficiary uuid;
  v_company_country uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    IF p_scope <> 'country' AND NOT (
      p_scope = 'company'
      AND p_country_id IS NOT NULL
      AND public.has_country_role(p_country_id, ARRAY['admin_pays'])
    ) THEN
      RAISE EXCEPTION 'Droits insuffisants';
    END IF;
    IF p_scope = 'country'
      AND (p_country_id IS NULL OR NOT public.has_country_role(p_country_id, ARRAY['admin_pays']))
    THEN
      RAISE EXCEPTION 'Droits insuffisants';
    END IF;
  END IF;

  IF p_scope NOT IN ('global', 'country', 'company') THEN
    RAISE EXCEPTION 'Scope invalide';
  END IF;
  IF COALESCE(p_rate, 0) < 0 THEN
    RAISE EXCEPTION 'Le taux doit etre superieur ou egal a 0';
  END IF;
  IF p_scope = 'country' AND p_country_id IS NULL THEN
    RAISE EXCEPTION 'countryId requis';
  END IF;
  IF p_scope = 'company' AND (p_company_id IS NULL OR p_country_id IS NULL) THEN
    RAISE EXCEPTION 'companyId et countryId requis';
  END IF;

  IF p_scope = 'company' AND p_stakeholder_role = 'recruiter' THEN
    SELECT c."countryId", c."recruitedByUserId"
    INTO v_company_country, v_beneficiary
    FROM "Companies" c
    WHERE c.id = p_company_id;

    IF v_company_country IS NULL THEN
      RAISE EXCEPTION 'Compagnie introuvable';
    END IF;
    IF v_company_country IS DISTINCT FROM p_country_id THEN
      RAISE EXCEPTION 'La compagnie n''appartient pas au pays selectionne';
    END IF;

    v_beneficiary := COALESCE(p_beneficiary_user_id, v_beneficiary);
  ELSE
    v_beneficiary := CASE
      WHEN p_stakeholder_role IN ('platform', 'admin_pays', 'master', 'seller') THEN NULL
      ELSE p_beneficiary_user_id
    END;
  END IF;

  IF p_stakeholder_role = 'custom' AND COALESCE(p_rate, 0) > 0
    AND (p_label IS NULL OR v_beneficiary IS NULL) THEN
    RAISE EXCEPTION 'Label et beneficiaire requis pour un stakeholder custom actif';
  END IF;

  IF p_stakeholder_role = 'recruiter'
    AND p_scope = 'company'
    AND COALESCE(p_rate, 0) > 0
    AND v_beneficiary IS NULL
  THEN
    RAISE EXCEPTION 'Recruteur beneficiaire requis pour cette compagnie';
  END IF;

  v_user_id := public.current_app_user_id();

  IF COALESCE(p_rate, 0) <= 0 AND p_stakeholder_role <> 'custom' THEN
    DELETE FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = p_scope
      AND s."stakeholderRole" = p_stakeholder_role
      AND (p_scope = 'global' OR s."countryId" IS NOT DISTINCT FROM p_country_id)
      AND (p_scope <> 'company' OR s."companyId" IS NOT DISTINCT FROM p_company_id);
    RETURN NULL;
  END IF;

  v_active := COALESCE(p_is_active, true) AND COALESCE(p_rate, 0) > 0;

  IF p_setting_id IS NULL THEN
    SELECT s.id
    INTO v_id
    FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = p_scope
      AND s."stakeholderRole" = p_stakeholder_role
      AND (p_scope = 'global' OR s."countryId" IS NOT DISTINCT FROM p_country_id)
      AND (p_scope <> 'company' OR s."companyId" IS NOT DISTINCT FROM p_company_id)
      AND (
        p_stakeholder_role <> 'custom'
        OR (
          COALESCE(s.label, '') = COALESCE(NULLIF(trim(p_label), ''), '')
          AND s."beneficiaryUserId" IS NOT DISTINCT FROM v_beneficiary
        )
      )
    ORDER BY s."isActive" DESC, s."updatedAt" DESC NULLS LAST
    LIMIT 1;
  ELSE
    v_id := p_setting_id;
  END IF;

  IF v_id IS NOT NULL THEN
    UPDATE "StakeholderCommissionSettings"
    SET
      "scope" = p_scope,
      "countryId" = CASE WHEN p_scope IN ('country', 'company') THEN p_country_id ELSE NULL END,
      "companyId" = CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
      "stakeholderRole" = p_stakeholder_role,
      "label" = NULLIF(trim(p_label), ''),
      "beneficiaryUserId" = v_beneficiary,
      rate = COALESCE(p_rate, 0),
      "baseType" = COALESCE(p_base_type, 'platform_commission'),
      "isActive" = v_active,
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    WHERE id = v_id
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;

  INSERT INTO "StakeholderCommissionSettings" (
    "scope", "countryId", "companyId", "stakeholderRole", "label", "beneficiaryUserId",
    rate, "baseType", "isActive", "updatedBy"
  )
  VALUES (
    p_scope,
    CASE WHEN p_scope IN ('country', 'company') THEN p_country_id ELSE NULL END,
    CASE WHEN p_scope = 'company' THEN p_company_id ELSE NULL END,
    p_stakeholder_role,
    NULLIF(trim(p_label), ''),
    v_beneficiary,
    COALESCE(p_rate, 0),
    COALESCE(p_base_type, 'platform_commission'),
    v_active,
    v_user_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION
  WHEN unique_violation THEN
    SELECT s.id
    INTO v_id
    FROM "StakeholderCommissionSettings" s
    WHERE s."scope" = p_scope
      AND s."stakeholderRole" = p_stakeholder_role
      AND (p_scope = 'global' OR s."countryId" IS NOT DISTINCT FROM p_country_id)
      AND (p_scope <> 'company' OR s."companyId" IS NOT DISTINCT FROM p_company_id)
    ORDER BY s."updatedAt" DESC NULLS LAST
    LIMIT 1;

    IF v_id IS NULL THEN
      RAISE;
    END IF;

    UPDATE "StakeholderCommissionSettings"
    SET
      rate = COALESCE(p_rate, 0),
      "baseType" = COALESCE(p_base_type, 'platform_commission'),
      "isActive" = v_active,
      "label" = NULLIF(trim(p_label), ''),
      "beneficiaryUserId" = v_beneficiary,
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    WHERE id = v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._stakeholder_commission_earned_rows(p_country_id uuid)
RETURNS TABLE(
  country_id uuid,
  company_id uuid,
  company_name text,
  stakeholder_role text,
  stakeholder_label text,
  beneficiary_user_id uuid,
  beneficiary_name text,
  rate double precision,
  base_type text,
  earned_amount double precision,
  ticket_count bigint,
  currency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_country_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH paid_bookings AS (
    SELECT
      rb.id AS booking_id,
      rb.price AS nominal_amount,
      COALESCE(rb."platformCommissionAmount", 0) AS stored_commission,
      rb."createdBy" AS seller_user_id,
      COALESCE(rb."saleChannel", 'traveler')::text AS sale_channel,
      c.id AS company_id,
      c.name::text AS company_name,
      c."countryId" AS country_id,
      c."recruitedByUserId" AS recruiter_user_id,
      COALESCE(country.currency, 'XOF')::text AS currency,
      owner_ur."userId" AS owner_user_id,
      mvn."masterUserId" AS master_user_id
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
    LEFT JOIN LATERAL (
      SELECT ur."userId"
      FROM "UserRoles" ur
      JOIN "Role" owner_role ON owner_role.id = ur."roleId" AND owner_role.name = 'owner'
      WHERE ur."companyId" = c.id
      LIMIT 1
    ) owner_ur ON true
    LEFT JOIN "MasterVendorNetwork" mvn
      ON mvn."vendorUserId" = rb."createdBy" AND mvn."isActive" = true
    WHERE rb."type" = 'voyage'
      AND c."countryId" = p_country_id
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."platformCommissionSource", 'traveler_online') IN ('traveler_online', 'counter_company')
  ),
  booking_commissions AS (
    SELECT
      pb.*,
      CASE
        WHEN pb.stored_commission > 0 THEN pb.stored_commission
        ELSE public._booking_platform_commission_amount(pb.nominal_amount, pb.company_id, pb.sale_channel, NULL)
      END AS platform_commission_amount
    FROM paid_bookings pb
  ),
  admin_users AS (
    SELECT ur."userId" AS user_id
    FROM "UserRoles" ur
    JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ro.name = 'admin_pays' AND ur."countryId" = p_country_id
  ),
  admin_count AS (
    SELECT GREATEST(COUNT(*)::double precision, 1) AS cnt FROM admin_users
  ),
  booking_settings AS (
    SELECT
      bc.*,
      s.setting_id,
      s.stakeholder_role,
      s.label,
      s.beneficiary_user_id AS setting_beneficiary_user_id,
      s.rate,
      s.base_type
    FROM booking_commissions bc
    CROSS JOIN LATERAL public._stakeholder_settings_for_booking(bc.country_id, bc.company_id) s
    WHERE bc.platform_commission_amount > 0
  ),
  role_slices AS (
    SELECT
      bs.country_id,
      bs.company_id,
      bs.company_name,
      bs.stakeholder_role,
      COALESCE(bs.label, bs.stakeholder_role)::text AS stakeholder_label,
      bs.rate,
      bs.base_type,
      bs.currency,
      bs.platform_commission_amount,
      bs.booking_id,
      CASE bs.stakeholder_role
        WHEN 'platform' THEN NULL::uuid
        WHEN 'admin_pays' THEN au.user_id
        WHEN 'recruiter' THEN
          CASE
            WHEN bs.setting_beneficiary_user_id IS NOT NULL THEN bs.setting_beneficiary_user_id
            WHEN bs.recruiter_user_id IS NULL THEN NULL
            WHEN EXISTS (
              SELECT 1 FROM admin_users ad WHERE ad.user_id = bs.recruiter_user_id
            ) THEN NULL
            ELSE bs.recruiter_user_id
          END
        WHEN 'master' THEN bs.master_user_id
        WHEN 'seller' THEN
          CASE
            WHEN bs.seller_user_id IS NOT NULL
              AND NOT public.is_company_role_user(bs.seller_user_id, bs.company_id)
              AND public._is_platform_seller_user(bs.seller_user_id)
              THEN bs.seller_user_id
            ELSE NULL
          END
        WHEN 'company' THEN bs.owner_user_id
        ELSE bs.setting_beneficiary_user_id
      END AS beneficiary_user_id,
      CASE bs.stakeholder_role
        WHEN 'admin_pays' THEN (SELECT cnt FROM admin_count)
        ELSE 1::double precision
      END AS split_divisor
    FROM booking_settings bs
    LEFT JOIN admin_users au ON bs.stakeholder_role = 'admin_pays'
  )
  SELECT
    rs.country_id,
    rs.company_id,
    rs.company_name,
    rs.stakeholder_role::text,
    rs.stakeholder_label,
    rs.beneficiary_user_id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')::text,
    MAX(rs.rate),
    MAX(rs.base_type)::text,
    ROUND(SUM(rs.platform_commission_amount * rs.rate / 100.0 / rs.split_divisor)::numeric, 2)::double precision,
    COUNT(DISTINCT rs.booking_id)::bigint,
    MAX(rs.currency)::text
  FROM role_slices rs
  LEFT JOIN "Users" u ON u.id = rs.beneficiary_user_id
  WHERE rs.stakeholder_role = 'platform' OR rs.beneficiary_user_id IS NOT NULL
  GROUP BY
    rs.country_id,
    rs.company_id,
    rs.company_name,
    rs.stakeholder_role,
    rs.stakeholder_label,
    rs.beneficiary_user_id,
    u."firstName",
    u."lastName"
  HAVING SUM(rs.platform_commission_amount * rs.rate / 100.0 / rs.split_divisor) > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_stakeholder_commission_setting(text, uuid, text, double precision, text, boolean, uuid, text, uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
