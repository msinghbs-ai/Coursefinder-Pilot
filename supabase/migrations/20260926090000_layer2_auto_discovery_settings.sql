-- Package 7 (Decisions 141, 146): Platform Admin controls for Layer 2 automatic catalogue discovery.
-- providers_in_flight cannot exceed the Firecrawl provider concurrency (the vendor limit still
-- governs actual fetches). Every change is audited.
create table if not exists pipeline.layer2_auto_discovery_settings(
  id int primary key default 1 check (id=1),
  enabled boolean not null default false,
  daily_provider_cap int not null default 20 check (daily_provider_cap between 0 and 500),
  providers_in_flight int not null default 5 check (providers_in_flight between 1 and 20),
  candidates_per_provider int not null default 3 check (candidates_per_provider between 1 and 5),
  updated_by uuid, updated_at timestamptz not null default now()
);
insert into pipeline.layer2_auto_discovery_settings(id) values (1) on conflict (id) do nothing;
create table if not exists pipeline.layer2_auto_discovery_settings_audit(
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid not null, reason text not null, before jsonb not null, after jsonb not null, created_at timestamptz not null default now()
);
alter table pipeline.layer2_auto_discovery_settings enable row level security;
alter table pipeline.layer2_auto_discovery_settings_audit enable row level security;
revoke all on pipeline.layer2_auto_discovery_settings, pipeline.layer2_auto_discovery_settings_audit from public, anon, authenticated;

create or replace function public.layer2_auto_discovery_settings_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare s pipeline.layer2_auto_discovery_settings%rowtype; v_fc int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role is required' using errcode='42501'; end if;
  select * into s from pipeline.layer2_auto_discovery_settings where id=1;
  select concurrency into v_fc from pipeline.layer2_acquisition_providers where provider_key='firecrawl';
  return jsonb_build_object('enabled',s.enabled,'daily_provider_cap',s.daily_provider_cap,'providers_in_flight',s.providers_in_flight,
    'candidates_per_provider',s.candidates_per_provider,'firecrawl_concurrency',v_fc,'updated_at',s.updated_at,
    'can_edit',security.current_role_rank()>=6,
    'recent_changes',coalesce((select jsonb_agg(jsonb_build_object('at',a.created_at,'reason',a.reason,'after',a.after) order by a.created_at desc)
       from (select * from pipeline.layer2_auto_discovery_settings_audit order by created_at desc limit 5) a),'[]'::jsonb));
end $$;

create or replace function public.layer2_auto_discovery_settings_save_v1(p_enabled boolean, p_daily_provider_cap int, p_providers_in_flight int, p_candidates_per_provider int, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare v_actor uuid := auth.uid(); v_before jsonb; v_fc int;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 6 then raise exception 'Platform Admin role is required to change Layer 2 automation' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reason,''))) < 8 then raise exception 'a reason of at least 8 characters is required' using errcode='22023'; end if;
  select concurrency into v_fc from pipeline.layer2_acquisition_providers where provider_key='firecrawl';
  if p_providers_in_flight > coalesce(v_fc,1) then raise exception 'providers in flight (%) cannot exceed the Firecrawl concurrency (%); raise it in Scraper Config first', p_providers_in_flight, v_fc using errcode='22023'; end if;
  select to_jsonb(s)-'updated_by' into v_before from pipeline.layer2_auto_discovery_settings s where id=1;
  update pipeline.layer2_auto_discovery_settings set enabled=coalesce(p_enabled,enabled), daily_provider_cap=p_daily_provider_cap,
    providers_in_flight=p_providers_in_flight, candidates_per_provider=p_candidates_per_provider, updated_by=v_actor, updated_at=now() where id=1;
  insert into pipeline.layer2_auto_discovery_settings_audit(actor_id,reason,before,after)
  select v_actor, btrim(p_reason), v_before, to_jsonb(s)-'updated_by' from pipeline.layer2_auto_discovery_settings s where id=1;
  return public.layer2_auto_discovery_settings_read_v1();
end $$;
revoke all on function public.layer2_auto_discovery_settings_read_v1() from public, anon;
revoke all on function public.layer2_auto_discovery_settings_save_v1(boolean,int,int,int,text) from public, anon;
grant execute on function public.layer2_auto_discovery_settings_read_v1() to authenticated, service_role;
grant execute on function public.layer2_auto_discovery_settings_save_v1(boolean,int,int,int,text) to authenticated, service_role;
