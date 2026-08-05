-- Bug : un simple 'vendeur' voyait TOUS les colis de la compagnie (liste
-- "Colis" / manifeste), pas seulement les siens. is_company_role_user (qui
-- inclut 'vendeur' -- necessaire ailleurs, ex. register_colis_autonome)
-- etait utilise a tort comme critere de "plein acces" dans
-- list_colis_autonomes. Le meme produit avait deja ete corrige pour les
-- STATS (migrations 182/183, _colis_stats_full_access exclut deliberement
-- vendeur/vendeur_gare/chauffeur/controleur -- forces sur leur propre
-- activite). On applique ici la meme regle a la liste des colis :
--   - owner / comptable_compagnie / super_admin (_colis_stats_full_access) :
--     toute la compagnie.
--   - emballeur_gare / chargeur_gare / distributeur_gare : toute la
--     compagnie (deja le cas -- ces roles traitent les lots par
--     destination, pas par vendeur).
--   - comptable_gare : ses gares assignees (deja le cas).
--   - vendeur / vendeur_gare / chauffeur / controleur (aucun role
--     operationnel de gare) : UNIQUEMENT ses propres colis (vendeur_id =
--     lui-meme), jamais ceux des autres vendeurs -- demande explicite.
--
-- Applique en base le 2026-08-05 (kqudaqtydimjclwaihqr, projet "Tibus 1.0").

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
  v_own_sales_role boolean;
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
    -- Ni acces plein, ni gare operationnelle assignee : seul un role de
    -- vente personnel donne acces, borne a ses propres colis.
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
        OR (v_gare_ids IS NOT NULL AND (ca.gare_depart_id = ANY(v_gare_ids) OR ca.gare_destination_id = ANY(v_gare_ids)))
        OR (v_gare_ids IS NULL AND ca.vendeur_id = v_user_id)
      )
    ORDER BY ca.created_at DESC
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 5000), 1)
  ) sub;

  RETURN v_rows;
END;
$function$;
