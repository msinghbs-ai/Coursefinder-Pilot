-- CF-247 F-INT D3 forward fix (Platform Admin decision, 9 Nov 2026: "Do not manually rerun an already-applied migration. If the revisit backfill was missed, implement an
-- idempotent forward migration with checksum, row-count and rollback/forward-recovery safeguards."): give the intake rows that wait for evidence their first revisit time.
-- Why (measured read-only on production, 9 Nov 2026):
--   * Migration 20261109040000 (release #943) gives a held row a revisit time only when the switch intake_dates.revisit_stored_inputs is on at the moment it is applied.
--     The switch was 0 (off by default), so its backfill (step 6 of that file) changed nothing: 8,793 undated active rows held as evidence_ambiguous (7,733),
--     reader_correction_needed (867) or calendar_needs_correction (193) still have next_revisit_at null and are never looked at again on a timer.
--   * That file is applied and is NOT run again. This migration is the forward fix: a new version that does the same thing once, with safeguards.
-- What (no new job, scheduler, engine, screen or setting; no date, calendar value or decision is written):
--   1 switch first: nothing is done unless intake_dates.revisit_stored_inputs = 1 at the moment this migration is applied (a notice is raised and the migration ends cleanly;
--     the migration never turns a switch on). The Platform Admin turns the switch on in Settings > Pipeline settings (with a reason) and then the change is merged.
--   2 the same rows as the original backfill: an active intake of an active course with a date missing, next_revisit_at null, and a next action that
--     security.intake_revisit_stored_inputs_v1 names (the one place that lists the four actions and reads the switch); the revisit time is the same spread over
--     intake_dates.revisit_days days (no storm). Beyond the original predicate, a row is left alone when its course is locked by hand (pipeline.manual_locks intakes),
--     when its value was withdrawn (intake status, event outcome or a withdrawn: reason) or rejected (pipeline.intake_date_rejections of its reading and year, or a
--     reason that names a rejected value). Only next_revisit_at changes, and only from null.
--   3 safeguards, all inside the one transaction of the migration (any failure rolls the whole change back, nothing is left half done):
--       a the rows are locked in a fixed order, then counted: the candidates must not exceed the rows the original step-6 predicate selects now (zero candidates is a clean no-op);
--       b the exact change is recorded before it is made: pipeline.intake_revisit_backfill_batches (counts and checksums) and pipeline.intake_revisit_backfill_log
--         (row, previous value, new value);
--       c a md5 checksum over (row, new value) is computed from the plan, written to the batch and asserted after the update (on the rows, on the batch as stored and
--         on the log as stored); the number of rows changed must equal the candidates and the log; every other column of every row, and the revisit time of every
--         other row, must be identical before and after.
--   4 forward recovery (not run automatically): security.intake_revisit_backfill_undo_v1(batch) puts back the previous value of a row only while the row still holds exactly
--     the value this backfill set (a row decided again since keeps its new time); public.admin_intake_revisit_backfill_undo_v1(batch, reason) is the Platform Admin call.
-- Safe to run again: the tables and functions are created if absent, and a second run finds no candidate (every row already has a time) and changes nothing.
-- Consumer API: unchanged (G3). Only new pipeline tables, new security and public.admin_ functions and pipeline.course_intake_dates.next_revisit_at (from null) are touched.
-- Replaces: nothing (it does what step 6 of 20261109040000 does when its switch is on, once, with safeguards; that migration is not run again)
-- Retires: nothing
-- Nothing is dropped or deleted.

-- 1 the batch record and the row log (new, additive) -----------------------------------------------------------------------------------------------
create table if not exists pipeline.intake_revisit_backfill_batches (
  batch_id uuid primary key,
  migration_version text not null,
  created_at timestamptz not null default now(),
  switch_value numeric not null,
  live_predicate_count integer not null,
  candidate_count integer not null,
  rows_changed integer not null,
  checksum_expected text not null,
  checksum_after text,
  elapsed_ms integer,
  status text not null default 'planned' check (status in ('planned', 'applied', 'undone', 'partly_undone')),
  undone_at timestamptz,
  rows_restored integer,
  rows_skipped integer
);
comment on table pipeline.intake_revisit_backfill_batches is 'CF-247 F-INT D3 forward fix (9 Nov 2026): one row for each time the revisit-time backfill (migration 20261109170000) changed rows: the switch value, the rows the original step-6 predicate selected (live_predicate_count), the candidates, the rows changed, the md5 checksum over (row, new value) expected from the plan and read back after the update, the time taken and, after security.intake_revisit_backfill_undo_v1, how many rows were restored and how many were left because they had changed since. Platform Admin and the service role only.';
alter table pipeline.intake_revisit_backfill_batches enable row level security;
revoke all on pipeline.intake_revisit_backfill_batches from public, anon, authenticated;

create table if not exists pipeline.intake_revisit_backfill_log (
  batch_id uuid not null references pipeline.intake_revisit_backfill_batches(batch_id),
  intake_id uuid not null,
  previous_next_revisit_at timestamptz,
  new_next_revisit_at timestamptz not null,
  created_at timestamptz not null default now(),
  undone_at timestamptz,
  undo_outcome text check (undo_outcome in ('restored', 'skipped_changed')),
  primary key (batch_id, intake_id)
);
comment on table pipeline.intake_revisit_backfill_log is 'CF-247 F-INT D3 forward fix (9 Nov 2026): the exact rows the revisit-time backfill (migration 20261109170000) changed in pipeline.course_intake_dates, with the value before (always null) and the value it set. security.intake_revisit_backfill_undo_v1 restores a row only while it still holds the value set here and records the outcome (restored, or skipped_changed when the row has changed since). Nothing else is stored; no row is removed.';
alter table pipeline.intake_revisit_backfill_log enable row level security;
revoke all on pipeline.intake_revisit_backfill_log from public, anon, authenticated;

-- 2 forward recovery (never run automatically) -----------------------------------------------------------------------------------------------------
create or replace function security.intake_revisit_backfill_undo_v1(p_batch uuid) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_restored int := 0; v_skipped int := 0; v_total int; v_status text;
begin
  perform 1 from pipeline.intake_revisit_backfill_batches b where b.batch_id = p_batch for update;
  if not found then raise exception 'revisit backfill batch % is not recorded', p_batch using errcode = '22023'; end if;
  -- a row goes back only while it holds exactly the value this backfill set; a row decided again since (a new time) or changed in any other way keeps what it has
  with l as (select g.intake_id, g.previous_next_revisit_at from pipeline.intake_revisit_backfill_log g where g.batch_id = p_batch and g.undone_at is null order by g.intake_id),
  u as (
    update pipeline.course_intake_dates d set next_revisit_at = l.previous_next_revisit_at
      from l, pipeline.intake_revisit_backfill_log g
     where g.batch_id = p_batch and g.intake_id = l.intake_id and d.intake_id = l.intake_id and d.next_revisit_at is not distinct from g.new_next_revisit_at
    returning d.intake_id)
  update pipeline.intake_revisit_backfill_log g set undone_at = now(), undo_outcome = case when u.intake_id is not null then 'restored' else 'skipped_changed' end
    from l left join u on u.intake_id = l.intake_id
   where g.batch_id = p_batch and g.intake_id = l.intake_id;
  select count(*) filter (where undo_outcome = 'restored'), count(*) filter (where undo_outcome = 'skipped_changed'), count(*)
    into v_restored, v_skipped, v_total from pipeline.intake_revisit_backfill_log where batch_id = p_batch;
  v_status := case when v_skipped = 0 then 'undone' else 'partly_undone' end;
  update pipeline.intake_revisit_backfill_batches b set status = v_status, undone_at = now(), rows_restored = v_restored, rows_skipped = v_skipped where b.batch_id = p_batch;
  return jsonb_build_object('batch', p_batch, 'status', v_status, 'rows_in_batch', v_total, 'restored', v_restored, 'skipped_changed_since', v_skipped);
end $function$;
comment on function security.intake_revisit_backfill_undo_v1(uuid) is 'CF-247 F-INT D3 forward fix (9 Nov 2026): puts back the previous next_revisit_at of the rows a revisit-time backfill batch changed, only for rows that still hold exactly the value the backfill set; a row that has changed since is left as it is and recorded as skipped_changed. Not run automatically; the Platform Admin calls public.admin_intake_revisit_backfill_undo_v1. Running it again changes nothing.';
revoke all on function security.intake_revisit_backfill_undo_v1(uuid) from public, anon, authenticated;

create or replace function public.admin_intake_revisit_backfill_undo_v1(p_batch uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  v := security.intake_revisit_backfill_undo_v1(p_batch);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake_dates', 'revisit_backfill_undo', 'pipeline.course_intake_dates', jsonb_build_object('reason', p_reason, 'result', v), auth.uid());
  return v;
end $function$;
comment on function public.admin_intake_revisit_backfill_undo_v1(uuid, text) is 'CF-247 F-INT D3 forward fix (9 Nov 2026): the Platform Admin''s forward recovery of a revisit-time backfill batch (security.intake_revisit_backfill_undo_v1), with a reason, recorded in the admin control log. Rows that changed since the backfill are left alone.';
revoke all on function public.admin_intake_revisit_backfill_undo_v1(uuid, text) from public, anon;
grant execute on function public.admin_intake_revisit_backfill_undo_v1(uuid, text) to authenticated;

-- 3 the backfill: once, only while the switch is on, with its safeguards -------------------------------------------------------------------------------
do $backfill$
declare
  v_batch uuid := gen_random_uuid();
  v_t0 timestamptz := clock_timestamp();
  v_switch numeric := security.pipeline_num_v1('intake_dates.revisit_stored_inputs', 0);
  v_days numeric := security.pipeline_num_v1('intake_dates.revisit_days', 14);
  v_live int; v_cand int; v_changed int; v_logged int; v_other_before text; v_other_after text; v_rest_before text; v_rest_after text; v_exp text; v_after text; v_stored text; v_logsum text;
begin
  if v_switch is distinct from 1 then
    raise notice 'F-INT revisit backfill: intake_dates.revisit_stored_inputs is % (not 1), so no row is changed; the switch is not turned on by this migration', v_switch;
    return;
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('cf247.intake_revisit_backfill', 0)) then
    raise exception 'F-INT revisit backfill: another run of the backfill holds its lock; nothing is changed';
  end if;
  set local lock_timeout = '30s';  -- fixed: technical safety time-out, so the migration never waits behind a long lock (the whole change rolls back)

  -- 3a the rows are locked in a fixed order (a running intake-dates-apply finishes its row first), then counted
  perform 1 from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses c on c.id = i.course_id
   where i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
     and d.next_revisit_at is null and security.intake_revisit_stored_inputs_v1(d.next_action)
   order by d.intake_id for update of d;

  -- the rows the original step-6 predicate selects now (the bound)
  select count(*) into v_live from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses c on c.id = i.course_id
   where i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
     and d.next_revisit_at is null and security.intake_revisit_stored_inputs_v1(d.next_action);

  -- the plan: the candidate rows and the value each would get (the same spread as the original step 6), held until the update is checked
  create temp table rb_plan on commit drop as
    select d.intake_id, d.next_revisit_at as previous_value,
           now() + make_interval(secs => v_days::float8 * 86400  -- fixed: seconds in a day
                                         * ((abs(hashtextextended(d.intake_id::text, 0)) % 10000) / 10000.0)) as new_value
      from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses c on c.id = i.course_id
     where i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
       and d.next_revisit_at is null and security.intake_revisit_stored_inputs_v1(d.next_action)
       -- left alone: a course locked by hand, a withdrawn value, a rejected value (a rejection without a year does not identify a row's value, so it is not matched)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = d.course_id and k.field in ('intakes', 'intake'))
       and coalesce(d.reason, '') not ilike 'withdrawn:%' and coalesce(d.reason, '') not ilike '%recorded as rejected%'
       and not exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = d.intake_id and w.outcome = 'withdrawn')
       and not exists (select 1 from pipeline.intake_date_rejections j where j.provider_id = d.provider_id and j.proposal_id is not distinct from d.proposal_id and j.year = d.evidence_year);
  select count(*) into v_cand from rb_plan;

  if v_cand = 0 then
    raise notice 'F-INT revisit backfill: no row needs a revisit time (the original predicate selects %), so nothing is changed', v_live;
    return;
  end if;
  if v_cand > v_live then
    raise exception 'F-INT revisit backfill: % candidate rows exceed the % rows the original predicate selects; nothing is changed', v_cand, v_live;
  end if;

  -- the checksum of the plan: (row, new value), in row order; the time is written in UTC to the microsecond so it does not depend on a session setting
  select md5(string_agg(p.intake_id::text || '=' || to_char(p.new_value at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), '|' order by p.intake_id)) into v_exp from rb_plan p;
  -- what must not change: every other column of every row, and the revisit time of every row that is not a candidate
  select md5(string_agg((to_jsonb(d) - 'next_revisit_at')::text, '|' order by d.intake_id)) into v_other_before from pipeline.course_intake_dates d;
  select md5(string_agg(d.intake_id::text || '=' || coalesce(to_char(d.next_revisit_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), ''), '|' order by d.intake_id)) into v_rest_before
    from pipeline.course_intake_dates d where not exists (select 1 from rb_plan p where p.intake_id = d.intake_id);

  -- 3b the record first, then the change
  insert into pipeline.intake_revisit_backfill_batches(batch_id, migration_version, switch_value, live_predicate_count, candidate_count, rows_changed, checksum_expected)
  values (v_batch, '20261109170000', v_switch, v_live, v_cand, 0, v_exp);
  insert into pipeline.intake_revisit_backfill_log(batch_id, intake_id, previous_next_revisit_at, new_next_revisit_at)
  select v_batch, p.intake_id, p.previous_value, p.new_value from rb_plan p;
  get diagnostics v_logged = row_count;

  update pipeline.course_intake_dates d set next_revisit_at = p.new_value
    from rb_plan p where p.intake_id = d.intake_id and d.next_revisit_at is null;
  get diagnostics v_changed = row_count;

  -- 3c the checks: any difference raises, and the whole migration rolls back
  select md5(string_agg(d.intake_id::text || '=' || to_char(d.next_revisit_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), '|' order by d.intake_id)) into v_after
    from pipeline.course_intake_dates d join rb_plan p on p.intake_id = d.intake_id;
  select md5(string_agg((to_jsonb(d) - 'next_revisit_at')::text, '|' order by d.intake_id)) into v_other_after from pipeline.course_intake_dates d;
  select md5(string_agg(d.intake_id::text || '=' || coalesce(to_char(d.next_revisit_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), ''), '|' order by d.intake_id)) into v_rest_after
    from pipeline.course_intake_dates d where not exists (select 1 from rb_plan p where p.intake_id = d.intake_id);
  if v_changed <> v_cand or v_logged <> v_cand then
    raise exception 'F-INT revisit backfill: % rows planned, % logged, % changed; rolled back', v_cand, v_logged, v_changed;
  end if;
  if v_after is distinct from v_exp then
    raise exception 'F-INT revisit backfill: checksum after the update (%) is not the planned checksum (%); rolled back', v_after, v_exp;
  end if;
  if v_other_after is distinct from v_other_before then
    raise exception 'F-INT revisit backfill: a column other than next_revisit_at changed; rolled back';
  end if;
  if v_rest_after is distinct from v_rest_before then
    raise exception 'F-INT revisit backfill: the revisit time of a row that is not a candidate changed; rolled back';
  end if;
  if (select count(*) from pipeline.intake_revisit_backfill_log g join pipeline.course_intake_dates d on d.intake_id = g.intake_id and d.next_revisit_at = g.new_next_revisit_at where g.batch_id = v_batch) <> v_cand then
    raise exception 'F-INT revisit backfill: the log does not match the rows; rolled back';
  end if;
  -- what was written to the record is read back: the checksum stored in the batch, and the checksum of the log rows as stored, are the planned checksum
  select b.checksum_expected into v_stored from pipeline.intake_revisit_backfill_batches b where b.batch_id = v_batch;
  select md5(string_agg(g.intake_id::text || '=' || to_char(g.new_next_revisit_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), '|' order by g.intake_id)) into v_logsum
    from pipeline.intake_revisit_backfill_log g where g.batch_id = v_batch;
  if v_stored is distinct from v_exp or v_logsum is distinct from v_exp then
    raise exception 'F-INT revisit backfill: the recorded checksum (%) or the checksum of the log (%) is not the planned checksum (%); rolled back', v_stored, v_logsum, v_exp;
  end if;

  update pipeline.intake_revisit_backfill_batches b
     set status = 'applied', rows_changed = v_changed, checksum_after = v_after, elapsed_ms = (extract(epoch from clock_timestamp() - v_t0) * 1000)::int  -- fixed: milliseconds in a second
   where b.batch_id = v_batch;
  raise notice 'F-INT revisit backfill: batch % gave % rows a revisit time (original predicate: % rows; left alone: %); checksum %', v_batch, v_changed, v_live, v_live - v_cand, v_after;
end $backfill$;

-- 4 housekeeping: the register ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.intake_revisit_backfill_batches', 'Layer 2', 'Intake dates', 'One row for each revisit-time backfill: switch value, rows the original predicate selected, candidates, rows changed, checksums, time taken and the result of any undo', 'active', '{}', '20261109170000'),
 ('table', 'pipeline.intake_revisit_backfill_log', 'Layer 2', 'Intake dates', 'The exact rows a revisit-time backfill changed, with the value before and the value set, for forward recovery', 'active', '{}', '20261109170000'),
 ('function', 'security.intake_revisit_backfill_undo_v1', 'Layer 2', 'Intake dates', 'Forward recovery of a revisit-time backfill batch: restores only rows that still hold the value the backfill set; never run automatically', 'active', '{}', '20261109170000'),
 ('function', 'public.admin_intake_revisit_backfill_undo_v1', 'Layer 2', 'Intake dates', 'Platform Admin call for the forward recovery of a revisit-time backfill batch, with a reason', 'active', '{}', '20261109170000')
on conflict (kind, name) do nothing;
