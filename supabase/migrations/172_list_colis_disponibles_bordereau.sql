-- Amélioration BL (bordereau de livraison) : jusqu'ici le seul moyen d'y
-- ajouter un colis était le scan QR ou la saisie manuelle de la référence
-- CL-XXXX (add_colis_to_bordereau prenait déjà un p_colis_id, donc la seule
-- brique manquante côté serveur est la LISTE des colis éligibles à afficher
-- avec un bouton "Ajouter", sans scan ni saisie).
--
-- Éligibilité = mêmes règles que celles déjà vérifiées par
-- add_colis_to_bordereau : même compagnie, même gare de départ (et même
-- gare de destination si le bordereau en a une), pas encore livré, pas déjà
-- sur un bordereau ouvert (celui-ci inclus — un colis déjà ajouté à CE
-- bordereau ne doit pas réapparaître dans la liste des colis à ajouter).

CREATE OR REPLACE FUNCTION public.list_colis_disponibles_bordereau(
  p_bordereau_id uuid,
  p_limit integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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

REVOKE EXECUTE ON FUNCTION public.list_colis_disponibles_bordereau(uuid, integer) FROM PUBLIC, anon;
