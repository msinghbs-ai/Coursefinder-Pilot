create table if not exists pipeline.layer2_execution_policies (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references pipeline.layer2_source_profiles(id) on delete cascade,
  schedule_mode text not null default 'manual' check (schedule_mode in ('manual','daily','weekly','disabled')),
  scheduled_hour_utc smallint null check (scheduled_hour_utc between 0 and 23),
  batch_size integer not null default 10 check (batch_size between 1 and 500),
  routing_strategy text not null default 'direct_then_best_value' check (routing_strategy in ('direct_then_best_value','lowest_cost_proven','highest_success','manual_provider')),
  max_paid_attempts_per_entity smallint not null default 2 check (max_paid_attempts_per_entity between 0 and 5),
  max_vendor_units_per_entity numeric null check (max_vendor_units_per_entity is null or max_vendor_units_per_entity >= 0),
  max_cost_usd_per_entity numeric null check (max_cost_usd_per_entity is null or max_cost_usd_per_entity >= 0),
  auto_handoff_layer3 boolean not null default true,
  stop_on_identity_mismatch boolean not null default true,
  enabled boolean not null default true,
  next_run_at timestamptz null,
  last_run_at timestamptz null,
  updated_by uuid null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists pipeline.layer2_run_batches (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references pipeline.layer2_source_profiles(id),
  profile_version_id uuid not null references pipeline.layer2_source_profile_versions(id),
  trigger_type text not null default 'manual' check (trigger_type in ('manual','schedule','trial','resume')),
  status text not null default 'queued' check (status in ('queued','running','completed','partial','failed','cancelled')),
  requested_by uuid null,
  policy_snapshot jsonb not null default '{}'::jsonb,
  target_count integer not null default 0,
  processed_count integer not null default 0,
  resolved_l2_count integer not null default 0,
  escalated_l3_count integer not null default 0,
  blocked_count integer not null default 0,
  vendor_units numeric not null default 0,
  vendor_cost_usd numeric not null default 0,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now()
);

create table if not exists pipeline.layer2_run_items (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references pipeline.layer2_run_batches(id) on delete cascade,
  entity_type text not null check (entity_type in ('course','scholarship')),
  entity_id uuid null,
  source_url text null,
  status text not null default 'queued' check (status in ('queued','discovering','acquiring','extracting','resolved_l2','layer3_required','blocked','cancelled')),
  selected_provider_id uuid null references pipeline.layer2_acquisition_providers(id),
  job_id uuid null references pipeline.jobs(id),
  evidence_count integer not null default 0,
  fields_targeted integer not null default 0,
  fields_resolved integer not null default 0,
  vendor_units numeric not null default 0,
  vendor_cost_usd numeric not null default 0,
  blocker text null,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now()
);

alter table pipeline.layer2_provider_attempts
  add column if not exists runtime_platform text null,
  add column if not exists runtime_region text null,
  add column if not exists runtime_execution_id text null,
  add column if not exists runtime_deployment_id text null,
  add column if not exists egress_identity text null;

alter table pipeline.evidence_artifacts
  add column if not exists retention_class text,
  add column if not exists retain_until timestamptz,
  add column if not exists review_state text,
  add column if not exists capture_version integer,
  add column if not exists evidence_group_key text;

update pipeline.evidence_artifacts
set retention_class=coalesce(retention_class,case when coalesce(metadata->>'layer','')='2' then 'standard_365' else 'legacy' end),
    review_state=coalesce(review_state,'unreviewed')
where retention_class is null or review_state is null;

create index if not exists layer2_policy_schedule_idx on pipeline.layer2_execution_policies(enabled,schedule_mode,next_run_at);
create index if not exists layer2_batches_profile_created_idx on pipeline.layer2_run_batches(profile_id,created_at desc);
create index if not exists layer2_items_batch_status_idx on pipeline.layer2_run_items(batch_id,status,created_at);
create index if not exists layer2_evidence_review_idx on pipeline.evidence_artifacts(retention_class,review_state,captured_at desc) where retention_class is not null;
create index if not exists layer2_evidence_group_version_idx on pipeline.evidence_artifacts(evidence_group_key,capture_version desc) where evidence_group_key is not null;

alter table pipeline.layer2_execution_policies enable row level security;
alter table pipeline.layer2_run_batches enable row level security;
alter table pipeline.layer2_run_items enable row level security;
revoke all on pipeline.layer2_execution_policies,pipeline.layer2_run_batches,pipeline.layer2_run_items from anon,authenticated;
grant select,insert,update,delete on pipeline.layer2_execution_policies,pipeline.layer2_run_batches,pipeline.layer2_run_items to service_role;

do $$ begin
  insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,auto_handoff_layer3,stop_on_identity_mismatch)
  select p.id,'manual',10,'direct_then_best_value',2,true,true
  from pipeline.layer2_source_profiles p
  where p.enabled=true and p.domain in ('course_facts','scholarship')
  on conflict(profile_id) do nothing;
end $$;

create or replace function security.admin_layer2_ops_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','catalogue','ref','public'
as $$
declare v_rank integer; v_result jsonb;begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if p_operation='layer2_ops_overview' then
    select jsonb_build_object(
      'sources',(select coalesce(jsonb_agg(jsonb_build_object(
        'profile_id',p.id,'profile_key',p.profile_key,'country_code',c.iso_alpha2,'data_type',case when p.domain='course_facts' then 'Courses' else 'Scholarships' end,
        'source_label',s.label,'provider_name',cp.canonical_name,'enabled',p.enabled,'paused',p.paused,
        'schedule_mode',coalesce(ep.schedule_mode,'manual'),'batch_size',coalesce(ep.batch_size,10),'routing_strategy',coalesce(ep.routing_strategy,'direct_then_best_value'),
        'max_paid_attempts_per_entity',coalesce(ep.max_paid_attempts_per_entity,2),'next_run_at',ep.next_run_at,'last_run_at',ep.last_run_at,
        'current_version_id',p.current_version_id,'current_version',pv.version_no,'freshness_sla_hours',p.freshness_sla_hours,
        'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at
      ) order by c.iso_alpha2,case when p.domain='course_facts' then 1 else 2 end,coalesce(cp.canonical_name,s.label)),'[]'::jsonb)
      from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id left join ref.countries c on c.id=s.country_id left join catalogue.providers cp on cp.id=s.provider_id left join pipeline.layer2_execution_policies ep on ep.profile_id=p.id left join pipeline.layer2_source_profile_versions pv on pv.id=p.current_version_id where p.domain in ('course_facts','scholarship')),
      'providers',(select coalesce(jsonb_agg(jsonb_build_object('id',ap.id,'provider_key',ap.provider_key,'display_name',ap.display_name,'enabled',ap.enabled,'credential_configured',ap.vault_secret_id is not null,'priority',ap.priority,'rate_limit_per_minute',ap.rate_limit_per_minute,'concurrency',ap.concurrency,'last_tested_at',ap.last_tested_at,'last_test_status',ap.last_test_status,'billing_config',security.layer2_provider_sanitise_json(ap.billing_config)) order by ap.priority,ap.display_name),'[]'::jsonb) from pipeline.layer2_acquisition_providers ap where ap.enabled=true),
      'recent_runs',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'profile_id',b.profile_id,'trigger_type',b.trigger_type,'status',b.status,'target_count',b.target_count,'processed_count',b.processed_count,'resolved_l2_count',b.resolved_l2_count,'escalated_l3_count',b.escalated_l3_count,'blocked_count',b.blocked_count,'vendor_units',b.vendor_units,'vendor_cost_usd',b.vendor_cost_usd,'created_at',b.created_at,'started_at',b.started_at,'completed_at',b.completed_at) order by b.created_at desc),'[]'::jsonb) from (select * from pipeline.layer2_run_batches order by created_at desc limit 20)b),
      'evidence_summary',(select jsonb_build_object('count',count(*),'unreviewed',count(*) filter(where review_state='unreviewed'),'retained_until_365',count(*) filter(where retention_class='standard_365'),'held',count(*) filter(where retention_class='hold'),'latest',max(captured_at)) from pipeline.evidence_artifacts where coalesce(metadata->>'layer','')='2')
    ) into v_result;
    return v_result;
  end if;
  if p_operation='layer2_ops_run_detail' then
    return (select jsonb_build_object('run',to_jsonb(b),'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from pipeline.layer2_run_items i where i.batch_id=b.id)) from pipeline.layer2_run_batches b where b.id=nullif(p_args->>'id','')::uuid);
  end if;
  raise exception 'unsupported layer2 ops read operation: %',p_operation using errcode='22023';
end$$;
revoke all on function security.admin_layer2_ops_read(text,jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer2_ops_read(text,jsonb) to authenticated;

create or replace function public.layer2_ops_policy_update(p_actor uuid,p_profile_id uuid,p_patch jsonb)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline'
as $$
declare v_rank integer:=0; v_row pipeline.layer2_execution_policies%rowtype;begin
  if p_actor is null or p_actor<>auth.uid() then raise exception 'actor mismatch' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
  if not exists(select 1 from pipeline.layer2_source_profiles where id=p_profile_id and domain in ('course_facts','scholarship')) then raise exception 'layer2 enrichment profile required' using errcode='22023'; end if;
  insert into pipeline.layer2_execution_policies(profile_id) values(p_profile_id) on conflict(profile_id) do nothing;
  update pipeline.layer2_execution_policies set
    schedule_mode=coalesce(nullif(p_patch->>'schedule_mode',''),schedule_mode),
    scheduled_hour_utc=case when p_patch ? 'scheduled_hour_utc' then nullif(p_patch->>'scheduled_hour_utc','')::smallint else scheduled_hour_utc end,
    batch_size=case when p_patch ? 'batch_size' then (p_patch->>'batch_size')::integer else batch_size end,
    routing_strategy=coalesce(nullif(p_patch->>'routing_strategy',''),routing_strategy),
    max_paid_attempts_per_entity=case when p_patch ? 'max_paid_attempts_per_entity' then (p_patch->>'max_paid_attempts_per_entity')::smallint else max_paid_attempts_per_entity end,
    max_vendor_units_per_entity=case when p_patch ? 'max_vendor_units_per_entity' then nullif(p_patch->>'max_vendor_units_per_entity','')::numeric else max_vendor_units_per_entity end,
    max_cost_usd_per_entity=case when p_patch ? 'max_cost_usd_per_entity' then nullif(p_patch->>'max_cost_usd_per_entity','')::numeric else max_cost_usd_per_entity end,
    auto_handoff_layer3=case when p_patch ? 'auto_handoff_layer3' then (p_patch->>'auto_handoff_layer3')::boolean else auto_handoff_layer3 end,
    stop_on_identity_mismatch=case when p_patch ? 'stop_on_identity_mismatch' then (p_patch->>'stop_on_identity_mismatch')::boolean else stop_on_identity_mismatch end,
    updated_by=p_actor,updated_at=now()
  where profile_id=p_profile_id returning * into v_row;
  return jsonb_build_object('ok',true,'policy',to_jsonb(v_row));
end$$;
revoke all on function public.layer2_ops_policy_update(uuid,uuid,jsonb) from public,anon;
grant execute on function public.layer2_ops_policy_update(uuid,uuid,jsonb) to authenticated;

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable set search_path='pg_catalog','public','security' as $$
declare v_result jsonb;v_id uuid;begin
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation in ('layer2_ops_overview','layer2_ops_run_detail') then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id);end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end$$;
