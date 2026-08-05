-- Bug : le detail "Montant du jour par agence" (bouton Detail sur Accueil)
-- renvoyait le nom + le nombre de colis de TOUTES les agences de la
-- compagnie a n'importe quel role ayant simplement acces a la compagnie
-- (is_company_role_user -- inclut vendeur/controleur), meme quand les
-- montants tombaient a 0 pour les agences hors de son propre perimetre. Un
-- vendeur simple decouvrait ainsi l'existence et le nombre d'agences de la
-- compagnie, une fuite d'info non voulue. Cote client (home_screen.dart),
-- le bouton "Detail" est deja masque hors owner/super_admin/admin_pays --
-- on applique ici la meme restriction cote serveur (defense en profondeur :
-- la RPC ne doit pas repondre a un appel direct hors UI).
--
-- Avant : is_company_role_user() en garde d'entree (large), puis un repli
-- "vendeur_filter = soi-meme" ou "gerant_gares" pour les roles non
-- full-access -- ce repli est supprime : ce detail par agence est reserve a
-- owner/super_admin/admin_pays, point.
--
-- Applique en base le 2026-08-05 (kqudaqtydimjclwaihqr, projet "Tibus 1.0").

CREATE OR REPLACE FUNCTION public._colis_gare_breakdown_access(p_user_id uuid, p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner'])
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      JOIN "Users" u ON u.id = ur."userId"
      JOIN "Companies" c ON c."countryId" = ur."countryId"
      WHERE u."auth_user_id" = auth.uid()
        AND c.id = p_company_id
        AND r.name = 'admin_pays'
    );
$function$;

CREATE OR REPLACE FUNCTION public.get_colis_today_by_gare(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public._colis_gare_breakdown_access(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO v_result
  FROM (
    SELECT
      g.id AS "gareId",
      g.name AS "gareName",
      COUNT(ca.id) AS count,
      COALESCE(SUM(ca.montant_fret), 0) AS montant
    FROM public."Gares" g
    LEFT JOIN public.colis_autonomes ca
      ON ca.gare_depart_id = g.id
      AND ca.company_id = p_company_id
      AND ca.created_at::date = now()::date
    WHERE g."companyId" = p_company_id
      AND g.name <> '__CASH_SESSION_HUB__'
      AND g.name NOT LIKE '\_\_%'
    GROUP BY g.id, g.name
    ORDER BY montant DESC, g.name
  ) t;

  RETURN v_result;
END;
$function$;
