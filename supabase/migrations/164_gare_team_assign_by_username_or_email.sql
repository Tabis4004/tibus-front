-- Autonomie du gérant de gare : il peut recruter n'importe quel utilisateur
-- Tibus inscrit dans son équipe de gare (vendeur/contrôleur/comptable de
-- gare) en le cherchant par E-MAIL OU NOM D'UTILISATEUR (avant : e-mail
-- exact uniquement). L'affectation rattache l'utilisateur à la compagnie de
-- la gare (UserRoles.companyId + gareId) — employé de la compagnie de facto,
-- sans passer par l'owner.

CREATE OR REPLACE FUNCTION public.assign_gare_team_role_by_email(p_gare_id uuid, p_email text, p_role_name text)
RETURNS TABLE(id uuid, "firstName" text, "lastName" text, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company uuid;
  v_assigner uuid;
  v_target uuid;
  v_role uuid;
  v_identifier text := lower(btrim(COALESCE(p_email, '')));
BEGIN
  IF NOT public.can_manage_gare(p_gare_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;

  IF p_role_name NOT IN ('vendeur_gare', 'controleur_gare', 'comptable_gare') THEN
    RAISE EXCEPTION 'Rôle gare non autorisé : %', p_role_name;
  END IF;

  IF v_identifier = '' THEN
    RAISE EXCEPTION 'E-mail ou nom d''utilisateur requis';
  END IF;

  SELECT g."companyId" INTO v_company FROM public."Gares" g WHERE g.id = p_gare_id;
  v_assigner := public.current_app_user_id();

  SELECT r.id INTO v_role FROM public."Role" r WHERE r.name = p_role_name AND r.scope = 'company';
  IF v_role IS NULL THEN RAISE EXCEPTION 'Rôle introuvable'; END IF;

  -- E-mail exact OU nom d'utilisateur exact (insensible à la casse).
  SELECT u.id INTO v_target
  FROM public."Users" u
  WHERE lower(u.email) = v_identifier OR lower(u.username) = v_identifier
  ORDER BY (lower(u.email) = v_identifier) DESC
  LIMIT 1;

  IF v_target IS NULL THEN
    RAISE EXCEPTION 'Aucun utilisateur inscrit avec cet e-mail ou nom d''utilisateur';
  END IF;

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
$function$;
