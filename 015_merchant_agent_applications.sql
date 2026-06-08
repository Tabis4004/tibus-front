-- Enrolement Agent Marchand.
-- Stocke les demandes et le lien Google Maps pour futur affichage landing/mapping.

CREATE TABLE IF NOT EXISTS "MerchantAgentApplications" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "createdBy" uuid NOT NULL REFERENCES "Users" (id),
  "commercialName" text NOT NULL,
  "fullName" text NOT NULL,
  "phone" text NOT NULL,
  "email" text,
  "countryId" uuid REFERENCES "Countries" (id),
  "countryName" text,
  "cityId" uuid REFERENCES "Cities" (id),
  "city" text NOT NULL,
  "physicalAddress" text NOT NULL,
  "googleMapsUrl" text NOT NULL,
  "status" text NOT NULL DEFAULT 'pending',
  "reviewedBy" uuid REFERENCES "Users" (id),
  "reviewedAt" timestamptz,
  "notes" text
);

ALTER TABLE "MerchantAgentApplications" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "MerchantAgentApplications"
  ADD COLUMN IF NOT EXISTS "cityId" uuid REFERENCES "Cities" (id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'MerchantAgentApplications'
      AND policyname = 'merchant_agent_applications_select'
  ) THEN
    CREATE POLICY "merchant_agent_applications_select"
      ON "MerchantAgentApplications"
      FOR SELECT TO authenticated
      USING (
        "createdBy" = public.current_app_user_id()
        OR public.is_super_admin()
        OR public.has_global_droit('manage_users')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'MerchantAgentApplications'
      AND policyname = 'merchant_agent_applications_insert'
  ) THEN
    CREATE POLICY "merchant_agent_applications_insert"
      ON "MerchantAgentApplications"
      FOR INSERT TO authenticated
      WITH CHECK ("createdBy" = public.current_app_user_id());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'MerchantAgentApplications'
      AND policyname = 'merchant_agent_applications_update_admin'
  ) THEN
    CREATE POLICY "merchant_agent_applications_update_admin"
      ON "MerchantAgentApplications"
      FOR UPDATE TO authenticated
      USING (public.is_super_admin() OR public.has_global_droit('manage_users'))
      WITH CHECK (public.is_super_admin() OR public.has_global_droit('manage_users'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "merchant_agent_applications_created_by_idx"
  ON "MerchantAgentApplications" ("createdBy");

CREATE INDEX IF NOT EXISTS "merchant_agent_applications_status_idx"
  ON "MerchantAgentApplications" ("status");

CREATE INDEX IF NOT EXISTS "merchant_agent_applications_city_id_idx"
  ON "MerchantAgentApplications" ("cityId");

DROP FUNCTION IF EXISTS public.submit_merchant_agent_application(
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  text
);

CREATE OR REPLACE FUNCTION public.submit_merchant_agent_application(
  p_commercial_name text,
  p_full_name text,
  p_phone text,
  p_email text,
  p_country_id uuid,
  p_country_name text,
  p_city_id uuid,
  p_city text,
  p_physical_address text,
  p_google_maps_url text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app_user_id uuid;
  v_role_id uuid;
  v_application_id uuid;
  v_first_name text;
  v_last_name text;
  v_city_name text;
  v_country_name text;
BEGIN
  v_app_user_id := public.current_app_user_id();

  IF v_app_user_id IS NULL THEN
    RAISE EXCEPTION 'Votre profil est en cours de préparation. Réessayez dans un instant.';
  END IF;

  IF p_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays requis.';
  END IF;

  SELECT c.name INTO v_country_name
  FROM "Countries" c
  WHERE c.id = p_country_id;

  IF v_country_name IS NULL THEN
    RAISE EXCEPTION 'Pays introuvable.';
  END IF;

  SELECT c.name INTO v_city_name
  FROM "Cities" c
  WHERE c.id = p_city_id
    AND c."countryId" = p_country_id;

  IF v_city_name IS NULL THEN
    RAISE EXCEPTION 'Ville introuvable pour ce pays.';
  END IF;

  v_first_name := split_part(btrim(p_full_name), ' ', 1);
  v_last_name := NULLIF(btrim(substr(btrim(p_full_name), length(v_first_name) + 1)), '');

  SELECT r.id INTO v_role_id
  FROM "Role" r
  WHERE r.name = 'vendeur_independant'
    AND r.scope = 'platform'
  LIMIT 1;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Rôle vendeur_independant introuvable.';
  END IF;

  INSERT INTO "MerchantAgentApplications" (
    "createdBy",
    "commercialName",
    "fullName",
    "phone",
    "email",
    "countryId",
    "countryName",
    "cityId",
    "city",
    "physicalAddress",
    "googleMapsUrl",
    "status"
  )
  VALUES (
    v_app_user_id,
    btrim(p_commercial_name),
    btrim(p_full_name),
    btrim(p_phone),
    NULLIF(btrim(COALESCE(p_email, '')), ''),
    p_country_id,
    COALESCE(NULLIF(btrim(COALESCE(p_country_name, '')), ''), v_country_name),
    p_city_id,
    v_city_name,
    btrim(p_physical_address),
    btrim(p_google_maps_url),
    'pending'
  )
  RETURNING id INTO v_application_id;

  UPDATE "Users"
  SET
    "firstName" = COALESCE(NULLIF(v_first_name, ''), 'Utilisateur'),
    "lastName" = COALESCE(v_last_name, 'Tibus'),
    "phone" = btrim(p_phone),
    "email" = COALESCE(NULLIF(btrim(COALESCE(p_email, '')), ''), "email"),
    "countryId" = p_country_id,
    "profileCompleted" = true,
    "onboardingCompleted" = false
  WHERE id = v_app_user_id;

  INSERT INTO "UserRoles" (
    "roleId",
    "userId",
    "companyId",
    "countryId",
    "assignedBy"
  )
  VALUES (
    v_role_id,
    v_app_user_id,
    NULL,
    NULL,
    v_app_user_id
  )
  ON CONFLICT DO NOTHING;

  RETURN v_application_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_merchant_agent_application(
  text,
  text,
  text,
  text,
  uuid,
  text,
  uuid,
  text,
  text,
  text
) TO authenticated;

-- Backfill: les demandes Agent Marchand créées avant l'attribution automatique
-- reçoivent le rôle vendeur_independant sans doublon.
INSERT INTO "UserRoles" ("roleId", "userId", "companyId", "countryId")
SELECT r.id, maa."createdBy", NULL, NULL
FROM "MerchantAgentApplications" maa
JOIN "Role" r ON r.name = 'vendeur_independant'
WHERE NOT EXISTS (
  SELECT 1
  FROM "UserRoles" ur
  WHERE ur."userId" = maa."createdBy"
    AND ur."roleId" = r.id
    AND ur."companyId" IS NULL
    AND ur."countryId" IS NULL
);
