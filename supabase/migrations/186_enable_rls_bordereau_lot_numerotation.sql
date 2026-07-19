-- Sécurité : bordereau_lot_numerotation avait RLS désactivée (table de
-- compteur interne — un next_seq par gare de départ, utilisée uniquement
-- par le trigger assign_bordereau_numero_lot(), SECURITY DEFINER, migration
-- 182). Sans RLS, la table était intégralement exposée en lecture/écriture
-- via l'API PostgREST à n'importe quel détenteur de la clé anon.
--
-- Alignement exact sur les deux tables sœurs (colis_numerotation_gares,
-- bordereau_numerotation) : RLS activée, AUCUNE policy définie. Avec RLS
-- activée et zéro policy, Postgres refuse par défaut tout accès aux rôles
-- normaux (anon, authenticated) — seul le propriétaire des fonctions
-- SECURITY DEFINER (qui a BYPASSRLS) peut lire/écrire. C'est volontaire ET
-- plus strict que "authenticated autorisé" : un compteur de numérotation
-- n'a aucune raison d'être lu ou modifié directement par un client API,
-- authentifié ou non — toute compagnie authentifiée pourrait sinon
-- perturber la numérotation d'une AUTRE compagnie en écrivant directement
-- dans cette table (elle n'a pas de colonne company_id pour scoper une
-- policy par compagnie). Le trigger reste seul point d'écriture légitime.

ALTER TABLE public.bordereau_lot_numerotation ENABLE ROW LEVEL SECURITY;
