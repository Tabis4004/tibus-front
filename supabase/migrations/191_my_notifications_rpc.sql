-- RPC d'inbox pour l'utilisateur courant, sur la table "Notifications"
-- existante (déjà utilisée pour les réservations) — alimentée pour les
-- ventes/statuts colis par la migration 190. Même style que
-- list_superadmin_notifications / count_unread_superadmin_notifications.

CREATE OR REPLACE FUNCTION public.list_my_notifications(p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(row_data ORDER BY created_at DESC), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'id', n.id,
      'type', n.type,
      'title', n.title,
      'message', n.message,
      'isRead', n."isRead",
      'metadata', n.metadata,
      'createdAt', n."createdAt"
    ) AS row_data,
    n."createdAt" AS created_at
    FROM "Notifications" n
    WHERE n."userId" = public.current_app_user_id()
    ORDER BY n."createdAt" DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
  ) t;
$$;

CREATE OR REPLACE FUNCTION public.count_unread_my_notifications()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COUNT(*)::integer FROM "Notifications"
  WHERE "userId" = public.current_app_user_id() AND "isRead" = false;
$$;

CREATE OR REPLACE FUNCTION public.mark_my_notification_read(p_notification_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE "Notifications" SET "isRead" = true
  WHERE id = p_notification_id AND "userId" = public.current_app_user_id();
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_my_notifications_read()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE "Notifications" SET "isRead" = true
  WHERE "userId" = public.current_app_user_id() AND "isRead" = false;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_my_notifications(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.count_unread_my_notifications() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_my_notification_read(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_all_my_notifications_read() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_notifications(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_unread_my_notifications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_my_notification_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_my_notifications_read() TO authenticated;
