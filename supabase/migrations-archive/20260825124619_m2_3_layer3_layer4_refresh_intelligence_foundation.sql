-- M2.3 Layer 3 / Layer 4 / Refresh Intelligence foundation
-- Change Control: CF-CHG-20260825-038

create table if not exists pipeline.layer3_model_profiles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  aggregator_provider text not null,
  base_url text not null check (base_url ~* '^https://'),
  model_identifier text not null,
  secret_env_key text not null,
  allowed_task_classes text[] not null default '{}'::text[],
  prompt_profile_version text not null,
  prompt_system text not null,
  structured_output_schema jsonb not null default '{}'::jsonb,
  deterministic_validators jsonb not null default '{}'::jsonb,
  max_input_tokens integer not null check (max_input_tokens between 128 and 2000000),
  max_output_tokens integer not null check (max_output_tokens between 32 and 200000),
  requests_per_minute integer not null check (requests_per_minute between 1 and 100000),
  requests_per_day integer not null check (requests_per_day between 1 and 10000000),
  retry_ceiling integer not null default 1 check (retry_ceiling between 0 and 10),
  timeout_ms integer not null default 30000 check (timeout_ms between 1000 and 180000),
  fallback_profile_id uuid references pipeline.layer3_model_profiles(id),
  cost_ceiling_usd numeric(12,6) not null default 0 check (cost_ceiling_usd >= 0),
  enabled boolean not null default true,
  paused boolean not null default true,
  last_validation_result jsonb,
  quality_benchmark jsonb,
  change_control_ref text not null,
  uat_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (fallback_profile_id is null or fallback_profile_id <> id)
);

insert into pipeline.layer3_model_profiles(
  code, aggregator_provider, base_url, model_identifier, secret_env_key,
  allowed_task_classes, prompt_profile_version, prompt_system,
  structured_output_schema, deterministic_validators,
  max_input_tokens, max_output_tokens, requests_per_minute, requests_per_day,
  retry_ceiling, timeout_ms, cost_ceiling_usd, enabled, paused,
  last_validation_result, change_control_ref, uat_ref
) values (
  'openrouter-free-router-v1','openrouter','https://openrouter.ai/api/v1','openrouter/free','OPENROUTER_API_KEY',
  array['course_description','official_course_url','delivery_mode','duration'],
  'm2.3-evidence-interpretation-v1',
  'Interpret only the supplied governed evidence. Return JSON only. Never redefine regulatory identity. If evidence is insufficient, set candidate_value to null and explain why.',
  jsonb_build_object('type','object','required',jsonb_build_array('candidate_value','confidence','rationale','evidence_quotes')),
  jsonb_build_object('candidate_required',false,'confidence_min',0,'confidence_max',1,'max_rationale_chars',1600,'max_quote_chars',600,'max_quotes',4),
  12000,1200,20,50,1,30000,0,true,true,
  jsonb_build_object('state','pending_credentials_and_benchmark','validated',false),
  'CF-CHG-20260825-038','pending-live-provider-uat'
) on conflict (code) do update set
  aggregator_provider=excluded.aggregator_provider,
  base_url=excluded.base_url,
  model_identifier=excluded.model_identifier,
  secret_env_key=excluded.secret_env_key,
  allowed_task_classes=excluded.allowed_task_classes,
  prompt_profile_version=excluded.prompt_profile_version,
  structured_output_schema=excluded.structured_output_schema,
  deterministic_validators=excluded.deterministic_validators,
  max_input_tokens=excluded.max_input_tokens,
  max_output_tokens=excluded.max_output_tokens,
  requests_per_minute=excluded.requests_per_minute,
  requests_per_day=excluded.requests_per_day,
  retry_ceiling=excluded.retry_ceiling,
  timeout_ms=excluded.timeout_ms,
  cost_ceiling_usd=excluded.cost_ceiling_usd,
  change_control_ref=excluded.change_control_ref,
  updated_at=now();

create table if not exists pipeline.layer3_interpretations (
  id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  evidence_hash text not null,
  entity_type text not null,
  entity_id uuid not null,
  task_class text not null,
  profile_id uuid not null references pipeline.layer3_model_profiles(id),
  prompt_profile_version text not null,
  eligibility_reason text not null check (eligibility_reason in ('new_evidence','changed_evidence','layer2_unresolved','freshness_expired','governed_revalidation')),
  revalidation_ref text,
  status text not null default 'reserved' check (status in ('reserved','calling','validated','rejected_validation','provider_error','cancelled','no_candidate')),
  layer2_state jsonb not null default '{}'::jsonb,
  raw_result jsonb,
  candidate_value jsonb,
  confidence numeric,
  rationale text,
  evidence_quotes jsonb not null default '[]'::jsonb,
  validator_result jsonb,
  aggregator_response_model text,
  input_tokens integer,
  output_tokens integer,
  estimated_cost_usd numeric(12,6) not null default 0,
  call_started_at timestamptz,
  call_completed_at timestamptz,
  interpretation_expires_at timestamptz,
  requested_by uuid,
  change_control_ref text not null default 'CF-CHG-20260825-038',
  uat_ref text,
  created_at timestamptz not null default now()
);
create index if not exists layer3_interpretations_entity_task_created_idx on pipeline.layer3_interpretations(entity_type,entity_id,task_class,created_at desc);
create index if not exists layer3_interpretations_evidence_profile_idx on pipeline.layer3_interpretations(evidence_id,profile_id,task_class,created_at desc);
create index if not exists layer3_interpretations_status_idx on pipeline.layer3_interpretations(status,created_at desc);

create table if not exists pipeline.layer4_review_items (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  field_code text not null,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  layer3_interpretation_id uuid references pipeline.layer3_interpretations(id),
  before_value jsonb,
  proposed_value jsonb,
  layer2_state jsonb not null default '{}'::jsonb,
  layer3_state jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','edited_approved','rejected','more_evidence','returned_layer2','returned_layer3','superseded')),
  assigned_to uuid,
  escalation_reason text,
  change_control_ref text not null default 'CF-CHG-20260825-038',
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists layer4_review_items_status_created_idx on pipeline.layer4_review_items(status,created_at desc);
create unique index if not exists layer4_review_pending_interpretation_uq on pipeline.layer4_review_items(layer3_interpretation_id) where layer3_interpretation_id is not null and status='pending';

create table if not exists pipeline.layer4_decisions (
  id uuid primary key default gen_random_uuid(),
  review_item_id uuid not null references pipeline.layer4_review_items(id),
  action text not null check (action in ('approve','edit_and_approve','reject','request_more_evidence','return_layer2','return_layer3')),
  actor_id uuid not null,
  reason text not null,
  before_value jsonb,
  proposed_value jsonb,
  final_value jsonb,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  layer2_state jsonb not null default '{}'::jsonb,
  layer3_state jsonb not null default '{}'::jsonb,
  scalar_resolution_id uuid references pipeline.layer4_course_field_resolutions(id),
  change_control_ref text not null,
  created_at timestamptz not null default now()
);
create index if not exists layer4_decisions_review_created_idx on pipeline.layer4_decisions(review_item_id,created_at desc);

create table if not exists pipeline.refresh_policies (
  id uuid primary key default gen_random_uuid(),
  country_code text,
  layer smallint not null check (layer between 1 and 4),
  source_profile_id uuid,
  entity_type text,
  entity_id uuid,
  freshness_class text not null check (freshness_class in ('critical','weekly','monthly','term-cycle','annual','event-driven')),
  cadence_interval interval,
  next_due_at timestamptz,
  hash_sensitive boolean not null default true,
  important_date_sensitive boolean not null default false,
  enabled boolean not null default true,
  change_control_ref text not null,
  updated_at timestamptz not null default now(),
  check (source_profile_id is not null or entity_id is not null or (layer=4 and freshness_class='event-driven'))
);
create index if not exists refresh_policies_due_idx on pipeline.refresh_policies(enabled,next_due_at) where enabled;

create table if not exists pipeline.refresh_requests (
  id uuid primary key default gen_random_uuid(),
  requested_layer smallint not null check (requested_layer between 1 and 4),
  country_code text,
  source_profile_id uuid,
  entity_type text,
  entity_id uuid,
  reason text not null,
  trigger_type text not null check (trigger_type in ('source_hash_changed','freshness_expired','important_date','upstream_accepted','manual_governed','layer4_return')),
  important_date_id uuid,
  status text not null default 'queued' check (status in ('queued','running','completed','cancelled','blocked')),
  requested_by uuid,
  change_control_ref text not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (source_profile_id is not null or entity_id is not null)
);
create index if not exists refresh_requests_status_created_idx on pipeline.refresh_requests(status,created_at desc);

create table if not exists pipeline.important_links (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  authority_category text not null check (authority_category in ('regulatory_authority','international_student_immigration','quality_outcomes','official_scholarship','qualification_framework','statistics_data','accepted_provider_course_source','source_health','official_policy_change')),
  authority_name text not null,
  owner_label text not null,
  url text not null check (url ~* '^https?://'),
  purpose text not null,
  related_layer smallint check (related_layer between 1 and 4),
  related_source_profile_id uuid,
  last_verified_at timestamptz,
  verification_cadence interval not null default interval '90 days',
  next_verification_at timestamptz,
  health_status text not null default 'unverified' check (health_status in ('healthy','degraded','blocked','unverified','retired')),
  change_control_ref text not null,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(country_code,url)
);
create index if not exists important_links_country_category_idx on pipeline.important_links(country_code,authority_category,health_status);

create table if not exists pipeline.important_dates (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  event_type text not null check (event_type in ('course_application_deadline','intake_date','scholarship_window','regulatory_dataset_release','provider_application_window','national_education_event')),
  title text not null,
  source_url text not null check (source_url ~* '^https?://'),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  scope_type text not null check (scope_type in ('source','provider','course','scholarship','country_reference')),
  source_profile_id uuid,
  entity_type text,
  entity_id uuid,
  date_precision text not null check (date_precision in ('exact','date_range','month','term','year','source_vague')),
  starts_at timestamptz,
  ends_at timestamptz,
  timezone text,
  source_wording text,
  warning_window interval not null default interval '14 days',
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','expired','cancelled','unverified')),
  refresh_layer smallint check (refresh_layer between 1 and 4),
  change_control_ref text not null,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (date_precision <> 'exact' or starts_at is not null),
  check (date_precision <> 'source_vague' or source_wording is not null),
  check (scope_type='country_reference' or source_profile_id is not null or entity_id is not null)
);
create index if not exists important_dates_ticker_idx on pipeline.important_dates(status,starts_at) where status='active';

alter table pipeline.refresh_requests add constraint refresh_requests_important_date_fk foreign key (important_date_id) references pipeline.important_dates(id) not valid;
alter table pipeline.refresh_requests validate constraint refresh_requests_important_date_fk;

-- Keep private pipeline tables private. All browser access is through role-checked RPC/Edge boundaries.
revoke all on pipeline.layer3_model_profiles, pipeline.layer3_interpretations, pipeline.layer4_review_items, pipeline.layer4_decisions, pipeline.refresh_policies, pipeline.refresh_requests, pipeline.important_links, pipeline.important_dates from public, anon, authenticated;

create or replace function public.layer3_model_profiles_admin()
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,security,pipeline,auth as $$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'code',code,'aggregator_provider',aggregator_provider,'base_url',base_url,'model_identifier',model_identifier,
    'allowed_task_classes',allowed_task_classes,'prompt_profile_version',prompt_profile_version,'structured_output_schema',structured_output_schema,
    'deterministic_validators',deterministic_validators,'max_input_tokens',max_input_tokens,'max_output_tokens',max_output_tokens,
    'requests_per_minute',requests_per_minute,'requests_per_day',requests_per_day,'retry_ceiling',retry_ceiling,'timeout_ms',timeout_ms,
    'fallback_profile_id',fallback_profile_id,'cost_ceiling_usd',cost_ceiling_usd,'enabled',enabled,'paused',paused,
    'last_validation_result',last_validation_result,'quality_benchmark',quality_benchmark,'change_control_ref',change_control_ref,'uat_ref',uat_ref,
    'updated_at',updated_at
  ) order by code) from pipeline.layer3_model_profiles),'[]'::jsonb);
end $$;

create or replace function public.layer3_model_profile_set_state(p_profile_id uuid,p_enabled boolean,p_paused boolean,p_reason text)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,security,pipeline,auth as $$
begin
  if auth.uid() is null or security.current_role_rank()<4 then raise exception 'administrator role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'governance reason required'; end if;
  update pipeline.layer3_model_profiles set enabled=p_enabled,paused=p_paused,
    last_validation_result=coalesce(last_validation_result,'{}'::jsonb)||jsonb_build_object('state_change_reason',trim(p_reason),'state_changed_at',now(),'state_changed_by',auth.uid()),
    updated_at=now() where id=p_profile_id;
  if not found then raise exception 'profile not found'; end if;
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'enabled',p_enabled,'paused',p_paused);
end $$;

create or replace function public.layer3_reserve_interpretation_service(
  p_actor uuid,p_evidence_id uuid,p_entity_type text,p_entity_id uuid,p_task_class text,p_profile_id uuid,
  p_layer2_state jsonb default '{}'::jsonb,p_revalidation_ref text default null
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,security,pipeline as $$
declare v_rank int:=0; v_ev pipeline.evidence_artifacts%rowtype; v_p pipeline.layer3_model_profiles%rowtype; v_prev pipeline.layer3_interpretations%rowtype; v_reason text; v_id uuid;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and r.status='active' and (ur.expires_at is null or ur.expires_at>now());
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  select * into v_ev from pipeline.evidence_artifacts where id=p_evidence_id;
  if not found or v_ev.content_hash is null then raise exception 'governed evidence with content hash required'; end if;
  select * into v_p from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'model profile not found'; end if;
  if not v_p.enabled or v_p.paused then raise exception 'model profile not executable'; end if;
  if not (p_task_class=any(v_p.allowed_task_classes)) then raise exception 'task class not allowed by profile'; end if;
  perform pg_advisory_xact_lock(hashtext(p_evidence_id::text||':'||p_entity_id::text||':'||p_task_class||':'||p_profile_id::text));
  select * into v_prev from pipeline.layer3_interpretations where entity_type=lower(p_entity_type) and entity_id=p_entity_id and task_class=p_task_class and profile_id=p_profile_id and status in ('validated','no_candidate') order by created_at desc limit 1;
  if p_revalidation_ref is not null then
    if length(trim(p_revalidation_ref))<5 then raise exception 'governed revalidation reference required'; end if;
    v_reason:='governed_revalidation';
  elsif found and v_prev.evidence_hash=v_ev.content_hash and (v_prev.interpretation_expires_at is null or v_prev.interpretation_expires_at>now()) then
    return jsonb_build_object('call_required',false,'reason','unchanged_evidence','prior_interpretation_id',v_prev.id,'evidence_hash',v_ev.content_hash);
  elsif found and v_prev.evidence_hash<>v_ev.content_hash then v_reason:='changed_evidence';
  elsif found and v_prev.interpretation_expires_at is not null and v_prev.interpretation_expires_at<=now() then v_reason:='freshness_expired';
  elsif coalesce(p_layer2_state->>'status','') in ('unresolved','blocked','partial','escalated_l3') then v_reason:='layer2_unresolved';
  else v_reason:='new_evidence'; end if;
  insert into pipeline.layer3_interpretations(evidence_id,evidence_hash,entity_type,entity_id,task_class,profile_id,prompt_profile_version,eligibility_reason,revalidation_ref,layer2_state,requested_by)
  values(p_evidence_id,v_ev.content_hash,lower(p_entity_type),p_entity_id,p_task_class,p_profile_id,v_p.prompt_profile_version,v_reason,p_revalidation_ref,coalesce(p_layer2_state,'{}'::jsonb),p_actor) returning id into v_id;
  return jsonb_build_object('call_required',true,'interpretation_id',v_id,'eligibility_reason',v_reason,'evidence_hash',v_ev.content_hash,
    'profile',jsonb_build_object('id',v_p.id,'aggregator_provider',v_p.aggregator_provider,'base_url',v_p.base_url,'model_identifier',v_p.model_identifier,'secret_env_key',v_p.secret_env_key,'prompt_profile_version',v_p.prompt_profile_version,'prompt_system',v_p.prompt_system,'schema',v_p.structured_output_schema,'validators',v_p.deterministic_validators,'max_input_tokens',v_p.max_input_tokens,'max_output_tokens',v_p.max_output_tokens,'requests_per_minute',v_p.requests_per_minute,'requests_per_day',v_p.requests_per_day,'retry_ceiling',v_p.retry_ceiling,'timeout_ms',v_p.timeout_ms,'cost_ceiling_usd',v_p.cost_ceiling_usd,'fallback_profile_id',v_p.fallback_profile_id));
end $$;

create or replace function public.layer3_complete_interpretation_service(
  p_interpretation_id uuid,p_raw_result jsonb,p_candidate_value jsonb,p_confidence numeric,p_rationale text,p_evidence_quotes jsonb,
  p_validator_result jsonb,p_valid boolean,p_response_model text,p_input_tokens integer,p_output_tokens integer,p_estimated_cost_usd numeric,p_expiry timestamptz
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,pipeline,catalogue as $$
declare v_i pipeline.layer3_interpretations%rowtype; v_review uuid; v_before jsonb;
begin
  select * into v_i from pipeline.layer3_interpretations where id=p_interpretation_id for update;
  if not found then raise exception 'interpretation not found'; end if;
  if v_i.status not in ('reserved','calling') then raise exception 'interpretation is not completable'; end if;
  if p_estimated_cost_usd<0 then raise exception 'invalid cost'; end if;
  update pipeline.layer3_interpretations set raw_result=p_raw_result,candidate_value=p_candidate_value,confidence=p_confidence,rationale=p_rationale,
    evidence_quotes=coalesce(p_evidence_quotes,'[]'::jsonb),validator_result=coalesce(p_validator_result,'{}'::jsonb),
    status=case when not p_valid then 'rejected_validation' when p_candidate_value is null or p_candidate_value='null'::jsonb then 'no_candidate' else 'validated' end,
    aggregator_response_model=p_response_model,input_tokens=p_input_tokens,output_tokens=p_output_tokens,estimated_cost_usd=coalesce(p_estimated_cost_usd,0),call_completed_at=now(),interpretation_expires_at=p_expiry
  where id=p_interpretation_id;
  if p_valid and p_candidate_value is not null and p_candidate_value<>'null'::jsonb then
    if v_i.entity_type='course' then
      if v_i.task_class='course_description' then select to_jsonb(description) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='delivery_mode' then select to_jsonb(delivery_mode) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='duration' then select jsonb_build_object('value',duration_value,'unit',duration_unit) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='official_course_url' then select to_jsonb(url) into v_before from catalogue.course_links where course_id=v_i.entity_id and link_type='official_course' and coalesce(status,'active')='active' order by last_verified_at desc nulls last,created_at desc limit 1;
      end if;
    end if;
    insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,proposed_value,layer2_state,layer3_state,escalation_reason)
    values(v_i.entity_type,v_i.entity_id,v_i.task_class,v_i.evidence_id,v_i.id,v_before,p_candidate_value,v_i.layer2_state,
      jsonb_build_object('profile_id',v_i.profile_id,'prompt_profile_version',v_i.prompt_profile_version,'candidate_value',p_candidate_value,'confidence',p_confidence,'rationale',p_rationale,'validator_result',p_validator_result,'response_model',p_response_model),'validated Layer 3 candidate requires human decision') returning id into v_review;
  end if;
  return jsonb_build_object('ok',true,'interpretation_id',p_interpretation_id,'validated',p_valid,'review_item_id',v_review);
end $$;

create or replace function public.layer3_fail_interpretation_service(p_interpretation_id uuid,p_error text)
returns void language plpgsql security definer set search_path=pg_catalog,pipeline as $$
begin update pipeline.layer3_interpretations set status='provider_error',validator_result=jsonb_build_object('provider_error',left(coalesce(p_error,'unknown'),2000)),call_completed_at=now() where id=p_interpretation_id and status in ('reserved','calling'); end $$;

create or replace function public.layer3_usage_window_service(p_profile_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,pipeline as $$
select jsonb_build_object(
 'minute_calls',(select count(*) from pipeline.layer3_interpretations where profile_id=p_profile_id and created_at>=now()-interval '1 minute' and status<>'cancelled'),
 'day_calls',(select count(*) from pipeline.layer3_interpretations where profile_id=p_profile_id and created_at>=date_trunc('day',now()) and status<>'cancelled'),
 'day_cost_usd',(select coalesce(sum(estimated_cost_usd),0) from pipeline.layer3_interpretations where profile_id=p_profile_id and created_at>=date_trunc('day',now()))
) $$;

create or replace function public.layer4_review_queue(p_status text default 'pending',p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,security,pipeline,auth as $$
begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,proposed_value,layer2_state,layer3_state,status,assigned_to,escalation_reason,change_control_ref,created_at,decided_at from pipeline.layer4_review_items where status=coalesce(p_status,status) order by created_at desc limit least(greatest(p_limit,1),250)) x),'[]'::jsonb);
end $$;

create or replace function public.layer4_review_decide(p_review_item_id uuid,p_action text,p_reason text,p_final_value jsonb default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$
declare v_actor uuid:=auth.uid(); v_rank int; v_item pipeline.layer4_review_items%rowtype; v_final jsonb; v_state text; v_scalar jsonb; v_scalar_id uuid; v_decision uuid;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 if p_action not in ('approve','edit_and_approve','reject','request_more_evidence','return_layer2','return_layer3') then raise exception 'invalid action'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'decision reason required'; end if;
 select * into v_item from pipeline.layer4_review_items where id=p_review_item_id for update;
 if not found then raise exception 'review item not found'; end if;
 if v_item.status<>'pending' then raise exception 'review item already decided'; end if;
 v_final:=case when p_action='approve' then v_item.proposed_value when p_action='edit_and_approve' then p_final_value else null end;
 if p_action='edit_and_approve' and p_final_value is null then raise exception 'edited final value required'; end if;
 if p_action in ('approve','edit_and_approve') then
   if v_item.entity_type<>'course' then raise exception 'terminal apply currently supports course scalar facts only'; end if;
   v_scalar:=security.layer4_course_scalar_resolve_impl(v_actor,v_item.entity_id,v_item.field_code,v_final,trim(p_reason));
   v_scalar_id:=nullif(v_scalar->>'resolution_id','')::uuid;
   v_state:=case when p_action='approve' then 'approved' else 'edited_approved' end;
 elsif p_action='reject' then v_state:='rejected';
 elsif p_action='request_more_evidence' then v_state:='more_evidence';
 elsif p_action='return_layer2' then v_state:='returned_layer2';
 else v_state:='returned_layer3'; end if;
 update pipeline.layer4_review_items set status=v_state,decided_at=now() where id=v_item.id;
 insert into pipeline.layer4_decisions(review_item_id,action,actor_id,reason,before_value,proposed_value,final_value,evidence_id,layer2_state,layer3_state,scalar_resolution_id,change_control_ref)
 values(v_item.id,p_action,v_actor,trim(p_reason),v_item.before_value,v_item.proposed_value,v_final,v_item.evidence_id,v_item.layer2_state,v_item.layer3_state,v_scalar_id,v_item.change_control_ref) returning id into v_decision;
 if p_action='return_layer2' then insert into pipeline.refresh_requests(requested_layer,entity_type,entity_id,reason,trigger_type,requested_by,change_control_ref) values(2,v_item.entity_type,v_item.entity_id,trim(p_reason),'layer4_return',v_actor,v_item.change_control_ref); end if;
 return jsonb_build_object('ok',true,'decision_id',v_decision,'review_item_id',v_item.id,'action',p_action,'status',v_state,'final_value',v_final,'scalar_resolution_id',v_scalar_id,'publication_changed',false,'search_refresh_required',p_action in ('approve','edit_and_approve'));
end $$;

create or replace function public.important_links_list(p_country_code text default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,security,pipeline,auth as $$ begin
 if auth.uid() is null or security.current_role_rank()<2 then raise exception 'authenticated operator role required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.country_code,x.authority_category,x.authority_name) from (select id,country_code,authority_category,authority_name,owner_label,url,purpose,related_layer,related_source_profile_id,last_verified_at,verification_cadence,next_verification_at,health_status,change_control_ref,updated_at from pipeline.important_links where p_country_code is null or country_code=upper(p_country_code)) x),'[]'::jsonb); end $$;

create or replace function public.important_link_upsert(p_id uuid,p_country_code text,p_authority_category text,p_authority_name text,p_owner_label text,p_url text,p_purpose text,p_related_layer smallint,p_related_source_profile_id uuid,p_verification_days integer,p_health_status text)
returns uuid language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$ declare v_id uuid:=coalesce(p_id,gen_random_uuid()); begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 if p_verification_days not between 1 and 730 then raise exception 'verification cadence days must be 1..730'; end if;
 insert into pipeline.important_links(id,country_code,authority_category,authority_name,owner_label,url,purpose,related_layer,related_source_profile_id,verification_cadence,next_verification_at,health_status,change_control_ref,created_by,updated_by)
 values(v_id,upper(p_country_code),p_authority_category,trim(p_authority_name),trim(p_owner_label),trim(p_url),trim(p_purpose),p_related_layer,p_related_source_profile_id,make_interval(days=>p_verification_days),now()+make_interval(days=>p_verification_days),p_health_status,'CF-CHG-20260825-038',auth.uid(),auth.uid())
 on conflict(id) do update set country_code=excluded.country_code,authority_category=excluded.authority_category,authority_name=excluded.authority_name,owner_label=excluded.owner_label,url=excluded.url,purpose=excluded.purpose,related_layer=excluded.related_layer,related_source_profile_id=excluded.related_source_profile_id,verification_cadence=excluded.verification_cadence,health_status=excluded.health_status,updated_by=auth.uid(),updated_at=now(); return v_id; end $$;

create or replace function public.important_dates_ticker(p_country_code text default null,p_days integer default 60)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,security,pipeline,auth as $$ begin
 if auth.uid() is null or security.current_role_rank()<2 then raise exception 'authenticated operator role required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at nulls last,x.title) from (select id,country_code,event_type,title,source_url,evidence_id,scope_type,source_profile_id,entity_type,entity_id,date_precision,starts_at,ends_at,timezone,source_wording,warning_window,expires_at,status,refresh_layer,change_control_ref from pipeline.important_dates where status='active' and (p_country_code is null or country_code=upper(p_country_code)) and (starts_at is null or starts_at<=now()+make_interval(days=>least(greatest(p_days,1),365)))) x),'[]'::jsonb); end $$;

create or replace function public.important_date_upsert(p_id uuid,p_country_code text,p_event_type text,p_title text,p_source_url text,p_evidence_id uuid,p_scope_type text,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,p_date_precision text,p_starts_at timestamptz,p_ends_at timestamptz,p_timezone text,p_source_wording text,p_warning_days integer,p_expires_at timestamptz,p_refresh_layer smallint)
returns uuid language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$ declare v_id uuid:=coalesce(p_id,gen_random_uuid()); begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 if p_warning_days not between 0 and 365 then raise exception 'warning days must be 0..365'; end if;
 if p_date_precision='exact' and p_starts_at is null then raise exception 'exact dates require a sourced timestamp'; end if;
 if p_date_precision='source_vague' and nullif(trim(coalesce(p_source_wording,'')),'') is null then raise exception 'vague source wording must be retained'; end if;
 insert into pipeline.important_dates(id,country_code,event_type,title,source_url,evidence_id,scope_type,source_profile_id,entity_type,entity_id,date_precision,starts_at,ends_at,timezone,source_wording,warning_window,expires_at,status,refresh_layer,change_control_ref,created_by,updated_by)
 values(v_id,upper(p_country_code),p_event_type,trim(p_title),trim(p_source_url),p_evidence_id,p_scope_type,p_source_profile_id,p_entity_type,p_entity_id,p_date_precision,p_starts_at,p_ends_at,p_timezone,p_source_wording,make_interval(days=>p_warning_days),p_expires_at,'active',p_refresh_layer,'CF-CHG-20260825-038',auth.uid(),auth.uid())
 on conflict(id) do update set country_code=excluded.country_code,event_type=excluded.event_type,title=excluded.title,source_url=excluded.source_url,evidence_id=excluded.evidence_id,scope_type=excluded.scope_type,source_profile_id=excluded.source_profile_id,entity_type=excluded.entity_type,entity_id=excluded.entity_id,date_precision=excluded.date_precision,starts_at=excluded.starts_at,ends_at=excluded.ends_at,timezone=excluded.timezone,source_wording=excluded.source_wording,warning_window=excluded.warning_window,expires_at=excluded.expires_at,refresh_layer=excluded.refresh_layer,updated_by=auth.uid(),updated_at=now(); return v_id; end $$;

create or replace function public.important_date_queue_targeted_refresh(p_important_date_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$ declare v_d pipeline.important_dates%rowtype; v_id uuid; begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'refresh reason required'; end if;
 select * into v_d from pipeline.important_dates where id=p_important_date_id and status='active'; if not found then raise exception 'active important date not found'; end if;
 if v_d.refresh_layer is null then raise exception 'important date has no governed refresh layer'; end if;
 if v_d.source_profile_id is null and v_d.entity_id is null then raise exception 'country-wide important date cannot trigger ingestion'; end if;
 insert into pipeline.refresh_requests(requested_layer,country_code,source_profile_id,entity_type,entity_id,reason,trigger_type,important_date_id,requested_by,change_control_ref)
 values(v_d.refresh_layer,v_d.country_code,v_d.source_profile_id,v_d.entity_type,v_d.entity_id,trim(p_reason),'important_date',v_d.id,auth.uid(),v_d.change_control_ref) returning id into v_id; return v_id; end $$;

-- Explicit execution ACLs. Service functions are Edge/service-role only; admin reads/writes are authenticated and self-authorising.
do $$ declare r record; begin
 for r in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('layer3_model_profiles_admin','layer3_model_profile_set_state','layer3_reserve_interpretation_service','layer3_complete_interpretation_service','layer3_fail_interpretation_service','layer3_usage_window_service','layer4_review_queue','layer4_review_decide','important_links_list','important_link_upsert','important_dates_ticker','important_date_upsert','important_date_queue_targeted_refresh') loop execute format('revoke all on function %I.%I(%s) from public,anon,authenticated',r.nspname,r.proname,r.args); end loop; end $$;
grant execute on function public.layer3_model_profiles_admin() to authenticated;
grant execute on function public.layer3_model_profile_set_state(uuid,boolean,boolean,text) to authenticated;
grant execute on function public.layer4_review_queue(text,integer) to authenticated;
grant execute on function public.layer4_review_decide(uuid,text,text,jsonb) to authenticated;
grant execute on function public.important_links_list(text) to authenticated;
grant execute on function public.important_link_upsert(uuid,text,text,text,text,text,text,smallint,uuid,integer,text) to authenticated;
grant execute on function public.important_dates_ticker(text,integer) to authenticated;
grant execute on function public.important_date_upsert(uuid,text,text,text,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,text,integer,timestamptz,smallint) to authenticated;
grant execute on function public.important_date_queue_targeted_refresh(uuid,text) to authenticated;
grant execute on function public.layer3_reserve_interpretation_service(uuid,uuid,text,uuid,text,uuid,jsonb,text) to service_role;
grant execute on function public.layer3_complete_interpretation_service(uuid,jsonb,jsonb,numeric,text,jsonb,jsonb,boolean,text,integer,integer,numeric,timestamptz) to service_role;
grant execute on function public.layer3_fail_interpretation_service(uuid,text) to service_role;
grant execute on function public.layer3_usage_window_service(uuid) to service_role;
