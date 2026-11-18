-- CF-247 F-AER.03 AER machine admission switched on after validation (Platform Admin 11 Nov 2026 14:39 AEDT "Go"; route chosen 15:22 "Option A": through this migration).
-- Guards: G1 (no job), G2 (values are settings, changed with a reason), G3 (no consumer API object changed), Decision 260,
--   "a passing qualification never switches anything on by itself": the switch is the Platform Admin's explicit decision, recorded here; the validation is the gate.
--   If the validation does not pass, aer.machine_mode stays 1 (shadow) and the failed validation is recorded.
-- Decisions: Platform Admin 10 Nov 2026 (AER recovery pack, decision 1: build, shadow, enable after independent validation); 11 Nov 2026 14:39 AEDT: enable now, at 14 shadow
--   hours instead of 24. Evidence at that time (production, read only and rolled-back runs): 716 shadow results, 0 of 297 current "would admit" reads fail when checked again,
--   0 human non-approvals of rule admissions, 0 of 302 disagreements with past human decisions; only the shadow time (14.2 of 24 h) was short.
-- What, in one transaction:
--   1. aer.machine_shadow_min_hours 24 -> 14 (with the decision as reason);
--   2. security.aer_machine_validate_v1() runs and records its result (pipeline.aer_machine_validations) and a control event;
--   3. only if it passed: aer.machine_mode 1 -> 2 (with the validation id as reason) and a control event.
-- Effect: job aer-machine-admission (24 and 54 past the hour) admits the reads rule aer-machine-v1 passes (about 297, within aer.machine_daily_max 300), audit sample
--   aer.machine_audit_pct to a person; every other read stays in Layer 4. Layer 4 entry items fall below aer.schedule_layer4_max, so new reads restart.
-- Replaces: nothing. Retires: nothing.
-- Reversal without code: aer.machine_mode 1 (shadow) or aer.machine_suspended 1 on Settings > Pipeline settings; admitted rows are withdrawn by the existing machine withdrawal.

set local statement_timeout = '300s'; -- fixed: the validation re-checks every waiting read (about 60 s); one run, inside the deploy's transaction

do $act$
declare v jsonb; vid bigint; t timestamptz := clock_timestamp();
begin
  if (select value #>> '{}' from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'aer.machine_mode') <> '1' then
    raise notice 'aer.machine_mode is not 1 (shadow): nothing done'; return;
  end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(14),
         reason = 'Platform Admin decision 11 Nov 2026 14:39 AEDT ("Go"): enable AER machine admission at 14 shadow hours instead of 24 (716 shadow results; 0 of 297 regressions on recheck; 0 of 302 history disagreements; every other validation rule met)',
         updated_at = now()
   where toolset_key = 'pipeline' and key = 'aer.machine_shadow_min_hours';
  v := security.aer_machine_validate_v1();
  select max(id) into vid from pipeline.aer_machine_validations;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('aer', 'machine_validate', 'aer.machine_mode', (v - 'history_disagreements') || jsonb_build_object('validation_id', vid, 'secs', round(extract(epoch from clock_timestamp() - t)::numeric, 1),
          'by', 'Integration Controller under Platform Admin decision 11 Nov 2026 14:39 (migration 20261112001700)'));
  if coalesce((v->>'passed')::boolean, false) then
    update pipeline.platform_toolset_settings set value = to_jsonb(2),
           reason = format('Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 1) and 11 Nov 2026 14:39 AEDT ("Go"); validation %s passed (shadow %s h, %s results, %s would admit, %s regressions, %s human non-approvals, history %s of %s disagreements)',
                           vid, v->>'shadow_hours', v->>'shadow_results', v->>'shadow_would_admit', v->>'regressions_on_recheck', v->>'human_non_approvals_of_rule_admits',
                           v->'history'->>'rule_would_admit_but_human_edited_or_refused', v->'history'->>'rule_would_admit'),
           updated_at = now()
     where toolset_key = 'pipeline' and key = 'aer.machine_mode';
    insert into pipeline.admin_control_events(area, action, target, detail)
    values ('aer', 'machine_mode_set', 'aer.machine_mode', jsonb_build_object('from', 1, 'to', 2, 'validation_id', vid, 'decision', 'Platform Admin 11 Nov 2026 14:39 Go', 'migration', '20261112001700'));
    raise notice 'validation % passed: aer.machine_mode set to 2', vid;
  else
    raise notice 'validation % did not pass: aer.machine_mode stays 1 (%)', vid, v - 'history_disagreements' - 'history';
  end if;
end $act$;
