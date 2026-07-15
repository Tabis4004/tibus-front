-- 159_droit_driven_geography_and_modules_access.sql
--
-- Backfill de changements déjà appliqués en direct sur la base via le MCP
-- Supabase (apply_migration), pour garder l'historique des migrations
-- aligné avec le schéma réel.
--
-- Contexte produit : la page admin "Rôles & Permissions" affichait les
-- droits (Role.droits) en lecture seule sans qu'ils pilotent réellement quoi
-- que ce soit côté frontend — deux systèmes de permissions déconnectés
-- coexistaient (droits déclaratifs vs vérifications de rôle codées en dur).
-- On corrige en :
--   1. Ajoutant has_country_droit(), miroir de has_company_droit() existant,
--      pour les ressources scopées pays (Cities) plutôt que compagnie.
--   2. Ajoutant les droits manage_geography (admin_pays : voir/ajouter des
--      villes de son pays) et manage_feature_modules (owner + admin_pays :
--      activer/désactiver les modules d'une compagnie) — accordés par défaut
--      aux rôles qui en bénéficiaient déjà en pratique, pour ne rien casser.
--   3. Basculant les RLS de Cities et CompanyFeatureModules sur ces droits
--      plutôt que sur des noms de rôle en dur — ce qui les rend réellement
--      éditables par le super_admin depuis l'écran Rôles & Permissions.
--      Corrige au passage un vrai trou : la policy d'écriture sur
--      CompanyFeatureModules n'incluait pas le rôle "owner".
--   4. Ajoutant admin_update_role_droits(), RPC super_admin uniquement qui
--      alimente le nouvel écran Rôles & Permissions éditable.

-- ─── has_country_droit ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.has_country_droit(p_country_id uuid, p_droit text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      JOIN "Users" u ON u.id = ur."userId"
      WHERE u."auth_user_id" = auth.uid()
        AND ur."companyId" IS NULL
        AND ur."countryId" = p_country_id
        AND p_droit = ANY (r.droits)
    );
$function$;

-- Prédicat utilisé DANS les policies RLS (comme has_company_droit /
-- has_country_role) : doit rester exécutable par anon et authenticated,
-- sinon l'évaluation de la policy échoue pour tout le monde.
REVOKE EXECUTE ON FUNCTION public.has_country_droit(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_country_droit(uuid, text) TO anon, authenticated;

-- ─── Nouveaux droits ────────────────────────────────────────────────────

UPDATE "Role"
SET droits = array_append(droits, 'manage_geography')
WHERE name IN ('admin_pays', 'super_admin') AND NOT ('manage_geography' = ANY(droits));

UPDATE "Role"
SET droits = array_append(droits, 'manage_feature_modules')
WHERE name IN ('owner', 'admin_pays', 'super_admin')
  AND NOT ('manage_feature_modules' = ANY(droits));

-- ─── RLS pilotée par les droits ─────────────────────────────────────────

DROP POLICY IF EXISTS "cities_write_admin" ON "Cities";
CREATE POLICY "cities_write_admin" ON "Cities"
  FOR ALL
  USING (public.has_country_droit("countryId", 'manage_geography'))
  WITH CHECK (public.has_country_droit("countryId", 'manage_geography'));

DROP POLICY IF EXISTS "company_feature_modules_write" ON "CompanyFeatureModules";
CREATE POLICY "company_feature_modules_write" ON "CompanyFeatureModules"
  FOR ALL
  USING (public.has_company_droit("companyId", 'manage_feature_modules'))
  WITH CHECK (public.has_company_droit("companyId", 'manage_feature_modules'));

-- ─── RPC d'édition des droits (backend de l'écran Rôles & Permissions) ──

CREATE OR REPLACE FUNCTION public.admin_update_role_droits(p_role_name text, p_droits text[])
 RETURNS TABLE(id uuid, name text, droits text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_id uuid;
  v_clean_droits text[];
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Accès réservé au super_admin';
  END IF;

  IF p_role_name IS NULL OR trim(p_role_name) = '' THEN
    RAISE EXCEPTION 'Nom de rôle requis';
  END IF;

  SELECT r.id INTO v_role_id FROM "Role" r WHERE r.name = p_role_name;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Rôle introuvable: %', p_role_name;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT d), ARRAY[]::text[])
  INTO v_clean_droits
  FROM unnest(COALESCE(p_droits, ARRAY[]::text[])) AS d
  WHERE d IS NOT NULL AND trim(d) <> '';

  UPDATE "Role"
  SET droits = v_clean_droits
  WHERE "Role".id = v_role_id;

  RETURN QUERY
  SELECT r.id, r.name, r.droits FROM "Role" r WHERE r.id = v_role_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_update_role_droits(text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_role_droits(text, text[]) TO authenticated;
