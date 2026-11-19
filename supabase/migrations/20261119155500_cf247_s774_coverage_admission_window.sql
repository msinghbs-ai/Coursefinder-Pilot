-- CF-247 s774: admission runner C no longer times out in the coverage admission (IQ-00588; Platform Admin 19 Nov 2026 15:18 AEDT, chat S1-Build).
-- Measured in rolled-back live dry runs (GitHub Actions, 19 Nov 2026 15:20-15:35 AEDT):
--   * admission-rule-runner-c failed at 13:15 and 14:43 on the 120 s statement limit inside zoho_course_search_v2 (the consumer API evidence
--     snapshot) and at 13:17 inside security.coverage_admission_plan_v1; coverage-admit took up to 118 s (median 82 s on lane c).
--   * The plan reads every read page of the extractor on every run that is not skipped: 24,966 pages, 43,316 rows, 53 s, of which 601 rows
--     needed action and 42 were writes. Each page calls security.layer4_entity_or_parent_blocked (0.8 ms) against a view with 0 rows.
--   * security.consumer_api_snapshot_v1 (6.5 s; its Zoho searches cannot be stopped once started) ran before every batch with any row,
--     including batches that then changed nothing.
-- What changes (md5-guarded edits of existing functions; no table, column or job; the frozen consumer API is only read, never changed):
--   1. security.coverage_admission_plan_v1: the Layer 4 block check is one anti-join (the same rule: an operational block on the course or its
--      provider), and the plan reads only the window of course ids the gated job sets (transaction-local cf247.adm_lo / cf247.adm_hi). Without
--      them (security.platform_health_check_v1, any other caller) it plans every page, as before.
--   2. security.coverage_admission_apply_v1: the before snapshot (Decision 163 evidence) is taken just before the batch's first change, so a
--      batch that changes nothing no longer reads the consumer API. The after snapshot is unchanged (only when courses changed).
--   3. security.coverage_admission_gated_v1: each run plans the next admit.window_pages pages (new setting, default 1,500) by course id after
--      the cursor kept in pipeline.job_input_marks.last_result; a full pass of about 25,000 pages takes about 17 runs (10 minutes apart). A window
--      that reached p_limit writes or the refusal limit is planned again before the cursor moves on. Between passes the job is skipped as before
--      until new input arrives; input that arrived during a pass starts another pass.
-- Replaces: the whole-table admission plan on every run, the per-page Layer 4 block function call, the snapshot of batches that change nothing.
-- Retires: nothing.
-- G1: no job added or changed. G2: one new setting (admit.window_pages, on Settings › Pipeline settings). G3: untouched.

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
  ('pipeline', 'admit.window_pages', 'Coverage admission: pages planned per run',
   'Each run of coverage-admit and coverage-admit-intakes plans this many read course pages, in course order from where its last run stopped, so one run stays well inside the statement limit. A full pass of every page takes several runs.',
   'number', to_jsonb(1500), 100, 30000, 'pages', 643, 'Admission checks', 'security.coverage_admission_gated_v1',
   'CF-247 s774 (Platform Admin 19 Nov 2026 15:18, IQ-00588): bounded coverage admission window')
on conflict do nothing;

-- 1. the plan: set-based block check and the run's window
select pg_temp.cf_edit_def('security.coverage_admission_plan_v1(text)'::regprocedure, 'f9dceaf2ff05e2b410d06ed968cfcac0',
  array[$o$       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')
$o$],
  array[$n$       -- s774 (IQ-00588): the same Layer 4 rule as security.layer4_entity_or_parent_blocked, as one anti-join (an operational block on the course or its provider)
       and not exists (select 1 from security.layer4_active_blocks b where b.block_scope='operational'
                         and ((b.entity_type='course' and b.entity_id=p.course_id) or (b.entity_type='provider' and b.entity_id=co.provider_id)))
       -- s774: the run's window of course ids, set by security.coverage_admission_gated_v1; none set plans every page, as before
       and (nullif(current_setting('cf247.adm_hi', true), '') is null
            or (p.course_id > coalesce(nullif(current_setting('cf247.adm_lo', true), '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
                and p.course_id <= current_setting('cf247.adm_hi', true)::uuid))
$n$]);

-- 2. the apply: the before snapshot only for a batch that changes something
select pg_temp.cf_edit_def('security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure, '82110032efa36af06d6117bde03e50d6',
  array[$o$  v_before:=security.consumer_api_snapshot_v1();
$o$,
$o$    begin
      if r.provider_cricos is null or r.course_cricos is null then
$o$,
$o$      if v_rule like 'take:%' then
        perform security.layer4_course_link_apply_impl($o$],
  array[$n$  -- s774 (IQ-00588): the before snapshot is taken just before the batch's first change (below), not for a batch that changes nothing
$n$,
$n$    begin
      if v_before is null then v_before:=security.consumer_api_snapshot_v1(); end if;  -- s774: the state before this batch's first change
      if r.provider_cricos is null or r.course_cricos is null then
$n$,
$n$      if v_rule like 'take:%' then
        if v_before is null then v_before:=security.consumer_api_snapshot_v1(); end if;  -- s774: the state before this batch's first change
        perform security.layer4_course_link_apply_impl($n$]);

-- 3. the gated job: one window a run, a cursor across runs
do $$
begin
  if md5(replace(pg_get_functiondef('security.coverage_admission_gated_v1(text,integer,text,text[])'::regprocedure), chr(13), '')) <> 'adc4cf19720f361fbce223eb64297ba0' then
    raise exception 'pre-check: security.coverage_admission_gated_v1 changed since it was read (19 Nov 2026 15:25)';
  end if;
end $$;

create or replace function security.coverage_admission_gated_v1(p_key text, p_limit integer, p_extractor text, p_attributes text[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare m pipeline.job_input_marks%rowtype; v_in timestamptz := security.admit_input_mark_v1(); v jsonb; v_more boolean;
        v_full int := security.pipeline_num_v1('waste.admit_full_check_hours', 6)::int;
        -- s774 (IQ-00588): one window of pages a run, resumed from the cursor
        v_win int := greatest(100, security.pipeline_num_v1('admit.window_pages', 1500)::int);
        v_lo uuid; v_hi uuid; v_n int; v_last boolean; v_hit boolean; v_cur uuid; v_pass_in timestamptz;
begin
  insert into pipeline.job_input_marks(job_key) values (p_key) on conflict do nothing;
  select * into m from pipeline.job_input_marks where job_key = p_key for update;
  v_lo := nullif(m.last_result->>'cursor', '')::uuid;
  -- between passes only: skipped while nothing it depends on changed (as before)
  if v_lo is null and not coalesce((m.last_result->>'more')::boolean, true) and m.last_input_at is not null and v_in <= m.last_input_at
     and m.last_full_at > now() - make_interval(hours => v_full) then
    update pipeline.job_input_marks set runs_skipped = runs_skipped + 1, last_run_at = now() where job_key = p_key;
    return jsonb_build_object('skipped', 'no new input');
  end if;
  -- the newest input when this pass started: input that arrives during the pass starts another pass
  v_pass_in := case when v_lo is null then v_in else coalesce(nullif(m.last_result->>'pass_input_at', '')::timestamptz, v_in) end;
  select count(*), (array_agg(w.course_id order by w.course_id desc))[1] into v_n, v_hi
    from (select p.course_id from pipeline.coverage_course_pages p
           where p.read_status = 'read' and p.candidates->>'extractor' = p_extractor and (v_lo is null or p.course_id > v_lo)
           order by p.course_id limit v_win) w;
  v_last := v_n < v_win;
  perform set_config('cf247.adm_lo', coalesce(v_lo::text, ''), true);
  perform set_config('cf247.adm_hi', case when v_last then 'ffffffff-ffff-ffff-ffff-ffffffffffff' else v_hi::text end, true);  -- fixed: the top of the id range ends a pass
  v := security.coverage_admission_apply_v1(p_limit, p_extractor, p_attributes);
  perform set_config('cf247.adm_lo', '', true);
  perform set_config('cf247.adm_hi', '', true);
  v_hit := coalesce((v->>'written')::int, 0) >= p_limit or coalesce((v->>'stopped_at_limit')::boolean, false);  -- IQ-00067: stopped at the refusal limit
  -- a window that reached a limit is planned again; otherwise the cursor moves on, and after the last window the pass is complete
  v_cur := case when v_hit then v_lo when v_last then null else v_hi end;
  v_more := v_hit or not v_last;
  update pipeline.job_input_marks
     set last_input_at = case when v_last and not v_hit then v_pass_in else last_input_at end,
         last_full_at = case when v_last and not v_hit then now() else last_full_at end,
         last_run_at = now(),
         last_result = v || jsonb_build_object('more', v_more, 'cursor', v_cur, 'pass_input_at', v_pass_in,
                                               'window', jsonb_build_object('after', v_lo, 'pages', v_n, 'last', v_last)),
         runs_done = runs_done + 1
   where job_key = p_key;
  return v || jsonb_build_object('window_pages', v_n, 'pass_complete', v_last and not v_hit);
end $function$;

-- post-checks
do $$
declare v_t timestamptz; v_ms numeric; v_ms2 numeric; v_hi uuid; v_n int; v_rows int; v_act int; v_a int; v_b int; v jsonb;
        v_src text := (select prosrc from pg_proc where oid = 'security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure);
begin
  if position('not security.layer4_entity_or_parent_blocked(' in (select prosrc from pg_proc where oid = 'security.coverage_admission_plan_v1(text)'::regprocedure)) > 0
     or position('cf247.adm_hi' in (select prosrc from pg_proc where oid = 'security.coverage_admission_plan_v1(text)'::regprocedure)) = 0 then
    raise exception 'post-check: the admission plan does not read a window with the set-based block check';
  end if;
  if position('  v_before:=security.consumer_api_snapshot_v1();' in v_src) > 0
     or (length(v_src) - length(replace(v_src, 'if v_before is null then v_before:=security.consumer_api_snapshot_v1(); end if;', ''))) / length('if v_before is null then v_before:=security.consumer_api_snapshot_v1(); end if;') <> 2 then
    raise exception 'post-check: the before snapshot is not taken lazily before each kind of change';
  end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'admit.window_pages') is null then
    raise exception 'post-check: setting admit.window_pages is missing';
  end if;
  -- the first window, as a run plans it
  select (array_agg(w.course_id order by w.course_id desc))[1], count(*) into v_hi, v_n from (select p.course_id from pipeline.coverage_course_pages p
     where p.read_status = 'read' and p.candidates->>'extractor' = 'coverage-sweep-v0.5.6' order by p.course_id limit 1500) w;  -- fixed: post-check sample
  select count(*) filter (where security.layer4_entity_or_parent_blocked('course', p.course_id, 'operational')),
         count(*) filter (where exists (select 1 from security.layer4_active_blocks b where b.block_scope = 'operational'
                         and ((b.entity_type = 'course' and b.entity_id = p.course_id) or (b.entity_type = 'provider' and b.entity_id = co.provider_id))))
    into v_a, v_b
    from pipeline.coverage_course_pages p join catalogue.courses co on co.id = p.course_id where p.course_id <= v_hi and p.read_status = 'read';
  if v_a <> v_b then raise exception 'post-check: the set-based block check differs from the function (% against %)', v_b, v_a; end if;
  perform set_config('cf247.adm_lo', '', true);
  perform set_config('cf247.adm_hi', v_hi::text, true);
  v_t := clock_timestamp();
  select count(*), count(*) filter (where action in ('write', 'differs')) into v_rows, v_act from security.coverage_admission_plan_v1('coverage-sweep-v0.5.6');
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp();
  v := security.coverage_admission_apply_v1(500, 'coverage-sweep-v0.5.6', array['official_url', 'english']);
  v_ms2 := extract(epoch from clock_timestamp() - v_t) * 1000;
  perform set_config('cf247.adm_hi', '', true);
  perform set_config('cf.diag', coalesce(current_setting('cf.diag', true), '') || format('s774 window=%s pages plan_rows=%s actionable=%s plan_ms=%s apply_ms=%s result=%s blocked=%s; ', v_n, v_rows, v_act, round(v_ms), round(v_ms2), v - 'last_error', v_a), true);
  if v_ms > 30000 then raise exception 'post-check: one admission plan window took % ms', round(v_ms); end if;  -- fixed: post-check bound
end $$;
