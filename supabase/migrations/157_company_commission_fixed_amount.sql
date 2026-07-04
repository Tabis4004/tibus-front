-- 157_company_commission_fixed_amount.sql
--
-- Ajoute le support d'une commission "montant fixe" (en plus du pourcentage)
-- pour les réglages de commission par compagnie (scope = 'company').
--
-- Décision explicite : les commissions par PAYS restent uniquement en
-- pourcentage et ne sont pas branchées sur le calcul réel (comportement
-- préexistant, inchangé). Seul le scope "company" gagne le montant fixe.
--
-- Backfill de changements déjà appliqués en direct sur la base via le MCP
-- Supabase (apply_migration), afin de garder l'historique des migrations
-- aligné avec le schéma réel.

-- ─── Schéma ──────────────────────────────────────────────────────────────

alter table "CommissionSettings"
  add column if not exists "amountType" text not null default 'percentage',
  add column if not exists "fixedAmount" double precision not null default 0;

alter table "CommissionSettings"
  drop constraint if exists "CommissionSettings_amountType_check";
alter table "CommissionSettings"
  add constraint "CommissionSettings_amountType_check"
  check ("amountType" in ('percentage', 'fixed'));

alter table "CommissionSettings"
  drop constraint if exists "CommissionSettings_fixedAmount_check";
alter table "CommissionSettings"
  add constraint "CommissionSettings_fixedAmount_check"
  check ("fixedAmount" >= 0);

-- Trace d'audit sur la réservation : quel type de commission a été appliqué
-- au moment de la capture.
alter table "ReservationBus"
  add column if not exists "platformCommissionAmountType" text;

-- ─── Fonctions ───────────────────────────────────────────────────────────

-- upsert_commission_setting appelle list_commission_settings ; on doit donc
-- supprimer dans le bon ordre (dépendant d'abord) avant de recréer, car le
-- type de retour des deux fonctions change.
drop function if exists public.upsert_commission_setting(text, uuid, uuid, double precision, text, boolean);
drop function if exists public.list_commission_settings();

create or replace function public.list_commission_settings()
returns table(
  id uuid,
  scope text,
  country_id uuid,
  country_name text,
  company_id uuid,
  company_name text,
  rate double precision,
  paid_by text,
  is_active boolean,
  amount_type text,
  fixed_amount double precision,
  source text,
  updated_at timestamptz,
  updated_by_name text
)
language sql
stable security definer
set search_path to 'public'
as $function$
  with allowed_countries as (
    select c.id, c.name::text as name
    from "Countries" c
    where public.can_manage_commission_country(c.id)
  ),
  country_rows as (
    select
      s.id,
      'country'::text as scope,
      ac.id as country_id,
      ac.name as country_name,
      null::uuid as company_id,
      null::text as company_name,
      coalesce(s.rate, 0) as rate,
      coalesce(s."paidBy", 'company') as paid_by,
      coalesce(s."isActive", false) as is_active,
      'percentage'::text as amount_type,
      0::double precision as fixed_amount,
      case when s.id is null then 'unset' else 'configured' end as source,
      s."updatedAt" as updated_at,
      nullif(trim(coalesce(u."firstName", '') || ' ' || coalesce(u."lastName", '')), '') as updated_by_name
    from allowed_countries ac
    left join lateral (
      select *
      from "CommissionSettings" cs
      where cs."scope" = 'country'
        and cs."countryId" = ac.id
      order by cs."isActive" desc, cs."updatedAt" desc
      limit 1
    ) s on true
    left join "Users" u on u.id = s."updatedBy"
  ),
  company_rows as (
    select
      s.id,
      'company'::text as scope,
      c."countryId" as country_id,
      ac.name as country_name,
      c.id as company_id,
      c.name::text as company_name,
      s.rate,
      s."paidBy" as paid_by,
      s."isActive" as is_active,
      coalesce(s."amountType", 'percentage') as amount_type,
      coalesce(s."fixedAmount", 0) as fixed_amount,
      'company_override'::text as source,
      s."updatedAt" as updated_at,
      nullif(trim(coalesce(u."firstName", '') || ' ' || coalesce(u."lastName", '')), '') as updated_by_name
    from "CommissionSettings" s
    join "Companies" c on c.id = s."companyId"
    join allowed_countries ac on ac.id = c."countryId"
    left join "Users" u on u.id = s."updatedBy"
    where s."scope" = 'company'
  )
  select * from country_rows
  union all
  select * from company_rows
  order by country_name, scope, company_name nulls first;
$function$;

create or replace function public.upsert_commission_setting(
  p_scope text,
  p_country_id uuid,
  p_company_id uuid,
  p_rate double precision,
  p_paid_by text default 'company'::text,
  p_is_active boolean default true,
  p_amount_type text default 'percentage'::text,
  p_fixed_amount double precision default 0
)
returns table(
  id uuid,
  scope text,
  country_id uuid,
  country_name text,
  company_id uuid,
  company_name text,
  rate double precision,
  paid_by text,
  is_active boolean,
  amount_type text,
  fixed_amount double precision,
  source text,
  updated_at timestamptz,
  updated_by_name text
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid;
  v_country_id uuid;
  v_existing_id uuid;
  v_amount_type text := coalesce(p_amount_type, 'percentage');
  v_fixed_amount double precision := coalesce(p_fixed_amount, 0);
begin
  v_user_id := public.current_app_user_id();
  if v_user_id is null then
    raise exception 'Utilisateur introuvable';
  end if;

  if p_scope not in ('country', 'company') then
    raise exception 'Portee commission invalide';
  end if;
  if v_amount_type not in ('percentage', 'fixed') then
    raise exception 'Type de commission invalide';
  end if;
  -- Décision produit : le scope pays reste toujours en pourcentage.
  if p_scope = 'country' then
    v_amount_type := 'percentage';
    v_fixed_amount := 0;
  end if;
  if v_amount_type = 'percentage' and (p_rate < 0 or p_rate > 100) then
    raise exception 'Le taux doit etre entre 0 et 100';
  end if;
  if v_amount_type = 'fixed' and v_fixed_amount < 0 then
    raise exception 'Le montant fixe doit etre positif ou nul';
  end if;
  if coalesce(p_paid_by, 'company') not in ('company', 'traveler') then
    raise exception 'paid_by invalide';
  end if;

  if p_scope = 'country' then
    v_country_id := p_country_id;
    if v_country_id is null then
      raise exception 'country_id requis';
    end if;
  else
    if p_company_id is null then
      raise exception 'company_id requis';
    end if;
    select c."countryId" into v_country_id
    from "Companies" c
    where c.id = p_company_id;
    if v_country_id is null then
      raise exception 'Compagnie introuvable';
    end if;
  end if;

  if not public.can_manage_commission_country(v_country_id) then
    raise exception 'Acces commission refuse';
  end if;

  select cs.id into v_existing_id
  from "CommissionSettings" cs
  where cs."scope" = p_scope
    and (
      (p_scope = 'country' and cs."countryId" = v_country_id)
      or
      (p_scope = 'company' and cs."companyId" = p_company_id)
    )
  order by cs."isActive" desc, cs."updatedAt" desc
  limit 1;

  if v_existing_id is null then
    insert into "CommissionSettings" (
      "scope", "countryId", "companyId", "rate", "paidBy", "isActive", "amountType", "fixedAmount", "updatedBy"
    )
    values (
      p_scope,
      case when p_scope = 'country' then v_country_id else null end,
      case when p_scope = 'company' then p_company_id else null end,
      p_rate,
      coalesce(p_paid_by, 'company'),
      coalesce(p_is_active, true),
      v_amount_type,
      v_fixed_amount,
      v_user_id
    )
    returning "CommissionSettings".id into v_existing_id;
  else
    update "CommissionSettings"
    set
      "countryId" = case when p_scope = 'country' then v_country_id else "CommissionSettings"."countryId" end,
      "companyId" = case when p_scope = 'company' then p_company_id else null end,
      "rate" = p_rate,
      "paidBy" = coalesce(p_paid_by, 'company'),
      "isActive" = coalesce(p_is_active, true),
      "amountType" = v_amount_type,
      "fixedAmount" = v_fixed_amount,
      "updatedAt" = now(),
      "updatedBy" = v_user_id
    where "CommissionSettings".id = v_existing_id;
  end if;

  return query
  select l.*
  from public.list_commission_settings() l
  where l.id = v_existing_id;
end;
$function$;

-- resolve_seller_commission_setting : renvoie désormais aussi amount_type
-- et fixed_amount. Priorité inchangée : réglage compagnie actif (1) >
-- champ legacy Companies.commissionRate (2) > défaut 5% (3). Les réglages
-- de scope "country" ne sont toujours pas consultés ici (décision produit).
drop function if exists public.resolve_seller_commission_setting(uuid);

create or replace function public.resolve_seller_commission_setting(p_company_id uuid)
returns table(
  setting_id uuid,
  setting_scope text,
  country_id uuid,
  company_id uuid,
  rate double precision,
  paid_by text,
  amount_type text,
  fixed_amount double precision
)
language sql
stable security definer
set search_path to 'public'
as $function$
  with company_row as (
    select c.id, c."countryId", coalesce(c."commissionRate", 0) as legacy_rate
    from public."Companies" c
    where c.id = p_company_id
  ),
  resolved as (
    select
      s.id as setting_id,
      s.scope as setting_scope,
      coalesce(s."countryId", cr."countryId") as country_id,
      s."companyId" as company_id,
      s.rate,
      s."paidBy" as paid_by,
      coalesce(s."amountType", 'percentage') as amount_type,
      coalesce(s."fixedAmount", 0) as fixed_amount,
      1 as priority
    from company_row cr
    join public."CommissionSettings" s
      on s."scope" = 'company'
     and s."companyId" = cr.id
     and s."isActive" = true
    union all
    select
      null::uuid as setting_id,
      'legacy_company'::text as setting_scope,
      cr."countryId" as country_id,
      cr.id as company_id,
      cr.legacy_rate as rate,
      'traveler'::text as paid_by,
      'percentage'::text as amount_type,
      0::double precision as fixed_amount,
      2 as priority
    from company_row cr
    union all
    select
      null::uuid as setting_id,
      'default'::text as setting_scope,
      cr."countryId" as country_id,
      null::uuid as company_id,
      5::double precision as rate,
      'traveler'::text as paid_by,
      'percentage'::text as amount_type,
      0::double precision as fixed_amount,
      3 as priority
    from company_row cr
    where cr."countryId" is not null
  )
  select
    resolved.setting_id,
    resolved.setting_scope,
    resolved.country_id,
    resolved.company_id,
    coalesce(resolved.rate, 0),
    coalesce(resolved.paid_by, 'traveler'),
    coalesce(resolved.amount_type, 'percentage'),
    coalesce(resolved.fixed_amount, 0)
  from resolved
  order by priority
  limit 1;
$function$;

-- _booking_platform_commission_amount : ajoute p_amount_type/p_fixed_amount.
-- L'ancienne surcharge à 4 arguments est supprimée explicitement (sinon
-- CREATE OR REPLACE avec des paramètres en plus crée une 2e signature au
-- lieu de remplacer la fonction).
drop function if exists public._booking_platform_commission_amount(double precision, uuid, text, double precision);

create or replace function public._booking_platform_commission_amount(
  p_nominal_amount double precision,
  p_company_id uuid,
  p_sale_channel text default 'traveler'::text,
  p_commission_rate double precision default null::double precision,
  p_amount_type text default null::text,
  p_fixed_amount double precision default null::double precision
)
returns double precision
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_margin record;
  v_rate double precision;
  v_paid_by text;
  v_channel text;
  v_amount_type text;
  v_fixed_amount double precision;
begin
  if p_nominal_amount is null or p_nominal_amount <= 0 or p_company_id is null then
    return 0;
  end if;

  v_channel := coalesce(p_sale_channel, 'traveler');
  if v_channel not in ('traveler', 'counter_sale') then
    return 0;
  end if;

  select * into v_margin from public.resolve_seller_commission_setting(p_company_id) limit 1;
  v_paid_by := coalesce(v_margin.paid_by, 'company');
  v_amount_type := coalesce(p_amount_type, v_margin.amount_type, 'percentage');
  v_rate := coalesce(p_commission_rate, v_margin.rate, 0);
  v_fixed_amount := coalesce(p_fixed_amount, v_margin.fixed_amount, 0);

  if v_amount_type = 'fixed' then
    if v_fixed_amount <= 0 then
      return 0;
    end if;
  else
    if v_rate <= 0 then
      return 0;
    end if;
  end if;

  if v_channel = 'traveler' and v_paid_by = 'traveler' then
    if v_amount_type = 'fixed' then
      return round(v_fixed_amount::numeric, 2)::double precision;
    end if;
    return round((p_nominal_amount * v_rate / 100.0)::numeric, 2)::double precision;
  end if;

  if v_channel = 'counter_sale' and v_paid_by = 'company' then
    if v_amount_type = 'fixed' then
      return round(v_fixed_amount::numeric, 2)::double precision;
    end if;
    return round((p_nominal_amount * v_rate / 100.0)::numeric, 2)::double precision;
  end if;

  return 0;
end;
$function$;

-- capture_booking_platform_commission : résout et stocke amount_type/fixed_amount.
create or replace function public.capture_booking_platform_commission(
  p_booking_id uuid,
  p_nominal_amount double precision default null::double precision,
  p_company_id uuid default null::uuid,
  p_sale_channel text default null::text,
  p_commission_rate double precision default null::double precision,
  p_traveler_paid_total double precision default null::double precision
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_booking record;
  v_company_id uuid;
  v_nominal double precision;
  v_channel text;
  v_margin record;
  v_amount double precision;
  v_paid_by text;
  v_source text;
  v_reference text;
begin
  select rb.*, g."companyId" as resolved_company_id
  into v_booking
  from "ReservationBus" rb
  join "Reservations" r on r.id = rb."reservationId"
  join "ProgrammationTrajets" pt on pt.id = r."trajetId"
  join "Gares" g on g.id = pt.depart
  where rb.id = p_booking_id;
  if not found then raise exception 'Billet introuvable'; end if;

  v_company_id := coalesce(p_company_id, v_booking.resolved_company_id);
  v_nominal := coalesce(p_nominal_amount, v_booking.price, 0);
  v_channel := coalesce(p_sale_channel, v_booking."saleChannel", 'traveler');
  select * into v_margin from public.resolve_seller_commission_setting(v_company_id) limit 1;
  v_paid_by := coalesce(v_margin.paid_by, 'company');
  v_amount := public._booking_platform_commission_amount(
    v_nominal, v_company_id, v_channel,
    coalesce(p_commission_rate, v_margin.rate),
    v_margin.amount_type,
    v_margin.fixed_amount
  );
  v_source := public._booking_platform_commission_source(v_channel, v_paid_by);

  update "ReservationBus"
  set
    "platformCommissionAmount" = v_amount,
    "platformCommissionRate" = coalesce(p_commission_rate, v_margin.rate, 0),
    "platformCommissionAmountType" = coalesce(v_margin.amount_type, 'percentage'),
    "commissionPaidBy" = v_paid_by,
    "platformCommissionSource" = case when v_amount > 0 then v_source else null end,
    "travelerPaidTotal" = coalesce(p_traveler_paid_total, "travelerPaidTotal")
  where id = p_booking_id;

  if v_amount > 0 and v_source = 'counter_company' then
    v_reference := coalesce(p_booking_id::text, p_booking_id::text);
    perform public.charge_company_counter_platform_commission(
      p_booking_id, v_company_id, v_amount, v_reference
    );
  end if;
end;
$function$;

-- calculate_traveler_payment_total : gère désormais le mode montant fixe
-- (v_x_fixed) en plus du pourcentage (v_x). Une marge % explicite passée en
-- paramètre (p_trip_margin_percent) écrase toujours le réglage compagnie,
-- même si celui-ci est configuré en montant fixe. Formule identique
-- bit-à-bit au comportement précédent quand v_x_fixed = 0.
create or replace function public.calculate_traveler_payment_total(
  p_nominal_amount double precision,
  p_company_id uuid,
  p_gateway text default 'fedapay'::text,
  p_method text default 'mobile_money'::text,
  p_network text default null::text,
  p_trip_margin_percent double precision default null::double precision,
  p_country_id uuid default null::uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_country_id uuid;
  v_country_name text;
  v_company_name text;
  v_margin record;
  v_fees record;
  v_x double precision;
  v_x_fixed double precision;
  v_amount_type text;
  v_y double precision;
  v_z double precision;
  v_f double precision;
  v_v double precision;
  v_raw double precision;
  v_total double precision;
  v_configured text;
  v_fee_mode text;
  v_is_geniuspay boolean;
  v_network_known boolean;
  v_fees_found boolean := false;
begin
  if p_nominal_amount is null or p_nominal_amount < 0 then raise exception 'Montant nominal invalide'; end if;
  if p_company_id is null then raise exception 'company_id requis'; end if;

  v_is_geniuspay := lower(trim(coalesce(p_gateway, ''))) = 'geniuspay';
  v_network_known := p_network is not null
    and trim(p_network) <> ''
    and lower(trim(p_network)) <> 'unknown';

  if p_country_id is not null then
    v_country_id := p_country_id;
    select co.name into v_country_name from "Countries" co where co.id = v_country_id;
    if v_country_name is null then
      raise exception 'Pays de paiement introuvable (countryId=%)', p_country_id;
    end if;
  else
    select c."countryId", c.name into v_country_id, v_company_name from "Companies" c where c.id = p_company_id;
    if v_country_id is null then
      raise exception 'Compagnie sans pays (countryId NULL) pour %', coalesce(v_company_name, p_company_id::text);
    end if;
    select co.name into v_country_name from "Countries" co where co.id = v_country_id;
  end if;

  select * into v_margin from public.resolve_seller_commission_setting(p_company_id) limit 1;

  -- Une marge % explicite (p_trip_margin_percent) écrase toujours le réglage
  -- compagnie, y compris s'il est configuré en montant fixe.
  if p_trip_margin_percent is not null then
    v_amount_type := 'percentage';
    v_x := p_trip_margin_percent;
    v_x_fixed := 0;
  elsif coalesce(v_margin.amount_type, 'percentage') = 'fixed' then
    v_amount_type := 'fixed';
    v_x := 0;
    v_x_fixed := coalesce(v_margin.fixed_amount, 0);
  else
    v_amount_type := 'percentage';
    v_x := coalesce(v_margin.rate, 0);
    v_x_fixed := 0;
  end if;

  v_v := p_nominal_amount * (1 + v_x / 100.0) + v_x_fixed;

  if v_is_geniuspay then
    if v_network_known then
      select * into v_fees
      from public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method, p_network)
      limit 1;
      v_fees_found := found;
    end if;

    if not v_fees_found then
      select * into v_fees
      from public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method, null)
      limit 1;
      v_fees_found := found;
    end if;

    if not v_fees_found then
      select string_agg(lower(gpf.gateway)||'/'||lower(gpf.method)||'/'||lower(gpf.network), ', ')
      into v_configured from "GatewayPaymentFees" gpf where gpf."countryId" = v_country_id;
      raise exception 'Configuration frais gateway manquante pour gateway=% pays=% methode=% reseau=%. Config: %',
        lower(p_gateway), coalesce(v_country_name,'?'), lower(p_method), lower(coalesce(p_network,'max')), coalesce(v_configured,'aucune');
    end if;

    v_z := coalesce(v_fees.z_percent, 0);
    v_f := coalesce(v_fees.f_fixed, 0);
    v_y := coalesce(v_fees.y_percent, 0);

    v_raw := p_nominal_amount * (1 + (v_x + v_y + v_z) / 100.0) + v_f + v_x_fixed;
    v_total := ceil(v_raw);
    v_fee_mode := 'additive';

    return jsonb_build_object(
      'nominalAmount', p_nominal_amount,
      'platformMarginPercent', v_x,
      'platformMarginFixed', v_x_fixed,
      'marginAmountType', v_amount_type,
      'platformNetAmount', v_v,
      'gatewayFeePercent', v_y,
      'geniusPayFeePercent', v_z,
      'fixedFee', v_f,
      'rawTotalAmount', v_raw,
      'totalAmount', v_total,
      'gatewayAmount', v_total,
      'feeMode', v_fee_mode,
      'feesDeferredToGateway', false,
      'networkFeeDeferred', false,
      'paidBy', coalesce(v_margin.paid_by, 'company'),
      'marginScope', coalesce(v_margin.setting_scope, 'unset'),
      'gateway', lower(p_gateway),
      'method', lower(v_fees.method),
      'network', lower(v_fees.network),
      'requestedNetwork', lower(coalesce(nullif(trim(p_network), ''), 'unknown')),
      'usedMaxFallback', case when v_network_known then coalesce(v_fees.used_max_fallback, false) else true end,
      'countryId', v_country_id,
      'countryName', v_country_name
    );
  end if;

  select * into v_fees
  from public.resolve_gateway_payment_fee(p_gateway, v_country_id, p_method, p_network)
  limit 1;

  if not found then
    select string_agg(lower(gpf.gateway)||'/'||lower(gpf.method)||'/'||lower(gpf.network), ', ')
    into v_configured from "GatewayPaymentFees" gpf where gpf."countryId" = v_country_id;
    raise exception 'Configuration frais gateway manquante pour gateway=% pays=% methode=% reseau=%. Config: %',
      lower(p_gateway), coalesce(v_country_name,'?'), lower(p_method), lower(coalesce(p_network,'max')), coalesce(v_configured,'aucune');
  end if;

  v_z := coalesce(v_fees.z_percent, 0);
  v_f := coalesce(v_fees.f_fixed, 0);
  v_y := coalesce(v_fees.y_percent, 0);

  v_fee_mode := case
    when lower(trim(p_gateway)) = 'fedapay' then 'on_top'
    else 'deducted'
  end;

  if v_fee_mode = 'on_top' then
    v_raw := v_v * (1 + (v_y + v_z) / 100.0) + v_f;
  else
    if (v_y + v_z) >= 100 then raise exception 'Taux gateway invalides: Y+Z >= 100%%'; end if;
    v_raw := (v_v + v_f) / (1 - (v_y + v_z) / 100.0);
  end if;

  v_total := ceil(v_raw);

  return jsonb_build_object(
    'nominalAmount', p_nominal_amount,
    'platformMarginPercent', v_x,
    'platformMarginFixed', v_x_fixed,
    'marginAmountType', v_amount_type,
    'platformNetAmount', v_v,
    'gatewayFeePercent', v_y,
    'geniusPayFeePercent', v_z,
    'fixedFee', v_f,
    'rawTotalAmount', v_raw,
    'totalAmount', v_total,
    'gatewayAmount', case when v_fee_mode = 'on_top' then ceil(v_v) else v_total end,
    'feeMode', v_fee_mode,
    'feesDeferredToGateway', false,
    'paidBy', coalesce(v_margin.paid_by, 'company'),
    'marginScope', coalesce(v_margin.setting_scope, 'unset'),
    'gateway', lower(p_gateway),
    'method', lower(v_fees.method),
    'network', lower(v_fees.network),
    'requestedNetwork', lower(coalesce(nullif(trim(p_network), ''), 'unknown')),
    'usedMaxFallback', coalesce(v_fees.used_max_fallback, false),
    'countryId', v_country_id,
    'countryName', v_country_name
  );
end;
$function$;
