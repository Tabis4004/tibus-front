-- =============================================================================
-- Tibus — Politiques RLS DEFINITIVES
-- =============================================================================
-- PRÉREQUIS : init_schema.sql + 001_roles_model.sql exécutés
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Fonctions utilitaires
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.id FROM "Users" u WHERE u."auth_user_id" = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.has_global_role(p_roles text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    JOIN "Users" u ON u.id = ur."userId"
    WHERE u."auth_user_id" = auth.uid()
      AND ur."companyId" IS NULL
      AND ur."countryId" IS NULL
      AND r.scope = 'platform'
      AND r.name = ANY (p_roles)
  );
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.has_global_role(ARRAY['super_admin']);
$$;

CREATE OR REPLACE FUNCTION public.has_country_role(p_country_id uuid, p_roles text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      JOIN "Users" u ON u.id = ur."userId"
      WHERE u."auth_user_id" = auth.uid()
        AND ur."companyId" IS NULL
        AND ur."countryId" = p_country_id
        AND r.name = ANY (p_roles)
    );
$$;

CREATE OR REPLACE FUNCTION public.has_company_role(p_company_id uuid, p_roles text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "UserRoles" ur
    JOIN "Role" r ON r.id = ur."roleId"
    JOIN "Users" u ON u.id = ur."userId"
    WHERE u."auth_user_id" = auth.uid()
      AND ur."companyId" = p_company_id
      AND r.name = ANY (p_roles)
  );
$$;

CREATE OR REPLACE FUNCTION public.has_company_droit(p_company_id uuid, p_droit text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      JOIN "Users" u ON u.id = ur."userId"
      WHERE u."auth_user_id" = auth.uid()
        AND ur."companyId" = p_company_id
        AND p_droit = ANY (r.droits)
    )
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      JOIN "Users" u ON u.id = ur."userId"
      JOIN "Companies" c ON c."countryId" = ur."countryId"
      WHERE u."auth_user_id" = auth.uid()
        AND c.id = p_company_id
        AND r.name = 'admin_pays'
        AND p_droit = ANY (r.droits)
    );
$$;

CREATE OR REPLACE FUNCTION public.has_global_droit(p_droit text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM "UserRoles" ur
      JOIN "Role" r ON r.id = ur."roleId"
      JOIN "Users" u ON u.id = ur."userId"
      WHERE u."auth_user_id" = auth.uid()
        AND ur."companyId" IS NULL
        AND p_droit = ANY (r.droits)
    );
$$;

CREATE OR REPLACE FUNCTION public.can_sell_all_companies()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_global_droit('sell_all_companies');
$$;

CREATE OR REPLACE FUNCTION public.is_in_master_network()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM "MasterVendorNetwork" mvn
    JOIN "Users" u ON u.id = mvn."vendorUserId"
    WHERE u."auth_user_id" = auth.uid() AND mvn."isActive" = true
  );
$$;

CREATE OR REPLACE FUNCTION public.can_sell_for_company(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.can_sell_all_companies()
    OR public.has_company_droit(p_company_id, 'sell_tickets')
    -- Vendeur indépendant : plateforme directe, hors réseau master
    OR (
      public.has_global_role(ARRAY['vendeur_independant'])
      AND NOT public.is_in_master_network()
      AND EXISTS (
        SELECT 1 FROM "IndependentSellerCompanies" isc
        JOIN "Users" u ON u.id = isc."sellerUserId"
        WHERE u."auth_user_id" = auth.uid()
          AND isc."companyId" = p_company_id AND isc."isActive" = true
      )
    )
    -- Vendeur réseau : assigné par un master, compagnies autorisées par le master
    OR (
      public.has_global_role(ARRAY['vendeur_reseau', 'vendeur_master', 'master'])
      AND public.is_in_master_network()
      AND EXISTS (
        SELECT 1 FROM "IndependentSellerCompanies" isc
        JOIN "Users" u ON u.id = isc."sellerUserId"
        WHERE u."auth_user_id" = auth.uid()
          AND isc."companyId" = p_company_id AND isc."isActive" = true
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.is_company_staff(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR public.has_company_role(p_company_id, ARRAY[
      'owner', 'comptable_compagnie', 'controleur', 'vendeur'
    ])
    OR public.can_sell_for_company(p_company_id);
$$;

CREATE OR REPLACE FUNCTION public.can_assign_role(
  p_assignable_role_id uuid,
  p_company_id uuid DEFAULT NULL
)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
    OR EXISTS (
      SELECT 1
      FROM "UserRoles" ur_assigner
      JOIN "Role" r_assigner ON r_assigner.id = ur_assigner."roleId"
      JOIN "RoleAssignmentRules" rar ON rar."assignerRoleId" = r_assigner.id
      JOIN "Users" u ON u.id = ur_assigner."userId"
      JOIN "Role" r_target ON r_target.id = p_assignable_role_id
      WHERE u."auth_user_id" = auth.uid()
        AND rar."assignableRoleId" = p_assignable_role_id
        AND (
          (r_target.scope = 'platform' AND ur_assigner."companyId" IS NULL)
          OR (
            r_target.scope = 'company'
            AND r_assigner.name = 'owner'
            AND ur_assigner."companyId" = p_company_id
          )
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.trajet_company_id(p_trajet_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT g."companyId"
  FROM "ProgrammationTrajets" pt
  JOIN "Gares" g ON g.id = pt.depart
  WHERE pt.id = p_trajet_id LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.reservation_company_id(p_reservation_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.trajet_company_id(r."trajetId")
  FROM "Reservations" r WHERE r.id = p_reservation_id LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- Countries & Cities — lecture publique
-- ---------------------------------------------------------------------------

CREATE POLICY "countries_select_public" ON "Countries"
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "countries_write_admin" ON "Countries"
  FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_global_droit('manage_country'))
  WITH CHECK (public.is_super_admin() OR public.has_global_droit('manage_country'));

CREATE POLICY "cities_select_public" ON "Cities"
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "cities_write_admin" ON "Cities"
  FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_global_droit('manage_country'))
  WITH CHECK (public.is_super_admin() OR public.has_global_droit('manage_country'));

-- ---------------------------------------------------------------------------
-- Role & RoleAssignmentRules — gestion par super_admin
-- ---------------------------------------------------------------------------

CREATE POLICY "role_select_authenticated" ON "Role"
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "role_write_super_admin" ON "Role"
  FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_global_droit('manage_roles'))
  WITH CHECK (public.is_super_admin() OR public.has_global_droit('manage_roles'));

CREATE POLICY "role_assignment_rules_select" ON "RoleAssignmentRules"
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "role_assignment_rules_write" ON "RoleAssignmentRules"
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

CREATE POLICY "users_select" ON "Users" FOR SELECT TO authenticated USING (
  "auth_user_id" = auth.uid()
  OR public.is_super_admin()
  OR public.has_global_droit('manage_platform')
  OR EXISTS (
    SELECT 1 FROM "UserRoles" ur_me
    JOIN "UserRoles" ur_them ON ur_them."companyId" = ur_me."companyId"
    JOIN "Role" r ON r.id = ur_me."roleId"
    WHERE ur_me."userId" = public.current_app_user_id()
      AND ur_them."userId" = "Users".id
      AND ur_me."companyId" IS NOT NULL
      AND r.name = 'owner'
  )
);

CREATE POLICY "users_insert_self" ON "Users" FOR INSERT TO authenticated
  WITH CHECK ("auth_user_id" = auth.uid());

CREATE POLICY "users_update" ON "Users" FOR UPDATE TO authenticated
  USING ("auth_user_id" = auth.uid() OR public.is_super_admin())
  WITH CHECK ("auth_user_id" = auth.uid() OR public.is_super_admin());

-- ---------------------------------------------------------------------------
-- UserRoles
-- ---------------------------------------------------------------------------

CREATE POLICY "userroles_select" ON "UserRoles" FOR SELECT TO authenticated USING (
  public.is_super_admin()
  OR "userId" = public.current_app_user_id()
  OR public.is_company_staff("companyId")
  OR public.has_global_droit('manage_platform')
);

CREATE POLICY "userroles_insert" ON "UserRoles" FOR INSERT TO authenticated WITH CHECK (
  public.is_super_admin()
  -- Auto-inscription voyageur
  OR (
    "userId" = public.current_app_user_id()
    AND "companyId" IS NULL AND "countryId" IS NULL
    AND EXISTS (SELECT 1 FROM "Role" r WHERE r.id = "roleId" AND r.name = 'traveler')
  )
  -- Auto-inscription vendeur indépendant (plateforme directe, hors réseau master)
  OR (
    "userId" = public.current_app_user_id()
    AND "companyId" IS NULL AND "countryId" IS NULL
    AND NOT public.is_in_master_network()
    AND EXISTS (SELECT 1 FROM "Role" r WHERE r.id = "roleId" AND r.name = 'vendeur_independant')
  )
  OR public.can_assign_role("roleId", "companyId")
);

CREATE POLICY "userroles_update" ON "UserRoles" FOR UPDATE TO authenticated
  USING (public.is_super_admin() OR public.can_assign_role("roleId", "companyId"))
  WITH CHECK (public.is_super_admin() OR public.can_assign_role("roleId", "companyId"));

CREATE POLICY "userroles_delete" ON "UserRoles" FOR DELETE TO authenticated
  USING (public.is_super_admin() OR public.can_assign_role("roleId", "companyId"));

-- ---------------------------------------------------------------------------
-- Companies
-- ---------------------------------------------------------------------------

CREATE POLICY "companies_select" ON "Companies" FOR SELECT TO anon, authenticated USING (
  "isActive" = true
  OR public.is_super_admin()
  OR public.is_company_staff(id)
  OR public.has_country_role("countryId", ARRAY['admin_pays'])
);

CREATE POLICY "companies_insert" ON "Companies" FOR INSERT TO authenticated
  WITH CHECK (public.is_super_admin() OR public.has_global_droit('manage_company'));

CREATE POLICY "companies_update" ON "Companies" FOR UPDATE TO authenticated
  USING (public.has_company_droit(id, 'manage_company') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit(id, 'manage_company') OR public.is_super_admin());

CREATE POLICY "companies_delete" ON "Companies" FOR DELETE TO authenticated
  USING (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Bus & Gares
-- ---------------------------------------------------------------------------

CREATE POLICY "bus_select" ON "Bus" FOR SELECT TO anon, authenticated USING (
  EXISTS (SELECT 1 FROM "Companies" c WHERE c.id = "Bus"."companyId" AND c."isActive" = true)
  OR public.is_super_admin() OR public.is_company_staff("companyId")
);

CREATE POLICY "bus_write" ON "Bus" FOR ALL TO authenticated
  USING (public.has_company_droit("companyId", 'manage_buses') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit("companyId", 'manage_buses') OR public.is_super_admin());

CREATE POLICY "gares_select" ON "Gares" FOR SELECT TO anon, authenticated USING (
  EXISTS (SELECT 1 FROM "Companies" c WHERE c.id = "Gares"."companyId" AND c."isActive" = true)
  OR public.is_super_admin() OR public.is_company_staff("companyId")
);

CREATE POLICY "gares_write" ON "Gares" FOR ALL TO authenticated
  USING (public.has_company_droit("companyId", 'manage_stations') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit("companyId", 'manage_stations') OR public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Programmation (lecture globale pour voyageurs)
-- ---------------------------------------------------------------------------

CREATE POLICY "programmationtrajets_select" ON "ProgrammationTrajets"
  FOR SELECT TO anon, authenticated USING (
    EXISTS (
      SELECT 1 FROM "Gares" g JOIN "Companies" c ON c.id = g."companyId"
      WHERE g.id = "ProgrammationTrajets".depart AND c."isActive" = true
    )
    OR public.is_super_admin()
    OR public.is_company_staff(public.trajet_company_id(id))
  );

CREATE POLICY "programmationtrajets_write" ON "ProgrammationTrajets"
  FOR ALL TO authenticated
  USING (public.has_company_droit(public.trajet_company_id(id), 'manage_trips') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit(public.trajet_company_id(id), 'manage_trips') OR public.is_super_admin());

CREATE POLICY "programmationtrajetdays_select" ON "ProgrammationTrajetDays"
  FOR SELECT TO anon, authenticated USING (
    EXISTS (
      SELECT 1 FROM "ProgrammationTrajets" pt
      JOIN "Gares" g ON g.id = pt.depart JOIN "Companies" c ON c.id = g."companyId"
      WHERE pt.id = "ProgrammationTrajetDays"."trajetId" AND c."isActive" = true
    ) OR public.is_super_admin() OR public.is_company_staff(public.trajet_company_id("trajetId"))
  );

CREATE POLICY "programmationtrajetdays_write" ON "ProgrammationTrajetDays"
  FOR ALL TO authenticated
  USING (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_trips') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_trips') OR public.is_super_admin());

CREATE POLICY "programmationtrajetarrets_select" ON "ProgrammationTrajetArrets"
  FOR SELECT TO anon, authenticated USING (
    EXISTS (
      SELECT 1 FROM "ProgrammationTrajets" pt
      JOIN "Gares" g ON g.id = pt.depart JOIN "Companies" c ON c.id = g."companyId"
      WHERE pt.id = "ProgrammationTrajetArrets"."trajetId" AND c."isActive" = true
    ) OR public.is_super_admin() OR public.is_company_staff(public.trajet_company_id("trajetId"))
  );

CREATE POLICY "programmationtrajetarrets_write" ON "ProgrammationTrajetArrets"
  FOR ALL TO authenticated
  USING (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_routes') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_routes') OR public.is_super_admin());

CREATE POLICY "programmationbus_select" ON "ProgrammationBus"
  FOR SELECT TO anon, authenticated USING (
    EXISTS (
      SELECT 1 FROM "ProgrammationTrajets" pt
      JOIN "Gares" g ON g.id = pt.depart JOIN "Companies" c ON c.id = g."companyId"
      WHERE pt.id = "ProgrammationBus"."trajetId" AND c."isActive" = true
    ) OR public.is_super_admin() OR public.is_company_staff(public.trajet_company_id("trajetId"))
  );

CREATE POLICY "programmationbus_write" ON "ProgrammationBus"
  FOR ALL TO authenticated
  USING (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_trips') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_trips') OR public.is_super_admin());

-- ---------------------------------------------------------------------------
-- Reservations & ReservationBus
-- ---------------------------------------------------------------------------

CREATE POLICY "reservations_select" ON "Reservations"
  FOR SELECT TO anon, authenticated USING (
    EXISTS (
      SELECT 1 FROM "ProgrammationTrajets" pt
      JOIN "Gares" g ON g.id = pt.depart JOIN "Companies" c ON c.id = g."companyId"
      WHERE pt.id = "Reservations"."trajetId" AND c."isActive" = true
    ) OR public.is_super_admin() OR public.is_company_staff(public.trajet_company_id("trajetId"))
  );

CREATE POLICY "reservations_write" ON "Reservations"
  FOR ALL TO authenticated
  USING (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_trips') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit(public.trajet_company_id("trajetId"), 'manage_trips') OR public.is_super_admin());

CREATE POLICY "payment_select" ON "Payment" FOR SELECT TO authenticated USING (
  public.is_super_admin()
  OR EXISTS (
    SELECT 1 FROM "ReservationBus" rb
    WHERE rb."paymentId" = "Payment".id
      AND (rb."createdBy" = public.current_app_user_id()
        OR public.is_company_staff(public.reservation_company_id(rb."reservationId")))
  )
  OR EXISTS (
    SELECT 1 FROM "Subscriptions" s
    WHERE s."paymentId" = "Payment".id
      AND (s."createdBy" = public.current_app_user_id()
        OR public.is_company_staff(s."companyId"))
  )
);

CREATE POLICY "reservationbus_select" ON "ReservationBus" FOR SELECT TO authenticated USING (
  public.is_super_admin()
  OR "createdBy" = public.current_app_user_id()
  OR public.has_company_droit(public.reservation_company_id("reservationId"), 'view_bookings')
  OR public.has_global_droit('view_bookings')
);

CREATE POLICY "reservationbus_insert" ON "ReservationBus" FOR INSERT TO authenticated WITH CHECK (
  public.is_super_admin()
  OR (
    "createdBy" = public.current_app_user_id()
    AND public.has_global_role(ARRAY['traveler'])
  )
  OR public.can_sell_for_company(public.reservation_company_id("reservationId"))
);

CREATE POLICY "reservationbus_update" ON "ReservationBus" FOR UPDATE TO authenticated
  USING (
    public.is_super_admin()
    OR "createdBy" = public.current_app_user_id()
    OR public.has_company_droit(public.reservation_company_id("reservationId"), 'cancel_bookings')
    OR public.has_company_droit(public.reservation_company_id("reservationId"), 'view_bookings')
  )
  WITH CHECK (
    public.is_super_admin()
    OR "createdBy" = public.current_app_user_id()
    OR public.has_company_droit(public.reservation_company_id("reservationId"), 'cancel_bookings')
    OR public.has_company_droit(public.reservation_company_id("reservationId"), 'view_bookings')
  );

CREATE POLICY "reservationbuscolis_select" ON "ReservationBusColis" FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM "ReservationBus" rb
    WHERE rb.id = "ReservationBusColis"."reservationId"
      AND (public.is_super_admin() OR rb."createdBy" = public.current_app_user_id()
        OR public.has_company_droit(public.reservation_company_id(rb."reservationId"), 'view_bookings'))
  )
);

CREATE POLICY "reservationbuscolis_write" ON "ReservationBusColis" FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "ReservationBus" rb
      WHERE rb.id = "ReservationBusColis"."reservationId"
        AND (public.is_super_admin() OR rb."createdBy" = public.current_app_user_id()
          OR public.can_sell_for_company(public.reservation_company_id(rb."reservationId")))
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM "ReservationBus" rb
      WHERE rb.id = "ReservationBusColis"."reservationId"
        AND (public.is_super_admin() OR rb."createdBy" = public.current_app_user_id()
          OR public.can_sell_for_company(public.reservation_company_id(rb."reservationId")))
    )
  );

-- ---------------------------------------------------------------------------
-- Abonnements
-- ---------------------------------------------------------------------------

CREATE POLICY "subscriptionplans_select" ON "SubscriptionPlans"
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "subscriptionplans_write" ON "SubscriptionPlans"
  FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

CREATE POLICY "subscriptionplandurations_select" ON "SubscriptionPlanDurations"
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "subscriptionplandurations_write" ON "SubscriptionPlanDurations"
  FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

CREATE POLICY "subscriptions_select" ON "Subscriptions" FOR SELECT TO authenticated USING (
  public.is_super_admin() OR public.is_company_staff("companyId") OR "createdBy" = public.current_app_user_id()
);
CREATE POLICY "subscriptions_write" ON "Subscriptions" FOR ALL TO authenticated
  USING (public.has_company_droit("companyId", 'manage_subscriptions') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit("companyId", 'manage_subscriptions') OR public.is_super_admin());

-- ---------------------------------------------------------------------------
-- PromoCodes, Notifications, Reviews
-- ---------------------------------------------------------------------------

CREATE POLICY "promocodes_select" ON "PromoCodes"
  FOR SELECT TO anon, authenticated USING (
    "isActive" = true OR public.is_super_admin() OR public.is_company_staff("companyId")
  );
CREATE POLICY "promocodes_write" ON "PromoCodes" FOR ALL TO authenticated
  USING (public.has_company_droit("companyId", 'manage_company') OR public.is_super_admin())
  WITH CHECK (public.has_company_droit("companyId", 'manage_company') OR public.is_super_admin());

CREATE POLICY "notifications_select" ON "Notifications" FOR SELECT TO authenticated USING (
  public.is_super_admin() OR "userId" = public.current_app_user_id()
);
CREATE POLICY "notifications_insert" ON "Notifications" FOR INSERT TO authenticated WITH CHECK (
  public.is_super_admin() OR "userId" = public.current_app_user_id()
  OR public.has_global_droit('manage_platform')
);
CREATE POLICY "notifications_update" ON "Notifications" FOR UPDATE TO authenticated
  USING (public.is_super_admin() OR "userId" = public.current_app_user_id())
  WITH CHECK (public.is_super_admin() OR "userId" = public.current_app_user_id());

CREATE POLICY "reviews_select" ON "Reviews" FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "reviews_insert" ON "Reviews" FOR INSERT TO authenticated WITH CHECK (
  "travelerId" = public.current_app_user_id()
  AND EXISTS (
    SELECT 1 FROM "ReservationBus" rb
    WHERE rb.id = "reservationBusId" AND rb."createdBy" = public.current_app_user_id()
  )
);
CREATE POLICY "reviews_update" ON "Reviews" FOR UPDATE TO authenticated
  USING (
    public.is_super_admin()
    OR public.has_company_droit("companyId", 'manage_company')
    OR "travelerId" = public.current_app_user_id()
  )
  WITH CHECK (
    public.is_super_admin()
    OR public.has_company_droit("companyId", 'manage_company')
    OR "travelerId" = public.current_app_user_id()
  );

-- ---------------------------------------------------------------------------
-- IndependentSellerCompanies
-- ---------------------------------------------------------------------------

-- IndependentSellerCompanies : vendeurs indépendants (plateforme)
CREATE POLICY "isc_select" ON "IndependentSellerCompanies" FOR SELECT TO authenticated USING (
  public.is_super_admin()
  OR public.has_global_droit('manage_independent_sellers')
  OR "sellerUserId" = public.current_app_user_id()
  OR public.has_company_role("companyId", ARRAY['owner'])
);

CREATE POLICY "isc_write" ON "IndependentSellerCompanies" FOR ALL TO authenticated
  USING (
    public.is_super_admin()
  OR public.has_global_droit('manage_independent_sellers')
  OR public.has_company_role("companyId", ARRAY['owner'])
  )
  WITH CHECK (
    public.is_super_admin()
  OR public.has_global_droit('manage_independent_sellers')
  OR public.has_company_role("companyId", ARRAY['owner'])
  );

-- MasterVendorNetwork : réseau master (séparé des indépendants)
CREATE POLICY "mvn_select" ON "MasterVendorNetwork" FOR SELECT TO authenticated USING (
  public.is_super_admin()
  OR "masterUserId" = public.current_app_user_id()
  OR "vendorUserId" = public.current_app_user_id()
  OR public.has_global_droit('manage_network_sellers')
);

CREATE POLICY "mvn_write" ON "MasterVendorNetwork" FOR ALL TO authenticated
  USING (
    public.is_super_admin()
    OR "masterUserId" = public.current_app_user_id()
    OR public.has_global_droit('manage_network_sellers')
  )
  WITH CHECK (
    public.is_super_admin()
    OR "masterUserId" = public.current_app_user_id()
    OR public.has_global_droit('manage_network_sellers')
  );

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.current_app_user_id() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_global_role(text[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_country_role(uuid, text[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_company_role(uuid, text[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_company_droit(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_global_droit(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_sell_all_companies() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_in_master_network() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_sell_for_company(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_company_staff(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_assign_role(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trajet_company_id(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reservation_company_id(uuid) TO anon, authenticated;
