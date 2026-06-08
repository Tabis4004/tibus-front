-- Tibus — Journal d'audit plateforme (HUB admin)

CREATE TABLE IF NOT EXISTS "PlatformAuditLogs" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "moduleKey" varchar NOT NULL,
  "action" varchar NOT NULL,
  "summary" text NOT NULL,
  "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "actorUserId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "companyId" uuid REFERENCES "Companies" ("id") ON DELETE SET NULL,
  "countryId" uuid REFERENCES "Countries" ("id") ON DELETE SET NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "PlatformAuditLogs_module_created_idx"
  ON "PlatformAuditLogs" ("moduleKey", "createdAt" DESC);

ALTER TABLE "PlatformAuditLogs" ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_platform_scope()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_super_admin()
    OR public.has_global_role(ARRAY[
      'admin_pays',
      'master',
      'master_independant',
      'vendeur_master',
      'vendeur_independant'
    ]);
$$;

DROP POLICY IF EXISTS "PlatformAuditLogs_select_platform" ON "PlatformAuditLogs";
CREATE POLICY "PlatformAuditLogs_select_platform"
  ON "PlatformAuditLogs"
  FOR SELECT
  TO authenticated
  USING (public.has_platform_scope());

CREATE OR REPLACE FUNCTION public.log_platform_audit(
  p_module_key text,
  p_action text,
  p_summary text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_id uuid;
  v_log_id uuid;
BEGIN
  IF NOT public.has_platform_scope() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  v_actor_id := public.current_app_user_id();
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  INSERT INTO "PlatformAuditLogs" ("moduleKey", "action", "summary", "metadata", "actorUserId")
  VALUES (
    trim(p_module_key),
    trim(p_action),
    trim(p_summary),
    COALESCE(p_metadata, '{}'::jsonb),
    v_actor_id
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_platform_audit_logs(
  p_module_key text,
  p_limit integer DEFAULT 15
)
RETURNS TABLE (
  id uuid,
  "moduleKey" varchar,
  action varchar,
  summary text,
  metadata jsonb,
  "actorName" text,
  "actorEmail" text,
  "createdAt" timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_platform_scope() THEN
    RAISE EXCEPTION 'Droits insuffisants';
  END IF;

  RETURN QUERY
  SELECT
    l.id,
    l."moduleKey",
    l.action,
    l.summary,
    l.metadata,
    trim(concat(u."firstName", ' ', u."lastName")) AS "actorName",
    u.email::text AS "actorEmail",
    l."createdAt"
  FROM "PlatformAuditLogs" l
  JOIN "Users" u ON u.id = l."actorUserId"
  WHERE l."moduleKey" = trim(p_module_key)
  ORDER BY l."createdAt" DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 15), 50));
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_platform_audit(text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_platform_audit_logs(text, integer) TO authenticated;
