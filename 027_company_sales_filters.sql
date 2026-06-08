-- Lot 27: filtres journal ventes compagnie (canal, période vente, date départ, recherche).

DROP FUNCTION IF EXISTS public.list_company_ticket_sales(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.list_company_ticket_sales(
  p_company_id uuid,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0,
  p_sale_channel text DEFAULT NULL,
  p_created_from timestamptz DEFAULT NULL,
  p_created_to timestamptz DEFAULT NULL,
  p_departure_from timestamptz DEFAULT NULL,
  p_departure_to timestamptz DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS TABLE(
  booking_id uuid,
  created_at timestamptz,
  reference text,
  passenger_name text,
  seat_number text,
  ticket_amount double precision,
  currency text,
  sale_channel text,
  ticket_status text,
  seller_user_id uuid,
  seller_name text,
  route_label text,
  departure_time timestamptz,
  hours_before_departure double precision,
  can_cancel boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_search text := NULLIF(TRIM(p_search), '');
BEGIN
  IF NOT public.can_view_company_sales(p_company_id) THEN
    RAISE EXCEPTION 'Acces journal ventes refuse';
  END IF;

  RETURN QUERY
  SELECT
    rb.id,
    rb."createdAt",
    p.reference::text,
    COALESCE(rb."passengerName", u."firstName" || ' ' || u."lastName")::text,
    rb."seatNumber"::text,
    COALESCE(rb.price, 0)::double precision,
    COALESCE(country.currency, 'XOF')::text,
    COALESCE(rb."saleChannel", 'traveler')::text,
    COALESCE(rb."ticketStatus", 'issued')::text,
    rb."createdBy",
    NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), '')::text,
    (g_depart.name || ' -> ' || g_final.name)::text,
    r.date,
    GREATEST(EXTRACT(EPOCH FROM (r.date - now())) / 3600.0, 0)::double precision,
    (
      COALESCE(rb."ticketStatus", 'issued') = 'issued'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND r.date > now()
      AND public.can_cancel_company_ticket(p_company_id)
    )
  FROM "ReservationBus" rb
  JOIN "Payment" p ON p.id = rb."paymentId"
  JOIN "Reservations" r ON r.id = rb."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g_depart ON g_depart.id = pt.depart
  JOIN "Gares" g_final ON g_final.id = pt.final
  JOIN "Companies" c ON c.id = g_depart."companyId"
  LEFT JOIN "Countries" country ON country.id = c."countryId"
  LEFT JOIN "Users" u ON u.id = rb."createdBy"
  WHERE rb."type" = 'voyage'
    AND c.id = p_company_id
    AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
    AND (
      p_sale_channel IS NULL
      OR NULLIF(TRIM(p_sale_channel), '') IS NULL
      OR COALESCE(rb."saleChannel", 'traveler') = NULLIF(TRIM(p_sale_channel), '')
    )
    AND (p_created_from IS NULL OR rb."createdAt" >= p_created_from)
    AND (p_created_to IS NULL OR rb."createdAt" <= p_created_to)
    AND (p_departure_from IS NULL OR r.date >= p_departure_from)
    AND (p_departure_to IS NULL OR r.date <= p_departure_to)
    AND (
      v_search IS NULL
      OR p.reference ILIKE '%' || v_search || '%'
      OR COALESCE(rb."passengerName", u."firstName" || ' ' || u."lastName") ILIKE '%' || v_search || '%'
    )
  ORDER BY rb."createdAt" DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_ticket_sales(
  uuid, integer, integer, text, timestamptz, timestamptz, timestamptz, timestamptz, text
) TO authenticated;
