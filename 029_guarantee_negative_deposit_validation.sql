-- Lot 29: solde négatif configurable + dépôts avec relevé validés par owner/comptable.

ALTER TABLE "Companies"
  ADD COLUMN IF NOT EXISTS "guaranteeAllowNegative" boolean NOT NULL DEFAULT false;

ALTER TABLE "Companies"
  DROP CONSTRAINT IF EXISTS "Companies_guaranteeBalance_check";

CREATE TABLE IF NOT EXISTS "CompanyGuaranteeDeposit" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "amount" double precision NOT NULL,
  "reference" text,
  "note" text,
  "receiptPath" text NOT NULL,
  "receiptFileName" text,
  "status" text NOT NULL DEFAULT 'pending',
  "submittedBy" uuid NOT NULL REFERENCES "Users" ("id") DEFERRABLE INITIALLY IMMEDIATE,
  "validatedBy" uuid REFERENCES "Users" ("id") DEFERRABLE INITIALLY IMMEDIATE,
  "validatedAt" timestamptz,
  "rejectionReason" text,
  "ledgerId" uuid REFERENCES "CompanyGuaranteeLedger" ("id") ON DELETE SET NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "CompanyGuaranteeDeposit_amount_check" CHECK ("amount" > 0),
  CONSTRAINT "CompanyGuaranteeDeposit_status_check"
    CHECK ("status" IN ('pending', 'approved', 'rejected'))
);

CREATE INDEX IF NOT EXISTS "CompanyGuaranteeDeposit_company_status_idx"
  ON "CompanyGuaranteeDeposit" ("companyId", "status", "createdAt" DESC);

ALTER TABLE "CompanyGuaranteeDeposit" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_guarantee_deposit_select" ON "CompanyGuaranteeDeposit";
CREATE POLICY "company_guarantee_deposit_select" ON "CompanyGuaranteeDeposit"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), "companyId")
    OR public.can_manage_guarantee_deposit("companyId")
  );

CREATE OR REPLACE FUNCTION public.can_validate_guarantee_deposit(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie']);
$$;

CREATE OR REPLACE FUNCTION public.credit_company_guarantee_fund(
  p_company_id uuid,
  p_amount double precision,
  p_reference text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_author_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance double precision;
  v_new_balance double precision;
  v_ledger_id uuid;
  v_author uuid;
BEGIN
  IF COALESCE(p_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Montant depot invalide';
  END IF;

  v_author := COALESCE(p_author_id, public.current_app_user_id());

  SELECT c."guaranteeBalance" INTO v_balance
  FROM "Companies" c
  WHERE c.id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  v_new_balance := v_balance + p_amount;

  UPDATE "Companies"
  SET "guaranteeBalance" = v_new_balance
  WHERE id = p_company_id;

  INSERT INTO "CompanyGuaranteeLedger" (
    "companyId", "type", "amount", "balanceAfter", "reference", "note", "createdBy"
  )
  VALUES (
    p_company_id,
    'deposit',
    p_amount,
    v_new_balance,
    NULLIF(trim(p_reference), ''),
    NULLIF(trim(p_note), ''),
    v_author
  )
  RETURNING id INTO v_ledger_id;

  RETURN v_ledger_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_company_guarantee_sufficient(
  p_company_id uuid,
  p_amount double precision,
  p_sale_channel text DEFAULT 'traveler'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance double precision;
  v_currency text;
  v_allow_negative boolean;
BEGIN
  IF NOT public.is_guarantee_reservation_channel(p_sale_channel) THEN
    RETURN jsonb_build_object('required', false, 'sufficient', true, 'skipped', true);
  END IF;

  IF COALESCE(p_amount, 0) <= 0 THEN
    RETURN jsonb_build_object('required', true, 'sufficient', true, 'amount', 0);
  END IF;

  SELECT c."guaranteeBalance", COALESCE(ct.currency, 'XOF'), c."guaranteeAllowNegative"
  INTO v_balance, v_currency, v_allow_negative
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  RETURN jsonb_build_object(
    'required', true,
    'sufficient', v_allow_negative OR v_balance >= p_amount,
    'allowNegative', v_allow_negative,
    'balance', v_balance,
    'amount', p_amount,
    'currency', v_currency
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.deduct_company_guarantee_fund(
  p_company_id uuid,
  p_amount double precision,
  p_sale_channel text,
  p_booking_id uuid DEFAULT NULL,
  p_reference text DEFAULT NULL,
  p_author_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance double precision;
  v_new_balance double precision;
  v_allow_negative boolean;
  v_ledger_id uuid;
  v_author uuid;
BEGIN
  IF NOT public.is_guarantee_reservation_channel(p_sale_channel) THEN
    RETURN jsonb_build_object('skipped', true);
  END IF;

  IF COALESCE(p_amount, 0) <= 0 THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'zero_amount');
  END IF;

  v_author := COALESCE(p_author_id, public.current_app_user_id());

  SELECT c."guaranteeBalance", c."guaranteeAllowNegative"
  INTO v_balance, v_allow_negative
  FROM "Companies" c
  WHERE c.id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  IF NOT v_allow_negative AND v_balance < p_amount THEN
    RAISE EXCEPTION 'Fond de garantie insuffisant (solde: %, requis: %)', v_balance, p_amount
      USING ERRCODE = 'P0001';
  END IF;

  v_new_balance := v_balance - p_amount;

  UPDATE "Companies"
  SET "guaranteeBalance" = v_new_balance
  WHERE id = p_company_id;

  INSERT INTO "CompanyGuaranteeLedger" (
    "companyId", "type", "amount", "balanceAfter", "reference", "bookingId", "createdBy"
  )
  VALUES (
    p_company_id,
    'reservation',
    p_amount,
    v_new_balance,
    NULLIF(trim(p_reference), ''),
    p_booking_id,
    v_author
  )
  RETURNING id INTO v_ledger_id;

  RETURN jsonb_build_object(
    'ledgerId', v_ledger_id,
    'type', 'reservation',
    'amount', p_amount,
    'balanceAfter', v_new_balance,
    'allowNegative', v_allow_negative
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_company_guarantee_settings(
  p_company_id uuid,
  p_allow_negative boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner'])
  ) THEN
    RAISE EXCEPTION 'Parametrage fond de garantie reserve au owner';
  END IF;

  UPDATE "Companies"
  SET "guaranteeAllowNegative" = COALESCE(p_allow_negative, false)
  WHERE id = p_company_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  RETURN jsonb_build_object(
    'companyId', p_company_id,
    'allowNegative', COALESCE(p_allow_negative, false)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_company_guarantee_deposit(
  p_company_id uuid,
  p_amount double precision,
  p_receipt_path text,
  p_reference text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_receipt_file_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF NOT public.can_manage_guarantee_deposit(p_company_id) THEN
    RAISE EXCEPTION 'Droit soumission depot refuse';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF NULLIF(trim(p_receipt_path), '') IS NULL THEN
    RAISE EXCEPTION 'Releve de depot obligatoire';
  END IF;

  INSERT INTO "CompanyGuaranteeDeposit" (
    "companyId", "amount", "reference", "note", "receiptPath", "receiptFileName", "submittedBy"
  )
  VALUES (
    p_company_id,
    p_amount,
    NULLIF(trim(p_reference), ''),
    NULLIF(trim(p_note), ''),
    trim(p_receipt_path),
    NULLIF(trim(p_receipt_file_name), ''),
    v_user_id
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END;
$$;

CREATE OR REPLACE FUNCTION public.list_company_guarantee_deposits(
  p_company_id uuid,
  p_status text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  created_at timestamptz,
  amount double precision,
  reference text,
  note text,
  receipt_path text,
  receipt_file_name text,
  status text,
  submitted_by_name text,
  validated_by_name text,
  validated_at timestamptz,
  rejection_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), p_company_id)
    OR public.can_manage_guarantee_deposit(p_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces depots refuse';
  END IF;

  RETURN QUERY
  SELECT
    d.id,
    d."createdAt",
    d.amount,
    d.reference,
    d.note,
    d."receiptPath",
    d."receiptFileName",
    d.status,
    NULLIF(TRIM(us."firstName" || ' ' || us."lastName"), ''),
    NULLIF(TRIM(uv."firstName" || ' ' || uv."lastName"), ''),
    d."validatedAt",
    d."rejectionReason"
  FROM "CompanyGuaranteeDeposit" d
  LEFT JOIN "Users" us ON us.id = d."submittedBy"
  LEFT JOIN "Users" uv ON uv.id = d."validatedBy"
  WHERE d."companyId" = p_company_id
    AND (p_status IS NULL OR NULLIF(trim(p_status), '') IS NULL OR d.status = p_status)
  ORDER BY d."createdAt" DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_company_guarantee_deposit(p_deposit_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_ledger_id uuid;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_row
  FROM "CompanyGuaranteeDeposit"
  WHERE id = p_deposit_id
  FOR UPDATE;

  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Depot introuvable'; END IF;
  IF v_row.status <> 'pending' THEN RAISE EXCEPTION 'Depot deja traite'; END IF;
  IF NOT public.can_validate_guarantee_deposit(v_row."companyId") THEN
    RAISE EXCEPTION 'Validation reservee au owner ou comptable';
  END IF;

  v_ledger_id := public.credit_company_guarantee_fund(
    v_row."companyId",
    v_row.amount,
    v_row.reference,
    COALESCE(v_row.note, 'Depot valide'),
    v_user_id
  );

  UPDATE "CompanyGuaranteeDeposit"
  SET
    status = 'approved',
    "validatedBy" = v_user_id,
    "validatedAt" = now(),
    "ledgerId" = v_ledger_id
  WHERE id = p_deposit_id;

  RETURN jsonb_build_object(
    'id', p_deposit_id,
    'status', 'approved',
    'ledgerId', v_ledger_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_company_guarantee_deposit(
  p_deposit_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_row
  FROM "CompanyGuaranteeDeposit"
  WHERE id = p_deposit_id
  FOR UPDATE;

  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Depot introuvable'; END IF;
  IF v_row.status <> 'pending' THEN RAISE EXCEPTION 'Depot deja traite'; END IF;
  IF NOT public.can_validate_guarantee_deposit(v_row."companyId") THEN
    RAISE EXCEPTION 'Rejet reserve au owner ou comptable';
  END IF;

  UPDATE "CompanyGuaranteeDeposit"
  SET
    status = 'rejected',
    "validatedBy" = v_user_id,
    "validatedAt" = now(),
    "rejectionReason" = NULLIF(trim(p_reason), '')
  WHERE id = p_deposit_id;

  RETURN jsonb_build_object('id', p_deposit_id, 'status', 'rejected');
END;
$$;

-- Remplace le depot immediat admin par soumission (garde compat si appele sans releve).
CREATE OR REPLACE FUNCTION public.deposit_company_guarantee_fund(
  p_company_id uuid,
  p_amount double precision,
  p_reference text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'Utilisez submit_company_guarantee_deposit avec un releve de depot';
END;
$$;

CREATE OR REPLACE FUNCTION public.get_company_guarantee_fund(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance double precision;
  v_currency text;
  v_allow_negative boolean;
  v_recent jsonb;
  v_pending_count integer;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), p_company_id)
    OR public.can_manage_guarantee_deposit(p_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces fond de garantie refuse';
  END IF;

  SELECT c."guaranteeBalance", COALESCE(ct.currency, 'XOF'), c."guaranteeAllowNegative"
  INTO v_balance, v_currency, v_allow_negative
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  SELECT COUNT(*)::integer INTO v_pending_count
  FROM "CompanyGuaranteeDeposit" d
  WHERE d."companyId" = p_company_id AND d.status = 'pending';

  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t."createdAt" DESC), '[]'::jsonb)
  INTO v_recent
  FROM (
    SELECT
      l.id,
      l."createdAt",
      l.type,
      l.amount,
      l."balanceAfter",
      l.reference,
      l."bookingId",
      l.note,
      NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), '') AS "authorName"
    FROM "CompanyGuaranteeLedger" l
    LEFT JOIN "Users" u ON u.id = l."createdBy"
    WHERE l."companyId" = p_company_id
    ORDER BY l."createdAt" DESC
    LIMIT 20
  ) t;

  RETURN jsonb_build_object(
    'companyId', p_company_id,
    'balance', v_balance,
    'currency', v_currency,
    'allowNegative', v_allow_negative,
    'pendingDeposits', v_pending_count,
    'recent', v_recent
  );
END;
$$;

-- Storage bucket releves de depot
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'guarantee-deposit-receipts',
  'guarantee-deposit-receipts',
  false,
  10485760,
  ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "guarantee_receipt_upload" ON storage.objects;
CREATE POLICY "guarantee_receipt_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'guarantee-deposit-receipts'
    AND (
      public.is_super_admin()
      OR public.has_global_droit('manage_country')
      OR public.has_global_droit('manage_company')
    )
  );

DROP POLICY IF EXISTS "guarantee_receipt_read" ON storage.objects;
CREATE POLICY "guarantee_receipt_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'guarantee-deposit-receipts'
    AND (
      public.is_super_admin()
      OR public.has_global_droit('manage_country')
      OR (storage.foldername(name))[1] IS NOT NULL
        AND public.is_company_role_user(
          public.current_app_user_id(),
          ((storage.foldername(name))[1])::uuid
        )
    )
  );

GRANT EXECUTE ON FUNCTION public.credit_company_guarantee_fund(uuid, double precision, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_company_guarantee_settings(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_company_guarantee_deposit(uuid, double precision, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_guarantee_deposits(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_company_guarantee_deposit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_company_guarantee_deposit(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_validate_guarantee_deposit(uuid) TO authenticated;
