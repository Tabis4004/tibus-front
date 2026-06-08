-- =============================================================================
-- Tibus 052 — verifyToken sans pgcrypto (gen_random_bytes absent sur certains projets)
-- Exécuter dans Supabase SQL Editor après 051
-- =============================================================================

-- Optionnel : activer pgcrypto dans le schéma extensions (Supabase)
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Jeton QR : gen_random_uuid() est natif (pas besoin de pgcrypto)
CREATE OR REPLACE FUNCTION public.new_ticket_verify_token()
RETURNS text
LANGUAGE sql
VOLATILE
SET search_path = public
AS $$
  SELECT replace(gen_random_uuid()::text, '-', '');
$$;

CREATE OR REPLACE FUNCTION public.reservationbus_assign_verify_token()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW."verifyToken" IS NULL OR BTRIM(NEW."verifyToken") = '' THEN
    NEW."verifyToken" := public.new_ticket_verify_token();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reservationbus_verify_token_trg ON "ReservationBus";
CREATE TRIGGER reservationbus_verify_token_trg
  BEFORE INSERT ON "ReservationBus"
  FOR EACH ROW
  EXECUTE FUNCTION public.reservationbus_assign_verify_token();

-- Backfill des billets existants sans jeton (sans gen_random_bytes)
UPDATE "ReservationBus"
SET "verifyToken" = public.new_ticket_verify_token()
WHERE ("verifyToken" IS NULL OR BTRIM("verifyToken") = '')
  AND COALESCE("ticketStatus", 'issued') = 'issued';

GRANT EXECUTE ON FUNCTION public.new_ticket_verify_token() TO authenticated, service_role;
