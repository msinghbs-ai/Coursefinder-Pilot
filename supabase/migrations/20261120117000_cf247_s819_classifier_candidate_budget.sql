-- CF-247 s819 (Platform Admin 20 Nov 2026 09:55 AEDT, chat S1-Build): the scholarship classifier runs in under 10 s. s815 stopped its time-outs
-- (09:29, 10:29 and 11:29 AEDT ran 120 s and were cancelled); the first run on the new code, 12:29 AEDT, succeeded in 17.5 s. Timed again in a
-- rolled-back run at 12:40 AEDT: 12.6 s for one batch at sch_cov.classify_candidate_budget 1,500 (security.scholarship_coverage_items_v1 11.0 s),
-- about 8 ms a candidate on the live database (3 to 5 ms when quiet).
-- Change: the setting only, 1,500 → 700 candidate pages a run (about 6 to 8 s at 8 to 12 ms a candidate). Each run still takes at least one
-- university; the hourly run takes fewer universities, so a full pass of every university takes about twice as many runs.
-- Parity before writing (read live 20 Nov 2026 12:33 AEDT): head 20261120121100, 2,215 rows; main at #1416. Number inside the S1-Build range
-- (20261120111000 to 20261120119000, Platform Admin plan 20 Nov 10:48).
-- G3: no consumer object changes. G2: the value stays a setting (Settings › Pipeline settings › Job sizes) with its reason. No spend.
-- Replaces: the candidate budget of 1,500 set by s815.
-- Retires: nothing.

update pipeline.platform_toolset_settings set value = to_jsonb(700), updated_at = now(),
       help = 'The classifier takes providers in its usual order until their scholarship page candidates reach this many (always at least one provider); about 5 to 12 ms a candidate on the live database.',
       reason = 'CF-247 s819 (Platform Admin 20 Nov 2026 09:55, S1-Build): the run at 1,500 took 12.6 to 17.5 s; the target is under 10 s; was 1500'
 where toolset_key = 'pipeline' and key = 'sch_cov.classify_candidate_budget';

-- post-check: the setting reads 700, and one classifier batch is timed (rolled back) and reported
do $$
declare v_o text; t0 timestamptz; v_r jsonb; v_ms int;
begin
  if security.pipeline_num_v1('sch_cov.classify_candidate_budget', 0) <> 700 then
    raise exception 'post-check: sch_cov.classify_candidate_budget does not read 700';
  end if;
  t0 := clock_timestamp();
  begin
    v_r := security.scholarship_coverage_classify_v1();
    v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    raise exception 'cf-s819-undo';
  exception when others then
    if sqlerrm <> 'cf-s819-undo' then raise exception 'post-check: the classifier failed: %', sqlerrm; end if;
  end;
  v_o := 'classifier batch ' || v_ms || ' ms, ' || coalesce(v_r->>'providers', '?') || ' providers, ' || coalesce(v_r->>'cases', '?') || ' cases (rolled back)';
  perform set_config('cf.diag', v_o, true);
end $$;
