-- Lot 39: Formulaire contact + WhatsApp (migration Convex contactSettings / contactInquiries).

CREATE TABLE IF NOT EXISTS "ContactSettings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "scope" text NOT NULL,
  "whatsappNumber" text NOT NULL,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid REFERENCES "Users" ("id") ON DELETE SET NULL,
  CONSTRAINT "ContactSettings_scope_check" CHECK (char_length(trim("scope")) > 0),
  CONSTRAINT "ContactSettings_whatsapp_check" CHECK (char_length(trim("whatsappNumber")) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS "ContactSettings_scope_key"
  ON "ContactSettings" ("scope");

CREATE TABLE IF NOT EXISTS "ContactInquiries" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "name" text NOT NULL,
  "email" text NOT NULL,
  "phone" text,
  "inquiryTo" text NOT NULL,
  "message" text NOT NULL,
  "status" text NOT NULL DEFAULT 'new',
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "ContactInquiries_status_check"
    CHECK ("status" IN ('new', 'read', 'resolved'))
);

CREATE INDEX IF NOT EXISTS "ContactInquiries_inquiry_to_idx"
  ON "ContactInquiries" ("inquiryTo", "createdAt" DESC);

CREATE INDEX IF NOT EXISTS "ContactInquiries_status_idx"
  ON "ContactInquiries" ("status", "createdAt" DESC);

ALTER TABLE "ContactSettings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ContactInquiries" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "contact_settings_select" ON "ContactSettings";
CREATE POLICY "contact_settings_select" ON "ContactSettings"
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "contact_inquiries_insert" ON "ContactInquiries";
CREATE POLICY "contact_inquiries_insert" ON "ContactInquiries"
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "contact_inquiries_select" ON "ContactInquiries";
CREATE POLICY "contact_inquiries_select" ON "ContactInquiries"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR (
      "inquiryTo" <> 'platform'
      AND public.has_company_role("inquiryTo"::uuid, ARRAY['owner'])
    )
  );

DROP POLICY IF EXISTS "contact_inquiries_update" ON "ContactInquiries";
CREATE POLICY "contact_inquiries_update" ON "ContactInquiries"
  FOR UPDATE TO authenticated
  USING (
    public.is_super_admin()
    OR (
      "inquiryTo" <> 'platform'
      AND public.has_company_role("inquiryTo"::uuid, ARRAY['owner'])
    )
  )
  WITH CHECK (
    public.is_super_admin()
    OR (
      "inquiryTo" <> 'platform'
      AND public.has_company_role("inquiryTo"::uuid, ARRAY['owner'])
    )
  );

CREATE OR REPLACE FUNCTION public.get_contact_options()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_platform text;
  v_companies jsonb;
BEGIN
  SELECT cs."whatsappNumber"
  INTO v_platform
  FROM "ContactSettings" cs
  WHERE cs."scope" = 'platform'
  LIMIT 1;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'companyId', cs."scope",
        'companyName', COALESCE(c.name, 'Compagnie'),
        'whatsappNumber', cs."whatsappNumber"
      )
      ORDER BY c.name
    ),
    '[]'::jsonb
  )
  INTO v_companies
  FROM "ContactSettings" cs
  LEFT JOIN "Companies" c ON c.id::text = cs."scope"
  WHERE cs."scope" <> 'platform';

  RETURN jsonb_build_object(
    'platformWhatsapp', v_platform,
    'companies', v_companies
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_contact_inquiry(
  p_name text,
  p_email text,
  p_phone text DEFAULT NULL,
  p_inquiry_to text DEFAULT 'platform',
  p_message text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_inquiry_to text := trim(COALESCE(p_inquiry_to, 'platform'));
BEGIN
  IF trim(COALESCE(p_name, '')) = ''
    OR trim(COALESCE(p_email, '')) = ''
    OR trim(COALESCE(p_message, '')) = '' THEN
    RAISE EXCEPTION 'Champs requis manquants';
  END IF;

  IF v_inquiry_to <> 'platform' THEN
    IF NOT EXISTS (
      SELECT 1 FROM "Companies" c
      WHERE c.id::text = v_inquiry_to AND c."isActive" = true
    ) THEN
      RAISE EXCEPTION 'Compagnie destinataire invalide';
    END IF;
  END IF;

  INSERT INTO "ContactInquiries" ("name", "email", "phone", "inquiryTo", "message", "status")
  VALUES (
    trim(p_name),
    trim(p_email),
    NULLIF(trim(COALESCE(p_phone, '')), ''),
    v_inquiry_to,
    trim(p_message),
    'new'
  )
  RETURNING "id" INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_contact_whatsapp(
  p_scope text,
  p_whatsapp_number text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope text := trim(COALESCE(p_scope, ''));
  v_number text := trim(COALESCE(p_whatsapp_number, ''));
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Connexion requise';
  END IF;

  IF v_scope = '' OR v_number = '' THEN
    RAISE EXCEPTION 'Scope et numéro WhatsApp requis';
  END IF;

  IF v_scope = 'platform' THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'Seul le super admin peut modifier le WhatsApp plateforme';
    END IF;
  ELSIF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_scope::uuid, ARRAY['owner']) THEN
    RAISE EXCEPTION 'Droits insuffisants pour cette compagnie';
  END IF;

  INSERT INTO "ContactSettings" ("scope", "whatsappNumber", "updatedBy", "updatedAt")
  VALUES (v_scope, v_number, v_user_id, now())
  ON CONFLICT ("scope") DO UPDATE
  SET
    "whatsappNumber" = EXCLUDED."whatsappNumber",
    "updatedBy" = v_user_id,
    "updatedAt" = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.list_contact_inquiries()
RETURNS SETOF "ContactInquiries"
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ci.*
  FROM "ContactInquiries" ci
  WHERE public.is_super_admin()
     OR (
       ci."inquiryTo" <> 'platform'
       AND public.has_company_role(ci."inquiryTo"::uuid, ARRAY['owner'])
     )
  ORDER BY ci."createdAt" DESC;
$$;

CREATE OR REPLACE FUNCTION public.update_contact_inquiry_status(
  p_inquiry_id uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inquiry "ContactInquiries"%ROWTYPE;
BEGIN
  IF p_status NOT IN ('new', 'read', 'resolved') THEN
    RAISE EXCEPTION 'Statut invalide';
  END IF;

  SELECT * INTO v_inquiry
  FROM "ContactInquiries"
  WHERE "id" = p_inquiry_id;

  IF v_inquiry."id" IS NULL THEN
    RAISE EXCEPTION 'Demande introuvable';
  END IF;

  IF NOT public.is_super_admin()
    AND (
      v_inquiry."inquiryTo" = 'platform'
      OR NOT public.has_company_role(v_inquiry."inquiryTo"::uuid, ARRAY['owner'])
    ) THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  UPDATE "ContactInquiries"
  SET "status" = p_status
  WHERE "id" = p_inquiry_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_contact_options() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_contact_inquiry(text, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_contact_whatsapp(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_contact_inquiries() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_contact_inquiry_status(uuid, text) TO authenticated;
