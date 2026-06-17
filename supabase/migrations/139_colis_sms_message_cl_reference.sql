-- SMS colis : référence courte CL-XXXXXXXX au lieu de l'UUID complet

CREATE OR REPLACE FUNCTION public.colis_public_reference_sql(p_colis_id uuid)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'CL-' || upper(substr(replace(p_colis_id::text, '-', ''), 1, 8));
$$;

CREATE OR REPLACE FUNCTION public.build_colis_sms_message(
  p_statut text,
  p_colis_id uuid,
  p_company_name text,
  p_gare_depart text,
  p_gare_destination text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_ref text := public.colis_public_reference_sql(p_colis_id);
BEGIN
  RETURN CASE p_statut
    WHEN 'enregistre' THEN format(
      'Tibus/%s: colis enregistre. Ref %s. %s -> %s.',
      COALESCE(p_company_name, 'Compagnie'), v_ref,
      COALESCE(p_gare_depart, '?'), COALESCE(p_gare_destination, '?')
    )
    WHEN 'charge' THEN format(
      'Tibus/%s: votre colis est charge en soute (%s -> %s). Ref %s.',
      COALESCE(p_company_name, 'Compagnie'),
      COALESCE(p_gare_depart, '?'), COALESCE(p_gare_destination, '?'), v_ref
    )
    WHEN 'arrive' THEN format(
      'Tibus/%s: colis arrive a %s. Ref retrait %s.',
      COALESCE(p_company_name, 'Compagnie'), COALESCE(p_gare_destination, 'gare'), v_ref
    )
    WHEN 'livre' THEN format(
      'Tibus/%s: colis remis au destinataire. Ref %s. Merci.',
      COALESCE(p_company_name, 'Compagnie'), v_ref
    )
    ELSE NULL
  END;
END;
$$;
