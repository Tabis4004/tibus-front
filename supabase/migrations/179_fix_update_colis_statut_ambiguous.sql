-- « Remettre au destinataire » KO : deliver_colis_autonome appelle en
-- interne update_colis_autonome_statut(v_colis.id, 'livre') — appel à
-- 2 arguments. Depuis l'ajout du bus de convoi, la base contient DEUX
-- surcharges : (uuid, text) héritée de la migration 138 et (uuid, text,
-- uuid DEFAULT NULL). L'appel à 2 arguments est donc ambigu →
-- « function public.update_colis_autonome_statut(uuid, unknown) is not
-- unique » (42725).
--
-- Correctif : supprimer la surcharge obsolète à 2 paramètres. Tous les
-- appels à 2 arguments (dont celui de deliver_colis_autonome) se résolvent
-- alors sans ambiguïté sur la version à 3 paramètres, p_bus_id prenant sa
-- valeur par défaut NULL.

DROP FUNCTION IF EXISTS public.update_colis_autonome_statut(uuid, text);
