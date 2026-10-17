-- ============================================================================
-- Patch du 2026-10-17 (2) : rôle « superviseur » sur plusieurs gares.
--
-- Le owner attribue le rôle superviseur depuis l'écran Équipe de l'app, puis
-- coche les gares supervisées. Le superviseur voit en lecture seule les
-- recettes (stats, journal de vente) et les colis de ces gares uniquement.
-- Aucune modification des rôles existants. Idempotent : sans risque à rejouer.
--
--   psql "$HOSTINGER_DB_URL" -f 00_patch_2026-10-17b.sql
-- ============================================================================

-- 1. Rôle « superviseur » (compagnie), attribuable par le owner.
INSERT INTO public."Role" (name, droits, scope, level, "isSystem", description)
SELECT 'superviseur', ARRAY['view_reports']::text[], 'company', 23, true,
       'Superviseur : consulte les recettes et les colis des gares qui lui sont attribuées (lecture seule)'
WHERE NOT EXISTS (SELECT 1 FROM public."Role" WHERE name = 'superviseur');

INSERT INTO public."RoleAssignmentRules" ("assignerRoleId", "assignableRoleId")
SELECT o.id, s.id
FROM public."Role" o, public."Role" s
WHERE o.name = 'owner' AND s.name = 'superviseur'
  AND NOT EXISTS (
    SELECT 1 FROM public."RoleAssignmentRules" r
    WHERE r."assignerRoleId" = o.id AND r."assignableRoleId" = s.id
  );

-- 2. Gares attribuées au superviseur (autant que le owner le souhaite).
--    Table dédiée : UserRoles n'autorise qu'une ligne par rôle et par
--    compagnie, on n'y touche pas (aucun risque pour les comptes existants).
CREATE TABLE IF NOT EXISTS public.superviseur_gares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public."Companies"(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public."Users"(id) ON DELETE CASCADE,
  gare_id uuid NOT NULL REFERENCES public."Gares"(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (company_id, user_id, gare_id)
);
ALTER TABLE public.superviseur_gares ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.superviseur_gares FROM anon, authenticated;

-- Gares d'un superviseur — vide s'il n'a plus le rôle (retrait du rôle =
-- plus aucun accès, même si les lignes restent).
CREATE OR REPLACE FUNCTION public._superviseur_gares(p_user_id uuid, p_company_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT array_agg(DISTINCT sg.gare_id)
  FROM public.superviseur_gares sg
  WHERE sg.user_id = p_user_id
    AND sg.company_id = p_company_id
    AND EXISTS (
      SELECT 1 FROM "UserRoles" ur JOIN "Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = p_user_id AND ur."companyId" = p_company_id AND r.name = 'superviseur'
    );
$fn$;
REVOKE ALL ON FUNCTION public._superviseur_gares(uuid, uuid) FROM PUBLIC, anon;

-- 3. Recettes (stats, journal de vente, liste des vendeurs) : le superviseur
--    voit ses gares, par le même mécanisme que le gérant de gare.
CREATE OR REPLACE FUNCTION public._colis_stats_gerant_gares(p_user_id uuid, p_company_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT array_agg(DISTINCT g)
  FROM (
    SELECT ur."gareId" AS g
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = p_user_id
      AND ur."companyId" = p_company_id
      AND ur."gareId" IS NOT NULL
      AND r.name IN ('gerant_gare', 'gestionnaire_gare')
    UNION
    SELECT unnest(public._superviseur_gares(p_user_id, p_company_id))
  ) s
  WHERE g IS NOT NULL;
$fn$;

-- 4. Filtre « gare » des stats : seulement ses gares pour un gérant ou un
--    superviseur (toutes pour le owner et le comptable compagnie).
CREATE OR REPLACE FUNCTION public.list_company_gares_for_stats(p_company_id uuid)
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_gares uuid[];
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT public._colis_stats_full_access(v_user_id, p_company_id) THEN
    v_gares := public._colis_stats_gerant_gares(v_user_id, p_company_id);
  END IF;

  RETURN QUERY
  SELECT g.id, g.name::text
  FROM public."Gares" g
  WHERE g."companyId" = p_company_id
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
    AND (v_gares IS NULL OR g.id = ANY(v_gares))
  ORDER BY g.name;
END;
$fn$;

-- 5. Attribution des gares par le owner (remplace la liste complète).
CREATE OR REPLACE FUNCTION public.set_superviseur_gares(p_company_id uuid, p_user_id uuid, p_gare_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_count integer;
BEGIN
  IF NOT (public.is_super_admin() OR public.has_company_role(p_company_id, ARRAY['owner'])) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = p_user_id AND ur."companyId" = p_company_id AND r.name = 'superviseur'
  ) THEN
    RAISE EXCEPTION 'Cet utilisateur n''a pas le role superviseur dans cette compagnie';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_gare_ids, '{}')) gid
    WHERE NOT EXISTS (SELECT 1 FROM "Gares" g WHERE g.id = gid AND g."companyId" = p_company_id)
  ) THEN
    RAISE EXCEPTION 'Gare invalide pour cette compagnie';
  END IF;

  DELETE FROM public.superviseur_gares
  WHERE company_id = p_company_id AND user_id = p_user_id
    AND NOT (gare_id = ANY(COALESCE(p_gare_ids, '{}')));
  INSERT INTO public.superviseur_gares (company_id, user_id, gare_id, created_by)
  SELECT p_company_id, p_user_id, gid, public.current_app_user_id()
  FROM unnest(COALESCE(p_gare_ids, '{}')) gid
  ON CONFLICT (company_id, user_id, gare_id) DO NOTHING;

  SELECT count(*) INTO v_count FROM public.superviseur_gares
  WHERE company_id = p_company_id AND user_id = p_user_id;
  RETURN v_count;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.list_superviseur_gares(p_company_id uuid)
RETURNS TABLE("userId" uuid, "gareId" uuid, "gareName" text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT (public.is_super_admin() OR public.has_company_role(p_company_id, ARRAY['owner'])) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT sg.user_id, sg.gare_id, g.name::text
  FROM public.superviseur_gares sg JOIN "Gares" g ON g.id = sg.gare_id
  WHERE sg.company_id = p_company_id
  ORDER BY g.name;
END;
$fn$;

REVOKE ALL ON FUNCTION public.set_superviseur_gares(uuid, uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_superviseur_gares(uuid, uuid, uuid[]) TO authenticated;
REVOKE ALL ON FUNCTION public.list_superviseur_gares(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_superviseur_gares(uuid) TO authenticated;

-- 6. Accès au module colis + liste des colis de ses gares (lecture seule).
--    Modification ciblée des fonctions existantes (rejouable sans risque).
DO $mig$
DECLARE
  v_def text;
BEGIN
  v_def := pg_get_functiondef('public.is_company_role_user(uuid,uuid)'::regprocedure);
  IF position('''superviseur''' IN v_def) = 0 THEN
    IF v_def !~ 'ro\.name IN \(' THEN
      RAISE EXCEPTION 'is_company_role_user : liste des roles introuvable, migration a adapter';
    END IF;
    EXECUTE regexp_replace(v_def, '(ro\.name IN \([^)]*)\)', '\1, ''superviseur'')');
  END IF;

  v_def := pg_get_functiondef('public.list_colis_autonomes(uuid,text,integer,text)'::regprocedure);
  IF position('_superviseur_gares' IN v_def) = 0 THEN
    IF position('IF NOT v_full_access AND v_gare_ids IS NULL THEN' IN v_def) = 0 THEN
      RAISE EXCEPTION 'list_colis_autonomes : point d''insertion introuvable, migration a adapter';
    END IF;
    EXECUTE regexp_replace(v_def,
      'IF NOT v_full_access AND v_gare_ids IS NULL THEN',
      'IF NOT v_full_access THEN
    SELECT array_agg(DISTINCT x) INTO v_gare_ids
    FROM unnest(COALESCE(v_gare_ids, ''{}''::uuid[]) || COALESCE(public._superviseur_gares(v_user_id, p_company_id), ''{}''::uuid[])) x;
  END IF;
  IF NOT v_full_access AND v_gare_ids IS NULL THEN');
  END IF;
END
$mig$;
