-- 213 — Embarquement se referme sur le propriétaire et les rôles de gare
--
-- Décision exploitant : seuls le propriétaire de la compagnie et les rôles
-- RATTACHÉS À UNE GARE tiennent le portillon. Les rôles à portée compagnie
-- (controleur, vendeur, chauffeur) perdent l'accès au module.
--
-- Le raisonnement tient au modèle de fraude. Un rôle à portée compagnie n'est
-- rattaché à aucune gare : il pouvait donc ouvrir une session sur n'importe
-- quel itinéraire de la compagnie, donc choisir le tarif appliqué à tout un
-- départ. C'était la dernière latitude laissée au terrain sur le montant.
-- Désormais un gérant, un contrôleur ou un comptable de gare ne voit que les
-- itinéraires partant de SA gare, et le propriétaire — seul à avoir un motif
-- légitime de voir toute la compagnie — garde une vue complète.
--
-- Portée exacte après cette migration :
--   can_use_embarquement      : super_admin, owner, gerant_gare,
--                               controleur_gare, comptable_gare
--   embarquement_sees_all_gares : super_admin, owner uniquement
--   embarquement_my_gares       : la ou les gares du UserRoles.gareId pour
--                                 les trois rôles de gare
--
-- vendeur_gare sort aussi de embarquement_my_gares : il n'est pas dans
-- can_use_embarquement, l'y laisser n'aurait décrit qu'un droit inatteignable.
--
-- Vérifié avant application : can_use_embarquement n'est référencée que par
-- des fonctions embarquement_* (18 au total). Le scanner web de Tibus et la
-- billetterie ont leurs propres prédicats — restreindre ici ne leur retire
-- rien.
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-23
-- (nom côté Supabase : embarquement_acces_owner_et_roles_gare).

CREATE OR REPLACE FUNCTION public.can_use_embarquement(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY[
         'owner', 'gerant_gare', 'controleur_gare', 'comptable_gare'
       ]);
$$;

CREATE OR REPLACE FUNCTION public.embarquement_sees_all_gares(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner']);
$$;

CREATE OR REPLACE FUNCTION public.embarquement_my_gares(p_company_id uuid)
RETURNS TABLE(id uuid, name text, city_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF public.embarquement_sees_all_gares(p_company_id) THEN
    RETURN QUERY
    SELECT g.id, g.name::text, COALESCE(c.name::text, '')
    FROM public."Gares" g
    LEFT JOIN public."Cities" c ON c.id = g."cityId"
    WHERE g."companyId" = p_company_id
      AND g."isActive"
      AND g.name <> '__CASH_SESSION_HUB__'
      AND g.name NOT LIKE '\_\_%'
    ORDER BY g.name;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT g.id, g.name::text, COALESCE(c.name::text, '')
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Gares" g ON g.id = ur."gareId"
  LEFT JOIN public."Cities" c ON c.id = g."cityId"
  WHERE ur."userId" = v_user
    AND ur."companyId" = p_company_id
    AND ur."gareId" IS NOT NULL
    AND r.name IN ('gerant_gare', 'controleur_gare', 'comptable_gare')
    AND g."isActive"
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY 2;
END;
$$;
