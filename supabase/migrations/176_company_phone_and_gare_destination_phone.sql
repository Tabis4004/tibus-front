-- Numéro de téléphone de la compagnie — affiché en en-tête du reçu colis
-- sous le nom de la compagnie (voir colis_receipt_lines.dart /
-- printer_service.dart / ColisReceiptPanel). Distinct du téléphone de
-- gare (Gares.phone, migration 175).
ALTER TABLE "Companies" ADD COLUMN IF NOT EXISTS "phone" varchar;

-- Expose companyPhone et gareDestinationPhone dans get_colis_autonome_detail
-- (RPC utilisée pour l'impression du reçu) — le téléphone de la gare de
-- destination s'affiche désormais sous le champ "Destination" du reçu, au
-- même titre que le téléphone de la gare de départ sous "Agence".
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
  SELECT jsonb_build_object('id', ca.id, 'companyId', ca.company_id, 'statutColis', ca.statut_colis, 'nomExpediteur', ca.nom_expediteur, 'telephoneExpediteur', ca.telephone_expediteur, 'nomDestinataire', ca.nom_destinataire, 'telephoneDestinataire', ca.telephone_destinataire, 'descriptionContenu', ca.description_contenu, 'poidsKg', ca.poids_kg, 'nombrePieces', ca.nombre_pieces, 'montantFret', ca.montant_fret, 'valeurMarchandise', ca.valeur_marchandise, 'sourceVente', ca.source_vente, 'createdAt', ca.created_at, 'updatedAt', ca.updated_at, 'gareDepartId', ca.gare_depart_id, 'gareDestinationId', ca.gare_destination_id, 'gareDepart', gd.name, 'gareDepartPhone', gd.phone, 'gareDestination', gdest.name, 'gareDestinationPhone', gdest.phone, 'companyName', c.name, 'companyPhone', c.phone,
    'natureIds', COALESCE((SELECT jsonb_agg(cns.nature_id) FROM public.colis_natures_selectionnees cns WHERE cns.colis_id = ca.id), '[]'::jsonb),
    'natures', COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb))
  INTO v_row FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id JOIN "Companies" c ON c.id = ca.company_id WHERE ca.id = p_colis_id;
  RETURN v_row;
END; $function$;
