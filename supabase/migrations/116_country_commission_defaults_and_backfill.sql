-- 116 — Commission plateforme pays par défaut + recalcul des commissions capturées

INSERT INTO "CommissionSettings" ("scope", "countryId", "rate", "paidBy", "isActive")
SELECT
  'country',
  c.id,
  5,
  'traveler',
  true
FROM "Countries" c
WHERE EXISTS (SELECT 1 FROM "Companies" co WHERE co."countryId" = c.id)
  AND NOT EXISTS (
    SELECT 1 FROM "CommissionSettings" cs
    WHERE cs."scope" = 'country'
      AND cs."countryId" = c.id
      AND cs."isActive" = true
  );

CREATE OR REPLACE FUNCTION public.resolve_seller_commission_setting(p_company_id uuid)
RETURNS TABLE(
  setting_id uuid,
  setting_scope text,
  country_id uuid,
  company_id uuid,
  rate double precision,
  paid_by text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH company_row AS (
    SELECT c.id, c."countryId", COALESCE(c."commissionRate", 0) AS legacy_rate
    FROM "Companies" c
    WHERE c.id = p_company_id
  ),
  resolved AS (
    SELECT
      s.id AS setting_id,
      s.scope AS setting_scope,
      COALESCE(s."countryId", cr."countryId") AS country_id,
      s."companyId" AS company_id,
      s.rate,
      s."paidBy" AS paid_by,
      1 AS priority
    FROM company_row cr
    JOIN "CommissionSettings" s
      ON s."scope" = 'company'
     AND s."companyId" = cr.id
     AND s."isActive" = true
    UNION ALL
    SELECT
      s.id AS setting_id,
      s.scope AS setting_scope,
      s."countryId" AS country_id,
      NULL::uuid AS company_id,
      s.rate,
      s."paidBy" AS paid_by,
      2 AS priority
    FROM company_row cr
    JOIN "CommissionSettings" s
      ON s."scope" = 'country'
     AND s."countryId" = cr."countryId"
     AND s."isActive" = true
    UNION ALL
    SELECT
      NULL::uuid AS setting_id,
      'country_default'::text AS setting_scope,
      cr."countryId" AS country_id,
      NULL::uuid AS company_id,
      5::double precision AS rate,
      'traveler'::text AS paid_by,
      3 AS priority
    FROM company_row cr
    WHERE cr."countryId" IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM "CommissionSettings" s
        WHERE s."scope" = 'country'
          AND s."countryId" = cr."countryId"
          AND s."isActive" = true
      )
      AND NOT EXISTS (
        SELECT 1 FROM "CommissionSettings" s
        WHERE s."scope" = 'company'
          AND s."companyId" = cr.id
          AND s."isActive" = true
      )
    UNION ALL
    SELECT
      NULL::uuid AS setting_id,
      'legacy_company'::text AS setting_scope,
      cr."countryId" AS country_id,
      cr.id AS company_id,
      cr.legacy_rate AS rate,
      'company'::text AS paid_by,
      4 AS priority
    FROM company_row cr
  )
  SELECT
    resolved.setting_id,
    resolved.setting_scope,
    resolved.country_id,
    resolved.company_id,
    COALESCE(resolved.rate, 0),
    COALESCE(resolved.paid_by, 'company')
  FROM resolved
  ORDER BY priority
  LIMIT 1;
$$;

UPDATE "ReservationBus" rb
SET
  "platformCommissionAmount" = calc.commission_amount,
  "platformCommissionSource" = calc.commission_source
FROM (
  SELECT
    rb2.id AS booking_id,
    public._booking_platform_commission_amount(
      rb2.price,
      c.id,
      CASE
        WHEN COALESCE(rb2."saleChannel", 'traveler') IN ('counter_sale', 'seller_reservation') THEN 'counter_sale'
        ELSE 'traveler'
      END,
      NULL
    ) AS commission_amount,
    CASE
      WHEN COALESCE(rb2."saleChannel", 'traveler') IN ('counter_sale', 'seller_reservation') THEN 'counter_company'
      ELSE 'traveler_online'
    END AS commission_source
  FROM "ReservationBus" rb2
  JOIN "Payment" p ON p.id = rb2."paymentId"
  JOIN "Reservations" r ON r.id = rb2."reservationId"
  JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
  JOIN "Gares" g ON g.id = pt.depart
  JOIN "Companies" c ON c.id = g."companyId"
  WHERE rb2."type" = 'voyage'
    AND (rb2."isReservation" = false OR p."txID" IS NOT NULL)
    AND COALESCE(rb2."platformCommissionAmount", 0) = 0
) calc
WHERE rb.id = calc.booking_id
  AND calc.commission_amount > 0;

NOTIFY pgrst, 'reload schema';
