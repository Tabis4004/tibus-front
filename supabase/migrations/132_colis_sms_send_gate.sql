-- SMS colis : n'envoyer que si l'admin a autorisé la config owner ET l'étape est activée.

CREATE OR REPLACE FUNCTION public.colis_sms_enabled_for_statut(p_company_id uuid, p_statut text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.company_colis_sms_owner_config_enabled(p_company_id)
    AND CASE p_statut
      WHEN 'enregistre' THEN COALESCE(c.sms_on_enregistre, false)
      WHEN 'charge' THEN COALESCE(c.sms_on_charge, false)
      WHEN 'arrive' THEN COALESCE(c.sms_on_arrive, false)
      WHEN 'livre' THEN COALESCE(c.sms_on_livre, false)
      ELSE false
    END
  FROM "Companies" c
  WHERE c.id = p_company_id;
$$;
