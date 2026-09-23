-- 211 — Le tarif vient du référentiel, plus jamais du téléphone
--
-- CONTEXTE (décisif pour comprendre chaque choix ci-dessous) : le premier
-- client, TSR Côte d'Ivoire, exploite déjà une billetterie tierce et a été
-- victime d'une sous-déclaration de recettes. Embarquement sert de COMPTEUR
-- INDÉPENDANT : on scanne les billets au portillon et on compare le total à
-- ce que l'autre application déclare. L'outil n'a donc de valeur que si
-- personne, sur le terrain, ne peut influencer le montant.
--
-- Ce que cette migration corrige, et c'était une faille réelle :
-- embarquement_scan_external recevait p_amount DEPUIS LE CLIENT (migration
-- 210). Même sans champ à l'écran, un APK modifié ou un appel direct à
-- PostgREST avec la clé anon pouvait écrire n'importe quel montant — donc
-- fabriquer la preuve censée confondre la fraude. Le paramètre disparaît :
-- le serveur lit lui-même le tarif figé sur la session.
--
-- Chaîne de confiance mise en place :
--   1. Un owner/super_admin déclare le tarif d'un itinéraire (price), via
--      embarquement_upsert_itineraire qui exige can_admin_embarquement.
--   2. Chaque changement de tarif est journalisé (qui, quand, ancien, nouveau)
--      par trigger — sans ça, un admin pourrait baisser un tarif après coup
--      et la vérification ne vaudrait plus rien a posteriori.
--   3. À l'ouverture, embarquement_open_session COPIE ce tarif sur la session
--      (fare_amount). Figé : une modification ultérieure du référentiel ne
--      réécrit pas l'histoire d'une session déjà tenue.
--   4. Au scan, le montant est ce fare_amount. L'agent n'a aucun champ, aucun
--      choix, aucune touche.
--
-- Le libellé du trajet est lui aussi dérivé du référentiel, pas transmis par
-- le client : autrement l'ouvreur pourrait afficher un trajet et en facturer
-- un autre. La saisie libre du trajet disparaît côté écran (décision
-- utilisateur) — une session ne peut naître que d'un itinéraire déclaré, et
-- seulement s'il a un tarif (RAISE sinon, plutôt qu'une session muette qui
-- produirait une recette à zéro).
--
-- Traçabilité demandée : embarquement_session_info renvoie le nom de qui a
-- ouvert et de qui a clôturé, pour affichage sur le manifeste et sur le
-- rapport financier. L'accès à l'ouverture reste donné aux agents comme au
-- gérant de gare / comptable — c'est le nom qui rend le choix responsable.
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-23
-- (nom côté Supabase : embarquement_tarif_referentiel_et_session).

ALTER TABLE public.embarquement_itineraires
  ADD COLUMN IF NOT EXISTS price numeric(12, 2);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'embarquement_itineraires_price_positive') THEN
    ALTER TABLE public.embarquement_itineraires
      ADD CONSTRAINT embarquement_itineraires_price_positive CHECK (price IS NULL OR price >= 0);
  END IF;
END $$;

-- Journal des tarifs : la pièce qui rend la vérification opposable dans le
-- temps. Un tarif modifié après un départ laisse une trace nominative.
CREATE TABLE IF NOT EXISTS public.embarquement_itineraire_price_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  itineraire_id uuid NOT NULL REFERENCES public.embarquement_itineraires(id) ON DELETE CASCADE,
  old_price numeric(12, 2),
  new_price numeric(12, 2),
  changed_by uuid REFERENCES public."Users"(id),
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS embarquement_itineraire_price_log_idx
  ON public.embarquement_itineraire_price_log(itineraire_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.embarquement_log_itineraire_price()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.price IS NOT NULL THEN
      INSERT INTO public.embarquement_itineraire_price_log(itineraire_id, old_price, new_price, changed_by)
      VALUES (NEW.id, NULL, NEW.price, public.current_app_user_id());
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.price IS DISTINCT FROM OLD.price THEN
    INSERT INTO public.embarquement_itineraire_price_log(itineraire_id, old_price, new_price, changed_by)
    VALUES (NEW.id, OLD.price, NEW.price, public.current_app_user_id());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS embarquement_itineraire_price_log_trg ON public.embarquement_itineraires;
CREATE TRIGGER embarquement_itineraire_price_log_trg
  AFTER INSERT OR UPDATE OF price ON public.embarquement_itineraires
  FOR EACH ROW EXECUTE FUNCTION public.embarquement_log_itineraire_price();

-- Tarif FIGÉ sur la session : une session tenue hier garde le tarif d'hier.
ALTER TABLE public.embarquement_sessions
  ADD COLUMN IF NOT EXISTS itineraire_id uuid REFERENCES public.embarquement_itineraires(id),
  ADD COLUMN IF NOT EXISTS fare_amount numeric(12, 2);

-- RETURNS TABLE modifié → DROP obligatoire, CREATE OR REPLACE ne suffit pas.
DROP FUNCTION IF EXISTS public.embarquement_list_itineraires(uuid);
CREATE FUNCTION public.embarquement_list_itineraires(p_company_id uuid)
RETURNS TABLE(id uuid, origin_label text, destination_label text, price numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT i.id, i.origin_label, i.destination_label, i.price
  FROM public.embarquement_itineraires i
  WHERE i.company_id = p_company_id AND i.active
  ORDER BY i.origin_label, i.destination_label;
END;
$$;

-- p_price ajouté → nouvelle signature. DROP de l'ancienne à 4 arguments,
-- sinon PostgREST hésite entre les deux ("function is not unique", cf. 203).
DROP FUNCTION IF EXISTS public.embarquement_upsert_itineraire(uuid, text, text, uuid);
CREATE OR REPLACE FUNCTION public.embarquement_upsert_itineraire(
  p_company_id uuid,
  p_origin_label text,
  p_destination_label text,
  p_id uuid DEFAULT NULL,
  p_price numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.can_admin_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_origin_label, '')), '') IS NULL
     OR NULLIF(BTRIM(COALESCE(p_destination_label, '')), '') IS NULL THEN
    RAISE EXCEPTION 'origine et destination requises';
  END IF;
  IF p_price IS NOT NULL AND p_price < 0 THEN
    RAISE EXCEPTION 'tarif invalide';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.embarquement_itineraires
      (company_id, origin_label, destination_label, price, created_by)
    VALUES (p_company_id, BTRIM(p_origin_label), BTRIM(p_destination_label),
            round(p_price, 2), public.current_app_user_id())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.embarquement_itineraires
    SET origin_label = BTRIM(p_origin_label),
        destination_label = BTRIM(p_destination_label),
        price = round(p_price, 2)
    WHERE id = p_id AND company_id = p_company_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Itineraire introuvable'; END IF;
  END IF;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

-- Ouverture de session hors-Tibus : le trajet ET le tarif sortent du
-- référentiel, le client ne transmet qu'un identifiant d'itinéraire.
-- embarquement_create_session (historique, Tibus) reste en place, intacte.
CREATE OR REPLACE FUNCTION public.embarquement_open_session(
  p_company_id uuid,
  p_itineraire_id uuid,
  p_bus_label text DEFAULT NULL,
  p_capacity_declared integer DEFAULT NULL,
  p_gare_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_origin text;
  v_dest text;
  v_price numeric(12, 2);
  v_session_id uuid;
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT i.origin_label, i.destination_label, i.price
  INTO v_origin, v_dest, v_price
  FROM public.embarquement_itineraires i
  WHERE i.id = p_itineraire_id AND i.company_id = p_company_id AND i.active;

  IF v_origin IS NULL THEN
    RAISE EXCEPTION 'Itineraire introuvable pour cette compagnie';
  END IF;
  IF v_price IS NULL THEN
    RAISE EXCEPTION 'Tarif non defini pour cet itineraire';
  END IF;
  IF p_capacity_declared IS NULL OR p_capacity_declared <= 0 THEN
    RAISE EXCEPTION 'Capacite requise';
  END IF;

  INSERT INTO public.embarquement_sessions
    (company_id, itineraire_id, route_label, bus_label, capacity_declared,
     gare_id, fare_amount, opened_by)
  VALUES
    (p_company_id, p_itineraire_id, v_origin || ' → ' || v_dest,
     NULLIF(BTRIM(COALESCE(p_bus_label, '')), ''), p_capacity_declared,
     p_gare_id, v_price, v_user)
  RETURNING id INTO v_session_id;

  RETURN jsonb_build_object('id', v_session_id, 'fare_amount', v_price,
                            'route_label', v_origin || ' → ' || v_dest);
END;
$$;

-- LA correction de fond : p_amount disparaît. Le montant n'est plus une
-- donnée d'entrée, c'est une lecture serveur du tarif figé sur la session.
DROP FUNCTION IF EXISTS public.embarquement_scan_external(uuid, text, text, text, text, text, numeric);
CREATE OR REPLACE FUNCTION public.embarquement_scan_external(
  p_session_id uuid,
  p_raw_payload text,
  p_passenger_name text,
  p_ticket_number text DEFAULT NULL,
  p_origin_label text DEFAULT NULL,
  p_destination_label text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_closed timestamptz;
  v_fare numeric(12, 2);
  v_user uuid := public.current_app_user_id();
  v_status text := 'valid';
  v_scan_id uuid;
  v_dup_count integer;
BEGIN
  SELECT es.company_id, es.closed_at, es.fare_amount
  INTO v_company_id, v_closed, v_fare
  FROM public.embarquement_sessions es WHERE es.id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF v_closed IS NOT NULL THEN
    RAISE EXCEPTION 'Session cloturee';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_passenger_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'passenger_name requis';
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_ticket_number, '')), '') IS NOT NULL THEN
    SELECT count(*) INTO v_dup_count
    FROM public.embarquement_scans s
    WHERE s.session_id = p_session_id
      AND s.deleted_at IS NULL
      AND s.status = 'valid'
      AND s.ticket_number IS NOT NULL
      AND UPPER(BTRIM(s.ticket_number)) = UPPER(BTRIM(p_ticket_number));
    IF v_dup_count > 0 THEN
      v_status := 'duplicate';
    END IF;
  END IF;

  INSERT INTO public.embarquement_scans
    (session_id, scanned_by, raw_payload, source, passenger_name, ticket_number,
     origin_label, destination_label, status, amount)
  VALUES
    (p_session_id, v_user, p_raw_payload, 'external', BTRIM(p_passenger_name),
     NULLIF(BTRIM(COALESCE(p_ticket_number, '')), ''),
     NULLIF(BTRIM(COALESCE(p_origin_label, '')), ''),
     NULLIF(BTRIM(COALESCE(p_destination_label, '')), ''), v_status, v_fare)
  RETURNING id INTO v_scan_id;

  RETURN jsonb_build_object('scanId', v_scan_id, 'status', v_status, 'amount', v_fare);
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_user_label(p_user uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT NULLIF(BTRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')), '')
         || COALESCE('', '')
    FROM public."Users" u WHERE u.id = p_user;
$$;

-- Qui a ouvert, qui a clôturé, à quel tarif — affiché sur le manifeste et
-- sur le rapport financier.
CREATE OR REPLACE FUNCTION public.embarquement_session_info(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_out jsonb;
BEGIN
  SELECT es.company_id INTO v_company_id
  FROM public.embarquement_sessions es WHERE es.id = p_session_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Session introuvable'; END IF;
  IF NOT public.can_use_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  SELECT jsonb_build_object(
    'id', es.id,
    'route_label', es.route_label,
    'bus_label', es.bus_label,
    'capacity_declared', es.capacity_declared,
    'fare_amount', es.fare_amount,
    'itineraire_id', es.itineraire_id,
    'opened_at', es.opened_at,
    'closed_at', es.closed_at,
    'opened_by_name', COALESCE(public.embarquement_user_label(es.opened_by), uo.username, uo.email, 'Inconnu'),
    'closed_by_name', COALESCE(public.embarquement_user_label(es.closed_by), uc.username, uc.email)
  )
  INTO v_out
  FROM public.embarquement_sessions es
  LEFT JOIN public."Users" uo ON uo.id = es.opened_by
  LEFT JOIN public."Users" uc ON uc.id = es.closed_by
  WHERE es.id = p_session_id;

  RETURN v_out;
END;
$$;

GRANT EXECUTE ON FUNCTION public.embarquement_open_session(uuid, uuid, text, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_session_info(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_list_itineraires(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_upsert_itineraire(uuid, text, text, uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_scan_external(uuid, text, text, text, text, text) TO authenticated;
