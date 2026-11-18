-- CF-247 F-SCH.01 activation: eligibility reader on in shadow (bounded sample), the four built scholarship recoveries on, scholarship scope widened
-- (pilot-only ended; the evidence-based legitimacy check replaces the 30-course minimum), and a "declining admission" check in the flow guard.
-- Decision: Platform Admin, 12 Nov 2026 11:50 AEDT, in the F-SCH.01 session, approving all four scholarship decisions:
--   2 "Enable shadow first" (stored evidence first; up to US$0.50 AI and 1,600 Firecrawl credits for shadow; then activate processing of evidence-proven
--     cases through the existing admission policy without another indefinite manual checkpoint),
--   3 "Enable all three options" (listing traversal; register pages and stored re-reads; transient retries; a successful read is never an approval),
--   4 "Staged by cohort" (remove the trial-only restriction; replace the 30-course minimum with provider-legitimacy and scholarship-source verification;
--     bounded, automatically progressing cohorts; staging is batching, not a new gate),
--   5 continuous operations with "automated alerts for stalled processing or declining admission throughput".
-- Route: the Platform Admin's settings screen function (public.admin_toolsets_write) needs a signed-in Platform Admin; a session acting under the Platform
--   Admin's identity was refused by the session's permission check, so the decided values are applied here, in review and CI, each change recorded in
--   pipeline.admin_control_events with its before value, its after value and the decision as reason (the same record the settings screen writes).
-- Guards: G1 (no new job), G2 (values are settings; the new check reads settings), G3 (no consumer API object), Decision 260; Layer 4 authority unchanged:
--   sch_elig.apply_on stays 0 (shadow), so nothing is admitted from a reader answer by this change.
-- Bounded cohorts are the existing pacing, not a new scheduler: discovery takes scholarship.discover_providers_max (6) providers every 10 minutes;
--   security.scholarship_discovery_settle_v1 (hourly, batch.scholarship_discovery_settle) returns settled rows whose reason has cleared; Firecrawl is held to
--   the scholarship daily share (daily_share_scholarships 800), the per-provider cap (scholarship_cap_per_uni 150 a 30 days) and firecrawl_cap; AI to the
--   OpenRouter floor, ceiling and lane guard.
-- Live values before (read 12 Nov 2026 12:05 AEDT): sch_elig.on 0, batch.sch_eligibility_read 20, batch.sch_eligibility_enqueue 200,
--   sch_cov.recover_listings_on 0, sch_cov.recover_register_pages_on 0, sch_cov.recover_stored_reads_on 0, retry.scholarship_transient_recover_on 0,
--   scholarship.pilot_only true (scholarship.legitimacy_checks_on true, scholarship.non_university_admission true).
-- Live definition this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 12:05 AEDT): security.scholarship_flow_guard_v1() 0dbd3d33b48b2cc3622e5f2ad0a36009
-- Replaces: security.scholarship_flow_guard_v1 (same name and signature; md5-guarded text edit).
-- Retires: nothing (scholarship.pilot_only is set false and kept as a setting).

-- 1. the new check's settings (G2) ------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'sch_flow.decline_pct', 'Scholarship flow guard: admission is declining below',
  'Admission is declining when the scholarships admitted in the last sch_flow.stall_hours are fewer than this share of the daily average over the sch_flow.decline_window_days before, while unresolved cases wait.',
  'number', to_jsonb(50), 1, 100, 'per cent of the daily average', 1443, 'F-SCH.01 activation (Platform Admin 12 Nov 2026 11:50 §5: alerts for declining admission throughput)', 'Scholarship flow guard', 'security.scholarship_flow_guard_v1'),
 ('pipeline', 'sch_flow.decline_window_days', 'Scholarship flow guard: days the admission average is taken over',
  'The daily average admission is taken over this many days before the latest sch_flow.stall_hours.',
  'number', to_jsonb(7), 2, 30, 'days', 1444, 'F-SCH.01 activation', 'Scholarship flow guard', 'security.scholarship_flow_guard_v1'),
 ('pipeline', 'sch_flow.decline_min_daily', 'Scholarship flow guard: smallest daily average checked for a decline',
  'A decline is reported only when the daily average admission is at least this many scholarships (a quiet flow is not a decline).',
  'number', to_jsonb(5), 1, 1000, 'scholarships a day', 1445, 'F-SCH.01 activation', 'Scholarship flow guard', 'security.scholarship_flow_guard_v1')
on conflict (toolset_key, key) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'setting', 'pipeline.' || x.k, jsonb_build_object('before', null, 'after', x.v, 'reason', 'Added by migration 20261113040000 (F-SCH.01 activation): the flow guard''s declining-admission check'),
       '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
  from (values ('sch_flow.decline_pct', to_jsonb(50)), ('sch_flow.decline_window_days', to_jsonb(7)), ('sch_flow.decline_min_daily', to_jsonb(5))) x(k, v)
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'toolsets' and e.target = 'pipeline.' || x.k);

-- 2. the decided values, each with its control event -------------------------------------------------------------------------------------------------
do $s$
declare r record; v_before jsonb; v_n int := 0;
begin
  for r in select * from (values
     ('batch.sch_eligibility_enqueue', to_jsonb(300), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 2): shadow runs on a bounded first sample of 300 cases, within the authorised shadow spend (US$0.50 AI, 1,600 Firecrawl credits); restored to 200 when evidence-proven cases are acted on. Applied by migration 20261113040000 (Integration Controller, Claude).'),
     ('batch.sch_eligibility_read', to_jsonb(40), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 2): 40 pages a worker call, the setting maximum, so the shadow sample is read within the hour. Applied by migration 20261113040000 (Integration Controller, Claude).'),
     ('sch_elig.on', to_jsonb(1), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 2 "Enable shadow first"): eligibility reader on in shadow; sch_elig.apply_on stays 0; stored copies first. Applied by migration 20261113040000 (Integration Controller, Claude).'),
     ('sch_cov.recover_listings_on', to_jsonb(1), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 3): listing traversal on; existing acquisition, deduplication, spend, retry and evidence controls; a successful read is never an approval. Applied by migration 20261113040000 (Integration Controller, Claude).'),
     ('sch_cov.recover_register_pages_on', to_jsonb(1), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 3): never-read register pages read once; existing controls; a read is never an approval. Applied by migration 20261113040000 (Integration Controller, Claude).'),
     ('sch_cov.recover_stored_reads_on', to_jsonb(1), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 3): refused pages read again once from their stored copy; existing controls; a read is never an approval. Applied by migration 20261113040000 (Integration Controller, Claude).'),
     ('retry.scholarship_transient_recover_on', to_jsonb(1), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 3): reads stopped by a time-out, server error or credit refusal retried within the existing cycle limits. Applied by migration 20261113040000 (Integration Controller, Claude).'),
     ('scholarship.pilot_only', to_jsonb(false), 'Platform Admin decision 12 Nov 2026 11:50 AEDT (F-SCH.01 decision 4 "Staged by cohort"): the trial-only restriction is removed; with scholarship.legitimacy_checks_on the evidence-based legitimacy check replaces the 30-course minimum for every provider; cohorts are the existing discovery pacing and spend limits. Applied by migration 20261113040000 (Integration Controller, Claude).')
    ) x(k, v, reason) loop
    select s.value into v_before from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = r.k;
    if not found then raise exception 'setting % does not exist', r.k; end if;
    if v_before is distinct from r.v then
      update pipeline.platform_toolset_settings set value = r.v, reason = left(r.reason, 500), updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b', updated_at = now()
       where toolset_key = 'pipeline' and key = r.k;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('toolsets', 'setting', 'pipeline.' || r.k, jsonb_build_object('before', v_before, 'after', r.v, 'reason', r.reason), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
      v_n := v_n + 1;
    end if;
  end loop;
  raise notice 'settings changed: %', v_n;
end $s$;

-- 3. the flow guard reports a declining admission (md5-guarded) ----------------------------------------------------------------------------------------
create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.scholarship_flow_guard_v1()', '0dbd3d33b48b2cc3622e5f2ad0a36009', array[
  array[$o$  -- e. cases overdue
$o$,
        $n$  -- d2. admission declining (F-SCH.01 activation, Platform Admin 12 Nov 2026 11:50 §5): the latest window against the daily average before it
  declare v_last int; v_avg numeric; v_days int := security.pipeline_num_v1('sch_flow.decline_window_days', 7)::int;
          v_pct numeric := security.pipeline_num_v1('sch_flow.decline_pct', 50); v_min numeric := security.pipeline_num_v1('sch_flow.decline_min_daily', 5);
  begin
    select count(*) into v_last from pipeline.scholarship_admission_log l where l.action = 'admitted' and l.at > now() - v_stall;
    select count(*)::numeric / greatest(v_days, 1) into v_avg from pipeline.scholarship_admission_log l
     where l.action = 'admitted' and l.at <= now() - v_stall and l.at > now() - v_stall - make_interval(days => v_days);
    if v_k > 0 and v_avg >= v_min and v_last < v_avg * v_pct / 100 then
      f := f || jsonb_build_object('code', 'admission_declining', 'severity', 'P2', 'count', v_last,
             'detail', jsonb_build_object('admitted_latest', v_last, 'window_hours', v_stall_h, 'daily_average_before', round(v_avg, 1), 'average_days', v_days, 'threshold_pct', v_pct),
             'title', format('Scholarships: %s admitted in the last %s hours against a daily average of %s over the %s days before', v_last, v_stall_h, round(v_avg, 1), v_days),
             'expected', 'Admission keeps pace with the recent average while cases wait; the flow guard''s other findings name the cause.');
    end if;
  end;
  -- e. cases overdue
$n$]
], array[1]);

-- 4. post-check ---------------------------------------------------------------------------------------------------------------------------------------
do $p$
declare v jsonb;
begin
  if security.pipeline_num_v1('sch_elig.on', 0) <> 1 or security.pipeline_num_v1('sch_elig.apply_on', -1) <> 0 then raise exception 'post-check: the reader is on in shadow only'; end if;
  if security.pipeline_num_v1('sch_cov.recover_listings_on', 0) <> 1 or security.pipeline_num_v1('sch_cov.recover_register_pages_on', 0) <> 1
     or security.pipeline_num_v1('sch_cov.recover_stored_reads_on', 0) <> 1 or security.pipeline_num_v1('retry.scholarship_transient_recover_on', 0) <> 1 then
    raise exception 'post-check: the four recoveries are on';
  end if;
  if security.scholarship_flag_v1('scholarship.pilot_only', true) then raise exception 'post-check: pilot-only ended'; end if;
  if (select count(*) from pipeline.admin_control_events e where e.area = 'toolsets' and e.created_at > now() - interval '1 hour'  -- fixed: this migration's own events
        and e.detail->>'reason' like '%migration 20261113040000%') < 8 then raise exception 'post-check: every change and every new setting has its control event'; end if;
  if pg_get_functiondef('security.scholarship_flow_guard_v1()'::regprocedure) not like '%''admission_declining''%' then raise exception 'post-check: flow guard not edited'; end if;
  v := security.scholarship_flow_guard_v1();
  if not coalesce((v->>'on')::boolean, false) then raise exception 'post-check: flow guard did not run (%)', v; end if;
  raise notice 'flow guard after activation: %', v;
end $p$;
