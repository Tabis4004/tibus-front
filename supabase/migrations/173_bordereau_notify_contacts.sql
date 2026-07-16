-- Partage du bordereau (BL) par WhatsApp/email : jusqu'ici les seuls contacts
-- disponibles sur un colis sont l'expéditeur et le destinataire, qui n'ont
-- rien à voir avec le bordereau (document interne au transporteur). Le
-- besoin réel est de partager le BL avec d'autres utilisateurs du module
-- (propriétaire de la compagnie, contrôleur), pour suivi/contrôle — d'où
-- cette liste de contacts, dérivée de UserRoles/Role/Users, même schéma que
-- list_gare_team_members (migration 145).

CREATE OR REPLACE FUNCTION public.list_bordereau_notify_contacts(p_company_id uuid)
RETURNS TABLE (
  user_id uuid,
  "firstName" text,
  "lastName" text,
  email text,
  phone text,
  role_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public._assert_bordereau_access(p_company_id);

  RETURN QUERY
  SELECT DISTINCT ON (u.id)
    u.id, u."firstName"::text, u."lastName"::text, u.email::text, u.phone::text, r.name::text
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Users" u ON u.id = ur."userId"
  WHERE ur."companyId" = p_company_id
    AND r.name IN ('owner', 'controleur')
  ORDER BY u.id, (r.name = 'owner') DESC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_bordereau_notify_contacts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bordereau_notify_contacts(uuid) TO authenticated;
