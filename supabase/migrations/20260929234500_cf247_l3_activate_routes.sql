-- CF-CHG-20260915-247 Layer 3 model routing: ACTIVATION, under Platform Admin direction 29 Sep 2026 18:30 IST
-- (CF-CHG-20260915-247). "Use stronger models, qualify per task class, route to the cheapest passing model, retire
-- unused profiles, automate admission with Layer 3 routine profiles."
--
-- Fresh-holdout results (frozen contracts and holdout sets, pinned models, bar unchanged: >=95% exact on stated cases
-- AND zero wrong-admitted values):
--   provider_intake_validation   only anthropic/claude-sonnet-4.6 passed (13/13 stated, 0 wrong, 3 of 34 not-stated
--                                withheld; US$0.0114 a call). It is the cheapest (only) passing model.
--   provider_english_validation  only anthropic/claude-sonnet-4.6 passed (19/19 stated, 0 wrong, 0 withheld;
--                                US$0.0107 a call).
--   provider_current_tuition_validation  only qwen/qwen3-235b-a22b-2507 passed (8/8 admissible fees exact, 0 wrong,
--                                9 of 28 not-admissible withheld; US$0.00055 a call). The incumbent
--                                mistral-small-3.2 did NOT pass the fresh holdout (6/8, 0 wrong, 24 withheld), so the
--                                route switches to qwen3-235b-2507 (better numbers on the same frozen holdout).
-- No other candidate passed, so no fallback is set for any task class.
--
-- This migration:
--  1. records each passing fresh-holdout qualification as the profile's quality_benchmark (same binding hash), enables
--     and unpauses exactly one profile per task class, and logs an 'activated' event;
--  2. pauses the incumbent tuition profile and moves its not-yet-started tuition work to the new profile (the one item
--     already being interpreted finishes under the old profile);
--  3. retires every unused or failed Layer 3 profile (disabled, paused, retired_at + reason; nothing deleted;
--     scholarship profiles untouched);
--  4. daily spend guards: intake US$4, English US$4, tuition US$5 (tuition enforced in the dispatch headroom);
--  5. schedules the intake and English routes (rate-limited), their governed admission, a credit-floor guard (all
--     Layer 3 route crons stop below US$5 of OpenRouter credit), and raises the tuition hand-off from 20 to 50 pages
--     per 10 minutes.

-- 0. preconditions: the three holdout sets are still frozen as run, and each profile's qualification is a pass on them
do $pre$
declare r record;
begin
  if (select count(*) from pipeline.layer3_holdout_sets where gold_set in ('l3r-intake-h1','l3r-english-h1','l3r-tuition-h1')
        and digest=pipeline.layer3_holdout_digest(gold_set))<>3 then
    raise exception 'a holdout set changed after it was frozen; activation refused';
  end if;
  for r in select p.code, p.model_identifier, p.holdout_qualification q, s.digest
             from pipeline.layer3_model_profiles p
             join pipeline.layer3_holdout_sets s on s.gold_set=p.holdout_qualification->>'gold_set'
            where p.code in ('openrouter-intake-l3r-claude-sonnet-4-6-v1','openrouter-english-l3r-claude-sonnet-4-6-v1','openrouter-tuition-l3r-qwen3-235b-2507-v1') loop
    if not coalesce((r.q->>'pass')::boolean,false) or coalesce((r.q->>'wrong_admitted')::int,-1)<>0 or coalesce((r.q->>'incomplete')::int,-1)<>0
       or coalesce((r.q->>'stated_exact_rate')::numeric,0)<0.95 or not coalesce((r.q->>'model_exact')::boolean,false)
       or not coalesce((r.q->>'text_pinned')::boolean,false) or r.q->>'gold_digest' is distinct from r.digest
       or r.q->>'configured_model' is distinct from r.model_identifier or nullif(r.q->>'binding_hash','') is null then
      raise exception 'profile % does not hold a passing fresh-holdout qualification; activation refused', r.code;
    end if;
  end loop;
  if (select count(*) from pipeline.layer3_model_profiles
       where code in ('openrouter-intake-l3r-claude-sonnet-4-6-v1','openrouter-english-l3r-claude-sonnet-4-6-v1','openrouter-tuition-l3r-qwen3-235b-2507-v1'))<>3 then
    raise exception 'expected three qualified profiles';
  end if;
  if exists (select 1 from pg_proc where oid='public.layer3_dispatch_headroom_service(text)'::regprocedure and md5(prosrc)<>'eef1df739175da919f50a66ac2428a7b') then
    raise exception 'public.layer3_dispatch_headroom_service changed since it was read; re-read and re-apply';
  end if;
end $pre$;

alter table pipeline.layer3_profile_activation_events drop constraint layer3_profile_activation_events_action_check;
alter table pipeline.layer3_profile_activation_events add constraint layer3_profile_activation_events_action_check
  check (action = any (array['activated','activation_refused','paused','auto_paused_binding_drift','throughput_changed','retired']));

-- 1. pause the incumbent tuition profile first (only one executable profile per task class at any time)
update pipeline.layer3_model_profiles set paused=true, updated_at=now()
 where code='openrouter-provider-tuition-validation-mistral-small-3-2-v1';
insert into pipeline.layer3_profile_activation_events(profile_id,action,actor_id,reason,binding_hash,benchmark_run_id,checks,change_control_ref)
select id,'paused',null,
       'Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247): superseded on the tuition route by qwen3-235b-2507, which passed the fresh holdout l3r-tuition-h1 (8/8, 0 wrong); this profile did not (6/8, 0 wrong, 24 withheld)',
       quality_benchmark->>'binding_hash', holdout_qualification->>'run_id',
       jsonb_build_object('holdout',holdout_qualification-'summary','superseded_by','openrouter-tuition-l3r-qwen3-235b-2507-v1'),
       'CF-CHG-20260915-247'
  from pipeline.layer3_model_profiles where code='openrouter-provider-tuition-validation-mistral-small-3-2-v1';

-- 2. activate the three qualified profiles: quality_benchmark := the passing fresh-holdout qualification (its binding hash
--    is what the worker must present at run time)
update pipeline.layer3_model_profiles p
   set quality_benchmark = p.holdout_qualification || jsonb_build_object('qualification_source','fresh_holdout','activated_under',
         'Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247)'),
       last_validation_result = jsonb_build_object('state','qualified_on_fresh_holdout','validated',true,'run_id',p.holdout_qualification->>'run_id'),
       enabled=true, paused=false, retired_at=null, retired_reason=null, fallback_profile_id=null, updated_at=now()
 where p.code in ('openrouter-intake-l3r-claude-sonnet-4-6-v1','openrouter-english-l3r-claude-sonnet-4-6-v1','openrouter-tuition-l3r-qwen3-235b-2507-v1');
insert into pipeline.layer3_profile_activation_events(profile_id,action,actor_id,reason,binding_hash,benchmark_run_id,checks,change_control_ref)
select id,'activated',null,
       'Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247): cheapest (only) model to pass the fresh holdout '||(holdout_qualification->>'gold_set')
         ||' for '||(holdout_qualification->>'task_class')||' ('||(holdout_qualification->>'stated_exact')||'/'||(holdout_qualification->>'stated_cases')
         ||' stated exact, 0 wrong-admitted, US$'||(holdout_qualification->>'cost_per_call_usd')||' a call)',
       holdout_qualification->>'binding_hash', holdout_qualification->>'run_id',
       jsonb_build_object('holdout',holdout_qualification-'summary','qualification_rule',holdout_qualification->>'qualification_rule','fallback',null),
       'CF-CHG-20260915-247'
  from pipeline.layer3_model_profiles
 where code in ('openrouter-intake-l3r-claude-sonnet-4-6-v1','openrouter-english-l3r-claude-sonnet-4-6-v1','openrouter-tuition-l3r-qwen3-235b-2507-v1');

-- tuition work not yet started moves to the new profile (dispatch reserves only work of the active profile)
update pipeline.layer3_work_items w set profile_id=(select id from pipeline.layer3_model_profiles where code='openrouter-tuition-l3r-qwen3-235b-2507-v1'), updated_at=now()
 where w.task_class='provider_current_tuition_validation' and w.status in ('pending','failed')
   and w.profile_id=(select id from pipeline.layer3_model_profiles where code='openrouter-provider-tuition-validation-mistral-small-3-2-v1');

-- 3. retire every other Layer 3 profile that is failed or unused (never deleted; scholarship profiles are not touched)
with r(code, reason) as (values
  ('openrouter-intake-l3r-gpt-4-1-mini-v1','failed fresh holdout l3r-intake-h1 (11/12 stated on 46 of 47 cases, 2 wrong)'),
  ('openrouter-intake-l3r-gemini-2-5-flash-v1','failed fresh holdout l3r-intake-h1 (11/13 stated, 2 wrong)'),
  ('openrouter-intake-l3r-qwen3-235b-2507-v1','failed fresh holdout l3r-intake-h1 (12/13 stated, 1 wrong)'),
  ('openrouter-intake-l3r-deepseek-v3-2-v1','failed fresh holdout l3r-intake-h1 (12/13 stated, 1 wrong)'),
  ('openrouter-intake-l3r-claude-haiku-4-5-v1','failed fresh holdout l3r-intake-h1 (12/13 stated, 0 wrong)'),
  ('openrouter-english-l3r-gpt-4-1-mini-v1','failed fresh holdout l3r-english-h1 (17/19 stated)'),
  ('openrouter-english-l3r-gemini-2-5-flash-v1','failed fresh holdout l3r-english-h1 (18/19 stated)'),
  ('openrouter-english-l3r-qwen3-235b-2507-v1','failed fresh holdout l3r-english-h1 (14/19 stated)'),
  ('openrouter-english-l3r-deepseek-v3-2-v1','failed fresh holdout l3r-english-h1 (17/19 stated)'),
  ('openrouter-english-l3r-claude-haiku-4-5-v1','failed fresh holdout l3r-english-h1 (18/19 stated, 0 wrong)'),
  ('openrouter-tuition-l3r-gpt-4-1-mini-v1','failed fresh holdout l3r-tuition-h1 (6/8 admissible fees)'),
  ('openrouter-tuition-l3r-gemini-2-5-flash-v1','failed fresh holdout l3r-tuition-h1 (7/8 admissible fees)'),
  ('openrouter-tuition-l3r-deepseek-v3-2-v1','failed fresh holdout l3r-tuition-h1 (3/8 admissible fees)'),
  ('openrouter-provider-tuition-validation-mistral-small-3-2-v1','superseded on the tuition route; failed fresh holdout l3r-tuition-h1 (6/8, 0 wrong, 24 withheld)'),
  ('openrouter-provider-tuition-validation-claude-haiku-4-5-v1','unused: earlier tuition candidate that did not pass its benchmark'),
  ('openrouter-provider-tuition-validation-deepseek-v3-2-v1','unused: earlier tuition candidate that did not pass its benchmark'),
  ('openrouter-provider-tuition-validation-gemini-2-5-flash-v1','unused: earlier tuition candidate that did not pass its benchmark'),
  ('openrouter-provider-tuition-validation-gpt-oss-20b-v1','unused: earlier tuition candidate that did not pass its benchmark'),
  ('openrouter-provider-tuition-validation-v1','unused: free nemotron tuition profile, did not pass its benchmark'),
  ('openrouter-provider-intake-validation-mistral-medium-3-1-v1','unused: intake profile that did not pass its benchmark; intake now routes to claude-sonnet-4.6'),
  ('openrouter-provider-intake-validation-mistral-small-3-2-v1','unused: intake profile that did not pass its benchmark; intake now routes to claude-sonnet-4.6'),
  ('openrouter-free-router-v1','unused: paused free nemotron profile (course_description, official_course_url, delivery_mode, duration)'),
  ('openrouter-international-contact-v1','unused: paused free nemotron profile (international_contact)'),
  ('openrouter-source-pattern-v1','unused: paused free nemotron profile (source_pattern)')),
upd as (
  update pipeline.layer3_model_profiles p
     set enabled=false, paused=true, retired_at=now(),
         retired_reason='Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247): '||r.reason, updated_at=now()
    from r where p.code=r.code and p.retired_at is null
     and not (p.allowed_task_classes && array['scholarship_page_classification','scholarship_detail_extract'])
  returning p.id, p.retired_reason, p.quality_benchmark->>'binding_hash' bh)
insert into pipeline.layer3_profile_activation_events(profile_id,action,actor_id,reason,binding_hash,benchmark_run_id,checks,change_control_ref)
select id,'retired',null,retired_reason,bh,null,jsonb_build_object('enabled',false,'paused',true),'CF-CHG-20260915-247' from upd;

-- 4. daily spend guards (US$ a day, per task class)
insert into pipeline.layer3_route_budget(task_class,daily_usd_max,note) values
  ('provider_intake_validation',4,'Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247): claude-sonnet-4.6 about US$0.011 a call'),
  ('provider_english_validation',4,'Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247): claude-sonnet-4.6 about US$0.011 a call'),
  ('provider_current_tuition_validation',5,'Platform Admin approval 29 Sep 2026 (spend ceiling US$5 a day), enforced in public.layer3_dispatch_headroom_service')
on conflict (task_class) do update set daily_usd_max=excluded.daily_usd_max, note=excluded.note, updated_at=now();

-- tuition dispatch headroom: also refuses a retired profile and stops for the day at the task's spend guard
create or replace function public.layer3_dispatch_headroom_service(p_task_class text DEFAULT 'provider_current_tuition_validation'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare
  v_caller text;
  v_p pipeline.layer3_model_profiles%rowtype;
  v_usage jsonb;
  v_minute integer;
  v_day integer;
  v_minute_headroom integer;
  v_day_headroom integer;
  v_day_cost numeric;
  v_budget numeric;
begin
  v_caller:=coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    nullif(current_setting('request.jwt.role',true),''),
    nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',
    auth.role(),
    session_user
  );
  if v_caller not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_p
  from pipeline.layer3_model_profiles
  where p_task_class=any(allowed_task_classes)
    and enabled and not paused and retired_at is null
    and coalesce((quality_benchmark->>'pass')::boolean,false)
  order by updated_at desc,id
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok',false,'reason','no_qualified_executable_profile',
      'task_class',p_task_class,'minute_headroom',0,'day_headroom',0,'dispatch_headroom',0
    );
  end if;

  v_usage:=public.layer3_usage_window_service(v_p.id);
  v_minute:=coalesce((v_usage->>'minute_calls')::integer,0);
  v_day:=coalesce((v_usage->>'day_calls')::integer,0);
  v_minute_headroom:=greatest(v_p.requests_per_minute-v_minute,0);
  v_day_headroom:=greatest(v_p.requests_per_day-v_day,0);
  v_day_cost:=coalesce((v_usage->>'day_cost_usd')::numeric,0);
  select b.daily_usd_max into v_budget from pipeline.layer3_route_budget b where b.task_class=p_task_class;
  if v_budget is not null and v_day_cost>=v_budget then
    return jsonb_build_object(
      'ok',false,'reason','daily_spend_guard','task_class',p_task_class,'profile_id',v_p.id,'profile_code',v_p.code,
      'day_cost_usd',v_day_cost,'daily_usd_max',v_budget,'minute_headroom',0,'day_headroom',0,'dispatch_headroom',0
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'profile_id',v_p.id,
    'profile_code',v_p.code,
    'task_class',p_task_class,
    'minute_calls',v_minute,
    'minute_limit',v_p.requests_per_minute,
    'minute_headroom',v_minute_headroom,
    'day_calls',v_day,
    'day_limit',v_p.requests_per_day,
    'day_headroom',v_day_headroom,
    'dispatch_headroom',least(v_minute_headroom,v_day_headroom),
    'day_cost_usd',v_day_cost,
    'daily_usd_max',v_budget,
    'day_input_tokens',coalesce((v_usage->>'day_input_tokens')::bigint,0),
    'day_output_tokens',coalesce((v_usage->>'day_output_tokens')::bigint,0),
    'live_day_calls',coalesce((v_usage->>'live_day_calls')::integer,0),
    'benchmark_day_calls',coalesce((v_usage->>'benchmark_day_calls')::integer,0),
    'day_resets_at',date_trunc('day',now())+interval '1 day'
  );
end $function$;

-- 5. schedules (rate-limited): intake and English routes every 2 minutes (8 pages a run, 4 at a time), offset by a
--    minute; governed admission every 5 minutes; credit-floor guard every 10 minutes; tuition hand-off 50 per 10 minutes
select cron.schedule('layer3-intake-route','*/2 * * * *',
  $$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"work","task":"intake","limit":8,"concurrency":4}'::jsonb)$$);
select cron.schedule('layer3-english-route','1-59/2 * * * *',
  $$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"work","task":"english","limit":8,"concurrency":4}'::jsonb)$$);
select cron.schedule('layer3-fact-admit','3-59/5 * * * *',
  $$select security.layer3_fact_admit_v1('provider_intake_validation',100), security.layer3_fact_admit_v1('provider_english_validation',100)$$);
select cron.schedule('layer3-route-guard','*/10 * * * *',
  $$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"guard"}'::jsonb)$$);
select cron.schedule('coverage-tuition-handoff','*/10 * * * *',
  $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"tuition_handoff","limit":50}'::jsonb)$$);

insert into pipeline.layer3_route_events(kind,detail) values ('routes_activated',jsonb_build_object(
  'direction','Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247)',
  'provider_intake_validation','openrouter-intake-l3r-claude-sonnet-4-6-v1',
  'provider_english_validation','openrouter-english-l3r-claude-sonnet-4-6-v1',
  'provider_current_tuition_validation','openrouter-tuition-l3r-qwen3-235b-2507-v1',
  'fallbacks','none (no other candidate passed)',
  'daily_usd_max',jsonb_build_object('intake',4,'english',4,'tuition',5),'credit_floor_usd',5,
  'tuition_handoff_per_10_min',jsonb_build_object('from',20,'to',50)));

-- post-conditions: exactly one executable, qualified profile per task class, and it is the qualified one
do $post$
declare t text; c text;
begin
  foreach t in array array['provider_intake_validation','provider_english_validation','provider_current_tuition_validation'] loop
    if (select count(*) from pipeline.layer3_model_profiles where t=any(allowed_task_classes) and enabled and not paused)<>1 then
      raise exception 'expected exactly one executable profile for %', t;
    end if;
  end loop;
  select code into c from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused;
  if c<>'openrouter-tuition-l3r-qwen3-235b-2507-v1' then raise exception 'tuition route is %', c; end if;
  if (pipeline.layer3_routed_profile('provider_intake_validation')).code is distinct from 'openrouter-intake-l3r-claude-sonnet-4-6-v1'
     or (pipeline.layer3_routed_profile('provider_english_validation')).code is distinct from 'openrouter-english-l3r-claude-sonnet-4-6-v1' then
    raise exception 'intake/English routed profile not as qualified';
  end if;
end $post$;
