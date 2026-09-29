-- CF-CHG-20260915-247 plan item A3, requalification (Platform Admin option 1, 29 Sep 2026):
--  * gold sets: every benchmark case belongs to a named gold set; a set is FROZEN (row count and sha256 digest of its
--    answers recorded) before any model runs on it, and a run is refused if the set changed since it was frozen.
--    The first 44 cases become gold set 'a3-dev-1' (the development set); the fresh holdout is 'a3-holdout-1'.
--  * results record which deterministic safety rule (if any) forced not_stated;
--  * the finalise step takes the profile and gold set from the run's own rows (so a comparison model can be benchmarked
--    on the same frozen holdout under its own profile), and never changes enabled/paused;
--  * a comparison profile for a stronger individually pinned model (mistralai/mistral-medium-3.1), disabled and paused.
-- Nothing is activated: no cron, hand-off, admission rule or profile enable/unpause.

alter table pipeline.layer3_intake_benchmark_cases add column if not exists gold_set text;
update pipeline.layer3_intake_benchmark_cases set gold_set='a3-dev-1' where gold_set is null;
alter table pipeline.layer3_intake_benchmark_cases alter column gold_set set not null;
alter table pipeline.layer3_intake_benchmark_results add column if not exists safety_blockers text[] not null default '{}';

create table if not exists pipeline.layer3_intake_gold_sets (
  gold_set text primary key,
  case_count int not null,
  digest text not null check (digest ~ '^[0-9a-f]{64}$'),
  frozen_at timestamptz not null default now(),
  note text
);
alter table pipeline.layer3_intake_gold_sets enable row level security;
revoke all on pipeline.layer3_intake_gold_sets from public, anon, authenticated;
comment on table pipeline.layer3_intake_gold_sets is 'CF-247 A3: frozen intake gold sets (sha256 of every case''s answer fields, in case_key order). A benchmark run is refused when the current digest differs.';

-- Digest of a gold set's answers: case identity, pinned text, gold answer and excerpt (notes are commentary, excluded).
create or replace function pipeline.layer3_intake_gold_digest(p_gold_set text)
returns text language sql stable set search_path to 'pg_catalog','pipeline','extensions' as $f$
  select encode(extensions.digest(coalesce(string_agg(concat_ws('|', c.case_key, c.course_id, c.evidence_id, c.text_sha256, c.gold_status, c.gold_months::text, coalesce(c.evidence_excerpt,'~')), E'\n' order by c.case_key),''),'sha256'),'hex')
    from pipeline.layer3_intake_benchmark_cases c where c.gold_set=p_gold_set
$f$;
revoke all on function pipeline.layer3_intake_gold_digest(text) from public, anon, authenticated;

insert into pipeline.layer3_intake_gold_sets(gold_set, case_count, digest, note)
select 'a3-dev-1', count(*), pipeline.layer3_intake_gold_digest('a3-dev-1'), 'first 44 cases (development set; runs r1/r2 on 29 Sep 2026)'
  from pipeline.layer3_intake_benchmark_cases where gold_set='a3-dev-1'
on conflict (gold_set) do nothing;

-- Comparison profile: a stronger individually pinned model, same settings, disabled and paused.
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-provider-intake-validation-mistral-medium-3-1-v1',aggregator_provider,base_url,'mistralai/mistral-medium-3.1',secret_env_key,allowed_task_classes,'cf247-intake-validation-v1.2.0',prompt_system,
       structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
       false,true,jsonb_build_object('state','pending_intake_benchmark','validated',false),
       jsonb_build_object('pass',false,'state','pending_intake_benchmark','qualification_rule','A3: >=95% exact on stated cases and zero invented intakes on not-stated cases','role','comparison'),
       change_control_ref,uat_ref
  from pipeline.layer3_model_profiles where code='openrouter-provider-intake-validation-mistral-small-3-2-v1'
   and not exists (select 1 from pipeline.layer3_model_profiles where code='openrouter-provider-intake-validation-mistral-medium-3-1-v1');
update pipeline.layer3_model_profiles set prompt_profile_version='cf247-intake-validation-v1.2.0',
       deterministic_validators=deterministic_validators||jsonb_build_object('max_quotes',12,'safety_rule','course_not_open_to_international|not_available_to_student_visa_holders|no_current_intake'),
       updated_at=now()
 where code in ('openrouter-provider-intake-validation-mistral-small-3-2-v1','openrouter-provider-intake-validation-mistral-medium-3-1-v1');

-- Replace the benchmark RPCs (this change's own functions), each guarded by the reviewed live checksum.
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid='public.layer3_intake_benchmark_cases_service()'::regprocedure)<>'e7506c861179148f9a9ce3667a90c484'
     or (select md5(prosrc) from pg_proc where oid='public.layer3_intake_benchmark_profile_service()'::regprocedure)<>'4378b41af1c7a3b811f1ab8a006a08d7'
     or (select md5(prosrc) from pg_proc where oid='public.layer3_intake_benchmark_result_record_service(text,uuid,jsonb)'::regprocedure)<>'53f6629f1d745013d1d5178f7840eb14'
     or (select md5(prosrc) from pg_proc where oid='public.layer3_intake_benchmark_finalise_service(text,jsonb,text)'::regprocedure)<>'e2b68a46f16e9661e6d46dc991165dde' then
    raise exception 'intake benchmark RPCs changed since review; not replaced'; end if;
end $g$;
drop function public.layer3_intake_benchmark_cases_service();
drop function public.layer3_intake_benchmark_profile_service();

create or replace function public.layer3_intake_benchmark_cases_service(p_gold_set text default 'a3-dev-1')
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  return jsonb_build_object('gold_set',p_gold_set,
    'frozen_digest',(select g.digest from pipeline.layer3_intake_gold_sets g where g.gold_set=p_gold_set),
    'current_digest',pipeline.layer3_intake_gold_digest(p_gold_set),
    'cases',coalesce((select jsonb_agg(jsonb_build_object('case_id',c.id,'case_key',c.case_key,'course_id',c.course_id,'evidence_id',c.evidence_id,'storage_path',e.storage_path,
            'text_sha256',c.text_sha256,'gold_status',c.gold_status,'gold_months',to_jsonb(c.gold_months),'evidence_excerpt',c.evidence_excerpt) order by c.case_key)
      from pipeline.layer3_intake_benchmark_cases c join pipeline.evidence_artifacts e on e.id=c.evidence_id where c.gold_set=p_gold_set),'[]'::jsonb));
end $f$;

create or replace function public.layer3_intake_benchmark_profile_service(p_code text default 'openrouter-provider-intake-validation-mistral-small-3-2-v1')
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v jsonb;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  if p_code not like 'openrouter-provider-intake-validation-%' then raise exception 'not an intake benchmark profile'; end if;
  select jsonb_build_object('id',id,'code',code,'model_identifier',model_identifier,'base_url',base_url,'secret_env_key',secret_env_key,'enabled',enabled,'paused',paused,
         'max_input_tokens',max_input_tokens,'max_output_tokens',max_output_tokens,'timeout_ms',timeout_ms,'retry_ceiling',retry_ceiling,'cost_ceiling_usd',cost_ceiling_usd,
         'spent_usd',(select coalesce(sum(cost_usd),0) from pipeline.layer3_intake_benchmark_results))
    into v from pipeline.layer3_model_profiles where code=p_code and 'provider_intake_validation'=any(allowed_task_classes);
  return v;
end $f$;

create or replace function public.layer3_intake_benchmark_result_record_service(p_run_label text, p_case_id uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  insert into pipeline.layer3_intake_benchmark_results(run_label,case_id,profile_id,configured_model,returned_model,text_sha256,text_matches_gold,gold_excerpt_in_text,layer2_months,layer2_exact,
    layer3_status,layer3_months,layer3_valid,layer3_errors,layer3_exact,invented_months,missed_months,quotes,raw_answer,input_tokens,output_tokens,cost_usd,latency_ms,external_calls,safety_blockers)
  values (p_run_label,p_case_id,nullif(p_result->>'profile_id','')::uuid,p_result->>'configured_model',p_result->>'returned_model',p_result->>'text_sha256',(p_result->>'text_matches_gold')::boolean,(p_result->>'gold_excerpt_in_text')::boolean,
    coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'layer2_months') x),'{}'),(p_result->>'layer2_exact')::boolean,
    p_result->>'layer3_status',coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'layer3_months') x),'{}'),(p_result->>'layer3_valid')::boolean,
    coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'layer3_errors') x),'{}'),(p_result->>'layer3_exact')::boolean,
    coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'invented_months') x),'{}'),
    coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_result->'missed_months') x),'{}'),
    p_result->'quotes',p_result->'raw_answer',coalesce((p_result->>'input_tokens')::int,0),coalesce((p_result->>'output_tokens')::int,0),
    greatest(coalesce((p_result->>'cost_usd')::numeric,0),0),(p_result->>'latency_ms')::int,coalesce((p_result->>'external_calls')::int,0),
    coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'safety_blockers') x),'{}'))
  on conflict (run_label,case_id) do nothing;
  return jsonb_build_object('ok',true,'spent_usd',(select coalesce(sum(cost_usd),0) from pipeline.layer3_intake_benchmark_results));
end $f$;

-- Records a run in layer3_quality_benchmark_runs and on the run's own profile. Scores are recomputed from stored rows.
-- The run must cover every case of exactly one frozen, unchanged gold set, under exactly one profile.
create or replace function public.layer3_intake_benchmark_finalise_service(p_run_label text, p_summary jsonb, p_binding_hash text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare p pipeline.layer3_model_profiles%rowtype; v_run uuid; v_n int; v_stated int; v_stated_exact int; v_ns int; v_ns_invented int; v_cost numeric; v_in int; v_out int; v_calls int; v_lat int;
        v_rate numeric; v_pass boolean; v_model_ok boolean; v_cost_ok boolean; v_text_ok boolean; v_all int; v_models text[]; v_set text; v_frozen text; v_digest text; v_safety int;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  if p_binding_hash is null or p_binding_hash !~ '^[0-9a-f]{64}$' then raise exception 'binding hash required' using errcode='22023'; end if;
  if (select count(distinct r.profile_id) from pipeline.layer3_intake_benchmark_results r where r.run_label=p_run_label)<>1 then raise exception 'run must have exactly one profile'; end if;
  if (select count(distinct c.gold_set) from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label)<>1 then raise exception 'run must cover exactly one gold set'; end if;
  select * into p from pipeline.layer3_model_profiles where id=(select r.profile_id from pipeline.layer3_intake_benchmark_results r where r.run_label=p_run_label limit 1) for update;
  select c.gold_set into v_set from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label limit 1;
  select g.digest into v_frozen from pipeline.layer3_intake_gold_sets g where g.gold_set=v_set;
  v_digest:=pipeline.layer3_intake_gold_digest(v_set);
  select count(*) into v_all from pipeline.layer3_intake_benchmark_cases where gold_set=v_set;
  select count(*), count(*) filter (where c.gold_status='months'), count(*) filter (where c.gold_status='months' and r.layer3_exact),
         count(*) filter (where c.gold_status='not_stated'), count(*) filter (where c.gold_status='not_stated' and cardinality(r.layer3_months)>0),
         coalesce(sum(r.cost_usd),0), coalesce(sum(r.input_tokens),0), coalesce(sum(r.output_tokens),0), coalesce(sum(r.external_calls),0), coalesce(max(r.latency_ms),0),
         bool_and(coalesce(r.text_matches_gold,false) and coalesce(r.gold_excerpt_in_text,false)), count(*) filter (where cardinality(r.safety_blockers)>0)
    into v_n, v_stated, v_stated_exact, v_ns, v_ns_invented, v_cost, v_in, v_out, v_calls, v_lat, v_text_ok, v_safety
    from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label;
  -- returned models from rows that called the model (rows the safety rule answered make no call)
  v_models:=array(select distinct coalesce(r.returned_model,'<none>') from pipeline.layer3_intake_benchmark_results r where r.run_label=p_run_label and r.external_calls>0 order by 1);
  v_rate:=case when v_stated>0 then round(v_stated_exact::numeric/v_stated,4) end;
  v_model_ok:=coalesce(array_length(v_models,1),0)>0 and not exists(select 1 from unnest(v_models) m where m<>p.model_identifier);
  v_cost_ok:=v_cost<=p.cost_ceiling_usd;
  v_pass:=v_frozen is not null and v_frozen=v_digest and v_n=v_all and v_n>0 and v_stated>0 and v_ns>0 and coalesce(v_rate,0)>=0.95 and v_ns_invented=0 and v_model_ok and v_cost_ok and coalesce(v_text_ok,false);
  insert into pipeline.layer3_quality_benchmark_runs(profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,returned_models,external_call_count,input_tokens,output_tokens,estimated_cost_usd,max_latency_ms,evidence_ids,binding_hash,prompt_profile_version,validator_profile,summary,change_control_ref,uat_ref,completed_at)
  select p.id,'00000000-0000-0000-0000-000000000000'::uuid,case when v_pass then 'pass' else 'fail' end,
         coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold_status',c.gold_status,'gold_months',c.gold_months,'layer2_months',r.layer2_months,'layer2_exact',r.layer2_exact,
                  'layer3_status',r.layer3_status,'layer3_months',r.layer3_months,'layer3_valid',r.layer3_valid,'layer3_errors',r.layer3_errors,'layer3_exact',r.layer3_exact,'invented_months',r.invented_months,'missed_months',r.missed_months,'safety_blockers',r.safety_blockers) order by c.case_key)
                  from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold_status='months'),'[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold_status',c.gold_status,'layer2_months',r.layer2_months,'layer3_status',r.layer3_status,'layer3_months',r.layer3_months,'layer3_valid',r.layer3_valid,'layer3_errors',r.layer3_errors,'invented_months',r.invented_months,'safety_blockers',r.safety_blockers) order by c.case_key)
                  from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold_status='not_stated'),'[]'::jsonb),
         p.model_identifier,coalesce(v_models,'{}'),v_calls,v_in,v_out,v_cost,v_lat,
         coalesce((select array_agg(distinct c.evidence_id) from pipeline.layer3_intake_benchmark_results r join pipeline.layer3_intake_benchmark_cases c on c.id=r.case_id where r.run_label=p_run_label),'{}'),
         p_binding_hash,p.prompt_profile_version,coalesce(p.deterministic_validators,'{}'::jsonb),
         left(format('CF-247 A3 intake benchmark %s on %s (digest %s): stated exact %s/%s (%s); not-stated with invented intakes %s/%s; safety rule applied %s; cases %s/%s; cost_usd=%s',p_run_label,v_set,left(coalesce(v_frozen,'unfrozen'),12),v_stated_exact,v_stated,v_rate,v_ns_invented,v_ns,v_safety,v_n,v_all,round(v_cost,6)),1000),
         'CF-CHG-20260915-247','CF-247-A3-intake-layer3-benchmark',now()
  returning id into v_run;
  update pipeline.layer3_model_profiles set
    quality_benchmark=jsonb_build_object('run_id',v_run,'run_label',p_run_label,'pass',v_pass,'gold_set',v_set,'gold_digest',v_frozen,'gold_unchanged',v_frozen is not null and v_frozen=v_digest,
      'binding_hash',p_binding_hash,'completed_at',now(),'configured_model',p.model_identifier,
      'returned_models',coalesce(v_models,'{}'),'model_exact',v_model_ok,'cost_pass',v_cost_ok,'text_pinned',coalesce(v_text_ok,false),'estimated_cost_usd',v_cost,'input_tokens',v_in,'output_tokens',v_out,
      'external_call_count',v_calls,'max_latency_ms',v_lat,'cases',v_n,'gold_cases',v_all,'stated_cases',v_stated,'stated_exact',v_stated_exact,'stated_exact_rate',v_rate,'not_stated_cases',v_ns,
      'not_stated_with_invented_intakes',v_ns_invented,'safety_rule_cases',v_safety,'summary',p_summary,
      'qualification_rule','A3: >=95% exact on stated cases and zero invented intakes on not-stated cases','change_control_ref','CF-CHG-20260915-247','uat_ref','CF-247-A3-intake-layer3-benchmark'),
    last_validation_result=jsonb_build_object('state',case when v_pass then 'intake_benchmark_passed' else 'intake_benchmark_failed' end,'validated',v_pass,'benchmark_run_id',v_run,'completed_at',now()),
    updated_at=now()
  where id=p.id;
  return jsonb_build_object('ok',true,'pass',v_pass,'run_id',v_run,'gold_set',v_set,'gold_digest',v_frozen,'gold_unchanged',v_frozen is not null and v_frozen=v_digest,'stated_exact',v_stated_exact,'stated_cases',v_stated,'stated_exact_rate',v_rate,'not_stated_cases',v_ns,
    'not_stated_with_invented_intakes',v_ns_invented,'safety_rule_cases',v_safety,'cases',v_n,'gold_cases',v_all,'model',p.model_identifier,'model_exact',v_model_ok,'cost_usd',v_cost,'text_pinned',v_text_ok,'profile_enabled',p.enabled,'profile_paused',p.paused);
end $f$;

do $g$ declare fn text;
begin
  foreach fn in array array['layer3_intake_benchmark_cases_service(text)','layer3_intake_benchmark_profile_service(text)',
                            'layer3_intake_benchmark_result_record_service(text,uuid,jsonb)','layer3_intake_benchmark_finalise_service(text,jsonb,text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', fn);
    execute format('grant execute on function public.%s to service_role', fn);
  end loop;
end $g$;
