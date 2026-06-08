-- Lot 40: Contact owner — WhatsApp + e-mail de notification.

ALTER TABLE "ContactSettings"
  ADD COLUMN IF NOT EXISTS "notificationEmail" text;

ALTER TABLE "ContactSettings"
  ALTER COLUMN "whatsappNumber" DROP NOT NULL;

ALTER TABLE "ContactSettings"
  DROP CONSTRAINT IF EXISTS "ContactSettings_whatsapp_check";

ALTER TABLE "ContactSettings"
  ADD CONSTRAINT "ContactSettings_channel_check"
  CHECK (
    (NULLIF(BTRIM(COALESCE("whatsappNumber", '')), '') IS NOT NULL)
    OR (NULLIF(BTRIM(COALESCE("notificationEmail", '')), '') IS NOT NULL)
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
  v_platform_email text;
  v_companies jsonb;
BEGIN
  SELECT
    NULLIF(BTRIM(cs."whatsappNumber"), ''),
    NULLIF(BTRIM(cs."notificationEmail"), '')
  INTO v_platform, v_platform_email
  FROM "ContactSettings" cs
  WHERE cs."scope" = 'platform'
  LIMIT 1;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'companyId', cs."scope",
        'companyName', COALESCE(c.name, 'Compagnie'),
        'whatsappNumber', NULLIF(BTRIM(cs."whatsappNumber"), ''),
        'notificationEmail', NULLIF(BTRIM(cs."notificationEmail"), '')
      )
      ORDER BY c.name
    ),
    '[]'::jsonb
  )
  INTO v_companies
  FROM "ContactSettings" cs
  LEFT JOIN "Companies" c ON c.id::text = cs."scope"
  WHERE cs."scope" <> 'platform'
    AND NULLIF(BTRIM(cs."whatsappNumber"), '') IS NOT NULL;

  RETURN jsonb_build_object(
    'platformWhatsapp', v_platform,
    'platformNotificationEmail', v_platform_email,
    'companies', v_companies
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_owner_contact_settings()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_row "ContactSettings"%ROWTYPE;
BEGIN
  SELECT ur."companyId"
  INTO v_company_id
  FROM "UserRoles" ur
  JOIN "Role" r ON r.id = ur."roleId"
  WHERE ur."userId" = public.current_app_user_id()
    AND r.name = 'owner'
    AND ur."companyId" IS NOT NULL
  LIMIT 1;

  IF v_company_id IS NULL AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Aucune compagnie propriétaire trouvée';
  END IF;

  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object(
      'scope', null,
      'whatsappNumber', null,
      'notificationEmail', null
    );
  END IF;

  SELECT * INTO v_row
  FROM "ContactSettings"
  WHERE "scope" = v_company_id::text;

  RETURN jsonb_build_object(
    'scope', v_company_id::text,
    'whatsappNumber', NULLIF(BTRIM(v_row."whatsappNumber"), ''),
    'notificationEmail', NULLIF(BTRIM(v_row."notificationEmail"), ''),
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_contact_settings(
  p_scope text,
  p_whatsapp_number text DEFAULT NULL,
  p_notification_email text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope text := trim(COALESCE(p_scope, ''));
  v_whatsapp text := NULLIF(trim(COALESCE(p_whatsapp_number, '')), '');
  v_email text := NULLIF(lower(trim(COALESCE(p_notification_email, ''))), '');
  v_user_id uuid := public.current_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Connexion requise';
  END IF;

  IF v_scope = '' THEN
    RAISE EXCEPTION 'Scope requis';
  END IF;

  IF v_whatsapp IS NULL AND v_email IS NULL THEN
    RAISE EXCEPTION 'WhatsApp ou e-mail requis';
  END IF;

  IF v_email IS NOT NULL AND v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Adresse e-mail invalide';
  END IF;

  IF v_scope = 'platform' THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'Seul le super admin peut modifier les contacts plateforme';
    END IF;
  ELSIF NOT public.is_super_admin()
    AND NOT public.has_company_role(v_scope::uuid, ARRAY['owner']) THEN
    RAISE EXCEPTION 'Droits insuffisants pour cette compagnie';
  END IF;

  INSERT INTO "ContactSettings" ("scope", "whatsappNumber", "notificationEmail", "updatedBy", "updatedAt")
  VALUES (v_scope, v_whatsapp, v_email, v_user_id, now())
  ON CONFLICT ("scope") DO UPDATE
  SET
    "whatsappNumber" = EXCLUDED."whatsappNumber",
    "notificationEmail" = EXCLUDED."notificationEmail",
    "updatedBy" = v_user_id,
    "updatedAt" = now();
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
  v_email text;
BEGIN
  SELECT NULLIF(BTRIM("notificationEmail"), '')
  INTO v_email
  FROM "ContactSettings"
  WHERE "scope" = trim(p_scope);

  PERFORM public.set_contact_settings(p_scope, p_whatsapp_number, v_email);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_contact_inquiry_notify_target(p_inquiry_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inquiry "ContactInquiries"%ROWTYPE;
  v_email text;
  v_company_name text;
BEGIN
  SELECT * INTO v_inquiry FROM "ContactInquiries" WHERE "id" = p_inquiry_id;
  IF v_inquiry."id" IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  IF v_inquiry."inquiryTo" = 'platform' THEN
    SELECT NULLIF(BTRIM("notificationEmail"), '')
    INTO v_email
    FROM "ContactSettings"
    WHERE "scope" = 'platform';
  ELSE
    SELECT NULLIF(BTRIM(cs."notificationEmail"), ''), c.name
    INTO v_email, v_company_name
    FROM "ContactSettings" cs
    LEFT JOIN "Companies" c ON c.id::text = cs."scope"
    WHERE cs."scope" = v_inquiry."inquiryTo";
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'notificationEmail', v_email,
    'companyName', COALESCE(v_company_name, 'Tibus'),
    'inquiry', jsonb_build_object(
      'id', v_inquiry."id",
      'name', v_inquiry."name",
      'email', v_inquiry."email",
      'phone', v_inquiry."phone",
      'message', v_inquiry."message",
      'inquiryTo', v_inquiry."inquiryTo"
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_owner_contact_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_contact_settings(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_contact_inquiry_notify_target(uuid) TO service_role;
