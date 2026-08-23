--
-- PostgreSQL database dump
--

\restrict 87kobLgFsaA4L3pwhdubygoDFCKSLyqom6wRg1dDkcB4dEmqD5PGfVxVqGbmUaG

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: Companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Companies" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    "countryId" uuid NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL,
    "commissionRate" double precision NOT NULL,
    logo text,
    "managerName" character varying,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "arretReservation" boolean DEFAULT true NOT NULL,
    "voyageColisMsg" text,
    "guaranteeBalance" double precision DEFAULT 0 NOT NULL,
    "guaranteeAllowNegative" boolean DEFAULT false NOT NULL,
    colis_autonome_enabled boolean DEFAULT false NOT NULL,
    sms_on_enregistre boolean DEFAULT false NOT NULL,
    sms_on_charge boolean DEFAULT false NOT NULL,
    sms_on_arrive boolean DEFAULT false NOT NULL,
    sms_on_livre boolean DEFAULT false NOT NULL,
    "recruitedByUserId" uuid,
    "ownerContractAcceptedAt" timestamp with time zone,
    "ownerContractAcceptedBy" uuid,
    "liveAuthorizedByAdmin" boolean DEFAULT false NOT NULL,
    "liveAuthorizedAt" timestamp with time zone,
    "liveAuthorizedBy" uuid,
    "payAtStation" boolean DEFAULT false NOT NULL,
    colis_prix_min_fixe_general double precision,
    colis_prix_min_taux_general double precision,
    colis_pourcentage_percu_general double precision,
    phone character varying,
    colis_ui_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT "Companies_commissionRate_check" CHECK (("commissionRate" >= (0)::double precision))
);


--
-- Name: COLUMN "Companies"."payAtStation"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Companies"."payAtStation" IS 'Si true, le voyageur paie en ligne X%+gateway uniquement. M réglé en gare.';


--
-- Name: CompanyFeatureModules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."CompanyFeatureModules" (
    "companyId" uuid NOT NULL,
    "moduleA" boolean DEFAULT true NOT NULL,
    "moduleB" boolean DEFAULT true NOT NULL,
    "moduleC" boolean DEFAULT true NOT NULL,
    "moduleD" boolean DEFAULT true NOT NULL,
    "moduleE" boolean DEFAULT false NOT NULL,
    "moduleF" boolean DEFAULT false NOT NULL,
    "updatedAt" timestamp with time zone DEFAULT now() NOT NULL,
    "updatedBy" uuid,
    "moduleDColisSmsConfig" boolean DEFAULT false NOT NULL,
    "smsEnregistreAllowed" boolean DEFAULT false NOT NULL,
    "smsChargeAllowed" boolean DEFAULT false NOT NULL,
    "smsArriveAllowed" boolean DEFAULT false NOT NULL,
    "smsLivreAllowed" boolean DEFAULT false NOT NULL
);


--
-- Name: Bus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Bus" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "registrationNumber" character varying NOT NULL,
    model character varying,
    "isActive" boolean DEFAULT true NOT NULL,
    capacity integer NOT NULL,
    "companyId" uuid NOT NULL,
    CONSTRAINT "Bus_capacity_check" CHECK ((capacity > 1))
);


--
-- Name: Cities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Cities" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    "countryId" uuid NOT NULL
);


--
-- Name: ColisTrackingSubscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."ColisTrackingSubscriptions" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "colisId" uuid NOT NULL,
    "userId" uuid NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: CompanyExpenseCategory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."CompanyExpenseCategory" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "companyId" uuid NOT NULL,
    name text NOT NULL,
    "ohadaAccountCode" text NOT NULL,
    "ohadaAccountLabel" text NOT NULL,
    "sortOrder" integer DEFAULT 0 NOT NULL,
    "isPreset" boolean DEFAULT false NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ContactSettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."ContactSettings" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    scope text NOT NULL,
    "whatsappNumber" text,
    "updatedAt" timestamp with time zone DEFAULT now() NOT NULL,
    "updatedBy" uuid,
    "notificationEmail" text,
    CONSTRAINT "ContactSettings_channel_check" CHECK (((NULLIF(btrim(COALESCE("whatsappNumber", ''::text)), ''::text) IS NOT NULL) OR (NULLIF(btrim(COALESCE("notificationEmail", ''::text)), ''::text) IS NOT NULL))),
    CONSTRAINT "ContactSettings_scope_check" CHECK ((char_length(TRIM(BOTH FROM scope)) > 0))
);


--
-- Name: Countries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Countries" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    currency character varying
);


--
-- Name: DeviceTokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."DeviceTokens" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "userId" uuid NOT NULL,
    "fcmToken" character varying NOT NULL,
    platform character varying NOT NULL,
    "appVersion" character varying,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "lastSeenAt" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "DeviceTokens_platform_check" CHECK (((platform)::text = ANY ((ARRAY['android'::character varying, 'ios'::character varying])::text[])))
);


--
-- Name: Gares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Gares" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    "companyId" uuid NOT NULL,
    "googleMapsLink" text,
    "gestionnaireUserId" uuid,
    "gestionnaireSharePct" double precision DEFAULT 0 NOT NULL,
    "gestionnaireSharePctReservation" double precision DEFAULT 0 NOT NULL,
    latitude double precision,
    longitude double precision,
    "cityId" uuid NOT NULL,
    phone character varying,
    CONSTRAINT gares_gestionnaire_share_pct_check CHECK ((("gestionnaireSharePct" >= (0)::double precision) AND ("gestionnaireSharePct" <= (100)::double precision))),
    CONSTRAINT gares_gestionnaire_share_pct_reservation_check CHECK ((("gestionnaireSharePctReservation" >= (0)::double precision) AND ("gestionnaireSharePctReservation" <= (100)::double precision)))
);


--
-- Name: TABLE "Gares"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public."Gares" IS 'Points d''arrêt / gares routières de la compagnie';


--
-- Name: COLUMN "Gares"."googleMapsLink"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Gares"."googleMapsLink" IS 'Lien Google Maps à copier-coller (ex: https://maps.app.goo.gl/...)';


--
-- Name: COLUMN "Gares".latitude; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Gares".latitude IS 'Latitude WGS84 (optionnel, pour carte accueil)';


--
-- Name: COLUMN "Gares".longitude; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Gares".longitude IS 'Longitude WGS84 (optionnel, pour carte accueil)';


--
-- Name: COLUMN "Gares"."cityId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Gares"."cityId" IS 'Ville de la gare (doit etre dans le pays de la compagnie)';


--
-- Name: Notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Notifications" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "userId" uuid NOT NULL,
    type character varying NOT NULL,
    title character varying NOT NULL,
    message text NOT NULL,
    "isRead" boolean DEFAULT false NOT NULL,
    "relatedReservationBusId" uuid,
    "relatedReservationId" uuid,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb
);


--
-- Name: Role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Role" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    droits character varying[] NOT NULL,
    scope character varying DEFAULT 'company'::character varying NOT NULL,
    level integer DEFAULT 0 NOT NULL,
    "isSystem" boolean DEFAULT true NOT NULL,
    description text,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "createdBy" uuid,
    CONSTRAINT "Role_scope_check" CHECK (((scope)::text = ANY ((ARRAY['platform'::character varying, 'company'::character varying])::text[])))
);


--
-- Name: COLUMN "Role".droits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Role".droits IS 'Permissions : manage_platform, manage_roles, manage_country, manage_company,
   manage_buses, manage_stations, manage_routes, manage_trips, sell_tickets,
   sell_all_companies, reserve_tickets, view_bookings, cancel_bookings,
   manage_sellers, manage_independent_sellers, manage_network_sellers,
   view_network_commissions, view_reports, manage_subscriptions,
   manage_accounting, control_tickets, assign_company_roles';


--
-- Name: COLUMN "Role".scope; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Role".scope IS 'platform = sans compagnie | company = lié à une compagnie';


--
-- Name: COLUMN "Role".level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Role".level IS 'Ordre hiérarchique indicatif (plus élevé = plus de pouvoir)';


--
-- Name: COLUMN "Role"."isSystem"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Role"."isSystem" IS 'true = rôle système, false = rôle custom créé par super_admin';


--
-- Name: UserRoles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserRoles" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "roleId" uuid NOT NULL,
    "userId" uuid NOT NULL,
    "companyId" uuid,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "countryId" uuid,
    "assignedBy" uuid,
    "assignedAt" timestamp with time zone DEFAULT now() NOT NULL,
    "gareId" uuid
);


--
-- Name: Users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Users" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid,
    "firstName" character varying NOT NULL,
    "lastName" character varying NOT NULL,
    username character varying NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    email character varying,
    phone character varying,
    "countryId" uuid NOT NULL,
    "profileCompleted" boolean DEFAULT false NOT NULL,
    "onboardingCompleted" boolean DEFAULT false NOT NULL,
    "referralCode" character varying,
    "referredByUserId" uuid,
    "activeOwnerCompanyId" uuid
);


--
-- Name: caisses_gares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caisses_gares (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    gare_id uuid NOT NULL,
    gestionnaire_id uuid NOT NULL,
    solde_especes_actuel integer DEFAULT 0 NOT NULL,
    statut text DEFAULT 'ouverte'::text NOT NULL,
    fond_roulement integer DEFAULT 0 NOT NULL,
    opened_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    CONSTRAINT caisses_gares_fond_check CHECK ((fond_roulement >= 0)),
    CONSTRAINT caisses_gares_solde_check CHECK ((solde_especes_actuel >= 0)),
    CONSTRAINT caisses_gares_statut_check CHECK ((statut = ANY (ARRAY['ouverte'::text, 'en_reversement'::text, 'cloturee'::text])))
);


--
-- Name: colis_autonomes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colis_autonomes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    gare_depart_id uuid NOT NULL,
    gare_destination_id uuid NOT NULL,
    nom_expediteur text NOT NULL,
    telephone_expediteur text NOT NULL,
    nom_destinataire text NOT NULL,
    telephone_destinataire text NOT NULL,
    description_contenu text,
    poids_kg double precision,
    nombre_pieces integer DEFAULT 1 NOT NULL,
    montant_fret double precision DEFAULT 0 NOT NULL,
    vendeur_id uuid NOT NULL,
    source_vente text DEFAULT 'guichet_cash'::text NOT NULL,
    statut_colis text DEFAULT 'enregistre'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    valeur_marchandise double precision,
    pourcentage_percu double precision,
    bus_id uuid,
    photo_path text,
    numero_recu text,
    annule_par uuid,
    annule_at timestamp with time zone,
    motif_annulation text,
    custom_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT colis_autonomes_destinataire_check CHECK ((btrim(nom_destinataire) <> ''::text)),
    CONSTRAINT colis_autonomes_expediteur_check CHECK ((btrim(nom_expediteur) <> ''::text)),
    CONSTRAINT colis_autonomes_montant_check CHECK ((montant_fret >= (0)::double precision)),
    CONSTRAINT colis_autonomes_nombre_pieces_check CHECK ((nombre_pieces > 0)),
    CONSTRAINT colis_autonomes_source_vente_check CHECK ((source_vente = 'guichet_cash'::text)),
    CONSTRAINT colis_autonomes_statut_check CHECK ((statut_colis = ANY (ARRAY['enregistre'::text, 'charge'::text, 'arrive'::text, 'livre'::text, 'annule'::text])))
);


--
-- Name: colis_natures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colis_natures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    libelle text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    prix_min_fixe double precision,
    prix_min_taux double precision,
    CONSTRAINT colis_natures_libelle_check CHECK ((btrim(libelle) <> ''::text))
);


--
-- Name: colis_natures_selectionnees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colis_natures_selectionnees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    colis_id uuid NOT NULL,
    nature_id uuid NOT NULL
);


--
-- Name: colis_numerotation_gares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colis_numerotation_gares (
    gare_id uuid NOT NULL,
    last_seq integer DEFAULT 0 NOT NULL
);


--
-- Name: Bus Bus_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Bus"
    ADD CONSTRAINT "Bus_pkey" PRIMARY KEY (id);


--
-- Name: Bus Bus_registrationNumber_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Bus"
    ADD CONSTRAINT "Bus_registrationNumber_key" UNIQUE ("registrationNumber");


--
-- Name: Cities Cities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Cities"
    ADD CONSTRAINT "Cities_pkey" PRIMARY KEY (id);


--
-- Name: ColisTrackingSubscriptions ColisTrackingSubscriptions_colisId_userId_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ColisTrackingSubscriptions"
    ADD CONSTRAINT "ColisTrackingSubscriptions_colisId_userId_key" UNIQUE ("colisId", "userId");


--
-- Name: ColisTrackingSubscriptions ColisTrackingSubscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ColisTrackingSubscriptions"
    ADD CONSTRAINT "ColisTrackingSubscriptions_pkey" PRIMARY KEY (id);


--
-- Name: Companies Companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Companies"
    ADD CONSTRAINT "Companies_pkey" PRIMARY KEY (id);


--
-- Name: CompanyExpenseCategory CompanyExpenseCategory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CompanyExpenseCategory"
    ADD CONSTRAINT "CompanyExpenseCategory_pkey" PRIMARY KEY (id);


--
-- Name: CompanyFeatureModules CompanyFeatureModules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CompanyFeatureModules"
    ADD CONSTRAINT "CompanyFeatureModules_pkey" PRIMARY KEY ("companyId");


--
-- Name: ContactSettings ContactSettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ContactSettings"
    ADD CONSTRAINT "ContactSettings_pkey" PRIMARY KEY (id);


--
-- Name: Countries Countries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Countries"
    ADD CONSTRAINT "Countries_pkey" PRIMARY KEY (id);


--
-- Name: DeviceTokens DeviceTokens_fcmToken_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DeviceTokens"
    ADD CONSTRAINT "DeviceTokens_fcmToken_key" UNIQUE ("fcmToken");


--
-- Name: DeviceTokens DeviceTokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DeviceTokens"
    ADD CONSTRAINT "DeviceTokens_pkey" PRIMARY KEY (id);


--
-- Name: Gares Gares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Gares"
    ADD CONSTRAINT "Gares_pkey" PRIMARY KEY (id);


--
-- Name: Notifications Notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Notifications"
    ADD CONSTRAINT "Notifications_pkey" PRIMARY KEY (id);


--
-- Name: Role Role_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Role"
    ADD CONSTRAINT "Role_name_key" UNIQUE (name);


--
-- Name: Role Role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Role"
    ADD CONSTRAINT "Role_pkey" PRIMARY KEY (id);


--
-- Name: UserRoles UserRoles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserRoles"
    ADD CONSTRAINT "UserRoles_pkey" PRIMARY KEY (id);


--
-- Name: Users Users_auth_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_auth_user_id_key" UNIQUE (auth_user_id);


--
-- Name: Users Users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_email_key" UNIQUE (email);


--
-- Name: Users Users_phone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_phone_key" UNIQUE (phone);


--
-- Name: Users Users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_pkey" PRIMARY KEY (id);


--
-- Name: Users Users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_username_key" UNIQUE (username);


--
-- Name: caisses_gares caisses_gares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caisses_gares
    ADD CONSTRAINT caisses_gares_pkey PRIMARY KEY (id);


--
-- Name: colis_autonomes colis_autonomes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_autonomes
    ADD CONSTRAINT colis_autonomes_pkey PRIMARY KEY (id);


--
-- Name: colis_natures colis_natures_company_libelle_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_natures
    ADD CONSTRAINT colis_natures_company_libelle_key UNIQUE (company_id, libelle);


--
-- Name: colis_natures colis_natures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_natures
    ADD CONSTRAINT colis_natures_pkey PRIMARY KEY (id);


--
-- Name: colis_natures_selectionnees colis_natures_selectionnees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_natures_selectionnees
    ADD CONSTRAINT colis_natures_selectionnees_pkey PRIMARY KEY (id);


--
-- Name: colis_natures_selectionnees colis_natures_selectionnees_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_natures_selectionnees
    ADD CONSTRAINT colis_natures_selectionnees_unique UNIQUE (colis_id, nature_id);


--
-- Name: colis_numerotation_gares colis_numerotation_gares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_numerotation_gares
    ADD CONSTRAINT colis_numerotation_gares_pkey PRIMARY KEY (gare_id);


--
-- Name: CompanyExpenseCategory company_expense_category_company_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CompanyExpenseCategory"
    ADD CONSTRAINT company_expense_category_company_name_unique UNIQUE ("companyId", name);


--
-- Name: ColisTrackingSubscriptions_colisId_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "ColisTrackingSubscriptions_colisId_idx" ON public."ColisTrackingSubscriptions" USING btree ("colisId");


--
-- Name: Companies_countryId_name_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "Companies_countryId_name_key" ON public."Companies" USING btree ("countryId", name);


--
-- Name: ContactSettings_scope_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "ContactSettings_scope_key" ON public."ContactSettings" USING btree (scope);


--
-- Name: DeviceTokens_userId_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "DeviceTokens_userId_idx" ON public."DeviceTokens" USING btree ("userId");


--
-- Name: Notifications_userId_isRead_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "Notifications_userId_isRead_idx" ON public."Notifications" USING btree ("userId", "isRead");


--
-- Name: UserRoles_company_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "UserRoles_company_unique" ON public."UserRoles" USING btree ("userId", "roleId", "companyId") WHERE ("companyId" IS NOT NULL);


--
-- Name: UserRoles_platform_country_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "UserRoles_platform_country_unique" ON public."UserRoles" USING btree ("userId", "roleId", "countryId") WHERE (("companyId" IS NULL) AND ("countryId" IS NOT NULL));


--
-- Name: UserRoles_platform_global_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "UserRoles_platform_global_unique" ON public."UserRoles" USING btree ("userId", "roleId") WHERE (("companyId" IS NULL) AND ("countryId" IS NULL));


--
-- Name: Users_referral_code_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "Users_referral_code_key" ON public."Users" USING btree ("referralCode") WHERE ("referralCode" IS NOT NULL);


--
-- Name: Users_referred_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "Users_referred_by_idx" ON public."Users" USING btree ("referredByUserId") WHERE ("referredByUserId" IS NOT NULL);


--
-- Name: caisses_gares_gare_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX caisses_gares_gare_idx ON public.caisses_gares USING btree (gare_id, opened_at DESC);


--
-- Name: caisses_gares_gestionnaire_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX caisses_gares_gestionnaire_idx ON public.caisses_gares USING btree (gestionnaire_id, opened_at DESC);


--
-- Name: caisses_gares_open_gestionnaire_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX caisses_gares_open_gestionnaire_idx ON public.caisses_gares USING btree (gestionnaire_id) WHERE (statut = 'ouverte'::text);


--
-- Name: colis_autonomes_company_statut_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colis_autonomes_company_statut_idx ON public.colis_autonomes USING btree (company_id, statut_colis, created_at DESC);


--
-- Name: colis_autonomes_numero_recu_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colis_autonomes_numero_recu_idx ON public.colis_autonomes USING btree (numero_recu);


--
-- Name: company_expense_category_company_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_expense_category_company_idx ON public."CompanyExpenseCategory" USING btree ("companyId", "sortOrder", name);


--
-- Name: company_feature_modules_updated_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_feature_modules_updated_idx ON public."CompanyFeatureModules" USING btree ("updatedAt" DESC);


--
-- Name: gares_city_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gares_city_id_idx ON public."Gares" USING btree ("cityId");


--
-- Name: idx_colis_autonomes_bus_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colis_autonomes_bus_id ON public.colis_autonomes USING btree (bus_id);


--
-- Name: user_roles_gare_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_roles_gare_id_idx ON public."UserRoles" USING btree ("gareId");


--
-- Name: colis_autonomes colis_autonomes_module_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER colis_autonomes_module_guard BEFORE INSERT ON public.colis_autonomes FOR EACH ROW EXECUTE FUNCTION public.trg_colis_autonomes_module_guard();


--
-- Name: colis_autonomes colis_numero_recu_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER colis_numero_recu_trg BEFORE INSERT ON public.colis_autonomes FOR EACH ROW EXECUTE FUNCTION public.assign_colis_numero_recu();


--
-- Name: Companies companies_seed_colis_natures; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER companies_seed_colis_natures AFTER INSERT ON public."Companies" FOR EACH ROW EXECUTE FUNCTION public.tg_seed_company_colis_natures();


--
-- Name: Companies companies_seed_expense_categories; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER companies_seed_expense_categories AFTER INSERT ON public."Companies" FOR EACH ROW EXECUTE FUNCTION public.tg_seed_company_expense_categories();


--
-- Name: CompanyExpenseCategory company_expense_category_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER company_expense_category_touch_updated_at BEFORE UPDATE ON public."CompanyExpenseCategory" FOR EACH ROW EXECUTE FUNCTION public.tg_company_expense_touch_updated_at();


--
-- Name: Gares gares_validate_city_country; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER gares_validate_city_country BEFORE INSERT OR UPDATE OF "cityId", "companyId" ON public."Gares" FOR EACH ROW EXECUTE FUNCTION public.tg_validate_gare_city_in_company_country();


--
-- Name: UserRoles trg_single_admin_pays_per_country; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_single_admin_pays_per_country BEFORE INSERT OR UPDATE OF "roleId", "countryId", "userId" ON public."UserRoles" FOR EACH ROW EXECUTE FUNCTION public.enforce_single_admin_pays_per_country();


--
-- Name: CompanyFeatureModules trg_sync_colis_module_d; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_colis_module_d AFTER INSERT OR UPDATE OF "moduleD" ON public."CompanyFeatureModules" FOR EACH ROW EXECUTE FUNCTION public.sync_colis_autonome_from_module_d();


--
-- Name: UserRoles user_roles_assignment_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER user_roles_assignment_check BEFORE INSERT OR UPDATE ON public."UserRoles" FOR EACH ROW EXECUTE FUNCTION public.validate_user_role_assignment();


--
-- Name: Bus Bus_companyId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Bus"
    ADD CONSTRAINT "Bus_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES public."Companies"(id) DEFERRABLE;


--
-- Name: Cities Cities_countryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Cities"
    ADD CONSTRAINT "Cities_countryId_fkey" FOREIGN KEY ("countryId") REFERENCES public."Countries"(id) DEFERRABLE;


--
-- Name: ColisTrackingSubscriptions ColisTrackingSubscriptions_colisId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ColisTrackingSubscriptions"
    ADD CONSTRAINT "ColisTrackingSubscriptions_colisId_fkey" FOREIGN KEY ("colisId") REFERENCES public.colis_autonomes(id) ON DELETE CASCADE;


--
-- Name: ColisTrackingSubscriptions ColisTrackingSubscriptions_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ColisTrackingSubscriptions"
    ADD CONSTRAINT "ColisTrackingSubscriptions_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."Users"(id) ON DELETE CASCADE;


--
-- Name: Companies Companies_countryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Companies"
    ADD CONSTRAINT "Companies_countryId_fkey" FOREIGN KEY ("countryId") REFERENCES public."Countries"(id) DEFERRABLE;


--
-- Name: Companies Companies_liveAuthorizedBy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Companies"
    ADD CONSTRAINT "Companies_liveAuthorizedBy_fkey" FOREIGN KEY ("liveAuthorizedBy") REFERENCES public."Users"(id) ON DELETE SET NULL;


--
-- Name: Companies Companies_ownerContractAcceptedBy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Companies"
    ADD CONSTRAINT "Companies_ownerContractAcceptedBy_fkey" FOREIGN KEY ("ownerContractAcceptedBy") REFERENCES public."Users"(id) ON DELETE SET NULL;


--
-- Name: Companies Companies_recruitedByUserId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Companies"
    ADD CONSTRAINT "Companies_recruitedByUserId_fkey" FOREIGN KEY ("recruitedByUserId") REFERENCES public."Users"(id) DEFERRABLE;


--
-- Name: CompanyExpenseCategory CompanyExpenseCategory_companyId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CompanyExpenseCategory"
    ADD CONSTRAINT "CompanyExpenseCategory_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES public."Companies"(id) ON DELETE CASCADE;


--
-- Name: CompanyFeatureModules CompanyFeatureModules_companyId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CompanyFeatureModules"
    ADD CONSTRAINT "CompanyFeatureModules_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES public."Companies"(id) ON DELETE CASCADE;


--
-- Name: CompanyFeatureModules CompanyFeatureModules_updatedBy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CompanyFeatureModules"
    ADD CONSTRAINT "CompanyFeatureModules_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES public."Users"(id);


--
-- Name: ContactSettings ContactSettings_updatedBy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ContactSettings"
    ADD CONSTRAINT "ContactSettings_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES public."Users"(id) ON DELETE SET NULL;


--
-- Name: DeviceTokens DeviceTokens_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DeviceTokens"
    ADD CONSTRAINT "DeviceTokens_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."Users"(id) ON DELETE CASCADE;


--
-- Name: Gares Gares_cityId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Gares"
    ADD CONSTRAINT "Gares_cityId_fkey" FOREIGN KEY ("cityId") REFERENCES public."Cities"(id);


--
-- Name: Gares Gares_companyId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Gares"
    ADD CONSTRAINT "Gares_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES public."Companies"(id) DEFERRABLE;


--
-- Name: Gares Gares_gestionnaireUserId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Gares"
    ADD CONSTRAINT "Gares_gestionnaireUserId_fkey" FOREIGN KEY ("gestionnaireUserId") REFERENCES public."Users"(id) ON DELETE SET NULL;


--
-- Name: Notifications Notifications_relatedReservationBusId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Notifications"
    ADD CONSTRAINT "Notifications_relatedReservationBusId_fkey" FOREIGN KEY ("relatedReservationBusId") REFERENCES public."ReservationBus"(id) DEFERRABLE;


--
-- Name: Notifications Notifications_relatedReservationId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Notifications"
    ADD CONSTRAINT "Notifications_relatedReservationId_fkey" FOREIGN KEY ("relatedReservationId") REFERENCES public."Reservations"(id) DEFERRABLE;


--
-- Name: Notifications Notifications_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Notifications"
    ADD CONSTRAINT "Notifications_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."Users"(id) DEFERRABLE;


--
-- Name: UserRoles UserRoles_assignedBy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserRoles"
    ADD CONSTRAINT "UserRoles_assignedBy_fkey" FOREIGN KEY ("assignedBy") REFERENCES public."Users"(id) DEFERRABLE;


--
-- Name: UserRoles UserRoles_companyId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserRoles"
    ADD CONSTRAINT "UserRoles_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES public."Companies"(id) DEFERRABLE;


--
-- Name: UserRoles UserRoles_countryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserRoles"
    ADD CONSTRAINT "UserRoles_countryId_fkey" FOREIGN KEY ("countryId") REFERENCES public."Countries"(id) DEFERRABLE;


--
-- Name: UserRoles UserRoles_gareId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserRoles"
    ADD CONSTRAINT "UserRoles_gareId_fkey" FOREIGN KEY ("gareId") REFERENCES public."Gares"(id) ON DELETE CASCADE;


--
-- Name: UserRoles UserRoles_roleId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserRoles"
    ADD CONSTRAINT "UserRoles_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES public."Role"(id) DEFERRABLE;


--
-- Name: UserRoles UserRoles_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserRoles"
    ADD CONSTRAINT "UserRoles_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."Users"(id) DEFERRABLE;


--
-- Name: Users Users_activeOwnerCompanyId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_activeOwnerCompanyId_fkey" FOREIGN KEY ("activeOwnerCompanyId") REFERENCES public."Companies"(id) ON DELETE SET NULL;


--
-- Name: Users Users_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id);


--
-- Name: Users Users_countryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_countryId_fkey" FOREIGN KEY ("countryId") REFERENCES public."Countries"(id) DEFERRABLE;


--
-- Name: Users Users_referredByUserId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_referredByUserId_fkey" FOREIGN KEY ("referredByUserId") REFERENCES public."Users"(id) ON DELETE SET NULL;


--
-- Name: caisses_gares caisses_gares_gare_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caisses_gares
    ADD CONSTRAINT caisses_gares_gare_id_fkey FOREIGN KEY (gare_id) REFERENCES public."Gares"(id) ON DELETE RESTRICT;


--
-- Name: caisses_gares caisses_gares_gestionnaire_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caisses_gares
    ADD CONSTRAINT caisses_gares_gestionnaire_id_fkey FOREIGN KEY (gestionnaire_id) REFERENCES public."Users"(id) ON DELETE RESTRICT;


--
-- Name: colis_autonomes colis_autonomes_annule_par_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_autonomes
    ADD CONSTRAINT colis_autonomes_annule_par_fkey FOREIGN KEY (annule_par) REFERENCES public."Users"(id);


--
-- Name: colis_autonomes colis_autonomes_bus_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_autonomes
    ADD CONSTRAINT colis_autonomes_bus_id_fkey FOREIGN KEY (bus_id) REFERENCES public."Bus"(id) ON DELETE SET NULL;


--
-- Name: colis_autonomes colis_autonomes_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_autonomes
    ADD CONSTRAINT colis_autonomes_company_id_fkey FOREIGN KEY (company_id) REFERENCES public."Companies"(id) ON DELETE CASCADE;


--
-- Name: colis_autonomes colis_autonomes_gare_depart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_autonomes
    ADD CONSTRAINT colis_autonomes_gare_depart_id_fkey FOREIGN KEY (gare_depart_id) REFERENCES public."Gares"(id);


--
-- Name: colis_autonomes colis_autonomes_gare_destination_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_autonomes
    ADD CONSTRAINT colis_autonomes_gare_destination_id_fkey FOREIGN KEY (gare_destination_id) REFERENCES public."Gares"(id);


--
-- Name: colis_autonomes colis_autonomes_vendeur_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_autonomes
    ADD CONSTRAINT colis_autonomes_vendeur_id_fkey FOREIGN KEY (vendeur_id) REFERENCES public."Users"(id);


--
-- Name: colis_natures colis_natures_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_natures
    ADD CONSTRAINT colis_natures_company_id_fkey FOREIGN KEY (company_id) REFERENCES public."Companies"(id) ON DELETE CASCADE;


--
-- Name: colis_natures_selectionnees colis_natures_selectionnees_colis_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_natures_selectionnees
    ADD CONSTRAINT colis_natures_selectionnees_colis_id_fkey FOREIGN KEY (colis_id) REFERENCES public.colis_autonomes(id) ON DELETE CASCADE;


--
-- Name: colis_natures_selectionnees colis_natures_selectionnees_nature_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_natures_selectionnees
    ADD CONSTRAINT colis_natures_selectionnees_nature_id_fkey FOREIGN KEY (nature_id) REFERENCES public.colis_natures(id) ON DELETE RESTRICT;


--
-- Name: colis_numerotation_gares colis_numerotation_gares_gare_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colis_numerotation_gares
    ADD CONSTRAINT colis_numerotation_gares_gare_id_fkey FOREIGN KEY (gare_id) REFERENCES public."Gares"(id) ON DELETE CASCADE;


--
-- Name: Bus; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Bus" ENABLE ROW LEVEL SECURITY;

--
-- Name: Cities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Cities" ENABLE ROW LEVEL SECURITY;

--
-- Name: ColisTrackingSubscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."ColisTrackingSubscriptions" ENABLE ROW LEVEL SECURITY;

--
-- Name: ColisTrackingSubscriptions ColisTrackingSubscriptions_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ColisTrackingSubscriptions_delete_own" ON public."ColisTrackingSubscriptions" FOR DELETE USING (("userId" IN ( SELECT "Users".id
   FROM public."Users"
  WHERE ("Users".auth_user_id = auth.uid()))));


--
-- Name: ColisTrackingSubscriptions ColisTrackingSubscriptions_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ColisTrackingSubscriptions_insert_own" ON public."ColisTrackingSubscriptions" FOR INSERT WITH CHECK (("userId" IN ( SELECT "Users".id
   FROM public."Users"
  WHERE ("Users".auth_user_id = auth.uid()))));


--
-- Name: ColisTrackingSubscriptions ColisTrackingSubscriptions_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ColisTrackingSubscriptions_select_own" ON public."ColisTrackingSubscriptions" FOR SELECT USING (("userId" IN ( SELECT "Users".id
   FROM public."Users"
  WHERE ("Users".auth_user_id = auth.uid()))));


--
-- Name: Companies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Companies" ENABLE ROW LEVEL SECURITY;

--
-- Name: CompanyExpenseCategory; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."CompanyExpenseCategory" ENABLE ROW LEVEL SECURITY;

--
-- Name: CompanyFeatureModules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."CompanyFeatureModules" ENABLE ROW LEVEL SECURITY;

--
-- Name: ContactSettings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."ContactSettings" ENABLE ROW LEVEL SECURITY;

--
-- Name: Countries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Countries" ENABLE ROW LEVEL SECURITY;

--
-- Name: DeviceTokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."DeviceTokens" ENABLE ROW LEVEL SECURITY;

--
-- Name: DeviceTokens DeviceTokens_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "DeviceTokens_delete_own" ON public."DeviceTokens" FOR DELETE USING (("userId" IN ( SELECT "Users".id
   FROM public."Users"
  WHERE ("Users".auth_user_id = auth.uid()))));


--
-- Name: DeviceTokens DeviceTokens_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "DeviceTokens_select_own" ON public."DeviceTokens" FOR SELECT USING (("userId" IN ( SELECT "Users".id
   FROM public."Users"
  WHERE ("Users".auth_user_id = auth.uid()))));


--
-- Name: DeviceTokens DeviceTokens_upsert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "DeviceTokens_upsert_own" ON public."DeviceTokens" FOR INSERT WITH CHECK (("userId" IN ( SELECT "Users".id
   FROM public."Users"
  WHERE ("Users".auth_user_id = auth.uid()))));


--
-- Name: Gares; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Gares" ENABLE ROW LEVEL SECURITY;

--
-- Name: Notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Notifications" ENABLE ROW LEVEL SECURITY;

--
-- Name: Role; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Role" ENABLE ROW LEVEL SECURITY;

--
-- Name: UserRoles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."UserRoles" ENABLE ROW LEVEL SECURITY;

--
-- Name: Users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."Users" ENABLE ROW LEVEL SECURITY;

--
-- Name: Bus bus_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bus_select ON public."Bus" FOR SELECT TO authenticated, anon USING (((EXISTS ( SELECT 1
   FROM public."Companies" c
  WHERE ((c.id = "Bus"."companyId") AND (c."isActive" = true)))) OR public.is_super_admin() OR public.is_company_staff("companyId")));


--
-- Name: Bus bus_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bus_write ON public."Bus" TO authenticated USING ((public.has_company_droit("companyId", 'manage_buses'::text) OR public.is_super_admin())) WITH CHECK ((public.has_company_droit("companyId", 'manage_buses'::text) OR public.is_super_admin()));


--
-- Name: caisses_gares; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caisses_gares ENABLE ROW LEVEL SECURITY;

--
-- Name: caisses_gares caisses_gares_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caisses_gares_select ON public.caisses_gares FOR SELECT TO authenticated USING ((public.is_super_admin() OR (gestionnaire_id = public.current_app_user_id()) OR public.can_validate_station_reversal(public.station_cash_gare_company_id(gare_id)) OR public.can_operate_station_cash(public.station_cash_gare_company_id(gare_id))));


--
-- Name: Cities cities_select_public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cities_select_public ON public."Cities" FOR SELECT TO authenticated, anon USING (true);


--
-- Name: Cities cities_write_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cities_write_admin ON public."Cities" USING (public.has_country_droit("countryId", 'manage_geography'::text)) WITH CHECK (public.has_country_droit("countryId", 'manage_geography'::text));


--
-- Name: colis_autonomes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colis_autonomes ENABLE ROW LEVEL SECURITY;

--
-- Name: colis_autonomes colis_autonomes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colis_autonomes_select ON public.colis_autonomes FOR SELECT TO authenticated USING ((public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin() OR public.has_gare_colis_access(public.current_app_user_id(), company_id, gare_depart_id, gare_destination_id)));


--
-- Name: colis_autonomes colis_autonomes_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colis_autonomes_write ON public.colis_autonomes TO authenticated USING ((public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin())) WITH CHECK ((public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin()));


--
-- Name: colis_natures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colis_natures ENABLE ROW LEVEL SECURITY;

--
-- Name: colis_natures colis_natures_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colis_natures_select ON public.colis_natures FOR SELECT TO authenticated USING ((public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin()));


--
-- Name: colis_natures_selectionnees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colis_natures_selectionnees ENABLE ROW LEVEL SECURITY;

--
-- Name: colis_natures_selectionnees colis_natures_selectionnees_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colis_natures_selectionnees_select ON public.colis_natures_selectionnees FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.colis_autonomes ca
  WHERE ((ca.id = colis_natures_selectionnees.colis_id) AND (public.is_company_role_user(public.current_app_user_id(), ca.company_id) OR public.is_super_admin())))));


--
-- Name: colis_natures_selectionnees colis_natures_selectionnees_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colis_natures_selectionnees_write ON public.colis_natures_selectionnees TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.colis_autonomes ca
  WHERE ((ca.id = colis_natures_selectionnees.colis_id) AND (public.is_company_role_user(public.current_app_user_id(), ca.company_id) OR public.is_super_admin()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.colis_autonomes ca
  WHERE ((ca.id = colis_natures_selectionnees.colis_id) AND (public.is_company_role_user(public.current_app_user_id(), ca.company_id) OR public.is_super_admin())))));


--
-- Name: colis_natures colis_natures_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colis_natures_write ON public.colis_natures TO authenticated USING ((public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin())) WITH CHECK ((public.is_company_role_user(public.current_app_user_id(), company_id) OR public.is_super_admin()));


--
-- Name: colis_numerotation_gares; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colis_numerotation_gares ENABLE ROW LEVEL SECURITY;

--
-- Name: Companies companies_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_delete ON public."Companies" FOR DELETE TO authenticated USING (public.is_super_admin());


--
-- Name: Companies companies_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_insert ON public."Companies" FOR INSERT TO authenticated WITH CHECK ((public.is_super_admin() OR public.has_country_role("countryId", ARRAY['admin_pays'::text])));


--
-- Name: Companies companies_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_select ON public."Companies" FOR SELECT TO authenticated, anon USING ((("isActive" = true) OR public.is_super_admin() OR public.is_company_staff(id) OR public.has_country_role("countryId", ARRAY['admin_pays'::text])));


--
-- Name: Companies companies_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY companies_update ON public."Companies" FOR UPDATE TO authenticated USING ((public.has_company_droit(id, 'manage_company'::text) OR public.is_super_admin())) WITH CHECK ((public.has_company_droit(id, 'manage_company'::text) OR public.is_super_admin()));


--
-- Name: CompanyFeatureModules company_feature_modules_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY company_feature_modules_read ON public."CompanyFeatureModules" FOR SELECT USING ((public.is_super_admin() OR public.has_company_role("companyId", ARRAY['owner'::text, 'comptable_compagnie'::text]) OR (EXISTS ( SELECT 1
   FROM public."Companies" c
  WHERE ((c.id = "CompanyFeatureModules"."companyId") AND public.has_country_role(c."countryId", ARRAY['admin_pays'::text]))))));


--
-- Name: CompanyFeatureModules company_feature_modules_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY company_feature_modules_write ON public."CompanyFeatureModules" USING (public.has_company_droit("companyId", 'manage_feature_modules'::text)) WITH CHECK (public.has_company_droit("companyId", 'manage_feature_modules'::text));


--
-- Name: ContactSettings contact_settings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contact_settings_select ON public."ContactSettings" FOR SELECT TO authenticated, anon USING (true);


--
-- Name: Countries countries_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY countries_delete_admin ON public."Countries" FOR DELETE TO authenticated USING (public.is_super_admin());


--
-- Name: Countries countries_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY countries_insert_admin ON public."Countries" FOR INSERT TO authenticated WITH CHECK (public.is_super_admin());


--
-- Name: Countries countries_select_public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY countries_select_public ON public."Countries" FOR SELECT TO authenticated, anon USING (true);


--
-- Name: Countries countries_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY countries_update_admin ON public."Countries" FOR UPDATE TO authenticated USING ((public.is_super_admin() OR public.has_country_role(id, ARRAY['admin_pays'::text]))) WITH CHECK ((public.is_super_admin() OR public.has_country_role(id, ARRAY['admin_pays'::text])));


--
-- Name: Gares gares_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gares_select ON public."Gares" FOR SELECT TO authenticated, anon USING (((EXISTS ( SELECT 1
   FROM public."Companies" c
  WHERE ((c.id = "Gares"."companyId") AND (c."isActive" = true)))) OR public.is_super_admin() OR public.is_company_staff("companyId")));


--
-- Name: Gares gares_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gares_write ON public."Gares" TO authenticated USING ((public.has_company_droit("companyId", 'manage_stations'::text) OR public.is_super_admin())) WITH CHECK ((public.has_company_droit("companyId", 'manage_stations'::text) OR public.is_super_admin()));


--
-- Name: Notifications notifications_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_insert ON public."Notifications" FOR INSERT TO authenticated WITH CHECK ((public.is_super_admin() OR ("userId" = public.current_app_user_id()) OR public.has_global_droit('manage_platform'::text)));


--
-- Name: Notifications notifications_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_select ON public."Notifications" FOR SELECT TO authenticated USING ((public.is_super_admin() OR ("userId" = public.current_app_user_id())));


--
-- Name: Notifications notifications_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_update ON public."Notifications" FOR UPDATE TO authenticated USING ((public.is_super_admin() OR ("userId" = public.current_app_user_id()))) WITH CHECK ((public.is_super_admin() OR ("userId" = public.current_app_user_id())));


--
-- Name: Role role_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_select_authenticated ON public."Role" FOR SELECT TO authenticated USING (true);


--
-- Name: Role role_write_super_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_write_super_admin ON public."Role" TO authenticated USING ((public.is_super_admin() OR public.has_global_droit('manage_roles'::text))) WITH CHECK ((public.is_super_admin() OR public.has_global_droit('manage_roles'::text)));


--
-- Name: UserRoles userroles_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY userroles_delete ON public."UserRoles" FOR DELETE TO authenticated USING ((public.is_super_admin() OR public.can_assign_role("roleId", "companyId")));


--
-- Name: UserRoles userroles_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY userroles_insert ON public."UserRoles" FOR INSERT TO authenticated WITH CHECK ((public.is_super_admin() OR (("userId" = public.current_app_user_id()) AND ("companyId" IS NULL) AND ("countryId" IS NULL) AND (EXISTS ( SELECT 1
   FROM public."Role" r
  WHERE ((r.id = "UserRoles"."roleId") AND ((r.name)::text = 'traveler'::text))))) OR (("userId" = public.current_app_user_id()) AND ("companyId" IS NULL) AND ("countryId" IS NULL) AND (NOT public.is_in_master_network()) AND (EXISTS ( SELECT 1
   FROM public."Role" r
  WHERE ((r.id = "UserRoles"."roleId") AND ((r.name)::text = 'vendeur_independant'::text))))) OR public.can_assign_role("roleId", "companyId")));


--
-- Name: UserRoles userroles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY userroles_select ON public."UserRoles" FOR SELECT TO authenticated USING ((public.is_super_admin() OR ("userId" = public.current_app_user_id()) OR public.is_company_staff("companyId") OR public.has_global_droit('manage_platform'::text)));


--
-- Name: UserRoles userroles_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY userroles_update ON public."UserRoles" FOR UPDATE TO authenticated USING ((public.is_super_admin() OR public.can_assign_role("roleId", "companyId"))) WITH CHECK ((public.is_super_admin() OR public.can_assign_role("roleId", "companyId")));


--
-- Name: Users users_insert_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_insert_self ON public."Users" FOR INSERT TO authenticated WITH CHECK ((auth_user_id = auth.uid()));


--
-- Name: Users users_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_select ON public."Users" FOR SELECT TO authenticated USING (((auth_user_id = auth.uid()) OR public.is_super_admin() OR public.has_global_droit('manage_platform'::text) OR (EXISTS ( SELECT 1
   FROM ((public."UserRoles" ur_me
     JOIN public."UserRoles" ur_them ON ((ur_them."companyId" = ur_me."companyId")))
     JOIN public."Role" r ON ((r.id = ur_me."roleId")))
  WHERE ((ur_me."userId" = public.current_app_user_id()) AND (ur_them."userId" = "Users".id) AND (ur_me."companyId" IS NOT NULL) AND ((r.name)::text = 'owner'::text))))));


--
-- Name: Users users_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_update ON public."Users" FOR UPDATE TO authenticated USING (((auth_user_id = auth.uid()) OR public.is_super_admin())) WITH CHECK (((auth_user_id = auth.uid()) OR public.is_super_admin()));


--
-- PostgreSQL database dump complete
--

\unrestrict 87kobLgFsaA4L3pwhdubygoDFCKSLyqom6wRg1dDkcB4dEmqD5PGfVxVqGbmUaG

