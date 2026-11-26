-- CF-247 s1272 (S1-Build; Platform Admin via SS-Programme-Control 26 Nov 2026 19:06 and 19:13 AEDT: "Complete the existing planner correction and activate s1261").
-- Cause (admin #1201, read live again 26 Nov 19:00 AEDT): the planner's academic_entry step only re-fetched failed pages; nothing the planner ran queued a course entry read.
--   The scheduled entry reader (job 358 aer-scheduled-read, security.aer_schedule_tick_v1) does queue reads by security.aer_schedule_courses_v1, but only while the
--   entry route is on, and a refusal recorded as skipped (the OpenRouter weekly key limit, 12 to 15 Nov) kept its course out for 30 days.
-- Fix, on the existing mechanism only (no new queue, planner, scheduler, worker or job):
--   1. One eligibility rule, now per provider: security.aer_schedule_courses_v1(limit, all, provider) on security.aer_course_population_v1(provider) (manual locks, AER
--      provider eligibility, country scope, hidden providers, bound page with a stored copy, identity); the two-argument form calls it for every provider.
--      A refusal recorded as skipped now counts as not read, and the refusal pattern (aer.retry_now_error_pattern) gains the route-off outcome.
--   2. security.enrich_plan_v1 proposes academic_entry when the provider has due entry reads (as well as pages due a revisit).
--   3. security.enrich_plan_start_step_v1 queues them through security.aer_entry_reads_plan_v1: the scheduled reader's capacity rules (run-as owner, daily maximum shared
--      through pipeline.aer_schedule_runs, Layer 4 back-pressure, item gate), at most aer.schedule_per_provider a plan, through security.course_entry_read_enqueue_v1.
--   4. security.enrich_plan_tick_v1 closes the step when those reads have left the queue (never counted as delivery).
--   Spending is held where the work is handed out: security.ai_route_v1 in public.svc_enrich_ai_next (route switch, US$ cap, platform ceiling). While the route is off
--   the reads wait queued; s1261 switches it on.
-- G1: no job. G2: existing settings (used_by extended). G3: no consumer object touched (checked). Locks and cron unchanged (checked).
-- Replaces: security.aer_schedule_courses_v1(integer, boolean) (md5 0e42dd3e), security.enrich_plan_v1 (04f1ec1f), security.enrich_plan_start_step_v1 (87e3d7c5),
--   security.enrich_plan_tick_v1 (26b0ae9c), each md5 guarded; anchored edits on the planner functions.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
  if md5(pg_get_functiondef('security.aer_schedule_courses_v1(integer,boolean)'::regprocedure)) <> '0e42dd3e90291ad35e7d9f3665163a95' then raise exception 'guard: aer_schedule_courses_v1 changed'; end if;
  if md5(pg_get_functiondef('security.enrich_plan_v1(uuid)'::regprocedure)) <> '04f1ec1f5f7803637071df71b6764efd' then raise exception 'guard: enrich_plan_v1 changed'; end if;
  if md5(pg_get_functiondef('security.enrich_plan_start_step_v1(uuid,text)'::regprocedure)) <> '87e3d7c5899fde5a2714c6020cb7ef44' then raise exception 'guard: enrich_plan_start_step_v1 changed'; end if;
  if md5(pg_get_functiondef('security.enrich_plan_tick_v1(uuid)'::regprocedure)) <> '26b0ae9c387b904439a085e95b47c4ab' then raise exception 'guard: enrich_plan_tick_v1 changed'; end if;
  if md5(pg_get_functiondef('security.course_entry_read_enqueue_v1(uuid,uuid,text)'::regprocedure)) <> 'df0f2a2826e61b92b168847f1557435b' then raise exception 'guard: course_entry_read_enqueue_v1 changed'; end if;
  if (select value #>> '{}' from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'aer.retry_now_error_pattern') <> 'Key limit exceeded|Insufficient credits|requires more credits|HTTP 402' then
    raise exception 'guard: aer.retry_now_error_pattern is not the value this change extends';
  end if;
end $g$;
create temp table s1272_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1272_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none

-- 1. one eligibility rule, per provider
create function security.aer_schedule_courses_v1(p_limit integer, p_all boolean, p_provider uuid)
 returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, turn bigint)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with s as (select make_interval(days => security.pipeline_num_v1('aer.schedule_retry_days', 30)::int) retry,
                    security.pipeline_num_v1('aer.schedule_per_provider', 5) per,
                    coalesce(security.toolset_setting('pipeline', 'aer.retry_now_error_pattern') #>> '{}', '') refused),
  c as (select p.* from security.aer_course_population_v1(p_provider) p cross join s
         where not exists (select 1 from catalogue.course_entry_requirements x where x.course_id = p.course_id and x.status in ('active', 'proposed'))
           and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = p.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending')
           and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = p.course_id and f.field = 'entry_requirements'
                             and (f.state in ('queued', 'waiting', 'ai', 'leased', 'review')
                                  -- 13 Nov 2026: a read the AI provider refused (aer.retry_now_error_pattern) was not read, so it does not wait for the retry interval
                                  -- s1272: a refusal recorded as skipped (held_partial) was not read either
                                  or (f.updated_at > now() - s.retry and not (f.state in ('failed', 'skipped') and s.refused <> '' and coalesce(f.reason, '') ~* s.refused))))
           and not exists (select 1 from pipeline.enrichment_flags fl where fl.entity = 'course' and fl.entity_key = p.course_id::text and fl.field = 'entry_requirements'
                             and fl.reason_code = 'enrich_no_value' and fl.state in ('raised', 'counting'))),
  r as (select c.*, row_number() over (partition by c.provider_id order by c.title, c.course_id) turn from c)
  select r.course_id, r.provider_id, r.country, r.provider_name, r.tier, r.turn
    from r cross join s
   where p_all or r.turn <= s.per
   order by r.turn, r.tier, r.provider_name, r.provider_id
   limit p_limit
$function$;
comment on function security.aer_schedule_courses_v1(integer, boolean, uuid) is 'AER (s1272): the courses the scheduled entry reader may read, for one provider or (null) all; the one eligibility rule the scheduler and the planner share.';
revoke all on function security.aer_schedule_courses_v1(integer, boolean, uuid) from public, anon, authenticated;
grant execute on function security.aer_schedule_courses_v1(integer, boolean, uuid) to service_role;

create or replace function security.aer_schedule_courses_v1(p_limit integer, p_all boolean DEFAULT false)
 returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, turn bigint)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select * from security.aer_schedule_courses_v1(p_limit, p_all, null::uuid)  -- s1272: the one rule, every provider
$function$;

do $p$
declare v_reason constant text := 'CF-247 s1272: a refusal recorded as skipped, and a read held because the entry route was switched off, were not reads; they are read again at the next run';
        v_old text; v_new text;
begin
  select value #>> '{}' into v_old from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'aer.retry_now_error_pattern';
  v_new := v_old || '|AI route is switched off';
  update pipeline.platform_toolset_settings
     set value = to_jsonb(v_new), reason = v_reason, updated_at = now(),
         help = 'A read that failed or was skipped with a recorded reason matching this pattern (case-insensitive) was refused by the AI provider or held by a switched-off route, not read: it is read again at the next run and does not count as a try. Empty: no exception.'
   where toolset_key = 'pipeline' and key = 'aer.retry_now_error_pattern';
  update pipeline.platform_toolset_settings
     set used_by = concat_ws(', ', nullif(used_by, ''), 'security.aer_entry_reads_plan_v1 (s1272)'), updated_at = now()
   where toolset_key = 'pipeline' and key in ('batch.aer_schedule_courses', 'aer.schedule_daily_max', 'aer.schedule_layer4_max', 'aer.schedule_per_provider')
     and coalesce(used_by, '') not like '%aer_entry_reads_plan_v1%';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline.aer.retry_now_error_pattern', jsonb_build_object('before', v_old, 'after', v_new, 'reason', v_reason, 'via', 'CF-247 s1272 migration'), null);
end $p$;

-- the planner's entry reads: the scheduled reader's capacity rules for one provider (security.aer_schedule_tick_v1: run-as owner, daily maximum, Layer 4
-- back-pressure, item gate), logged in pipeline.aer_schedule_runs so the daily maximum is shared. Spending is held where the work is handed out
-- (security.ai_route_v1 in public.svc_enrich_ai_next: route switch, its daily cap and the platform ceiling).
create or replace function security.aer_entry_reads_plan_v1(p_provider uuid, p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $f$
declare v_batch int := security.pipeline_num_v1('batch.aer_schedule_courses', 20)::int;
        v_daymax int := security.pipeline_num_v1('aer.schedule_daily_max', 200)::int;
        v_l4max int := security.pipeline_num_v1('aer.schedule_layer4_max', 600)::int;
        v_fair boolean := security.pipeline_num_v1('wc.aer_fair_on', 0) >= 1;
        v_owner uuid; v_orank int; v_used int; v_l4 int; v_prog int; v_parked int; v_bp boolean; v_room int; v_why text; v_job uuid;
        v_n int := 0; v_courses jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb; r record;
begin
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;
  select ro.rank into v_orank from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ur.user_id = v_owner and (ur.expires_at is null or ur.expires_at > now()) and ro.status = 'active' order by ro.rank desc limit 1;
  select coalesce(sum(x.course_reads), 0) into v_used from pipeline.aer_schedule_runs x where x.ran_at > now() - interval '1 day';  -- fixed: the daily maximum is counted over the last 24 hours
  select count(*) into v_l4 from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run');
  select count(*) into v_prog from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  select count(*) into v_parked from security.aer_parked_items_v1();
  v_bp := v_l4 - v_parked + v_prog >= v_l4max;
  if v_fair then v_bp := coalesce((security.work_review_room_v1('aer')->>'room')::numeric, 0) <= 0; end if;
  v_room := greatest(0, least(v_batch, v_daymax - v_used));
  v_why := case when v_owner is null then 'no owner to run as (Coverage › Attributes, Fill the gaps)'
                when coalesce(v_orank, 0) < 6 then 'the owner it runs as does not hold the Platform Admin role that Read next batch requires'  -- fixed: the rank admin_aer course_batch requires
                when v_bp then 'Layer 4 is full (aer.schedule_layer4_max)'
                when v_room = 0 then 'the daily maximum is reached (aer.schedule_daily_max)' end;
  if v_why is null then
    for r in select * from security.aer_schedule_courses_v1(v_room, false, p_provider) loop
      if security.enrich_item_held_v1(r.course_id, 'entry_requirements') then
        v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', 'held by the item gate'); continue;
      end if;
      begin
        v_job := security.course_entry_read_enqueue_v1(r.course_id, v_owner, p_reason);
        v_courses := v_courses || to_jsonb(r.course_id); v_n := v_n + 1;
      exception when others then
        v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', left(sqlerrm, 300));
      end;
    end loop;
    insert into pipeline.aer_schedule_runs(course_reads, corrections, matrix_pages, layer4_waiting, in_progress, back_pressure, used_before, room, refusal, estimate_usd, detail)
    values (v_n, 0, 0, v_l4, v_prog, v_bp, v_used, v_room, null, round(v_n * security.course_entry_cost_v1(), 4),
            jsonb_build_object('from', 'enrichment plan (s1272)', 'provider_id', p_provider, 'new', v_courses, 'skipped', v_skip));
  end if;
  return jsonb_build_object('queued', v_n, 'courses', v_courses, 'skipped', v_skip, 'refusal', v_why);
end $f$;
comment on function security.aer_entry_reads_plan_v1(uuid, text) is 'PIM (s1272): the planner''s academic entry step queues the provider''s due entry reads under the scheduled reader''s capacity rules; logged in pipeline.aer_schedule_runs.';
revoke all on function security.aer_entry_reads_plan_v1(uuid, text) from public, anon, authenticated;
grant execute on function security.aer_entry_reads_plan_v1(uuid, text) to service_role;

-- 2. planner: propose academic_entry for due entry reads too
do $a$
declare d text := pg_get_functiondef('security.enrich_plan_v1(uuid)'::regprocedure);
        a1 constant text := $q$  -- 7 academic entry (s1171): hand capped course pages to the bounded revisit; the AER readers and Layer 4 admit the rows
  if exists (select 1 from security.pim_source_revisit_due_v1(p_provider)) and security.pipeline_num_v1('pim.source_revisit_batch', 25) > 0 then
    v_steps := v_steps || jsonb_build_object('step', 'academic_entry', 'label', 'Read failed course pages again (academic entry)',
      'why', (select count(*) from security.pim_source_revisit_due_v1(p_provider)) || ' course pages at their read limit are due a revisit; a read is a fetch only, rows are admitted by the AER readers and Layer 4',
      'fields', jsonb_build_array('academic_entry'), 'est_credits', least((select count(*) from security.pim_source_revisit_due_v1(p_provider)), security.pipeline_num_v1('pim.source_revisit_batch', 25)::int),
      'est_usd', 0, 'group', 'reads');
  end if;
$q$;
        b1 constant text := $q$  -- 7 academic entry (s1171; s1272): hand capped course pages to the bounded revisit, and queue the entry reads of the courses the scheduled entry reader may take
  --   (security.aer_schedule_courses_v1 for this provider: the same eligibility rules, manual locks and country scope); the AER readers and Layer 4 admit the rows
  v_rev := (select count(*) from security.pim_source_revisit_due_v1(p_provider));
  v_ent := (select count(*) from security.aer_schedule_courses_v1(security.pipeline_num_v1('aer.schedule_daily_max', 200)::int, true, p_provider));
  if (v_rev > 0 and security.pipeline_num_v1('pim.source_revisit_batch', 25) > 0) or v_ent > 0 then
    v_steps := v_steps || jsonb_build_object('step', 'academic_entry', 'label', 'Academic entry: read entry requirements (and failed course pages again)',
      'why', concat_ws('; ', case when v_ent > 0 then v_ent || ' courses with a stored page and no entry requirement are due a read' end,
                             case when v_rev > 0 then v_rev || ' course pages at their read limit are due a revisit' end) || '; rows are admitted by the AER readers and Layer 4',
      'fields', jsonb_build_array('academic_entry'), 'est_credits', least(v_rev, security.pipeline_num_v1('pim.source_revisit_batch', 25)::int),
      'est_usd', round(least(v_ent, security.pipeline_num_v1('aer.schedule_per_provider', 5)::int) * security.course_entry_cost_v1(), 4), 'group', 'reads');
  end if;
$q$;
        a2 constant text := 'v_stalled jsonb;';
begin
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then raise exception 'guard: the planner anchors are not found exactly once'; end if;
  execute replace(replace(d, a1, b1), a2, 'v_stalled jsonb; v_rev int; v_ent int;');
end $a$;

-- 3. step start: the entry reads
do $s$
declare d text := pg_get_functiondef('security.enrich_plan_start_step_v1(uuid,text)'::regprocedure);
        a constant text := $q$  if p_step = 'academic_entry' then  -- s1171: hand-off to the academic entry lane through the bounded revisit
    v := security.pim_source_revisit_v1(r.provider_id, security.pipeline_num_v1('pim.source_revisit_batch', 25)::int);
    return jsonb_build_object('kind', 'handoff', 'lane', 'academic_entry', 'courses', v->'courses', 'revisited', v->'revisited');
  end if;$q$;
        b constant text := $q$  if p_step = 'academic_entry' then  -- s1171: hand-off to the academic entry lane through the bounded revisit; s1272: and the entry reads, queued for the course entry reader
    v := security.pim_source_revisit_v1(r.provider_id, security.pipeline_num_v1('pim.source_revisit_batch', 25)::int);
    v_fields := security.aer_entry_reads_plan_v1(r.provider_id, 'Enrichment plan (' || r.mode || '): ' || coalesce(r.reason, 'academic entry'));
    return jsonb_build_object('kind', 'handoff', 'lane', 'academic_entry', 'courses', v->'courses', 'revisited', v->'revisited',
                              'entry_courses', coalesce(v_fields->'courses', '[]'::jsonb), 'entry_reads', coalesce((v_fields->>'queued')::int, 0), 'entry_refusal', v_fields->>'refusal');
  end if;$q$;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the step anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $s$;

-- 4. tick: the step is done when its entry reads left the queue
do $t$
declare d text := pg_get_functiondef('security.enrich_plan_tick_v1(uuid)'::regprocedure);
        a constant text := $q$and g.read_attempts < 3 and coalesce(g.read_at, '-infinity') < (s->>'started_at')::timestamptz) then 'done' end)  -- s1171: fetches finished, not rows admitted$q$;
        b constant text := $q$and g.read_attempts < 3 and coalesce(g.read_at, '-infinity') < (s->>'started_at')::timestamptz)
               and not exists (select 1 from pipeline.field_enrich_items fe where fe.field = 'entry_requirements' and fe.state in ('queued', 'waiting', 'ai', 'leased')
                                  and fe.course_id = any (array(select y::uuid from jsonb_array_elements_text(coalesce(s->'ref'->'entry_courses', '[]'::jsonb)) y))) then 'done' end)  -- s1171: fetches finished; s1272: and the entry reads it queued left the queue; not rows admitted$q$;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the tick anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $t$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); pv uuid; pl jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1272_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1272_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from security.aer_schedule_courses_v1(1, false)) <> (select count(*) from security.aer_schedule_courses_v1(1, false, null::uuid)) then raise exception 'post-check: the two forms disagree'; end if;
  select e.provider_id into pv from security.aer_schedule_courses_v1(1, false) e;  -- fixed: one sample provider for the check
  if pv is not null then
    pl := security.enrich_plan_v1(pv);
    if not exists (select 1 from jsonb_array_elements(pl->'steps') x where x->>'step' = 'academic_entry') then raise exception 'post-check: a provider with due entry reads gets no academic_entry step: %', pl->'steps'; end if;
    raise notice 'sample provider % proposes academic_entry', pv;
  end if;
end $c$;
