-- 212 — Les itinéraires viennent de Tibus, et l'agent ne voit que sa gare
--
-- Ce que cette migration corrige dans MA conception précédente : le module
-- s'était doté de son propre référentiel d'itinéraires (embarquement_itineraires,
-- migrations 205 et 211, tarif compris). C'était un doublon. Tibus 1.0
-- maintient déjà exactement cette information :
--
--   Gares (name, cityId, companyId)
--   ProgrammationTrajetArrets (fromGareId, toGareId, price, kilometrage)
--
-- soit « gare dans une ville, puis itinéraire gare de départ → gare d'arrivée,
-- puis prix » — le modèle décrit par l'exploitant. Tibus Kenya y a déjà ses
-- deux segments à 5 000, comme toutes les autres compagnies. Deux tables de
-- tarifs qui divergent, c'est précisément le reproche que notre client fait à
-- son prestataire actuel : on ne peut pas le reproduire dans l'outil censé
-- l'établir. embarquement_itineraires reste en base (données conservées) mais
-- sort du circuit : plus aucune RPC d'Embarquement ne la lit.
--
-- PORTÉE PAR GARE — le comportement déjà en place côté Colis
-- (list_company_station_gares, migration 198) est reproduit ici : owner,
-- controleur, vendeur et chauffeur voient toute la compagnie ; les rôles
-- rattachés à une gare ne voient que la leur. Un gérant de gare ouvrant une
-- session ne se voit donc proposer que les itinéraires PARTANT de sa gare, et
-- le serveur le revérifie à l'ouverture plutôt que de faire confiance à
-- l'écran.
--
-- can_use_embarquement s'ouvre à gerant_gare, controleur_gare et
-- comptable_gare (décision utilisateur). C'était bloquant : ces trois rôles
-- sont les SEULS à porter un gareId en base, et aucun n'avait accès au module.
--
-- DOUBLONS DE TARIF — constat : la seule collision en base (RIMBO, Dakar →
-- Badalabougou) vient de DEUX trajets distincts couvrant le même segment au
-- même prix, pas d'une ligne dupliquée. Interdire à deux trajets de partager
-- un segment casserait la modélisation d'un réseau à arrêts intermédiaires ;
-- l'index unique porte donc sur (trajetId, fromGareId, toGareId), la vraie
-- clé naturelle — aucune violation actuelle. Et si deux trajets annoncent des
-- prix DIFFÉRENTS pour un même couple de gares, embarquement_list_trajets le
-- signale (price_conflict) et l'ouverture de session est refusée : mieux vaut
-- bloquer que compter une recette sur un prix arbitraire.
--
-- HISTORIQUE DES PRIX — trajet_arret_price_log enregistre qui change un tarif,
-- quand, et de combien à combien. Le trigger est posé sur une table du cœur de
-- Tibus, utilisée par la billetterie web : il est volontairement défensif
-- (current_app_user_id() capturé dans un bloc EXCEPTION) pour ne jamais faire
-- échouer une écriture de la billetterie.
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-23
-- (nom côté Supabase : embarquement_itineraires_tibus_et_portee_gare).

CREATE OR REPLACE FUNCTION public.can_use_embarquement(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY[
         'owner', 'controleur', 'vendeur', 'chauffeur',
         'gerant_gare', 'controleur_gare', 'comptable_gare'
       ]);
$$;

CREATE OR REPLACE FUNCTION public.embarquement_sees_all_gares(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'controleur', 'vendeur', 'chauffeur']);
$$;

CREATE OR REPLACE FUNCTION public.embarquement_my_gares(p_company_id uuid)
RETURNS TABLE(id uuid, name text, city_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF public.embarquement_sees_all_gares(p_company_id) THEN
    RETURN QUERY
    SELECT g.id, g.name::text, COALESCE(c.name::text, '')
    FROM public."Gares" g
    LEFT JOIN public."Cities" c ON c.id = g."cityId"
    WHERE g."companyId" = p_company_id
      AND g."isActive"
      AND g.name <> '__CASH_SESSION_HUB__'
      AND g.name NOT LIKE '\_\_%'
    ORDER BY g.name;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT g.id, g.name::text, COALESCE(c.name::text, '')
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  JOIN public."Gares" g ON g.id = ur."gareId"
  LEFT JOIN public."Cities" c ON c.id = g."cityId"
  WHERE ur."userId" = v_user
    AND ur."companyId" = p_company_id
    AND ur."gareId" IS NOT NULL
    AND r.name IN ('gerant_gare', 'controleur_gare', 'comptable_gare', 'vendeur_gare')
    AND g."isActive"
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY 2;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_list_trajets(p_company_id uuid)
RETURNS TABLE(
  from_gare_id uuid, from_gare text, from_city text,
  to_gare_id uuid, to_gare text, to_city text,
  price numeric, price_conflict boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT a."fromGareId", gf.name::text, COALESCE(cf.name::text, ''),
         a."toGareId", gt.name::text, COALESCE(ct.name::text, ''),
         min(a.price)::numeric,
         (min(a.price) IS DISTINCT FROM max(a.price)) AS price_conflict
  FROM public."ProgrammationTrajetArrets" a
  JOIN public."Gares" gf ON gf.id = a."fromGareId"
  JOIN public."Gares" gt ON gt.id = a."toGareId"
  LEFT JOIN public."Cities" cf ON cf.id = gf."cityId"
  LEFT JOIN public."Cities" ct ON ct.id = gt."cityId"
  WHERE gf."companyId" = p_company_id
    AND a."fromGareId" IN (SELECT mg.id FROM public.embarquement_my_gares(p_company_id) mg)
    AND a.price IS NOT NULL
  GROUP BY a."fromGareId", gf.name, cf.name, a."toGareId", gt.name, ct.name
  ORDER BY gf.name, gt.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_open_session_gare(
  p_company_id uuid,
  p_from_gare_id uuid,
  p_to_gare_id uuid,
  p_bus_label text DEFAULT NULL,
  p_capacity_declared integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_from text;
  v_to text;
  v_min numeric(12, 2);
  v_max numeric(12, 2);
  v_session_id uuid;
  v_route text;
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.embarquement_my_gares(p_company_id) mg WHERE mg.id = p_from_gare_id
  ) THEN
    RAISE EXCEPTION 'Gare de depart hors de votre perimetre';
  END IF;

  SELECT gf.name::text, gt.name::text, min(a.price), max(a.price)
  INTO v_from, v_to, v_min, v_max
  FROM public."ProgrammationTrajetArrets" a
  JOIN public."Gares" gf ON gf.id = a."fromGareId"
  JOIN public."Gares" gt ON gt.id = a."toGareId"
  WHERE a."fromGareId" = p_from_gare_id
    AND a."toGareId" = p_to_gare_id
    AND gf."companyId" = p_company_id
    AND a.price IS NOT NULL
  GROUP BY gf.name, gt.name;

  IF v_from IS NULL THEN
    RAISE EXCEPTION 'Itineraire introuvable ou sans tarif dans Tibus';
  END IF;
  IF v_min IS DISTINCT FROM v_max THEN
    RAISE EXCEPTION 'Tarifs contradictoires pour cet itineraire dans Tibus (% vs %)', v_min, v_max;
  END IF;
  IF p_capacity_declared IS NULL OR p_capacity_declared <= 0 THEN
    RAISE EXCEPTION 'Capacite requise';
  END IF;

  v_route := v_from || ' → ' || v_to;

  INSERT INTO public.embarquement_sessions
    (company_id, route_label, bus_label, capacity_declared, gare_id, fare_amount, opened_by)
  VALUES
    (p_company_id, v_route, NULLIF(BTRIM(COALESCE(p_bus_label, '')), ''),
     p_capacity_declared, p_from_gare_id, v_min, v_user)
  RETURNING id INTO v_session_id;

  RETURN jsonb_build_object('id', v_session_id, 'fare_amount', v_min, 'route_label', v_route);
END;
$$;

CREATE TABLE IF NOT EXISTS public.trajet_arret_price_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  arret_id uuid NOT NULL,
  trajet_id uuid,
  from_gare_id uuid,
  to_gare_id uuid,
  old_price double precision,
  new_price double precision,
  changed_by uuid REFERENCES public."Users"(id),
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS trajet_arret_price_log_idx
  ON public.trajet_arret_price_log(arret_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.log_trajet_arret_price()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid;
BEGIN
  -- Défensif : ce trigger vit sur une table de la billetterie web. Une erreur
  -- ici ne doit jamais faire échouer une vente.
  BEGIN
    v_user := public.current_app_user_id();
  EXCEPTION WHEN OTHERS THEN
    v_user := NULL;
  END;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.trajet_arret_price_log
      (arret_id, trajet_id, from_gare_id, to_gare_id, old_price, new_price, changed_by)
    VALUES (NEW.id, NEW."trajetId", NEW."fromGareId", NEW."toGareId", NULL, NEW.price, v_user);
    RETURN NEW;
  END IF;

  IF NEW.price IS DISTINCT FROM OLD.price THEN
    INSERT INTO public.trajet_arret_price_log
      (arret_id, trajet_id, from_gare_id, to_gare_id, old_price, new_price, changed_by)
    VALUES (NEW.id, NEW."trajetId", NEW."fromGareId", NEW."toGareId", OLD.price, NEW.price, v_user);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trajet_arret_price_log_trg ON public."ProgrammationTrajetArrets";
CREATE TRIGGER trajet_arret_price_log_trg
  AFTER INSERT OR UPDATE OF price ON public."ProgrammationTrajetArrets"
  FOR EACH ROW EXECUTE FUNCTION public.log_trajet_arret_price();

CREATE UNIQUE INDEX IF NOT EXISTS programmation_trajet_arrets_unique_segment
  ON public."ProgrammationTrajetArrets" ("trajetId", "fromGareId", "toGareId");

GRANT EXECUTE ON FUNCTION public.embarquement_my_gares(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_list_trajets(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_open_session_gare(uuid, uuid, uuid, text, integer) TO authenticated;
