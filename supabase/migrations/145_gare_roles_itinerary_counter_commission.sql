-- =============================================================================
-- Tibus 145 — Rôles par gare, visibilité itinéraires, commissions guichet par tranches
-- =============================================================================

ALTER TABLE public."UserRoles"
  ADD COLUMN IF NOT EXISTS "gareId" uuid REFERENCES public."Gares"(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS user_roles_gare_id_idx ON public."UserRoles" ("gareId");

ALTER TABLE public."ProgrammationTrajets"
  ADD COLUMN IF NOT EXISTS "isSchedulingActive" boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public."ProgrammationTrajets"."isSchedulingActive" IS
  'false = masqué à la programmation des départs ; reste dans les filtres reporting historique';

-- Rôles gare (gerant_gare = gérant ; gestionnaire_gare conservé alias)
INSERT INTO public."Role" ("name", "scope", "level", "isSystem", "description", "droits") VALUES
  ('gerant_gare', 'company', 22, true, 'Gérant de gare — équipe et programmation départs', ARRAY['manage_gare', 'sell_tickets', 'schedule_trips']),
  ('vendeur_gare', 'company', 20, true, 'Vendeur guichet rattaché à une gare', ARRAY['sell_tickets']),
  ('controleur_gare', 'company', 19, true, 'Contrôleur embarquement rattaché à une gare', ARRAY['control_tickets']),
  ('comptable_gare', 'company', 18, true, 'Comptable rattaché à une gare', ARRAY['view_accounting'])
ON CONFLICT ("name") DO UPDATE SET
  "scope" = EXCLUDED."scope",
  "level" = EXCLUDED."level",
  "isSystem" = EXCLUDED."isSystem",
  "description" = EXCLUDED."description",
  "droits" = EXCLUDED."droits";

INSERT INTO public."RoleAssignmentRules" ("assignerRoleId", "assignableRoleId")
SELECT a.id, b.id FROM public."Role" a CROSS JOIN public."Role" b
WHERE a.name IN ('owner', 'gerant_gare', 'gestionnaire_gare')
  AND b.name IN ('vendeur_gare', 'controleur_gare', 'comptable_gare', 'gerant_gare')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public."GareCounterCommissionTiers" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId" uuid NOT NULL REFERENCES public."Companies"(id) ON DELETE CASCADE,
  "gareId" uuid REFERENCES public."Gares"(id) ON DELETE CASCADE,
  "roleScope" text NOT NULL DEFAULT 'vendeur'
    CHECK ("roleScope" IN ('vendeur', 'vendeur_gare')),
  "minAmount" double precision NOT NULL DEFAULT 0 CHECK ("minAmount" >= 0),
  "maxAmount" double precision CHECK ("maxAmount" IS NULL OR "maxAmount" > "minAmount"),
  "commissionType" text NOT NULL CHECK ("commissionType" IN ('fixed', 'percentage')),
  "commissionValue" double precision NOT NULL CHECK ("commissionValue" >= 0),
  "isActive" boolean NOT NULL DEFAULT true,
  "sortOrder" integer NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gare_counter_commission_tiers_company_idx
  ON public."GareCounterCommissionTiers" ("companyId", "gareId", "roleScope", "sortOrder");

ALTER TABLE public."GareCounterCommissionTiers" ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._is_gare_scoped_role(p_role_name text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_role_name IN (
    'gerant_gare', 'gestionnaire_gare', 'vendeur_gare', 'controleur_gare', 'comptable_gare'
  );
$$;

CREATE OR REPLACE FUNCTION public.has_gare_role(p_gare_id uuid, p_roles text[])
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = public.current_app_user_id()
      AND ur."gareId" = p_gare_id
      AND r.name = ANY (p_roles)
  ) OR public.is_super_admin();
$$;

CREATE OR REPLACE FUNCTION public.resolve_user_managed_gare_id(p_user_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := COALESCE(p_user_id, public.current_app_user_id());
  v_gare uuid;
BEGIN
  SELECT ur."gareId" INTO v_gare
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user
    AND ur."gareId" IS NOT NULL
    AND r.name IN ('gerant_gare', 'gestionnaire_gare')
  ORDER BY ur.id
  LIMIT 1;

  IF v_gare IS NOT NULL THEN RETURN v_gare; END IF;

  SELECT g.id INTO v_gare FROM public."Gares" g
  WHERE g."gestionnaireUserId" = v_user
  LIMIT 1;

  RETURN v_gare;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_gare(p_gare_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
BEGIN
  SELECT g."companyId" INTO v_company FROM public."Gares" g WHERE g.id = p_gare_id;
  IF v_company IS NULL THEN RETURN false; END IF;
  IF public.is_super_admin() THEN RETURN true; END IF;
  IF public.has_company_role(v_company, ARRAY['owner', 'comptable_compagnie']) THEN RETURN true; END IF;
  IF public.has_gare_role(p_gare_id, ARRAY['gerant_gare', 'gestionnaire_gare']) THEN RETURN true; END IF;
  IF EXISTS (
    SELECT 1 FROM public."Gares" g
    WHERE g.id = p_gare_id AND g."gestionnaireUserId" = public.current_app_user_id()
  ) THEN RETURN true; END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_trajet_scheduling_active(
  p_trajet_id uuid,
  p_active boolean
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_depart uuid;
BEGIN
  SELECT g."companyId", t.depart INTO v_company, v_depart
  FROM public."ProgrammationTrajets" t
  JOIN public."Gares" g ON g.id = t.depart
  WHERE t.id = p_trajet_id;

  IF v_company IS NULL THEN RAISE EXCEPTION 'Itinéraire introuvable'; END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company, ARRAY['owner', 'comptable_compagnie', 'controleur'])
    OR public.can_manage_gare(v_depart)
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  UPDATE public."ProgrammationTrajets"
  SET "isSchedulingActive" = p_active
  WHERE id = p_trajet_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_trajet_scheduling_active(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_gare_team_members(p_gare_id uuid)
RETURNS TABLE (
  user_id uuid,
  "firstName" text,
  "lastName" text,
  email text,
  role_name text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.can_manage_gare(p_gare_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT u.id, u."firstName"::text, u."lastName"::text, u.email::text, r.name::text
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Users" u ON u.id = ur."userId"
  WHERE ur."gareId" = p_gare_id
    AND r.name IN ('vendeur_gare', 'controleur_gare', 'comptable_gare', 'gerant_gare', 'gestionnaire_gare')
  ORDER BY u."lastName", u."firstName", r.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_gare_team_members(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_gare_team_role_by_email(
  p_gare_id uuid,
  p_email text,
  p_role_name text
)
RETURNS TABLE (id uuid, "firstName" text, "lastName" text, email text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_assigner uuid;
  v_target uuid;
  v_role uuid;
BEGIN
  IF NOT public.can_manage_gare(p_gare_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;

  IF p_role_name NOT IN ('vendeur_gare', 'controleur_gare', 'comptable_gare') THEN
    RAISE EXCEPTION 'Rôle gare non autorisé : %', p_role_name;
  END IF;

  SELECT g."companyId" INTO v_company FROM public."Gares" g WHERE g.id = p_gare_id;
  v_assigner := public.current_app_user_id();

  SELECT r.id INTO v_role FROM public."Role" r WHERE r.name = p_role_name AND r.scope = 'company';
  IF v_role IS NULL THEN RAISE EXCEPTION 'Rôle introuvable'; END IF;

  SELECT u.id INTO v_target FROM public."Users" u WHERE lower(u.email) = lower(trim(p_email)) LIMIT 1;
  IF v_target IS NULL THEN RAISE EXCEPTION 'Aucun utilisateur inscrit avec cet email'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public."UserRoles" ur
    WHERE ur."userId" = v_target AND ur."roleId" = v_role AND ur."gareId" = p_gare_id
  ) THEN
    INSERT INTO public."UserRoles" ("roleId", "userId", "companyId", "gareId", "countryId", "assignedBy")
    VALUES (v_role, v_target, v_company, p_gare_id, NULL, v_assigner);
  END IF;

  RETURN QUERY SELECT u.id, u."firstName"::text, u."lastName"::text, u.email::text
  FROM public."Users" u WHERE u.id = v_target;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_gare_team_role_by_email(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_gare_team_role(
  p_gare_id uuid,
  p_user_id uuid,
  p_role_name text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_role uuid;
BEGIN
  IF NOT public.can_manage_gare(p_gare_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF p_role_name NOT IN ('vendeur_gare', 'controleur_gare', 'comptable_gare', 'gerant_gare', 'gestionnaire_gare') THEN
    RAISE EXCEPTION 'Rôle gare non autorisé';
  END IF;
  SELECT r.id INTO v_role FROM public."Role" r WHERE r.name = p_role_name;
  DELETE FROM public."UserRoles"
  WHERE "userId" = p_user_id AND "roleId" = v_role AND "gareId" = p_gare_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_gare_team_role(uuid, uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.compute_counter_seller_commission(
  p_amount double precision,
  p_company_id uuid,
  p_gare_id uuid DEFAULT NULL,
  p_seller_user_id uuid DEFAULT NULL
)
RETURNS double precision
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_amount double precision := COALESCE(p_amount, 0);
  v_role_scope text := 'vendeur';
  v_tier record;
  v_result double precision := 0;
BEGIN
  IF v_amount <= 0 THEN RETURN 0; END IF;

  IF p_seller_user_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = p_seller_user_id AND r.name = 'vendeur_gare'
  ) THEN
    v_role_scope := 'vendeur_gare';
  END IF;

  SELECT * INTO v_tier
  FROM public."GareCounterCommissionTiers" t
  WHERE t."companyId" = p_company_id
    AND t."isActive" = true
    AND t."roleScope" = v_role_scope
    AND (t."gareId" IS NULL OR t."gareId" = p_gare_id)
    AND v_amount >= t."minAmount"
    AND (t."maxAmount" IS NULL OR v_amount <= t."maxAmount")
  ORDER BY t."gareId" NULLS LAST, t."sortOrder", t."minAmount" DESC
  LIMIT 1;

  IF NOT FOUND THEN RETURN 0; END IF;

  IF v_tier."commissionType" = 'fixed' THEN
    v_result := v_tier."commissionValue";
  ELSE
    v_result := round((v_amount * v_tier."commissionValue" / 100.0)::numeric, 2);
  END IF;

  RETURN GREATEST(v_result, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.compute_counter_seller_commission(double precision, uuid, uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_gare_counter_commission_tiers(
  p_company_id uuid,
  p_gare_id uuid DEFAULT NULL
)
RETURNS SETOF public."GareCounterCommissionTiers"
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR (p_gare_id IS NOT NULL AND public.can_manage_gare(p_gare_id))
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT * FROM public."GareCounterCommissionTiers" t
  WHERE t."companyId" = p_company_id
    AND (p_gare_id IS NULL OR t."gareId" IS NULL OR t."gareId" = p_gare_id)
  ORDER BY t."roleScope", t."gareId" NULLS FIRST, t."sortOrder", t."minAmount";
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_gare_counter_commission_tiers(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_gare_counter_commission_tier(
  p_id uuid,
  p_company_id uuid,
  p_gare_id uuid,
  p_role_scope text,
  p_min_amount double precision,
  p_max_amount double precision,
  p_commission_type text,
  p_commission_value double precision,
  p_is_active boolean DEFAULT true,
  p_sort_order integer DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid := COALESCE(p_id, gen_random_uuid());
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR (p_gare_id IS NOT NULL AND public.can_manage_gare(p_gare_id))
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  INSERT INTO public."GareCounterCommissionTiers" AS t (
    id, "companyId", "gareId", "roleScope", "minAmount", "maxAmount",
    "commissionType", "commissionValue", "isActive", "sortOrder"
  ) VALUES (
    v_id, p_company_id, p_gare_id, p_role_scope, p_min_amount, p_max_amount,
    p_commission_type, p_commission_value, COALESCE(p_is_active, true), COALESCE(p_sort_order, 0)
  )
  ON CONFLICT (id) DO UPDATE SET
    "gareId" = EXCLUDED."gareId",
    "roleScope" = EXCLUDED."roleScope",
    "minAmount" = EXCLUDED."minAmount",
    "maxAmount" = EXCLUDED."maxAmount",
    "commissionType" = EXCLUDED."commissionType",
    "commissionValue" = EXCLUDED."commissionValue",
    "isActive" = EXCLUDED."isActive",
    "sortOrder" = EXCLUDED."sortOrder";

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_gare_counter_commission_tier(
  uuid, uuid, uuid, text, double precision, double precision, text, double precision, boolean, integer
) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_gare_counter_commission_tier(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public."GareCounterCommissionTiers"%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public."GareCounterCommissionTiers" WHERE id = p_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_row."companyId", ARRAY['owner', 'comptable_compagnie'])
    OR (v_row."gareId" IS NOT NULL AND public.can_manage_gare(v_row."gareId"))
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  DELETE FROM public."GareCounterCommissionTiers" WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_gare_counter_commission_tier(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Validation UserRoles.gareId + résolution compagnie staff/gare
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_user_role_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public
AS $function$
DECLARE
  v_scope varchar;
  v_role_name varchar;
BEGIN
  SELECT r.scope, r.name INTO v_scope, v_role_name
  FROM public."Role" r WHERE r.id = NEW."roleId";

  IF v_scope IS NULL THEN
    RAISE EXCEPTION 'Rôle introuvable : %', NEW."roleId";
  END IF;

  IF v_scope = 'platform' AND NEW."companyId" IS NOT NULL THEN
    RAISE EXCEPTION 'Rôle plateforme "%" : companyId doit être NULL', v_role_name;
  END IF;

  IF v_scope = 'company' AND NEW."companyId" IS NULL THEN
    RAISE EXCEPTION 'Rôle compagnie "%" : companyId est obligatoire', v_role_name;
  END IF;

  IF v_role_name = 'admin_pays' AND NEW."countryId" IS NULL THEN
    RAISE EXCEPTION 'admin_pays requiert un countryId';
  END IF;

  IF v_scope = 'platform' AND v_role_name <> 'admin_pays' AND NEW."countryId" IS NOT NULL THEN
    RAISE EXCEPTION 'Rôle "%" : countryId doit être NULL', v_role_name;
  END IF;

  IF public._is_gare_scoped_role(v_role_name) AND NEW."gareId" IS NULL THEN
    RAISE EXCEPTION 'Rôle gare "%" : gareId est obligatoire', v_role_name;
  END IF;

  IF NEW."gareId" IS NOT NULL AND NOT public._is_gare_scoped_role(v_role_name) THEN
    RAISE EXCEPTION 'Seuls les rôles gare peuvent avoir un gareId (rôle "%")', v_role_name;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.current_owner_company_id()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO public
AS $function$
DECLARE
  v_user_id uuid;
  v_active uuid;
  v_fallback uuid;
  v_staff_roles text[] := ARRAY[
    'owner', 'comptable_compagnie', 'controleur',
    'gerant_gare', 'gestionnaire_gare', 'controleur_gare', 'comptable_gare'
  ];
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT u."activeOwnerCompanyId" INTO v_active
  FROM public."Users" u
  WHERE u.id = v_user_id;

  IF v_active IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = v_active
      AND r.name = ANY (v_staff_roles)
  ) THEN
    RETURN v_active;
  END IF;

  SELECT ur."companyId" INTO v_fallback
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user_id
    AND ur."companyId" IS NOT NULL
    AND r.name = ANY (v_staff_roles)
  ORDER BY ur."companyId"
  LIMIT 1;

  RETURN v_fallback;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.resolve_user_managed_gare_id(uuid) TO authenticated;
