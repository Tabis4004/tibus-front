-- Génère le script SQL complet (fonctions + triggers) du périmètre
-- colis/guichet/bordereau utilisé par courrier_mobile pour le client SIS,
-- prêt à rejouer tel quel sur la nouvelle instance Supabase self-hosted
-- (Hostinger).
--
-- Comment l'utiliser :
--   1. Ouvrir Tibus 1.0 (kqudaqtydimjclwaihqr) > SQL Editor sur le
--      dashboard Supabase (ou `psql` avec la connection string du projet).
--   2. Exécuter CE fichier tel quel.
--   3. Copier le contenu de la seule colonne résultat ("script") dans le
--      fichier ../pour_technicien/functions_and_triggers.sql (déjà présent,
--      vide -- à remplir). C'est le paquet que le technicien exécutera sur
--      la nouvelle instance Hostinger (ordre indifférent : CREATE OR
--      REPLACE FUNCTION ne valide pas l'existence des fonctions/tables
--      appelées à l'intérieur du corps tant qu'elles ne sont pas réellement
--      exécutées).
--
-- Périmètre : liste de fonctions établie en croisant tous les .rpc(...) /
-- .from(...) appelés par courrier_mobile (lib/data/services/*.dart) avec
-- la fermeture de leurs dépendances internes (fonctions -> fonctions
-- qu'elles appellent -> tables qu'elles touchent), tracée directement sur
-- Tibus 1.0 le 2026-08-09, RE-VÉRIFIÉE le 2026-08-23 (re-grep de tous les
-- .rpc()/.from() du code actuel contre cette liste : un seul écart trouvé,
-- list_company_villes_depart, ajoutée ci-dessous -- elle référence aussi
-- la table "Cities", absente jusqu'ici, ajoutée à 02_table_schema_pg_dump.sh
-- et 03_export_sis_data.sh, cf. commentaire dédié plus bas).
--
-- Complétée le 2026-08-23 (suite) : restriction de visibilité gare-scopée
-- pour les colis (un agent ne voit/opère plus que sur sa gare de DÉPART,
-- plus jamais la destination) -- appliquée directement sur Tibus 1.0 à
-- list_colis_autonomes et has_gare_colis_access (déjà dans cette liste,
-- pas de nouvelle entrée nécessaire), et côté app (station_cash_screen.dart)
-- en basculant l'écran d'ouverture de caisse de list_company_gares_for_stats
-- vers list_company_station_gares -- fonction déjà existante côté base mais
-- pas encore appelée par le code, ajoutée à la liste ci-dessous.
--
-- Exclut volontairement : codes promo, parrainage,
-- fidélité voyageur (claim_referral_signup, list_owner_promo_codes,
-- get_traveler_loyalty_context, validate_loyalty_redemption) — features
-- "propriétaire" transverses avec la billetterie bus, jamais demandées par
-- SIS (logiciel métier interne, pas d'accès client aux réservations).
--
-- process_loyalty_on_colis EST conservée bien qu'elle appartienne au même
-- système : register_colis_autonome l'appelle inconditionnellement (PERFORM
-- public.process_loyalty_on_colis(...)), mais elle se dégrade en no-op
-- silencieux (EXCEPTION WHEN OTHERS THEN NULL, vérifié dans son corps) si
-- les tables CompanyLoyaltySettings / TravelerLoyaltyBalance /
-- LoyaltyPointLedger n'existent pas — d'où leur ABSENCE volontaire de la
-- liste de tables (voir 02_table_schema_pg_dump.sh). Plus simple que
-- d'éditer register_colis_autonome, aucun risque fonctionnel.
--
-- CORRIGÉ le 2026-08-28 : la méthode de traçage (.rpc()/.from() de l'app +
-- fermeture fonction->fonction) est AVEUGLE aux fonctions invoquées par les
-- POLICIES RLS des tables du périmètre (elles ne sont jamais "appelées"
-- explicitement, Postgres les exécute implicitement à chaque ligne). Deux
-- angles morts trouvés en croisant avec les policies de UserRoles/Companies/
-- Bus/Gares (voir sis_schema_tables.sql) :
--   - is_company_staff : utilisée par userroles_select, companies_select,
--     bus_select, gares_select. Dépendances (is_super_admin,
--     has_company_role) déjà dans cette liste -- aucune nouvelle table.
--   - can_assign_role : utilisée par userroles_insert/update/delete
--     (l'app fait bien un .from('UserRoles').insert(...) direct dans
--     auth_service.dart, donc la policy s'applique réellement). Dépend en
--     plus de la table "RoleAssignmentRules" (30 lignes, référentiel
--     global comme "Role" -- ajoutée à 02_table_schema_pg_dump.sh et
--     03_export_sis_data.sh).
-- Vérifié sur Tibus 1.0 : is_company_staff n'appelle NI can_sell_for_company
-- NI is_in_master_network -- ces deux-là (+ "MasterVendorNetwork" et
-- "IndependentSellerCompanies") ne sont PAS des dépendances de SIS, malgré
-- ce qui avait été supposé au départ. is_in_master_network() vaut d'ailleurs
-- littéralement `select false;` aujourd'hui côté Tibus 1.0 (stub), donc même
-- si elle était un jour appelée, elle ne toucherait aucune table.

with fn(name) as (
  values
    -- Appelées directement par l'app (courrier_mobile/lib/data/services/*.dart)
    ('list_my_notifications'),('count_unread_my_notifications'),('mark_my_notification_read'),
    ('mark_all_my_notifications_read'),('list_colis_autonomes'),('get_colis_autonome_detail'),
    ('register_colis_autonome'),('get_colis_prix_min'),('update_colis_autonome_statut'),
    ('resolve_colis_retrait_code'),('deliver_colis_autonome'),('set_colis_autonome_photo'),
    ('get_company_colis_settings'),('get_colis_autonome_stats'),('get_colis_today_by_gare'),
    -- Écriture des réglages colis autonome (admin_service.dart) -- absentes
    -- jusqu'au 2026-09-08 : seule la LECTURE (get_company_colis_settings)
    -- avait été migrée, pas l'écriture -- cause du bug "les réglages ne
    -- s'appliquent pas" chez SIS (l'écran affichait l'état actuel, mais
    -- toute modification échouait silencieusement, fonction introuvable).
    ('update_company_colis_price_settings'),('update_company_colis_ui_config'),
    ('upsert_colis_nature'),('delete_colis_nature'),
    ('list_company_colis_vendeurs'),('get_colis_sales_journal'),('list_company_gares_for_stats'),
    ('list_company_villes_depart'),('list_company_station_gares'),
    ('get_open_station_cash_for_user'),('open_station_cash_register'),('list_station_cash_movements'),
    ('submit_station_cash_reversal'),('close_station_cash_register'),('subscribe_to_colis_tracking'),
    ('unsubscribe_from_colis_tracking'),('get_contact_options'),('list_bordereaux_livraison'),
    ('create_bordereau_livraison'),('mark_bordereau_charge'),('mark_bordereau_arrive'),
    ('get_bordereau_livraison'),('list_colis_disponibles_bordereau'),('add_colis_to_bordereau'),
    ('remove_colis_from_bordereau'),('close_bordereau_livraison'),('list_bordereau_notify_contacts'),
    ('register_device_token'),('unregister_device_token'),
    -- Fermeture des dépendances internes (fonctions -> fonctions, niveaux 1-3)
    ('_assert_bordereau_access'),('_assert_lot_access'),('_colis_gare_breakdown_access'),
    ('_colis_notification_recipients'),('_colis_stats_full_access'),('_colis_stats_gerant_gares'),
    ('_create_colis_notifications'),('_owner_company_id'),('assert_seller_cash_departure_gare'),
    ('build_colis_sms_message'),('build_colis_sms_payload'),('can_operate_station_cash'),
    ('can_validate_station_reversal'),('company_colis_module_enabled'),
    ('company_colis_sms_owner_config_enabled'),('compute_colis_prix_min'),('current_app_user_id'),
    ('has_company_role'),('has_gare_colis_access'),('has_gare_role'),('is_company_role_user'),
    ('is_super_admin'),('process_loyalty_on_colis'),('record_station_cash_movement'),
    ('resolve_seller_company_id'),('station_cash_gare_company_id'),('colis_public_reference_sql'),
    ('colis_sms_enabled_for_statut'),('has_company_droit'),('normalize_phone_digits'),
    ('company_colis_sms_step_allowed'),
    -- Invoquées implicitement par les policies RLS des tables du périmètre,
    -- jamais via .rpc()/.from() explicite -- voir commentaire daté 2026-08-28
    -- ci-dessus.
    ('is_company_staff'),('can_assign_role'),
    -- Fonctions appelées par les TRIGGERS des tables du périmètre (voir
    -- 02_table_schema_pg_dump.sh) — indispensables : elles s'exécutent
    -- automatiquement à l'INSERT/UPDATE, pas via un appel explicite de l'app.
    ('assign_colis_numero_recu'),('colis_gare_prefix'),('trg_colis_autonomes_module_guard'),
    ('assert_company_module'),('company_has_module'),('_company_module_flag'),
    ('enforce_single_admin_pays_per_country'),('get_country_admin_pays_holder'),
    ('validate_user_role_assignment'),('_is_gare_scoped_role'),
    ('sync_colis_autonome_from_module_d'),('tg_seed_company_colis_natures'),
    ('_seed_company_colis_natures'),('tg_seed_company_expense_categories'),
    ('_seed_company_expense_categories'),('tg_validate_gare_city_in_company_country')
),
fn_defs as (
  select p.proname, pg_get_functiondef(p.oid) as def
  from pg_proc p join fn on fn.name = p.proname and p.pronamespace = 'public'::regnamespace
),
trg_defs as (
  select t.tgname, c.relname, pg_get_triggerdef(t.oid) as def
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  where c.relname in ('Companies','CompanyFeatureModules','Gares','UserRoles','colis_autonomes')
    and not t.tgisinternal
)
select
  (select string_agg(
     E'-- ==== FUNCTION ' || proname || E' ====\n' || def || ';',
     E'\n\n' order by proname
   ) from fn_defs)
  || E'\n\n-- ============================= TRIGGERS =============================\n\n'
  || (select string_agg(
       E'-- ==== TRIGGER ' || tgname || ' ON "' || relname || E'" ====\n'
       || 'DROP TRIGGER IF EXISTS ' || tgname || ' ON "' || relname || E'";\n'
       || def || ';',
       E'\n\n' order by tgname
     ) from trg_defs)
  as script;
