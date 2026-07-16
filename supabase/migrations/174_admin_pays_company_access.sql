-- Un admin_pays autorisé (droit "manage_feature_modules", même droit qui
-- affiche déjà le bouton "Gérer" côté front — voir
-- canManageCompanyFeatureModules) doit pouvoir accéder aux données d'une
-- compagnie de son pays comme le ferait un membre de cette compagnie
-- (owner/comptable_compagnie/controleur/vendeur), sans quoi le bouton
-- "Gérer" ouvre la console owner mais toutes les requêtes y échouent avec
-- "Droits insuffisants" (is_company_role_user ne connaît que les rôles
-- rattachés directement à la compagnie, pas les rôles pays).
--
-- is_company_role_user est le point de passage central : 25 fonctions
-- SECURITY DEFINER s'appuient dessus (colis autonome, bordereaux, caisse
-- gare, SMS, etc.). has_company_droit encapsule déjà exactement la même
-- logique admin_pays+pays+droit que le front (voir has_company_droit,
-- migration antérieure) — on la réutilise plutôt que de dupliquer la
-- vérification.
--
-- Note : la console owner "historique" (bus, voyages, ventes billetterie)
-- utilise en partie des vérifications inline plus anciennes, pas cette
-- fonction — un admin_pays peut donc encore y rencontrer "Droits
-- insuffisants" sur certains écrans plus anciens ; à traiter au cas par cas
-- si signalé.

CREATE OR REPLACE FUNCTION public.is_company_role_user(p_user_id uuid, p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM "UserRoles" ur
    JOIN "Role" ro ON ro.id = ur."roleId"
    WHERE ur."userId" = p_user_id
      AND ur."companyId" = p_company_id
      AND ro.name IN ('owner', 'comptable_compagnie', 'controleur', 'vendeur')
  )
  OR public.has_company_droit(p_company_id, 'manage_feature_modules');
$function$;
