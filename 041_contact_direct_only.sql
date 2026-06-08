-- Lot 41: Contact direct — pas de stockage de messages ni d'e-mail automatique.
-- Conserver uniquement ContactSettings (WhatsApp + e-mail affiché).

DROP FUNCTION IF EXISTS public.get_contact_inquiry_notify_target(uuid);
DROP FUNCTION IF EXISTS public.submit_contact_inquiry(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.list_contact_inquiries();
DROP FUNCTION IF EXISTS public.update_contact_inquiry_status(uuid, text);

DROP POLICY IF EXISTS "contact_inquiries_insert" ON "ContactInquiries";
DROP POLICY IF EXISTS "contact_inquiries_select" ON "ContactInquiries";
DROP POLICY IF EXISTS "contact_inquiries_update" ON "ContactInquiries";

DROP TABLE IF EXISTS "ContactInquiries";

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
    AND (
      NULLIF(BTRIM(cs."whatsappNumber"), '') IS NOT NULL
      OR NULLIF(BTRIM(cs."notificationEmail"), '') IS NOT NULL
    );

  RETURN jsonb_build_object(
    'platformWhatsapp', v_platform,
    'platformNotificationEmail', v_platform_email,
    'companies', v_companies
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_contact_options() TO anon, authenticated;
