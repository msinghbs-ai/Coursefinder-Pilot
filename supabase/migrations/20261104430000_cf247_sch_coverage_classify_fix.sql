-- CF-247 scholarship coverage classification fix (Integration Controller, 4 Nov 2026: v2.15.460 production defect). Lands after 20261104390000.
--
-- Why (live, read-only, 4 Nov 2026 07:11-07:20 AEDT): job scholarship-coverage-classify failed its first run (06:29 AEDT) with "ON CONFLICT DO UPDATE
--   command cannot affect row a second time"; pipeline.scholarship_coverage_items and pipeline.scholarship_coverage_providers are empty. The duplicate
--   key is a listing item: 19 item addresses appear more than once in the items of one listing page (40 rows; for example VU listing 4 lists the
--   STEM Accommodation and Block Model scholarships twice, SAE listing 5 lists its apply page four times, RMIT 13 and Lincoln 10 twice), so
--   security.scholarship_coverage_items_v1 returns the case "list:<listing>:<address>" more than once and the one insert meets the same
--   (provider_id, item_key) twice. No register, candidate, scholarship or provider key repeats (register entries checked: 0 duplicates).
-- What (md5-guarded edit of security.scholarship_coverage_classify_v1):
--   1 The insert takes one row per (provider_id, item_key) with a deterministic winner: the most pressing state (state_codes.sort), then the
--     smallest md5 of its evidence. The number of duplicate rows folded is returned (duplicate_cases), so a repeat is visible, not silent.
--   2 The report writes never abort the run (the SS-021 pattern): each security.work_item_report_v1 call runs in its own block; a failure is
--     counted (report_errors, report_error_last) and its signature is not recorded, so the same report is tried again on the next run. The
--     cases and provider states are kept either way.
-- Activation: unchanged (sch_cov.classify_on 1; records only). Nothing spends, admits, decides or publishes.
-- md5 (before = live, read 4 Nov 2026 07:11 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/sch-coverage-recovery/run.sh):
--   security.scholarship_coverage_classify_v1(uuid[])   a268ce816990d71ef545dbdc0ae28a5e -> c072494c5e0082e2a8b58a06dfd94a00
-- Read, not edited: security.scholarship_coverage_items_v1(uuid[]) d3dfacf0e70fd33162eab7a57aca72e4.
-- Replaces: security.scholarship_coverage_classify_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Consumer API: untouched (G3). Nothing is dropped or deleted.

do $guard$
begin
  if to_regclass('pipeline.scholarship_coverage_items') is null then raise exception 'this fix lands after 20261104390000 (scholarship coverage recovery)'; end if;
  if md5(pg_get_functiondef('security.scholarship_coverage_items_v1(uuid[])'::regprocedure)) <> 'd3dfacf0e70fd33162eab7a57aca72e4' then
    raise exception 'live security.scholarship_coverage_items_v1 differs from the definition this fix was written against';
  end if;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.scholarship_coverage_classify_v1(uuid[])', 'a268ce816990d71ef545dbdc0ae28a5e', 'c072494c5e0082e2a8b58a06dfd94a00', array[
  -- 1 counters
  array[$o$        r record; p record; v_sig text; v_rep jsonb; v_ev text; v_n int := 0; v_items int := 0; v_reports int := 0; v_ok int := 0; v_fail int := 0;$o$,
        $n$        r record; p record; v_sig text; v_rep jsonb; v_ev text; v_n int := 0; v_items int := 0; v_reports int := 0; v_ok int := 0; v_fail int := 0;
        v_dup int := 0; v_rerr int := 0; v_rlast text;$n$],
  -- 2 one row per conflict key, deterministic winner
  array[$o$  select n.provider_id, n.item_key, n.state, n.reason, n.evidence, case when$o$,
        $n$  -- CF-247 fix (4 Nov 2026): a listing can list the same address twice; one row per (provider_id, item_key), the most pressing state first
  select distinct on (n.provider_id, n.item_key) n.provider_id, n.item_key, n.state, n.reason, n.evidence, case when$n$],
  array[$o$    from sch_cov_now n join pipeline.scholarship_coverage_state_codes k on k.code = n.state
  on conflict$o$,
        $n$    from sch_cov_now n join pipeline.scholarship_coverage_state_codes k on k.code = n.state
   order by n.provider_id, n.item_key, k.sort, md5(n.evidence::text)
  on conflict$n$],
  array[$o$  get diagnostics v_items = row_count;$o$,
        $n$  get diagnostics v_items = row_count;
  v_dup := v_items - (select count(*) from (select distinct n.provider_id, n.item_key from sch_cov_now n) d);$n$],
  -- 3 the report writes never abort the run (SS-021)
  array[$o$      perform security.work_item_report_v1('sch_coverage', p.id::text, 'state:' || r.code, v_ev,$o$,
        $n$      begin
      perform security.work_item_report_v1('sch_coverage', p.id::text, 'state:' || r.code, v_ev,$n$],
  array[$o$                           'evidence', jsonb_build_object('cases', r.n, 'sample', to_jsonb(r.sample), 'escalation_due', r.due)));
      v_reports := v_reports + 1;$o$,
        $n$                           'evidence', jsonb_build_object('cases', r.n, 'sample', to_jsonb(r.sample), 'escalation_due', r.due)));
      v_reports := v_reports + 1;
      exception when others then
        -- not recorded as reported, so the next run tries again; the cases are kept
        v_rerr := v_rerr + 1; v_rlast := left(r.code || ': ' || sqlerrm, 300); v_rep := v_rep - r.code;
      end;$n$],
  array[$o$      perform security.work_item_report_v1('sch_coverage', p.id::text, 'state:' || r.code, 'succeeded', jsonb_build_object('provider_id', p.id, 'outcome', 'succeeded_with_result'));
      v_reports := v_reports + 1;$o$,
        $n$      begin
        perform security.work_item_report_v1('sch_coverage', p.id::text, 'state:' || r.code, 'succeeded', jsonb_build_object('provider_id', p.id, 'outcome', 'succeeded_with_result'));
        v_reports := v_reports + 1;
      exception when others then
        v_rerr := v_rerr + 1; v_rlast := left(r.code || ': ' || sqlerrm, 300); v_rep := v_rep || jsonb_build_object(r.code, p.reported->>r.code);
      end;$n$],
  array[$o$'work_reports', v_reports, 'recoveries_succeeded', v_ok, 'recoveries_failed', v_fail);$o$,
        $n$'work_reports', v_reports, 'recoveries_succeeded', v_ok, 'recoveries_failed', v_fail,
                            'duplicate_cases', v_dup, 'report_errors', v_rerr, 'report_error_last', v_rlast);$n$]
], array[1, 1, 1, 1, 1, 1, 1, 1]);

do $$
begin
  if md5(pg_get_functiondef('security.scholarship_coverage_classify_v1(uuid[])'::regprocedure)) <> 'c072494c5e0082e2a8b58a06dfd94a00' then
    raise exception 'post-check: scholarship_coverage_classify_v1';
  end if;
end $$;
