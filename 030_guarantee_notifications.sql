-- Lot 30: notifications in-app + push pour le workflow fond de garantie.

ALTER TABLE "Notifications"
  ADD COLUMN IF NOT EXISTS "metadata" jsonb;

CREATE TABLE IF NOT EXISTS "UserPushSubscription" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "userId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "endpoint" text NOT NULL,
  "p256dh" text NOT NULL,
  "auth" text NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "UserPushSubscription_endpoint_key" UNIQUE ("endpoint")
);

CREATE INDEX IF NOT EXISTS "UserPushSubscription_userId_idx"
  ON "UserPushSubscription" ("userId");

ALTER TABLE "UserPushSubscription" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push_subscription_select" ON "UserPushSubscription";
CREATE POLICY "push_subscription_select" ON "UserPushSubscription"
  FOR SELECT TO authenticated
  USING ("userId" = public.current_app_user_id() OR public.is_super_admin());

DROP POLICY IF EXISTS "push_subscription_write" ON "UserPushSubscription";
CREATE POLICY "push_subscription_write" ON "UserPushSubscription"
  FOR ALL TO authenticated
  USING ("userId" = public.current_app_user_id())
  WITH CHECK ("userId" = public.current_app_user_id());

CREATE OR REPLACE FUNCTION public.create_user_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_message text,
  p_metadata jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_user_id IS NULL THEN RETURN NULL; END IF;

  INSERT INTO "Notifications" ("userId", "type", "title", "message", "metadata")
  VALUES (p_user_id, p_type, p_title, p_message, p_metadata)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_company_guarantee_validator_ids(p_company_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(DISTINCT ur."userId"), ARRAY[]::uuid[])
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."companyId" = p_company_id
    AND r.name IN ('owner', 'comptable_compagnie');
$$;

CREATE OR REPLACE FUNCTION public.notify_guarantee_deposit_pending(
  p_company_id uuid,
  p_deposit_id uuid,
  p_amount double precision
)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_name text;
  v_currency text;
  v_user_id uuid;
  v_notify_ids uuid[];
BEGIN
  SELECT c.name, COALESCE(ct.currency, 'XOF')
  INTO v_company_name, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  v_notify_ids := public.get_company_guarantee_validator_ids(p_company_id);

  FOREACH v_user_id IN ARRAY v_notify_ids
  LOOP
    PERFORM public.create_user_notification(
      v_user_id,
      'guarantee_deposit_pending',
      'Dépôt fond de garantie à valider',
      format(
        'Un dépôt de %s %s pour %s nécessite votre validation.',
        to_char(p_amount, 'FM999999999990'),
        v_currency,
        COALESCE(v_company_name, 'la compagnie')
      ),
      jsonb_build_object(
        'companyId', p_company_id,
        'depositId', p_deposit_id,
        'amount', p_amount,
        'url', '/company/guarantee-fund'
      )
    );
  END LOOP;

  RETURN v_notify_ids;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_guarantee_deposit_approved(
  p_company_id uuid,
  p_deposit_id uuid,
  p_amount double precision,
  p_submitted_by uuid
)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_name text;
  v_currency text;
  v_notify_ids uuid[];
BEGIN
  SELECT c.name, COALESCE(ct.currency, 'XOF')
  INTO v_company_name, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  v_notify_ids := ARRAY[]::uuid[];
  IF p_submitted_by IS NOT NULL THEN
    v_notify_ids := ARRAY[p_submitted_by];
    PERFORM public.create_user_notification(
      p_submitted_by,
      'guarantee_deposit_approved',
      'Dépôt fond de garantie validé',
      format(
        'Votre dépôt de %s %s pour %s a été validé. Le solde est crédité de façon cumulative.',
        to_char(p_amount, 'FM999999999990'),
        v_currency,
        COALESCE(v_company_name, 'la compagnie')
      ),
      jsonb_build_object(
        'companyId', p_company_id,
        'depositId', p_deposit_id,
        'amount', p_amount,
        'url', '/admin'
      )
    );
  END IF;

  RETURN v_notify_ids;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_guarantee_deposit_rejected(
  p_company_id uuid,
  p_deposit_id uuid,
  p_amount double precision,
  p_submitted_by uuid,
  p_reason text DEFAULT NULL
)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_name text;
  v_currency text;
  v_notify_ids uuid[];
  v_reason text;
BEGIN
  SELECT c.name, COALESCE(ct.currency, 'XOF')
  INTO v_company_name, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  v_reason := NULLIF(trim(p_reason), '');
  v_notify_ids := ARRAY[]::uuid[];

  IF p_submitted_by IS NOT NULL THEN
    v_notify_ids := ARRAY[p_submitted_by];
    PERFORM public.create_user_notification(
      p_submitted_by,
      'guarantee_deposit_rejected',
      'Dépôt fond de garantie rejeté',
      format(
        'Votre dépôt de %s %s pour %s a été rejeté%s.',
        to_char(p_amount, 'FM999999999990'),
        v_currency,
        COALESCE(v_company_name, 'la compagnie'),
        CASE WHEN v_reason IS NULL THEN '' ELSE format(' (%s)', v_reason) END
      ),
      jsonb_build_object(
        'companyId', p_company_id,
        'depositId', p_deposit_id,
        'amount', p_amount,
        'reason', v_reason,
        'url', '/admin'
      )
    );
  END IF;

  RETURN v_notify_ids;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_guarantee_balance_low(
  p_company_id uuid,
  p_balance double precision
)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_name text;
  v_currency text;
  v_user_id uuid;
  v_notify_ids uuid[];
BEGIN
  SELECT c.name, COALESCE(ct.currency, 'XOF')
  INTO v_company_name, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  v_notify_ids := public.get_company_guarantee_validator_ids(p_company_id);

  FOREACH v_user_id IN ARRAY v_notify_ids
  LOOP
    PERFORM public.create_user_notification(
      v_user_id,
      'guarantee_balance_low',
      'Solde fond de garantie bas',
      format(
        'Le solde du fond de garantie de %s est à %s %s.',
        COALESCE(v_company_name, 'la compagnie'),
        to_char(p_balance, 'FM999999999990'),
        v_currency
      ),
      jsonb_build_object(
        'companyId', p_company_id,
        'balance', p_balance,
        'url', '/company/guarantee-fund'
      )
    );
  END LOOP;

  RETURN v_notify_ids;
END;
$$;

-- Soumission : notifie owner + comptable
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
  v_notify_ids uuid[];
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

  v_notify_ids := public.notify_guarantee_deposit_pending(p_company_id, v_id, p_amount);

  RETURN jsonb_build_object(
    'id', v_id,
    'status', 'pending',
    'notifyUserIds', to_jsonb(v_notify_ids),
    'pushEvent', 'submitted',
    'depositId', v_id
  );
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
  v_notify_ids uuid[];
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

  v_notify_ids := public.notify_guarantee_deposit_approved(
    v_row."companyId",
    p_deposit_id,
    v_row.amount,
    v_row."submittedBy"
  );

  RETURN jsonb_build_object(
    'id', p_deposit_id,
    'status', 'approved',
    'ledgerId', v_ledger_id,
    'notifyUserIds', to_jsonb(v_notify_ids),
    'pushEvent', 'approved',
    'depositId', p_deposit_id
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
  v_notify_ids uuid[];
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

  v_notify_ids := public.notify_guarantee_deposit_rejected(
    v_row."companyId",
    p_deposit_id,
    v_row.amount,
    v_row."submittedBy",
    p_reason
  );

  RETURN jsonb_build_object(
    'id', p_deposit_id,
    'status', 'rejected',
    'notifyUserIds', to_jsonb(v_notify_ids),
    'pushEvent', 'rejected',
    'depositId', p_deposit_id
  );
END;
$$;

-- Alerte solde bas après déduction (si solde <= 0)
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

  IF v_new_balance <= 0 THEN
    PERFORM public.notify_guarantee_balance_low(p_company_id, v_new_balance);
  END IF;

  RETURN jsonb_build_object(
    'ledgerId', v_ledger_id,
    'type', 'reservation',
    'amount', p_amount,
    'balanceAfter', v_new_balance,
    'allowNegative', v_allow_negative
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.register_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF NULLIF(trim(p_endpoint), '') IS NULL THEN RAISE EXCEPTION 'Endpoint requis'; END IF;

  INSERT INTO "UserPushSubscription" ("userId", "endpoint", "p256dh", "auth", "updatedAt")
  VALUES (v_user_id, trim(p_endpoint), trim(p_p256dh), trim(p_auth), now())
  ON CONFLICT ("endpoint") DO UPDATE
  SET
    "userId" = EXCLUDED."userId",
    "p256dh" = EXCLUDED."p256dh",
    "auth" = EXCLUDED."auth",
    "updatedAt" = now();

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_subscription(p_endpoint text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  DELETE FROM "UserPushSubscription"
  WHERE "endpoint" = trim(p_endpoint)
    AND ("userId" = v_user_id OR public.is_super_admin());

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_user_notifications(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  type text,
  title text,
  message text,
  is_read boolean,
  metadata jsonb,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.type::text,
    n.title::text,
    n.message,
    n."isRead",
    n.metadata,
    n."createdAt"
  FROM "Notifications" n
  WHERE n."userId" = v_user_id
  ORDER BY n."createdAt" DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100))
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_notification_unread_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_count integer;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  SELECT COUNT(*)::integer INTO v_count
  FROM "Notifications" n
  WHERE n."userId" = v_user_id AND n."isRead" = false;

  RETURN COALESCE(v_count, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  UPDATE "Notifications"
  SET "isRead" = true
  WHERE id = p_notification_id AND "userId" = v_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  UPDATE "Notifications"
  SET "isRead" = true
  WHERE "userId" = v_user_id AND "isRead" = false;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_user_notification(uuid, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_guarantee_validator_ids(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_subscription(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_subscription(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_user_notifications(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_unread_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;
