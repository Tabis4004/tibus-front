-- 122 — Rôle démarcheur (recruteur commercial) + dashboard performance / commissions

INSERT INTO "Role" ("name", "scope", "level", "isSystem", "description", "droits") VALUES
  (
    'demarcheur',
    'platform',
    12,
    true,
    'Démarcheur Tibus — suit les compagnies recrutées et ses commissions recruteur',
    ARRAY['view_recruited_companies', 'view_recruiter_commissions']
  )
ON CONFLICT ("name") DO UPDATE SET
  "scope" = EXCLUDED."scope",
  "level" = EXCLUDED."level",
  "isSystem" = EXCLUDED."isSystem",
  "description" = EXCLUDED."description",
  "droits" = EXCLUDED."droits";

CREATE OR REPLACE FUNCTION public.is_demarcheur()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = public.current_app_user_id()
      AND r.name = 'demarcheur'
  );
$$;

CREATE OR REPLACE FUNCTION public.get_demarcheur_dashboard(
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_country_id uuid;
  v_from timestamptz;
  v_to timestamptz;
  v_companies jsonb := '[]'::jsonb;
  v_commissions jsonb;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  IF NOT (public.is_demarcheur() OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_from := COALESCE(p_date_from, date_trunc('month', now()));
  v_to := COALESCE(p_date_to, now());

  SELECT ur."countryId"
  INTO v_country_id
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId" AND r.name = 'demarcheur'
  WHERE ur."userId" = v_user_id
    AND ur."countryId" IS NOT NULL
  LIMIT 1;

  IF v_country_id IS NULL THEN
    SELECT c."countryId"
    INTO v_country_id
    FROM "Companies" c
    WHERE c."recruitedByUserId" = v_user_id
      AND c."countryId" IS NOT NULL
    LIMIT 1;
  END IF;

  WITH recruited AS (
    SELECT
      c.id,
      c.name,
      c."isActive",
      c."managerName",
      c."countryId",
      co.name AS country_name,
      co.currency
    FROM "Companies" c
    LEFT JOIN "Countries" co ON co.id = c."countryId"
    WHERE c."recruitedByUserId" = v_user_id
  ),
  booking_stats AS (
    SELECT
      c.id AS company_id,
      COUNT(rb.id)::bigint AS ticket_count,
      COALESCE(SUM(rb.price), 0)::double precision AS sales_total
    FROM "Companies" c
    JOIN "Gares" g ON g."companyId" = c.id
    JOIN "ProgrammationTrajets" pt ON pt.depart = g.id
    JOIN "Reservations" r ON r."trajetId" = pt.id
    JOIN "ReservationBus" rb ON rb."reservationId" = r.id
    LEFT JOIN "Payment" p ON p.id = rb."paymentId"
    WHERE c."recruitedByUserId" = v_user_id
      AND rb."type" = 'voyage'
      AND rb."createdAt" >= v_from
      AND rb."createdAt" <= v_to
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
    GROUP BY c.id
  ),
  recruiter_earned AS (
    SELECT
      e.company_id,
      COALESCE(SUM(e.earned_amount), 0)::double precision AS commission_earned,
      COALESCE(SUM(e.ticket_count), 0)::bigint AS commission_tickets
    FROM public._stakeholder_commission_earned_rows(v_country_id) e
    WHERE e.stakeholder_role = 'recruiter'
      AND e.beneficiary_user_id = v_user_id
    GROUP BY e.company_id
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'companyId', rc.id,
      'name', rc.name,
      'isActive', rc."isActive",
      'managerName', rc."managerName",
      'countryId', rc."countryId",
      'countryName', rc.country_name,
      'currency', COALESCE(rc.currency, 'XOF'),
      'ticketCount', COALESCE(bs.ticket_count, 0),
      'salesTotal', COALESCE(bs.sales_total, 0),
      'commissionEarned', COALESCE(re.commission_earned, 0),
      'commissionTickets', COALESCE(re.commission_tickets, 0)
    )
    ORDER BY rc.name
  ), '[]'::jsonb)
  INTO v_companies
  FROM recruited rc
  LEFT JOIN booking_stats bs ON bs.company_id = rc.id
  LEFT JOIN recruiter_earned re ON re.company_id = rc.id;

  v_commissions := public.get_my_stakeholder_commission_dashboard(v_country_id);

  RETURN jsonb_build_object(
    'dateFrom', v_from,
    'dateTo', v_to,
    'countryId', v_country_id,
    'companies', v_companies,
    'commissions', v_commissions
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_stakeholder_country_users(p_country_id uuid)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  email text,
  roles text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')::text,
    u.email::text,
    COALESCE(array_agg(DISTINCT r.name) FILTER (WHERE r.name IS NOT NULL), ARRAY[]::text[])
  FROM "Users" u
  JOIN "UserRoles" ur ON ur."userId" = u.id
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."countryId" = p_country_id
     OR r.name IN (
       'admin_pays',
       'master',
       'master_independant',
       'vendeur_master',
       'vendeur_independant',
       'demarcheur',
       'super_admin'
     )
  GROUP BY u.id, u."firstName", u."lastName", u.email
  ORDER BY 2 NULLS LAST, u.email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_demarcheur() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_demarcheur_dashboard(timestamptz, timestamptz) TO authenticated;
