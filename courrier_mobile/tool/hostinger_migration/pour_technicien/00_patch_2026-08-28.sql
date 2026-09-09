-- ============================================================================
-- Patch du 2026-08-28 : tables et fonctions absentes de l'export initial du
-- 2026-08-09/08-23, trouvées en croisant les corps de fonctions déjà
-- migrées avec les tables/fonctions réellement définies sur l'instance.
-- Idempotent pour les fonctions (CREATE OR REPLACE). Les CREATE TABLE
-- échoueront si déjà appliqués -- normal, à ignorer si c'est le cas.
--
-- À exécuter directement sur Hostinger : psql "$HOSTINGER_DB_URL" -f 00_patch_2026-08-28.sql
-- Puis importer les données correspondantes (voir 00_patch_data_2026-08-28/*.csv
-- si fourni, sinon relancer le pipeline complet 02->03->04/05 avec les
-- scripts corrigés de pour_moi/).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tables utilisées par des fonctions déjà migrées (create_bordereau_
--    livraison, mark_bordereau_charge/arrive, submit_station_cash_reversal,
--    record_station_cash_movement, list_station_cash_movements,
--    get_open_station_cash_for_user...) mais jamais ajoutées au schéma
--    exporté -- cause du crash "relation reversements_comptables does not
--    exist" sur l'écran Caisse physique guichet.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.bordereaux_livraison (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "reference" text NOT NULL,
  "company_id" uuid NOT NULL,
  "gare_depart_id" uuid,
  "gare_destination_id" uuid,
  "bus_id" uuid,
  "statut" text NOT NULL DEFAULT 'ouvert'::text,
  "created_by" uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "closed_at" timestamp with time zone,
  "numero_lot" integer,
  "ville_depart_id" uuid NOT NULL,
  "date_lot" date NOT NULL DEFAULT CURRENT_DATE,
  PRIMARY KEY (id),
  FOREIGN KEY (company_id) REFERENCES "Companies"(id) ON DELETE CASCADE,
  FOREIGN KEY (bus_id) REFERENCES "Bus"(id),
  FOREIGN KEY (created_by) REFERENCES "Users"(id),
  FOREIGN KEY (gare_depart_id) REFERENCES "Gares"(id),
  FOREIGN KEY (gare_destination_id) REFERENCES "Gares"(id),
  FOREIGN KEY (ville_depart_id) REFERENCES "Cities"(id),
  CHECK ((statut = ANY (ARRAY['ouvert'::text, 'clos'::text, 'charge'::text, 'arrive'::text])))
);
ALTER TABLE public.bordereaux_livraison ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.bordereau_colis (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "bordereau_id" uuid NOT NULL,
  "colis_id" uuid NOT NULL,
  "added_at" timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (bordereau_id, colis_id),
  FOREIGN KEY (colis_id) REFERENCES colis_autonomes(id) ON DELETE CASCADE,
  FOREIGN KEY (bordereau_id) REFERENCES bordereaux_livraison(id) ON DELETE CASCADE
);
ALTER TABLE public.bordereau_colis ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.reversements_comptables (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "caisse_id" uuid NOT NULL,
  "comptable_id" uuid,
  "montant_reverse" integer NOT NULL,
  "statut_validation" text NOT NULL DEFAULT 'en_attente'::text,
  "soumis_par" uuid NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "validated_at" timestamp with time zone,
  PRIMARY KEY (id),
  FOREIGN KEY (caisse_id) REFERENCES caisses_gares(id) ON DELETE RESTRICT,
  FOREIGN KEY (comptable_id) REFERENCES "Users"(id) ON DELETE SET NULL,
  FOREIGN KEY (soumis_par) REFERENCES "Users"(id) ON DELETE RESTRICT,
  CHECK ((montant_reverse > 0)),
  CHECK ((statut_validation = ANY (ARRAY['en_attente'::text, 'approuve_recu'::text])))
);
CREATE INDEX IF NOT EXISTS reversements_caisse_idx ON public.reversements_comptables USING btree (caisse_id, created_at DESC);
CREATE INDEX IF NOT EXISTS reversements_statut_idx ON public.reversements_comptables USING btree (statut_validation, created_at DESC);
ALTER TABLE public.reversements_comptables ENABLE ROW LEVEL SECURITY;

-- NB : ticket_id/colis_id référencent "ReservationBus" dans le schéma
-- d'origine (billetterie, hors périmètre SIS). Toujours NULL pour les
-- lignes SIS (vérifié sur Tibus 1.0) -- gardées nullable, sans FK, puisque
-- "ReservationBus" n'existe pas et n'a pas à exister chez vous.
CREATE TABLE IF NOT EXISTS public.mouvements_caisse (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "caisse_id" uuid NOT NULL,
  "type_mouvement" text NOT NULL,
  "montant" integer NOT NULL,
  "solde_apres" integer NOT NULL,
  "ticket_id" uuid,
  "colis_id" uuid,
  "effectue_par" uuid NOT NULL,
  "reversement_id" uuid,
  "note" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "colis_autonome_id" uuid,
  PRIMARY KEY (id),
  FOREIGN KEY (colis_autonome_id) REFERENCES colis_autonomes(id) ON DELETE SET NULL,
  FOREIGN KEY (reversement_id) REFERENCES reversements_comptables(id) ON DELETE SET NULL,
  FOREIGN KEY (effectue_par) REFERENCES "Users"(id) ON DELETE RESTRICT,
  FOREIGN KEY (caisse_id) REFERENCES caisses_gares(id) ON DELETE RESTRICT,
  CHECK ((montant > 0)),
  CHECK ((solde_apres >= 0)),
  CHECK ((type_mouvement = ANY (ARRAY['encaissement_billet'::text, 'encaissement_colis'::text, 'decaissement_annulation'::text, 'reversement_comptable'::text])))
);
CREATE INDEX IF NOT EXISTS mouvements_caisse_caisse_idx ON public.mouvements_caisse USING btree (caisse_id, created_at DESC);
ALTER TABLE public.mouvements_caisse ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 2. Table de référence globale utilisée par can_assign_role (policies
--    userroles_insert/update/delete). 30 lignes chez Tibus 1.0, à exporter
--    en entier comme "Role" (voir 03_export_sis_data.sh corrigé).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public."RoleAssignmentRules" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "assignerRoleId" uuid NOT NULL,
  "assignableRoleId" uuid NOT NULL,
  PRIMARY KEY (id),
  UNIQUE ("assignerRoleId", "assignableRoleId"),
  FOREIGN KEY ("assignableRoleId") REFERENCES "Role"(id) ON DELETE CASCADE DEFERRABLE,
  FOREIGN KEY ("assignerRoleId") REFERENCES "Role"(id) ON DELETE CASCADE DEFERRABLE
);

-- ---------------------------------------------------------------------------
-- 3. Fonctions invoquées implicitement par les policies RLS de UserRoles /
--    Companies / Bus / Gares -- jamais tracées par le grep .rpc()/.from()
--    de l'app puisqu'aucun appel explicite ne les mentionne.
--
--    IMPORTANT, corrige une fausse piste suivie plus tôt dans cette
--    migration : is_company_staff N'APPELLE PAS can_sell_for_company ni
--    is_in_master_network. Elle n'a besoin QUE de is_super_admin() et
--    has_company_role(), déjà présentes chez vous. Les tables
--    "MasterVendorNetwork" et "IndependentSellerCompanies" ne sont PAS
--    nécessaires pour SIS -- ne pas les créer.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_company_staff(p_company_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY[
      'owner', 'comptable_compagnie', 'controleur', 'vendeur'
    ]);
$function$;

CREATE OR REPLACE FUNCTION public.can_assign_role(p_assignable_role_id uuid, p_company_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1
      FROM "UserRoles" ur_assigner
      JOIN "Role" r_assigner ON r_assigner.id = ur_assigner."roleId"
      JOIN "RoleAssignmentRules" rar ON rar."assignerRoleId" = r_assigner.id
      JOIN "Users" u ON u.id = ur_assigner."userId"
      JOIN "Role" r_target ON r_target.id = p_assignable_role_id
      WHERE u."auth_user_id" = auth.uid()
        AND rar."assignableRoleId" = p_assignable_role_id
        AND (
          (r_target.scope = 'platform' AND ur_assigner."companyId" IS NULL)
          OR (
            r_target.scope = 'company'
            AND r_assigner.name = 'owner'
            AND ur_assigner."companyId" = p_company_id
          )
        )
    );
$function$;
