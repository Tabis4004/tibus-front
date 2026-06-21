-- =============================================================================
-- Tibus 146 — Gérant de gare (assignation obligatoire), résolution gareId, reversements
-- =============================================================================

-- Résout la gare rattachée à l'utilisateur (tous rôles gare-scoped).
CREATE OR REPLACE FUNCTION public.resolve_user_gare_id(p_user_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := COALESCE(p_user_id, public.current_app_user_id());
  v_gare uuid;
BEGIN
  IF v_user IS NULL THEN RETURN NULL; END IF;

  SELECT ur."gareId" INTO v_gare
  FROM public."UserRoles" ur
  JOIN public."Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = v_user
    AND ur."gareId" IS NOT NULL
    AND r.name IN (
      'gerant_gare', 'gestionnaire_gare', 'comptable_gare',
      'controleur_gare', 'vendeur_gare'
    )
  ORDER BY
    CASE r.name
      WHEN 'gerant_gare' THEN 1
      WHEN 'gestionnaire_gare' THEN 2
      WHEN 'comptable_gare' THEN 3
      ELSE 9
    END,
    ur.id
  LIMIT 1;

  IF v_gare IS NOT NULL THEN RETURN v_gare; END IF;

  SELECT g.id INTO v_gare FROM public."Gares" g
  WHERE g."gestionnaireUserId" = v_user
  LIMIT 1;

  RETURN v_gare;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_user_gare_id(uuid) TO authenticated;

-- Owner désigne le gérant d'une gare (UserRoles.gareId + legacy gestionnaireUserId).
CREATE OR REPLACE FUNCTION public.assign_gare_gerant(
  p_gare_id uuid,
  p_user_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_gerant_role uuid;
  v_assigner uuid;
BEGIN
  SELECT g."companyId" INTO v_company FROM public."Gares" g WHERE g.id = p_gare_id;
  IF v_company IS NULL THEN RAISE EXCEPTION 'Gare introuvable'; END IF;

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company, ARRAY['owner'])
  ) THEN
    RAISE EXCEPTION 'Seul le propriétaire peut désigner un gérant de gare';
  END IF;

  SELECT r.id INTO v_gerant_role
  FROM public."Role" r
  WHERE r.name = 'gerant_gare' AND r.scope = 'company';
  IF v_gerant_role IS NULL THEN RAISE EXCEPTION 'Rôle gerant_gare introuvable'; END IF;

  v_assigner := public.current_app_user_id();

  DELETE FROM public."UserRoles" ur
  USING public."Role" r
  WHERE ur."roleId" = r.id
    AND ur."gareId" = p_gare_id
    AND r.name IN ('gerant_gare', 'gestionnaire_gare');

  UPDATE public."Gares" SET "gestionnaireUserId" = NULL WHERE id = p_gare_id;

  IF p_user_id IS NOT NULL THEN
    DELETE FROM public."UserRoles" ur
    USING public."Role" r
    WHERE ur."roleId" = r.id
      AND ur."userId" = p_user_id
      AND ur."gareId" IS NOT NULL
      AND r.name IN ('gerant_gare', 'gestionnaire_gare');

    IF NOT EXISTS (
      SELECT 1 FROM public."UserRoles" ur
      WHERE ur."userId" = p_user_id
        AND ur."roleId" = v_gerant_role
        AND ur."gareId" = p_gare_id
    ) THEN
      INSERT INTO public."UserRoles" ("roleId", "userId", "companyId", "gareId", "countryId", "assignedBy")
      VALUES (v_gerant_role, p_user_id, v_company, p_gare_id, NULL, v_assigner);
    END IF;

    UPDATE public."Gares" SET "gestionnaireUserId" = p_user_id WHERE id = p_gare_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_gare_gerant(uuid, uuid) TO authenticated;

-- Droits validation reversement : owner, comptable compagnie, comptable/gérant de gare.
CREATE OR REPLACE FUNCTION public.can_validate_station_reversal(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR EXISTS (
      SELECT 1
      FROM public."UserRoles" ur
      JOIN public."Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = public.current_app_user_id()
        AND ur."companyId" = p_company_id
        AND ur."gareId" IS NOT NULL
        AND r.name IN ('comptable_gare', 'gerant_gare', 'gestionnaire_gare')
    );
$$;

-- Liste reversements : expose gare_id ; filtre gare pour comptable/gérant de gare.
CREATE OR REPLACE FUNCTION public.list_company_station_cash_reversals(
  p_company_id uuid,
  p_status text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  created_at timestamptz,
  validated_at timestamptz,
  montant_reverse integer,
  statut_validation text,
  caisse_id uuid,
  gare_id uuid,
  gare_name text,
  gestionnaire_name text,
  solde_caisse integer,
  soumis_par_name text,
  comptable_name text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_gare uuid := public.resolve_user_gare_id();
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.can_validate_station_reversal(p_company_id)
    OR public.has_company_role(p_company_id, ARRAY['controleur'])
  ) THEN
    RAISE EXCEPTION 'Acces reversements refuse';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.created_at,
    r.validated_at,
    r.montant_reverse,
    r.statut_validation,
    r.caisse_id,
    c.gare_id,
    g.name::text,
    NULLIF(TRIM(gest."firstName" || ' ' || gest."lastName"), ''),
    c.solde_especes_actuel,
    NULLIF(TRIM(sub."firstName" || ' ' || sub."lastName"), ''),
    NULLIF(TRIM(comp."firstName" || ' ' || comp."lastName"), '')
  FROM public.reversements_comptables r
  JOIN public.caisses_gares c ON c.id = r.caisse_id
  JOIN public."Gares" g ON g.id = c.gare_id
  JOIN public."Users" gest ON gest.id = c.gestionnaire_id
  JOIN public."Users" sub ON sub.id = r.soumis_par
  LEFT JOIN public."Users" comp ON comp.id = r.comptable_id
  WHERE g."companyId" = p_company_id
    AND (
      p_status IS NULL
      OR NULLIF(trim(p_status), '') IS NULL
      OR r.statut_validation = p_status
    )
    AND (
      public.is_super_admin()
      OR public.has_company_role(p_company_id, ARRAY['owner', 'comptable_compagnie', 'controleur'])
      OR v_user_gare IS NULL
      OR c.gare_id = v_user_gare
    )
  ORDER BY r.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_station_cash_reversals(uuid, text) TO authenticated;

-- Validation reversement : comptable/gérant limités à leur gare ; conserve le mouvement caisse.
CREATE OR REPLACE FUNCTION public.validate_station_cash_reversal(p_reversement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid;
  v_rev record;
  v_caisse record;
  v_company_id uuid;
  v_movement_id uuid;
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  SELECT * INTO v_rev
  FROM public.reversements_comptables
  WHERE id = p_reversement_id
  FOR UPDATE;

  IF v_rev.id IS NULL THEN RAISE EXCEPTION 'Reversement introuvable'; END IF;
  IF v_rev.statut_validation <> 'en_attente' THEN RAISE EXCEPTION 'Reversement deja traite'; END IF;

  SELECT * INTO v_caisse
  FROM public.caisses_gares
  WHERE id = v_rev.caisse_id
  FOR UPDATE;

  IF v_caisse.id IS NULL THEN RAISE EXCEPTION 'Caisse introuvable'; END IF;

  v_company_id := public.station_cash_gare_company_id(v_caisse.gare_id);

  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(v_company_id, ARRAY['owner', 'comptable_compagnie'])
    OR public.has_gare_role(
      v_caisse.gare_id,
      ARRAY['comptable_gare', 'gerant_gare', 'gestionnaire_gare']
    )
  ) THEN
    RAISE EXCEPTION 'Validation reservee au comptable ou owner';
  END IF;

  v_movement_id := public.record_station_cash_movement(
    v_caisse.id,
    'reversement_comptable',
    v_rev.montant_reverse,
    NULL,
    NULL,
    v_user_id,
    v_rev.id,
    'Reversement valide par comptable',
    'out'
  );

  UPDATE public.reversements_comptables
  SET
    statut_validation = 'approuve_recu',
    comptable_id = v_user_id,
    validated_at = now()
  WHERE id = p_reversement_id;

  UPDATE public.caisses_gares
  SET statut = 'cloturee', closed_at = now()
  WHERE id = v_caisse.id;

  RETURN jsonb_build_object(
    'id', p_reversement_id,
    'status', 'approuve_recu',
    'movementId', v_movement_id,
    'balanceAfter', (SELECT solde_especes_actuel FROM public.caisses_gares WHERE id = v_caisse.id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_station_cash_reversal(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
