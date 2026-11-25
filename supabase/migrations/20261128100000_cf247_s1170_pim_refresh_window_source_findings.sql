-- CF-247 s1170 (S1-RM-Design; Global Autonomous PIM step 5, first slice; Platform Admin 25 Nov 2026 23:12 AEDT: "Step 5 - recurring refresh, source-change detection and recovery of
-- expired leases."; Master Plan 6.2 interface 2: freshness is "inside or past the refresh window; only for a held value").
--   1. The refresh window is a setting (G2): pipeline pim.refresh_days, default 365 days (one academic year), changed on Settings with a reason. pipeline.field_register.refresh_days
--      (null by default) overrides it for one field.
--   2. security.field_state_entity_v1 now gives freshness for a held value: last verified, the window in days, and inside or past.
--   3. security.pim_refresh_v1(): by course field, held values and how many are past their window (refresh due); and the stored course pages by read outcome (read, fetch_failed,
--      blocked, robots_disallowed, http_error, not_read) with how many are due for the existing page re-read. A failed or blocked source keeps its old value (nothing is removed here).
--      Counted into the background PIM snapshot (pim.refresh).
--   Expired leases: the 90 expired field-enrich leases read live belong to S1-Build's held course entry window (route off, spend hold); the existing ops-job-lifecycle closes
--   leases at the attempt cap. They are reported in pim.leases and not touched here.
-- G1: no job (the existing data-delivery count). G2: the window is a setting. G3: no consumer API object touched (checked before and after). The cron ceiling and locks are checked.
-- Replaces: the s1164 freshness of security.field_state_entity_v1 (window and state added); the s1169 snapshot expression (one key added). Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the column add and function replaces
set local statement_timeout = '120s';  -- fixed: the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if to_regprocedure('security.pim_lifecycle_v1()') is null then raise exception 'guard: s1169 is not live'; end if;
end $g$;
create temp table s1170_locks on commit drop as select count(*) n from pipeline.manual_locks;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by, updated_at)
values ('pipeline', 'pim.refresh_days', 'PIM: refresh a held value after',
        'A held course or provider value is fresh for this many days after it was last verified; after that it is shown as refresh due. A field can have its own window in the field register. Nothing is removed when a value is due.',
        'number', '365'::jsonb, 30, 730, 'days', 1860, 'S1-RM-Design s1170 (PIM step 5; Master Plan 6.2 interface 2)', 'Data delivery',
        'security.field_state_entity_v1, security.pim_refresh_v1', now())
on conflict do nothing;

alter table pipeline.field_register add column if not exists refresh_days integer check (refresh_days is null or refresh_days between 1 and 3650);
comment on column pipeline.field_register.refresh_days is 'Refresh window for this field in days; null uses the setting pim.refresh_days (s1170).';

-- freshness of a held value (course grain): window and state added after the s1161/s1164 facts
do $r$
declare d text := pg_get_functiondef('security.field_state_entity_v1(text,uuid)'::regprocedure);
        a1 constant text := E'      if v_part then s := s || jsonb_build_object(''completeness'', ''partial''); end if;\n    end if;\n    return s;';
        b1 constant text := E'      if v_part then s := s || jsonb_build_object(''completeness'', ''partial''); end if;\n    end if;\n'
          || E'    -- s1170: freshness of a held value (window and inside or past)\n'
          || E'    if s->>''completeness'' in (''verified'', ''partial'') then\n'
          || E'      s := s || jsonb_build_object(''freshness'', jsonb_build_object(''last_verified_at'', (select c.last_verified_at from catalogue.courses c where c.id = p_entity),\n'
          || E'        ''window_days'', coalesce(r.refresh_days, security.pipeline_num_v1(''pim.refresh_days'', 365)::int),\n'
          || E'        ''state'', case when (select c.last_verified_at from catalogue.courses c where c.id = p_entity) >= now() - make_interval(days => coalesce(r.refresh_days, security.pipeline_num_v1(''pim.refresh_days'', 365)::int)) then ''inside'' else ''past'' end));\n'
          || E'    end if;\n    return s;';
        a2 constant text := E'''freshness'', case when v_held then jsonb_build_object(''last_verified_at'', p.last_verified_at, ''window_days'', null) end,';
        b2 constant text := E'''freshness'', case when v_held then jsonb_build_object(''last_verified_at'', p.last_verified_at, ''window_days'', coalesce(r.refresh_days, security.pipeline_num_v1(''pim.refresh_days'', 365)::int),\n'
          || E'        ''state'', case when p.last_verified_at >= now() - make_interval(days => coalesce(r.refresh_days, security.pipeline_num_v1(''pim.refresh_days'', 365)::int)) then ''inside'' else ''past'' end) end,';
begin
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 then raise exception 'guard: the course freshness anchor is not found exactly once'; end if;
  if (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then raise exception 'guard: the provider freshness anchor is not found exactly once'; end if;
  execute replace(replace(d, a1, b1), a2, b2);
end $r$;

create or replace function security.pim_refresh_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
  with w as (select security.pipeline_num_v1('pim.refresh_days', 365)::int d),
  h as (
    select a.attribute field, count(*) held,
           count(*) filter (where c.last_verified_at is null or c.last_verified_at < now() - make_interval(days => coalesce(r.refresh_days, w.d))) due,
           min(c.last_verified_at) oldest_verified
      from pipeline.course_attribute_coverage a cross join w
      join pipeline.field_register r on r.field = a.attribute
      join catalogue.courses c on c.id = a.course_id and c.lifecycle_status = 'active'
     where a.state = 'admitted' and not exists (select 1 from security.provider_hidden_v1 x where x.provider_id = a.provider_id)
     group by a.attribute),
  p as (
    select case when g.read_status is null then 'not_read'
                when g.read_status = 'read' and g.http_status >= 400 then 'http_error'
                when g.read_status in ('read', 'fetch_failed', 'blocked', 'robots_disallowed') then g.read_status
                else 'other' end outcome,
           count(*) pages, count(*) filter (where g.next_read_at <= now()) due_for_reread
      from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
     where g.status = 'bound'
     group by 1)
  select jsonb_build_object(
    'as_at', now(), 'window_days', (select d from w),
    'fields', coalesce((select jsonb_agg(jsonb_build_object('field', field, 'held', held, 'refresh_due', due, 'oldest_verified', oldest_verified) order by field) from h), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(jsonb_build_object('outcome', outcome, 'pages', pages, 'due_for_reread', due_for_reread) order by outcome) from p), '[]'::jsonb),
    'meaning', 'Held values past their refresh window are due to be verified again; the old value stays until a verified successor replaces it. Bound course pages by their last read; a failed, blocked or refused source keeps its value and is re-read by the existing page re-read when due.')
$f$;
comment on function security.pim_refresh_v1() is 'PIM step 5 (s1170): refresh due by course field (window pim.refresh_days or the field''s own) and bound course pages by read outcome; counted into the Data Delivery snapshot.';
revoke all on function security.pim_refresh_v1() from public, anon, authenticated;
grant execute on function security.pim_refresh_v1() to service_role;

do $s$
declare d text := pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure);
        a constant text := E'''lifecycle'', security.pim_lifecycle_v1())';
        b constant text := E'''lifecycle'', security.pim_lifecycle_v1(), ''refresh'', security.pim_refresh_v1())';
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the s1169 snapshot anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $s$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); x jsonb; c1 uuid; t0 timestamptz := clock_timestamp();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1170_locks) then raise exception 'guard: a manual lock was removed'; end if;  -- people may add locks while this runs
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron jobs above the ceiling of 140'; end if;  -- fixed: the protected ceiling
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pim.refresh_days' and used_by is not null and unit = 'days') then
    raise exception 'guard: the refresh window setting is missing';
  end if;
  select q.course_id into c1 from catalogue.course_english_requirements q join catalogue.courses c on c.id = q.course_id and c.lifecycle_status = 'active'
   where q.status = 'active' order by q.course_id limit 1;  -- fixed: one sample course for the rehearsal
  x := security.field_state_entity_v1('english', c1);
  if x->'freshness'->>'state' not in ('inside', 'past') or (x->'freshness'->>'window_days')::int < 1 then raise exception 'guard: freshness of a held value %', x; end if;
  x := security.pim_refresh_v1();
  if jsonb_array_length(x->'fields') = 0 or jsonb_array_length(x->'sources') = 0 then raise exception 'guard: the refresh read is empty'; end if;
  if position('pim_refresh_v1' in pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) = 0 then raise exception 'guard: the snapshot does not count refresh'; end if;
  raise notice 'refresh read % ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int;  -- fixed: milliseconds
end $c$;
