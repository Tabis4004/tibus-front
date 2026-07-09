-- Suppression d'un itinéraire par l'owner (ou super_admin), avec garde-fou :
-- refuse si des réservations y sont rattachées (historique billets/compta),
-- auquel cas il faut désactiver la programmation à la place.
-- Supprime les enfants sans réservation : jours programmés, arrêts/segments,
-- bus assignés. PromoCodes.trajetId est détaché (NULL), les mappings
-- partenaires partent en cascade (FK ON DELETE CASCADE).

CREATE OR REPLACE FUNCTION public.delete_owner_route(p_trajet_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_company uuid;
  v_reservations integer;
BEGIN
  SELECT g."companyId" INTO v_company
  FROM public."ProgrammationTrajets" t
  JOIN public."Gares" g ON g.id = t.depart
  WHERE t.id = p_trajet_id;

  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Itinéraire introuvable';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company, ARRAY['owner'])
  ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT count(*) INTO v_reservations
  FROM public."Reservations"
  WHERE "trajetId" = p_trajet_id;

  IF v_reservations > 0 THEN
    RAISE EXCEPTION 'Suppression impossible : % reservation(s) liee(s) a cet itineraire. Desactivez la programmation a la place.', v_reservations;
  END IF;

  UPDATE public."PromoCodes" SET "trajetId" = NULL WHERE "trajetId" = p_trajet_id;
  DELETE FROM public."ProgrammationBus" WHERE "trajetId" = p_trajet_id;
  DELETE FROM public."ProgrammationTrajetDays" WHERE "trajetId" = p_trajet_id;
  DELETE FROM public."ProgrammationTrajetArrets" WHERE "trajetId" = p_trajet_id;
  DELETE FROM public."ProgrammationTrajets" WHERE id = p_trajet_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.delete_owner_route(uuid) FROM PUBLIC, anon;
