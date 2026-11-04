-- CF-247 SS-020 follow-up items 1, 2 and 4 (Decision 269 amendments, Platform Admin 4 Nov 2026 about 05:40; approval 06:53 §2; role decision
-- Option A, direction 4 Nov 2026 10:00 §8: "retain Pipeline Operator access to existing Layer 1 scheduling and run controls ... Preserve existing
-- role boundaries and audit behaviour. Do not widen access"). Admin docs/platform/ui-audit/2026-11-04-ss020-follow-up-prompt.md,
-- 2026-11-04-ss020-implementation-review.md and docs/platform/2026-11-04-autonomous-admission-throughput-direction-1000.md §8.
-- Item 1, "Rewire, then retire": Layer 1 › Sources' Schedule and Run now act on the register's Layer 1 refresh policy (pipeline.refresh_policies,
--   the rows security.refresh_scheduler_tick_impl reads), so Scheduled jobs › Automations › "Refresh schedules and one-off runs" can retire.
-- Role and audit rules, matched to the legacy controls (read live 4 Nov 2026 11:09 AEDT):
--   - Legacy Edit schedule (security.scheduler_policy_edit_v1_browser_bridge, md5 863025c7): rank 4 or above, reason of 5 or more characters,
--     changes the policy's cadence and next run (enabled as given), audited in pipeline.refresh_policy_action_events ('edit_schedule').
--   - Legacy Run on demand (security.scheduler_policy_run_now_v1_browser_bridge, md5 be605352): rank 4 or above, reason of 5 or more, enabled
--     policy only, queues one manual_governed Layer 1 request (no duplicate), audited ('run_on_demand').
--   Layer 1 › Sources now calls those same two functions for a register with a policy, so ranks 4 and 5 keep exactly what Automations gave them,
--   with the same audit rows. A rank 4 or 5 user cannot choose Manual (it switches automatic loading off, a Platform Admin setting today) and
--   cannot change a source without a policy (the legacy screen never reached those). The Platform Admin keeps everything it had: Manual, the
--   load cadence and automatic loading, and the existing Run now (admin_layer1_command / layer1-operations).
-- Measured live, read only, 4 Nov 2026 06:55-07:20 and 11:09-11:10 AEDT (project fxcwkweaxjtknorudmwp):
--   a. 3 Layer 1 policies: AU CRICOS (weekly, 7 days; its Sources schedule said 30 days), NZQA providers (weekly) and Education Counts NZ
--      (monthly). The third has no Layer 1 operations profile, is not on Layer 1 › Sources, and its one request has been queued since
--      24 Sep 2026; it is left as it is (recorded for the Platform Admin).
--   b. layer1_source_operations.verification_cadence_days drives next_verification_at, which security.layer1_regulatory_scheduler_tick_impl
--      reads for all 43 profiles. It is not retired; the Schedule stops writing it only for a register with a refresh policy. The 41 sources
--      without one keep today's write (Platform Admin only, reason of 4 or more, as today).
--   c. The next run moves with the cadence: the previous due time (next run less the old cadence) plus the new cadence, never earlier than now.
-- Item 4: "Layer 2 → conditional Layer 3" is written only in src/ScheduledJobsWorkspace.jsx (the retiring screen); no table row, setting or
--   function holds it (checked live), so no data changes.
-- Replaces: public.admin_layer1_schedule (same name and arguments; md5-guarded whole replacement); public.scheduler_policy_run_now_v1 as the
--   Layer 1 run entry by public.admin_layer1_policy_run_v1 (new, calls the same legacy implementation)
-- Retires: the screen Scheduled jobs › Automations › Refresh schedules and one-off runs, and the functions only it called
--   (public.scheduler_policies_list_v1 and its security implementation, public.scheduler_policy_edit_v1, public.scheduler_policy_run_now_v1,
--   public.refresh_intelligence_overview and its security implementation), marked retiring in pipeline.component_register. The two security
--   bridges (edit and run on demand) stay active: Layer 1 › Sources uses them. Nothing is dropped, deleted or switched on.
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

-- a new function, created only when absent or already this definition
create or replace function pg_temp.create_once(p_sig text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if to_regprocedure(p_sig) is not null then
    if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
    raise exception '% already exists with another definition (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure));
  end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': created';
end $f$;

-- 0. the definitions the new code calls or relies on are the ones it was written against (not changed here)
do $g$
declare r record;
begin
  for r in select * from (values
      ('security.refresh_scheduler_tick_impl(timestamptz,integer)', '5f7b3ece8e91919d622b16af652b9250'),
      ('security.scheduler_policy_edit_v1_browser_bridge(uuid,timestamptz,integer,timestamptz,boolean,text)', '863025c7a7c6c39dd445ff5419ff58ce'),
      ('security.scheduler_policy_run_now_v1_browser_bridge(uuid,text)', 'be60535243220790e08d56e4ee47d4e0')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. Layer 1 › Sources' Schedule edits the register's Layer 1 refresh policy through the legacy edit control ------------------------------
select pg_temp.replace_once('public.admin_layer1_schedule(uuid,text,text)', '53b48153be94af028d322e2d5851962a', 'cc0c680d0a1768410d0dd9c516ff4af7', $def$
create or replace function public.admin_layer1_schedule(p_source_id uuid, p_schedule text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_days int; v_auto boolean; v_rank int; v_before jsonb; v_after jsonb; v_policy pipeline.refresh_policies%rowtype; v_next timestamptz;
begin
  v_rank := coalesce(security.current_role_rank(), 0);
  if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator required' using errcode = '42501'; end if;
  select case p_schedule when 'daily' then 1 when 'weekly' then 7 when 'monthly' then 30 when 'quarterly' then 91 when 'yearly' then 365 when 'manual' then 30 end,
         p_schedule <> 'manual' into v_days, v_auto;
  if v_days is null then raise exception 'schedule must be daily, weekly, monthly, quarterly, yearly or manual'; end if;
  select jsonb_build_object('verification_cadence_days', verification_cadence_days, 'ingestion_cadence_days', ingestion_cadence_days, 'auto_ingest', auto_ingest)
    into v_before from pipeline.layer1_source_operations where source_id = p_source_id for update;
  if v_before is null then raise exception 'not a Layer 1 source'; end if;
  -- SS-020 follow-up (Decision 269 amendment; Option A, 4 Nov 2026 10:00 §8): a register with a Layer 1 refresh policy is scheduled by that
  -- policy (security.refresh_scheduler_tick_impl). Its Schedule goes through the legacy Edit schedule control, with that control's rank (4),
  -- reason (5 characters) and audit (refresh_policy_action_events); verification_cadence_days is no longer written for it.
  select * into v_policy from pipeline.refresh_policies where layer = 1 and source_id = p_source_id order by updated_at desc, id limit 1 for update;
  if found then
    if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'give a reason of at least 5 characters (kept in the log)' using errcode = '22023'; end if;
    if v_rank < 6 and p_schedule = 'manual' then raise exception 'Manual switches automatic loading off: Platform Admin required' using errcode = '42501'; end if;
    v_next := greatest(now(), coalesce(v_policy.next_due_at - coalesce(v_policy.cadence_interval, make_interval()), now()) + make_interval(days => v_days));
    v_before := v_before || jsonb_build_object('refresh_policy', jsonb_build_object('policy_id', v_policy.id, 'cadence_interval', v_policy.cadence_interval::text, 'next_due_at', v_policy.next_due_at));
    perform security.scheduler_policy_edit_v1_browser_bridge(v_policy.id, v_policy.updated_at, v_days, v_next, v_policy.enabled, p_reason);
    if v_rank >= 6 then
      update pipeline.layer1_source_operations
         set ingestion_cadence_days = case when p_schedule = 'manual' then ingestion_cadence_days else v_days end,
             auto_ingest = v_auto, change_reason = left(p_reason, 500), updated_by = auth.uid(), updated_at = now()
       where source_id = p_source_id;
    end if;
    select jsonb_build_object('verification_cadence_days', o.verification_cadence_days, 'ingestion_cadence_days', o.ingestion_cadence_days, 'auto_ingest', o.auto_ingest,
             'refresh_policy', jsonb_build_object('policy_id', p.id, 'cadence_interval', p.cadence_interval::text, 'next_due_at', p.next_due_at))
      into v_after from pipeline.layer1_source_operations o, pipeline.refresh_policies p where o.source_id = p_source_id and p.id = v_policy.id;
  else
    -- no Layer 1 refresh policy: its runs come from next_verification_at (layer1_regulatory_scheduler_tick_impl), and only the Platform Admin
    -- changes it, as before
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
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

-- 2. Layer 1 › Sources' Run now for ranks 4 and 5: the legacy Run on demand of the register's policy ---------------------------------------
select pg_temp.create_once('public.admin_layer1_policy_run_v1(uuid,text)', '574e4ece482e5907d539a171e389f01a', $def$
create or replace function public.admin_layer1_policy_run_v1(p_source_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_policy uuid;
begin
  -- SS-020 follow-up (Option A, 4 Nov 2026 10:00 §8): the same rank (4), reason (5 characters), enabled-policy rule, duplicate check and audit
  -- as Refresh schedules › Run on demand, which it replaces as the entry point
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator required' using errcode = '42501'; end if;
  select id into v_policy from pipeline.refresh_policies where layer = 1 and source_id = p_source_id order by updated_at desc, id limit 1;
  if v_policy is null then raise exception 'this source has no refresh policy; a Platform Admin starts it with Run now' using errcode = '22023'; end if;
  return security.scheduler_policy_run_now_v1_browser_bridge(v_policy, p_reason);
end $f$
$def$);
revoke all on function public.admin_layer1_policy_run_v1(uuid, text) from public, anon;
grant execute on function public.admin_layer1_policy_run_v1(uuid, text) to authenticated, service_role;

-- 3. housekeeping: the retired section and the functions only it called ------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaced_by, retire_after, introduced_in, note) values
 ('screen', 'Scheduled jobs › Automations › Refresh schedules and one-off runs', 'Platform', 'Scheduled jobs',
  'Refresh policies of Layers 1 to 3 (edit schedule, run on demand), refresh queue and search refresh signals', 'retiring',
  'Layer 1 › Sources › Schedule and Run now (the Layer 1 refresh policies, same roles and audit)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104510000',
  'SS-020 follow-up (Decision 269 amendment 4 Nov 2026, "Rewire, then retire"; Option A 10:00 §8): section removed from Automations; old addresses open Layer 1 › Sources'),
 ('function', 'public.scheduler_policies_list_v1', 'Platform', 'Scheduled jobs',
  'Refresh schedules list', 'retiring', 'security.admin_layer1_operations_read (Layer 1 › Sources schedule columns)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104510000',
  'SS-020 follow-up: only caller was the Refresh schedules section'),
 ('function', 'security.scheduler_policies_list_v1_browser_bridge', 'Platform', 'Scheduled jobs',
  'Refresh schedules list (implementation)', 'retiring', 'security.admin_layer1_operations_read',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104510000',
  'SS-020 follow-up: only caller public.scheduler_policies_list_v1 (retiring)'),
 ('function', 'public.scheduler_policy_edit_v1', 'Platform', 'Scheduled jobs',
  'Edit a refresh schedule (screen entry)', 'retiring', 'public.admin_layer1_schedule (Layer 1 › Sources › Schedule; same implementation)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104510000',
  'SS-020 follow-up: only caller was the Refresh schedules section; security.scheduler_policy_edit_v1_browser_bridge stays (admin_layer1_schedule calls it)'),
 ('function', 'public.scheduler_policy_run_now_v1', 'Platform', 'Scheduled jobs',
  'Run a refresh schedule once (screen entry)', 'retiring', 'public.admin_layer1_policy_run_v1 (Layer 1 › Sources › Run now; same implementation)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104510000',
  'SS-020 follow-up: only caller was the Refresh schedules section; security.scheduler_policy_run_now_v1_browser_bridge stays (admin_layer1_policy_run_v1 calls it)'),
 ('function', 'public.refresh_intelligence_overview', 'Platform', 'Scheduled jobs',
  'Refresh queue and search refresh signals of the Refresh schedules section', 'retiring', 'Scheduled jobs › Jobs (register runs) and Task manager',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104510000',
  'SS-020 follow-up: only caller was the Refresh schedules section'),
 ('function', 'security.refresh_intelligence_overview_impl', 'Platform', 'Scheduled jobs',
  'Refresh queue and search refresh signals (implementation)', 'retiring', 'Scheduled jobs › Jobs and Task manager',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104510000',
  'SS-020 follow-up: only caller public.refresh_intelligence_overview (retiring)')
on conflict (kind, name) do update set status = excluded.status, replaced_by = excluded.replaced_by, retire_after = excluded.retire_after,
  note = excluded.note, updated_at = now()
 where pipeline.component_register.status = 'active';

-- 4. post-check -------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.component_register where introduced_in = '20261104510000' and status in ('retiring', 'retired')) < 7 then
    raise exception 'SS-020 follow-up: the register rows were not all recorded';
  end if;
end $$;
