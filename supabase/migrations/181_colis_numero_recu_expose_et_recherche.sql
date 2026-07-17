-- Expose numeroRecu dans get_colis_autonome_detail + list_colis_autonomes,
-- et permet la recherche/retrait par ce numéro (ex. ABOI000001) dans
-- resolve_colis_retrait_code.
-- APPLIQUÉE EN PRODUCTION (apply_migration colis_numero_recu_expose_et_recherche).

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
    'natureIds', COALESCE((SELECT jsonb_agg(cns.nature_id) FROM public.colis_natures_selectionnees cns WHERE cns.colis_id = ca.id), '[]'::jsonb),
    'natures', COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb))
  INTO v_row FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id JOIN "Companies" c ON c.id = ca.company_id WHERE ca.id = p_colis_id;
  RETURN v_row;
END; $function$;

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

  v_full_access := public.is_company_role_user(v_user_id, p_company_id);

  IF NOT v_full_access THEN
    SELECT array_agg(ur."gareId") INTO v_gare_ids
    FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user_id
      AND ur."companyId" = p_company_id
      AND ur."gareId" IS NOT NULL
      AND r.name = 'comptable_gare';

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
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  ) sub;

  RETURN v_rows;
END;
$function$;

-- Recherche par numéro de reçu (ABOI000001), UUID, ou référence CL-XXXXXXXX.
CREATE OR REPLACE FUNCTION public.resolve_colis_retrait_code(p_code text)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw text := upper(trim(p_code));
  v_alnum text;
  v_id uuid;
BEGIN
  IF v_raw IS NULL OR v_raw = '' THEN
    RETURN NULL;
  END IF;

  BEGIN
    v_id := v_raw::uuid;
    IF EXISTS (SELECT 1 FROM public.colis_autonomes WHERE id = v_id) THEN
      RETURN v_id;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation THEN
      NULL;
  END;

  v_alnum := regexp_replace(v_raw, '[^A-Z0-9]', '', 'g');

  -- Numéro de reçu par gare (ex. ABOI000001).
  SELECT ca.id INTO v_id
  FROM public.colis_autonomes ca
  WHERE upper(ca.numero_recu) = v_alnum
  LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  v_raw := regexp_replace(v_alnum, '^CL-?', '');
  IF length(v_raw) < 4 THEN
    RETURN NULL;
  END IF;

  SELECT ca.id
  INTO v_id
  FROM public.colis_autonomes ca
  WHERE upper(replace(ca.id::text, '-', '')) LIKE v_raw || '%'
  ORDER BY ca.created_at DESC
  LIMIT 1;

  IF v_id IS NULL AND length(v_raw) > 8 THEN
    SELECT ca.id
    INTO v_id
    FROM public.colis_autonomes ca
    WHERE upper(replace(ca.id::text, '-', '')) LIKE left(v_raw, 8) || '%'
    ORDER BY ca.created_at DESC
    LIMIT 1;
  END IF;

  RETURN v_id;
END;
$$;
