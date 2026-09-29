-- CF-CHG-20260915-247 plan item A3: intakes found by the coverage sweep are HELD. Before any admission they go to a
-- Layer 3 benchmark (a qualified, pinned model), following the tuition house pattern (Decision 160/163):
--  * a gold set of real sweep pages with the true international intake months, each justified by a verbatim
--    excerpt of the stored page text (pipeline.layer3_intake_benchmark_cases; gold rows in the next migration);
--  * per-case results for the Layer 2 extractor and the Layer 3 model (pipeline.layer3_intake_benchmark_results);
--  * a separate model profile for task class provider_intake_validation, created DISABLED and PAUSED;
--  * the one-time benchmark Edge function layer3-intake-benchmark is added to the nonce allowlist.
-- Nothing here activates anything: no cron, no admission, no hand-off, no change to coverage_admission_apply_v1,
-- coverage-sweep, scholarship or consumer API functions. Activation is a separate Platform Admin step.

create table if not exists pipeline.layer3_intake_benchmark_cases (
  id uuid primary key default gen_random_uuid(),
  case_key text not null unique,
  course_id uuid not null references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  source_url text not null,
  text_sha256 text not null check (text_sha256 ~ '^[0-9a-f]{64}$'),
  gold_status text not null check (gold_status in ('months','not_stated')),
  gold_months int[] not null default '{}',
  evidence_excerpt text,
  layer2_months int[] not null default '{}',
  layer2_bucket text not null check (layer2_bucket in ('l2_right','l2_wrong','l2_empty_right','l2_empty_wrong')),
  extractor_version text,
  notes text,
  change_control_ref text not null default 'CF-CHG-20260915-247',
  created_at timestamptz not null default now(),
  constraint layer3_intake_gold_shape check (
    (gold_status='months' and cardinality(gold_months)>0 and gold_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12] and evidence_excerpt is not null)
    or (gold_status='not_stated' and cardinality(gold_months)=0))
);
comment on table pipeline.layer3_intake_benchmark_cases is 'CF-247 A3: gold set of sweep course pages with the true international intake months (or not stated), justified by a verbatim excerpt of the stored page text; text_sha256 pins the exact text the gold was read from.';

create table if not exists pipeline.layer3_intake_benchmark_results (
  id uuid primary key default gen_random_uuid(),
  run_label text not null,
  case_id uuid not null references pipeline.layer3_intake_benchmark_cases(id) on delete cascade,
  profile_id uuid references pipeline.layer3_model_profiles(id),
  configured_model text,
  returned_model text,
  text_sha256 text,
  text_matches_gold boolean,
  gold_excerpt_in_text boolean,
  layer2_months int[] not null default '{}',
  layer2_exact boolean,
  layer3_status text,
  layer3_months int[] not null default '{}',
  layer3_valid boolean,
  layer3_errors text[] not null default '{}',
  layer3_exact boolean,
  invented_months int[] not null default '{}',
  missed_months int[] not null default '{}',
  quotes jsonb,
  raw_answer jsonb,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  cost_usd numeric not null default 0 check (cost_usd>=0),
  latency_ms int,
  external_calls int not null default 0,
  created_at timestamptz not null default now(),
  unique (run_label, case_id)
);
comment on table pipeline.layer3_intake_benchmark_results is 'CF-247 A3: per-case Layer 2 and Layer 3 intake results against the gold set, one row per benchmark run and case, with OpenRouter usage.';

alter table pipeline.layer3_intake_benchmark_cases enable row level security;
alter table pipeline.layer3_intake_benchmark_results enable row level security;
revoke all on pipeline.layer3_intake_benchmark_cases, pipeline.layer3_intake_benchmark_results from public, anon, authenticated;

-- Separate profile for the intake task class: same pinned model as the qualified tuition profile, created disabled
-- and paused. Its quality_benchmark is written only by the benchmark; enabling/unpausing is the activation step.
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-provider-intake-validation-mistral-small-3-2-v1','openrouter','https://openrouter.ai/api/v1','mistralai/mistral-small-3.2-24b-instruct','OPENROUTER_API_KEY',
       array['provider_intake_validation'],'cf247-intake-validation-v1.1.0',
       'Prompt text lives in supabase/functions/_shared/cf247-intake-validation.ts (INTAKE_SYSTEM_PROMPT) and is bound by the benchmark binding hash.',
       jsonb_build_object('type','object','required',jsonb_build_array('rationale','quotes','months','status')),
       jsonb_build_object('quote_in_page_text_required',true,'months_named_in_quotes_required',true,'not_stated_allowed',true,'semester_terms_not_months',true,'international_only',true),
       16000,600,30,15000,1,45000,3.00,
       false,true,
       jsonb_build_object('state','pending_intake_benchmark','validated',false),
       jsonb_build_object('pass',false,'state','pending_intake_benchmark','qualification_rule','A3: >=95% exact on stated cases and zero invented intakes on not-stated cases'),
       'CF-CHG-20260915-247','CF-247-A3-intake-layer3-benchmark'
 where not exists (select 1 from pipeline.layer3_model_profiles where code='openrouter-provider-intake-validation-mistral-small-3-2-v1');

-- Service RPCs (service_role only) for the one-time benchmark function.
create or replace function public.layer3_intake_benchmark_pages_service(p_course_ids uuid[])
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue' as $f$
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('course_id',p.course_id,'provider_id',p.provider_id,'provider',pv.canonical_name,'url',p.url,
            'evidence_id',p.evidence_id,'storage_path',e.storage_path,'layer2_intakes',p.candidates->'intakes','extractor',p.candidates->>'extractor','identity_basis',p.identity_basis))
    from pipeline.coverage_course_pages p join pipeline.evidence_artifacts e on e.id=p.evidence_id join catalogue.providers pv on pv.id=p.provider_id
   where p.course_id=any(p_course_ids) and p.read_status='read' and e.storage_path is not null),'[]'::jsonb);
end $f$;

create or replace function public.layer3_intake_benchmark_cases_service()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('case_id',c.id,'case_key',c.case_key,'course_id',c.course_id,'evidence_id',c.evidence_id,'storage_path',e.storage_path,
            'text_sha256',c.text_sha256,'gold_status',c.gold_status,'gold_months',to_jsonb(c.gold_months),'evidence_excerpt',c.evidence_excerpt) order by c.case_key)
    from pipeline.layer3_intake_benchmark_cases c join pipeline.evidence_artifacts e on e.id=c.evidence_id),'[]'::jsonb);
end $f$;

create or replace function public.layer3_intake_benchmark_profile_service()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v jsonb;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  select jsonb_build_object('id',id,'code',code,'model_identifier',model_identifier,'base_url',base_url,'secret_env_key',secret_env_key,'enabled',enabled,'paused',paused,
         'max_input_tokens',max_input_tokens,'max_output_tokens',max_output_tokens,'timeout_ms',timeout_ms,'retry_ceiling',retry_ceiling,'cost_ceiling_usd',cost_ceiling_usd,
         'spent_usd',(select coalesce(sum(cost_usd),0) from pipeline.layer3_intake_benchmark_results))
    into v from pipeline.layer3_model_profiles where code='openrouter-provider-intake-validation-mistral-small-3-2-v1';
  return v;
end $f$;

create or replace function public.layer3_intake_benchmark_result_record_service(p_run_label text, p_case_id uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  insert into pipeline.layer3_intake_benchmark_results(run_label,case_id,profile_id,configured_model,returned_model,text_sha256,text_matches_gold,gold_excerpt_in_text,layer2_months,layer2_exact,
    layer3_status,layer3_months,layer3_valid,layer3_errors,layer3_exact,invented_months,missed_months,quotes,raw_answer,input_tokens,output_tokens,cost_usd,latency_ms,external_calls)
  values (p_run_label,p_case_id,nullif(p_result->>'profile_id','')::uuid,p_result->>'configured_model',p_result->>'returned_model',p_result->>'text_sha256',(p_result->>'text_matches_gold')::boolean,(p_result->>'gold_excerpt_in_text')::boolean,
    coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'layer2_months') x),'{}'),(p_result->>'layer2_exact')::boolean,
    p_result->>'layer3_status',coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'layer3_months') x),'{}'),(p_result->>'layer3_valid')::boolean,
    coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'layer3_errors') x),'{}'),(p_result->>'layer3_exact')::boolean,
    coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'invented_months') x),'{}'),
    coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'missed_months') x),'{}'),
    p_result->'quotes',p_result->'raw_answer',coalesce((p_result->>'input_tokens')::int,0),coalesce((p_result->>'output_tokens')::int,0),
    greatest(coalesce((p_result->>'cost_usd')::numeric,0),0),(p_result->>'latency_ms')::int,coalesce((p_result->>'external_calls')::int,0))
  on conflict (run_label,case_id) do nothing;
  return jsonb_build_object('ok',true,'spent_usd',(select coalesce(sum(cost_usd),0) from pipeline.layer3_intake_benchmark_results));
end $f$;

-- Records the benchmark outcome in the house style (layer3_quality_benchmark_runs + the profile's quality_benchmark).
-- The profile stays exactly as enabled/paused as it was (created disabled and paused); a pass activates nothing.
create or replace function public.layer3_intake_benchmark_finalise_service(p_run_label text, p_summary jsonb, p_binding_hash text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare p pipeline.layer3_model_profiles%rowtype; v_run uuid; v_n int; v_stated int; v_stated_exact int; v_ns int; v_ns_invented int; v_cost numeric; v_in int; v_out int; v_calls int; v_lat int;
        v_rate numeric; v_pass boolean; v_model_ok boolean; v_cost_ok boolean; v_text_ok boolean; v_all int; v_models text[];
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  if p_binding_hash is null or p_binding_hash !~ '^[0-9a-f]{64}$' then raise exception 'binding hash required' using errcode='22023'; end if;
  select * into p from pipeline.layer3_model_profiles where code='openrouter-provider-intake-validation-mistral-small-3-2-v1' for update;
  if not found then raise exception 'intake profile missing'; end if;
  select count(*) into v_all from pipeline.layer3_intake_benchmark_cases;
  -- scores are recomputed here from the stored rows, never taken from the caller
  select count(*), count(*) filter (where c.gold_status='months'), count(*) filter (where c.gold_status='months' and r.layer3_exact),
         count(*) filter (where c.gold_status='not_stated'), count(*) filter (where c.gold_status='not_stated' and cardinality(r.layer3_months)>0),
         coalesce(sum(r.cost_usd),0), coalesce(sum(r.input_tokens),0), coalesce(sum(r.output_tokens),0), coalesce(sum(r.external_calls),0), coalesce(max(r.latency_ms),0),
         bool_and(coalesce(r.text_matches_gold,false) and coalesce(r.gold_excerpt_in_text,false))
    into v_n, v_stated, v_stated_exact, v_ns, v_ns_invented, v_cost, v_in, v_out, v_calls, v_lat, v_text_ok
    from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label;
  -- returned models come from the stored per-case rows (a failed call with no model counts against model_exact)
  v_models:=array(select distinct coalesce(r.returned_model,'<none>') from pipeline.layer3_intake_benchmark_results r where r.run_label=p_run_label order by 1);
  v_rate:=case when v_stated>0 then round(v_stated_exact::numeric/v_stated,4) end;
  v_model_ok:=coalesce(array_length(v_models,1),0)>0 and not exists(select 1 from unnest(v_models) m where m<>p.model_identifier);
  v_cost_ok:=v_cost<=p.cost_ceiling_usd;
  v_pass:=v_n=v_all and v_n>0 and v_stated>0 and v_ns>0 and coalesce(v_rate,0)>=0.95 and v_ns_invented=0 and v_model_ok and v_cost_ok and coalesce(v_text_ok,false);
  insert into pipeline.layer3_quality_benchmark_runs(profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,returned_models,external_call_count,input_tokens,output_tokens,estimated_cost_usd,max_latency_ms,evidence_ids,binding_hash,prompt_profile_version,validator_profile,summary,change_control_ref,uat_ref,completed_at)
  select p.id,'00000000-0000-0000-0000-000000000000'::uuid,case when v_pass then 'pass' else 'fail' end,
         coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold_status',c.gold_status,'gold_months',c.gold_months,'layer2_months',r.layer2_months,'layer2_exact',r.layer2_exact,
                  'layer3_status',r.layer3_status,'layer3_months',r.layer3_months,'layer3_valid',r.layer3_valid,'layer3_errors',r.layer3_errors,'layer3_exact',r.layer3_exact,'invented_months',r.invented_months,'missed_months',r.missed_months) order by c.case_key)
                  from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold_status='months'),'[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold_status',c.gold_status,'layer2_months',r.layer2_months,'layer3_status',r.layer3_status,'layer3_months',r.layer3_months,'layer3_valid',r.layer3_valid,'layer3_errors',r.layer3_errors,'invented_months',r.invented_months) order by c.case_key)
                  from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold_status='not_stated'),'[]'::jsonb),
         p.model_identifier,coalesce(v_models,'{}'),v_calls,v_in,v_out,v_cost,v_lat,
         coalesce((select array_agg(distinct c.evidence_id) from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label),'{}'),
         p_binding_hash,p.prompt_profile_version,coalesce(p.deterministic_validators,'{}'::jsonb),
         left(format('CF-247 A3 intake benchmark %s: stated exact %s/%s (%s); not-stated with invented intakes %s/%s; cases %s/%s; cost_usd=%s',p_run_label,v_stated_exact,v_stated,v_rate,v_ns_invented,v_ns,v_n,v_all,round(v_cost,6)),1000),
         'CF-CHG-20260915-247','CF-247-A3-intake-layer3-benchmark',now()
  returning id into v_run;
  update pipeline.layer3_model_profiles set
    quality_benchmark=jsonb_build_object('run_id',v_run,'run_label',p_run_label,'pass',v_pass,'binding_hash',p_binding_hash,'completed_at',now(),'configured_model',p.model_identifier,
      'returned_models',coalesce(v_models,'{}'),'model_exact',v_model_ok,'cost_pass',v_cost_ok,'text_pinned',coalesce(v_text_ok,false),'estimated_cost_usd',v_cost,'input_tokens',v_in,'output_tokens',v_out,
      'external_call_count',v_calls,'max_latency_ms',v_lat,'cases',v_n,'gold_cases',v_all,'stated_cases',v_stated,'stated_exact',v_stated_exact,'stated_exact_rate',v_rate,'not_stated_cases',v_ns,
      'not_stated_with_invented_intakes',v_ns_invented,'summary',p_summary,
      'qualification_rule','A3: >=95% exact on stated cases and zero invented intakes on not-stated cases','change_control_ref','CF-CHG-20260915-247','uat_ref','CF-247-A3-intake-layer3-benchmark'),
    last_validation_result=jsonb_build_object('state',case when v_pass then 'intake_benchmark_passed' else 'intake_benchmark_failed' end,'validated',v_pass,'benchmark_run_id',v_run,'completed_at',now()),
    updated_at=now()
  where id=p.id;
  return jsonb_build_object('ok',true,'pass',v_pass,'run_id',v_run,'stated_exact',v_stated_exact,'stated_cases',v_stated,'stated_exact_rate',v_rate,'not_stated_cases',v_ns,
    'not_stated_with_invented_intakes',v_ns_invented,'cases',v_n,'gold_cases',v_all,'model_exact',v_model_ok,'cost_usd',v_cost,'text_pinned',v_text_ok,'profile_enabled',p.enabled,'profile_paused',p.paused);
end $f$;

do $g$ declare fn text;
begin
  foreach fn in array array['layer3_intake_benchmark_pages_service(uuid[])','layer3_intake_benchmark_cases_service()','layer3_intake_benchmark_profile_service()',
                            'layer3_intake_benchmark_result_record_service(text,uuid,jsonb)','layer3_intake_benchmark_finalise_service(text,jsonb,text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', fn);
    execute format('grant execute on function public.%s to service_role', fn);
  end loop;
end $g$;

-- Nonce allowlist: add the one-time benchmark function. Guarded by the reviewed live definition's checksum.
do $n$ declare v text;
begin
  if (select md5(prosrc) from pg_proc where oid='pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure)<>'765217baba62e3f81f680305d327e117' then
    raise exception 'svc_pilot_submit_nonce changed since review; not replaced'; end if;
  v:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  if (length(v)-length(replace(v,$o$'layer3-work-dispatch')$o$,'')))/length($o$'layer3-work-dispatch')$o$)<>1 then raise exception 'nonce allowlist anchor not found'; end if;
  v:=replace(v,$o$'layer3-work-dispatch')$o$,$o$'layer3-work-dispatch','layer3-intake-benchmark')$o$);
  execute v;
end $n$;
