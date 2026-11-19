-- CF-CHG-20260915-247 Layer 3 cost-tiered cascade: LADDER RUNTIME AND ACTIVATION (intake and English).
-- Platform Admin direction, 29 Sep 2026 (21:08 IST): "use openrouter model routing in layer 3, use cheapest one with 80%
-- success rates and for failed one use higher cost model and so on ... be cost effective using model when required".
--
-- Rule (recorded per tier, enforced below):
--   * a tier needs >= 80% right (exact + correctly not stated) AND 0 wrong-admitted on the task's FROZEN holdout set;
--     escalation only rescues answers a model did not give, it cannot catch a confident wrong answer;
--   * tiers are ordered by measured cost per call, cheapest first; the final tier is the qualified single-route model;
--   * a page moves up a tier when the answer fails the automatic checks (no verbatim quote, validator rejection,
--     incomplete, provider error, returned-model mismatch) or says "not stated" while the page shows a clear signal
--     (month names near intake words; an English test name with a score);
--   * 5% of answers accepted below the final tier are re-asked to the final tier; a disagreement sends the course to
--     Layer 4 with both answers, and 3 disagreements in a tier's last 60 audits pause that tier (logged; never re-promoted
--     automatically);
--   * admission, write-only-when-empty, differences to Layer 4, daily spend guards and the credit floor are unchanged.
-- Simulation on the frozen holdouts (escalating on failed checks): intake 43/45 right, 0 wrong, US$1.29 per 1,000 pages
-- (US$10.94 with the final tier alone); English 36/37 right, 0 wrong, US$0.17 per 1,000 (US$10.72).
-- Tuition keeps its single qualified route (Qwen3 235B 2507, US$0.55 per 1,000) for now.

-- 1. audits of accepted lower-tier answers
create table if not exists pipeline.layer3_tier_audits (
  id bigint generated always as identity primary key,
  task_class text not null, tier_no int not null, profile_id uuid not null, audit_profile_id uuid not null,
  work_item_id uuid, agree boolean not null, detail jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
alter table pipeline.layer3_tier_audits enable row level security;
revoke all on pipeline.layer3_tier_audits from public, anon, authenticated;

-- 2. the ladders, with each tier's holdout evidence; refuse a tier that does not meet the rule
do $l$
declare r record; v_n int; v_ok int; v_wrong int; v_cost numeric;
begin
  for r in select * from (values
      ('provider_intake_validation',1,'openrouter-intake-l3c-qwen3-30b-a3b-2507-v1',false),
      ('provider_intake_validation',2,'openrouter-intake-l3r-claude-haiku-4-5-v1',false),
      ('provider_intake_validation',3,'openrouter-intake-l3r-claude-sonnet-4-6-v1',true),
      ('provider_english_validation',1,'openrouter-english-l3c-qwen3-30b-a3b-2507-v1',false),
      ('provider_english_validation',2,'openrouter-english-l3c-mistral-small-3-2-v1',false),
      ('provider_english_validation',3,'openrouter-english-l3r-claude-sonnet-4-6-v1',true)) x(task,tier,code,final) loop
    select count(*), count(*) filter (where h.outcome in ('exact','exact_not_stated')), count(*) filter (where h.outcome='wrong_admitted'), avg(h.cost_usd)
      into v_n, v_ok, v_wrong, v_cost
      from pipeline.layer3_holdout_results h join pipeline.layer3_model_profiles p on p.id=h.profile_id join pipeline.layer3_holdout_cases c on c.id=h.case_id
     where p.code=r.code and c.task_class=r.task;
    if v_n<30 or v_ok::numeric/v_n<0.80 or v_wrong>0 then raise exception 'tier % % (%) does not meet the rule: % of % right, % wrong', r.task, r.tier, r.code, v_ok, v_n, v_wrong; end if;
    insert into pipeline.layer3_route_tiers(task_class,tier_no,profile_id,min_success,cost_per_call_usd,h1_success_rate,h1_wrong_admitted,is_final,qualified_by,active)
    select r.task, r.tier, p.id, 0.80, round(v_cost,6), round(v_ok::numeric/v_n,4), v_wrong, r.final,
           jsonb_build_object('holdout_cases',v_n,'right',v_ok,'wrong_admitted',v_wrong,'rule','>=80% right and 0 wrong-admitted on the frozen holdout',
             'direction','Platform Admin 29 Sep 2026 21:08 IST'), false
      from pipeline.layer3_model_profiles p where p.code=r.code
    on conflict (task_class,contract_version,tier_no) do update set profile_id=excluded.profile_id, cost_per_call_usd=excluded.cost_per_call_usd,
      h1_success_rate=excluded.h1_success_rate, h1_wrong_admitted=excluded.h1_wrong_admitted, is_final=excluded.is_final, qualified_by=excluded.qualified_by, updated_at=now();
  end loop;
end $l$;

-- 3. ladder completion: every tier's attempt is its own interpretation (escalated attempts carry their own cost); the
--    claimed interpretation becomes the final attempt, then the existing completion logic runs unchanged
create or replace function public.layer3_fact_complete_ladder_service(p_work_item_id uuid, p_interpretation_id uuid, p_attempts jsonb, p_final jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare w pipeline.layer3_work_items%rowtype; base pipeline.layer3_interpretations%rowtype; a jsonb; v_tier record; v_res jsonb; v_disagree int;
begin
  perform public.layer3_routing_service_guard();
  select * into w from pipeline.layer3_work_items where id=p_work_item_id for update;
  if w.id is null or w.interpretation_id is distinct from p_interpretation_id then raise exception 'work item / interpretation mismatch'; end if;
  if w.status<>'interpreting' then return jsonb_build_object('work_status',w.status,'note','already completed'); end if;
  select * into base from pipeline.layer3_interpretations where id=p_interpretation_id;
  for a in select * from jsonb_array_elements(coalesce(p_attempts,'[]'::jsonb)) loop
    if not exists (select 1 from pipeline.layer3_route_tiers t where t.task_class=w.task_class and t.active and t.profile_id=(a->>'profile_id')::uuid) then
      raise exception 'attempt profile is not an active tier for %', w.task_class; end if;
    v_res:=a->'result';
    insert into pipeline.layer3_interpretations(evidence_id,evidence_hash,entity_type,entity_id,task_class,profile_id,prompt_profile_version,eligibility_reason,status,layer2_state,
      raw_result,rationale,validator_result,aggregator_response_model,input_tokens,output_tokens,estimated_cost_usd,external_call_count,call_latency_ms,call_started_at,call_completed_at,
      selected_evidence_reason,change_control_ref,uat_ref,cascade_tier_no,escalation_reasons)
    select base.evidence_id,base.evidence_hash,base.entity_type,base.entity_id,base.task_class,(a->>'profile_id')::uuid,p.prompt_profile_version,base.eligibility_reason,'escalated',base.layer2_state,
      v_res->'answer',left(coalesce(v_res->'answer'->>'rationale',''),4000),
      jsonb_build_object('valid',coalesce((v_res->>'valid')::boolean,false),'errors',coalesce(v_res->'errors','[]'::jsonb),'text_sha256',v_res->>'text_sha256','routing','cf247-l3-cascade-v1'),
      v_res->>'returned_model',nullif(v_res->>'input_tokens','')::int,nullif(v_res->>'output_tokens','')::int,greatest(coalesce((v_res->>'cost_usd')::numeric,0),0),
      coalesce((v_res->>'external_calls')::int,0),nullif(v_res->>'latency_ms','')::int,base.call_started_at,now(),
      base.selected_evidence_reason,base.change_control_ref,base.uat_ref,(a->>'tier_no')::int,(select array_agg(x) from jsonb_array_elements_text(coalesce(a->'escalation_reasons','[]'::jsonb)) x)
      from pipeline.layer3_model_profiles p where p.id=(a->>'profile_id')::uuid;
  end loop;
  select t.* into v_tier from pipeline.layer3_route_tiers t where t.task_class=w.task_class and t.active and t.profile_id=(p_final->>'profile_id')::uuid;
  if v_tier.id is null then raise exception 'final profile is not an active tier for %', w.task_class; end if;
  update pipeline.layer3_interpretations i set profile_id=v_tier.profile_id, cascade_tier_no=v_tier.tier_no,
         prompt_profile_version=(select p.prompt_profile_version from pipeline.layer3_model_profiles p where p.id=v_tier.profile_id),
         escalation_reasons=(select array_agg(x) from jsonb_array_elements_text(coalesce(p_final->'escalation_reasons','[]'::jsonb)) x)
   where i.id=p_interpretation_id;
  if jsonb_typeof(p_final->'audit')='object' then
    insert into pipeline.layer3_tier_audits(task_class,tier_no,profile_id,audit_profile_id,work_item_id,agree,detail)
    values (w.task_class,v_tier.tier_no,v_tier.profile_id,(p_final->'audit'->>'profile_id')::uuid,w.id,coalesce((p_final->'audit'->>'agree')::boolean,false),p_final->'audit');
    select count(*) filter (where not agree) into v_disagree from (select agree from pipeline.layer3_tier_audits where task_class=w.task_class and profile_id=v_tier.profile_id order by id desc limit 60) x;
    if v_disagree>=3 and not v_tier.is_final then
      update pipeline.layer3_route_tiers set active=false, updated_at=now() where id=v_tier.id;
      insert into pipeline.layer3_route_events(kind,detail) values ('tier_paused_audit',jsonb_build_object('task_class',w.task_class,'tier_no',v_tier.tier_no,'profile_id',v_tier.profile_id,'disagreements_last_60',v_disagree));
    end if;
  end if;
  return public.layer3_fact_complete_service(p_work_item_id, p_interpretation_id, p_final->'result');
end $f$;
revoke all on function public.layer3_fact_complete_ladder_service(uuid,uuid,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.layer3_fact_complete_ladder_service(uuid,uuid,jsonb,jsonb) to service_role;

-- 4. admission accepts an answer from any active tier of the task (still only validated answers, same rules)
do $patch$
declare v text; a text:=$o$     where w.task_class=p_task_class and w.status='validated' and i.profile_id=p.id$o$;
begin
  if (select md5(prosrc) from pg_proc where oid='security.layer3_fact_admit_v1(text,int)'::regprocedure)<>'cfb6b617dafeba2ac8ba1301e3c6ec96' then
    raise exception 'layer3_fact_admit_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.layer3_fact_admit_v1(text,int)'::regprocedure);
  if (length(v)-length(replace(v,a,'')))/length(a)<>1 then raise exception 'admit anchor not found exactly once'; end if;
  execute replace(v,a,$n$     where w.task_class=p_task_class and w.status='validated'
       and (i.profile_id=p.id or exists (select 1 from pipeline.layer3_route_tiers t where t.task_class=p_task_class and t.active and t.profile_id=i.profile_id))$n$);
end $patch$;

-- 5. activation: tier profiles on (the final tier is already on), ladders active, route mode ladder; the Claude Haiku
--    intake profile is un-retired as tier 2
update pipeline.layer3_model_profiles p set enabled=true, paused=false, retired_at=null, retired_reason=null, updated_at=now(),
       last_validation_result=coalesce(p.last_validation_result,'{}'::jsonb)||jsonb_build_object('cascade_tier',true,'activated_at',now(),'activation_basis','Platform Admin direction 29 Sep 2026 21:08 IST (cost-first cascade)')
  from pipeline.layer3_route_tiers t where t.profile_id=p.id and t.task_class in ('provider_intake_validation','provider_english_validation') and not t.is_final;
update pipeline.layer3_route_tiers set active=true, updated_at=now() where task_class in ('provider_intake_validation','provider_english_validation');
update pipeline.layer3_route_budget set route_mode='ladder' where task_class in ('provider_intake_validation','provider_english_validation');
insert into pipeline.layer3_route_events(kind,detail)
select 'cascade_activated', jsonb_build_object('task_class',t.task_class,'tiers',jsonb_agg(jsonb_build_object('tier',t.tier_no,'model',p.model_identifier,'right',t.h1_success_rate,'wrong',t.h1_wrong_admitted,'cost_per_call_usd',t.cost_per_call_usd) order by t.tier_no),
       'basis','Platform Admin direction 29 Sep 2026 21:08 IST')
  from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.active group by t.task_class;
