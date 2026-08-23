-- M1-PUBLICATION-UAT — governed controlled Pilot publication profile.
-- Change Control: CF-CHG-20260823-024.
-- This migration does not publish the catalogue. It creates a bounded profile,
-- explicitly approves two stable-key UAT Courses, and exposes service-only
-- publication mutation / Search-refresh functions.

create table if not exists publishing.publication_profiles (
  profile_code text primary key,
  entity_type text not null,
  profile_name text not null,
  profile_status text not null check (profile_status in ('active','inactive','retired')),
  profile_scope jsonb not null default '{}'::jsonb,
  criteria jsonb not null default '{}'::jsonb,
  change_control_ref text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists publishing.publication_approvals (
  profile_code text not null references publishing.publication_profiles(profile_code) on delete cascade,
  entity_id uuid not null references pim.entity_registry(id) on delete cascade,
  approval_status text not null check (approval_status in ('approved','revoked')),
  approval_reason text,
  approved_by_ref text not null,
  approved_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (profile_code,entity_id)
);

create table if not exists publishing.publication_events (
  event_id bigint generated always as identity primary key,
  entity_id uuid not null references pim.entity_registry(id) on delete cascade,
  profile_code text not null references publishing.publication_profiles(profile_code),
  prior_status text,
  target_status text not null,
  changed boolean not null,
  reason text,
  readiness jsonb not null default '{}'::jsonb,
  change_control_ref text not null,
  created_at timestamptz not null default now()
);

create index if not exists publication_approvals_entity_idx
  on publishing.publication_approvals(entity_id,profile_code,approval_status);
create index if not exists publication_events_entity_created_idx
  on publishing.publication_events(entity_id,created_at desc);

insert into publishing.publication_profiles(
  profile_code,entity_type,profile_name,profile_status,profile_scope,criteria,change_control_ref,updated_at
) values (
  'pilot-course-positive-v1','course','Pilot AU/NZ controlled positive-path publication','active',
  jsonb_build_object('environment','pilot','countries',jsonb_build_array('AU','NZ'),'purpose','controlled_positive_path_uat'),
  jsonb_build_object(
    'explicit_approval',true,
    'lifecycle','active',
    'stable_course_identity',true,
    'stable_provider_identity',true,
    'course_code_required',true,
    'search_projection_required',true,
    'governed_evidence_links_min',1,
    'layer2_enrichment','truthful_optional_by_country'
  ),
  'CF-CHG-20260823-024',now()
)
on conflict(profile_code) do update set
  profile_name=excluded.profile_name,
  profile_status=excluded.profile_status,
  profile_scope=excluded.profile_scope,
  criteria=excluded.criteria,
  change_control_ref=excluded.change_control_ref,
  updated_at=now();

insert into publishing.publication_approvals(
  profile_code,entity_id,approval_status,approval_reason,approved_by_ref,approved_at,updated_at
)
select 'pilot-course-positive-v1',c.id,'approved',
       case when c.stable_key='course:cricos:00025b:102784c'
            then 'Controlled AU positive-path UAT; accepted first-party Course Facts present.'
            else 'Controlled NZ positive-path UAT; Layer 2 gaps remain truthful and are not manufactured.' end,
       'CF-CHG-20260823-024',now(),now()
from catalogue.courses c
where c.stable_key in ('course:cricos:00025b:102784c','course:nzqa:8509:109509')
on conflict(profile_code,entity_id) do update set
  approval_status='approved',
  approval_reason=excluded.approval_reason,
  approved_by_ref=excluded.approved_by_ref,
  approved_at=excluded.approved_at,
  revoked_at=null,
  updated_at=now();

create or replace function publishing.course_publication_readiness_v1(
  p_course_id uuid,
  p_profile_code text default 'pilot-course-positive-v1'
) returns jsonb
language plpgsql
stable
security definer
set search_path=publishing,catalogue,search,ref,pipeline,pg_temp
as $function$
declare
  v_profile_active boolean := false;
  v_approved boolean := false;
  v_active boolean := false;
  v_country text;
  v_course_key text;
  v_provider_key text;
  v_course_code text;
  v_title text;
  v_projected boolean := false;
  v_evidence bigint := 0;
  v_blockers text[] := '{}'::text[];
  v_exists boolean := false;
begin
  select exists(
    select 1 from publishing.publication_profiles pp
    where pp.profile_code=p_profile_code and pp.entity_type='course' and pp.profile_status='active'
  ) into v_profile_active;

  select true,
         c.lifecycle_status='active',trim(co.iso_alpha2::text),c.stable_key,p.stable_key,c.course_code,c.canonical_title,
         exists(select 1 from search.course_documents d where d.course_id=c.id)
    into v_exists,v_active,v_country,v_course_key,v_provider_key,v_course_code,v_title,v_projected
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  join ref.countries co on co.id=p.country_id
  where c.id=p_course_id;

  if not coalesce(v_exists,false) then
    return jsonb_build_object('eligible',false,'profile_code',p_profile_code,'course_id',p_course_id,'blockers',jsonb_build_array('course_not_found'));
  end if;

  select exists(
    select 1 from publishing.publication_approvals pa
    where pa.profile_code=p_profile_code and pa.entity_id=p_course_id and pa.approval_status='approved'
  ) into v_approved;

  select coalesce(sum(el.link_count),0)::bigint into v_evidence
  from pipeline.evidence_entity_links el
  where el.entity_type='course' and el.entity_id=p_course_id;

  if not v_profile_active then v_blockers:=array_append(v_blockers,'profile_not_active'); end if;
  if not v_approved then v_blockers:=array_append(v_blockers,'not_explicitly_approved'); end if;
  if not v_active then v_blockers:=array_append(v_blockers,'lifecycle_not_active'); end if;
  if v_country is null or v_country not in ('AU','NZ') then v_blockers:=array_append(v_blockers,'country_out_of_scope'); end if;
  if nullif(trim(v_course_key),'') is null then v_blockers:=array_append(v_blockers,'course_stable_key_missing'); end if;
  if nullif(trim(v_provider_key),'') is null then v_blockers:=array_append(v_blockers,'provider_stable_key_missing'); end if;
  if nullif(trim(v_course_code),'') is null then v_blockers:=array_append(v_blockers,'course_code_missing'); end if;
  if nullif(trim(v_title),'') is null then v_blockers:=array_append(v_blockers,'course_title_missing'); end if;
  if not v_projected then v_blockers:=array_append(v_blockers,'search_not_projected'); end if;
  if v_evidence < 1 then v_blockers:=array_append(v_blockers,'governed_evidence_missing'); end if;

  return jsonb_build_object(
    'eligible',cardinality(v_blockers)=0,
    'profile_code',p_profile_code,
    'course_id',p_course_id,
    'country',v_country,
    'signals',jsonb_build_object(
      'profile_active',v_profile_active,
      'explicitly_approved',v_approved,
      'lifecycle_active',v_active,
      'stable_course_identity',nullif(trim(v_course_key),'') is not null,
      'stable_provider_identity',nullif(trim(v_provider_key),'') is not null,
      'course_code_present',nullif(trim(v_course_code),'') is not null,
      'course_title_present',nullif(trim(v_title),'') is not null,
      'search_projected',v_projected,
      'governed_evidence_links',v_evidence
    ),
    'blockers',to_jsonb(v_blockers)
  );
end
$function$;

create or replace function publishing.set_course_publication_v1(
  p_course_id uuid,
  p_target_status text,
  p_profile_code text default 'pilot-course-positive-v1',
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=publishing,catalogue,ref,pg_temp
as $function$
declare
  v_target text := lower(trim(coalesce(p_target_status,'')));
  v_prior text;
  v_country text;
  v_locale text;
  v_ready jsonb;
  v_canonical_changed integer := 0;
  v_website_changed integer := 0;
  v_zoho_changed integer := 0;
  v_website_status text;
  v_zoho_status text;
  v_changed boolean;
begin
  if v_target not in ('published','internal','unpublished','blocked') then
    raise exception 'unsupported publication status: %',p_target_status using errcode='22023';
  end if;

  select c.publication_status,trim(co.iso_alpha2::text)
    into v_prior,v_country
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  join ref.countries co on co.id=p.country_id
  where c.id=p_course_id
  for update of c;

  if not found then
    raise exception 'course not found: %',p_course_id using errcode='P0002';
  end if;

  v_ready:=publishing.course_publication_readiness_v1(p_course_id,p_profile_code);
  if v_target in ('published','internal') and not coalesce((v_ready->>'eligible')::boolean,false) then
    raise exception 'publication profile blocked: %',v_ready::text using errcode='42501';
  end if;

  v_locale:=case v_country when 'AU' then 'en-AU' when 'NZ' then 'en-NZ' else 'en' end;
  v_website_status:=case v_target when 'published' then 'published' when 'blocked' then 'blocked' else 'unpublished' end;
  v_zoho_status:=case v_target when 'published' then 'published' when 'internal' then 'internal' when 'blocked' then 'blocked' else 'unpublished' end;

  update catalogue.courses
     set publication_status=v_target,updated_at=now()
   where id=p_course_id and publication_status is distinct from v_target;
  get diagnostics v_canonical_changed=row_count;

  insert into publishing.entity_states(entity_id,channel_code,locale,publication_status,published_at,unpublished_at,last_checked_at,updated_at)
  values(p_course_id,'website',v_locale,v_website_status,
         case when v_website_status='published' then now() end,
         case when v_website_status in ('unpublished','blocked') then now() end,
         now(),now())
  on conflict(entity_id,channel_code,locale) do update set
    publication_status=excluded.publication_status,
    published_at=case when excluded.publication_status='published' then excluded.published_at else publishing.entity_states.published_at end,
    unpublished_at=case when excluded.publication_status in ('unpublished','blocked') then excluded.unpublished_at else publishing.entity_states.unpublished_at end,
    last_checked_at=now(),updated_at=now()
  where publishing.entity_states.publication_status is distinct from excluded.publication_status;
  get diagnostics v_website_changed=row_count;

  insert into publishing.entity_states(entity_id,channel_code,locale,publication_status,published_at,unpublished_at,last_checked_at,updated_at)
  values(p_course_id,'zoho',v_locale,v_zoho_status,
         case when v_zoho_status='published' then now() end,
         case when v_zoho_status in ('unpublished','blocked') then now() end,
         now(),now())
  on conflict(entity_id,channel_code,locale) do update set
    publication_status=excluded.publication_status,
    published_at=case when excluded.publication_status='published' then excluded.published_at else publishing.entity_states.published_at end,
    unpublished_at=case when excluded.publication_status in ('unpublished','blocked') then excluded.unpublished_at else publishing.entity_states.unpublished_at end,
    last_checked_at=now(),updated_at=now()
  where publishing.entity_states.publication_status is distinct from excluded.publication_status;
  get diagnostics v_zoho_changed=row_count;

  v_changed:=(v_canonical_changed+v_website_changed+v_zoho_changed)>0;

  if v_changed then
    insert into publishing.publication_events(entity_id,profile_code,prior_status,target_status,changed,reason,readiness,change_control_ref)
    values(p_course_id,p_profile_code,v_prior,v_target,true,p_reason,v_ready,'CF-CHG-20260823-024');
  end if;

  return jsonb_build_object(
    'course_id',p_course_id,'profile_code',p_profile_code,'prior_status',v_prior,'target_status',v_target,
    'changed',v_changed,
    'canonical_changed',v_canonical_changed=1,
    'website_channel',v_website_status,'website_changed',v_website_changed=1,
    'zoho_channel',v_zoho_status,'zoho_changed',v_zoho_changed=1,
    'search_refresh_required',v_canonical_changed=1,
    'readiness',v_ready
  );
end
$function$;

create or replace function publishing.refresh_course_publication_search_v1()
returns jsonb
language plpgsql
security definer
set search_path=publishing,search,pg_temp
as $function$
declare
  v_refresh jsonb;
  v_published bigint;
  v_internal bigint;
begin
  v_refresh:=search.refresh_course_documents_v3(true);
  select count(*) filter(where publication_status='published'),count(*) filter(where publication_status='internal')
    into v_published,v_internal
  from search.course_documents;
  return jsonb_build_object('refresh',v_refresh,'search_published',v_published,'search_internal',v_internal,'refreshed_at',now());
end
$function$;

revoke all on publishing.publication_profiles from public,anon,authenticated;
revoke all on publishing.publication_approvals from public,anon,authenticated;
revoke all on publishing.publication_events from public,anon,authenticated;
revoke all on function publishing.course_publication_readiness_v1(uuid,text) from public,anon,authenticated;
revoke all on function publishing.set_course_publication_v1(uuid,text,text,text) from public,anon,authenticated;
revoke all on function publishing.refresh_course_publication_search_v1() from public,anon,authenticated;

grant select on publishing.publication_profiles,publishing.publication_approvals,publishing.publication_events to service_role;
grant execute on function publishing.course_publication_readiness_v1(uuid,text) to service_role;
grant execute on function publishing.set_course_publication_v1(uuid,text,text,text) to service_role;
grant execute on function publishing.refresh_course_publication_search_v1() to service_role;

comment on function publishing.course_publication_readiness_v1(uuid,text) is
  'CF-CHG-20260823-024: explicit controlled publication readiness; Search presence alone is insufficient.';
comment on function publishing.set_course_publication_v1(uuid,text,text,text) is
  'CF-CHG-20260823-024: service-only bounded Course publication mutation; requires profile readiness for internal/published.';
comment on function publishing.refresh_course_publication_search_v1() is
  'CF-CHG-20260823-024: explicit Search refresh after bounded publication state changes.';
