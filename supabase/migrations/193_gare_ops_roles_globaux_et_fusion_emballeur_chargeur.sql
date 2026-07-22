-- Suite retours terrain (photos bordereau + rôles) :
--
-- 1) get_bordereau_livraison / list_colis_disponibles_bordereau ne
--    renvoyaient pas numero_recu (le numéro séquentiel par gare, ex.
--    GESC000024) : le mobile devait donc fabriquer une fausse référence
--    CL-XXXXXXXX à partir de l'UUID (voir BordereauColisRow.reference côté
--    Dart), qui n'a AUCUN rapport avec le numéro réellement imprimé sur le
--    reçu du client — d'où l'impression que « le code change à la
--    destination ». Le numéro est en réalité fixé UNE SEULE FOIS à
--    l'enregistrement (assign_colis_numero_recu, trigger BEFORE INSERT) et
--    ne change plus jamais : on corrige ici en exposant numero_recu, le
--    front n'aura plus qu'à l'utiliser avec repli CL- comme partout
--    ailleurs (colisReceiptNumber).
--
-- 2) emballeur_gare et chargeur_gare font le même travail sur le terrain
--    (emballage + impression bordereau, puis scan du bordereau pour
--    confirmer le chargement) : les deux rôles doivent pouvoir faire les
--    deux actions.
--
-- 3) emballeur_gare / chargeur_gare / distributeur_gare deviennent des
--    rôles GLOBAUX à la compagnie (comme vendeur/chauffeur/contrôleur/
--    comptable_compagnie) au lieu d'être rattachés à une seule gare
--    (UserRoles.gareId) : ils doivent pouvoir agir sur toutes les gares de
--    la compagnie, et doivent avoir accès à la liste générale des colis.
--    Rétrocompatibilité : les attributions déjà faites à une gare précise
--    (gareId NOT NULL) continuent de fonctionner, mais restent scopées à
--    cette gare (elles ne sont pas rétroactivement élargies à toute la
--    compagnie).

-- 1) Références réelles dans le bordereau/lot ---------------------------
CREATE OR REPLACE FUNCTION public.get_bordereau_livraison(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
  v_colis jsonb;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_bordereau_access(v_bl.company_id);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', ca.id,
    'statutColis', ca.statut_colis,
    'numeroRecu', ca.numero_recu,
    'nomExpediteur', ca.nom_expediteur,
    'telephoneExpediteur', ca.telephone_expediteur,
    'nomDestinataire', ca.nom_destinataire,
    'telephoneDestinataire', ca.telephone_destinataire,
    'descriptionContenu', ca.description_contenu,
    'poidsKg', ca.poids_kg,
    'nombrePieces', ca.nombre_pieces,
    'montantFret', ca.montant_fret,
    'gareDepart', gd.name,
    'gareDestination', gdest.name,
    'natures', (
      SELECT COALESCE(jsonb_agg(cn.libelle), '[]'::jsonb)
      FROM colis_natures_selectionnees cns
      JOIN colis_natures cn ON cn.id = cns.nature_id
      WHERE cns.colis_id = ca.id
    ),
    'addedAt', bc.added_at
  ) ORDER BY bc.added_at), '[]'::jsonb)
  INTO v_colis
  FROM bordereau_colis bc
  JOIN colis_autonomes ca ON ca.id = bc.colis_id
  JOIN "Gares" gd ON gd.id = ca.gare_depart_id
  JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id
  WHERE bc.bordereau_id = p_bordereau_id;

  RETURN jsonb_build_object(
    'id', v_bl.id,
    'reference', v_bl.reference,
    'numeroLot', v_bl.numero_lot,
    'statut', v_bl.statut,
    'companyId', v_bl.company_id,
    'companyName', (SELECT name FROM "Companies" WHERE id = v_bl.company_id),
    'gareDepart', (SELECT name FROM "Gares" WHERE id = v_bl.gare_depart_id),
    'gareDestination', (SELECT name FROM "Gares" WHERE id = v_bl.gare_destination_id),
    'busPlateNumber', (SELECT "registrationNumber" FROM "Bus" WHERE id = v_bl.bus_id),
    'createdAt', v_bl.created_at,
    'closedAt', v_bl.closed_at,
    'colis', v_colis
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_colis_disponibles_bordereau(p_bordereau_id uuid, p_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
  v_rows jsonb;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_bordereau_access(v_bl.company_id);

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
      ca.pourcentage_percu AS "pourcentagePercu",
      ca.bus_id AS "busId",
      b."registrationNumber" AS "busPlateNumber",
      ca.created_at AS "createdAt",
      ca.updated_at AS "updatedAt",
      gd.name AS "gareDepart",
      gdest.name AS "gareDestination",
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
    LEFT JOIN "Bus" b ON b.id = ca.bus_id
    WHERE ca.company_id = v_bl.company_id
      AND ca.gare_depart_id = v_bl.gare_depart_id
      AND (v_bl.gare_destination_id IS NULL OR ca.gare_destination_id = v_bl.gare_destination_id)
      AND ca.statut_colis <> 'livre'
      AND NOT EXISTS (
        SELECT 1
        FROM bordereau_colis bc
        JOIN bordereaux_livraison bl2 ON bl2.id = bc.bordereau_id
        WHERE bc.colis_id = ca.id AND bl2.statut = 'ouvert'
      )
    ORDER BY ca.created_at DESC
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 200), 500), 1)
  ) sub;

  RETURN v_rows;
END;
$function$;

-- 2) Fusion des permissions emballeur/chargeur ---------------------------
-- _assert_lot_access : ajoute un accès GLOBAL compagnie (has_company_role)
-- en plus du rôle de gare précis déjà géré — nécessaire pour le point 3
-- (rôles globaux) juste en dessous.
CREATE OR REPLACE FUNCTION public._assert_lot_access(p_company_id uuid, p_gare_id uuid, p_roles text[])
RETURNS void
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.current_app_user_id() IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN
    RAISE EXCEPTION 'Module colis autonome non active';
  END IF;
  IF public.is_super_admin() THEN RETURN; END IF;
  IF public.has_company_role(p_company_id, ARRAY['owner','comptable_compagnie']) THEN RETURN; END IF;
  -- Rôle opérationnel (emballeur_gare/chargeur_gare/distributeur_gare)
  -- attribué SANS gare (rôle global compagnie, nouveau schéma) : agit sur
  -- toutes les gares de la compagnie.
  IF public.has_company_role(p_company_id, p_roles) THEN RETURN; END IF;
  -- Rétrocompatibilité : rôle attribué à CETTE gare précise (ancien schéma),
  -- ou gérant de cette gare.
  IF public.has_gare_role(p_gare_id, array_append(p_roles, 'gerant_gare')) THEN RETURN; END IF;
  RAISE EXCEPTION 'Droits insuffisants pour cette action (role gare requis : %)', array_to_string(p_roles, ', ');
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_bordereau_livraison(p_company_id uuid, p_gare_depart_id uuid, p_gare_destination_id uuid DEFAULT NULL::uuid, p_bus_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_ref text;
BEGIN
  -- emballeur_gare ET chargeur_gare font le même travail terrain (emballage
  -- + chargement) : les deux peuvent créer un lot.
  PERFORM public._assert_lot_access(p_company_id, p_gare_depart_id, ARRAY['emballeur_gare','chargeur_gare']);

  IF p_gare_destination_id IS NULL THEN
    RAISE EXCEPTION 'La gare de destination est obligatoire pour creer un lot (regroupement par destination)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = p_gare_depart_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de depart invalide pour cette compagnie';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = p_gare_destination_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de destination invalide pour cette compagnie';
  END IF;
  IF p_bus_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM "Bus" b WHERE b.id = p_bus_id AND b."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Bus invalide pour cette compagnie';
  END IF;

  v_ref := 'BL-' || upper(substring(replace(gen_random_uuid()::text, '-', '') FROM 1 FOR 8));

  INSERT INTO bordereaux_livraison (
    reference, company_id, gare_depart_id, gare_destination_id, bus_id, created_by
  ) VALUES (
    v_ref, p_company_id, p_gare_depart_id, p_gare_destination_id, p_bus_id,
    public.current_app_user_id()
  ) RETURNING id INTO v_id;

  RETURN public.get_bordereau_livraison(v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_colis_to_bordereau(p_bordereau_id uuid, p_colis_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
  v_colis colis_autonomes%ROWTYPE;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_depart_id, ARRAY['emballeur_gare','chargeur_gare']);
  IF v_bl.statut <> 'ouvert' THEN RAISE EXCEPTION 'Lot cloture'; END IF;

  SELECT * INTO v_colis FROM colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;
  IF v_colis.company_id <> v_bl.company_id THEN
    RAISE EXCEPTION 'Colis d''une autre compagnie';
  END IF;
  IF v_colis.gare_depart_id <> v_bl.gare_depart_id THEN
    RAISE EXCEPTION 'Ce colis ne part pas de la gare de ce lot';
  END IF;
  IF v_bl.gare_destination_id IS NOT NULL AND v_colis.gare_destination_id <> v_bl.gare_destination_id THEN
    RAISE EXCEPTION 'Ce colis n''a pas la meme destination que ce lot';
  END IF;
  IF v_colis.statut_colis <> 'enregistre' THEN
    RAISE EXCEPTION 'Seuls les colis enregistres (pas encore charges) peuvent etre emballes dans un lot';
  END IF;
  IF EXISTS (
    SELECT 1 FROM bordereau_colis bc WHERE bc.bordereau_id = p_bordereau_id AND bc.colis_id = p_colis_id
  ) THEN
    RAISE EXCEPTION 'Colis deja sur ce lot';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM bordereau_colis bc
    JOIN bordereaux_livraison bl ON bl.id = bc.bordereau_id
    WHERE bc.colis_id = p_colis_id AND bl.statut IN ('ouvert', 'clos', 'charge')
  ) THEN
    RAISE EXCEPTION 'Colis deja affecte a un autre lot en cours';
  END IF;

  INSERT INTO bordereau_colis (bordereau_id, colis_id) VALUES (p_bordereau_id, p_colis_id);

  RETURN jsonb_build_object('id', v_colis.id, 'statutColis', v_colis.statut_colis);
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_bordereau_charge(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_bl bordereaux_livraison%ROWTYPE;
  v_company_name text;
  v_gare_depart_name text;
  v_gare_destination_name text;
  v_row record;
  v_results jsonb := '[]'::jsonb;
  v_notify_recipients uuid[];
  v_notify_title text;
  v_notify_message text;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  -- emballeur_gare ET chargeur_gare font le même travail terrain : l'un ou
  -- l'autre peut confirmer le chargement du lot qu'il vient d'emballer.
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_depart_id, ARRAY['emballeur_gare','chargeur_gare']);
  IF v_bl.statut <> 'clos' THEN
    RAISE EXCEPTION 'Le lot doit d''abord etre cloture (emballage termine) avant chargement';
  END IF;

  SELECT c.name INTO v_company_name FROM "Companies" c WHERE c.id = v_bl.company_id;
  SELECT name INTO v_gare_depart_name FROM "Gares" WHERE id = v_bl.gare_depart_id;
  SELECT name INTO v_gare_destination_name FROM "Gares" WHERE id = v_bl.gare_destination_id;

  FOR v_row IN
    SELECT ca.* FROM colis_autonomes ca
    JOIN bordereau_colis bc ON bc.colis_id = ca.id
    WHERE bc.bordereau_id = p_bordereau_id AND ca.statut_colis = 'enregistre'
  LOOP
    UPDATE colis_autonomes
    SET statut_colis = 'charge', bus_id = COALESCE(v_bl.bus_id, bus_id), updated_at = now()
    WHERE id = v_row.id;

    v_results := v_results || jsonb_build_object(
      'colisId', v_row.id,
      'sms', public.build_colis_sms_payload(
        v_bl.company_id, 'charge',
        public.build_colis_sms_message('charge', v_row.id, v_company_name, v_gare_depart_name, v_gare_destination_name),
        v_row.telephone_expediteur, v_row.telephone_destinataire
      )
    );
  END LOOP;

  UPDATE bordereaux_livraison SET statut = 'charge' WHERE id = p_bordereau_id;

  v_notify_recipients := public._colis_notification_recipients(
    v_bl.company_id, v_bl.gare_depart_id, v_bl.gare_destination_id, v_user_id
  );
  v_notify_title := 'Lot chargé';
  v_notify_message := format('Lot %s (%s → %s) chargé — %s colis', COALESCE(v_bl.numero_lot::text, v_bl.reference), v_gare_depart_name, v_gare_destination_name, jsonb_array_length(v_results));
  PERFORM public._create_colis_notifications(
    v_notify_recipients, 'lot_charge', v_notify_title, v_notify_message,
    jsonb_build_object('bordereauId', p_bordereau_id, 'companyId', v_bl.company_id)
  );

  RETURN jsonb_build_object(
    'id', p_bordereau_id, 'statut', 'charge', 'colisNotifications', v_results,
    'notifyRecipients', to_jsonb(v_notify_recipients),
    'notifyTitle', v_notify_title,
    'notifyMessage', v_notify_message
  );
END;
$function$;

-- 3) Accès à la liste générale des colis pour les 3 rôles opérationnels --
-- (compagnie entière si rôle global sans gare — nouveau schéma ; ou scopé
-- à leur(s) gare(s) si rôle encore attribué à une gare précise —
-- rétrocompat).
CREATE OR REPLACE FUNCTION public.list_colis_autonomes(p_company_id uuid, p_statut text DEFAULT NULL::text, p_limit integer DEFAULT 50)
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
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;

  v_full_access := public.is_company_role_user(v_user_id, p_company_id)
    OR public.has_company_role(p_company_id, ARRAY['emballeur_gare','chargeur_gare','distributeur_gare']);

  IF NOT v_full_access THEN
    SELECT array_agg(ur."gareId") INTO v_gare_ids
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = p_company_id
      AND ur."gareId" IS NOT NULL
      AND r.name IN ('comptable_gare', 'emballeur_gare', 'chargeur_gare', 'distributeur_gare');

    IF v_gare_ids IS NULL THEN
      RAISE EXCEPTION 'Droits insuffisants';
    END IF;
  END IF;

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
      gd.name AS "gareDepart",
      gdest.name AS "gareDestination",
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
      AND (v_full_access OR ca.gare_depart_id = ANY(v_gare_ids) OR ca.gare_destination_id = ANY(v_gare_ids))
    ORDER BY ca.created_at DESC
    -- Limite relevée (200 -> 5000) : la liste ne doit plus tronquer
    -- silencieusement les colis anciens d'une compagnie active.
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 5000), 1)
  ) sub;

  RETURN v_rows;
END;
$function$;

-- 4) emballeur_gare / chargeur_gare / distributeur_gare assignables comme
-- rôles compagnie directs (sans gare), via le même chemin que vendeur/
-- chauffeur/contrôleur/comptable_compagnie.
CREATE OR REPLACE FUNCTION public.assign_company_user_role_by_email(p_email text, p_role_name text DEFAULT 'vendeur'::text, p_company_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(id uuid, "firstName" text, "lastName" text, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id uuid;
  v_owner_user_id uuid;
  v_target_user_id uuid;
  v_role_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  v_owner_user_id := public.current_app_user_id();

  IF v_company_id IS NULL OR v_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_role_name NOT IN (
    'vendeur',
    'chauffeur',
    'controleur',
    'comptable_compagnie',
    'gestionnaire_gare',
    'emballeur_gare',
    'chargeur_gare',
    'distributeur_gare'
  ) THEN
    RAISE EXCEPTION 'Role compagnie non autorise : %', p_role_name;
  END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  SELECT r.id INTO v_role_id
  FROM "Role" r
  WHERE r.name = p_role_name AND r.scope = 'company'
  LIMIT 1;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role introuvable : %', p_role_name;
  END IF;

  SELECT u.id INTO v_target_user_id
  FROM "Users" u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Aucun utilisateur inscrit avec cet email';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    WHERE ur."userId" = v_target_user_id
      AND ur."roleId" = v_role_id
      AND ur."companyId" = v_company_id
  ) THEN
    INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId", "assignedBy")
    VALUES (v_role_id, v_target_user_id, v_company_id, NULL, v_owner_user_id);
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u."firstName"::text,
    u."lastName"::text,
    u.email::text
  FROM "Users" u
  WHERE u.id = v_target_user_id
  LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_company_user_role(p_user_id uuid, p_role_name text, p_company_id uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id uuid;
  v_role_id uuid;
BEGIN
  v_company_id := COALESCE(p_company_id, public.current_owner_company_id());
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Compagnie owner introuvable';
  END IF;

  IF p_role_name NOT IN (
    'vendeur',
    'chauffeur',
    'controleur',
    'comptable_compagnie',
    'gestionnaire_gare',
    'emballeur_gare',
    'chargeur_gare',
    'distributeur_gare'
  ) THEN
    RAISE EXCEPTION 'Role compagnie non autorise : %', p_role_name;
  END IF;

  IF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_company_id, ARRAY['owner'])
  THEN
    RAISE EXCEPTION 'Action reservee au proprietaire';
  END IF;

  SELECT r.id INTO v_role_id
  FROM "Role" r
  WHERE r.name = p_role_name AND r.scope = 'company'
  LIMIT 1;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role introuvable : %', p_role_name;
  END IF;

  DELETE FROM "UserRoles"
  WHERE "userId" = p_user_id
    AND "roleId" = v_role_id
    AND "companyId" = v_company_id;
END;
$function$;
