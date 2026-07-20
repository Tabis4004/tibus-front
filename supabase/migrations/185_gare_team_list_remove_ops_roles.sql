-- L'équipe de gare n'affichait pas les nouveaux rôles opérationnels
-- (emballeur_gare / chargeur_gare / distributeur_gare, migration 182) :
-- list_gare_team_members et remove_gare_team_role filtraient encore sur les
-- 4 anciens rôles — un membre ajouté avec succès (ex. emballeur) restait
-- donc invisible dans la liste, et non supprimable.
-- APPLIQUÉE EN PRODUCTION (apply_migration gare_team_list_remove_ops_roles).

CREATE OR REPLACE FUNCTION public.list_gare_team_members(p_gare_id uuid)
 RETURNS TABLE(user_id uuid, "firstName" text, "lastName" text, email text, role_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    AND r.name IN (
      'vendeur_gare', 'controleur_gare', 'comptable_gare', 'gerant_gare',
      'emballeur_gare', 'chargeur_gare', 'distributeur_gare'
    )
  ORDER BY u."lastName", u."firstName", r.name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_gare_team_role(p_gare_id uuid, p_user_id uuid, p_role_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_role uuid;
BEGIN
  IF NOT public.can_manage_gare(p_gare_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF p_role_name NOT IN (
    'vendeur_gare', 'controleur_gare', 'comptable_gare', 'gerant_gare', 'gestionnaire_gare',
    'emballeur_gare', 'chargeur_gare', 'distributeur_gare'
  ) THEN
    RAISE EXCEPTION 'Rôle gare non autorisé';
  END IF;
  SELECT r.id INTO v_role FROM public."Role" r WHERE r.name = p_role_name;
  DELETE FROM public."UserRoles"
  WHERE "userId" = p_user_id AND "roleId" = v_role AND "gareId" = p_gare_id;
END;
$function$;
