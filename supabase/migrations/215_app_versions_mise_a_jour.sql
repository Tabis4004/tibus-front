-- 215 — Registre central des versions des apps mobiles (pop-up de mise à jour)
--
-- Une ligne par app publiée (applicationId Android / bundle id iOS) et par
-- plateforme. L'app compare son propre versionCode à ces valeurs au démarrage :
--   version < min_version_code     -> mise à jour OBLIGATOIRE (pop-up bloquant)
--   version < latest_version_code  -> mise à jour proposée ("Plus tard" possible)
--
-- Vit dans Tibus 1.0 même pour les marques qui ont leur propre base (SIS,
-- base.societe-sis.com) : c'est l'éditeur qui publie les apps, donc c'est lui
-- qui tient le registre. courrier_mobile l'interroge avec un client dédié
-- pointé sur Tibus 1.0, indépendant de la base métier de la marque.
--
-- IMPORTANT : ne relever latest_version_code qu'une fois la version
-- effectivement disponible sur le store (déploiement Play terminé), sinon le
-- pop-up envoie l'utilisateur vers une fiche qui ne propose encore rien.

create table if not exists public.app_versions (
  app_id              text        not null,
  platform            text        not null check (platform in ('android', 'ios', 'windows')),
  latest_version_code integer     not null check (latest_version_code > 0),
  latest_version_name text,
  min_version_code    integer     not null default 0 check (min_version_code >= 0),
  store_url           text,
  message             text,
  updated_at          timestamptz not null default now(),
  primary key (app_id, platform),
  constraint app_versions_min_le_latest check (min_version_code <= latest_version_code)
);

comment on table public.app_versions is
  'Registre des versions publiées des apps mobiles — lu au démarrage pour proposer/imposer la mise à jour (migration 215).';

alter table public.app_versions enable row level security;

-- Lecture publique : l'info est publique (c''est ce que montre le store) et
-- la vérification doit marcher avant la connexion.
drop policy if exists app_versions_read on public.app_versions;
create policy app_versions_read on public.app_versions
  for select to anon, authenticated using (true);

-- Écriture : super_admin uniquement (ou service_role, qui contourne RLS).
drop policy if exists app_versions_write on public.app_versions;
create policy app_versions_write on public.app_versions
  for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

create or replace function public.app_versions_touch()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists app_versions_touch on public.app_versions;
create trigger app_versions_touch before update on public.app_versions
  for each row execute function public.app_versions_touch();

-- Point d'entrée unique de l'app : renvoie la décision toute faite.
-- update_status : 'none' | 'optional' | 'required'
create or replace function public.get_app_update(
  p_app_id text, p_platform text, p_version_code integer)
returns table (
  update_status       text,
  latest_version_code integer,
  latest_version_name text,
  min_version_code    integer,
  store_url           text,
  message             text)
language sql stable security invoker set search_path = public as $$
  select
    case
      when p_version_code < v.min_version_code    then 'required'
      when p_version_code < v.latest_version_code then 'optional'
      else 'none'
    end,
    v.latest_version_code, v.latest_version_name, v.min_version_code,
    coalesce(v.store_url,
      case when v.platform = 'android'
           then 'https://play.google.com/store/apps/details?id=' || v.app_id end),
    v.message
  from public.app_versions v
  where v.app_id = p_app_id and v.platform = p_platform;
$$;

grant select on public.app_versions to anon, authenticated;
grant execute on function public.get_app_update(text, text, integer) to anon, authenticated;

-- SIS Courrier : version 9 actuellement en production sur le Play Store.
insert into public.app_versions (app_id, platform, latest_version_code, latest_version_name, min_version_code)
values ('com.sis.courrier', 'android', 9, '0.1.0', 0)
on conflict (app_id, platform) do nothing;
