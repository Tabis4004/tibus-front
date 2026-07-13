-- =============================================================================
-- Courrier — migration additive PROPOSEE, NON APPLIQUEE.
-- Objectif : permettre les notifications push natives (FCM) pour le suivi
-- client de colis, en plus du SMS existant.
-- N'ALTERE ni ne SUPPRIME aucune table/colonne existante de Tibus.
-- A appliquer sur le projet Supabase existant (adaptation, pas de nouvelle
-- base) uniquement après validation.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "DeviceTokens" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "userId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "fcmToken" varchar UNIQUE NOT NULL,
  "platform" varchar NOT NULL CHECK ("platform" IN ('android', 'ios')),
  "appVersion" varchar,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "lastSeenAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "DeviceTokens_userId_idx" ON "DeviceTokens" ("userId");

ALTER TABLE "DeviceTokens" ENABLE ROW LEVEL SECURITY;

-- Un utilisateur ne gère que ses propres tokens.
CREATE POLICY "DeviceTokens_select_own" ON "DeviceTokens"
  FOR SELECT USING (
    "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid())
  );

CREATE POLICY "DeviceTokens_upsert_own" ON "DeviceTokens"
  FOR INSERT WITH CHECK (
    "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid())
  );

CREATE POLICY "DeviceTokens_delete_own" ON "DeviceTokens"
  FOR DELETE USING (
    "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid())
  );

-- Fonctions RPC miroir de register_push_subscription / unregister_push_subscription
-- (déjà utilisées côté web pour le Web Push) mais pour un token FCM natif.
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_fcm_token varchar,
  p_platform varchar,
  p_app_version varchar DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT "id" INTO v_user_id FROM "Users" WHERE "auth_user_id" = auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  INSERT INTO "DeviceTokens" ("userId", "fcmToken", "platform", "appVersion", "lastSeenAt")
  VALUES (v_user_id, p_fcm_token, p_platform, p_app_version, now())
  ON CONFLICT ("fcmToken") DO UPDATE SET
    "userId" = EXCLUDED."userId",
    "lastSeenAt" = now(),
    "appVersion" = EXCLUDED."appVersion";
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_device_token(p_fcm_token varchar)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM "DeviceTokens" WHERE "fcmToken" = p_fcm_token
    AND "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid());
END;
$$;

-- NOTE : l'envoi effectif (edge function `send-colis-push`, appel à
-- l'API FCM HTTP v1) reste à écrire une fois le projet Firebase créé —
-- hors périmètre de cette migration, qui ne pose que la fondation base
-- de données.
