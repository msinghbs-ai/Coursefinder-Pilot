-- CF-247 Layer 3 control (Platform Admin, 29 Sep 2026 22:47 IST): "Selecting model cascading is nowhere defined. Model
-- or layer 3 pause is nowhere defined. No control of operations or settings." and "all the older parked jobs in layers
-- 3 & 4 should be retried with cascade layer 3 models".
--
-- 1. security.admin_layer3_control_read_v1(): one read for the Layer 3 control screen: per task, running or paused,
--    daily budget and today's spend, the cascade in order (model, test score, cost per 1,000 pages, work handled in the
--    last 24 hours), the models that may be added (passed the tier rule on the frozen holdout), and 24-hour outcomes.
-- 2. public.admin_layer3_control(action, args): Platform Admin (rank >= 5) controls, each logged as a route event:
--      run_task {task, running}        pause or resume one task's route job
--      run_all {running}               pause or resume all Layer 3 routes
--      budget {task, daily_usd}        the task's daily spend limit (US$0-100)
--      tier_active {task, tier, active} switch one cascade step on or off (at least one stays on)
--      tier_move {task, tier, direction}   move a step up or down the cascade
--      tier_add {task, profile}        add a model that passed the tier rule (>= 80% right, 0 wrong-admitted)
--      tier_remove {task, tier}        remove a step (at least one stays)
--    The last active step of a ladder is its final tier (audits compare against it).
-- 3. Re-queue: parked Layer 3 work and the Layer 4 items Layer 3 raised because the model could not settle a page go back
--    to Layer 3 and are retried through the cascade (tuition through its qualified route). Layer 4 items where the page
--    DIFFERS from a value already held, and items raised by other layers, stay with a person.

-- reordering swaps steps through temporary negative numbers; live steps are always numbered 1..n
alter table pipeline.layer3_route_tiers drop constraint if exists layer3_route_tiers_tier_no_check;
alter table pipeline.layer3_route_tiers add constraint layer3_route_tiers_tier_no_check check (tier_no between -99 and 99 and tier_no<>0);

-- task -> route job
create or replace function security.layer3_task_job(p_task text) returns text language sql immutable as $f$
  select case p_task when 'provider_intake_validation' then 'layer3-intake-route' when 'provider_english_validation' then 'layer3-english-route'
                     when 'provider_current_tuition_validation' then 'layer3-tuition-dispatch' end
$f$;

-- tier rule evidence for a profile on a task (frozen holdout results)
create or replace function security.layer3_tier_evidence(p_task text, p_profile uuid) returns jsonb language sql stable
set search_path to 'pg_catalog','pipeline' as $f$
  select jsonb_build_object('cases',count(*),'right',count(*) filter (where h.outcome in ('exact','exact_not_stated')),
           'wrong',count(*) filter (where h.outcome='wrong_admitted'),'cost_per_call_usd',round(avg(h.cost_usd),6),
           'right_pct',case when count(*)>0 then round(100.0*count(*) filter (where h.outcome in ('exact','exact_not_stated'))/count(*),1) end,
           'eligible',count(*)>=30 and count(*) filter (where h.outcome='wrong_admitted')=0 and count(*) filter (where h.outcome in ('exact','exact_not_stated'))::numeric/nullif(count(*),0)>=0.80)
    from pipeline.layer3_holdout_results h join pipeline.layer3_holdout_cases c on c.id=h.case_id
   where h.profile_id=p_profile and c.task_class=p_task
$f$;

create or replace function security.layer3_renumber_tiers(p_task text) returns void language plpgsql
set search_path to 'pg_catalog','pipeline' as $f$
begin
  update pipeline.layer3_route_tiers t set tier_no=-t.tier_no where t.task_class=p_task;
  update pipeline.layer3_route_tiers t set tier_no=x.rn, updated_at=now()
    from (select id, row_number() over (order by -tier_no) rn from pipeline.layer3_route_tiers where task_class=p_task) x where x.id=t.id;
  update pipeline.layer3_route_tiers t set is_final = (t.active and t.tier_no=(select max(tier_no) from pipeline.layer3_route_tiers where task_class=p_task and active)) where t.task_class=p_task;
end $f$;

create or replace function security.admin_layer3_control_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','cron','security' as $f$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'generated_at', now(),
    'can_control', security.current_role_rank()>=5,
    'credit', (select jsonb_build_object('remaining_usd',round(remaining_usd,2),'observed_at',observed_at) from pipeline.layer3_openrouter_observations where kind='credits' order by observed_at desc limit 1),
    'tasks', (select jsonb_agg(jsonb_build_object(
        'task_class', b.task_class,
        'label', case b.task_class when 'provider_intake_validation' then 'Intakes' when 'provider_english_validation' then 'English requirements' else 'Tuition' end,
        'running', coalesce((select j.active from cron.job j where j.jobname=security.layer3_task_job(b.task_class)),false),
        'cascade', b.route_mode='ladder',
        'daily_usd', b.daily_usd_max,
        'spent_today_usd', round(coalesce((select sum(i.estimated_cost_usd) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),0),4),
        'last_24h', (select jsonb_build_object('admitted',count(*) filter (where w.status='admitted'),'to_review',count(*) filter (where w.status='layer4_required'),
                       'not_stated',count(*) filter (where w.status='no_candidate'),'retrying',count(*) filter (where w.status in ('failed','pending')))
                       from pipeline.layer3_work_items w where w.task_class=b.task_class and w.updated_at>=now()-interval '24 hours'),
        'in_review', (select count(*) from pipeline.layer4_review_items l where l.status='pending' and l.layer3_interpretation_id is not null
                        and l.field_code=case b.task_class when 'provider_intake_validation' then 'course_intake' when 'provider_english_validation' then 'course_english' else 'provider_current_tuition_validation' end),
        'tiers', case when b.route_mode='ladder' then (select coalesce(jsonb_agg(jsonb_build_object(
              'tier', t.tier_no, 'active', t.active, 'final', t.is_final, 'profile', p.code, 'model', p.model_identifier,
              'cost_per_1000_usd', round(t.cost_per_call_usd*1000,2), 'test_right_pct', round(t.h1_success_rate*100,1), 'test_wrong', t.h1_wrong_admitted,
              'answered_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours' and i.status in ('validated','no_candidate')),
              'passed_up_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours' and i.status='escalated'),
              'cost_24h_usd', (select round(coalesce(sum(i.estimated_cost_usd),0),4) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours'),
              'audits', (select jsonb_build_object('checked',count(*),'disagreed',count(*) filter (where not a.agree)) from pipeline.layer3_tier_audits a where a.profile_id=t.profile_id and a.task_class=b.task_class)
            ) order by t.tier_no),'[]'::jsonb) from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.task_class=b.task_class)
          else (select coalesce(jsonb_agg(jsonb_build_object('tier',1,'active',true,'final',true,'profile',p.code,'model',p.model_identifier,
              'cost_per_1000_usd', round(coalesce((security.layer3_tier_evidence(b.task_class,p.id)->>'cost_per_call_usd')::numeric,0)*1000,2),
              'test_right_pct', (security.layer3_tier_evidence(b.task_class,p.id)->>'right_pct')::numeric, 'test_wrong', (security.layer3_tier_evidence(b.task_class,p.id)->>'wrong')::int,
              'answered_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=p.id and i.created_at>=now()-interval '24 hours'),
              'passed_up_24h', 0, 'cost_24h_usd', (select round(coalesce(sum(i.estimated_cost_usd),0),4) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=p.id and i.created_at>=now()-interval '24 hours'))),'[]'::jsonb)
              from pipeline.layer3_model_profiles p where b.task_class=any(p.allowed_task_classes) and p.enabled and not p.paused and p.retired_at is null
               and coalesce((p.quality_benchmark->>'pass')::boolean,false)) end,
        'addable', case when b.route_mode='ladder' then (select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,
              'test_right_pct',(e->>'right_pct')::numeric,'test_wrong',(e->>'wrong')::int,'cost_per_1000_usd',round((e->>'cost_per_call_usd')::numeric*1000,2)) order by (e->>'cost_per_call_usd')::numeric),'[]'::jsonb)
            from pipeline.layer3_model_profiles p cross join lateral (select security.layer3_tier_evidence(b.task_class,p.id) e) x
           where b.task_class=any(p.allowed_task_classes) and coalesce((e->>'eligible')::boolean,false)
             and not exists (select 1 from pipeline.layer3_route_tiers t where t.task_class=b.task_class and t.profile_id=p.id)) else '[]'::jsonb end
      ) order by case b.task_class when 'provider_intake_validation' then 1 when 'provider_english_validation' then 2 else 3 end)
      from pipeline.layer3_route_budget b),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'kind',e.kind,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                 from (select * from pipeline.layer3_route_events order by created_at desc limit 12) e)
  ) into v;
  return v;
end $f$;
revoke all on function security.admin_layer3_control_read_v1() from public, anon;
grant execute on function security.admin_layer3_control_read_v1() to authenticated, service_role;
create or replace function public.admin_layer3_control_read() returns jsonb language sql stable security invoker as $f$ select security.admin_layer3_control_read_v1() $f$;
revoke all on function public.admin_layer3_control_read() from public, anon;
grant execute on function public.admin_layer3_control_read() to authenticated, service_role;

create or replace function security.admin_layer3_control_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','cron','security' as $f$
declare v_task text:=p_args->>'task'; v_tier int:=nullif(p_args->>'tier','')::int; v_on boolean:=(p_args->>'running')::boolean; t record; n record; p record; e jsonb; v_job text;
begin
  if auth.uid() is null or security.current_role_rank()<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if v_task is not null and not exists (select 1 from pipeline.layer3_route_budget where task_class=v_task) then raise exception 'unknown task'; end if;
  if p_action='run_task' then
    v_job:=security.layer3_task_job(v_task); perform cron.alter_job(j.jobid, active => v_on) from cron.job j where j.jobname=v_job;
  elsif p_action='run_all' then
    perform cron.alter_job(j.jobid, active => v_on) from cron.job j where j.jobname in ('layer3-intake-route','layer3-english-route','layer3-tuition-dispatch');
  elsif p_action='budget' then
    if (p_args->>'daily_usd')::numeric not between 0 and 100 then raise exception 'daily limit must be US$0-100'; end if;
    update pipeline.layer3_route_budget set daily_usd_max=(p_args->>'daily_usd')::numeric where task_class=v_task;
  elsif p_action in ('tier_active','tier_move','tier_remove') then
    select * into t from pipeline.layer3_route_tiers where task_class=v_task and tier_no=v_tier;
    if t.id is null then raise exception 'no such cascade step'; end if;
    if p_action='tier_active' then
      if not (p_args->>'active')::boolean and (select count(*) from pipeline.layer3_route_tiers where task_class=v_task and active and id<>t.id)=0 then raise exception 'at least one cascade step must stay on'; end if;
      update pipeline.layer3_route_tiers set active=(p_args->>'active')::boolean, updated_at=now() where id=t.id;
    elsif p_action='tier_move' then
      select * into n from pipeline.layer3_route_tiers where task_class=v_task and tier_no=v_tier+case p_args->>'direction' when 'up' then -1 else 1 end;
      if n.id is null then raise exception 'cannot move further'; end if;
      update pipeline.layer3_route_tiers set tier_no=-1 where id=t.id;
      update pipeline.layer3_route_tiers set tier_no=t.tier_no, updated_at=now() where id=n.id;
      update pipeline.layer3_route_tiers set tier_no=n.tier_no, updated_at=now() where id=t.id;
    else
      if (select count(*) from pipeline.layer3_route_tiers where task_class=v_task and active and id<>t.id)=0 then raise exception 'at least one cascade step must stay'; end if;
      delete from pipeline.layer3_route_tiers where id=t.id;
    end if;
    perform security.layer3_renumber_tiers(v_task);
  elsif p_action='tier_add' then
    select * into p from pipeline.layer3_model_profiles where code=p_args->>'profile';
    if p.id is null or not (v_task=any(p.allowed_task_classes)) then raise exception 'model profile not set up for this task'; end if;
    if exists (select 1 from pipeline.layer3_route_tiers where task_class=v_task and profile_id=p.id) then raise exception 'model already in the cascade'; end if;
    e:=security.layer3_tier_evidence(v_task,p.id);
    if not coalesce((e->>'eligible')::boolean,false) then raise exception 'model has not passed the tier rule (>= 80%% right and 0 wrong on the frozen test pages): %', e; end if;
    insert into pipeline.layer3_route_tiers(task_class,tier_no,profile_id,min_success,cost_per_call_usd,h1_success_rate,h1_wrong_admitted,is_final,qualified_by,active)
    values (v_task,(select coalesce(max(tier_no),0)+1 from pipeline.layer3_route_tiers where task_class=v_task),p.id,0.80,(e->>'cost_per_call_usd')::numeric,
            round((e->>'right')::numeric/(e->>'cases')::numeric,4),(e->>'wrong')::int,false,e||jsonb_build_object('added_by',auth.uid(),'added_at',now()),true);
    update pipeline.layer3_model_profiles set enabled=true, paused=false, retired_at=null, retired_reason=null, updated_at=now() where id=p.id;
    perform security.layer3_renumber_tiers(v_task);
  else raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.layer3_route_events(kind,detail) values ('admin_'||p_action, p_args||jsonb_build_object('by',auth.uid()));
  return security.admin_layer3_control_read_v1();
end $f$;
revoke all on function security.admin_layer3_control_v1(text,jsonb) from public, anon;
grant execute on function security.admin_layer3_control_v1(text,jsonb) to authenticated;
create or replace function public.admin_layer3_control(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language sql volatile security invoker as $f$ select security.admin_layer3_control_v1(p_action, coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_layer3_control(text,jsonb) from public, anon;
grant execute on function public.admin_layer3_control(text,jsonb) to authenticated;

-- final-tier flag kept consistent with the current ladders
select security.layer3_renumber_tiers(task_class) from (select distinct task_class from pipeline.layer3_route_tiers) x;

-- 3. re-queue parked work through Layer 3
-- 3a. intake and English: Layer 4 items Layer 3 raised because the model could not settle the page (not "differs from
--     the value already held") are superseded; their work items fail with a note and the pages are released for the cascade
with l4 as (
  update pipeline.layer4_review_items l set status='superseded', decided_at=now(),
         escalation_reason='Superseded: returned to Layer 3 to be retried through the model cascade (Platform Admin, 29 Sep 2026 22:47 IST).'
   where l.status='pending' and l.layer3_interpretation_id is not null and l.field_code in ('course_intake','course_english') and l.before_value is null
  returning l.layer3_interpretation_id),
wi as (
  update pipeline.layer3_work_items w set status='failed', updated_at=now(), last_error='released: retried through the model cascade (29 Sep 2026)'
    from l4 where w.interpretation_id=l4.layer3_interpretation_id and w.status='layer4_required'
  returning w.id)
update pipeline.layer3_fact_handoffs h set work_item_id=null, attempts=0 from wi where h.work_item_id=wi.id;
-- pages released earlier (refusals, lost workers) get their retry allowance back
update pipeline.layer3_fact_handoffs set attempts=0 where work_item_id is null and attempts>0;

-- 3b. tuition: parked and Layer 4 items Layer 3 raised go back to pending under the active tuition route
with active_tuition as (
  select p.id from pipeline.layer3_model_profiles p where 'provider_current_tuition_validation'=any(p.allowed_task_classes) and p.enabled and not p.paused
     and p.retired_at is null and coalesce((p.quality_benchmark->>'pass')::boolean,false) order by p.updated_at desc limit 1),
l4 as (
  update pipeline.layer4_review_items l set status='superseded', decided_at=now(),
         escalation_reason='Superseded: returned to Layer 3 to be retried with the current qualified tuition model (Platform Admin, 29 Sep 2026 22:47 IST).'
   where l.status='pending' and l.layer3_interpretation_id is not null and l.field_code='provider_current_tuition_validation' and l.before_value is null
     and exists (select 1 from active_tuition)
  returning l.layer3_interpretation_id)
update pipeline.layer3_work_items w set status='pending', profile_id=(select id from active_tuition), reserved_at=null, reserved_by=null, interpretation_id=null,
       available_at=now(), updated_at=now(), last_error='requeued: retried with the current qualified tuition model (29 Sep 2026)'
 where w.task_class='provider_current_tuition_validation' and w.status in ('layer4_required','parked') and exists (select 1 from active_tuition)
   and (w.interpretation_id in (select layer3_interpretation_id from l4) or not exists (select 1 from pipeline.layer4_review_items x where x.layer3_interpretation_id=w.interpretation_id and x.status='pending'));

insert into pipeline.layer3_route_events(kind,detail) values ('requeued_parked',jsonb_build_object('basis','Platform Admin 29 Sep 2026 22:47 IST','note','intake/English pages released to the cascade; tuition back to pending under the qualified route'));
