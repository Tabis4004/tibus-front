-- 067 — Ligne d'information éditable (super admin) pour l'attribution stakeholders
-- Exécuter après 066_stakeholder_commission_platform_pool.sql

CREATE TABLE IF NOT EXISTS "StakeholderCommissionInfo" (
  "id" uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000002'::uuid,
  "infoLine" text NOT NULL,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedBy" uuid,
  CONSTRAINT "StakeholderCommissionInfo_singleton_check"
    CHECK ("id" = '00000000-0000-0000-0000-000000000002'::uuid)
);

ALTER TABLE "StakeholderCommissionInfo"
  DROP CONSTRAINT IF EXISTS "StakeholderCommissionInfo_updatedBy_fkey";
ALTER TABLE "StakeholderCommissionInfo"
  ADD CONSTRAINT "StakeholderCommissionInfo_updatedBy_fkey"
  FOREIGN KEY ("updatedBy") REFERENCES "Users" ("id")
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "StakeholderCommissionInfo" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stakeholder_commission_info_select" ON "StakeholderCommissionInfo";
CREATE POLICY "stakeholder_commission_info_select" ON "StakeholderCommissionInfo"
  FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1
      FROM "UserRoles" ur
      JOIN "Role" ro ON ro.id = ur."roleId"
      WHERE ur."userId" = public.current_app_user_id()
        AND ro.name = 'admin_pays'
    )
  );

DROP POLICY IF EXISTS "stakeholder_commission_info_write" ON "StakeholderCommissionInfo";
CREATE POLICY "stakeholder_commission_info_write" ON "StakeholderCommissionInfo"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

INSERT INTO "StakeholderCommissionInfo" ("id", "infoLine")
VALUES (
  '00000000-0000-0000-0000-000000000002',
  'La répartition s''effectue sur la commission plateforme (M×X%) de chaque ligne ReservationBus, selon CommissionSettings pays/compagnie. La compagnie (owner) et tout utilisateur lié à une compagnie sont exclus.'
)
ON CONFLICT ("id") DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_stakeholder_commission_info()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'infoLine', i."infoLine",
    'updatedAt', i."updatedAt",
    'updatedByName', NULLIF(
      TRIM(COALESCE(u."firstName", '') || ' ' || COALESCE(u."lastName", '')),
      ''
    )
  )
  FROM "StakeholderCommissionInfo" i
  LEFT JOIN "Users" u ON u.id = i."updatedBy"
  WHERE i.id = '00000000-0000-0000-0000-000000000002'::uuid;
$$;

CREATE OR REPLACE FUNCTION public.upsert_stakeholder_commission_info(p_info_line text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Acces refuse';
  END IF;

  v_user_id := public.current_app_user_id();

  IF p_info_line IS NULL OR trim(p_info_line) = '' THEN
    RAISE EXCEPTION 'Ligne d''information requise';
  END IF;

  INSERT INTO "StakeholderCommissionInfo" ("id", "infoLine", "updatedBy")
  VALUES (
    '00000000-0000-0000-0000-000000000002',
    trim(p_info_line),
    v_user_id
  )
  ON CONFLICT ("id") DO UPDATE SET
    "infoLine" = EXCLUDED."infoLine",
    "updatedBy" = EXCLUDED."updatedBy",
    "updatedAt" = now();

  RETURN public.get_stakeholder_commission_info();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_stakeholder_commission_info() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_stakeholder_commission_info(text) TO authenticated;
