-- CRUD Pays & Villes depuis le panneau super admin (onglet Pays & Villes).
-- Ces policies existent déjà sur la base de prod (créées à la main) ; cette
-- migration les rend reproductibles et idempotentes.
--
-- Lecture : publique (anon + authenticated) — la recherche de trajets et les
-- formulaires publics listent pays et villes.
-- Écriture : super_admin ou droit global manage_country (admin pays).

-- Reprise à l'identique de la définition déjà en prod (droit global = rôle
-- sans companyId). Idempotent via CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION public.has_global_droit(p_droit text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      JOIN "Users" u ON u.id = ur."userId"
      WHERE u."auth_user_id" = auth.uid()
        AND ur."companyId" IS NULL
        AND p_droit = ANY (r.droits)
    );
$function$;

-- ── Countries ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS countries_select_public ON public."Countries";
CREATE POLICY countries_select_public ON public."Countries"
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS countries_write_admin ON public."Countries";
CREATE POLICY countries_write_admin ON public."Countries"
  FOR ALL TO authenticated
  USING (is_super_admin() OR has_global_droit('manage_country'))
  WITH CHECK (is_super_admin() OR has_global_droit('manage_country'));

-- ── Cities ───────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS cities_select_public ON public."Cities";
CREATE POLICY cities_select_public ON public."Cities"
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS cities_write_admin ON public."Cities";
CREATE POLICY cities_write_admin ON public."Cities"
  FOR ALL TO authenticated
  USING (is_super_admin() OR has_global_droit('manage_country'))
  WITH CHECK (is_super_admin() OR has_global_droit('manage_country'));
