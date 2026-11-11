-- CF-247 F-AER.04 machine admission of country tables and qualification rows switched on after validation (Platform Admin decision D1, 11 Nov 2026, SS-017 / Operating
-- Model v1.12: "a narrowly defined, source-verified machine-admission class ... run through the existing framework with QA, CI, audited activation and actual canonical results").
-- Guards: G1 (no job), G2 (values are settings, changed with a reason), G3 (no consumer API object changed), Decision 260,
--   "a passing qualification never switches anything on by itself": the switch is the Platform Admin's decision D1, carried out here; the validation is the gate.
--   If the validation does not pass, aer.matrix_machine_mode stays 1 (shadow) and the failed validation is recorded.
-- Evidence (production, 11 Nov 2026 21:55 AEDT): rule aer-matrix-machine-v1 shipped in shadow (#1035, 20261112093700); the first validation did not pass on one history
--   disagreement (ANU a6e3bcb2: the row's quote did not carry its minimum); the quote proof (#1038, 20261112110700) was applied to the rule and to the validation's replay.
--   Live dry run after it (rolled back): history 34 human decisions, the rule would admit 25, all 25 approved by a person (0 disagreements); 20 shadow results, 8 would
--   admit, 0 regressions on re-check: passed. An uploaded copy is never admitted (uploaded_copy, #1038).
-- What, in one transaction: security.aer_matrix_machine_validate_v1() runs and records its result and a control event; only if it passed, aer.matrix_machine_mode 1 -> 2
--   (with the validation id as reason) and a control event.
-- Effect: job aer-machine-admission (24 and 54 past the hour) admits, through the person's apply as the system actor marked machine, the first reads rule
--   aer-matrix-machine-v1 passes (at most aer.matrix_machine_daily_max a day), audit sample aer.matrix_machine_audit_pct to a person; every other read stays in Layer 4.
-- Replaces: nothing.
-- Retires: nothing.
-- Reversal without code: aer.matrix_machine_mode 1 (shadow) on Settings > Pipeline settings; an admitted read is withdrawn by security.aer_matrix_machine_withdraw_v1.

set local statement_timeout = '300s'; -- fixed: one validation run inside the deploy's transaction

do $act$
declare v jsonb; vid bigint; t timestamptz := clock_timestamp();
begin
  if (select value #>> '{}' from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'aer.matrix_machine_mode') <> '1' then
    raise notice 'aer.matrix_machine_mode is not 1 (shadow): nothing done'; return;
  end if;
  if position('minimum_not_in_quote' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_matrix_machine_check_v1(uuid)'::regprocedure)) = 0 then
    raise exception 'the quote proof (20261112110700) is not live: not switched on'; end if;
  v := security.aer_matrix_machine_validate_v1();
  select max(id) into vid from pipeline.aer_matrix_machine_validations;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('aer', 'matrix_machine_validate', 'aer.matrix_machine_mode', v || jsonb_build_object('validation_id', vid, 'secs', round(extract(epoch from clock_timestamp() - t)::numeric, 1),
          'by', 'Integration Controller under Platform Admin decision D1, 11 Nov 2026 (migration 20261112143700)'));
  if coalesce((v->>'passed')::boolean, false) then
    update pipeline.platform_toolset_settings set value = to_jsonb(2),
           reason = format('Platform Admin decision D1, 11 Nov 2026 (SS-017): validation %s passed (%s shadow results, %s would admit, %s regressions; history %s of %s disagreements)',
                           vid, v->>'shadow_results', v->>'shadow_would_admit', v->>'regressions_on_recheck',
                           v->'history'->>'rule_would_admit_but_human_edited_or_refused', v->'history'->>'rule_would_admit'),
           updated_at = now()
     where toolset_key = 'pipeline' and key = 'aer.matrix_machine_mode';
    insert into pipeline.admin_control_events(area, action, target, detail)
    values ('aer', 'matrix_machine_mode_set', 'aer.matrix_machine_mode', jsonb_build_object('from', 1, 'to', 2, 'validation_id', vid, 'decision', 'Platform Admin D1 11 Nov 2026', 'migration', '20261112143700'));
    raise notice 'validation % passed: aer.matrix_machine_mode set to 2', vid;
  else
    raise notice 'validation % did not pass: aer.matrix_machine_mode stays 1 (%)', vid, v - 'history';
  end if;
end $act$;
