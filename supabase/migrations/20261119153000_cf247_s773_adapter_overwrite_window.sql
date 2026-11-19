-- CF-247 s773: admission runner B no longer times out in the adapter overwrite (IQ-00594; Platform Admin 19 Nov 2026 15:18 AEDT, chat S1-Build).
-- Measured in rolled-back live dry runs (GitHub Actions, 19 Nov 2026 15:20-15:35 AEDT):
--   * admission-rule-runner-b failed at 13:19 on the 120 s statement limit inside the Layer 4 block check; its ticks run 60-150 s.
--     adapter-overwrite took up to 113 s (median 55 s on lane a, 81 s on lane b) in the last 6 hours.
--   * security.adapter_overwrite_v1 walks every read page with an adapter reading (20,545 pages) on every run that is not skipped, with ten
--     correlated reads per page and security.layer4_entity_or_parent_blocked (0.8 ms a call; 10,530 calls 8.5 s) against
--     security.layer4_active_blocks, which holds 0 rows. Its loop stops only after p_limit pages were replaced, and most pages need nothing.
-- What changes (md5-guarded; no table, column or job; signatures and grants unchanged):
--   1. security.adapter_overwrite_v1: the Layer 4 block check is one anti-join on security.layer4_active_blocks (the same rule: an operational
--      block on the course, or on its provider), and the loop reads only the window of course ids that the gated job sets for this run
--      (transaction-local settings cf247.ao_lo / cf247.ao_hi). Without them (any other caller) it reads every page, as before.
--   2. security.adapter_overwrite_gated_v1: each run takes the next batch.adapter_overwrite_window pages (new setting, default 1,000) by course
--      id after the cursor kept in pipeline.job_input_marks.last_result, so a full pass of about 20,500 pages takes about 21 runs (10 minutes
--      apart). A window that reached p_limit replacements is read again before the cursor moves on. When a pass ends, the job is skipped as
--      before until new input arrives (or waste.admit_full_check_hours passes); input that arrived during a pass starts another pass.
-- Replaces: the whole-table walk of the adapter overwrite on every run, and its per-page Layer 4 block function call.
-- Retires: nothing.
-- G1: no job added or changed. G2: one new setting (batch.adapter_overwrite_window, on Settings › Pipeline settings). G3: untouched.

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'batch.adapter_overwrite_window', 'Adapter overwrite: pages checked per run',
   'Each run of adapter-overwrite checks this many read pages with an adapter reading, in course order from where the last run stopped, so one run stays well inside the statement limit. A full pass of every page takes several runs.',
   'number', to_jsonb(1000), 100, 20000, 'pages', 102, 'Job sizes', 'security.adapter_overwrite_gated_v1',
   'CF-247 s773 (Platform Admin 19 Nov 2026 15:18, IQ-00594): bounded adapter overwrite window')
on conflict do nothing;

-- 1. the overwrite: set-based block check and the run's window
select pg_temp.cf_edit_def('security.adapter_overwrite_v1(integer)'::regprocedure, 'c800a74c92beed1e445d1fe47b553987',
  array[$o$       and not security.layer4_entity_or_parent_blocked('course', pg.course_id, 'operational')
  loop$o$],
  array[$n$       -- s773 (IQ-00594): the same Layer 4 rule as security.layer4_entity_or_parent_blocked, as one anti-join (an operational block on the course or its provider)
       and not exists (select 1 from security.layer4_active_blocks b where b.block_scope = 'operational'
                         and ((b.entity_type = 'course' and b.entity_id = pg.course_id) or (b.entity_type = 'provider' and b.entity_id = co.provider_id)))
       -- s773: the run's window of course ids, set by security.adapter_overwrite_gated_v1; none set reads every page, as before
       and (nullif(current_setting('cf247.ao_hi', true), '') is null
            or (pg.course_id > coalesce(nullif(current_setting('cf247.ao_lo', true), '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
                and pg.course_id <= current_setting('cf247.ao_hi', true)::uuid))
  loop$n$]);

-- 2. the gated job: one window a run, a cursor across runs
do $$
begin
  if md5(replace(pg_get_functiondef('security.adapter_overwrite_gated_v1(integer)'::regprocedure), chr(13), '')) <> 'ef72b3865d2a75bb7146321e1d2ef1ac' then
    raise exception 'pre-check: security.adapter_overwrite_gated_v1 changed since it was read (19 Nov 2026 15:25)';
  end if;
end $$;

create or replace function security.adapter_overwrite_gated_v1(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare m pipeline.job_input_marks%rowtype; v_in timestamptz := security.admit_input_mark_v1(); v jsonb; v_more boolean;
        v_full int := security.pipeline_num_v1('waste.admit_full_check_hours', 6)::int;
        -- s773 (IQ-00594): one window of pages a run, resumed from the cursor
        v_win int := greatest(100, security.pipeline_num_v1('batch.adapter_overwrite_window', 1000)::int);
        v_lo uuid; v_hi uuid; v_n int; v_last boolean; v_hit boolean; v_cur uuid; v_pass_in timestamptz;
begin
  insert into pipeline.job_input_marks(job_key) values ('adapter-overwrite') on conflict do nothing;
  select * into m from pipeline.job_input_marks where job_key = 'adapter-overwrite' for update;
  v_lo := nullif(m.last_result->>'cursor', '')::uuid;
  -- between passes only: skipped while nothing it depends on changed (as before)
  if v_lo is null and not coalesce((m.last_result->>'more')::boolean, true) and m.last_input_at is not null and v_in <= m.last_input_at
     and m.last_full_at > now() - make_interval(hours => v_full) then
    update pipeline.job_input_marks set runs_skipped = runs_skipped + 1, last_run_at = now() where job_key = 'adapter-overwrite';
    return jsonb_build_object('skipped', 'no new input');
  end if;
  -- the newest input when this pass started: input that arrives during the pass starts another pass
  v_pass_in := case when v_lo is null then v_in else coalesce(nullif(m.last_result->>'pass_input_at', '')::timestamptz, v_in) end;
  select count(*), max(w.course_id) into v_n, v_hi
    from (select pg.course_id from pipeline.coverage_course_pages pg
           where pg.read_status = 'read' and pg.identity_basis is not null and (v_lo is null or pg.course_id > v_lo)
             and (pg.candidates->>'intakes_by' = 'adapter' or pg.candidates->>'english_by' = 'adapter' or pg.candidates->>'fee_by' = 'adapter' or pg.candidates->'adapter_extra' ? 'mode' or pg.candidates->'adapter_extra' ? 'campus' or pg.candidates->'adapter_extra' ? 'location')
           order by pg.course_id limit v_win) w;
  v_last := v_n < v_win;
  perform set_config('cf247.ao_lo', coalesce(v_lo::text, ''), true);
  perform set_config('cf247.ao_hi', case when v_last then 'ffffffff-ffff-ffff-ffff-ffffffffffff' else v_hi::text end, true);  -- fixed: the top of the id range ends a pass
  perform security.fee_crosscheck_guard_v1();  -- CF-247 15 Oct: a fee far from the registered course total is held back first
  v := security.adapter_overwrite_v1(p_limit);
  perform set_config('cf247.ao_lo', '', true);
  perform set_config('cf247.ao_hi', '', true);
  v_hit := coalesce((v->>'replaced')::int, 0) >= p_limit;
  -- a window that reached the limit is read again; otherwise the cursor moves on, and after the last window the pass is complete
  v_cur := case when v_hit then v_lo when v_last then null else v_hi end;
  v_more := v_hit or not v_last;
  update pipeline.job_input_marks
     set last_input_at = case when v_last and not v_hit then v_pass_in else last_input_at end,
         last_full_at = case when v_last and not v_hit then now() else last_full_at end,
         last_run_at = now(),
         last_result = v || jsonb_build_object('more', v_more, 'cursor', v_cur, 'pass_input_at', v_pass_in,
                                               'window', jsonb_build_object('after', v_lo, 'pages', v_n, 'last', v_last)),
         runs_done = runs_done + 1
   where job_key = 'adapter-overwrite';
  return v || jsonb_build_object('window_pages', v_n, 'pass_complete', v_last and not v_hit);
end $function$;

-- post-checks
do $$
declare v_t timestamptz; v_ms numeric; v jsonb; v_hi uuid; v_n int; v_a int; v_b int;
begin
  if position('security.layer4_entity_or_parent_blocked' in (select prosrc from pg_proc where oid = 'security.adapter_overwrite_v1(integer)'::regprocedure)) > 0
     or position('cf247.ao_hi' in (select prosrc from pg_proc where oid = 'security.adapter_overwrite_v1(integer)'::regprocedure)) = 0 then
    raise exception 'post-check: the adapter overwrite does not read a window with the set-based block check';
  end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'batch.adapter_overwrite_window') is null then
    raise exception 'post-check: setting batch.adapter_overwrite_window is missing';
  end if;
  -- the first window, as a run reads it
  select max(w.course_id), count(*) into v_hi, v_n from (select pg.course_id from pipeline.coverage_course_pages pg
     where pg.read_status = 'read' and pg.identity_basis is not null
       and (pg.candidates->>'intakes_by' = 'adapter' or pg.candidates->>'english_by' = 'adapter' or pg.candidates->>'fee_by' = 'adapter' or pg.candidates->'adapter_extra' ? 'mode' or pg.candidates->'adapter_extra' ? 'campus' or pg.candidates->'adapter_extra' ? 'location')
     order by pg.course_id limit 1000) w;  -- fixed: post-check sample
  -- the set-based block check agrees with the function on every page of that window
  select count(*) filter (where security.layer4_entity_or_parent_blocked('course', pg.course_id, 'operational')),
         count(*) filter (where exists (select 1 from security.layer4_active_blocks b where b.block_scope = 'operational'
                         and ((b.entity_type = 'course' and b.entity_id = pg.course_id) or (b.entity_type = 'provider' and b.entity_id = co.provider_id))))
    into v_a, v_b
    from pipeline.coverage_course_pages pg join catalogue.courses co on co.id = pg.course_id where pg.course_id <= v_hi and pg.read_status = 'read';
  if v_a <> v_b then raise exception 'post-check: the set-based block check differs from the function (% against %)', v_b, v_a; end if;
  perform set_config('cf247.ao_lo', '', true);
  perform set_config('cf247.ao_hi', v_hi::text, true);
  v_t := clock_timestamp();
  v := security.adapter_overwrite_v1(200);
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  perform set_config('cf247.ao_hi', '', true);
  perform set_config('cf.diag', coalesce(current_setting('cf.diag', true), '') || format('s773 window=%s pages ms=%s result=%s blocked=%s; ', v_n, round(v_ms), v, v_a), true);
  if v_ms > 30000 then raise exception 'post-check: one adapter overwrite window took % ms', round(v_ms); end if;  -- fixed: post-check bound
end $$;
