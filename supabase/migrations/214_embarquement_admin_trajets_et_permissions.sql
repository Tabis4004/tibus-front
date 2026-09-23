-- 214 — Administration autonome des itinéraires, et permissions déléguées
--
-- Deux besoins exprimés par l'exploitant :
--
-- 1. AUTONOMIE. Le reste de l'administration d'Embarquement (gares, bus,
--    villes, équipe, coordonnées) est déjà embarqué dans l'app mobile, sur le
--    modèle de courrier_mobile. Les itinéraires tarifés faisaient exception :
--    il fallait passer par la billetterie web. embarquement_upsert_trajet
--    comble ce trou SANS créer de second référentiel — il écrit dans les
--    tables Tibus (ProgrammationTrajets + ProgrammationTrajetArrets), donc
--    une seule source de prix, et le trigger de la migration 212 journalise
--    le changement avec son auteur.
--
--    Un trajet créé depuis Embarquement naît avec isSchedulingActive = false :
--    il existe pour l'embarquement et la tarification, il n'est pas mis en
--    vente dans la billetterie sans décision explicite côté Tibus. Écriture
--    réservée au propriétaire (can_admin_embarquement).
--
-- 2. DÉLÉGATION. Le socle des rôles admis reste en dur (owner, gerant_gare,
--    controleur_gare, comptable_gare). embarquement_permissions ouvre le
--    module, en plus, à un autre rôle de gare — un vendeur_gare qui tient
--    aussi le portillon — sans livrer une nouvelle version de l'app.
--
--    Deux garde-fous, et le second est le plus important :
--      * le gérant n'accorde que sur SA gare (embarquement_can_grant) ;
--      * il n'accorde qu'à un rôle de niveau STRICTEMENT INFÉRIEUR au sien.
--    Sans cette seconde règle, un gérant pourrait s'accorder un rôle plus
--    large et sortir de son périmètre — la délégation deviendrait une
--    escalade de privilèges. Le propriétaire est traité comme un niveau
--    au-dessus de tout (1000).
--
--    Seuls les rôles en '%_gare' sont éligibles : la permission est adossée à
--    une gare, l'accorder à un rôle à portée compagnie n'aurait aucun sens et
--    rouvrirait exactement ce que la migration 213 a fermé.
--
-- Appliquée en live sur kqudaqtydimjclwaihqr via Supabase MCP le 2026-09-23
-- (nom côté Supabase : embarquement_admin_trajets_et_permissions_deleguees).

CREATE TABLE IF NOT EXISTS public.embarquement_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public."Companies"(id) ON DELETE CASCADE,
  gare_id uuid NOT NULL REFERENCES public."Gares"(id) ON DELETE CASCADE,
  role_name text NOT NULL,
  granted_by uuid REFERENCES public."Users"(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, gare_id, role_name)
);
CREATE INDEX IF NOT EXISTS embarquement_permissions_company_idx
  ON public.embarquement_permissions(company_id, gare_id);

CREATE OR REPLACE FUNCTION public.can_use_embarquement(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY[
         'owner', 'gerant_gare', 'controleur_gare', 'comptable_gare'
       ])
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      JOIN public."Users" u ON u.id = ur."userId"
      JOIN public.embarquement_permissions ep
        ON ep.company_id = ur."companyId"
       AND ep.gare_id = ur."gareId"
       AND ep.role_name = r.name
      WHERE u."auth_user_id" = auth.uid()
        AND ur."companyId" = p_company_id
        AND ur."gareId" IS NOT NULL
    );
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
    AND (
      r.name IN ('gerant_gare', 'controleur_gare', 'comptable_gare')
      OR EXISTS (
        SELECT 1 FROM public.embarquement_permissions ep
        WHERE ep.company_id = p_company_id
          AND ep.gare_id = ur."gareId"
          AND ep.role_name = r.name
      )
    )
    AND g."isActive"
    AND g.name <> '__CASH_SESSION_HUB__'
    AND g.name NOT LIKE '\_\_%'
  ORDER BY 2;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_can_grant(p_company_id uuid, p_gare_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner'])
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      JOIN public."Users" u ON u.id = ur."userId"
      WHERE u."auth_user_id" = auth.uid()
        AND ur."companyId" = p_company_id
        AND ur."gareId" = p_gare_id
        AND r.name = 'gerant_gare'
    );
$$;

CREATE OR REPLACE FUNCTION public.embarquement_grant_permission(
  p_company_id uuid,
  p_gare_id uuid,
  p_role_name text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := public.current_app_user_id();
  v_my_level integer;
  v_target_level integer;
  v_id uuid;
BEGIN
  IF NOT public.embarquement_can_grant(p_company_id, p_gare_id) THEN
    RAISE EXCEPTION 'Seuls le proprietaire et le gerant de cette gare peuvent accorder cette permission';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public."Gares" g
    WHERE g.id = p_gare_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Gare introuvable pour cette compagnie';
  END IF;

  SELECT r.level INTO v_target_level FROM public."Role" r WHERE r.name = p_role_name;
  IF v_target_level IS NULL THEN
    RAISE EXCEPTION 'Role inconnu';
  END IF;

  IF p_role_name NOT LIKE '%\_gare' THEN
    RAISE EXCEPTION 'Seuls les roles rattaches a une gare peuvent recevoir cette permission';
  END IF;

  IF public.is_super_admin() OR public.has_company_role(p_company_id, ARRAY['owner']) THEN
    v_my_level := 1000;
  ELSE
    SELECT max(r.level) INTO v_my_level
    FROM public."UserRoles" ur
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE ur."userId" = v_user
      AND ur."companyId" = p_company_id
      AND ur."gareId" = p_gare_id;
  END IF;

  IF v_my_level IS NULL OR v_target_level >= v_my_level THEN
    RAISE EXCEPTION 'On ne peut accorder qu a un role de niveau inferieur au sien';
  END IF;

  INSERT INTO public.embarquement_permissions (company_id, gare_id, role_name, granted_by)
  VALUES (p_company_id, p_gare_id, p_role_name, v_user)
  ON CONFLICT (company_id, gare_id, role_name)
  DO UPDATE SET granted_by = EXCLUDED.granted_by, granted_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_revoke_permission(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_company uuid;
  v_gare uuid;
BEGIN
  SELECT ep.company_id, ep.gare_id INTO v_company, v_gare
  FROM public.embarquement_permissions ep WHERE ep.id = p_id;
  IF v_company IS NULL THEN RAISE EXCEPTION 'Permission introuvable'; END IF;
  IF NOT public.embarquement_can_grant(v_company, v_gare) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  DELETE FROM public.embarquement_permissions WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_list_permissions(p_company_id uuid)
RETURNS TABLE(
  id uuid, gare_id uuid, gare_name text, role_name text,
  granted_by_name text, granted_at timestamptz, can_revoke boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.can_use_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  RETURN QUERY
  SELECT ep.id, ep.gare_id, g.name::text, ep.role_name,
         COALESCE(public.embarquement_user_label(ep.granted_by), u.username, u.email, 'Inconnu')::text,
         ep.granted_at,
         public.embarquement_can_grant(p_company_id, ep.gare_id)
  FROM public.embarquement_permissions ep
  JOIN public."Gares" g ON g.id = ep.gare_id
  LEFT JOIN public."Users" u ON u.id = ep.granted_by
  WHERE ep.company_id = p_company_id
  ORDER BY g.name, ep.role_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_grantable_roles()
RETURNS TABLE(name text, level integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT r.name::text, r.level
  FROM public."Role" r
  WHERE r.name LIKE '%\_gare'
    AND r.name NOT IN ('gerant_gare', 'controleur_gare', 'comptable_gare')
  ORDER BY r.level DESC;
$$;

CREATE OR REPLACE FUNCTION public.embarquement_upsert_trajet(
  p_company_id uuid,
  p_from_gare_id uuid,
  p_to_gare_id uuid,
  p_price numeric,
  p_kilometrage integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_trajet_id uuid;
  v_arret_id uuid;
BEGIN
  IF NOT public.can_admin_embarquement(p_company_id) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;
  IF p_from_gare_id = p_to_gare_id THEN
    RAISE EXCEPTION 'Gare de depart et d arrivee identiques';
  END IF;
  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Tarif requis';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public."Gares" g
    WHERE g.id = p_from_gare_id AND g."companyId" = p_company_id
  ) OR NOT EXISTS (
    SELECT 1 FROM public."Gares" g
    WHERE g.id = p_to_gare_id AND g."companyId" = p_company_id
  ) THEN
    RAISE EXCEPTION 'Les deux gares doivent appartenir a la compagnie';
  END IF;

  SELECT t.id INTO v_trajet_id
  FROM public."ProgrammationTrajets" t
  WHERE t.depart = p_from_gare_id AND t."final" = p_to_gare_id
  LIMIT 1;

  IF v_trajet_id IS NULL THEN
    INSERT INTO public."ProgrammationTrajets" (depart, "final", "isSchedulingActive")
    VALUES (p_from_gare_id, p_to_gare_id, false)
    RETURNING id INTO v_trajet_id;
  END IF;

  INSERT INTO public."ProgrammationTrajetArrets"
    ("trajetId", "fromGareId", "toGareId", price, kilometrage)
  VALUES (v_trajet_id, p_from_gare_id, p_to_gare_id, p_price, p_kilometrage)
  ON CONFLICT ("trajetId", "fromGareId", "toGareId")
  DO UPDATE SET price = EXCLUDED.price,
                kilometrage = COALESCE(EXCLUDED.kilometrage, public."ProgrammationTrajetArrets".kilometrage)
  RETURNING id INTO v_arret_id;

  RETURN jsonb_build_object('trajet_id', v_trajet_id, 'arret_id', v_arret_id, 'price', p_price);
END;
$$;

GRANT EXECUTE ON FUNCTION public.embarquement_grant_permission(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_revoke_permission(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_list_permissions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_grantable_roles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_upsert_trajet(uuid, uuid, uuid, numeric, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.embarquement_can_grant(uuid, uuid) TO authenticated;
