-- A15 Institute International Contact Intelligence
-- Private pipeline storage + governed Provider-detail projection only.

create table if not exists pipeline.provider_contact_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null unique references catalogue.providers(id) on delete cascade,
  country_id uuid not null references ref.countries(id),
  base_url text not null,
  domain text not null,
  enabled boolean not null default true,
  paused boolean not null default false,
  discovery_path_terms text[] not null default array[
    'international','contact','regional','recruitment','representative',
    'manager','market','adviser','advisor','admissions'
  ]::text[],
  title_terms text[] not null default array[
    'international recruitment manager','regional manager','regional director',
    'international manager','international admissions','international office',
    'country manager','market manager','international recruitment'
  ]::text[],
  last_run_at timestamptz,
  last_success_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists pipeline.provider_contact_observations (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  profile_id uuid references pipeline.provider_contact_profiles(id) on delete set null,
  source_class text not null check (source_class in ('first_party','licensed_enrichment','manual')),
  source_provider text,
  source_url text,
  external_person_id text,
  full_name text,
  job_title text,
  team_name text,
  territory_text text,
  territory_codes text[] not null default '{}'::text[],
  work_email text,
  work_phone text,
  professional_profile_url text,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  identity_hash text not null unique,
  verification_state text not null default 'current'
    check (verification_state in ('current','unverified','stale','superseded','rejected')),
  observed_at timestamptz not null default now(),
  last_verified_at timestamptz not null default now(),
  valid_from timestamptz,
  valid_to timestamptz,
  is_current boolean not null default true,
  confidence numeric(5,4) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source_class <> 'first_party' or source_url is not null)
);

create table if not exists pipeline.provider_contact_watch_events (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  observation_id uuid references pipeline.provider_contact_observations(id) on delete set null,
  event_type text not null check (event_type in ('new_contact','title_changed','territory_changed','contact_changed','contact_removed','contact_restored')),
  source_class text not null check (source_class in ('first_party','licensed_enrichment','manual')),
  before_state jsonb,
  after_state jsonb,
  detected_at timestamptz not null default now(),
  acknowledged boolean not null default false,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists pipeline.provider_contact_enrichment_attempts (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  source_provider text not null,
  request_type text not null,
  domain text,
  requested_titles text[] not null default '{}'::text[],
  status text not null,
  external_call_count integer not null default 0 check (external_call_count >= 0),
  vendor_units numeric(14,4) check (vendor_units is null or vendor_units >= 0),
  estimated_cost_usd numeric(14,6) check (estimated_cost_usd is null or estimated_cost_usd >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  error text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists provider_contact_profiles_country_idx
  on pipeline.provider_contact_profiles(country_id, enabled, paused);
create index if not exists provider_contact_observations_provider_current_idx
  on pipeline.provider_contact_observations(provider_id, is_current, source_class, last_verified_at desc);
create index if not exists provider_contact_observations_evidence_idx
  on pipeline.provider_contact_observations(evidence_id) where evidence_id is not null;
create index if not exists provider_contact_watch_events_provider_idx
  on pipeline.provider_contact_watch_events(provider_id, detected_at desc);
create index if not exists provider_contact_enrichment_attempts_provider_idx
  on pipeline.provider_contact_enrichment_attempts(provider_id, created_at desc);

alter table pipeline.provider_contact_profiles enable row level security;
alter table pipeline.provider_contact_observations enable row level security;
alter table pipeline.provider_contact_watch_events enable row level security;
alter table pipeline.provider_contact_enrichment_attempts enable row level security;

revoke all on pipeline.provider_contact_profiles from public, anon, authenticated;
revoke all on pipeline.provider_contact_observations from public, anon, authenticated;
revoke all on pipeline.provider_contact_watch_events from public, anon, authenticated;
revoke all on pipeline.provider_contact_enrichment_attempts from public, anon, authenticated;

grant select,insert,update,delete on pipeline.provider_contact_profiles to service_role;
grant select,insert,update,delete on pipeline.provider_contact_observations to service_role;
grant select,insert,update,delete on pipeline.provider_contact_watch_events to service_role;
grant select,insert,update,delete on pipeline.provider_contact_enrichment_attempts to service_role;

insert into pipeline.provider_contact_profiles(provider_id,country_id,base_url,domain)
select
  p.id,
  p.country_id,
  case when p.website ~* '^https?://' then p.website else 'https://'||p.website end,
  lower(
    regexp_replace(
      regexp_replace(
        regexp_replace(case when p.website ~* '^https?://' then p.website else 'https://'||p.website end,'^https?://','','i'),
        '/.*$','','g'
      ),
      '^www\.','','i'
    )
  )
from catalogue.providers p
join ref.countries c on c.id=p.country_id
where c.iso_alpha2 in ('AU','NZ')
  and nullif(trim(p.website),'') is not null
  and (
    p.canonical_name ilike '%university%'
    or (c.iso_alpha2='NZ' and p.canonical_name ilike 'te pukenga%')
  )
on conflict (provider_id) do update
set base_url=excluded.base_url,
    domain=excluded.domain,
    country_id=excluded.country_id,
    updated_at=now();

create or replace function security.admin_provider_contacts(p_provider_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','ref','public','auth'
as $$
declare
  v_rank integer:=0;
  v_profile jsonb;
  v_items jsonb;
  v_events jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  select jsonb_build_object(
    'profile_id',p.id,
    'enabled',p.enabled,
    'paused',p.paused,
    'base_url',p.base_url,
    'domain',p.domain,
    'last_run_at',p.last_run_at,
    'last_success_at',p.last_success_at,
    'last_error',p.last_error
  )
  into v_profile
  from pipeline.provider_contact_profiles p
  where p.provider_id=p_provider_id;

  select coalesce(jsonb_agg(row_json order by source_priority, lower(coalesce(row_json->>'territory_text','')), lower(coalesce(row_json->>'job_title','')), lower(coalesce(row_json->>'full_name',''))),'[]'::jsonb)
  into v_items
  from (
    select
      case o.source_class when 'first_party' then 1 when 'manual' then 2 else 3 end source_priority,
      jsonb_build_object(
        'id',o.id,
        'source_class',o.source_class,
        'source_provider',o.source_provider,
        'full_name',o.full_name,
        'job_title',o.job_title,
        'team_name',o.team_name,
        'territory_text',o.territory_text,
        'territory_codes',o.territory_codes,
        'work_email',o.work_email,
        'work_phone',o.work_phone,
        'professional_profile_url',o.professional_profile_url,
        'source_url',o.source_url,
        'evidence_id',o.evidence_id,
        'verification_state',o.verification_state,
        'confidence',o.confidence,
        'observed_at',o.observed_at,
        'last_verified_at',o.last_verified_at,
        'source_priority',case o.source_class when 'first_party' then 'preferred' when 'manual' then 'governed_manual' else 'secondary_enrichment' end
      ) row_json
    from pipeline.provider_contact_observations o
    where o.provider_id=p_provider_id and o.is_current=true and o.verification_state <> 'rejected'
    order by 1, o.last_verified_at desc
    limit 50
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,
    'event_type',e.event_type,
    'source_class',e.source_class,
    'before_state',e.before_state,
    'after_state',e.after_state,
    'detected_at',e.detected_at,
    'acknowledged',e.acknowledged
  ) order by e.detected_at desc),'[]'::jsonb)
  into v_events
  from (
    select * from pipeline.provider_contact_watch_events
    where provider_id=p_provider_id
    order by detected_at desc
    limit 20
  ) e;

  return jsonb_build_object(
    'profile',coalesce(v_profile,'{}'::jsonb),
    'items',coalesce(v_items,'[]'::jsonb),
    'events',coalesce(v_events,'[]'::jsonb),
    'summary',jsonb_build_object(
      'current_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and verification_state<>'rejected'),
      'first_party_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='first_party' and verification_state<>'rejected'),
      'enriched_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='licensed_enrichment' and verification_state<>'rejected'),
      'unacknowledged_changes',(select count(*) from pipeline.provider_contact_watch_events where provider_id=p_provider_id and acknowledged=false)
    )
  );
end $$;

revoke all on function security.admin_provider_contacts(uuid) from public, anon, authenticated;

create or replace function security.admin_provider_detail(p_provider_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'security', 'public', 'catalogue', 'pipeline', 'ref', 'search', 'scholarship', 'auth'
as $$
declare
  v_rank integer:=0;
  v_base jsonb;
  v_courses jsonb;
  v_evidence jsonb;
  v_campuses jsonb;
  v_contacts jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  v_base:=public.ui_provider_detail(p_provider_id);
  if v_base is null then return '{}'::jsonb; end if;
  v_courses:=public.ui_provider_related_courses(p_provider_id,25,0,null,null,null);
  v_evidence:=public.ui_provider_related_evidence(p_provider_id,25,0,null,null);
  v_contacts:=security.admin_provider_contacts(p_provider_id);

  with base as (
    select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.city,ca.postcode,ca.status,ca.publication_status,
           sd.code subdivision_code,sd.name subdivision_name,
           (select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count
    from catalogue.campuses ca left join ref.subdivisions sd on sd.id=ca.subdivision_id
    where ca.provider_id=p_provider_id
  ), numbered as (select *,count(*) over() total_count from base), ordered as (
    select * from numbered order by lower(name),id limit 25
  )
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',25,'offset',0)
    into v_campuses from ordered o;

  return v_base || jsonb_build_object(
    'courses_page',coalesce(v_courses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'evidence_page',coalesce(v_evidence,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'campuses_page',coalesce(v_campuses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'courses',coalesce(v_courses->'items','[]'::jsonb),
    'evidence',coalesce(v_evidence->'items','[]'::jsonb),
    'international_contacts',coalesce(v_contacts,jsonb_build_object('items','[]'::jsonb,'events','[]'::jsonb,'summary','{}'::jsonb)),
    'scholarship_count',(select count(*) from scholarship.scholarships s where s.provider_id=p_provider_id),
    'history',jsonb_build_object('created_at',v_base->'created_at','updated_at',v_base->'updated_at','last_verified_at',v_base->'last_verified_at')
  );
end $$;

revoke all on function security.admin_provider_detail(uuid) from public, anon;
grant execute on function security.admin_provider_detail(uuid) to authenticated, service_role;
