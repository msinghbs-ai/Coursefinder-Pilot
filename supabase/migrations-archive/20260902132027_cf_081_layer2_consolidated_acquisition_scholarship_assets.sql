-- CF-CHG-20260902-081
-- Consolidated Layer 2 acquisition / Scholarship seed / Provider assets.
-- Applied to Pilot as migration 20260902132027.
--
-- Key invariants:
--  * Layer 1 identity/statistical domains remain outside generic Layer 2 vendor routing.
--  * A single first-party source may have multiple deterministic extraction profiles.
--  * Same-URL Evidence may be reused for bounded TTL fan-out instead of refetched.
--  * Parse.bot is registered disabled until trial endpoint/credential qualification.
--  * Provider logos are candidates until evidence-backed approval; they never define Provider identity.

begin;

alter table pipeline.layer2_source_profiles
  drop constraint if exists layer2_source_profiles_source_id_key;

create or replace function pipeline.layer2_route_scope_guard()
returns trigger language plpgsql security definer
set search_path to 'pg_catalog','pipeline' as $$
declare v_domain text; v_target text; v_enabled boolean;
begin
 select domain,target_entity_type,enabled into v_domain,v_target,v_enabled
 from pipeline.layer2_source_profiles where id=new.profile_id;
 if v_domain is null then raise exception 'Layer 2 source profile not found' using errcode='23503'; end if;
 if not ((v_domain='course_facts' and v_target='course_fact')
      or (v_domain='scholarship' and v_target='scholarship')
      or (v_domain='provider_asset' and v_target='provider_asset')) then
   raise exception 'Layer 2 acquisition routes are limited to Course, Scholarship and Provider Asset enrichment; QILT/PRISMS remain Layer 1' using errcode='23514';
 end if;
 if not coalesce(v_enabled,false) then raise exception 'Layer 2 source profile is not enabled' using errcode='23514'; end if;
 return new;
end $$;

create table if not exists pipeline.layer2_shared_fetches(
 id uuid primary key default extensions.gen_random_uuid(),
 url_hash text not null unique, source_url text not null,
 evidence_id uuid not null references pipeline.evidence_artifacts(id) on delete restrict,
 content_hash text,mime_type text,
 acquisition_provider_id uuid references pipeline.layer2_acquisition_providers(id) on delete set null,
 source_profile_id uuid references pipeline.layer2_source_profiles(id) on delete set null,
 captured_at timestamptz not null default now(), reusable_until timestamptz not null,
 last_reused_at timestamptz,reuse_count integer not null default 0 check(reuse_count>=0),
 metadata jsonb not null default '{}'::jsonb);
create index if not exists layer2_shared_fetch_reusable_idx on pipeline.layer2_shared_fetches(reusable_until desc);

create table if not exists pipeline.layer2_fanout_tasks(
 id uuid primary key default extensions.gen_random_uuid(),
 shared_fetch_id uuid not null references pipeline.layer2_shared_fetches(id) on delete cascade,
 profile_id uuid not null references pipeline.layer2_source_profiles(id) on delete cascade,
 task_type text not null default 'extract' check(task_type in('extract','scholarship_discovery','provider_asset')),
 status text not null default 'queued' check(status in('queued','running','completed','failed','skipped')),
 created_at timestamptz not null default now(),started_at timestamptz,completed_at timestamptz,last_error text,
 metadata jsonb not null default '{}'::jsonb,unique(shared_fetch_id,profile_id,task_type));
create index if not exists layer2_fanout_queue_idx on pipeline.layer2_fanout_tasks(status,created_at) where status='queued';

create table if not exists pipeline.layer2_domain_refresh_policies(
 domain text primary key,routine_hours integer not null check(routine_hours between 1 and 8760),
 change_check_hours integer not null check(change_check_hours between 1 and 8760),
 accelerated_hours integer,acceleration_rule text,enabled boolean not null default true,
 notes text,updated_at timestamptz not null default now());

insert into pipeline.layer2_domain_refresh_policies(domain,routine_hours,change_check_hours,accelerated_hours,acceleration_rule,notes) values
 ('course_facts',720,168,72,'published intake/fee/calendar change or changed hash','Monthly full refresh; weekly lightweight check.'),
 ('scholarship',168,72,24,'inside 45 days of application boundary or changed hash','Weekly full refresh; three-day lightweight check.'),
 ('provider_asset',2160,720,null,null,'90-day full refresh; monthly lightweight check.'),
 ('provider_profile',720,168,72,'changed first-party Provider page','Shared provider-page acquisition.')
on conflict(domain) do update set routine_hours=excluded.routine_hours,change_check_hours=excluded.change_check_hours,
 accelerated_hours=excluded.accelerated_hours,acceleration_rule=excluded.acceleration_rule,notes=excluded.notes,updated_at=now();

create table if not exists catalogue.provider_assets(
 id uuid primary key default extensions.gen_random_uuid(),
 provider_id uuid not null references catalogue.providers(id) on delete cascade,
 asset_type text not null check(asset_type in('logo','logo_dark','logo_light','brand_mark')),
 source_url text not null,evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
 storage_path text,mime_type text,width integer,height integer,content_hash text,
 is_primary boolean not null default false,
 status text not null default 'candidate' check(status in('candidate','approved','rejected','superseded')),
 observed_at timestamptz not null default now(),verified_at timestamptz,metadata jsonb not null default '{}'::jsonb);
create unique index if not exists provider_assets_source_hash_uq
 on catalogue.provider_assets(provider_id,asset_type,coalesce(content_hash,''),source_url);
create unique index if not exists provider_assets_one_primary_logo_idx on catalogue.provider_assets(provider_id)
 where is_primary and asset_type in('logo','logo_dark','logo_light') and status='approved';

create table if not exists pipeline.provider_asset_candidates(
 id uuid primary key default extensions.gen_random_uuid(),
 provider_id uuid not null references catalogue.providers(id) on delete cascade,
 profile_id uuid references pipeline.layer2_source_profiles(id) on delete set null,
 source_url text not null,asset_url text not null,asset_type text not null default 'logo',
 evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,content_hash text,confidence numeric(5,4),
 status text not null default 'discovered' check(status in('discovered','accepted','rejected','needs_review')),
 discovered_at timestamptz not null default now(),metadata jsonb not null default '{}'::jsonb,unique(provider_id,asset_url));

alter table pipeline.layer2_shared_fetches enable row level security;
alter table pipeline.layer2_fanout_tasks enable row level security;
alter table pipeline.layer2_domain_refresh_policies enable row level security;
alter table catalogue.provider_assets enable row level security;
alter table pipeline.provider_asset_candidates enable row level security;
revoke all on pipeline.layer2_shared_fetches,pipeline.layer2_fanout_tasks,pipeline.layer2_domain_refresh_policies,pipeline.provider_asset_candidates from public,anon,authenticated;
revoke all on catalogue.provider_assets from public,anon,authenticated;

-- Runtime RPC implementations are deliberately service-role only.
create or replace function public.layer2_shared_fetch_lookup(p_source_url text,p_max_age_hours integer default 24)
returns jsonb language sql security definer set search_path='pg_catalog','pipeline','public' as $$
 select coalesce((select jsonb_build_object('shared_fetch_id',id,'evidence_id',evidence_id,'content_hash',content_hash,
 'mime_type',mime_type,'captured_at',captured_at,'reusable_until',reusable_until,'source_url',source_url,
 'acquisition_provider_id',acquisition_provider_id) from pipeline.layer2_shared_fetches
 where url_hash=encode(extensions.digest(lower(trim(p_source_url)),'sha256'),'hex')
 and reusable_until>now() and captured_at>=now()-make_interval(hours=>greatest(1,least(coalesce(p_max_age_hours,24),168))) limit 1),'{}'::jsonb) $$;
revoke all on function public.layer2_shared_fetch_lookup(text,integer) from public,anon,authenticated;
grant execute on function public.layer2_shared_fetch_lookup(text,integer) to service_role;

create or replace function public.layer2_shared_fetch_reused(p_shared_fetch_id uuid,p_job_id uuid,p_profile_id uuid)
returns void language plpgsql security definer set search_path='pg_catalog','pipeline','public' as $$
begin
 update pipeline.layer2_shared_fetches set last_reused_at=now(),reuse_count=reuse_count+1 where id=p_shared_fetch_id;
 update pipeline.jobs set result=coalesce(result,'{}'::jsonb)||jsonb_build_object('shared_fetch_id',p_shared_fetch_id,'shared_fetch_reused',true,'consumer_profile_id',p_profile_id) where id=p_job_id;
end $$;
revoke all on function public.layer2_shared_fetch_reused(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.layer2_shared_fetch_reused(uuid,uuid,uuid) to service_role;

create or replace function public.layer2_shared_fetch_register(p_source_url text,p_evidence_id uuid,p_content_hash text,p_mime_type text,p_acquisition_provider_id uuid,p_profile_id uuid,p_ttl_hours integer default 24)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline','public' as $$
declare v_id uuid;v_source uuid;v_n integer:=0;
begin
 select source_id into v_source from pipeline.layer2_source_profiles where id=p_profile_id;
 insert into pipeline.layer2_shared_fetches(url_hash,source_url,evidence_id,content_hash,mime_type,acquisition_provider_id,source_profile_id,captured_at,reusable_until,metadata)
 values(encode(extensions.digest(lower(trim(p_source_url)),'sha256'),'hex'),p_source_url,p_evidence_id,p_content_hash,p_mime_type,p_acquisition_provider_id,p_profile_id,now(),now()+make_interval(hours=>greatest(1,least(coalesce(p_ttl_hours,24),168))),jsonb_build_object('registered_by','layer2-acquire-v2','canonical_mutation_authorised',false))
 on conflict(url_hash) do update set source_url=excluded.source_url,evidence_id=excluded.evidence_id,content_hash=excluded.content_hash,mime_type=excluded.mime_type,acquisition_provider_id=excluded.acquisition_provider_id,source_profile_id=excluded.source_profile_id,captured_at=excluded.captured_at,reusable_until=excluded.reusable_until,metadata=excluded.metadata returning id into v_id;
 insert into pipeline.layer2_fanout_tasks(shared_fetch_id,profile_id,task_type,metadata)
 select v_id,p.id,case when p.target_entity_type='provider_asset' then 'provider_asset' when p.domain='scholarship' then 'scholarship_discovery' else 'extract' end,
 jsonb_build_object('source_profile_id',p_profile_id,'source_id',v_source,'shared_evidence_id',p_evidence_id)
 from pipeline.layer2_source_profiles p where p.source_id=v_source and p.id<>p_profile_id and p.enabled and not p.paused
 on conflict(shared_fetch_id,profile_id,task_type) do nothing;
 get diagnostics v_n=row_count;
 return jsonb_build_object('shared_fetch_id',v_id,'fanout_tasks_created',v_n);
end $$;
revoke all on function public.layer2_shared_fetch_register(text,uuid,text,text,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.layer2_shared_fetch_register(text,uuid,text,text,uuid,uuid,integer) to service_role;

insert into pipeline.layer2_acquisition_providers(provider_key,display_name,adapter_type,base_url,auth_scheme,auth_field_name,capabilities,request_template,enabled,priority,concurrency,timeout_seconds,operational_owner,change_control_ref)
values('parsebot','Parse.bot (trial pending)','structured_api_proxy',null,'header','X-API-Key',
 '{"raw":true,"html":true,"json":true,"javascript":true,"anti_bot":true,"structured_output":true}'::jsonb,
 '{"response_adapter":"generic_json","configuration_required":true}'::jsonb,false,25,2,90,'Platform Operations','CF-CHG-20260902-081')
on conflict(provider_key) do update set enabled=false,base_url=null,display_name=excluded.display_name,capabilities=excluded.capabilities,request_template=excluded.request_template,updated_at=now();

-- Profile validation now recognises provider_asset. Existing validation rules remain authoritative.
-- Seed one first-party AU/NZ web-catalogue anchor per Provider into Scholarship + Logo profiles.
with anchors as(
 select distinct on(s.provider_id) s.id source_id,s.provider_id,c.iso_alpha2 country_code
 from pipeline.sources s join ref.countries c on c.id=s.country_id
 where s.provider_id is not null and s.source_type='web_catalogue' and c.iso_alpha2 in('AU','NZ') and nullif(s.url,'') is not null
 order by s.provider_id,s.trust_rank desc nulls last,s.updated_at desc)
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select source_id,lower(country_code)||'-provider-scholarship-'||provider_id::text,'scholarship','scholarship_catalogue','scholarship','first_party',true,false,'PIM/Data Operations',168,'weekly; accelerate around application deadlines or changed hash' from anchors
on conflict(profile_key) do nothing;

with anchors as(
 select distinct on(s.provider_id) s.id source_id,s.provider_id,c.iso_alpha2 country_code
 from pipeline.sources s join ref.countries c on c.id=s.country_id
 where s.provider_id is not null and s.source_type='web_catalogue' and c.iso_alpha2 in('AU','NZ') and nullif(s.url,'') is not null
 order by s.provider_id,s.trust_rank desc nulls last,s.updated_at desc)
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select source_id,lower(country_code)||'-provider-logo-'||provider_id::text,'provider_asset','website','provider_asset','first_party',true,false,'PIM/Data Operations',2160,'90-day routine; monthly hash check' from anchors
on conflict(profile_key) do nothing;

-- Current-version configuration + Direct/Parse.bot(disabled)/Firecrawl/ZenRows routes are created by the applied migration.
-- Study Australia full refresh becomes weekly; DFAT becomes monthly; maintenance becomes weekly.
update pipeline.scholarship_etl_schedules set cadence_hours=168,next_due_at=greatest(next_due_at,now()+interval '72 hours'),updated_at=now() where feed='study_australia';
update pipeline.scholarship_etl_schedules set cadence_hours=720,next_due_at=greatest(next_due_at,now()+interval '168 hours'),updated_at=now() where feed='australia_awards';

do $$ begin
 if exists(select 1 from cron.job where jobname='coursefinder-scholarship-maintenance') then perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-scholarship-maintenance' limit 1)); end if;
 perform cron.schedule('coursefinder-scholarship-maintenance','20 5 * * 0','select security.scholarship_maintenance_tick_impl(now());');
end $$;

commit;
