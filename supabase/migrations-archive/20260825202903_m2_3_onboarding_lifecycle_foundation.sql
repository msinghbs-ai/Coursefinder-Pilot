-- CF-CHG-20260825-037
-- Reusable Country / Provider / Course onboarding lifecycle. Private state, rank-checked browser contracts.

create table if not exists pipeline.onboarding_cases (
  id uuid primary key default gen_random_uuid(),
  case_type text not null check (case_type in ('country','source','provider','course')),
  country_code text,
  title text not null check (length(trim(title)) between 3 and 240),
  source_id uuid references pipeline.sources(id) on delete restrict,
  source_profile_id uuid references pipeline.layer2_source_profiles(id) on delete restrict,
  provider_id uuid references catalogue.providers(id) on delete restrict,
  course_id uuid references catalogue.courses(id) on delete restrict,
  stage text not null default 'draft' check (stage in (
    'draft','source_qualification','adapter_assessment','schema_assessment','l1_uat','l2_uat','l3_ready','operational_certification','production_promotion_ready'
  )),
  outcome text check (outcome is null or outcome in ('READY','CONDITIONAL','BLOCKED','PAUSED','REJECTED')),
  adapter_family text check (adapter_family is null or adapter_family in (
    'structured_api','csv_xlsx','json','xml','sitemap_catalogue','html_detail','document_pdf','direct_http','approved_scraper_browser','custom_adapter'
  )),
  source_qualification jsonb not null default '{}'::jsonb,
  adapter_assessment jsonb not null default '{}'::jsonb,
  schema_assessment jsonb not null default '{}'::jsonb,
  operational_manifest jsonb not null default '{}'::jsonb,
  change_control_ref text not null default 'CF-CHG-20260825-037',
  uat_ref text,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  check (case_type <> 'provider' or provider_id is not null),
  check (case_type <> 'course' or course_id is not null),
  check (case_type <> 'source' or source_id is not null)
);

create index if not exists onboarding_cases_stage_outcome_idx on pipeline.onboarding_cases(stage,outcome,updated_at desc);
create index if not exists onboarding_cases_country_idx on pipeline.onboarding_cases(country_code,case_type,updated_at desc);
create index if not exists onboarding_cases_source_idx on pipeline.onboarding_cases(source_id) where source_id is not null;
create index if not exists onboarding_cases_profile_idx on pipeline.onboarding_cases(source_profile_id) where source_profile_id is not null;
create index if not exists onboarding_cases_provider_idx on pipeline.onboarding_cases(provider_id) where provider_id is not null;
create index if not exists onboarding_cases_course_idx on pipeline.onboarding_cases(course_id) where course_id is not null;

alter table pipeline.onboarding_cases enable row level security;
revoke all on pipeline.onboarding_cases from public, anon, authenticated;
grant select,insert,update,delete on pipeline.onboarding_cases to service_role;

create table if not exists pipeline.onboarding_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references pipeline.onboarding_cases(id) on delete restrict,
  event_type text not null check (event_type in ('created','transition','outcome','metadata_update')),
  from_stage text,
  to_stage text,
  outcome text check (outcome is null or outcome in ('READY','CONDITIONAL','BLOCKED','PAUSED','REJECTED')),
  reason text not null check (length(trim(reason)) >= 3),
  details jsonb not null default '{}'::jsonb,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
  change_control_ref text not null default 'CF-CHG-20260825-037',
  uat_ref text,
  actor_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists onboarding_events_case_created_idx on pipeline.onboarding_lifecycle_events(case_id,created_at,id);
create index if not exists onboarding_events_evidence_idx on pipeline.onboarding_lifecycle_events(evidence_id) where evidence_id is not null;

alter table pipeline.onboarding_lifecycle_events enable row level security;
revoke all on pipeline.onboarding_lifecycle_events from public, anon, authenticated;
grant select,insert on pipeline.onboarding_lifecycle_events to service_role;

create or replace function security.onboarding_next_stage(p_stage text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
select case p_stage
  when 'draft' then 'source_qualification'
  when 'source_qualification' then 'adapter_assessment'
  when 'adapter_assessment' then 'schema_assessment'
  when 'schema_assessment' then 'l1_uat'
  when 'l1_uat' then 'l2_uat'
  when 'l2_uat' then 'l3_ready'
  when 'l3_ready' then 'operational_certification'
  when 'operational_certification' then 'production_promotion_ready'
  else null end
$$;
revoke all on function security.onboarding_next_stage(text) from public, anon, authenticated;
grant execute on function security.onboarding_next_stage(text) to service_role;

create or replace function security.onboarding_cases_list_impl(
  p_stage text default null,
  p_outcome text default null,
  p_country_code text default null,
  p_case_type text default null,
  p_limit integer default 100
) returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.updated_at desc, x.id)
    from (
      select c.id,c.case_type,c.country_code,c.title,c.source_id,c.source_profile_id,c.provider_id,c.course_id,
             c.stage,c.outcome,c.adapter_family,c.source_qualification,c.adapter_assessment,c.schema_assessment,
             c.operational_manifest,c.change_control_ref,c.uat_ref,c.created_by,c.updated_by,c.created_at,c.updated_at,
             security.onboarding_next_stage(c.stage) as next_stage,
             (select count(*) from pipeline.onboarding_lifecycle_events e where e.case_id=c.id) as history_count
      from pipeline.onboarding_cases c
      where (p_stage is null or c.stage=p_stage)
        and (p_outcome is null or c.outcome=p_outcome)
        and (p_country_code is null or c.country_code=upper(p_country_code))
        and (p_case_type is null or c.case_type=p_case_type)
      order by c.updated_at desc,c.id
      limit least(greatest(coalesce(p_limit,100),1),500)
    ) x
  ),'[]'::jsonb);
end $$;

create or replace function security.onboarding_case_context_impl(p_case_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v_case jsonb; v_history jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  select to_jsonb(c) || jsonb_build_object('next_stage',security.onboarding_next_stage(c.stage)) into v_case
  from pipeline.onboarding_cases c where c.id=p_case_id;
  if v_case is null then raise exception 'onboarding case not found'; end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]'::jsonb) into v_history
  from pipeline.onboarding_lifecycle_events e where e.case_id=p_case_id;
  return jsonb_build_object('case',v_case,'history',v_history);
end $$;

create or replace function security.onboarding_case_create_impl(
  p_case_type text,
  p_country_code text,
  p_title text,
  p_source_id uuid default null,
  p_source_profile_id uuid default null,
  p_provider_id uuid default null,
  p_course_id uuid default null,
  p_adapter_family text default null,
  p_reason text default null,
  p_change_control_ref text default 'CF-CHG-20260825-037',
  p_uat_ref text default null
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v_id uuid:=gen_random_uuid(); v_actor uuid:=auth.uid();
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'reason required'; end if;
  insert into pipeline.onboarding_cases(
    id,case_type,country_code,title,source_id,source_profile_id,provider_id,course_id,stage,outcome,
    adapter_family,change_control_ref,uat_ref,created_by,updated_by
  ) values (
    v_id,p_case_type,case when p_country_code is null then null else upper(p_country_code) end,trim(p_title),
    p_source_id,p_source_profile_id,p_provider_id,p_course_id,'draft',null,p_adapter_family,
    coalesce(nullif(trim(p_change_control_ref),''),'CF-CHG-20260825-037'),p_uat_ref,v_actor,v_actor
  );
  insert into pipeline.onboarding_lifecycle_events(case_id,event_type,to_stage,reason,change_control_ref,uat_ref,actor_id)
  values(v_id,'created','draft',trim(p_reason),coalesce(nullif(trim(p_change_control_ref),''),'CF-CHG-20260825-037'),p_uat_ref,v_actor);
  return v_id;
end $$;

create or replace function security.onboarding_case_transition_impl(
  p_case_id uuid,
  p_to_stage text,
  p_outcome text,
  p_reason text,
  p_details jsonb default '{}'::jsonb,
  p_evidence_id uuid default null,
  p_uat_ref text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v_case pipeline.onboarding_cases%rowtype; v_next text; v_actor uuid:=auth.uid();
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'reason required'; end if;
  if p_outcome is not null and p_outcome not in ('READY','CONDITIONAL','BLOCKED','PAUSED','REJECTED') then raise exception 'invalid onboarding outcome'; end if;
  select * into v_case from pipeline.onboarding_cases where id=p_case_id for update;
  if not found then raise exception 'onboarding case not found'; end if;
  if v_case.outcome='REJECTED' then raise exception 'rejected onboarding case is terminal'; end if;
  v_next:=security.onboarding_next_stage(v_case.stage);
  if v_next is null then raise exception 'onboarding case already at terminal lifecycle stage'; end if;
  if p_to_stage is distinct from v_next then raise exception 'invalid lifecycle transition: expected %, received %',v_next,p_to_stage; end if;

  update pipeline.onboarding_cases
  set stage=p_to_stage,outcome=p_outcome,updated_by=v_actor,updated_at=now(),
      uat_ref=coalesce(p_uat_ref,uat_ref)
  where id=p_case_id;

  insert into pipeline.onboarding_lifecycle_events(
    case_id,event_type,from_stage,to_stage,outcome,reason,details,evidence_id,change_control_ref,uat_ref,actor_id
  ) values(
    p_case_id,'transition',v_case.stage,p_to_stage,p_outcome,trim(p_reason),coalesce(p_details,'{}'::jsonb),p_evidence_id,
    v_case.change_control_ref,p_uat_ref,v_actor
  );
  return security.onboarding_case_context_impl(p_case_id);
end $$;

create or replace function security.onboarding_case_metadata_update_impl(
  p_case_id uuid,
  p_adapter_family text default null,
  p_source_qualification jsonb default null,
  p_adapter_assessment jsonb default null,
  p_schema_assessment jsonb default null,
  p_operational_manifest jsonb default null,
  p_reason text default null,
  p_uat_ref text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v_actor uuid:=auth.uid(); v_cc text;
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'reason required'; end if;
  select change_control_ref into v_cc from pipeline.onboarding_cases where id=p_case_id for update;
  if v_cc is null then raise exception 'onboarding case not found'; end if;
  update pipeline.onboarding_cases set
    adapter_family=coalesce(p_adapter_family,adapter_family),
    source_qualification=coalesce(p_source_qualification,source_qualification),
    adapter_assessment=coalesce(p_adapter_assessment,adapter_assessment),
    schema_assessment=coalesce(p_schema_assessment,schema_assessment),
    operational_manifest=coalesce(p_operational_manifest,operational_manifest),
    uat_ref=coalesce(p_uat_ref,uat_ref),updated_by=v_actor,updated_at=now()
  where id=p_case_id;
  insert into pipeline.onboarding_lifecycle_events(case_id,event_type,from_stage,to_stage,outcome,reason,details,change_control_ref,uat_ref,actor_id)
  select id,'metadata_update',stage,stage,outcome,trim(p_reason),jsonb_strip_nulls(jsonb_build_object(
    'adapter_family',p_adapter_family,'source_qualification',p_source_qualification,'adapter_assessment',p_adapter_assessment,
    'schema_assessment',p_schema_assessment,'operational_manifest',p_operational_manifest)),change_control_ref,p_uat_ref,v_actor
  from pipeline.onboarding_cases where id=p_case_id;
  return security.onboarding_case_context_impl(p_case_id);
end $$;

revoke all on function security.onboarding_cases_list_impl(text,text,text,text,integer) from public,anon,authenticated;
revoke all on function security.onboarding_case_context_impl(uuid) from public,anon,authenticated;
revoke all on function security.onboarding_case_create_impl(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function security.onboarding_case_transition_impl(uuid,text,text,text,jsonb,uuid,text) from public,anon,authenticated;
revoke all on function security.onboarding_case_metadata_update_impl(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) from public,anon,authenticated;
grant execute on function security.onboarding_cases_list_impl(text,text,text,text,integer) to service_role;
grant execute on function security.onboarding_case_context_impl(uuid) to service_role;
grant execute on function security.onboarding_case_create_impl(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) to service_role;
grant execute on function security.onboarding_case_transition_impl(uuid,text,text,text,jsonb,uuid,text) to service_role;
grant execute on function security.onboarding_case_metadata_update_impl(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) to service_role;

create or replace function public.onboarding_cases_list(
  p_stage text default null,p_outcome text default null,p_country_code text default null,p_case_type text default null,p_limit integer default 100
) returns jsonb language sql set search_path=pg_catalog,security as $$
  select security.onboarding_cases_list_impl(p_stage,p_outcome,p_country_code,p_case_type,p_limit)
$$;
create or replace function public.onboarding_case_context(p_case_id uuid)
returns jsonb language sql set search_path=pg_catalog,security as $$ select security.onboarding_case_context_impl(p_case_id) $$;
create or replace function public.onboarding_case_create(
  p_case_type text,p_country_code text,p_title text,p_source_id uuid default null,p_source_profile_id uuid default null,
  p_provider_id uuid default null,p_course_id uuid default null,p_adapter_family text default null,p_reason text default null,
  p_change_control_ref text default 'CF-CHG-20260825-037',p_uat_ref text default null
) returns uuid language sql set search_path=pg_catalog,security as $$
  select security.onboarding_case_create_impl(p_case_type,p_country_code,p_title,p_source_id,p_source_profile_id,p_provider_id,p_course_id,p_adapter_family,p_reason,p_change_control_ref,p_uat_ref)
$$;
create or replace function public.onboarding_case_transition(
  p_case_id uuid,p_to_stage text,p_outcome text,p_reason text,p_details jsonb default '{}'::jsonb,p_evidence_id uuid default null,p_uat_ref text default null
) returns jsonb language sql set search_path=pg_catalog,security as $$
  select security.onboarding_case_transition_impl(p_case_id,p_to_stage,p_outcome,p_reason,p_details,p_evidence_id,p_uat_ref)
$$;
create or replace function public.onboarding_case_metadata_update(
  p_case_id uuid,p_adapter_family text default null,p_source_qualification jsonb default null,p_adapter_assessment jsonb default null,
  p_schema_assessment jsonb default null,p_operational_manifest jsonb default null,p_reason text default null,p_uat_ref text default null
) returns jsonb language sql set search_path=pg_catalog,security as $$
  select security.onboarding_case_metadata_update_impl(p_case_id,p_adapter_family,p_source_qualification,p_adapter_assessment,p_schema_assessment,p_operational_manifest,p_reason,p_uat_ref)
$$;

revoke all on function public.onboarding_cases_list(text,text,text,text,integer) from public,anon;
revoke all on function public.onboarding_case_context(uuid) from public,anon;
revoke all on function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) from public,anon;
revoke all on function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text) from public,anon;
revoke all on function public.onboarding_case_metadata_update(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) from public,anon;
grant execute on function public.onboarding_cases_list(text,text,text,text,integer) to authenticated,service_role;
grant execute on function public.onboarding_case_context(uuid) to authenticated,service_role;
grant execute on function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text) to authenticated,service_role;
grant execute on function public.onboarding_case_metadata_update(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) to authenticated,service_role;