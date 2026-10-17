-- 222 — Abonnements par application (Courrier, Embarquement, Comptabilité)
--
-- Une date de fin par compagnie et par application. Après cette date, plus
-- aucune écriture (vente colis, session ou scan d'embarquement, dépense) :
-- l'application passe en lecture seule. L'app affiche un pop-up au owner un
-- mois avant la date et la date de fin dans son profil. Saisie des dates :
-- super admin (admin_set_company_app_subscription). Compagnie sans ligne :
-- aucune restriction.

-- 1. Date de fin d'abonnement par application et par compagnie.
--    app_key : 'courrier' (courrier_mobile), 'embarquement',
--    'comptabilite' (dépenses + bilan SYSCOHADA, option payante).
--    Pas de ligne = pas de restriction (compagnies existantes) ;
--    end_date NULL = illimité.
CREATE TABLE IF NOT EXISTS public.company_app_subscriptions (
  company_id uuid NOT NULL REFERENCES public."Companies"(id) ON DELETE CASCADE,
  app_key text NOT NULL CHECK (app_key IN ('courrier', 'embarquement', 'comptabilite')),
  end_date timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  PRIMARY KEY (company_id, app_key)
);
ALTER TABLE public.company_app_subscriptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.company_app_subscriptions FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._app_label(p_app text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE p_app
    WHEN 'courrier' THEN 'Courrier'
    WHEN 'embarquement' THEN 'Embarquement'
    WHEN 'comptabilite' THEN 'Comptabilite (depenses et bilan)'
    ELSE p_app END;
$fn$;

-- 2. Lecture seule après la date de fin : toute écriture est refusée.
--    [p_at] : heure réelle de l'opération (une vente faite hors ligne AVANT
--    la fin reste acceptée à sa synchronisation).
CREATE OR REPLACE FUNCTION public._assert_app_writable(p_company_id uuid, p_app text, p_at timestamptz DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_end timestamptz;
BEGIN
  IF p_company_id IS NULL OR public.is_super_admin() THEN RETURN; END IF;
  SELECT end_date INTO v_end FROM public.company_app_subscriptions
  WHERE company_id = p_company_id AND app_key = p_app;
  IF v_end IS NOT NULL AND COALESCE(p_at, now()) > v_end THEN
    RAISE EXCEPTION 'Abonnement % expire le % : application en lecture seule. Contactez Tabis Technology pour le renouveler.',
      public._app_label(p_app), to_char(v_end, 'DD/MM/YYYY');
  END IF;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._trg_app_writable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_data jsonb;
  v_company uuid;
  v_at timestamptz;
BEGIN
  v_data := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  IF TG_TABLE_NAME IN ('colis_autonomes', 'embarquement_sessions') THEN
    v_company := (v_data->>'company_id')::uuid;
  ELSIF TG_TABLE_NAME = 'embarquement_scans' THEN
    SELECT company_id INTO v_company FROM public.embarquement_sessions
    WHERE id = (v_data->>'session_id')::uuid;
  ELSIF TG_TABLE_NAME = 'CompanyExpense' THEN
    v_company := (v_data->>'companyId')::uuid;
  END IF;
  IF TG_TABLE_NAME = 'colis_autonomes' THEN
    v_at := NULLIF(current_setting('tibus.offline_sale_at', true), '')::timestamptz;
  END IF;
  PERFORM public._assert_app_writable(v_company, TG_ARGV[0], v_at);
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE TRIGGER app_writable_courrier
  BEFORE INSERT OR UPDATE ON public.colis_autonomes
  FOR EACH ROW EXECUTE FUNCTION public._trg_app_writable('courrier');

DO $mig$
BEGIN
  IF to_regclass('public.embarquement_sessions') IS NOT NULL THEN
    EXECUTE 'CREATE OR REPLACE TRIGGER app_writable_embarquement_sessions
      BEFORE INSERT ON public.embarquement_sessions
      FOR EACH ROW EXECUTE FUNCTION public._trg_app_writable(''embarquement'')';
    EXECUTE 'CREATE OR REPLACE TRIGGER app_writable_embarquement_scans
      BEFORE INSERT ON public.embarquement_scans
      FOR EACH ROW EXECUTE FUNCTION public._trg_app_writable(''embarquement'')';
  END IF;
  IF to_regclass('public."CompanyExpense"') IS NOT NULL THEN
    EXECUTE 'CREATE OR REPLACE TRIGGER app_writable_comptabilite
      BEFORE INSERT OR UPDATE OR DELETE ON public."CompanyExpense"
      FOR EACH ROW EXECUTE FUNCTION public._trg_app_writable(''comptabilite'')';
  END IF;
END
$mig$;

-- Vente hors ligne : l'heure réelle de la vente sert de référence.
DO $mig$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.register_colis_autonome_offline(text,timestamptz,uuid,uuid,uuid,text,text,text,text,text,double precision,integer,double precision,uuid[],double precision,double precision,uuid,jsonb)'::regprocedure);
  IF position('tibus.offline_sale_at' IN v_def) = 0 THEN
    IF position('IF v_local_id IS NULL THEN RAISE EXCEPTION ''Identifiant hors-ligne manquant''; END IF;' IN v_def) = 0 THEN
      RAISE EXCEPTION 'register_colis_autonome_offline : point d''insertion introuvable, migration a adapter';
    END IF;
    EXECUTE replace(v_def,
      'IF v_local_id IS NULL THEN RAISE EXCEPTION ''Identifiant hors-ligne manquant''; END IF;',
      'IF v_local_id IS NULL THEN RAISE EXCEPTION ''Identifiant hors-ligne manquant''; END IF;
  PERFORM set_config(''tibus.offline_sale_at'', COALESCE(p_offline_created_at, now())::text, true);');
  END IF;
END
$mig$;

-- 3. Abonnements d'une compagnie, pour l'app (pop-up un mois avant la fin,
--    profil du owner, mode lecture seule).
CREATE OR REPLACE FUNCTION public.get_company_app_subscriptions(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_user uuid := public.current_app_user_id();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_super_admin() OR EXISTS (
    SELECT 1 FROM "UserRoles" ur WHERE ur."userId" = v_user AND ur."companyId" = p_company_id
  )) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'appKey', s.app_key,
      'label', public._app_label(s.app_key),
      'endDate', s.end_date,
      'daysLeft', CASE WHEN s.end_date IS NULL THEN NULL
                       ELSE floor(extract(epoch FROM (s.end_date - now())) / 86400)::int END,
      'state', CASE WHEN s.end_date IS NULL THEN 'active'
                    WHEN s.end_date < now() THEN 'expired'
                    WHEN s.end_date < now() + interval '30 days' THEN 'warning'
                    ELSE 'active' END
    ) ORDER BY s.app_key)
    FROM public.company_app_subscriptions s
    WHERE s.company_id = p_company_id
  ), '[]'::jsonb);
END;
$fn$;

-- 4. Saisie des dates de fin (super admin uniquement).
CREATE OR REPLACE FUNCTION public.admin_set_company_app_subscription(p_company_id uuid, p_app_key text, p_end_date timestamptz)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  INSERT INTO public.company_app_subscriptions (company_id, app_key, end_date, updated_at, updated_by)
  VALUES (p_company_id, p_app_key, p_end_date, now(), public.current_app_user_id())
  ON CONFLICT (company_id, app_key)
  DO UPDATE SET end_date = EXCLUDED.end_date, updated_at = now(), updated_by = EXCLUDED.updated_by;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.get_company_app_subscriptions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_company_app_subscription(uuid, text, timestamptz) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_set_company_app_subscription(uuid, text, timestamptz), public.get_company_app_subscriptions(uuid) FROM anon, public;
