-- 062 — Création self-service d'une compagnie par un voyageur ou un propriétaire existant
-- Exécuter après 058_owner_multi_company.sql

CREATE OR REPLACE FUNCTION public.create_owner_company(
  p_name text,
  p_country_id uuid,
  p_manager_name text DEFAULT NULL,
  p_logo text DEFAULT NULL,
  p_voyage_colis_msg text DEFAULT NULL,
  p_arret_reservation boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_owner_role_id uuid;
  v_company_id uuid;
  v_name text := trim(p_name);
BEGIN
  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifie';
  END IF;

  IF char_length(v_name) < 2 THEN
    RAISE EXCEPTION 'Le nom de la compagnie doit contenir au moins 2 caracteres';
  END IF;

  IF p_country_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM "Countries" c WHERE c.id = p_country_id
  ) THEN
    RAISE EXCEPTION 'Pays invalide';
  END IF;

  IF NOT (
    public.has_global_role(ARRAY['traveler'])
    OR EXISTS (
      SELECT 1
      FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      WHERE ur."userId" = v_user_id
        AND r.name = 'owner'
        AND ur."companyId" IS NOT NULL
    )
  ) THEN
    RAISE EXCEPTION 'Vous ne pouvez pas creer de compagnie avec ce compte';
  END IF;

  SELECT id INTO v_owner_role_id
  FROM "Role"
  WHERE name = 'owner';

  IF v_owner_role_id IS NULL THEN
    RAISE EXCEPTION 'Role owner introuvable';
  END IF;

  INSERT INTO "Companies" (
    "name",
    "countryId",
    "isActive",
    "commissionRate",
    "managerName",
    "logo",
    "voyageColisMsg",
    "arretReservation"
  ) VALUES (
    v_name,
    p_country_id,
    true,
    8.5,
    NULLIF(trim(p_manager_name), ''),
    NULLIF(trim(p_logo), ''),
    NULLIF(trim(p_voyage_colis_msg), ''),
    COALESCE(p_arret_reservation, true)
  )
  RETURNING id INTO v_company_id;

  INSERT INTO "UserRoles" ("userId", "roleId", "companyId", "countryId")
  VALUES (v_user_id, v_owner_role_id, v_company_id, NULL);

  UPDATE "Users"
  SET "activeOwnerCompanyId" = v_company_id
  WHERE id = v_user_id;

  RETURN v_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_owner_company(
  text,
  uuid,
  text,
  text,
  text,
  boolean
) TO authenticated;
