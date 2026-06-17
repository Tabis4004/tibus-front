-- Corrige list_colis_autonomes : ORDER BY sur alias createdAt (pas created_at).

CREATE OR REPLACE FUNCTION public.list_colis_autonomes(
  p_company_id uuid,
  p_statut text DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_rows jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub."createdAt" DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      ca.id,
      ca.statut_colis AS "statutColis",
      ca.nom_expediteur AS "nomExpediteur",
      ca.telephone_expediteur AS "telephoneExpediteur",
      ca.nom_destinataire AS "nomDestinataire",
      ca.telephone_destinataire AS "telephoneDestinataire",
      ca.description_contenu AS "descriptionContenu",
      ca.poids_kg AS "poidsKg",
      ca.nombre_pieces AS "nombrePieces",
      ca.montant_fret AS "montantFret",
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
    ORDER BY ca.created_at DESC
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  ) sub;

  RETURN v_rows;
END;
$$;
