begin;

create table if not exists ranking.observation_provider_links(
  observation_id uuid not null references ranking.observations(id) on delete cascade,
  provider_id uuid not null references catalogue.providers(id) on delete restrict,
  link_method text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key(observation_id,provider_id)
);
create index if not exists ranking_observation_provider_links_provider_idx
  on ranking.observation_provider_links(provider_id,observation_id);
alter table ranking.observation_provider_links enable row level security;
revoke all on ranking.observation_provider_links from public,anon,authenticated;
grant select,insert,update,delete on ranking.observation_provider_links to service_role;

create or replace function public.svc_statistical_equivalent_provider_ids(p_provider_id uuid)
returns uuid[]
language sql stable security definer
set search_path to 'pg_catalog','catalogue','public'
as $$
with seed as (
  select p.id,p.country_id,
    lower(regexp_replace(coalesce(p.display_name,p.canonical_name),'[^a-z0-9]+','','g')) norm_name
  from catalogue.providers p where p.id=p_provider_id
), same_identifier as (
  select distinct pi2.provider_id id
  from catalogue.provider_identifiers pi1
  join catalogue.provider_identifiers pi2
    on lower(pi2.scheme)=lower(pi1.scheme)
   and lower(pi2.identifier)=lower(pi1.identifier)
   and pi2.valid_to is null
  join seed s on s.id=pi1.provider_id
  where pi1.valid_to is null
), same_name as (
  select p.id
  from catalogue.providers p join seed s on s.country_id=p.country_id
  where lower(regexp_replace(coalesce(p.display_name,p.canonical_name),'[^a-z0-9]+','','g'))=s.norm_name
)
select coalesce(array_agg(distinct id order by id),array[p_provider_id]::uuid[])
from (select id from same_identifier union select id from same_name union select p_provider_id) q;
$$;
revoke all on function public.svc_statistical_equivalent_provider_ids(uuid) from public,anon,authenticated;
grant execute on function public.svc_statistical_equivalent_provider_ids(uuid) to service_role;

-- Full svc_ranking_ingest_apply replacement is deployed in Pilot by CF-077 and
-- treats exact same-country provider names or shared current identifiers as
-- statistical equivalence. The source observation is retained once and linked
-- to every equivalent canonical Provider without merging Provider identity.

commit;