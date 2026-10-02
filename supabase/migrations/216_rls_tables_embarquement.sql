-- 216 — Active RLS sur les 3 tables créées par les migrations 211/212/214
-- sans RLS (alerte Supabase « rls_disabled_in_public » : lisibles ET
-- modifiables par n'importe qui avec la clé anon).
--
-- Ces tables ne sont accédées QUE par des fonctions SECURITY DEFINER
-- appartenant à postgres (propriétaire des tables, donc non soumis à RLS) :
--   embarquement_itineraire_price_log  <- embarquement_log_itineraire_price (trigger)
--   trajet_arret_price_log             <- log_trajet_arret_price (trigger)
--   embarquement_permissions           <- can_use_embarquement, embarquement_my_gares,
--                                         embarquement_grant/revoke/list_permission(s)
-- Aucune app ne les lit en direct. RLS activé SANS policy + révocation des
-- droits directs : ces fonctions continuent de marcher, l'accès direct via
-- PostgREST est fermé.
--
-- Point important pour les deux journaux de prix : ils servent de preuve
-- (cf. CLAUDE.md, compteur indépendant opposable à la billetterie). Ouverts
-- en écriture, n'importe qui pouvait en effacer ou falsifier l'historique.

alter table public.embarquement_itineraire_price_log enable row level security;
alter table public.trajet_arret_price_log            enable row level security;
alter table public.embarquement_permissions          enable row level security;

revoke all on public.embarquement_itineraire_price_log,
              public.trajet_arret_price_log,
              public.embarquement_permissions
  from anon, authenticated;
