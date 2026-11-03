-- CF-247 SS-020 follow-up items 1, 2 and 4 (Decision 269 amendments, Platform Admin 4 Nov 2026 about 05:40; approval 06:53 §2; admin
-- docs/platform/ui-audit/2026-11-04-ss020-follow-up-prompt.md and 2026-11-04-ss020-implementation-review.md).
-- Item 1, "Rewire, then retire": Layer 1 › Sources' Schedule now edits the Layer 1 refresh policy of the register (pipeline.refresh_policies,
--   the rows security.refresh_scheduler_tick_impl reads), so the section Scheduled jobs › Automations › "Refresh schedules and one-off runs"
--   can retire. Same role check as today (public.admin_layer1_schedule: Platform Admin, a reason of 4 or more characters).
-- Measured live, read only, 4 Nov 2026 06:55-07:20 AEDT (project fxcwkweaxjtknorudmwp):
--   a. pipeline.refresh_policies has 3 Layer 1 rows: AU CRICOS (weekly, 7 days; its Sources schedule said 30 days), NZQA providers (weekly,
--      7 days) and Education Counts NZ (monthly, 30 days). The third has no Layer 1 operations profile, so it is not on Layer 1 › Sources and
--      no tick dispatches its request (one request queued since 24 Sep 2026). It is left as it is (recorded for the Platform Admin).
--   b. layer1_source_operations.verification_cadence_days is not unread: svc_layer1_record_validation sets next_verification_at from it, and
--      security.layer1_regulatory_scheduler_tick_impl (hourly) queues a Layer 1 request when next_verification_at is due, for all 43 profiles.
--      It is therefore not marked retiring (nothing replaces it for the 41 profiles without a refresh policy; the register has no column kind).
--      The Schedule stops writing it for a register that has a Layer 1 refresh policy; there it changes the policy (cadence, freshness class,
--      next run) and leaves verification_cadence_days and next_verification_at as they are. A register without a policy keeps today's write,
--      because that column is the only cadence its runs have (DECISION for the Platform Admin, recorded in the SS-020 follow-up report).
--   c. The next run moves with the cadence: next run = the previous due time (next run less the old cadence) plus the new cadence, never
--      earlier than now. Manual keeps a monthly status check (as today) and switches automatic loading off.
-- Item 4: "Layer 2 → conditional Layer 3" is written only in src/ScheduledJobsWorkspace.jsx (the retiring screen); no table row, setting or
--   function holds it (checked live), so no data changes.
-- Replaces: public.admin_layer1_schedule (same name and arguments; md5-guarded whole replacement)
-- Retires: the screen Scheduled jobs › Automations › Refresh schedules and one-off runs, and the functions only it called
--   (public.scheduler_policies_list_v1, public.scheduler_policy_edit_v1, public.scheduler_policy_run_now_v1, public.refresh_intelligence_overview
--   and their security.* implementations), marked retiring in pipeline.component_register; nothing is dropped, deleted or switched on.
-- Consumer API: untouched (G3). No job is added or changed (G1, G2).

create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 0. the scheduler that reads the policies is the one this change was written against (not changed here)
do $g$
begin
  if md5(pg_get_functiondef('security.refresh_scheduler_tick_impl(timestamptz,integer)'::regprocedure)) <> '5f7b3ece8e91919d622b16af652b9250' then
    raise exception 'live security.refresh_scheduler_tick_impl differs from the definition this change was written against';
  end if;
end $g$;

-- 1. Layer 1 › Sources' Schedule edits the register's Layer 1 refresh policy -------------------------------------------------------------
select pg_temp.replace_once('public.admin_layer1_schedule(uuid,text,text)', '53b48153be94af028d322e2d5851962a', '112c34fb7a4aa3198c383bf8d02ff324', $def$
create or replace function public.admin_layer1_schedule(p_source_id uuid, p_schedule text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_days int; v_auto boolean; v_class text; v_before jsonb; v_after jsonb; v_policy pipeline.refresh_policies%rowtype; v_next timestamptz;
        v_policy_before jsonb; v_policy_after jsonb;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select case p_schedule when 'daily' then 1 when 'weekly' then 7 when 'monthly' then 30 when 'quarterly' then 91 when 'yearly' then 365 when 'manual' then 30 end,
         case p_schedule when 'daily' then 'critical' when 'weekly' then 'weekly' when 'monthly' then 'monthly' when 'quarterly' then 'term-cycle' when 'yearly' then 'annual' when 'manual' then 'monthly' end,
         p_schedule <> 'manual' into v_days, v_class, v_auto;
  if v_days is null then raise exception 'schedule must be daily, weekly, monthly, quarterly, yearly or manual'; end if;
  select jsonb_build_object('verification_cadence_days', verification_cadence_days, 'ingestion_cadence_days', ingestion_cadence_days, 'auto_ingest', auto_ingest)
    into v_before from pipeline.layer1_source_operations where source_id = p_source_id for update;
  if v_before is null then raise exception 'not a Layer 1 source'; end if;
  -- SS-020 follow-up (Decision 269 amendment, 4 Nov 2026): a register with a Layer 1 refresh policy is scheduled by that policy
  -- (security.refresh_scheduler_tick_impl); the Schedule edits it and moves its next run, and no longer writes verification_cadence_days.
  select * into v_policy from pipeline.refresh_policies where layer = 1 and source_id = p_source_id order by updated_at desc, id limit 1 for update;
  if found then
    v_policy_before := jsonb_build_object('policy_id', v_policy.id, 'freshness_class', v_policy.freshness_class, 'cadence_interval', v_policy.cadence_interval::text, 'next_due_at', v_policy.next_due_at);
    v_next := greatest(now(), coalesce(v_policy.next_due_at - coalesce(v_policy.cadence_interval, make_interval()), now()) + make_interval(days => v_days));
    update pipeline.refresh_policies
       set cadence_interval = make_interval(days => v_days), freshness_class = v_class, next_due_at = v_next, updated_at = now()
     where id = v_policy.id
    returning jsonb_build_object('policy_id', id, 'freshness_class', freshness_class, 'cadence_interval', cadence_interval::text, 'next_due_at', next_due_at) into v_policy_after;
    update pipeline.layer1_source_operations
       set ingestion_cadence_days = case when p_schedule = 'manual' then ingestion_cadence_days else v_days end,
           auto_ingest = v_auto, change_reason = left(p_reason, 500), updated_by = auth.uid(), updated_at = now()
     where source_id = p_source_id
    returning jsonb_build_object('verification_cadence_days', verification_cadence_days, 'ingestion_cadence_days', ingestion_cadence_days, 'auto_ingest', auto_ingest) into v_after;
    v_after := v_after || jsonb_build_object('refresh_policy', v_policy_after);
    v_before := v_before || jsonb_build_object('refresh_policy', v_policy_before);
  else
    -- no Layer 1 refresh policy: its runs come from next_verification_at (layer1_regulatory_scheduler_tick_impl), as before
    update pipeline.layer1_source_operations
       set verification_cadence_days = v_days, ingestion_cadence_days = case when p_schedule = 'manual' then ingestion_cadence_days else v_days end,
           auto_ingest = v_auto, next_verification_at = least(coalesce(next_verification_at, now() + make_interval(days => v_days)), now() + make_interval(days => v_days)),
           change_reason = left(p_reason, 500), updated_by = auth.uid(), updated_at = now()
     where source_id = p_source_id
    returning jsonb_build_object('verification_cadence_days', verification_cadence_days, 'ingestion_cadence_days', ingestion_cadence_days, 'auto_ingest', auto_ingest) into v_after;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'layer1_schedule_set', p_source_id::text, jsonb_build_object('schedule', p_schedule, 'before', v_before, 'after', v_after, 'reason', left(p_reason, 500)), auth.uid());
  return jsonb_build_object('ok', true, 'schedule', p_schedule) || v_after;
end $f$
$def$);

-- 2. housekeeping: the retired section and the functions only it called ------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaced_by, retire_after, introduced_in, note) values
 ('screen', 'Scheduled jobs › Automations › Refresh schedules and one-off runs', 'Platform', 'Scheduled jobs',
  'Refresh policies of Layers 1 to 3 (edit schedule, run on demand), refresh queue and search refresh signals', 'retiring',
  'Layer 1 › Sources › Schedule (edits the Layer 1 refresh policies); Run now on each source',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up (Decision 269 amendment 4 Nov 2026, "Rewire, then retire"): section removed from Automations; old addresses open Layer 1 › Sources'),
 ('function', 'public.scheduler_policies_list_v1', 'Platform', 'Scheduled jobs',
  'Refresh schedules list', 'retiring', 'security.admin_layer1_operations_read (Layer 1 › Sources schedule columns)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller was the Refresh schedules section'),
 ('function', 'security.scheduler_policies_list_v1_browser_bridge', 'Platform', 'Scheduled jobs',
  'Refresh schedules list (implementation)', 'retiring', 'security.admin_layer1_operations_read',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller public.scheduler_policies_list_v1 (retiring)'),
 ('function', 'public.scheduler_policy_edit_v1', 'Platform', 'Scheduled jobs',
  'Edit a refresh schedule', 'retiring', 'public.admin_layer1_schedule (Layer 1 › Sources › Schedule)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller was the Refresh schedules section'),
 ('function', 'security.scheduler_policy_edit_v1_browser_bridge', 'Platform', 'Scheduled jobs',
  'Edit a refresh schedule (implementation)', 'retiring', 'public.admin_layer1_schedule',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller public.scheduler_policy_edit_v1 (retiring)'),
 ('function', 'public.scheduler_policy_run_now_v1', 'Platform', 'Scheduled jobs',
  'Run a refresh schedule once', 'retiring', 'Layer 1 › Sources › Run now (admin_layer1_command)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller was the Refresh schedules section'),
 ('function', 'security.scheduler_policy_run_now_v1_browser_bridge', 'Platform', 'Scheduled jobs',
  'Run a refresh schedule once (implementation)', 'retiring', 'Layer 1 › Sources › Run now',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller public.scheduler_policy_run_now_v1 (retiring)'),
 ('function', 'public.refresh_intelligence_overview', 'Platform', 'Scheduled jobs',
  'Refresh queue and search refresh signals of the Refresh schedules section', 'retiring', 'Scheduled jobs › Jobs (register runs) and Task manager',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller was the Refresh schedules section'),
 ('function', 'security.refresh_intelligence_overview_impl', 'Platform', 'Scheduled jobs',
  'Refresh queue and search refresh signals (implementation)', 'retiring', 'Scheduled jobs › Jobs and Task manager',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104420000',
  'SS-020 follow-up: only caller public.refresh_intelligence_overview (retiring)')
on conflict (kind, name) do update set status = excluded.status, replaced_by = excluded.replaced_by, retire_after = excluded.retire_after,
  note = excluded.note, updated_at = now()
 where pipeline.component_register.status = 'active';

-- 3. post-check -------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.component_register where introduced_in = '20261104420000' and status in ('retiring', 'retired')) < 9 then
    raise exception 'SS-020 follow-up: the register rows were not all recorded';
  end if;
end $$;
