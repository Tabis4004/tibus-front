-- Bug : l'écran Stats (courrier_mobile) réutilisait list_company_station_gares
-- pour peupler le filtre "Gare" — mais cette RPC est réservée aux rôles qui
-- opèrent une caisse (vendeur / vendeur_gare / chauffeur, voir
-- can_operate_station_cash, migration 148) et lève une exception
-- "Acces gares caisse refuse" pour un owner/comptable_compagnie qui n'a
-- aucun de ces rôles. Côté client, _loadFilterOptions charge vendeurs et
-- gares avec un seul Future.wait : l'exception sur les gares fait échouer
-- TOUT le Future.wait, donc le filtre Agent (pourtant chargé avec succès)
-- reste lui aussi vide/masqué. D'où le rapport : "impossible de voir la
-- liste des gares ET des agents" pour un compte owner.
--
-- Nouvelle RPC dédiée aux stats, avec la même porte d'accès que
-- get_colis_autonome_stats / list_company_colis_vendeurs
-- (is_company_role_user, cf. migration 174) plutôt que
-- can_operate_station_cash — un owner/comptable_compagnie/controleur/vendeur
-- peut légitimement filtrer les stats colis par gare sans pouvoir ouvrir une
-- caisse.

CREATE OR REPLACE FUNCTION public.list_company_gares_for_stats(p_company_id uuid)
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT g.id, g.name::text
  FROM public."Gares" g
  WHERE g."companyId" = p_company_id
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY g.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_gares_for_stats(uuid) TO authenticated;
