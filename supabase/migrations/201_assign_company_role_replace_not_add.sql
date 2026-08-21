-- Retour terrain (formation SIS, 20/08/2026) : sur le panneau Équipe,
-- attribuer un nouveau rôle à un compte existant (onglet "Compte existant")
-- AJOUTAIT le rôle sans jamais retirer l'ancien -- un compte pouvait ainsi
-- accumuler vendeur + emballeur_gare + chargeur_gare + distributeur_gare +
-- controleur au fil des tentatives (cas vécu : sischargeur@gmail.com, 5
-- rôles cumulés en l'espace de 12 minutes). "Attribuer LE rôle X" doit
-- remplacer l'attribution précédente, pas s'y ajouter -- la suppression
-- manuelle reste possible via la corbeille sur chaque carte de rôle, pour
-- les cas où plusieurs rôles simultanés sont réellement voulus.
--
-- Portée volontairement limitée aux rôles listés dans cette fonction (le
-- même ensemble que OWNER_ASSIGNABLE_TEAM_ROLES côté front) : ne touche
-- jamais owner/traveler/gare_team (vendeur_gare etc., gérés par un autre
-- panneau/RPC) ni les rôles admin_pays/super_admin.
CREATE OR REPLACE FUNCTION public.assign_company_user_role_by_email(p_email text, p_role_name text DEFAULT 'vendeur'::text, p_company_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(id uuid, "firstName" text, "lastName" text, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id uuid;
  v_owner_user_id uuid;
  v_target_user_id uuid;
  v_role_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  v_owner_user_id := public.current_app_user_id();

  IF v_company_id IS NULL OR v_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_role_name NOT IN (
    'vendeur',
    'chauffeur',
    'controleur',
    'comptable_compagnie',
    'gestionnaire_gare',
    'emballeur_gare',
    'chargeur_gare',
    'distributeur_gare'
  ) THEN
    RAISE EXCEPTION 'Role compagnie non autorise : %', p_role_name;
  END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  SELECT r.id INTO v_role_id
  FROM "Role" r
  WHERE r.name = p_role_name AND r.scope = 'company'
  LIMIT 1;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role introuvable : %', p_role_name;
  END IF;

  SELECT u.id INTO v_target_user_id
  FROM "Users" u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Aucun utilisateur inscrit avec cet email';
  END IF;

  -- Remplace : retire les autres rôles compagnie "équipe" déjà attribués à
  -- CE compte sur CETTE compagnie avant d'ajouter le nouveau (jamais
  -- 'owner'/'traveler', hors du domaine de cette liste ci-dessus).
  DELETE FROM "UserRoles" ur
  USING "Role" r
  WHERE ur."roleId" = r.id
    AND ur."userId" = v_target_user_id
    AND ur."companyId" = v_company_id
    AND ur."gareId" IS NULL
    AND r.name IN (
      'vendeur', 'chauffeur', 'controleur', 'comptable_compagnie',
      'gestionnaire_gare', 'emballeur_gare', 'chargeur_gare', 'distributeur_gare'
    )
    AND r.name <> p_role_name;

  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    WHERE ur."userId" = v_target_user_id
      AND ur."roleId" = v_role_id
      AND ur."companyId" = v_company_id
  ) THEN
    INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId", "assignedBy")
    VALUES (v_role_id, v_target_user_id, v_company_id, NULL, v_owner_user_id);
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u."firstName"::text,
    u."lastName"::text,
    u.email::text
  FROM "Users" u
  WHERE u.id = v_target_user_id
  LIMIT 1;
END;
$function$;
