-- Un admin pays n'administre QUE son pays. Corrige les 3 policies qui
-- utilisaient has_global_droit (aveugle au pays) et permettaient à un
-- admin_pays d'écrire dans les données d'autres pays.
--
-- La lecture publique n'est PAS touchée : les voyageurs continuent de voir
-- tous les pays, villes, compagnies actives, itinéraires et voyages.
-- (companies_select, countries_select_public, cities_select_public inchangées.)

-- 1. Companies : un admin_pays ne crée des compagnies QUE dans son pays
--    (avant : has_global_droit('manage_company') = n'importe quel pays).
DROP POLICY IF EXISTS companies_insert ON public."Companies";
CREATE POLICY companies_insert ON public."Companies"
  FOR INSERT TO authenticated
  WITH CHECK (
    is_super_admin()
    OR has_country_role("countryId", ARRAY['admin_pays'])
  );

-- 2. Countries : création/suppression réservées au super_admin ;
--    un admin_pays ne peut modifier QUE la fiche de son propre pays.
DROP POLICY IF EXISTS countries_write_admin ON public."Countries";

CREATE POLICY countries_insert_admin ON public."Countries"
  FOR INSERT TO authenticated
  WITH CHECK (is_super_admin());

CREATE POLICY countries_update_admin ON public."Countries"
  FOR UPDATE TO authenticated
  USING (is_super_admin() OR has_country_role(id, ARRAY['admin_pays']))
  WITH CHECK (is_super_admin() OR has_country_role(id, ARRAY['admin_pays']));

CREATE POLICY countries_delete_admin ON public."Countries"
  FOR DELETE TO authenticated
  USING (is_super_admin());

-- 3. Cities : un admin_pays ne gère QUE les villes de son pays.
DROP POLICY IF EXISTS cities_write_admin ON public."Cities";
CREATE POLICY cities_write_admin ON public."Cities"
  FOR ALL TO authenticated
  USING (is_super_admin() OR has_country_role("countryId", ARRAY['admin_pays']))
  WITH CHECK (is_super_admin() OR has_country_role("countryId", ARRAY['admin_pays']));
