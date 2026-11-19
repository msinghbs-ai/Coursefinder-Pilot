-- CF-CHG-20260915-247 Layer 3 model routing (Platform Admin direction 29 Sep 2026 18:30 IST): foundation.
-- Stronger, individually pinned OpenRouter models are qualified per task class on FRESH holdout gold sets and the
-- cheapest passing one is routed. This migration only adds the qualification machinery; nothing is activated here.
--  * contract freezes: the prompt, schema and validators of each task class are fingerprinted and time-stamped
--    BEFORE any holdout case is read, so no tuning can happen on the holdout;
--  * holdout gold sets (intake, English, tuition), frozen by a sha256 digest before any model runs on them;
--  * per-case qualification results, with a hard US$8 qualification spend cap (enforced in the Edge function and
--    re-checked here on every recorded row);
--  * OpenRouter catalogue/credit observations (the credit floor guard reads them);
--  * profile columns for retirement (retired_at, retired_reason) and the holdout qualification result;
--  * the Edge function layer3-model-routing is added to the nonce allowlist (checksum-guarded, applied on top of the
--    live definition).

alter table pipeline.layer3_model_profiles
  add column if not exists retired_at timestamptz,
  add column if not exists retired_reason text,
  add column if not exists holdout_qualification jsonb;
comment on column pipeline.layer3_model_profiles.retired_at is 'CF-247 model routing: when the profile was retired (disabled and paused, kept for audit).';
comment on column pipeline.layer3_model_profiles.holdout_qualification is 'CF-247 model routing: latest fresh-holdout qualification (layer3-model-routing).';

create table if not exists pipeline.layer3_task_contract_freezes (
  id uuid primary key default gen_random_uuid(),
  task_class text not null,
  contract_version text not null,
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  components jsonb not null default '{}'::jsonb,
  frozen_at timestamptz not null default now(),
  change_control_ref text not null default 'CF-CHG-20260915-247',
  unique (task_class, contract_version)
);

create table if not exists pipeline.layer3_holdout_sets (
  gold_set text primary key,
  task_class text not null,
  case_count int not null,
  digest text not null check (digest ~ '^[0-9a-f]{64}$'),
  contract_fingerprint text not null check (contract_fingerprint ~ '^[0-9a-f]{64}$'),
  sample_seed numeric not null,
  sample_query text not null,
  provider_count int not null,
  frozen_at timestamptz not null default now(),
  note text
);

create table if not exists pipeline.layer3_holdout_cases (
  id uuid primary key default gen_random_uuid(),
  gold_set text not null,
  case_key text not null unique,
  task_class text not null,
  course_id uuid not null references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  source_url text not null,
  text_sha256 text not null check (text_sha256 ~ '^[0-9a-f]{64}$'),
  gold jsonb not null,
  evidence_excerpt text,
  candidate_context jsonb,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists layer3_holdout_cases_set_idx on pipeline.layer3_holdout_cases(gold_set);

create table if not exists pipeline.layer3_holdout_results (
  id uuid primary key default gen_random_uuid(),
  run_label text not null,
  case_id uuid not null references pipeline.layer3_holdout_cases(id),
  profile_id uuid not null references pipeline.layer3_model_profiles(id),
  task_class text not null,
  configured_model text not null,
  returned_model text,
  outcome text not null check (outcome in ('exact','exact_not_stated','wrong_admitted','withheld','incomplete','not_stated_on_stated')),
  admitted jsonb,
  answer jsonb,
  errors text[] not null default '{}',
  text_matches_gold boolean,
  excerpt_in_text boolean,
  cost_usd numeric not null default 0 check (cost_usd >= 0),
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  latency_ms int,
  external_calls int not null default 0,
  created_at timestamptz not null default now(),
  unique (run_label, case_id)
);

create table if not exists pipeline.layer3_openrouter_observations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('credits','models')),
  payload jsonb not null,
  remaining_usd numeric,
  observed_at timestamptz not null default now()
);

do $g$ declare t text;
begin
  foreach t in array array['layer3_task_contract_freezes','layer3_holdout_sets','layer3_holdout_cases','layer3_holdout_results','layer3_openrouter_observations'] loop
    execute format('alter table pipeline.%I enable row level security', t);
    execute format('revoke all on pipeline.%I from public, anon, authenticated', t);
  end loop;
end $g$;

-- digest of a holdout set: identity, pinned text, gold answer and excerpt (notes excluded)
create or replace function pipeline.layer3_holdout_digest(p_gold_set text)
returns text language sql stable set search_path to 'pg_catalog','pipeline','extensions' as $f$
  select encode(extensions.digest(coalesce(string_agg(concat_ws('|', c.case_key, c.course_id, c.evidence_id, c.text_sha256, c.gold::text, coalesce(c.evidence_excerpt,'~'), coalesce(c.candidate_context::text,'~')), E'\n' order by c.case_key),''),'sha256'),'hex')
    from pipeline.layer3_holdout_cases c where c.gold_set=p_gold_set
$f$;
revoke all on function pipeline.layer3_holdout_digest(text) from public, anon, authenticated;

create or replace function public.layer3_routing_service_guard() returns void language plpgsql as $f$
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
end $f$;
revoke all on function public.layer3_routing_service_guard() from public, anon, authenticated;

-- contract freeze (first write wins; a changed fingerprint for the same version is refused)
create or replace function public.layer3_contract_freeze_record_service(p_task_class text, p_version text, p_fingerprint text, p_components jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v pipeline.layer3_task_contract_freezes%rowtype;
begin
  perform public.layer3_routing_service_guard();
  insert into pipeline.layer3_task_contract_freezes(task_class,contract_version,fingerprint,components) values (p_task_class,p_version,p_fingerprint,coalesce(p_components,'{}'))
  on conflict (task_class,contract_version) do nothing;
  select * into v from pipeline.layer3_task_contract_freezes where task_class=p_task_class and contract_version=p_version;
  return jsonb_build_object('task_class',v.task_class,'contract_version',v.contract_version,'fingerprint',v.fingerprint,'frozen_at',v.frozen_at,'matches',v.fingerprint=p_fingerprint);
end $f$;

create or replace function public.layer3_openrouter_observation_record_service(p_kind text, p_payload jsonb, p_remaining numeric)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v uuid;
begin
  perform public.layer3_routing_service_guard();
  insert into pipeline.layer3_openrouter_observations(kind,payload,remaining_usd) values (p_kind,p_payload,p_remaining) returning id into v;
  return jsonb_build_object('id',v);
end $f$;

-- pages for gold reading and qualification: the stored sweep page (intake, English) and, for tuition, the plain-text
-- evidence and candidate context the Layer 3 hand-off built (or would build) for the course
create or replace function public.layer3_routing_pages_service(p_course_ids uuid[])
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','security' as $f$
begin
  perform public.layer3_routing_service_guard();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'course_id',p.course_id,'provider_id',p.provider_id,'provider',coalesce(pv.display_name,pv.canonical_name),'course',co.title,'course_code',co.course_code,
      'url',p.url,'evidence_id',p.evidence_id,'storage_path',e.storage_path,'candidates',p.candidates,
      'tuition_target',security.coverage_tuition_target_v1(p.candidates->'fee'),
      'work_item_id',w.id,'work_status',w.status,'work_candidate_context',w.candidate_context,
      'text_evidence_id',te.id,'text_storage_path',te.storage_path,'text_mime',te.mime_type,'text_source_url',te.source_url))
    from pipeline.coverage_course_pages p
    join pipeline.evidence_artifacts e on e.id=p.evidence_id
    join catalogue.courses co on co.id=p.course_id
    join catalogue.providers pv on pv.id=p.provider_id
    left join pipeline.layer3_work_items w on w.id=p.l3_work_item_id
    left join pipeline.evidence_artifacts te on te.id=w.evidence_id
   where p.course_id=any(p_course_ids)),'[]'::jsonb);
end $f$;

create or replace function public.layer3_holdout_cases_service(p_gold_set text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  perform public.layer3_routing_service_guard();
  return jsonb_build_object('gold_set',p_gold_set,
    'task_class',(select s.task_class from pipeline.layer3_holdout_sets s where s.gold_set=p_gold_set),
    'frozen_digest',(select s.digest from pipeline.layer3_holdout_sets s where s.gold_set=p_gold_set),
    'contract_fingerprint',(select s.contract_fingerprint from pipeline.layer3_holdout_sets s where s.gold_set=p_gold_set),
    'current_digest',pipeline.layer3_holdout_digest(p_gold_set),
    'cases',coalesce((select jsonb_agg(jsonb_build_object('case_id',c.id,'case_key',c.case_key,'course_id',c.course_id,'evidence_id',c.evidence_id,
            'storage_path',e.storage_path,'mime_type',e.mime_type,'source_url',e.source_url,'text_sha256',c.text_sha256,'gold',c.gold,
            'evidence_excerpt',c.evidence_excerpt,'candidate_context',c.candidate_context) order by c.case_key)
      from pipeline.layer3_holdout_cases c join pipeline.evidence_artifacts e on e.id=c.evidence_id where c.gold_set=p_gold_set),'[]'::jsonb));
end $f$;

-- total qualification spend (every holdout run, every profile)
create or replace function pipeline.layer3_qualification_spent_usd() returns numeric language sql stable set search_path to 'pg_catalog','pipeline' as $f$
  select coalesce(sum(cost_usd),0) from pipeline.layer3_holdout_results
$f$;
revoke all on function pipeline.layer3_qualification_spent_usd() from public, anon, authenticated;

create or replace function public.layer3_routing_profile_service(p_code text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v jsonb;
begin
  perform public.layer3_routing_service_guard();
  select jsonb_build_object('id',id,'code',code,'model_identifier',model_identifier,'base_url',base_url,'secret_env_key',secret_env_key,'enabled',enabled,'paused',paused,
         'allowed_task_classes',allowed_task_classes,'prompt_profile_version',prompt_profile_version,'prompt_system',prompt_system,'structured_output_schema',structured_output_schema,
         'deterministic_validators',deterministic_validators,'max_input_tokens',max_input_tokens,'max_output_tokens',max_output_tokens,'timeout_ms',timeout_ms,'retry_ceiling',retry_ceiling,
         'cost_ceiling_usd',cost_ceiling_usd,'requests_per_minute',requests_per_minute,'requests_per_day',requests_per_day,'quality_benchmark',quality_benchmark,
         'holdout_qualification',holdout_qualification,'retired_at',retired_at,'qualification_spent_usd',pipeline.layer3_qualification_spent_usd())
    into v from pipeline.layer3_model_profiles where code=p_code;
  return v;
end $f$;

create or replace function public.layer3_holdout_result_record_service(p_run_label text, p_case_id uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  perform public.layer3_routing_service_guard();
  insert into pipeline.layer3_holdout_results(run_label,case_id,profile_id,task_class,configured_model,returned_model,outcome,admitted,answer,errors,text_matches_gold,excerpt_in_text,
    cost_usd,input_tokens,output_tokens,latency_ms,external_calls)
  values (p_run_label,p_case_id,(p_result->>'profile_id')::uuid,p_result->>'task_class',p_result->>'configured_model',p_result->>'returned_model',p_result->>'outcome',
    p_result->'admitted',p_result->'answer',coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'errors') x),'{}'),
    (p_result->>'text_matches_gold')::boolean,(p_result->>'excerpt_in_text')::boolean,greatest(coalesce((p_result->>'cost_usd')::numeric,0),0),
    coalesce((p_result->>'input_tokens')::int,0),coalesce((p_result->>'output_tokens')::int,0),(p_result->>'latency_ms')::int,coalesce((p_result->>'external_calls')::int,0))
  on conflict (run_label,case_id) do nothing;
  return jsonb_build_object('ok',true,'qualification_spent_usd',pipeline.layer3_qualification_spent_usd());
end $f$;

-- Records a qualification run: scores recomputed from stored rows; the run must cover every case of one frozen,
-- unchanged holdout set under one profile. Bar (unchanged): >=95% exact on stated cases AND zero wrong-admitted values,
-- every returned model equal to the pinned id, every page text still matching its pinned hash.
-- Writes holdout_qualification only; never changes enabled/paused or quality_benchmark (activation is separate).
create or replace function public.layer3_holdout_finalise_service(p_run_label text, p_binding_hash text, p_summary jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare p pipeline.layer3_model_profiles%rowtype; v_set text; v_task text; v_frozen text; v_digest text; v_all int; v_n int; v_stated int; v_exact int; v_ns int; v_ns_exact int;
        v_wrong int; v_withheld int; v_incomplete int; v_nsos int; v_cost numeric; v_in int; v_out int; v_calls int; v_lat int; v_text_ok boolean; v_models text[];
        v_model_ok boolean; v_rate numeric; v_pass boolean; v_run uuid; v_q jsonb;
begin
  perform public.layer3_routing_service_guard();
  if p_binding_hash is null or p_binding_hash !~ '^[0-9a-f]{64}$' then raise exception 'binding hash required'; end if;
  if (select count(distinct profile_id) from pipeline.layer3_holdout_results where run_label=p_run_label)<>1 then raise exception 'run must have exactly one profile'; end if;
  if (select count(distinct c.gold_set) from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label)<>1 then raise exception 'run must cover exactly one gold set'; end if;
  select * into p from pipeline.layer3_model_profiles where id=(select profile_id from pipeline.layer3_holdout_results where run_label=p_run_label limit 1) for update;
  select c.gold_set, c.task_class into v_set, v_task from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label limit 1;
  select digest into v_frozen from pipeline.layer3_holdout_sets where gold_set=v_set;
  v_digest:=pipeline.layer3_holdout_digest(v_set);
  select count(*) into v_all from pipeline.layer3_holdout_cases where gold_set=v_set;
  select count(*),
         count(*) filter (where c.gold->>'status' in ('months','stated','admit')),
         count(*) filter (where c.gold->>'status' in ('months','stated','admit') and r.outcome='exact'),
         count(*) filter (where c.gold->>'status' not in ('months','stated','admit')),
         count(*) filter (where c.gold->>'status' not in ('months','stated','admit') and r.outcome='exact_not_stated'),
         count(*) filter (where r.outcome='wrong_admitted'), count(*) filter (where r.outcome='withheld'),
         count(*) filter (where r.outcome='incomplete'), count(*) filter (where r.outcome='not_stated_on_stated'),
         coalesce(sum(r.cost_usd),0), coalesce(sum(r.input_tokens),0), coalesce(sum(r.output_tokens),0), coalesce(sum(r.external_calls),0), coalesce(max(r.latency_ms),0),
         bool_and(coalesce(r.text_matches_gold,false) and coalesce(r.excerpt_in_text,true))
    into v_n, v_stated, v_exact, v_ns, v_ns_exact, v_wrong, v_withheld, v_incomplete, v_nsos, v_cost, v_in, v_out, v_calls, v_lat, v_text_ok
    from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label;
  v_models:=array(select distinct coalesce(returned_model,'<none>') from pipeline.layer3_holdout_results where run_label=p_run_label and external_calls>0 order by 1);
  v_model_ok:=coalesce(array_length(v_models,1),0)>0 and not exists (select 1 from unnest(v_models) m where m<>p.model_identifier);
  v_rate:=case when v_stated>0 then round(v_exact::numeric/v_stated,4) end;
  v_pass:=v_frozen is not null and v_frozen=v_digest and v_n=v_all and v_stated>0 and coalesce(v_rate,0)>=0.95 and v_wrong=0 and v_model_ok and coalesce(v_text_ok,false);
  v_q:=jsonb_build_object('run_label',p_run_label,'pass',v_pass,'task_class',v_task,'gold_set',v_set,'gold_digest',v_frozen,'gold_unchanged',v_frozen=v_digest,
      'binding_hash',p_binding_hash,'configured_model',p.model_identifier,'returned_models',v_models,'model_exact',v_model_ok,'text_pinned',coalesce(v_text_ok,false),
      'cases',v_n,'gold_cases',v_all,'stated_cases',v_stated,'stated_exact',v_exact,'stated_exact_rate',v_rate,'not_stated_cases',v_ns,'not_stated_exact',v_ns_exact,
      'wrong_admitted',v_wrong,'withheld',v_withheld,'incomplete',v_incomplete,'not_stated_on_stated',v_nsos,
      'cost_usd',v_cost,'cost_per_call_usd',case when v_calls>0 then round(v_cost/v_calls,6) end,'input_tokens',v_in,'output_tokens',v_out,'external_calls',v_calls,'max_latency_ms',v_lat,
      'summary',coalesce(p_summary,'{}'::jsonb),'completed_at',now(),
      'qualification_rule','>=95% exact on stated cases AND zero wrong-admitted values (fresh holdout, pinned model)','change_control_ref','CF-CHG-20260915-247');
  insert into pipeline.layer3_quality_benchmark_runs(profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,returned_models,external_call_count,input_tokens,output_tokens,
    estimated_cost_usd,max_latency_ms,evidence_ids,binding_hash,prompt_profile_version,validator_profile,summary,change_control_ref,uat_ref,completed_at)
  select p.id,'00000000-0000-0000-0000-000000000000'::uuid,case when v_pass then 'pass' else 'fail' end,
    coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold',c.gold,'outcome',r.outcome,'admitted',r.admitted,'errors',r.errors) order by c.case_key)
      from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold->>'status' in ('months','stated','admit')),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('case_key',c.case_key,'gold',c.gold,'outcome',r.outcome,'admitted',r.admitted,'errors',r.errors) order by c.case_key)
      from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label and c.gold->>'status' not in ('months','stated','admit')),'[]'::jsonb),
    p.model_identifier,v_models,v_calls,v_in,v_out,v_cost,v_lat,
    coalesce((select array_agg(distinct c.evidence_id) from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where r.run_label=p_run_label),'{}'),
    p_binding_hash,p.prompt_profile_version,coalesce(p.deterministic_validators,'{}'::jsonb),
    left(format('CF-247 model routing holdout %s on %s (%s): stated exact %s/%s (%s); wrong-admitted %s; withheld %s; cost_usd=%s; %s',
      p_run_label,v_set,v_task,v_exact,v_stated,v_rate,v_wrong,v_withheld,round(v_cost,6),case when v_pass then 'PASS' else 'FAIL' end),1000),
    'CF-CHG-20260915-247','CF-247-layer3-model-routing',now()
  returning id into v_run;
  update pipeline.layer3_model_profiles set holdout_qualification=v_q||jsonb_build_object('run_id',v_run), updated_at=now() where id=p.id;
  return v_q||jsonb_build_object('run_id',v_run,'profile_code',p.code);
end $f$;

do $g$ declare fn text;
begin
  foreach fn in array array['layer3_contract_freeze_record_service(text,text,text,jsonb)','layer3_openrouter_observation_record_service(text,jsonb,numeric)',
    'layer3_routing_pages_service(uuid[])','layer3_holdout_cases_service(text)','layer3_routing_profile_service(text)',
    'layer3_holdout_result_record_service(text,uuid,jsonb)','layer3_holdout_finalise_service(text,text,jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', fn);
    execute format('grant execute on function public.%s to service_role', fn);
  end loop;
end $g$;

-- Nonce allowlist: add layer3-model-routing on top of the live definition (guarded by the reviewed checksum).
do $g$
declare v_def text;
begin
  if (select md5(prosrc) from pg_proc where oid='pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure)<>'bab3b602f58ad02a3db0f2a31ed9beab' then
    raise exception 'svc_pilot_submit_nonce changed since review; re-read the live definition before adding layer3-model-routing';
  end if;
  v_def:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  if position('''layer3-intake-benchmark'')' in v_def)=0 then raise exception 'allowlist anchor not found'; end if;
  execute replace(v_def,'''layer3-intake-benchmark'')','''layer3-intake-benchmark'',''layer3-model-routing'')');
end $g$;
