-- Retour terrain formation SIS (20/08/2026), points 3 et 5 :
--
-- 3) Les colis quittent chaque agence d'origine et se REGROUPENT à un point
--    central (le "hub") avant d'être emballés en lots par destination — ils
--    n'arrivent pas déjà triés par gare de départ. Le système imposait de
--    choisir UNE gare de départ précise pour créer un lot, et n'acceptait
--    dans ce lot que les colis enregistrés exactement à cette gare : au hub,
--    où les colis viennent de plusieurs agences d'une même ville, c'est
--    inutilisable.
--    Proposition initiale de l'utilisateur ("agence principale = Abidjan") a
--    été remplacée par une solution plus générale et plus robuste, retenue
--    après discussion : un lot se crée maintenant par VILLE de départ (pas
--    gare précise), et regroupe tous les colis de cette ville quelle que
--    soit leur gare d'origine exacte — la destination, elle, reste une gare
--    précise (plus spécifique, demande explicite). Le "point central"
--    devient simplement une gare de plus dans sa ville ; si une autre ville
--    a plusieurs gares un jour, le même mécanisme s'applique sans nouveau
--    cas particulier. La seule condition d'accès reste l'appartenance à la
--    compagnie (rôle emballeur_gare/chargeur_gare, déjà global compagnie
--    depuis la migration 193) — jamais liée à une gare précise.
--    Détail par colis (gare de départ réelle) conservé dans get_bordereau_livraison
--    pour garder la traçabilité malgré le regroupement par ville.
--
-- 5) Ajout d'un champ de date de lot ÉDITABLE par l'agent à la création
--    (date_lot, distincte de created_at qui reste l'horodatage technique) :
--    c'est cette date qui doit s'afficher partout (liste des lots, étiquette
--    imprimée), par défaut la date du jour.
--
-- Portée : schéma bordereaux_livraison + RPC lot (create/add/remove/close/
-- mark_charge/mark_arrive/list/get/list_colis_disponibles). Coordonné avec
-- courrier_mobile (bordereau_service.dart, bordereau_screen.dart) et le web
-- (src/lib/supabase/bordereaux.ts, BordereauPanel.tsx) dans le même déploi :
-- l'ancien paramètre p_gare_depart_id devient p_ville_depart_id (même
-- position/type uuid, mais sémantique différente) — les deux côtés doivent
-- être mis à jour ensemble.

-- 1) Schéma ----------------------------------------------------------------
ALTER TABLE public.bordereaux_livraison
  ADD COLUMN IF NOT EXISTS ville_depart_id uuid REFERENCES public."Cities"(id),
  ADD COLUMN IF NOT EXISTS date_lot date NOT NULL DEFAULT CURRENT_DATE;

-- Backfill : les lots existants gardent leur gare de départ (rétrocompat
-- d'affichage), on en déduit la ville ; la date de lot reprend la date de
-- création telle quelle (pas de perte d'info pour l'historique).
UPDATE public.bordereaux_livraison bl
SET ville_depart_id = g."cityId"
FROM public."Gares" g
WHERE g.id = bl.gare_depart_id AND bl.ville_depart_id IS NULL;

UPDATE public.bordereaux_livraison
SET date_lot = created_at::date
WHERE date_lot IS NULL;

-- gare_depart_id n'est plus renseignée pour les NOUVEAUX lots (regroupement
-- par ville) : la colonne reste pour les lots déjà créés, mais n'est plus
-- NOT NULL.
ALTER TABLE public.bordereaux_livraison
  ALTER COLUMN gare_depart_id DROP NOT NULL;

ALTER TABLE public.bordereaux_livraison
  ALTER COLUMN ville_depart_id SET NOT NULL;

-- 2) Contrôle d'accès par VILLE (au lieu de par gare précise) ---------------
-- Même logique que _assert_lot_access (migration 193) : rôle global
-- compagnie d'abord (cas normal), rétrocompat gare-scopée en repli — mais la
-- gare-scopée doit ici appartenir à la ville concernée (le rôle a pu être
-- attribué à UNE gare précise de cette ville, ancien schéma).
CREATE OR REPLACE FUNCTION public._assert_lot_access_ville(p_company_id uuid, p_ville_id uuid, p_roles text[])
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
  -- Rôle opérationnel attribué SANS gare (rôle global compagnie, cas
  -- normal depuis la migration 193) : agit sur toutes les villes.
  IF public.has_company_role(p_company_id, p_roles) THEN RETURN; END IF;
  -- Rétrocompatibilité : rôle attribué à une gare précise DE CETTE VILLE
  -- (ancien schéma), ou gérant de l'une de ces gares.
  IF EXISTS (
    SELECT 1 FROM "Gares" g
    WHERE g."cityId" = p_ville_id AND g."companyId" = p_company_id
      AND public.has_gare_role(g.id, array_append(p_roles, 'gerant_gare'))
  ) THEN RETURN; END IF;
  RAISE EXCEPTION 'Droits insuffisants pour cette action (role requis : %)', array_to_string(p_roles, ', ');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._assert_lot_access_ville(uuid, uuid, text[]) FROM PUBLIC, anon;

-- 3) Villes de départ disponibles pour la compagnie (peuple le sélecteur de
--    création de lot, remplace la liste de gares utilisée jusqu'ici).
CREATE OR REPLACE FUNCTION public.list_company_villes_depart(p_company_id uuid)
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT DISTINCT c.id, c.name::text
  FROM public."Cities" c
  JOIN public."Gares" g ON g."cityId" = c.id
  WHERE g."companyId" = p_company_id
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY c.name;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.list_company_villes_depart(uuid) TO authenticated;

-- 4) Création du lot : ville de départ (obligatoire) + gare de destination
--    (obligatoire, inchangé) + date de lot (éditable, défaut aujourd'hui).
CREATE OR REPLACE FUNCTION public.create_bordereau_livraison(
  p_company_id uuid,
  p_ville_depart_id uuid,
  p_gare_destination_id uuid DEFAULT NULL::uuid,
  p_bus_id uuid DEFAULT NULL::uuid,
  p_date_lot date DEFAULT NULL::date
)
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
  PERFORM public._assert_lot_access_ville(p_company_id, p_ville_depart_id, ARRAY['emballeur_gare','chargeur_gare']);

  IF p_gare_destination_id IS NULL THEN
    RAISE EXCEPTION 'La gare de destination est obligatoire pour creer un lot (regroupement par destination)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g."cityId" = p_ville_depart_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Ville de depart invalide pour cette compagnie (aucune gare de cette compagnie dans cette ville)';
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
    reference, company_id, ville_depart_id, gare_destination_id, bus_id, created_by, date_lot
  ) VALUES (
    v_ref, p_company_id, p_ville_depart_id, p_gare_destination_id, p_bus_id,
    public.current_app_user_id(), COALESCE(p_date_lot, CURRENT_DATE)
  ) RETURNING id INTO v_id;

  RETURN public.get_bordereau_livraison(v_id);
END;
$function$;

-- 5) Ajout d'un colis : le colis doit partir d'une gare de la VILLE du lot
--    (plus une gare précise) — c'est le changement central du point 3.
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
  PERFORM public._assert_lot_access_ville(v_bl.company_id, v_bl.ville_depart_id, ARRAY['emballeur_gare','chargeur_gare']);
  IF v_bl.statut <> 'ouvert' THEN RAISE EXCEPTION 'Lot cloture'; END IF;

  SELECT * INTO v_colis FROM colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;
  IF v_colis.company_id <> v_bl.company_id THEN
    RAISE EXCEPTION 'Colis d''une autre compagnie';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = v_colis.gare_depart_id AND g."cityId" = v_bl.ville_depart_id
  ) THEN
    RAISE EXCEPTION 'Ce colis ne part pas de la ville de depart de ce lot';
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

-- 6) Retrait d'un colis du lot (ouvert uniquement) — accès aligné sur
--    emballeur_gare ET chargeur_gare (même travail terrain, cf. migration
--    193) : gap corrigé ici, seul emballeur_gare pouvait retirer jusque-là.
CREATE OR REPLACE FUNCTION public.remove_colis_from_bordereau(p_bordereau_id uuid, p_colis_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_lot_access_ville(v_bl.company_id, v_bl.ville_depart_id, ARRAY['emballeur_gare','chargeur_gare']);
  IF v_bl.statut <> 'ouvert' THEN RAISE EXCEPTION 'Lot cloture'; END IF;
  DELETE FROM bordereau_colis WHERE bordereau_id = p_bordereau_id AND colis_id = p_colis_id;
END;
$function$;

-- 7) Cloture du lot — même correction d'accès (emballeur_gare + chargeur_gare).
CREATE OR REPLACE FUNCTION public.close_bordereau_livraison(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_lot_access_ville(v_bl.company_id, v_bl.ville_depart_id, ARRAY['emballeur_gare','chargeur_gare']);
  IF NOT EXISTS (SELECT 1 FROM bordereau_colis WHERE bordereau_id = p_bordereau_id) THEN
    RAISE EXCEPTION 'Le lot est vide — scannez au moins un colis avant de cloturer';
  END IF;
  UPDATE bordereaux_livraison
  SET statut = 'clos', closed_at = now()
  WHERE id = p_bordereau_id AND statut = 'ouvert';
  RETURN public.get_bordereau_livraison(p_bordereau_id);
END;
$function$;

-- 8) Chargement du lot : lookup du nom "gare de depart" remplace par le nom
--    de VILLE pour les messages SMS/notif (gare_depart_id est desormais NULL
--    sur les nouveaux lots).
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
  v_ville_depart_name text;
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
  PERFORM public._assert_lot_access_ville(v_bl.company_id, v_bl.ville_depart_id, ARRAY['emballeur_gare','chargeur_gare']);
  IF v_bl.statut <> 'clos' THEN
    RAISE EXCEPTION 'Le lot doit d''abord etre cloture (emballage termine) avant chargement';
  END IF;

  SELECT c.name INTO v_company_name FROM "Companies" c WHERE c.id = v_bl.company_id;
  SELECT name INTO v_ville_depart_name FROM "Cities" WHERE id = v_bl.ville_depart_id;
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
        public.build_colis_sms_message('charge', v_row.id, v_company_name, v_ville_depart_name, v_gare_destination_name),
        v_row.telephone_expediteur, v_row.telephone_destinataire
      )
    );
  END LOOP;

  UPDATE bordereaux_livraison SET statut = 'charge' WHERE id = p_bordereau_id;

  -- gare_depart_id est desormais NULL sur les lots ville : les gerants de
  -- gare de depart ne sont plus notifies individuellement via ce canal (ils
  -- n'ont plus une gare de depart unique a suivre) — owner/comptable et les
  -- gerants de la gare de destination le sont toujours.
  v_notify_recipients := public._colis_notification_recipients(
    v_bl.company_id, NULL, v_bl.gare_destination_id, v_user_id
  );
  v_notify_title := 'Lot chargé';
  v_notify_message := format('Lot %s (%s → %s) chargé — %s colis', COALESCE(v_bl.numero_lot::text, v_bl.reference), v_ville_depart_name, v_gare_destination_name, jsonb_array_length(v_results));
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

-- 9) Reception : idem, nom de ville a la place du nom de gare de depart pour
--    les messages (acces reste sur la gare de DESTINATION, inchange).
CREATE OR REPLACE FUNCTION public.mark_bordereau_arrive(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_bl bordereaux_livraison%ROWTYPE;
  v_company_name text;
  v_ville_depart_name text;
  v_gare_destination_name text;
  v_row record;
  v_results jsonb := '[]'::jsonb;
  v_notify_recipients uuid[];
  v_notify_title text;
  v_notify_message text;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  IF v_bl.gare_destination_id IS NULL THEN RAISE EXCEPTION 'Lot sans gare de destination'; END IF;
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_destination_id, ARRAY['distributeur_gare']);
  IF v_bl.statut <> 'charge' THEN
    RAISE EXCEPTION 'Le lot doit d''abord etre charge (parti) avant confirmation de reception';
  END IF;

  SELECT c.name INTO v_company_name FROM "Companies" c WHERE c.id = v_bl.company_id;
  SELECT name INTO v_ville_depart_name FROM "Cities" WHERE id = v_bl.ville_depart_id;
  SELECT name INTO v_gare_destination_name FROM "Gares" WHERE id = v_bl.gare_destination_id;

  FOR v_row IN
    SELECT ca.* FROM colis_autonomes ca
    JOIN bordereau_colis bc ON bc.colis_id = ca.id
    WHERE bc.bordereau_id = p_bordereau_id AND ca.statut_colis = 'charge'
  LOOP
    UPDATE colis_autonomes SET statut_colis = 'arrive', updated_at = now() WHERE id = v_row.id;

    v_results := v_results || jsonb_build_object(
      'colisId', v_row.id,
      'telephoneExpediteur', v_row.telephone_expediteur,
      'telephoneDestinataire', v_row.telephone_destinataire,
      'sms', public.build_colis_sms_payload(
        v_bl.company_id, 'arrive',
        public.build_colis_sms_message('arrive', v_row.id, v_company_name, v_ville_depart_name, v_gare_destination_name),
        v_row.telephone_expediteur, v_row.telephone_destinataire
      )
    );
  END LOOP;

  UPDATE bordereaux_livraison SET statut = 'arrive' WHERE id = p_bordereau_id;

  v_notify_recipients := public._colis_notification_recipients(
    v_bl.company_id, NULL, v_bl.gare_destination_id, v_user_id
  );
  v_notify_title := 'Lot arrivé';
  v_notify_message := format('Lot %s (%s → %s) arrivé — %s colis', COALESCE(v_bl.numero_lot::text, v_bl.reference), v_ville_depart_name, v_gare_destination_name, jsonb_array_length(v_results));
  PERFORM public._create_colis_notifications(
    v_notify_recipients, 'lot_arrive', v_notify_title, v_notify_message,
    jsonb_build_object('bordereauId', p_bordereau_id, 'companyId', v_bl.company_id)
  );

  RETURN jsonb_build_object(
    'id', p_bordereau_id, 'statut', 'arrive', 'colisNotifications', v_results,
    'notifyRecipients', to_jsonb(v_notify_recipients),
    'notifyTitle', v_notify_title,
    'notifyMessage', v_notify_message
  );
END;
$function$;

-- 10) Liste des lots : villeDepart remplace gareDepart, expose dateLot ;
--     signature de retour changee -> DROP necessaire avant CREATE.
DROP FUNCTION IF EXISTS public.list_bordereaux_livraison(uuid, integer);
CREATE OR REPLACE FUNCTION public.list_bordereaux_livraison(
  p_company_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  reference text,
  "numeroLot" integer,
  statut text,
  "villeDepart" text,
  "gareDestination" text,
  "busPlateNumber" text,
  "colisCount" bigint,
  "dateLot" date,
  "createdAt" timestamptz,
  "closedAt" timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public._assert_bordereau_access(p_company_id);
  RETURN QUERY
  SELECT bl.id, bl.reference, bl.numero_lot, bl.statut,
         vd.name::text, gdest.name::text, b."registrationNumber"::text,
         (SELECT count(*) FROM bordereau_colis bc WHERE bc.bordereau_id = bl.id),
         bl.date_lot, bl.created_at, bl.closed_at
  FROM bordereaux_livraison bl
  LEFT JOIN "Cities" vd ON vd.id = bl.ville_depart_id
  LEFT JOIN "Gares" gdest ON gdest.id = bl.gare_destination_id
  LEFT JOIN "Bus" b ON b.id = bl.bus_id
  WHERE bl.company_id = p_company_id
  ORDER BY bl.date_lot DESC, bl.created_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 50), 1);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_bordereaux_livraison(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bordereaux_livraison(uuid, integer) TO authenticated;

-- 11) Detail complet : villeDepart (lot) + gareDepart par colis conserve
--     (tracabilite de l'origine reelle malgre le regroupement par ville) +
--     dateLot.
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
    'villeDepart', (SELECT name FROM "Cities" WHERE id = v_bl.ville_depart_id),
    'gareDestination', (SELECT name FROM "Gares" WHERE id = v_bl.gare_destination_id),
    'busPlateNumber', (SELECT "registrationNumber" FROM "Bus" WHERE id = v_bl.bus_id),
    'dateLot', v_bl.date_lot,
    'createdAt', v_bl.created_at,
    'closedAt', v_bl.closed_at,
    'colis', v_colis
  );
END;
$function$;

-- 12) Colis disponibles pour un lot : filtre par ville de depart (au lieu de
--     gare exacte).
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
      AND gd."cityId" = v_bl.ville_depart_id
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
