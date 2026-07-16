-- Numéro de téléphone par gare — affiché sur le reçu colis (courrier
-- agent) sous le nom de la gare de départ, à côté du nom de la compagnie
-- (voir colis_receipt_lines.dart / printer_service.dart / ColisReceiptPanel).
ALTER TABLE "Gares" ADD COLUMN IF NOT EXISTS "phone" varchar;

-- Expose gareDepartPhone dans get_colis_autonome_detail (RPC utilisée par
-- le detail colis + l'impression reçu côté mobile/web).
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
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  SELECT jsonb_build_object('id', ca.id, 'companyId', ca.company_id, 'statutColis', ca.statut_colis, 'nomExpediteur', ca.nom_expediteur, 'telephoneExpediteur', ca.telephone_expediteur, 'nomDestinataire', ca.nom_destinataire, 'telephoneDestinataire', ca.telephone_destinataire, 'descriptionContenu', ca.description_contenu, 'poidsKg', ca.poids_kg, 'nombrePieces', ca.nombre_pieces, 'montantFret', ca.montant_fret, 'valeurMarchandise', ca.valeur_marchandise, 'sourceVente', ca.source_vente, 'createdAt', ca.created_at, 'updatedAt', ca.updated_at, 'gareDepartId', ca.gare_depart_id, 'gareDestinationId', ca.gare_destination_id, 'gareDepart', gd.name, 'gareDepartPhone', gd.phone, 'gareDestination', gdest.name, 'companyName', c.name,
    'natureIds', COALESCE((SELECT jsonb_agg(cns.nature_id) FROM public.colis_natures_selectionnees cns WHERE cns.colis_id = ca.id), '[]'::jsonb),
    'natures', COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb))
  INTO v_row FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id JOIN "Companies" c ON c.id = ca.company_id WHERE ca.id = p_colis_id;
  RETURN v_row;
END; $function$;

-- Expose gareDepartPhone dans list_colis_autonomes aussi, par cohérence
-- (même pattern que valeurMarchandise, migration 169).
CREATE OR REPLACE FUNCTION public.list_colis_autonomes(p_company_id uuid, p_statut text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      ca.valeur_marchandise AS "valeurMarchandise",
      ca.created_at AS "createdAt",
      ca.updated_at AS "updatedAt",
      gd.name AS "gareDepart",
      gd.phone AS "gareDepartPhone",
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
$function$;
