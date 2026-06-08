-- =============================================================================
-- Tibus — RLS Payment INSERT pour réservations voyageur
-- Étape 8 : permet aux travelers de créer un enregistrement Payment
-- =============================================================================

CREATE POLICY "payment_insert_traveler" ON "Payment"
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_super_admin()
    OR public.has_global_role(ARRAY['traveler'])
  );
