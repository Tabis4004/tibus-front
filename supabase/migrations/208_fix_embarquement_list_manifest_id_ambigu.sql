-- 208 — embarquement_list_manifest : "column reference \"id\" is ambiguous"
--
-- Symptôme : l'écran Manifeste affiche
--   PostgrestException(message: column reference "id" is ambiguous,
--   code: 42702, details: It could refer to either a PL/pgSQL variable or a
--   table column.)
-- et le manifeste est donc totalement illisible (aucune ligne, quel que soit
-- le nombre de scans enregistrés — les scans eux-mêmes passent bien).
--
-- Cause : la fonction déclare RETURNS TABLE(id uuid, ...). En PL/pgSQL, les
-- colonnes d'un RETURNS TABLE sont des VARIABLES OUT visibles dans tout le
-- corps. Le contrôle de droits en tête de fonction faisait
--   ... FROM public.embarquement_sessions WHERE id = p_session_id
-- où "id" peut désigner aussi bien la variable OUT que la colonne de la
-- table → PostgreSQL refuse (42702). Le RETURN QUERY plus bas était déjà
-- qualifié (s.id), d'où une fonction qui échoue AVANT même de lire quoi que
-- ce soit.
--
-- Correctif : aliaser la table et qualifier la colonne (es.id). Seule
-- embarquement_list_manifest cumule RETURNS TABLE(id ...) et un "id" nu ;
-- les autres fonctions du module (list_itineraires, list_buses,
-- list_company_gares, list_company_bus) sont déjà qualifiées, et celles qui
-- font "WHERE id = ..." sans alias (delete_itineraire, delete_bus,
-- close_session, scan_*) ne déclarent pas de OUT "id" — rien à y changer.

CREATE OR REPLACE FUNCTION public.embarquement_list_manifest(p_session_id uuid)
RETURNS TABLE(
  id uuid, scanned_at timestamptz, source text, passenger_name text,
  ticket_number text, origin_label text, destination_label text, status text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT es.company_id INTO v_company_id
  FROM public.embarquement_sessions es
  WHERE es.id = p_session_id;

  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT s.id, s.scanned_at, s.source, s.passenger_name, s.ticket_number,
         s.origin_label, s.destination_label, s.status
  FROM public.embarquement_scans s
  WHERE s.session_id = p_session_id AND s.deleted_at IS NULL
  ORDER BY s.scanned_at DESC;
END;
$$;
