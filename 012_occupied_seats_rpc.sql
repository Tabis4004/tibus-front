-- Expose uniquement les numeros de sieges payes/valides pour un depart.
-- Evite d'ouvrir la lecture complete de ReservationBus aux voyageurs.

CREATE OR REPLACE FUNCTION public.get_occupied_seats(p_reservation_id uuid)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY_AGG(rb."seatNumber" ORDER BY rb."seatNumber"), ARRAY[]::text[])
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  WHERE rb."reservationId" = p_reservation_id
    AND rb."type" = 'voyage'
    AND rb."seatNumber" IS NOT NULL
    AND (rb."isReservation" = false OR p."txID" IS NOT NULL);
$$;

GRANT EXECUTE ON FUNCTION public.get_occupied_seats(uuid) TO anon, authenticated;
