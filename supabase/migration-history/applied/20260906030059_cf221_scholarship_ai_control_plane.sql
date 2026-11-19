create table if not exists pipeline.scholarship_ai_settings(
  country_code text primary key,
  enabled boolean not null default false,
  schedule_on_change boolean not null default true,
  default_task_class text not null default 'scholarship_page_classification',
  default_profile_id uuid null references pipeline.layer3_model_profiles(id),
  max_records_per_run integer not null default 25 check(max_records_per_run between 1 and 200),
  daily_budget_usd numeric not null default 1.00 check(daily_budget_usd>=0),
  schedule_actor uuid null,
  updated_by uuid null,
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
alter table pipeline.scholarship_ai_settings enable row level security;

create table if not exists pipeline.scholarship_ai_runs(
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  scope_type text not null default 'country',
  provider_id uuid null,
  task_class text not null,
  profile_id uuid not null references pipeline.layer3_model_profiles(id),
  trigger_mode text not null default 'manual' check(trigger_mode in ('manual','scheduled','benchmark')),
  changes_only boolean not null default true,
  requested_limit integer not null,
  requested_by uuid null,
  status text not null default 'queued' check(status in ('queued','running','completed','completed_with_errors','failed','cancelled')),
  total_items integer not null default 0,
  processed_items integer not null default 0,
  validated_items integer not null default 0,
  review_items integer not null default 0,
  no_candidate_items integer not null default 0,
  failed_items integer not null default 0,
  skipped_unchanged_items integer not null default 0,
  api_calls integer not null default 0,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  cost_usd numeric not null default 0,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
alter table pipeline.scholarship_ai_runs enable row level security;
create index if not exists scholarship_ai_runs_created_idx on pipeline.scholarship_ai_runs(created_at desc);
create index if not exists scholarship_ai_runs_status_idx on pipeline.scholarship_ai_runs(status,created_at desc);

create table if not exists pipeline.scholarship_ai_run_items(
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references pipeline.scholarship_ai_runs(id) on delete cascade,
  candidate_id uuid not null references pipeline.layer2_scholarship_discovery_candidates(id),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  evidence_hash text not null,
  status text not null default 'queued' check(status in ('queued','running','validated','needs_review','no_candidate','failed','skipped_unchanged','cancelled')),
  interpretation_id uuid null references pipeline.layer3_interpretations(id),
  result_status text null,
  error_text text null,
  api_calls integer not null default 0,
  input_tokens integer not null default 0,
  output_tokens integer not null default 0,
  cost_usd numeric not null default 0,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(run_id,candidate_id)
);
alter table pipeline.scholarship_ai_run_items enable row level security;
create index if not exists scholarship_ai_run_items_run_status_idx on pipeline.scholarship_ai_run_items(run_id,status,created_at);
create index if not exists scholarship_ai_run_items_candidate_idx on pipeline.scholarship_ai_run_items(candidate_id,created_at desc);

insert into pipeline.layer3_model_profiles(
 code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
 structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref
)
select 'openrouter-scholarship-gemini-flash-lite-v1','openrouter','https://openrouter.ai/api/v1','google/gemini-2.5-flash-lite','OPENROUTER_API_KEY',array['scholarship_page_classification','scholarship_detail_extract'],'cf221-scholarship-v1',
'Interpret only the supplied first-party governed Scholarship Evidence. Return JSON only. Never invent a Scholarship, award, eligibility, date, course scope, citizenship rule or URL. If Evidence is insufficient, return candidate_value null.',
'{"type":"object","required":["candidate_value","confidence","rationale","evidence_quotes"]}'::jsonb,
'{"confidence_min":0,"confidence_max":1,"review_confidence_min":0.92,"max_quotes":4,"max_quote_chars":500,"max_rationale_chars":1400,"evidence_grounding_required":true}'::jsonb,
12000,1200,20,400,1,30000,0.02,true,true,
'{"state":"benchmark_required","validated":false,"message":"CF-221 paid Scholarship route staged; benchmark required before execution."}'::jsonb,
'{"pass":false,"state":"pending_paid_benchmark"}'::jsonb,'CF-CHG-20260906-221','CF-221-scholarship-ai-benchmark'
where not exists(select 1 from pipeline.layer3_model_profiles where code='openrouter-scholarship-gemini-flash-lite-v1');

insert into pipeline.layer3_model_profiles(
 code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
 structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref
)
select 'openrouter-scholarship-qwen35-27b-v1','openrouter','https://openrouter.ai/api/v1','qwen/qwen3.5-27b','OPENROUTER_API_KEY',array['scholarship_page_classification','scholarship_detail_extract'],'cf221-scholarship-v1',
'Interpret only the supplied first-party governed Scholarship Evidence. Return JSON only. Never invent a Scholarship, award, eligibility, date, course scope, citizenship rule or URL. If Evidence is insufficient, return candidate_value null.',
'{"type":"object","required":["candidate_value","confidence","rationale","evidence_quotes"]}'::jsonb,
'{"confidence_min":0,"confidence_max":1,"review_confidence_min":0.92,"max_quotes":4,"max_quote_chars":500,"max_rationale_chars":1400,"evidence_grounding_required":true}'::jsonb,
12000,1200,10,200,1,40000,0.05,true,true,
'{"state":"benchmark_required","validated":false,"message":"CF-221 paid Scholarship fallback route staged; benchmark required before execution."}'::jsonb,
'{"pass":false,"state":"pending_paid_benchmark"}'::jsonb,'CF-CHG-20260906-221','CF-221-scholarship-ai-benchmark'
where not exists(select 1 from pipeline.layer3_model_profiles where code='openrouter-scholarship-qwen35-27b-v1');

update pipeline.layer3_model_profiles p
set fallback_profile_id=q.id
from pipeline.layer3_model_profiles q
where p.code='openrouter-scholarship-gemini-flash-lite-v1' and q.code='openrouter-scholarship-qwen35-27b-v1' and p.fallback_profile_id is distinct from q.id;

insert into pipeline.scholarship_ai_settings(country_code,enabled,schedule_on_change,max_records_per_run,daily_budget_usd,metadata)
values ('AU',false,true,25,1.00,'{"state":"benchmark_required"}'::jsonb),('NZ',false,true,25,1.00,'{"state":"benchmark_required"}'::jsonb)
on conflict(country_code) do nothing;

create or replace function security.scholarship_ai_role_rank()
returns integer language sql stable security definer set search_path='pg_catalog','security' as $$
 select coalesce(max(r.rank),0)::int from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=auth.uid() and r.status='active' and (ur.expires_at is null or ur.expires_at>now())
$$;

create or replace function security.scholarship_ai_control_read_impl(p_country_code text default 'AU')
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','pipeline','scholarship','security' as $$
declare v_rank int:=security.scholarship_ai_role_rank(); v_country text:=upper(coalesce(nullif(p_country_code,''),'AU')); v_result jsonb;
begin
 if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select jsonb_build_object(
   'country_code',v_country,
   'role_rank',v_rank,
   'settings',(select to_jsonb(s)-'schedule_actor'-'updated_by' from pipeline.scholarship_ai_settings s where s.country_code=v_country),
   'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'model_identifier',p.model_identifier,'enabled',p.enabled,'paused',p.paused,'benchmark_pass',coalesce((p.quality_benchmark->>'pass')::boolean,false),'benchmark_state',coalesce(p.quality_benchmark->>'state',p.last_validation_result->>'state'),'cost_ceiling_usd',p.cost_ceiling_usd,'requests_per_minute',p.requests_per_minute,'requests_per_day',p.requests_per_day) order by p.code) from pipeline.layer3_model_profiles p where p.code like 'openrouter-scholarship-%'), '[]'::jsonb),
   'queue',jsonb_build_object(
      'unclassified',(select count(*) from pipeline.layer2_scholarship_discovery_candidates c where c.evidence_id is not null and c.classification is null),
      'needs_review',(select count(*) from pipeline.layer2_scholarship_discovery_candidates c where c.evidence_id is not null and c.classification='needs_review'),
      'detail_ready',(select count(*) from pipeline.layer2_scholarship_discovery_candidates c where c.evidence_id is not null and c.classification='detail_ready')
   ),
   'telemetry',jsonb_build_object(
      'runs_total',(select count(*) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'runs_active',(select count(*) from pipeline.scholarship_ai_runs r where r.country_code=v_country and r.status in ('queued','running')),
      'processed',(select coalesce(sum(r.processed_items),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'api_calls',(select coalesce(sum(r.api_calls),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'input_tokens',(select coalesce(sum(r.input_tokens),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'output_tokens',(select coalesce(sum(r.output_tokens),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'cost_usd',(select coalesce(sum(r.cost_usd),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country),
      'today_cost_usd',(select coalesce(sum(r.cost_usd),0) from pipeline.scholarship_ai_runs r where r.country_code=v_country and r.created_at>=date_trunc('day',now()))
   ),
   'recent_runs',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,country_code,task_class,profile_id,trigger_mode,changes_only,status,total_items,processed_items,validated_items,review_items,no_candidate_items,failed_items,api_calls,input_tokens,output_tokens,cost_usd,started_at,completed_at,created_at from pipeline.scholarship_ai_runs where country_code=v_country order by created_at desc limit 12) x),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;

create or replace function public.scholarship_ai_control_read(p_country_code text default 'AU')
returns jsonb language sql stable set search_path='pg_catalog','security' as $$ select security.scholarship_ai_control_read_impl(p_country_code) $$;
revoke all on function public.scholarship_ai_control_read(text) from public;
grant execute on function public.scholarship_ai_control_read(text) to authenticated;

create or replace function security.scholarship_ai_run_create_impl(p_country_code text,p_task_class text,p_profile_id uuid,p_limit integer,p_trigger_mode text default 'manual',p_changes_only boolean default true)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline','security' as $$
declare v_rank int:=security.scholarship_ai_role_rank(); v_actor uuid:=auth.uid(); v_profile pipeline.layer3_model_profiles%rowtype; v_run uuid; v_count int:=0; v_limit int:=least(greatest(coalesce(p_limit,10),1),100); v_benchmark boolean:=coalesce(p_trigger_mode,'manual')='benchmark';
begin
 if v_rank<4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
 select * into v_profile from pipeline.layer3_model_profiles where id=p_profile_id and p_task_class=any(allowed_task_classes);
 if not found then raise exception 'Scholarship AI model profile/task mismatch'; end if;
 if not v_benchmark and (not v_profile.enabled or v_profile.paused or coalesce((v_profile.quality_benchmark->>'pass')::boolean,false) is not true) then raise exception 'model profile benchmark must pass before governed execution'; end if;
 if v_benchmark and v_rank<5 then raise exception 'PIM Admin role required for model benchmark'; end if;
 if v_benchmark then v_limit:=least(v_limit,5); end if;
 insert into pipeline.scholarship_ai_runs(country_code,task_class,profile_id,trigger_mode,changes_only,requested_limit,requested_by,status,started_at,metadata)
 values(upper(p_country_code),p_task_class,p_profile_id,case when v_benchmark then 'benchmark' else coalesce(p_trigger_mode,'manual') end,p_changes_only,v_limit,v_actor,'queued',now(),jsonb_build_object('change_control_ref','CF-CHG-20260906-221')) returning id into v_run;
 with eligible as (
   select c.id candidate_id,c.evidence_id,e.content_hash,c.classification,c.created_at
   from pipeline.layer2_scholarship_discovery_candidates c
   join pipeline.evidence_artifacts e on e.id=c.evidence_id and e.content_hash is not null and e.storage_path is not null
   where c.evidence_id is not null
     and ((p_task_class='scholarship_page_classification' and (c.classification is null or c.classification='needs_review'))
       or (p_task_class='scholarship_detail_extract' and c.classification in ('detail_ready','needs_review')))
     and (not p_changes_only or not exists(
       select 1 from pipeline.scholarship_ai_run_items oldi
       join pipeline.scholarship_ai_runs oldr on oldr.id=oldi.run_id
       where oldi.candidate_id=c.id and oldr.task_class=p_task_class and oldi.evidence_hash=e.content_hash and oldi.status in ('validated','needs_review','no_candidate')
     ))
   order by case when c.classification='needs_review' then 0 when c.classification is null then 1 else 2 end,c.created_at asc
   limit v_limit
 )
 insert into pipeline.scholarship_ai_run_items(run_id,candidate_id,evidence_id,evidence_hash,metadata)
 select v_run,candidate_id,evidence_id,content_hash,jsonb_build_object('classification_at_queue',classification) from eligible;
 get diagnostics v_count=row_count;
 update pipeline.scholarship_ai_runs set total_items=v_count,status=case when v_count=0 then 'completed' else 'queued' end,completed_at=case when v_count=0 then now() else null end where id=v_run;
 return jsonb_build_object('ok',true,'run_id',v_run,'total_items',v_count,'trigger_mode',case when v_benchmark then 'benchmark' else coalesce(p_trigger_mode,'manual') end,'changes_only',p_changes_only);
end $$;

create or replace function public.scholarship_ai_run_create(p_country_code text,p_task_class text,p_profile_id uuid,p_limit integer default 10,p_trigger_mode text default 'manual',p_changes_only boolean default true)
returns jsonb language sql set search_path='pg_catalog','security' as $$ select security.scholarship_ai_run_create_impl(p_country_code,p_task_class,p_profile_id,p_limit,p_trigger_mode,p_changes_only) $$;
revoke all on function public.scholarship_ai_run_create(text,text,uuid,integer,text,boolean) from public;
grant execute on function public.scholarship_ai_run_create(text,text,uuid,integer,text,boolean) to authenticated;

create or replace function public.scholarship_ai_run_status(p_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','pipeline','security' as $$
declare v_rank int:=security.scholarship_ai_role_rank(); v_actor uuid:=auth.uid(); v_r pipeline.scholarship_ai_runs%rowtype;
begin
 if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select * into v_r from pipeline.scholarship_ai_runs where id=p_run_id;
 if not found then raise exception 'run not found'; end if;
 return jsonb_build_object('id',v_r.id,'status',v_r.status,'total_items',v_r.total_items,'processed_items',v_r.processed_items,'validated_items',v_r.validated_items,'review_items',v_r.review_items,'no_candidate_items',v_r.no_candidate_items,'failed_items',v_r.failed_items,'api_calls',case when v_rank>=4 then v_r.api_calls else null end,'input_tokens',case when v_rank>=4 then v_r.input_tokens else null end,'output_tokens',case when v_rank>=4 then v_r.output_tokens else null end,'cost_usd',case when v_rank>=4 then v_r.cost_usd else null end,'created_at',v_r.created_at,'started_at',v_r.started_at,'completed_at',v_r.completed_at);
end $$;
revoke all on function public.scholarship_ai_run_status(uuid) from public;
grant execute on function public.scholarship_ai_run_status(uuid) to authenticated;

create or replace function security.admin_platform_health_cf221()
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','pipeline','security','scholarship' as $$
declare v_rank int:=security.scholarship_ai_role_rank(); v_failed int; v_running int; v_completed int; v_ev24 bigint; v_attempts bigint; v_calls bigint; v_cost numeric; v_sch bigint; v_active_ai bigint;
begin
 if v_rank<1 then raise exception 'authenticated role required' using errcode='42501'; end if;
 select count(*) filter(where status='failed' and created_at>=now()-interval '24 hours'),count(*) filter(where status in ('queued','running')),count(*) filter(where status in ('completed','succeeded') and created_at>=now()-interval '24 hours') into v_failed,v_running,v_completed from pipeline.jobs;
 select count(*) into v_ev24 from pipeline.evidence_artifacts where created_at>=now()-interval '24 hours';
 select count(*) into v_attempts from pipeline.layer2_provider_attempts where created_at>=now()-interval '24 hours';
 select coalesce(sum(external_call_count),0),coalesce(sum(estimated_cost_usd),0) into v_calls,v_cost from pipeline.layer3_interpretations where created_at>=now()-interval '24 hours';
 select count(*) into v_sch from scholarship.scholarships;
 select count(*) into v_active_ai from pipeline.scholarship_ai_runs where status in ('queued','running');
 return jsonb_strip_nulls(jsonb_build_object(
   'overall_status',case when v_failed>0 then 'attention' when v_running>0 then 'active' else 'healthy' end,
   'jobs',jsonb_build_object('running',v_running,'failed_24h',v_failed,'completed_24h',v_completed),
   'data',jsonb_build_object('evidence_fetched_24h',v_ev24,'scholarships',v_sch),
   'edge_runtime',jsonb_build_object('status',case when v_failed>0 then 'attention' else 'healthy' end,'active_workloads',v_running,'completed_24h',v_completed),
   'api_activity',case when v_rank>=4 then jsonb_build_object('layer2_provider_requests_24h',v_attempts,'layer3_external_calls_24h',v_calls,'layer3_cost_24h_usd',v_cost) else null end,
   'scholarship_ai',case when v_rank>=3 then jsonb_build_object('active_runs',v_active_ai,'profiles_staged',(select count(*) from pipeline.layer3_model_profiles where code like 'openrouter-scholarship-%'),'profiles_qualified',(select count(*) from pipeline.layer3_model_profiles where code like 'openrouter-scholarship-%' and coalesce((quality_benchmark->>'pass')::boolean,false))) else null end,
   'security',case when v_rank>=6 then jsonb_build_object('status','reviewed_with_existing_findings','note','Security Advisor remains the authority; no CF-221 finding is asserted by this runtime snapshot.') else null end,
   'observed_at',now()
 ));
end $$;

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable set search_path='pg_catalog','public','security' as $$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='platform_health' then return security.admin_platform_health_cf221(); end if;
 if p_operation='scholarship_ai' then return security.scholarship_ai_control_read_impl(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='scholarship_runtime' then return security.admin_scholarship_runtime_read(p_args); end if;
 if p_operation='scholarship_runtime_uat' then return security.admin_scholarship_runtime_uat(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='layer_status_summary' then return security.admin_layer_status_summary(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation='campuses_page' then return security.admin_campus_page_fast(p_args); end if;
 if p_operation in ('providers_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='ranking_imports' then return security.admin_ranking_imports_read(p_args); end if;
 if p_operation in ('ranking_summary','ranking_filters','ranking_observations') then return security.admin_ranking_read(p_operation,p_args); end if;
 if p_operation in ('provider_asset_summary','provider_asset_coverage','provider_asset_context') then return security.admin_provider_asset_read(p_operation,p_args); end if;
 if p_operation in ('provider_contacts_page','provider_contact_detail','provider_contact_imports','provider_contact_import_detail') then return security.admin_provider_contact_read(p_operation,p_args); end if;
 if p_operation='contextual_compare' then return security.admin_contextual_compare(p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation='layer2_parent_runs' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>'limit','')::integer,10)); end if;
 if p_operation in ('layer2_ops_overview','layer2_ops_run_detail') then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation='layer2_profiles' and (p_args ? 'limit' or p_args ? 'offset' or p_args ? 'query' or p_args ? 'country' or p_args ? 'method' or p_args ? 'health') then return security.admin_layer2_profiles_page(p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions','data_quality_quarantine') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation in ('platform_readiness','platform_capacity','platform_environment_gates','platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks') then return security.admin_platform_maturity_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id))||jsonb_build_object('ranking_context',security.admin_provider_rankings(v_id,10))||jsonb_build_object('provider_asset_context',security.admin_provider_asset_read('provider_asset_context',jsonb_build_object('provider_id',v_id)))||jsonb_build_object('scholarship_context',security.admin_provider_scholarships(v_id));end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id))||jsonb_build_object('ranking_context',security.admin_course_rankings(v_id,10));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $$;
