-- Lot 1 billetterie Supabase: stocker le voyageur et le siege paye.
-- Idempotent: peut etre relance sans casser les donnees existantes.

ALTER TABLE "ReservationBus"
  ADD COLUMN IF NOT EXISTS "passengerName" text,
  ADD COLUMN IF NOT EXISTS "seatNumber" text;

CREATE UNIQUE INDEX IF NOT EXISTS "reservationbus_paid_seat_unique"
  ON "ReservationBus" ("reservationId", "seatNumber")
  WHERE "seatNumber" IS NOT NULL;
