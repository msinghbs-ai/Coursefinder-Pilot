-- CF-247 s1352 (S1-Build; SS-Programme-Control 28 Nov 2026 14:18 PC-20261128-AER-ROOT-CAUSE, P0 incident): cron run 2310728 (14:13 to 14:15) failed on
-- statement timeout inside security.aer_e13_recover_v1 (its FOR SELECT), called by security.aer_technical_recovery_v1 inside
-- security.aer_schedule_tick_v1; a statement timeout is not caught by "when others", so the whole AER cycle rolled back (no cycle 637).
-- Cause: the candidate query evaluated security.aer_recovery_rule_v1 (an expensive per-item eligibility check) for every pending item of all 161
-- pilot universities before the per-run bound applied.
-- Fix (same rules, bounded work): the query keeps only the cheap filters; the eligibility rule and the per-university limit are applied in the loop,
-- one candidate at a time in the same order, and the loop stops at the run's room, at batch.aer_e13_scan_max candidates examined, or after
-- aer.e13_time_budget_seconds, whichever comes first. So recovery can never use the cycle's whole statement time again. Nothing else changes:
-- the switch aer.e13_recover_on, the daily and pilot totals, the gate re-check, the correction path and every admission gate are as they were.
-- Edited from the live definition (md5 dc10a3a8 read 28 Nov 2026 14:25), each edit checked to apply exactly once.
-- G1: no job. G2: both new bounds are settings. G3: not the consumer API. Nothing dropped or deleted.
-- Replaces: the unbounded candidate query of security.aer_e13_recover_v1.
-- Retires: nothing.
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'aer.e13_time_budget_seconds', 'AER technical recovery (E13): time per run',
   'E13 stops looking for candidates after this many seconds in a run, so the AER cycle that calls it always finishes.',
   'number', to_jsonb(20), 1, 120, 'seconds', 1600, 'AER', 'security.aer_e13_recover_v1', 'CF-247 s1352 (PC-20261128-AER-ROOT-CAUSE)'),
  ('pipeline', 'batch.aer_e13_scan_max', 'AER technical recovery (E13): candidates examined per run',
   'E13 examines at most this many candidates in a run (each checked against the recovery rule one at a time).',
   'number', to_jsonb(200), 10, 5000, 'items', 1601, 'AER', 'security.aer_e13_recover_v1', 'CF-247 s1352')
on conflict do nothing;

do $e$
declare d text := pg_get_functiondef('security.aer_e13_recover_v1(boolean)'::regprocedure); n text;
  e1_old text := 'v_asked jsonb := ''[]''::jsonb; v_skip jsonb := ''[]''::jsonb; v_cand int := 0;';
  e1_new text := 'v_asked jsonb := ''[]''::jsonb; v_skip jsonb := ''[]''::jsonb; v_cand int := 0;
        -- s1352: bounded work per run (the cycle that calls this must always finish)
        v_t0 timestamptz := clock_timestamp(); v_budget interval := make_interval(secs => security.pipeline_num_v1(''aer.e13_time_budget_seconds'', 20));
        v_scan int := security.pipeline_num_v1(''batch.aer_e13_scan_max'', 200)::int; v_seen jsonb := ''{}''::jsonb; v_bounded text;';
  e2_old text := '         and coalesce((security.aer_recovery_rule_v1(i.id)->>''eligible'')::boolean, false)
';
  e3_old text := 'select * from k where k.turn <= v_per order by k.turn, k.tries, k.created_at, k.id';
  e3_new text := 'select * from k order by k.turn, k.tries, k.created_at, k.id';
  e4_old text := '    v_cand := v_cand + 1;
';
  e4_new text := '    -- s1352: the per-run bounds, then the per-university limit and the recovery rule, one candidate at a time (same order as before)
    if v_cand >= v_scan then v_bounded := ''scan limit (batch.aer_e13_scan_max)''; exit; end if;
    if clock_timestamp() - v_t0 > v_budget then v_bounded := ''time budget (aer.e13_time_budget_seconds)''; exit; end if;
    v_cand := v_cand + 1;
    continue when coalesce((v_seen->>r.provider_id::text)::int, 0) >= v_per;
    continue when not coalesce((security.aer_recovery_rule_v1(r.id)->>''eligible'')::boolean, false);
    v_seen := jsonb_set(v_seen, array[r.provider_id::text], to_jsonb(coalesce((v_seen->>r.provider_id::text)::int, 0) + 1));
';
begin
  if md5(d) <> 'dc10a3a8c91f94e9654399a42f1f447e' then raise exception 'pre-check: security.aer_e13_recover_v1 changed since it was read (md5 dc10a3a8)'; end if;
  if (length(d) - length(replace(d, e1_old, ''))) / length(e1_old) <> 1 then raise exception 'pre-check: declaration marker not found once'; end if;
  if (length(d) - length(replace(d, e2_old, ''))) / length(e2_old) <> 1 then raise exception 'pre-check: eligibility line not found once'; end if;
  if (length(d) - length(replace(d, e3_old, ''))) / length(e3_old) <> 1 then raise exception 'pre-check: final select not found once'; end if;
  if (length(d) - length(replace(d, e4_old, ''))) / length(e4_old) <> 1 then raise exception 'pre-check: loop counter not found once'; end if;
  n := replace(replace(replace(replace(d, e1_old, e1_new), e2_old, ''), e3_old, e3_new), e4_old, e4_new);
  execute n;
end $e$;
comment on function security.aer_e13_recover_v1(boolean) is 'CF-247 AER technical recovery (E13), bounded per run since s1352: the cheap candidate query, then the per-university limit and the recovery rule one candidate at a time; stops at the room, batch.aer_e13_scan_max or aer.e13_time_budget_seconds.';

do $e$
declare d text := pg_get_functiondef('security.aer_e13_recover_v1(boolean)'::regprocedure);
begin
  if position('security.aer_recovery_rule_v1(i.id)' in d) > 0 then raise exception 'post-check: the rule is still evaluated inside the candidate query'; end if;
  if position('continue when not coalesce((security.aer_recovery_rule_v1(r.id)' in d) = 0 then raise exception 'post-check: the rule is not applied in the loop'; end if;
  if position('aer.e13_time_budget_seconds' in d) = 0 then raise exception 'post-check: no time budget'; end if;
end $e$;
