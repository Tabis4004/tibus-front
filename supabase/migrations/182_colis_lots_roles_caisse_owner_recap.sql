-- Refonte du flux colis suite au retour de formation du promoteur :
--
-- 1) Roles distincts (emballeur_gare, chargeur_gare, distributeur_gare) —
--    chaque role fait son metier, pas celui de l'autre. Managers (owner,
--    comptable_compagnie, gerant_gare, super_admin) gardent un acces de
--    secours pour encadrement/depannage (voir _assert_lot_access).
-- 2) Cloture de caisse : le solde revient desormais a zero (chaque caisse ne
--    voyait deja que sa propre vente, mais le solde restait affiche apres
--    cloture, faussant les agregats owner).
-- 3) "Lots" : reutilisation de bordereaux_livraison/bordereau_colis comme
--    regroupement de colis PAR DESTINATION (gare_destination_id desormais
--    obligatoire a la creation), avec numero de lot entier sequentiel par
--    gare de depart (etiquette imprimee) et statuts etendus :
--      ouvert (emballage en cours, emballeur)
--      -> clos (lot scelle, pret a etre imprime/charge, emballeur)
--      -> charge (charge dans le vehicule, chargeur — scanne le LOT)
--      -> arrive (recu a destination, distributeur — scanne le LOT,
--         notifie les clients)
--    Le scan d'un colis dans un lot (emballage) ne change plus son statut :
--    l'ancien comportement marquait "charge" des l'emballage, melangeant
--    emballage et chargement. Le statut colis n'avance plus qu'au chargement
--    (bulk, via mark_bordereau_charge) puis a l'arrivee (bulk, via
--    mark_bordereau_arrive).
-- 4) Les transitions manuelles par colis (update_colis_autonome_statut,
--    utilisees par l'ecran de scan existant) sont alignees sur les memes
--    roles : enregistre->charge = chargeur_gare (gare de depart), charge->
--    arrive = distributeur_gare (gare de destination). arrive->livre
--    (remise client au guichet) reste inchangee.
-- 5) Nouveau recap owner par agence (get_company_revenue_by_gare) : jusqu'ici
--    le owner ne voyait qu'un montant global (get_company_accounting_dashboard,
--    caisseRevenue = ventes billetterie counter_sale uniquement, sans les
--    colis, ni de detail par gare).
--
-- APPLIQUEE EN PRODUCTION (apply_migration colis_lots_roles_caisse_owner_recap).

-- =============================================================================
-- 1. Roles distincts : emballeur_gare, chargeur_gare, distributeur_gare.
-- =============================================================================
INSERT INTO public."Role" ("name", "scope", "level", "isSystem", "description", "droits") VALUES
  ('emballeur_gare', 'company', 17, true, 'Emballeur — regroupe les colis en lots par destination et imprime le bordereau du lot', ARRAY['pack_colis']),
  ('chargeur_gare', 'company', 17, true, 'Chargeur — confirme le chargement des lots (bordereaux) dans le vehicule', ARRAY['load_colis']),
  ('distributeur_gare', 'company', 17, true, 'Distributeur — confirme la reception des lots a l''arrivee et notifie les clients', ARRAY['receive_colis'])
ON CONFLICT ("name") DO UPDATE SET
  "scope" = EXCLUDED."scope",
  "level" = EXCLUDED."level",
  "isSystem" = EXCLUDED."isSystem",
  "description" = EXCLUDED."description",
  "droits" = EXCLUDED."droits";

INSERT INTO public."RoleAssignmentRules" ("assignerRoleId", "assignableRoleId")
SELECT a.id, b.id FROM public."Role" a CROSS JOIN public."Role" b
WHERE a.name IN ('owner', 'gerant_gare', 'gestionnaire_gare')
  AND b.name IN ('emballeur_gare', 'chargeur_gare', 'distributeur_gare')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public._is_gare_scoped_role(p_role_name text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_role_name IN (
    'gerant_gare', 'gestionnaire_gare', 'vendeur_gare', 'controleur_gare', 'comptable_gare',
    'emballeur_gare', 'chargeur_gare', 'distributeur_gare'
  );
$$;

CREATE OR REPLACE FUNCTION public.assign_gare_team_role_by_email(p_gare_id uuid, p_email text, p_role_name text)
RETURNS TABLE(id uuid, "firstName" text, "lastName" text, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company uuid;
  v_assigner uuid;
  v_target uuid;
  v_role uuid;
  v_identifier text := lower(btrim(COALESCE(p_email, '')));
BEGIN
  IF NOT public.can_manage_gare(p_gare_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;

  IF p_role_name NOT IN (
    'vendeur_gare', 'controleur_gare', 'comptable_gare',
    'emballeur_gare', 'chargeur_gare', 'distributeur_gare'
  ) THEN
    RAISE EXCEPTION 'Rôle gare non autorisé : %', p_role_name;
  END IF;

  IF v_identifier = '' THEN
    RAISE EXCEPTION 'E-mail ou nom d''utilisateur requis';
  END IF;

  SELECT g."companyId" INTO v_company FROM public."Gares" g WHERE g.id = p_gare_id;
  v_assigner := public.current_app_user_id();

  SELECT r.id INTO v_role FROM public."Role" r WHERE r.name = p_role_name AND r.scope = 'company';
  IF v_role IS NULL THEN RAISE EXCEPTION 'Rôle introuvable'; END IF;

  SELECT u.id INTO v_target
  FROM public."Users" u
  WHERE lower(u.email) = v_identifier OR lower(u.username) = v_identifier
  ORDER BY (lower(u.email) = v_identifier) DESC
  LIMIT 1;

  IF v_target IS NULL THEN
    RAISE EXCEPTION 'Aucun utilisateur inscrit avec cet e-mail ou nom d''utilisateur';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public."UserRoles" ur
    WHERE ur."userId" = v_target AND ur."roleId" = v_role AND ur."gareId" = p_gare_id
  ) THEN
    INSERT INTO public."UserRoles" ("roleId", "userId", "companyId", "gareId", "countryId", "assignedBy")
    VALUES (v_role, v_target, v_company, p_gare_id, NULL, v_assigner);
  END IF;

  RETURN QUERY SELECT u.id, u."firstName"::text, u."lastName"::text, u.email::text
  FROM public."Users" u WHERE u.id = v_target;
END;
$function$;

-- Garde-fou generique reutilise par toutes les actions de lot (emballage /
-- chargement / distribution) : owner/comptable_compagnie/super_admin/
-- gerant_gare passent toujours (encadrement), sinon il faut le role gare
-- precis passe en parametre — pas un role "voisin" (vendeur_gare etc.).
CREATE OR REPLACE FUNCTION public._assert_lot_access(p_company_id uuid, p_gare_id uuid, p_roles text[])
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.current_app_user_id() IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN
    RAISE EXCEPTION 'Module colis autonome non active';
  END IF;
  IF public.is_super_admin() THEN RETURN; END IF;
  IF public.has_company_role(p_company_id, ARRAY['owner','comptable_compagnie']) THEN RETURN; END IF;
  IF public.has_gare_role(p_gare_id, array_append(p_roles, 'gerant_gare')) THEN RETURN; END IF;
  RAISE EXCEPTION 'Droits insuffisants pour cette action (role gare requis : %)', array_to_string(p_roles, ', ');
END;
$function$;

-- =============================================================================
-- 2. Cloture de caisse : le solde doit revenir a zero.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.close_station_cash_register(p_caisse_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_caisse record;
  v_company_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_caisse FROM public.caisses_gares WHERE id = p_caisse_id FOR UPDATE;
  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;

  IF v_caisse.statut <> 'ouverte' THEN
    RAISE EXCEPTION 'Session deja cloturee';
  END IF;

  v_company_id := public.station_cash_gare_company_id(v_caisse.gare_id);

  IF NOT (
    v_caisse.gestionnaire_id = v_user_id
    OR public.is_super_admin()
    OR public.has_company_role(v_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR public.has_gare_role(v_caisse.gare_id, ARRAY['comptable_gare', 'gerant_gare', 'gestionnaire_gare'])
  ) THEN
    RAISE EXCEPTION 'Cloture reservee au vendeur de la session, au comptable ou a l''owner';
  END IF;

  UPDATE public.caisses_gares
  SET statut = 'cloturee', closed_at = now(), solde_especes_actuel = 0
  WHERE id = p_caisse_id;

  RETURN jsonb_build_object(
    'id', p_caisse_id,
    'status', 'cloturee',
    'closedAt', now(),
    'balance', 0
  );
END;
$function$;

-- =============================================================================
-- 3. Lots : numero entier sequentiel par gare de depart + statuts etendus.
-- =============================================================================
ALTER TABLE public.bordereaux_livraison ADD COLUMN IF NOT EXISTS numero_lot integer;

CREATE TABLE IF NOT EXISTS public.bordereau_lot_numerotation (
  gare_depart_id uuid PRIMARY KEY REFERENCES public."Gares"(id) ON DELETE CASCADE,
  next_seq integer NOT NULL DEFAULT 1
);

CREATE OR REPLACE FUNCTION public.assign_bordereau_numero_lot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_seq integer;
BEGIN
  IF NEW.numero_lot IS NOT NULL THEN RETURN NEW; END IF;
  INSERT INTO public.bordereau_lot_numerotation (gare_depart_id, next_seq)
  VALUES (NEW.gare_depart_id, 2)
  ON CONFLICT (gare_depart_id) DO UPDATE SET next_seq = public.bordereau_lot_numerotation.next_seq + 1
  RETURNING next_seq - 1 INTO v_seq;
  NEW.numero_lot := v_seq;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS bordereau_numero_lot_trg ON public.bordereaux_livraison;
CREATE TRIGGER bordereau_numero_lot_trg
BEFORE INSERT ON public.bordereaux_livraison
FOR EACH ROW EXECUTE FUNCTION public.assign_bordereau_numero_lot();

WITH ordered AS (
  SELECT id, gare_depart_id, row_number() OVER (PARTITION BY gare_depart_id ORDER BY created_at) AS rn
  FROM public.bordereaux_livraison
  WHERE numero_lot IS NULL
)
UPDATE public.bordereaux_livraison bl
SET numero_lot = ordered.rn
FROM ordered
WHERE bl.id = ordered.id;

INSERT INTO public.bordereau_lot_numerotation (gare_depart_id, next_seq)
SELECT gare_depart_id, COALESCE(MAX(numero_lot), 0) + 1
FROM public.bordereaux_livraison
GROUP BY gare_depart_id
ON CONFLICT (gare_depart_id) DO UPDATE
  SET next_seq = GREATEST(public.bordereau_lot_numerotation.next_seq, EXCLUDED.next_seq);

ALTER TABLE public.bordereaux_livraison DROP CONSTRAINT IF EXISTS bordereaux_livraison_statut_check;
ALTER TABLE public.bordereaux_livraison ADD CONSTRAINT bordereaux_livraison_statut_check
  CHECK (statut IN ('ouvert', 'clos', 'charge', 'arrive'));

-- 3a. Creation d'un lot (emballeur) : destination desormais obligatoire.
CREATE OR REPLACE FUNCTION public.create_bordereau_livraison(
  p_company_id uuid,
  p_gare_depart_id uuid,
  p_gare_destination_id uuid DEFAULT NULL,
  p_bus_id uuid DEFAULT NULL
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
  PERFORM public._assert_lot_access(p_company_id, p_gare_depart_id, ARRAY['emballeur_gare']);

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

-- 3b. Ajout d'un colis au lot (scan emballeur) : ne change PLUS le statut du
--     colis (l'ancien comportement melangeait emballage et chargement) ;
--     verifie que le colis correspond bien a la meme gare de destination.
CREATE OR REPLACE FUNCTION public.add_colis_to_bordereau(
  p_bordereau_id uuid,
  p_colis_id uuid
)
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
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_depart_id, ARRAY['emballeur_gare']);
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

-- 3c. Retrait d'un colis du lot (tant qu'ouvert) : reserve a l'emballeur.
CREATE OR REPLACE FUNCTION public.remove_colis_from_bordereau(
  p_bordereau_id uuid,
  p_colis_id uuid
)
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
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_depart_id, ARRAY['emballeur_gare']);
  IF v_bl.statut <> 'ouvert' THEN RAISE EXCEPTION 'Lot cloture'; END IF;
  DELETE FROM bordereau_colis WHERE bordereau_id = p_bordereau_id AND colis_id = p_colis_id;
END;
$function$;

-- 3d. Cloture du lot (emballeur a fini) -> pret pour impression + chargement.
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
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_depart_id, ARRAY['emballeur_gare']);
  IF NOT EXISTS (SELECT 1 FROM bordereau_colis WHERE bordereau_id = p_bordereau_id) THEN
    RAISE EXCEPTION 'Le lot est vide — scannez au moins un colis avant de cloturer';
  END IF;
  UPDATE bordereaux_livraison
  SET statut = 'clos', closed_at = now()
  WHERE id = p_bordereau_id AND statut = 'ouvert';
  RETURN public.get_bordereau_livraison(p_bordereau_id);
END;
$function$;

-- 3e. Chargeur : scanne le LOT (pas chaque colis) pour confirmer le
--     chargement — bascule tous les colis du lot enregistre -> charge.
CREATE OR REPLACE FUNCTION public.mark_bordereau_charge(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
  v_company_name text;
  v_gare_depart_name text;
  v_gare_destination_name text;
  v_row record;
  v_results jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_depart_id, ARRAY['chargeur_gare']);
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

  RETURN jsonb_build_object('id', p_bordereau_id, 'statut', 'charge', 'colisNotifications', v_results);
END;
$function$;

-- 3f. Distributeur : scanne le LOT a l'arrivee pour confirmer reception —
--     bascule tous les colis du lot charge -> arrive. Le role s'applique a
--     la gare de DESTINATION (le distributeur travaille cote arrivee).
CREATE OR REPLACE FUNCTION public.mark_bordereau_arrive(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bl bordereaux_livraison%ROWTYPE;
  v_company_name text;
  v_gare_depart_name text;
  v_gare_destination_name text;
  v_row record;
  v_results jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  IF v_bl.gare_destination_id IS NULL THEN RAISE EXCEPTION 'Lot sans gare de destination'; END IF;
  PERFORM public._assert_lot_access(v_bl.company_id, v_bl.gare_destination_id, ARRAY['distributeur_gare']);
  IF v_bl.statut <> 'charge' THEN
    RAISE EXCEPTION 'Le lot doit d''abord etre charge (parti) avant confirmation de reception';
  END IF;

  SELECT c.name INTO v_company_name FROM "Companies" c WHERE c.id = v_bl.company_id;
  SELECT name INTO v_gare_depart_name FROM "Gares" WHERE id = v_bl.gare_depart_id;
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
        public.build_colis_sms_message('arrive', v_row.id, v_company_name, v_gare_depart_name, v_gare_destination_name),
        v_row.telephone_expediteur, v_row.telephone_destinataire
      )
    );
  END LOOP;

  UPDATE bordereaux_livraison SET statut = 'arrive' WHERE id = p_bordereau_id;

  RETURN jsonb_build_object('id', p_bordereau_id, 'statut', 'arrive', 'colisNotifications', v_results);
END;
$function$;

-- 3g. Listing/detail : lecture large (emballeur/chargeur/distributeur/
--     managers doivent tous pouvoir consulter les lots) ; expose numeroLot.
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
  "gareDepart" text,
  "gareDestination" text,
  "busPlateNumber" text,
  "colisCount" bigint,
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
         gd.name::text, gdest.name::text, b."registrationNumber"::text,
         (SELECT count(*) FROM bordereau_colis bc WHERE bc.bordereau_id = bl.id),
         bl.created_at, bl.closed_at
  FROM bordereaux_livraison bl
  JOIN "Gares" gd ON gd.id = bl.gare_depart_id
  LEFT JOIN "Gares" gdest ON gdest.id = bl.gare_destination_id
  LEFT JOIN "Bus" b ON b.id = bl.bus_id
  WHERE bl.company_id = p_company_id
  ORDER BY bl.created_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 50), 1);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_bordereau_livraison(p_bordereau_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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

GRANT EXECUTE ON FUNCTION public.mark_bordereau_charge(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_bordereau_arrive(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public._assert_lot_access(uuid, uuid, text[]) FROM PUBLIC, anon;

-- =============================================================================
-- 4. Role distinct sur les transitions manuelles (scan par colis) :
--    chargement = chargeur (gare de depart), arrivee = distributeur (gare de
--    destination). Livraison finale (arrive->livre) inchangee.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_colis_autonome_statut(p_colis_id uuid, p_new_statut text, p_bus_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_colis public.colis_autonomes%ROWTYPE;
  v_company_name text;
  v_gare_depart text;
  v_gare_destination text;
  v_allowed boolean := false;
  v_message text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF p_new_statut NOT IN ('enregistre', 'charge', 'arrive', 'livre') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  IF p_bus_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM "Bus" b WHERE b.id = p_bus_id AND b."companyId" = v_colis.company_id
  ) THEN
    RAISE EXCEPTION 'Bus invalide';
  END IF;

  IF v_colis.statut_colis = 'enregistre' AND p_new_statut = 'charge' THEN
    PERFORM public._assert_lot_access(v_colis.company_id, v_colis.gare_depart_id, ARRAY['chargeur_gare']);
  ELSIF v_colis.statut_colis = 'charge' AND p_new_statut = 'arrive' THEN
    PERFORM public._assert_lot_access(v_colis.company_id, v_colis.gare_destination_id, ARRAY['distributeur_gare']);
  END IF;

  v_allowed := CASE
    WHEN v_colis.statut_colis = 'enregistre' AND p_new_statut = 'charge' THEN true
    WHEN v_colis.statut_colis = 'charge' AND p_new_statut = 'arrive' THEN true
    WHEN v_colis.statut_colis = 'arrive' AND p_new_statut = 'livre' THEN true
    WHEN p_new_statut = v_colis.statut_colis THEN true
    ELSE false
  END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Transition non autorisee: % -> %', v_colis.statut_colis, p_new_statut; END IF;
  UPDATE public.colis_autonomes
  SET statut_colis = p_new_statut,
      bus_id = COALESCE(p_bus_id, bus_id),
      updated_at = now()
  WHERE id = p_colis_id;
  SELECT c.name, gd.name, gdest.name
  INTO v_company_name, v_gare_depart, v_gare_destination
  FROM "Companies" c
  JOIN "Gares" gd ON gd.id = v_colis.gare_depart_id
  JOIN "Gares" gdest ON gdest.id = v_colis.gare_destination_id
  WHERE c.id = v_colis.company_id;
  v_message := public.build_colis_sms_message(p_new_statut, p_colis_id, v_company_name, v_gare_depart, v_gare_destination);
  RETURN jsonb_build_object(
    'id', p_colis_id,
    'statutColis', p_new_statut,
    'sms', public.build_colis_sms_payload(
      v_colis.company_id,
      p_new_statut,
      v_message,
      v_colis.telephone_expediteur,
      v_colis.telephone_destinataire
    )
  );
END;
$function$;

-- =============================================================================
-- 5. Recap owner par agence (au lieu d'un seul montant global) : ticket
--    guichet + colis + solde caisse ouverte, par gare.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_company_revenue_by_gare(p_company_id uuid)
RETURNS TABLE (
  "gareId" uuid,
  "gareName" text,
  "ticketRevenue" double precision,
  "colisRevenue" double precision,
  "totalRevenue" double precision,
  "openCaisseBalance" double precision,
  currency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_currency text;
BEGIN
  IF NOT public.is_super_admin() AND NOT public.has_company_role(p_company_id, ARRAY['owner','comptable_compagnie']) THEN
    RAISE EXCEPTION 'Acces reserve au owner/comptable de la compagnie';
  END IF;

  SELECT COALESCE(country.currency, 'XOF') INTO v_currency
  FROM "Companies" c LEFT JOIN "Countries" country ON country.id = c."countryId"
  WHERE c.id = p_company_id;

  RETURN QUERY
  SELECT
    g.id,
    g.name::text,
    COALESCE(t.ticket_revenue, 0)::double precision,
    COALESCE(cc.colis_revenue, 0)::double precision,
    (COALESCE(t.ticket_revenue, 0) + COALESCE(cc.colis_revenue, 0))::double precision,
    COALESCE(cash.open_balance, 0)::double precision,
    v_currency
  FROM "Gares" g
  LEFT JOIN (
    SELECT pt.depart AS gare_id, SUM(rb.price) AS ticket_revenue
    FROM "ReservationBus" rb
    JOIN "Payment" p ON p.id = rb."paymentId"
    JOIN "Reservations" r ON r.id = rb."reservationId"
    JOIN "ProgrammationTrajets" pt ON pt.id = r."trajetId"
    WHERE rb."type" = 'voyage'
      AND COALESCE(rb."ticketStatus", 'issued') = 'issued'
      AND (rb."isReservation" = false OR p."txID" IS NOT NULL)
      AND COALESCE(rb."saleChannel", 'traveler') = 'counter_sale'
    GROUP BY pt.depart
  ) t ON t.gare_id = g.id
  LEFT JOIN (
    SELECT ca.gare_depart_id AS gare_id, SUM(ca.montant_fret) AS colis_revenue
    FROM colis_autonomes ca
    WHERE ca.company_id = p_company_id
    GROUP BY ca.gare_depart_id
  ) cc ON cc.gare_id = g.id
  LEFT JOIN (
    SELECT c.gare_id, SUM(c.solde_especes_actuel) AS open_balance
    FROM caisses_gares c
    WHERE c.statut = 'ouverte'
    GROUP BY c.gare_id
  ) cash ON cash.gare_id = g.id
  WHERE g."companyId" = p_company_id
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY (COALESCE(t.ticket_revenue,0) + COALESCE(cc.colis_revenue,0)) DESC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_company_revenue_by_gare(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
