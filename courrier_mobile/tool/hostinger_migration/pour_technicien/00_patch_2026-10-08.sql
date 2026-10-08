-- ============================================================================
-- Patch du 2026-10-08 : ventes colis faites HORS LIGNE.
--
-- Corrige les « doublons » côté finance : une vente faite sans réseau et
-- synchronisée le lendemain changeait de date et de numéro. Après ce patch :
-- - une même vente ne peut plus être enregistrée deux fois ;
-- - une vente hors ligne garde sa date réelle et reste identifiée comme
--   « hors ligne » (filtre dans l'app, mention HL sur le journal de vente) ;
-- - la clôture de caisse affiche la répartition en ligne / hors ligne.
--
-- Idempotent : sans risque à rejouer. À exécuter AVANT d'installer la
-- nouvelle version de l'application (sinon la synchronisation hors ligne et
-- la clôture de caisse échouent : fonctions introuvables).
--
--   psql "$HOSTINGER_DB_URL" -f 00_patch_2026-10-08.sql
-- ============================================================================

ALTER TABLE public.colis_autonomes ADD COLUMN IF NOT EXISTS offline_local_id text;
ALTER TABLE public.colis_autonomes ADD COLUMN IF NOT EXISTS offline_created_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS colis_autonomes_offline_local_id_key
  ON public.colis_autonomes (offline_local_id) WHERE offline_local_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS colis_autonomes_company_sale_date_idx
  ON public.colis_autonomes (company_id, (COALESCE(offline_created_at, created_at)));

-- ---------------------------------------------------------------------------
-- Enregistrement idempotent (en ligne ET hors ligne)
--   p_offline_created_at NULL     -> vente EN LIGNE avec clé anti-doublon
--   p_offline_created_at non NULL -> vente HORS LIGNE (heure réelle appareil)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_colis_autonome_offline(
  p_offline_local_id text,
  p_offline_created_at timestamptz,
  p_company_id uuid,
  p_gare_depart_id uuid,
  p_gare_destination_id uuid,
  p_nom_expediteur text,
  p_telephone_expediteur text,
  p_nom_destinataire text,
  p_telephone_destinataire text,
  p_description_contenu text,
  p_poids_kg double precision,
  p_nombre_pieces integer,
  p_montant_fret double precision,
  p_nature_ids uuid[],
  p_valeur_marchandise double precision DEFAULT NULL,
  p_pourcentage_percu double precision DEFAULT NULL,
  p_bus_id uuid DEFAULT NULL,
  p_custom_fields jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_local_id text := NULLIF(btrim(COALESCE(p_offline_local_id, '')), '');
  v_existing public.colis_autonomes%ROWTYPE;
  v_result jsonb;
  v_colis_id uuid;
  v_created timestamptz;
  v_opened timestamptz;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF v_local_id IS NULL THEN RAISE EXCEPTION 'Identifiant hors-ligne manquant'; END IF;

  -- Anti-doublon : la vente a déjà été créée (synchro rejouée, ou
  -- enregistrement en ligne réussi côté serveur mais réponse perdue).
  SELECT * INTO v_existing FROM public.colis_autonomes WHERE offline_local_id = v_local_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.vendeur_id IS DISTINCT FROM v_user_id THEN
      RAISE EXCEPTION 'Ce colis a déjà été synchronisé par un autre agent';
    END IF;
    RETURN jsonb_build_object(
      'id', v_existing.id,
      'statutColis', v_existing.statut_colis,
      'montantFret', v_existing.montant_fret,
      'alreadySynced', true,
      'isOffline', v_existing.offline_created_at IS NOT NULL,
      'offlineCreatedAt', v_existing.offline_created_at
    );
  END IF;

  v_result := public.register_colis_autonome(
    p_company_id => p_company_id,
    p_gare_depart_id => p_gare_depart_id,
    p_gare_destination_id => p_gare_destination_id,
    p_nom_expediteur => p_nom_expediteur,
    p_telephone_expediteur => p_telephone_expediteur,
    p_nom_destinataire => p_nom_destinataire,
    p_telephone_destinataire => p_telephone_destinataire,
    p_description_contenu => p_description_contenu,
    p_poids_kg => p_poids_kg,
    p_nombre_pieces => p_nombre_pieces,
    p_montant_fret => p_montant_fret,
    p_nature_ids => p_nature_ids,
    p_valeur_marchandise => p_valeur_marchandise,
    p_pourcentage_percu => p_pourcentage_percu,
    p_bus_id => p_bus_id,
    p_custom_fields => p_custom_fields
  );

  v_colis_id := (v_result ->> 'id')::uuid;

  IF p_offline_created_at IS NULL THEN
    -- Vente en ligne : seule la clé anti-doublon est enregistrée.
    UPDATE public.colis_autonomes SET offline_local_id = v_local_id WHERE id = v_colis_id;
    RETURN v_result || jsonb_build_object('alreadySynced', false, 'isOffline', false);
  END IF;

  -- Vente hors ligne : heure réelle de l'appareil, jamais dans le futur ni
  -- avant l'ouverture de la caisse qui encaisse la vente (empêche de
  -- reporter une vente sur une journée déjà clôturée en reculant l'horloge).
  SELECT c.opened_at INTO v_opened
  FROM public.mouvements_caisse m
  JOIN public.caisses_gares c ON c.id = m.caisse_id
  WHERE m.colis_autonome_id = v_colis_id AND m.type_mouvement = 'encaissement_colis'
  ORDER BY m.created_at
  LIMIT 1;

  v_created := LEAST(p_offline_created_at, now());
  IF v_opened IS NOT NULL THEN v_created := GREATEST(v_created, v_opened); END IF;

  UPDATE public.colis_autonomes
  SET offline_local_id = v_local_id, offline_created_at = v_created
  WHERE id = v_colis_id;

  UPDATE public.mouvements_caisse
  SET note = 'Vente colis guichet (hors-ligne)'
  WHERE colis_autonome_id = v_colis_id AND type_mouvement = 'encaissement_colis';

  RETURN v_result || jsonb_build_object('alreadySynced', false, 'isOffline', true, 'offlineCreatedAt', v_created);
END;
$function$;

REVOKE ALL ON FUNCTION public.register_colis_autonome_offline(text, timestamptz, uuid, uuid, uuid, text, text, text, text, text, double precision, integer, double precision, uuid[], double precision, double precision, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_colis_autonome_offline(text, timestamptz, uuid, uuid, uuid, text, text, text, text, text, double precision, integer, double precision, uuid[], double precision, double precision, uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- Liste des colis : origine de la vente + recherche par référence provisoire
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_colis_autonomes(p_company_id uuid, p_statut text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_rows jsonb;
  v_full_access boolean;
  v_gare_ids uuid[];
  v_own_sales_role boolean;
  v_search text := NULLIF(trim(p_search), '');
  v_search_digits text;
  v_search_local text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;

  v_full_access := public._colis_stats_full_access(v_user_id, p_company_id)
    OR public.has_company_role(p_company_id, ARRAY['emballeur_gare','chargeur_gare','distributeur_gare']);

  IF NOT v_full_access THEN
    SELECT array_agg(ur."gareId") INTO v_gare_ids
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = p_company_id
      AND ur."gareId" IS NOT NULL
      AND r.name IN ('comptable_gare', 'emballeur_gare', 'chargeur_gare', 'distributeur_gare');
  END IF;

  IF NOT v_full_access AND v_gare_ids IS NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND ur."companyId" = p_company_id
        AND r.name IN ('vendeur', 'vendeur_gare', 'chauffeur', 'controleur')
    ) INTO v_own_sales_role;
    IF NOT v_own_sales_role THEN
      RAISE EXCEPTION 'Droits insuffisants';
    END IF;
  END IF;

  v_search_digits := NULLIF(regexp_replace(COALESCE(v_search, ''), '[^0-9]', '', 'g'), '');
  -- Référence provisoire imprimée hors ligne : « ABOI-1A2B3C4D » -> les 8
  -- caractères après le dernier tiret = fin de offline_local_id.
  v_search_local := lower(regexp_replace(COALESCE(v_search, ''), '^.*-', ''));
  IF length(v_search_local) < 6 THEN v_search_local := NULL; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub."createdAt" DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      ca.id,
      ca.statut_colis AS "statutColis",
      ca.numero_recu AS "numeroRecu",
      ca.nom_expediteur AS "nomExpediteur",
      ca.telephone_expediteur AS "telephoneExpediteur",
      ca.nom_destinataire AS "nomDestinataire",
      ca.telephone_destinataire AS "telephoneDestinataire",
      ca.description_contenu AS "descriptionContenu",
      ca.poids_kg AS "poidsKg",
      ca.nombre_pieces AS "nombrePieces",
      ca.montant_fret AS "montantFret",
      ca.valeur_marchandise AS "valeurMarchandise",
      ca.created_at AS "createdAt",
      ca.updated_at AS "updatedAt",
      (ca.offline_created_at IS NOT NULL) AS "isOffline",
      ca.offline_created_at AS "offlineCreatedAt",
      CASE WHEN ca.offline_created_at IS NOT NULL THEN ca.offline_local_id END AS "offlineLocalId",
      gd.name AS "gareDepart",
      gdest.name AS "gareDestination",
      COALESCE(ca.custom_fields, '{}'::jsonb) AS "customFields",
      COALESCE(
        (SELECT jsonb_agg(n.libelle ORDER BY n.libelle)
         FROM public.colis_natures_selectionnees cns
         JOIN public.colis_natures n ON n.id = cns.nature_id
         WHERE cns.colis_id = ca.id),
        '[]'::jsonb
      ) AS "natures"
    FROM public.colis_autonomes ca
    JOIN "Gares" gd ON gd.id = ca.gare_depart_id
    JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id
    WHERE ca.company_id = p_company_id
      AND (p_statut IS NULL OR ca.statut_colis = p_statut)
      AND (
        v_full_access
        OR (v_gare_ids IS NOT NULL AND ca.gare_depart_id = ANY(v_gare_ids))
        OR (v_gare_ids IS NULL AND ca.vendeur_id = v_user_id)
      )
      AND (
        v_search IS NULL
        OR ca.numero_recu ILIKE '%' || v_search || '%'
        OR ca.nom_expediteur ILIKE '%' || v_search || '%'
        OR ca.nom_destinataire ILIKE '%' || v_search || '%'
        OR public.colis_public_reference_sql(ca.id) ILIKE '%' || regexp_replace(v_search, '^[Cc][Ll]-?', '') || '%'
        OR (v_search_local IS NOT NULL AND ca.offline_local_id ILIKE '%' || v_search_local || '%')
        OR (v_search_digits IS NOT NULL AND (
          regexp_replace(ca.telephone_expediteur, '\D', '', 'g') ILIKE '%' || v_search_digits || '%'
          OR regexp_replace(ca.telephone_destinataire, '\D', '', 'g') ILIKE '%' || v_search_digits || '%'
        ))
      )
    ORDER BY ca.created_at DESC
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 5000), 1)
  ) sub;

  RETURN v_rows;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Détail d'un colis : origine de la vente
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_colis_autonome_detail(p_colis_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user_id uuid := public.current_app_user_id(); v_colis public.colis_autonomes%ROWTYPE; v_row jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RETURN NULL; END IF;
  IF NOT (
    public.is_company_role_user(v_user_id, v_colis.company_id)
    OR public.has_gare_colis_access(v_user_id, v_colis.company_id, v_colis.gare_depart_id, v_colis.gare_destination_id)
  ) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  SELECT jsonb_build_object('id', ca.id, 'companyId', ca.company_id, 'statutColis', ca.statut_colis, 'numeroRecu', ca.numero_recu, 'nomExpediteur', ca.nom_expediteur, 'telephoneExpediteur', ca.telephone_expediteur, 'nomDestinataire', ca.nom_destinataire, 'telephoneDestinataire', ca.telephone_destinataire, 'descriptionContenu', ca.description_contenu, 'poidsKg', ca.poids_kg, 'nombrePieces', ca.nombre_pieces, 'montantFret', ca.montant_fret, 'valeurMarchandise', ca.valeur_marchandise, 'sourceVente', ca.source_vente, 'createdAt', ca.created_at, 'updatedAt', ca.updated_at, 'gareDepartId', ca.gare_depart_id, 'gareDestinationId', ca.gare_destination_id, 'gareDepart', gd.name, 'gareDepartPhone', gd.phone, 'gareDestination', gdest.name, 'gareDestinationPhone', gdest.phone, 'companyName', c.name, 'companyPhone', c.phone, 'photoPath', ca.photo_path,
    'isOffline', ca.offline_created_at IS NOT NULL,
    'offlineCreatedAt', ca.offline_created_at,
    'offlineLocalId', CASE WHEN ca.offline_created_at IS NOT NULL THEN ca.offline_local_id END,
    'customFields', COALESCE(ca.custom_fields, '{}'::jsonb),
    'natureIds', COALESCE((SELECT jsonb_agg(cns.nature_id) FROM public.colis_natures_selectionnees cns WHERE cns.colis_id = ca.id), '[]'::jsonb),
    'natures', COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb))
  INTO v_row FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id JOIN "Companies" c ON c.id = ca.company_id WHERE ca.id = p_colis_id;
  RETURN v_row;
END; $function$;

-- ---------------------------------------------------------------------------
-- Journal de vente : date réelle de vente + filtre origine + sous-totaux HL
-- (nouveau paramètre -> on supprime l'ancienne signature pour éviter toute
-- ambiguïté d'appel par paramètres nommés)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_colis_sales_journal(uuid, timestamptz, timestamptz, uuid);

CREATE OR REPLACE FUNCTION public.get_colis_sales_journal(
  p_company_id uuid,
  p_date_from timestamptz,
  p_date_to timestamptz DEFAULT NULL,
  p_vendeur_id uuid DEFAULT NULL,
  p_origin text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_full_access boolean;
  v_gerant_gares uuid[];
  v_date_to timestamptz := COALESCE(p_date_to, p_date_from + interval '1 day');
  v_origin text := NULLIF(lower(btrim(COALESCE(p_origin, ''))), '');
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF v_origin IS NOT NULL AND v_origin NOT IN ('online', 'offline') THEN
    RAISE EXCEPTION 'Origine invalide (online | offline)';
  END IF;

  v_full_access := public._colis_stats_full_access(v_user_id, p_company_id);
  IF NOT v_full_access THEN
    v_gerant_gares := public._colis_stats_gerant_gares(v_user_id, p_company_id);
    IF v_gerant_gares IS NULL THEN
      p_vendeur_id := v_user_id;
    END IF;
  END IF;

  WITH filtered AS (
    SELECT
      ca.id,
      ca.numero_recu,
      COALESCE(ca.offline_created_at, ca.created_at) AS sale_at,
      ca.created_at AS synced_at,
      (ca.offline_created_at IS NOT NULL) AS is_offline,
      ca.offline_local_id,
      ca.nom_expediteur,
      ca.nom_destinataire,
      ca.montant_fret,
      ca.valeur_marchandise,
      ca.vendeur_id,
      gdest.name AS gare_destination
    FROM public.colis_autonomes ca
    JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id
    WHERE ca.company_id = p_company_id
      AND ca.statut_colis <> 'annule'
      AND (v_gerant_gares IS NULL OR ca.gare_depart_id = ANY(v_gerant_gares))
      AND (p_vendeur_id IS NULL OR ca.vendeur_id = p_vendeur_id)
      AND COALESCE(ca.offline_created_at, ca.created_at) >= p_date_from
      AND COALESCE(ca.offline_created_at, ca.created_at) < v_date_to
      AND (v_origin IS NULL
           OR (v_origin = 'offline' AND ca.offline_created_at IS NOT NULL)
           OR (v_origin = 'online' AND ca.offline_created_at IS NULL))
  ),
  by_vendeur AS (
    SELECT
      f.vendeur_id,
      COALESCE(NULLIF(TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), ''), u.username, 'Agent inconnu') AS vendeur_name,
      u.username AS vendeur_username,
      jsonb_agg(
        jsonb_build_object(
          'id', f.id,
          'numeroRecu', f.numero_recu,
          'createdAt', f.sale_at,
          'syncedAt', f.synced_at,
          'isOffline', f.is_offline,
          'offlineLocalId', CASE WHEN f.is_offline THEN f.offline_local_id END,
          'nomExpediteur', f.nom_expediteur,
          'nomDestinataire', f.nom_destinataire,
          'montantFret', f.montant_fret,
          'valeurMarchandise', f.valeur_marchandise,
          'gareDestination', f.gare_destination
        )
        ORDER BY f.sale_at
      ) AS colis,
      COUNT(*) AS cnt,
      COALESCE(SUM(f.montant_fret), 0) AS total_frais,
      COALESCE(SUM(f.valeur_marchandise), 0) AS total_valeur,
      COUNT(*) FILTER (WHERE f.is_offline) AS offline_cnt,
      COALESCE(SUM(f.montant_fret) FILTER (WHERE f.is_offline), 0) AS offline_frais
    FROM filtered f
    LEFT JOIN "Users" u ON u.id = f.vendeur_id
    GROUP BY f.vendeur_id, u."firstName", u."lastName", u.username
  )
  SELECT jsonb_build_object(
    'groups', COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'vendeurId', bv.vendeur_id,
          'vendeurName', bv.vendeur_name,
          'vendeurUsername', bv.vendeur_username,
          'colis', bv.colis,
          'count', bv.cnt,
          'totalFrais', bv.total_frais,
          'totalValeur', bv.total_valeur,
          'offlineCount', bv.offline_cnt,
          'offlineFrais', bv.offline_frais
        )
        ORDER BY bv.vendeur_name
      ) FROM by_vendeur bv),
      '[]'::jsonb
    ),
    'grandCount', (SELECT COALESCE(SUM(cnt), 0) FROM by_vendeur),
    'grandTotalFrais', (SELECT COALESCE(SUM(total_frais), 0) FROM by_vendeur),
    'grandTotalValeur', (SELECT COALESCE(SUM(total_valeur), 0) FROM by_vendeur),
    'grandOfflineCount', (SELECT COALESCE(SUM(offline_cnt), 0) FROM by_vendeur),
    'grandOfflineFrais', (SELECT COALESCE(SUM(offline_frais), 0) FROM by_vendeur),
    'origin', v_origin,
    'fullAccess', v_full_access,
    'gareScope', v_gerant_gares IS NOT NULL
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_colis_sales_journal(uuid, timestamptz, timestamptz, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_colis_sales_journal(uuid, timestamptz, timestamptz, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Statistiques : date réelle de vente + filtre origine + compteurs HL
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_colis_autonome_stats(uuid, uuid, uuid, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION public.get_colis_autonome_stats(
  p_company_id uuid,
  p_vendeur_id uuid DEFAULT NULL,
  p_gare_depart_id uuid DEFAULT NULL,
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL,
  p_origin text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_result jsonb;
  v_full_access boolean;
  v_gerant_gares uuid[];
  v_origin text := NULLIF(lower(btrim(COALESCE(p_origin, ''))), '');
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF v_origin IS NOT NULL AND v_origin NOT IN ('online', 'offline') THEN
    RAISE EXCEPTION 'Origine invalide (online | offline)';
  END IF;

  v_full_access := public._colis_stats_full_access(v_user_id, p_company_id);
  IF NOT v_full_access THEN
    v_gerant_gares := public._colis_stats_gerant_gares(v_user_id, p_company_id);
    IF v_gerant_gares IS NULL THEN
      p_vendeur_id := v_user_id;
    END IF;
  END IF;

  WITH base AS (
    SELECT ca.*,
           COALESCE(ca.offline_created_at, ca.created_at) AS sale_at,
           (ca.offline_created_at IS NOT NULL) AS is_offline
    FROM public.colis_autonomes ca
    WHERE ca.company_id = p_company_id
      AND (p_gare_depart_id IS NULL OR ca.gare_depart_id = p_gare_depart_id)
      AND (p_date_from IS NULL OR COALESCE(ca.offline_created_at, ca.created_at) >= p_date_from)
      AND (p_date_to IS NULL OR COALESCE(ca.offline_created_at, ca.created_at) < p_date_to)
      AND (v_origin IS NULL
           OR (v_origin = 'offline' AND ca.offline_created_at IS NOT NULL)
           OR (v_origin = 'online' AND ca.offline_created_at IS NULL))
  ),
  filtered AS (
    SELECT * FROM base
    WHERE (v_gerant_gares IS NULL OR gare_depart_id = ANY(v_gerant_gares))
      AND (p_vendeur_id IS NULL OR vendeur_id = p_vendeur_id)
  ),
  mine AS (
    SELECT * FROM base WHERE vendeur_id = v_user_id
  )
  SELECT jsonb_build_object(
    'total', (SELECT COUNT(*) FROM filtered),
    'montantTotal', (SELECT COALESCE(SUM(montant_fret), 0) FROM filtered),
    'today', (SELECT COUNT(*) FROM filtered WHERE sale_at::date = now()::date),
    'montantToday', (SELECT COALESCE(SUM(montant_fret), 0) FROM filtered WHERE sale_at::date = now()::date),
    'thisMonth', (SELECT COUNT(*) FROM filtered WHERE date_trunc('month', sale_at) = date_trunc('month', now())),
    'montantThisMonth', (SELECT COALESCE(SUM(montant_fret), 0) FROM filtered WHERE date_trunc('month', sale_at) = date_trunc('month', now())),
    'delivered', (SELECT COUNT(*) FROM filtered WHERE statut_colis = 'livre'),
    'pending', (SELECT COUNT(*) FROM filtered WHERE statut_colis <> 'livre'),
    'offlineTotal', (SELECT COUNT(*) FROM filtered WHERE is_offline),
    'offlineMontant', (SELECT COALESCE(SUM(montant_fret), 0) FROM filtered WHERE is_offline),
    'mineTotal', (SELECT COUNT(*) FROM mine),
    'mineMontantTotal', (SELECT COALESCE(SUM(montant_fret), 0) FROM mine),
    'origin', v_origin,
    'fullAccess', v_full_access,
    'gareScope', v_gerant_gares IS NOT NULL
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_colis_autonome_stats(uuid, uuid, uuid, timestamptz, timestamptz, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Ventilation en ligne / hors ligne d'une session de caisse (clôture)
-- Mêmes droits que list_station_cash_movements.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_station_cash_origin_summary(p_caisse_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id uuid;
  v_result jsonb;
BEGIN
  SELECT public.station_cash_gare_company_id(c.gare_id) INTO v_company_id
  FROM public.caisses_gares c
  WHERE c.id = p_caisse_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;
  IF NOT (
    public.is_super_admin()
    OR public.can_operate_station_cash(v_company_id)
    OR public.can_validate_station_reversal(v_company_id)
  ) THEN
    RAISE EXCEPTION 'Acces mouvements refuse';
  END IF;

  SELECT jsonb_build_object(
    'onlineCount',   COUNT(*) FILTER (WHERE ca.offline_created_at IS NULL),
    'onlineMontant', COALESCE(SUM(m.montant) FILTER (WHERE ca.offline_created_at IS NULL), 0),
    'offlineCount',  COUNT(*) FILTER (WHERE ca.offline_created_at IS NOT NULL),
    'offlineMontant', COALESCE(SUM(m.montant) FILTER (WHERE ca.offline_created_at IS NOT NULL), 0)
  ) INTO v_result
  FROM public.mouvements_caisse m
  JOIN public.colis_autonomes ca ON ca.id = m.colis_autonome_id
  WHERE m.caisse_id = p_caisse_id
    AND m.type_mouvement = 'encaissement_colis';

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_station_cash_origin_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_station_cash_origin_summary(uuid) TO authenticated;
