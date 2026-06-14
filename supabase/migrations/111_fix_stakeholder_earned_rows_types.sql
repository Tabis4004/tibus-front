-- 111 — Corrige les types text dans _stakeholder_commission_earned_rows (varchar → text)

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
      c.id AS company_id,
      c.name::text AS company_name,
      c."countryId" AS country_id,
      COALESCE(country.currency, 'XOF')::text AS currency
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    JOIN "Gares" g ON g.id = pt.depart
    JOIN "Companies" c ON c.id = g."companyId"
    LEFT JOIN "Countries" country ON country.id = c."countryId"
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
        ELSE public._booking_platform_commission_amount(pb.nominal_amount, pb.company_id, 'traveler', NULL)
      END AS platform_commission_amount
    FROM paid_bookings pb
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
      AND (
        s.stakeholder_role = 'platform'
        OR s.beneficiary_user_id IS NOT NULL
      )
  )
  SELECT
    bs.country_id,
    bs.company_id,
    bs.company_name,
    bs.stakeholder_role::text,
    COALESCE(bs.label, bs.stakeholder_role)::text AS stakeholder_label,
    bs.setting_beneficiary_user_id AS beneficiary_user_id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')::text,
    MAX(bs.rate),
    MAX(bs.base_type)::text,
    ROUND(SUM(bs.platform_commission_amount * bs.rate / 100.0)::numeric, 2)::double precision,
    COUNT(DISTINCT bs.booking_id)::bigint,
    MAX(bs.currency)::text
  FROM booking_settings bs
  LEFT JOIN "Users" u ON u.id = bs.setting_beneficiary_user_id
  WHERE bs.stakeholder_role = 'platform' OR bs.setting_beneficiary_user_id IS NOT NULL
  GROUP BY
    bs.country_id,
    bs.company_id,
    bs.company_name,
    bs.stakeholder_role,
    bs.label,
    bs.setting_beneficiary_user_id,
    u."firstName",
    u."lastName"
  HAVING SUM(bs.platform_commission_amount * bs.rate / 100.0) > 0;
END;
$$;

NOTIFY pgrst, 'reload schema';
