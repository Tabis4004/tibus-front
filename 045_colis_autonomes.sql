-- Lot 45: Module autonome d'expédition de colis (fret gare à gare).

ALTER TABLE "Companies"
  ADD COLUMN IF NOT EXISTS colis_autonome_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sms_on_enregistre boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sms_on_charge boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sms_on_arrive boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sms_on_livre boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.colis_natures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  company_id uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  libelle text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT colis_natures_libelle_check CHECK (btrim(libelle) <> ''),
  CONSTRAINT colis_natures_company_libelle_key UNIQUE (company_id, libelle)
);

CREATE TABLE IF NOT EXISTS public.colis_autonomes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  company_id uuid NOT NULL REFERENCES "Companies" ("id") ON DELETE CASCADE,
  gare_depart_id uuid NOT NULL REFERENCES "Gares" ("id"),
  gare_destination_id uuid NOT NULL REFERENCES "Gares" ("id"),
  nom_expediteur text NOT NULL,
  telephone_expediteur text NOT NULL,
  nom_destinataire text NOT NULL,
  telephone_destinataire text NOT NULL,
  description_contenu text,
  poids_kg double precision,
  nombre_pieces integer NOT NULL DEFAULT 1,
  montant_fret double precision NOT NULL DEFAULT 0,
  vendeur_id uuid NOT NULL REFERENCES "Users" ("id"),
  source_vente text NOT NULL DEFAULT 'guichet_cash',
  statut_colis text NOT NULL DEFAULT 'enregistre',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT colis_autonomes_statut_check CHECK (statut_colis IN ('enregistre', 'charge', 'arrive', 'livre')),
  CONSTRAINT colis_autonomes_source_vente_check CHECK (source_vente = 'guichet_cash'),
  CONSTRAINT colis_autonomes_nombre_pieces_check CHECK (nombre_pieces > 0),
  CONSTRAINT colis_autonomes_montant_check CHECK (montant_fret >= 0),
  CONSTRAINT colis_autonomes_expediteur_check CHECK (btrim(nom_expediteur) <> ''),
  CONSTRAINT colis_autonomes_destinataire_check CHECK (btrim(nom_destinataire) <> '')
);

CREATE INDEX IF NOT EXISTS colis_autonomes_company_statut_idx ON public.colis_autonomes (company_id, statut_colis, created_at DESC);

CREATE TABLE IF NOT EXISTS public.colis_natures_selectionnees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  colis_id uuid NOT NULL REFERENCES public.colis_autonomes (id) ON DELETE CASCADE,
  nature_id uuid NOT NULL REFERENCES public.colis_natures (id) ON DELETE RESTRICT,
  CONSTRAINT colis_natures_selectionnees_unique UNIQUE (colis_id, nature_id)
);

ALTER TABLE public.colis_natures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colis_autonomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colis_natures_selectionnees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS colis_natures_select ON public.colis_natures;
CREATE POLICY colis_natures_select ON public.colis_natures FOR SELECT TO authenticated
  USING (public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin());
DROP POLICY IF EXISTS colis_natures_write ON public.colis_natures;
CREATE POLICY colis_natures_write ON public.colis_natures FOR ALL TO authenticated
  USING (public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin())
  WITH CHECK (public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin());

DROP POLICY IF EXISTS colis_autonomes_select ON public.colis_autonomes;
CREATE POLICY colis_autonomes_select ON public.colis_autonomes FOR SELECT TO authenticated
  USING (public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin());
DROP POLICY IF EXISTS colis_autonomes_write ON public.colis_autonomes;
CREATE POLICY colis_autonomes_write ON public.colis_autonomes FOR ALL TO authenticated
  USING (public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin())
  WITH CHECK (public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin());

DROP POLICY IF EXISTS colis_natures_selectionnees_select ON public.colis_natures_selectionnees;
CREATE POLICY colis_natures_selectionnees_select ON public.colis_natures_selectionnees FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.colis_autonomes ca WHERE ca.id = colis_id AND (public.is_company_role_user(public.current_app_user_id(), ca.company_id) OR public.is_super_admin())));
DROP POLICY IF EXISTS colis_natures_selectionnees_write ON public.colis_natures_selectionnees;
CREATE POLICY colis_natures_selectionnees_write ON public.colis_natures_selectionnees FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.colis_autonomes ca WHERE ca.id = colis_id AND (public.is_company_role_user(public.current_app_user_id(), ca.company_id) OR public.is_super_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.colis_autonomes ca WHERE ca.id = colis_id AND (public.is_company_role_user(public.current_app_user_id(), ca.company_id) OR public.is_super_admin())));

CREATE OR REPLACE FUNCTION public.company_colis_module_enabled(p_company_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(c.colis_autonome_enabled, false) FROM "Companies" c WHERE c.id = p_company_id;
$$;

CREATE OR REPLACE FUNCTION public.colis_sms_enabled_for_statut(p_company_id uuid, p_statut text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE p_statut WHEN 'enregistre' THEN COALESCE(c.sms_on_enregistre, false) WHEN 'charge' THEN COALESCE(c.sms_on_charge, false) WHEN 'arrive' THEN COALESCE(c.sms_on_arrive, false) WHEN 'livre' THEN COALESCE(c.sms_on_livre, false) ELSE false END FROM "Companies" c WHERE c.id = p_company_id;
$$;

CREATE OR REPLACE FUNCTION public.build_colis_sms_message(p_statut text, p_colis_id uuid, p_company_name text, p_gare_depart text, p_gare_destination text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN CASE p_statut
    WHEN 'enregistre' THEN format('Tibus/%s: colis enregistre. Code retrait: %s. %s -> %s.', COALESCE(p_company_name, 'Compagnie'), p_colis_id::text, COALESCE(p_gare_depart, '?'), COALESCE(p_gare_destination, '?'))
    WHEN 'charge' THEN format('Tibus/%s: votre colis est charge en soute (%s -> %s).', COALESCE(p_company_name, 'Compagnie'), COALESCE(p_gare_depart, '?'), COALESCE(p_gare_destination, '?'))
    WHEN 'arrive' THEN format('Tibus/%s: colis arrive a %s. Code retrait: %s.', COALESCE(p_company_name, 'Compagnie'), COALESCE(p_gare_destination, 'gare'), p_colis_id::text)
    WHEN 'livre' THEN format('Tibus/%s: colis remis au destinataire. Merci.', COALESCE(p_company_name, 'Compagnie'))
    ELSE NULL END;
END; $$;

CREATE OR REPLACE FUNCTION public.get_company_colis_settings(p_company_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id(); v_row "Companies"%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  SELECT * INTO v_row FROM "Companies" WHERE id = p_company_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Compagnie introuvable'; END IF;
  RETURN jsonb_build_object('companyId', v_row.id, 'colisAutonomeEnabled', COALESCE(v_row.colis_autonome_enabled, false), 'smsOnEnregistre', COALESCE(v_row.sms_on_enregistre, false), 'smsOnCharge', COALESCE(v_row.sms_on_charge, false), 'smsOnArrive', COALESCE(v_row.sms_on_arrive, false), 'smsOnLivre', COALESCE(v_row.sms_on_livre, false));
END; $$;

CREATE OR REPLACE FUNCTION public.update_company_colis_sms_settings(p_company_id uuid, p_sms_on_enregistre boolean, p_sms_on_charge boolean, p_sms_on_arrive boolean, p_sms_on_livre boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN RAISE EXCEPTION 'Module colis autonome non active'; END IF;
  UPDATE "Companies" SET sms_on_enregistre = COALESCE(p_sms_on_enregistre, false), sms_on_charge = COALESCE(p_sms_on_charge, false), sms_on_arrive = COALESCE(p_sms_on_arrive, false), sms_on_livre = COALESCE(p_sms_on_livre, false) WHERE id = p_company_id;
  RETURN public.get_company_colis_settings(p_company_id);
END; $$;

CREATE OR REPLACE FUNCTION public.upsert_colis_nature(p_company_id uuid, p_libelle text, p_nature_id uuid DEFAULT NULL, p_is_active boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id(); v_id uuid; v_libelle text := btrim(COALESCE(p_libelle, ''));
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, p_company_id) OR public.is_super_admin()) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN RAISE EXCEPTION 'Module colis autonome non active'; END IF;
  IF v_libelle = '' THEN RAISE EXCEPTION 'Libelle requis'; END IF;
  IF p_nature_id IS NOT NULL THEN
    UPDATE public.colis_natures SET libelle = v_libelle, is_active = COALESCE(p_is_active, true) WHERE id = p_nature_id AND company_id = p_company_id RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Nature introuvable'; END IF;
  ELSE
    INSERT INTO public.colis_natures (company_id, libelle, is_active) VALUES (p_company_id, v_libelle, COALESCE(p_is_active, true)) ON CONFLICT (company_id, libelle) DO UPDATE SET is_active = EXCLUDED.is_active RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('id', v_id, 'libelle', v_libelle, 'isActive', COALESCE(p_is_active, true));
END; $$;

CREATE OR REPLACE FUNCTION public.delete_colis_nature(p_nature_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company_id uuid; v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT company_id INTO v_company_id FROM public.colis_natures WHERE id = p_nature_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Nature introuvable'; END IF;
  IF NOT (public.is_company_role_user(v_user_id, v_company_id) OR public.is_super_admin()) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF EXISTS (SELECT 1 FROM public.colis_natures_selectionnees WHERE nature_id = p_nature_id) THEN RAISE EXCEPTION 'Nature utilisee — desactivez-la'; END IF;
  DELETE FROM public.colis_natures WHERE id = p_nature_id;
END; $$;

CREATE OR REPLACE FUNCTION public.register_colis_autonome(p_company_id uuid, p_gare_depart_id uuid, p_gare_destination_id uuid, p_nom_expediteur text, p_telephone_expediteur text, p_nom_destinataire text, p_telephone_destinataire text, p_description_contenu text, p_poids_kg double precision, p_nombre_pieces integer, p_montant_fret double precision, p_nature_ids uuid[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id(); v_colis_id uuid; v_nature_id uuid; v_company_name text; v_gare_depart text; v_gare_destination text; v_send_sms boolean; v_sms_message text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF NOT public.company_colis_module_enabled(p_company_id) THEN RAISE EXCEPTION 'Module colis autonome non active'; END IF;
  IF p_gare_depart_id = p_gare_destination_id THEN RAISE EXCEPTION 'Gares identiques'; END IF;
  IF NOT EXISTS (SELECT 1 FROM "Gares" g WHERE g.id = p_gare_depart_id AND g."companyId" = p_company_id) THEN RAISE EXCEPTION 'Gare depart invalide'; END IF;
  IF NOT EXISTS (SELECT 1 FROM "Gares" g WHERE g.id = p_gare_destination_id AND g."companyId" = p_company_id) THEN RAISE EXCEPTION 'Gare destination invalide'; END IF;
  IF COALESCE(array_length(p_nature_ids, 1), 0) = 0 THEN RAISE EXCEPTION 'Selectionnez au moins une nature'; END IF;
  INSERT INTO public.colis_autonomes (company_id, gare_depart_id, gare_destination_id, nom_expediteur, telephone_expediteur, nom_destinataire, telephone_destinataire, description_contenu, poids_kg, nombre_pieces, montant_fret, vendeur_id, source_vente, statut_colis)
  VALUES (p_company_id, p_gare_depart_id, p_gare_destination_id, btrim(p_nom_expediteur), btrim(p_telephone_expediteur), btrim(p_nom_destinataire), btrim(p_telephone_destinataire), NULLIF(btrim(COALESCE(p_description_contenu, '')), ''), NULLIF(p_poids_kg, 0), GREATEST(COALESCE(p_nombre_pieces, 1), 1), GREATEST(COALESCE(p_montant_fret, 0), 0), v_user_id, 'guichet_cash', 'enregistre') RETURNING id INTO v_colis_id;
  FOREACH v_nature_id IN ARRAY p_nature_ids LOOP
    IF NOT EXISTS (SELECT 1 FROM public.colis_natures n WHERE n.id = v_nature_id AND n.company_id = p_company_id AND n.is_active) THEN RAISE EXCEPTION 'Nature invalide'; END IF;
    INSERT INTO public.colis_natures_selectionnees (colis_id, nature_id) VALUES (v_colis_id, v_nature_id);
  END LOOP;
  SELECT c.name, gd.name, gdest.name INTO v_company_name, v_gare_depart, v_gare_destination FROM "Companies" c JOIN "Gares" gd ON gd.id = p_gare_depart_id JOIN "Gares" gdest ON gdest.id = p_gare_destination_id WHERE c.id = p_company_id;
  v_send_sms := public.colis_sms_enabled_for_statut(p_company_id, 'enregistre');
  v_sms_message := public.build_colis_sms_message('enregistre', v_colis_id, v_company_name, v_gare_depart, v_gare_destination);
  RETURN jsonb_build_object('id', v_colis_id, 'statutColis', 'enregistre', 'montantFret', GREATEST(COALESCE(p_montant_fret, 0), 0), 'sms', jsonb_build_object('send', v_send_sms, 'message', v_sms_message, 'expediteurPhone', btrim(p_telephone_expediteur), 'destinatairePhone', btrim(p_telephone_destinataire)));
END; $$;

CREATE OR REPLACE FUNCTION public.update_colis_autonome_statut(p_colis_id uuid, p_new_statut text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id(); v_colis public.colis_autonomes%ROWTYPE; v_company_name text; v_gare_depart text; v_gare_destination text; v_allowed boolean := false; v_message text; v_send boolean;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Colis introuvable'; END IF;
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF p_new_statut NOT IN ('enregistre', 'charge', 'arrive', 'livre') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  v_allowed := CASE WHEN v_colis.statut_colis = 'enregistre' AND p_new_statut = 'charge' THEN true WHEN v_colis.statut_colis = 'charge' AND p_new_statut = 'arrive' THEN true WHEN v_colis.statut_colis = 'arrive' AND p_new_statut = 'livre' THEN true WHEN p_new_statut = v_colis.statut_colis THEN true ELSE false END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Transition non autorisee: % -> %', v_colis.statut_colis, p_new_statut; END IF;
  UPDATE public.colis_autonomes SET statut_colis = p_new_statut, updated_at = now() WHERE id = p_colis_id;
  SELECT c.name, gd.name, gdest.name INTO v_company_name, v_gare_depart, v_gare_destination FROM "Companies" c JOIN "Gares" gd ON gd.id = v_colis.gare_depart_id JOIN "Gares" gdest ON gdest.id = v_colis.gare_destination_id WHERE c.id = v_colis.company_id;
  v_send := public.colis_sms_enabled_for_statut(v_colis.company_id, p_new_statut);
  v_message := public.build_colis_sms_message(p_new_statut, p_colis_id, v_company_name, v_gare_depart, v_gare_destination);
  RETURN jsonb_build_object('id', p_colis_id, 'statutColis', p_new_statut, 'sms', jsonb_build_object('send', v_send, 'message', v_message, 'expediteurPhone', v_colis.telephone_expediteur, 'destinatairePhone', v_colis.telephone_destinataire));
END; $$;

CREATE OR REPLACE FUNCTION public.deliver_colis_autonome(p_retrait_code uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id(); v_colis public.colis_autonomes%ROWTYPE; v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_retrait_code;
  IF v_colis.id IS NULL THEN RAISE EXCEPTION 'Code de retrait invalide'; END IF;
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  IF v_colis.statut_colis <> 'arrive' THEN RAISE EXCEPTION 'Colis non disponible (statut: %)', v_colis.statut_colis; END IF;
  v_result := public.update_colis_autonome_statut(v_colis.id, 'livre');
  RETURN v_result || jsonb_build_object('nomDestinataire', v_colis.nom_destinataire, 'nomExpediteur', v_colis.nom_expediteur);
END; $$;

CREATE OR REPLACE FUNCTION public.list_colis_autonomes(p_company_id uuid, p_statut text DEFAULT NULL, p_limit integer DEFAULT 50) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id(); v_rows jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_company_role_user(v_user_id, p_company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.created_at DESC), '[]'::jsonb) INTO v_rows FROM (
    SELECT ca.id, ca.statut_colis AS "statutColis", ca.nom_expediteur AS "nomExpediteur", ca.telephone_expediteur AS "telephoneExpediteur", ca.nom_destinataire AS "nomDestinataire", ca.telephone_destinataire AS "telephoneDestinataire", ca.description_contenu AS "descriptionContenu", ca.poids_kg AS "poidsKg", ca.nombre_pieces AS "nombrePieces", ca.montant_fret AS "montantFret", ca.created_at AS "createdAt", ca.updated_at AS "updatedAt", gd.name AS "gareDepart", gdest.name AS "gareDestination",
    COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb) AS "natures"
    FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id
    WHERE ca.company_id = p_company_id AND (p_statut IS NULL OR ca.statut_colis = p_statut) ORDER BY ca.created_at DESC LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  ) sub;
  RETURN v_rows;
END; $$;

CREATE OR REPLACE FUNCTION public.get_colis_autonome_detail(p_colis_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id(); v_colis public.colis_autonomes%ROWTYPE; v_row jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO v_colis FROM public.colis_autonomes WHERE id = p_colis_id;
  IF v_colis.id IS NULL THEN RETURN NULL; END IF;
  IF NOT public.is_company_role_user(v_user_id, v_colis.company_id) THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  SELECT jsonb_build_object('id', ca.id, 'companyId', ca.company_id, 'statutColis', ca.statut_colis, 'nomExpediteur', ca.nom_expediteur, 'telephoneExpediteur', ca.telephone_expediteur, 'nomDestinataire', ca.nom_destinataire, 'telephoneDestinataire', ca.telephone_destinataire, 'descriptionContenu', ca.description_contenu, 'poidsKg', ca.poids_kg, 'nombrePieces', ca.nombre_pieces, 'montantFret', ca.montant_fret, 'sourceVente', ca.source_vente, 'createdAt', ca.created_at, 'updatedAt', ca.updated_at, 'gareDepartId', ca.gare_depart_id, 'gareDestinationId', ca.gare_destination_id, 'gareDepart', gd.name, 'gareDestination', gdest.name, 'companyName', c.name,
    'natureIds', COALESCE((SELECT jsonb_agg(cns.nature_id) FROM public.colis_natures_selectionnees cns WHERE cns.colis_id = ca.id), '[]'::jsonb),
    'natures', COALESCE((SELECT jsonb_agg(n.libelle ORDER BY n.libelle) FROM public.colis_natures_selectionnees cns JOIN public.colis_natures n ON n.id = cns.nature_id WHERE cns.colis_id = ca.id), '[]'::jsonb))
  INTO v_row FROM public.colis_autonomes ca JOIN "Gares" gd ON gd.id = ca.gare_depart_id JOIN "Gares" gdest ON gdest.id = ca.gare_destination_id JOIN "Companies" c ON c.id = ca.company_id WHERE ca.id = p_colis_id;
  RETURN v_row;
END; $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.colis_natures TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.colis_autonomes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.colis_natures_selectionnees TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_colis_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_company_colis_sms_settings(uuid, boolean, boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_colis_nature(uuid, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_colis_nature(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_colis_autonome(uuid, uuid, uuid, text, text, text, text, text, double precision, integer, double precision, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_colis_autonome_statut(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deliver_colis_autonome(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_colis_autonomes(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_colis_autonome_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.company_colis_module_enabled(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_company_colis_module_enabled(p_company_id uuid, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  UPDATE "Companies" SET colis_autonome_enabled = COALESCE(p_enabled, false) WHERE id = p_company_id;
  RETURN public.get_company_colis_settings(p_company_id);
END; $$;
GRANT EXECUTE ON FUNCTION public.set_company_colis_module_enabled(uuid, boolean) TO authenticated;
