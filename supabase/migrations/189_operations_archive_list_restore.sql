-- RPC super_admin pour consulter et restaurer les enregistrements archivés
-- par wipe_company_operations / cancel_colis_autonome (voir migration 188).

CREATE OR REPLACE FUNCTION public.list_archived_operations(
  p_company_id uuid DEFAULT NULL::uuid,
  p_table_name text DEFAULT NULL::text,
  p_limit integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants — réservé au super administrateur';
  END IF;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY deleted_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'id', a.id,
      'tableName', a.table_name,
      'recordId', a.record_id,
      'companyId', a.company_id,
      'companyName', c.name,
      'payload', a.payload,
      'deletedVia', a.deleted_via,
      'deletedAt', a.deleted_at,
      'deletedByName', COALESCE(NULLIF(TRIM(u."firstName" || ' ' || u."lastName"), ''), u.username),
      'restoredAt', a.restored_at,
      'restoredByName', COALESCE(NULLIF(TRIM(ru."firstName" || ' ' || ru."lastName"), ''), ru.username)
    ) AS row_data,
    a.deleted_at
    FROM operations_archive a
    LEFT JOIN "Companies" c ON c.id = a.company_id
    LEFT JOIN "Users" u ON u.id = a.deleted_by
    LEFT JOIN "Users" ru ON ru.id = a.restored_by
    WHERE (p_company_id IS NULL OR a.company_id = p_company_id)
      AND (p_table_name IS NULL OR a.table_name = p_table_name)
    ORDER BY a.deleted_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500)
  ) t;

  RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_archived_record(p_archive_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid := public.current_app_user_id();
  v_archive record;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Droits insuffisants — réservé au super administrateur';
  END IF;

  SELECT * INTO v_archive FROM operations_archive WHERE id = p_archive_id;
  IF v_archive.id IS NULL THEN
    RAISE EXCEPTION 'Archive introuvable';
  END IF;
  IF v_archive.restored_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cet enregistrement a déjà été restauré le %', v_archive.restored_at;
  END IF;

  CASE v_archive.table_name
    WHEN 'mouvements_caisse' THEN
      INSERT INTO mouvements_caisse SELECT * FROM jsonb_populate_record(null::mouvements_caisse, v_archive.payload);
    WHEN 'reversements_comptables' THEN
      INSERT INTO reversements_comptables SELECT * FROM jsonb_populate_record(null::reversements_comptables, v_archive.payload);
    WHEN 'bordereau_colis' THEN
      INSERT INTO bordereau_colis SELECT * FROM jsonb_populate_record(null::bordereau_colis, v_archive.payload);
    WHEN 'ReservationBusColis' THEN
      INSERT INTO "ReservationBusColis" SELECT * FROM jsonb_populate_record(null::"ReservationBusColis", v_archive.payload);
    WHEN 'ReservationBus' THEN
      INSERT INTO "ReservationBus" SELECT * FROM jsonb_populate_record(null::"ReservationBus", v_archive.payload);
    WHEN 'Reservations' THEN
      INSERT INTO "Reservations" SELECT * FROM jsonb_populate_record(null::"Reservations", v_archive.payload);
    WHEN 'colis_autonomes' THEN
      INSERT INTO colis_autonomes SELECT * FROM jsonb_populate_record(null::colis_autonomes, v_archive.payload);
    WHEN 'bordereaux_livraison' THEN
      INSERT INTO bordereaux_livraison SELECT * FROM jsonb_populate_record(null::bordereaux_livraison, v_archive.payload);
    ELSE
      RAISE EXCEPTION 'Type de table non restaurable : %', v_archive.table_name;
  END CASE;

  UPDATE operations_archive SET restored_at = now(), restored_by = v_user_id WHERE id = p_archive_id;

  RETURN jsonb_build_object('id', p_archive_id, 'tableName', v_archive.table_name, 'recordId', v_archive.record_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_archived_operations(uuid, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_archived_operations(uuid, text, integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.restore_archived_record(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restore_archived_record(uuid) TO authenticated;
