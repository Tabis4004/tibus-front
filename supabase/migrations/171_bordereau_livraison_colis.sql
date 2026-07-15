-- Bordereau de livraison colis : document CRÉÉ manuellement en scannant les
-- colis embarqués dans le bus vers la gare de destination (pratique terrain).
-- Le manifeste filtrable (rapports) reste inchangé ; le bordereau est une
-- liste construite au chargement, imprimable, avec référence BL-XXXXXXXX.

CREATE TABLE public.bordereaux_livraison (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text UNIQUE NOT NULL,
  company_id uuid NOT NULL REFERENCES public."Companies"(id) ON DELETE CASCADE,
  gare_depart_id uuid NOT NULL REFERENCES public."Gares"(id),
  gare_destination_id uuid REFERENCES public."Gares"(id),
  bus_id uuid REFERENCES public."Bus"(id),
  statut text NOT NULL DEFAULT 'ouvert' CHECK (statut IN ('ouvert', 'clos')),
  created_by uuid REFERENCES public."Users"(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz
);

CREATE TABLE public.bordereau_colis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bordereau_id uuid NOT NULL REFERENCES public.bordereaux_livraison(id) ON DELETE CASCADE,
  colis_id uuid NOT NULL REFERENCES public.colis_autonomes(id) ON DELETE CASCADE,
  added_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (bordereau_id, colis_id)
);

CREATE INDEX bordereau_colis_colis_idx ON public.bordereau_colis (colis_id);

-- Fail-closed : accès uniquement via RPC SECURITY DEFINER.
ALTER TABLE public.bordereaux_livraison ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bordereau_colis ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._assert_bordereau_access(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user uuid := public.current_app_user_id();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user, p_company_id) OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN
    RAISE EXCEPTION 'Module colis autonome non active';
  END IF;
END;
$function$;

-- 1. Création (le convoyage part d'une gare, destination et bus optionnels).
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
  PERFORM public._assert_bordereau_access(p_company_id);

  IF NOT EXISTS (
    SELECT 1 FROM "Gares" g WHERE g.id = p_gare_depart_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare de depart invalide pour cette compagnie';
  END IF;
  IF p_gare_destination_id IS NOT NULL AND NOT EXISTS (
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

-- 2. Ajout d'un colis (scan) : lie le colis et le passe « chargé » si besoin
--    (même logique SMS que update_colis_autonome_statut).
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
  v_company_name text;
  v_gare_depart text;
  v_gare_destination text;
  v_message text;
  v_sms jsonb := jsonb_build_object('send', false);
BEGIN
  SELECT * INTO v_bl FROM bordereaux_livraison WHERE id = p_bordereau_id;
  IF v_bl.id IS NULL THEN RAISE EXCEPTION 'Bordereau introuvable'; END IF;
  PERFORM public._assert_bordereau_access(v_bl.company_id);
  IF v_bl.statut <> 'ouvert' THEN RAISE EXCEPTION 'Bordereau cloture'; END IF;

  SELECT * INTO v_colis FROM colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;
  IF v_colis.company_id <> v_bl.company_id THEN
    RAISE EXCEPTION 'Colis d''une autre compagnie';
  END IF;
  IF v_colis.statut_colis IN ('livre') THEN
    RAISE EXCEPTION 'Colis deja livre';
  END IF;
  IF EXISTS (
    SELECT 1 FROM bordereau_colis bc WHERE bc.bordereau_id = p_bordereau_id AND bc.colis_id = p_colis_id
  ) THEN
    RAISE EXCEPTION 'Colis deja sur ce bordereau';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM bordereau_colis bc
    JOIN bordereaux_livraison bl ON bl.id = bc.bordereau_id
    WHERE bc.colis_id = p_colis_id AND bl.statut = 'ouvert'
  ) THEN
    RAISE EXCEPTION 'Colis deja sur un autre bordereau ouvert';
  END IF;

  INSERT INTO bordereau_colis (bordereau_id, colis_id) VALUES (p_bordereau_id, p_colis_id);

  -- Passage « chargé » au scan (avec bus du bordereau) + payload SMS.
  IF v_colis.statut_colis = 'enregistre' THEN
    UPDATE colis_autonomes
    SET statut_colis = 'charge',
        bus_id = COALESCE(v_bl.bus_id, bus_id),
        updated_at = now()
    WHERE id = p_colis_id;

    SELECT c.name, gd.name, gdest.name
    INTO v_company_name, v_gare_depart, v_gare_destination
    FROM "Companies" c
    JOIN "Gares" gd ON gd.id = v_colis.gare_depart_id
    JOIN "Gares" gdest ON gdest.id = v_colis.gare_destination_id
    WHERE c.id = v_colis.company_id;

    v_message := public.build_colis_sms_message('charge', p_colis_id, v_company_name, v_gare_depart, v_gare_destination);
    v_sms := public.build_colis_sms_payload(
      v_colis.company_id, 'charge', v_message,
      v_colis.telephone_expediteur, v_colis.telephone_destinataire
    );
    v_colis.statut_colis := 'charge';
  END IF;

  RETURN jsonb_build_object(
    'id', v_colis.id,
    'statutColis', v_colis.statut_colis,
    'sms', v_sms
  );
END;
$function$;

-- 3. Retrait d'un colis (tant que le bordereau est ouvert).
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
  PERFORM public._assert_bordereau_access(v_bl.company_id);
  IF v_bl.statut <> 'ouvert' THEN RAISE EXCEPTION 'Bordereau cloture'; END IF;
  DELETE FROM bordereau_colis WHERE bordereau_id = p_bordereau_id AND colis_id = p_colis_id;
END;
$function$;

-- 4. Clôture.
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
  PERFORM public._assert_bordereau_access(v_bl.company_id);
  UPDATE bordereaux_livraison
  SET statut = 'clos', closed_at = now()
  WHERE id = p_bordereau_id AND statut = 'ouvert';
  RETURN public.get_bordereau_livraison(p_bordereau_id);
END;
$function$;

-- 5. Liste des bordereaux de la compagnie.
CREATE OR REPLACE FUNCTION public.list_bordereaux_livraison(
  p_company_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  reference text,
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
  SELECT bl.id, bl.reference, bl.statut,
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

-- 6. Détail complet (affichage + impression).
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

REVOKE EXECUTE ON FUNCTION public._assert_bordereau_access(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_bordereau_livraison(uuid, uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.add_colis_to_bordereau(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.remove_colis_from_bordereau(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.close_bordereau_livraison(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_bordereaux_livraison(uuid, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_bordereau_livraison(uuid) FROM PUBLIC, anon;
