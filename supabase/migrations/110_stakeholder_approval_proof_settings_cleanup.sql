-- 110 — Validation admin pays uniquement + preuve de paiement + nettoyage taux à 0

ALTER TABLE "StakeholderCommissionSettlements"
  ADD COLUMN IF NOT EXISTS "approvalNote" text,
  ADD COLUMN IF NOT EXISTS "paymentProofPath" text,
  ADD COLUMN IF NOT EXISTS "paymentProofFileName" text;

CREATE OR REPLACE FUNCTION public._can_approve_stakeholder_settlement(p_country_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.current_app_user_id() IS NULL THEN
    RETURN false;
  END IF;
  RETURN public.is_super_admin()
    OR public.has_country_role(p_country_id, ARRAY['admin_pays']);
END;
$$;

DROP FUNCTION IF EXISTS public.confirm_stakeholder_commission_settlement(uuid);

CREATE OR REPLACE FUNCTION public.confirm_stakeholder_commission_settlement(
  p_settlement_id uuid,
  p_approval_note text DEFAULT NULL,
  p_payment_proof_path text DEFAULT NULL,
  p_payment_proof_file_name text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settlement record;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();

  SELECT *
  INTO v_settlement
  FROM "StakeholderCommissionSettlements"
  WHERE id = p_settlement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reglement introuvable';
  END IF;

  IF v_settlement.status <> 'pending_confirmation' THEN
    RAISE EXCEPTION 'Reglement deja traite';
  END IF;

  IF NOT public._can_approve_stakeholder_settlement(v_settlement."countryId") THEN
    RAISE EXCEPTION 'Validation reservee au super admin ou admin pays';
  END IF;

  IF NULLIF(trim(p_approval_note), '') IS NULL THEN
    RAISE EXCEPTION 'Base de validation requise (reference virement, note comptable, etc.)';
  END IF;

  IF NULLIF(trim(p_payment_proof_path), '') IS NULL THEN
    RAISE EXCEPTION 'Preuve de paiement requise (releve, capture, recu)';
  END IF;

  UPDATE "StakeholderCommissionSettlements"
  SET
    status = 'confirmed',
    "confirmedBy" = v_user_id,
    "confirmedAt" = now(),
    "approvalNote" = NULLIF(trim(p_approval_note), ''),
    "paymentProofPath" = NULLIF(trim(p_payment_proof_path), ''),
    "paymentProofFileName" = NULLIF(trim(p_payment_proof_file_name), '')
  WHERE id = p_settlement_id;
END;
$$;

DROP FUNCTION IF EXISTS public.list_stakeholder_commission_settlement_history(uuid, uuid, integer);

CREATE OR REPLACE FUNCTION public.list_stakeholder_commission_settlement_history(
  p_country_id uuid DEFAULT NULL,
  p_beneficiary_user_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  id uuid,
  country_id uuid,
  country_name text,
  stakeholder_role text,
  beneficiary_user_id uuid,
  beneficiary_name text,
  amount double precision,
  currency text,
  status text,
  earned_snapshot double precision,
  note text,
  initiated_by uuid,
  initiated_by_name text,
  initiated_at timestamptz,
  confirmed_by uuid,
  confirmed_by_name text,
  confirmed_at timestamptz,
  rejected_by uuid,
  rejected_by_name text,
  rejected_at timestamptz,
  rejection_reason text,
  approval_note text,
  payment_proof_path text,
  payment_proof_file_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_country_id uuid;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  v_country_id := public._resolve_stakeholder_commission_country(p_country_id);

  IF NOT (
    public.is_super_admin()
    OR (v_country_id IS NOT NULL AND public.has_country_role(v_country_id, ARRAY['admin_pays']))
    OR p_beneficiary_user_id IS NULL
    OR p_beneficiary_user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s."countryId",
    c.name::text,
    s."stakeholderRole",
    s."beneficiaryUserId",
    NULLIF(TRIM(COALESCE(bu."firstName", '') || ' ' || COALESCE(bu."lastName", '')), ''),
    s.amount,
    s.currency,
    s.status,
    s."earnedSnapshot",
    s.note,
    s."initiatedBy",
    NULLIF(TRIM(COALESCE(iu."firstName", '') || ' ' || COALESCE(iu."lastName", '')), ''),
    s."initiatedAt",
    s."confirmedBy",
    NULLIF(TRIM(COALESCE(cu."firstName", '') || ' ' || COALESCE(cu."lastName", '')), ''),
    s."confirmedAt",
    s."rejectedBy",
    NULLIF(TRIM(COALESCE(ru."firstName", '') || ' ' || COALESCE(ru."lastName", '')), ''),
    s."rejectedAt",
    s."rejectionReason",
    s."approvalNote",
    s."paymentProofPath",
    s."paymentProofFileName"
  FROM "StakeholderCommissionSettlements" s
  JOIN "Countries" c ON c.id = s."countryId"
  LEFT JOIN "Users" bu ON bu.id = s."beneficiaryUserId"
  LEFT JOIN "Users" iu ON iu.id = s."initiatedBy"
  LEFT JOIN "Users" cu ON cu.id = s."confirmedBy"
  LEFT JOIN "Users" ru ON ru.id = s."rejectedBy"
  WHERE
    (v_country_id IS NULL OR s."countryId" = v_country_id)
    AND (p_beneficiary_user_id IS NULL OR s."beneficiaryUserId" IS NOT DISTINCT FROM p_beneficiary_user_id)
    AND (
      public.is_super_admin()
      OR public.has_country_role(s."countryId", ARRAY['admin_pays'])
      OR s."beneficiaryUserId" = v_user_id
      OR s."initiatedBy" = v_user_id
    )
  ORDER BY s."initiatedAt" DESC
  LIMIT GREATEST(COALESCE(p_limit, 50), 1);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_stakeholder_commission_setting(p_setting_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  DELETE FROM "StakeholderCommissionSettings"
  WHERE id = p_setting_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_stakeholder_commission_setting(
  p_scope text,
  p_country_id uuid DEFAULT NULL,
  p_stakeholder_role text DEFAULT 'platform',
  p_rate double precision DEFAULT 0,
  p_base_type text DEFAULT 'platform_commission',
  p_is_active boolean DEFAULT true,
  p_company_id uuid DEFAULT NULL,
  p_label text DEFAULT NULL,
  p_beneficiary_user_id uuid DEFAULT NULL,
  p_setting_id uuid DEFAULT NULL
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
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
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
  IF p_stakeholder_role = 'custom' AND COALESCE(p_rate, 0) > 0
    AND (p_label IS NULL OR p_beneficiary_user_id IS NULL) THEN
    RAISE EXCEPTION 'Label et beneficiaire requis pour un stakeholder custom actif';
  END IF;
  IF p_stakeholder_role <> 'platform'
    AND p_stakeholder_role <> 'custom'
    AND COALESCE(p_rate, 0) > 0
    AND p_beneficiary_user_id IS NULL
  THEN
    RAISE EXCEPTION 'Utilisateur beneficiaire requis lorsque le taux est superieur a 0';
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
          AND s."beneficiaryUserId" IS NOT DISTINCT FROM p_beneficiary_user_id
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
      "beneficiaryUserId" = p_beneficiary_user_id,
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
    p_beneficiary_user_id,
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
      "beneficiaryUserId" = p_beneficiary_user_id,
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    WHERE id = v_id;

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_stakeholder_commission_settlement(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_stakeholder_commission_settlement_history(uuid, uuid, integer) TO authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'stakeholder-payment-proofs',
  'stakeholder-payment-proofs',
  false,
  10485760,
  ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS stakeholder_proof_upload ON storage.objects;
CREATE POLICY stakeholder_proof_upload ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'stakeholder-payment-proofs'
    AND (
      public.is_super_admin()
      OR public.has_country_role(((storage.foldername(name))[1])::uuid, ARRAY['admin_pays'])
    )
  );

DROP POLICY IF EXISTS stakeholder_proof_read ON storage.objects;
CREATE POLICY stakeholder_proof_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'stakeholder-payment-proofs'
    AND (
      public.is_super_admin()
      OR public.has_country_role(((storage.foldername(name))[1])::uuid, ARRAY['admin_pays'])
    )
  );
