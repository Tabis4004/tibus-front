-- Lecture scoped-compagnie pour bordereau_lot_numerotation, sans ajouter de
-- colonne company_id : on réutilise station_cash_gare_company_id(gare_id)
-- (même pattern que caisses_gares_select, migration antérieure), qui dérive
-- la compagnie en direct depuis Gares — évite toute copie qui pourrait se
-- désynchroniser si une gare change de compagnie.
--
-- Écriture volontairement NON ouverte à authenticated : le seul écrivain
-- légitime reste le trigger assign_bordereau_numero_lot() (SECURITY
-- DEFINER, owner postgres, BYPASSRLS) — ouvrir l'écriture laisserait
-- n'importe quel utilisateur authentifié d'une compagnie modifier le
-- compteur d'une autre gare (la table n'a pas de colonne company_id pour
-- restreindre un UPDATE à "sa" compagnie sans cette même fonction).

CREATE POLICY bordereau_lot_numerotation_select
  ON public.bordereau_lot_numerotation
  FOR SELECT
  TO authenticated
  USING (
    public.is_super_admin()
    OR public.is_company_role_user(
      public.current_app_user_id(),
      public.station_cash_gare_company_id(gare_depart_id)
    )
  );
