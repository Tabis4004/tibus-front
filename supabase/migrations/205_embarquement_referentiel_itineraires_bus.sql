-- ============================================================================
-- Embarquement — référentiel hors-Tibus (itinéraires + bus), Phase 0.
-- Complète le travail déjà en place par ailleurs (embarquement_sessions/
-- embarquement_scans/embarquement_expected_passengers +
-- can_use_embarquement/embarquement_create_session/list_sessions/
-- update_session) sans y toucher. Convention de nommage et pattern
-- RLS/SECURITY DEFINER repris à l'identique de l'existant.
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-03
-- (nom de migration côté Supabase : embarquement_referentiel_itineraires_bus).
-- ============================================================================

CREATE TABLE public.embarquement_itineraires (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES "Companies"(id) ON DELETE CASCADE,
  origin_label text NOT NULL,
  destination_label text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES "Users"(id)
);
CREATE INDEX embarquement_itineraires_company_idx ON public.embarquement_itineraires(company_id) WHERE active;
ALTER TABLE public.embarquement_itineraires ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.embarquement_buses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES "Companies"(id) ON DELETE CASCADE,
  label text NOT NULL,
  capacity integer NOT NULL CHECK (capacity > 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES "Users"(id)
);
CREATE INDEX embarquement_buses_company_idx ON public.embarquement_buses(company_id) WHERE active;
ALTER TABLE public.embarquement_buses ENABLE ROW LEVEL SECURITY;

-- Lecture : même périmètre que embarquement_sessions_select (tout rôle
-- Embarquement de la compagnie). Écriture : uniquement via RPC ci-dessous.
CREATE POLICY embarquement_itineraires_select ON public.embarquement_itineraires FOR SELECT
  USING (public.is_super_admin() OR public.has_company_role(company_id, ARRAY['owner','controleur','vendeur','chauffeur']));

CREATE POLICY embarquement_buses_select ON public.embarquement_buses FOR SELECT
  USING (public.is_super_admin() OR public.has_company_role(company_id, ARRAY['owner','controleur','vendeur','chauffeur']));

-- Gate admin (écriture référentiel) : owner/super_admin uniquement — plus
-- restreint que can_use_embarquement (lecture/scan).
CREATE OR REPLACE FUNCTION public.can_admin_embarquement(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner']);
$$;

-- Itinéraires -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.embarquement_list_itineraires(p_company_id uuid)
RETURNS TABLE(id uuid, origin_label text, destination_label text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT i.id, i.origin_label, i.destination_label
  FROM public.embarquement_itineraires i
  WHERE i.company_id = p_company_id AND i.active
  ORDER BY i.origin_label, i.destination_label;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_upsert_itineraire(
  p_company_id uuid,
  p_origin_label text,
  p_destination_label text,
  p_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_id uuid;
BEGIN
  IF NOT public.can_admin_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants pour gerer le referentiel Embarquement';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_origin_label, '')), '') IS NULL
     OR NULLIF(BTRIM(COALESCE(p_destination_label, '')), '') IS NULL THEN
    RAISE EXCEPTION 'origin_label et destination_label requis';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.embarquement_itineraires (company_id, origin_label, destination_label, created_by)
    VALUES (p_company_id, BTRIM(p_origin_label), BTRIM(p_destination_label), v_user)
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.embarquement_itineraires
    SET origin_label = BTRIM(p_origin_label), destination_label = BTRIM(p_destination_label)
    WHERE id = p_id AND company_id = p_company_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Itineraire introuvable'; END IF;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_delete_itineraire(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id FROM public.embarquement_itineraires WHERE id = p_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Itineraire introuvable'; END IF;
  IF NOT public.can_admin_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants pour gerer le referentiel Embarquement';
  END IF;
  UPDATE public.embarquement_itineraires SET active = false WHERE id = p_id;
END;
$$;

-- Bus ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.embarquement_list_buses(p_company_id uuid)
RETURNS TABLE(id uuid, label text, capacity integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT b.id, b.label, b.capacity
  FROM public.embarquement_buses b
  WHERE b.company_id = p_company_id AND b.active
  ORDER BY b.label;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_upsert_bus(
  p_company_id uuid,
  p_label text,
  p_capacity integer,
  p_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_id uuid;
BEGIN
  IF NOT public.can_admin_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants pour gerer le referentiel Embarquement';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_label, '')), '') IS NULL THEN
    RAISE EXCEPTION 'label requis';
  END IF;
  IF p_capacity IS NULL OR p_capacity <= 0 THEN
    RAISE EXCEPTION 'capacity doit etre superieure a 0';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.embarquement_buses (company_id, label, capacity, created_by)
    VALUES (p_company_id, BTRIM(p_label), p_capacity, v_user)
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.embarquement_buses
    SET label = BTRIM(p_label), capacity = p_capacity
    WHERE id = p_id AND company_id = p_company_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Bus introuvable'; END IF;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_delete_bus(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id FROM public.embarquement_buses WHERE id = p_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Bus introuvable'; END IF;
  IF NOT public.can_admin_embarquement(v_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants pour gerer le referentiel Embarquement';
  END IF;
  UPDATE public.embarquement_buses SET active = false WHERE id = p_id;
END;
$$;
