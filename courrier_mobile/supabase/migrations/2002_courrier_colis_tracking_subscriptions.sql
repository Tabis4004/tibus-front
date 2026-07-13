-- =============================================================================
-- Courrier — migration additive.
-- Objectif : savoir QUELS utilisateurs (comptes) suivent QUEL colis, pour
-- que l'edge function send-colis-push sache à qui envoyer une notification
-- FCM lors d'un changement de statut. N'ALTERE ni ne SUPPRIME aucune table
-- existante de Tibus.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "ColisTrackingSubscriptions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "userId" uuid NOT NULL REFERENCES "Users" ("id") ON DELETE CASCADE,
  "colisId" uuid NOT NULL REFERENCES colis_autonomes ("id") ON DELETE CASCADE,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("userId", "colisId")
);

CREATE INDEX IF NOT EXISTS "ColisTrackingSubscriptions_colisId_idx"
  ON "ColisTrackingSubscriptions" ("colisId");

ALTER TABLE "ColisTrackingSubscriptions" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ColisTrackingSubscriptions_select_own" ON "ColisTrackingSubscriptions"
  FOR SELECT USING (
    "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid())
  );

CREATE POLICY "ColisTrackingSubscriptions_insert_own" ON "ColisTrackingSubscriptions"
  FOR INSERT WITH CHECK (
    "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid())
  );

CREATE POLICY "ColisTrackingSubscriptions_delete_own" ON "ColisTrackingSubscriptions"
  FOR DELETE USING (
    "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid())
  );

CREATE OR REPLACE FUNCTION public.subscribe_to_colis_tracking(p_colis_id uuid)
RETURNS void
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

  INSERT INTO "ColisTrackingSubscriptions" ("userId", "colisId")
  VALUES (v_user_id, p_colis_id)
  ON CONFLICT ("userId", "colisId") DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unsubscribe_from_colis_tracking(p_colis_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM "ColisTrackingSubscriptions" WHERE "colisId" = p_colis_id
    AND "userId" IN (SELECT "id" FROM "Users" WHERE "auth_user_id" = auth.uid());
END;
$$;
