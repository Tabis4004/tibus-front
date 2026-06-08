-- Lot 28: fond de garantie compagnie (dépôt plateforme + déduction réservations en ligne).
-- Solde + X (dépôt) | Solde - M (réservation voyageur / tiers) | bloqué si Solde < M
-- N'impacte PAS counter_sale (guichet compagnie).

ALTER TABLE "Companies"
  ADD COLUMN IF NOT EXISTS "guaranteeBalance" double precision NOT NULL DEFAULT 0;

ALTER TABLE "Companies"
  DROP CONSTRAINT IF EXISTS "Companies_guaranteeBalance_check";
ALTER TABLE "Companies"
  ADD CONSTRAINT "Companies_guaranteeBalance_check"
  CHECK ("guaranteeBalance" >= 0);

CREATE TABLE IF NOT EXISTS "CompanyGuaranteeLedger" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "companyId" uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  "type" text NOT NULL,
  "amount" double precision NOT NULL,
  "balanceAfter" double precision NOT NULL,
  "reference" text,
  "bookingId" uuid REFERENCES "ReservationBus" ("id") ON DELETE SET NULL,
  "note" text,
  "createdBy" uuid REFERENCES "Users" ("id") DEFERRABLE INITIALLY IMMEDIATE,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "CompanyGuaranteeLedger_type_check"
    CHECK ("type" IN ('deposit', 'reservation', 'release')),
  CONSTRAINT "CompanyGuaranteeLedger_amount_check"
    CHECK ("amount" > 0)
);

CREATE INDEX IF NOT EXISTS "CompanyGuaranteeLedger_company_created_idx"
  ON "CompanyGuaranteeLedger" ("companyId", "createdAt" DESC);

ALTER TABLE "CompanyGuaranteeLedger" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_guarantee_ledger_select" ON "CompanyGuaranteeLedger";
CREATE POLICY "company_guarantee_ledger_select" ON "CompanyGuaranteeLedger"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), "companyId")
    OR public.has_country_role(
      (SELECT c."countryId" FROM "Companies" c WHERE c.id = "companyId"),
      ARRAY['admin_pays']
    )
  );

CREATE OR REPLACE FUNCTION public.is_guarantee_reservation_channel(p_sale_channel text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(NULLIF(trim(p_sale_channel), ''), 'traveler')
    IN ('traveler', 'seller_reservation');
$$;

CREATE OR REPLACE FUNCTION public.can_manage_guarantee_deposit(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_super_admin()
    OR public.has_country_role(
      (SELECT c."countryId" FROM "Companies" c WHERE c.id = p_company_id),
      ARRAY['admin_pays']
    );
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
BEGIN
  IF NOT public.is_guarantee_reservation_channel(p_sale_channel) THEN
    RETURN jsonb_build_object('required', false, 'sufficient', true, 'skipped', true);
  END IF;

  IF COALESCE(p_amount, 0) <= 0 THEN
    RETURN jsonb_build_object('required', true, 'sufficient', true, 'amount', 0);
  END IF;

  SELECT c."guaranteeBalance", COALESCE(ct.currency, 'XOF')
  INTO v_balance, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compagnie introuvable';
  END IF;

  RETURN jsonb_build_object(
    'required', true,
    'sufficient', v_balance >= p_amount,
    'balance', v_balance,
    'amount', p_amount,
    'currency', v_currency
  );
END;
$$;

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
DECLARE
  v_user_id uuid;
  v_balance double precision;
  v_new_balance double precision;
  v_ledger_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF NOT public.can_manage_guarantee_deposit(p_company_id) THEN
    RAISE EXCEPTION 'Droit depot fond de garantie refuse';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Montant depot invalide';
  END IF;

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
    v_user_id
  )
  RETURNING id INTO v_ledger_id;

  RETURN jsonb_build_object(
    'ledgerId', v_ledger_id,
    'type', 'deposit',
    'amount', p_amount,
    'balanceAfter', v_new_balance
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

  SELECT c."guaranteeBalance" INTO v_balance
  FROM "Companies" c
  WHERE c.id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  IF v_balance < p_amount THEN
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
    'balanceAfter', v_new_balance
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.release_company_guarantee_fund(
  p_booking_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rb record;
  v_company_id uuid;
  v_balance double precision;
  v_new_balance double precision;
  v_amount double precision;
  v_ledger_id uuid;
BEGIN
  SELECT rb.id, rb."reservationId", rb.price, rb."saleChannel", p.reference
  INTO v_rb
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb.id = p_booking_id;

  IF v_rb.id IS NULL THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'booking_not_found');
  END IF;

  IF NOT public.is_guarantee_reservation_channel(v_rb."saleChannel") THEN
    RETURN jsonb_build_object('skipped', true);
  END IF;

  v_amount := COALESCE(v_rb.price, 0);
  IF v_amount <= 0 THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'zero_amount');
  END IF;

  IF EXISTS (
    SELECT 1 FROM "CompanyGuaranteeLedger" l
    WHERE l."bookingId" = p_booking_id AND l."type" = 'release'
  ) THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'already_released');
  END IF;

  v_company_id := public.reservation_company_id(v_rb."reservationId");

  SELECT c."guaranteeBalance" INTO v_balance
  FROM "Companies" c
  WHERE c.id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

  v_new_balance := v_balance + v_amount;

  UPDATE "Companies"
  SET "guaranteeBalance" = v_new_balance
  WHERE id = v_company_id;

  INSERT INTO "CompanyGuaranteeLedger" (
    "companyId", "type", "amount", "balanceAfter", "reference", "bookingId", "createdBy"
  )
  VALUES (
    v_company_id,
    'release',
    v_amount,
    v_new_balance,
    v_rb.reference,
    p_booking_id,
    public.current_app_user_id()
  )
  RETURNING id INTO v_ledger_id;

  RETURN jsonb_build_object(
    'ledgerId', v_ledger_id,
    'type', 'release',
    'amount', v_amount,
    'balanceAfter', v_new_balance
  );
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
  v_recent jsonb;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.is_company_role_user(public.current_app_user_id(), p_company_id)
    OR public.can_manage_guarantee_deposit(p_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces fond de garantie refuse';
  END IF;

  SELECT c."guaranteeBalance", COALESCE(ct.currency, 'XOF')
  INTO v_balance, v_currency
  FROM "Companies" c
  LEFT JOIN "Countries" ct ON ct.id = c."countryId"
  WHERE c.id = p_company_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;

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
    'recent', v_recent
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_company_guarantee_ledger(
  p_company_id uuid,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  created_at timestamptz,
  type text,
  amount double precision,
  balance_after double precision,
  reference text,
  booking_id uuid,
  note text,
  author_name text
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
    RAISE EXCEPTION 'Acces historique fond de garantie refuse';
  END IF;

  RETURN QUERY
  SELECT
    l.id,
    l."createdAt",
    l.type,
    l.amount,
    l."balanceAfter",
    l.reference,
    l."bookingId",
    l.note,
    NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), '')
  FROM "CompanyGuaranteeLedger" l
  LEFT JOIN "Users" u ON u.id = l."createdBy"
  WHERE l."companyId" = p_company_id
  ORDER BY l."createdAt" DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

-- Libère le fond à l'annulation d'un billet réservation en ligne.
CREATE OR REPLACE FUNCTION public.cancel_company_ticket(
  p_booking_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_rb record;
  v_preview jsonb;
  v_user_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT rb.*, r.date AS departure_time
  INTO v_rb
  FROM "ReservationBus" rb
  JOIN "Reservations" r ON r.id = rb."reservationId"
  WHERE rb.id = p_booking_id
  FOR UPDATE;

  IF v_rb.id IS NULL THEN RAISE EXCEPTION 'Billet introuvable'; END IF;
  IF COALESCE(v_rb."ticketStatus", 'issued') <> 'issued' THEN RAISE EXCEPTION 'Billet deja annule'; END IF;
  IF v_rb.departure_time <= now() THEN RAISE EXCEPTION 'Depart deja effectue ou en cours'; END IF;

  v_company_id := public.reservation_company_id(v_rb."reservationId");
  IF NOT public.can_cancel_company_ticket(v_company_id) THEN
    RAISE EXCEPTION 'Annulation reservee au owner et au vendeur de la compagnie';
  END IF;

  v_preview := public.preview_ticket_cancellation(p_booking_id);
  IF COALESCE((v_preview->>'canExecute')::boolean, false) = false THEN
    RAISE EXCEPTION 'Annulation impossible dans la fenetre actuelle';
  END IF;

  UPDATE "ReservationBus"
  SET
    "ticketStatus" = 'cancelled',
    "cancelledAt" = now(),
    "cancelledBy" = v_user_id,
    "penaltyAmount" = (v_preview->>'penaltyAmount')::double precision,
    "refundAmount" = (v_preview->>'refundAmount')::double precision,
    "cancellationReason" = NULLIF(trim(p_reason), ''),
    "sellerCommissionStatus" = CASE
      WHEN "sellerCommissionAmount" IS NOT NULL THEN 'cancelled'
      ELSE "sellerCommissionStatus"
    END
  WHERE id = p_booking_id;

  PERFORM public.release_company_guarantee_fund(p_booking_id);

  RETURN v_preview || jsonb_build_object('status', 'cancelled', 'cancelledAt', now());
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_guarantee_reservation_channel(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_company_guarantee_sufficient(uuid, double precision, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_company_guarantee_fund(uuid, double precision, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deduct_company_guarantee_fund(uuid, double precision, text, uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_company_guarantee_fund(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_guarantee_fund(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_guarantee_ledger(uuid, integer, integer) TO authenticated;
