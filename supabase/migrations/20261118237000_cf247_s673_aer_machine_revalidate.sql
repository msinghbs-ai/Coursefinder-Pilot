-- CF-247 S673 AER course machine admission re-validated (session S1-AER, Platform Admin standing mandate of 18 Nov 2026 19:28 AEDT, step 1: "Re-Run the AER Course Machine
--   Validation ... keeping 0.8 confidence and 8-character quote thresholds unchanged; keep variant twins held per Decision 276").
-- Guards: G1 (no job), G2 (no value changed), G3 (no consumer API object; no function or table created: 75 functions and 48 relations stay), Decision 276 (AER v1 frozen:
--   no threshold, reader, word list or rule changes), "a passing qualification never switches anything on by itself": the Platform Admin's mandate is the decision, the
--   validation is the gate, and aer.machine_mode is already 2 from 11 Nov 2026 (migration 20261112001700) so nothing is switched here.
-- Why: security.aer_machine_run_v1 and security.aer_machine_admit_v1 admit only while a passing row in pipeline.aer_machine_validations is younger than 7 days. The only
--   passing row is 11 Nov 2026 15:40 AEDT, so admission has run as shadow since 18 Nov 15:40 AEDT (docs/CURRENT-STATE.md, S2-BOOST-AER 19:00 block).
-- Evidence before this file (rolled-back live dry run of security.aer_machine_validate_v1, 18 Nov 2026 19:31 AEDT, workflow run 44267763745): passed; 396 shadow would-admit
--   reads re-checked with 0 regressions; 0 human non-approvals of rule admissions; history 0 of 302 disagreements; 187.9 shadow hours; function md5 945077fe5dc291cc0893976f8fe65aef.
-- What, in one transaction:
--   1. the live definition of security.aer_machine_validate_v1 is checked against the md5 above (stop if it differs);
--   2. security.aer_machine_validate_v1() runs and records its result (pipeline.aer_machine_validations) and one control event;
--   3. nothing else: aer.machine_mode, aer.machine_min_confidence (0.8), aer.machine_min_quote_chars (8), the shared-page and twin holds are not touched.
-- Effect: job aer-machine-admission (24 and 54 past the hour) admits the waiting reads rule aer-machine-v1 passes, within aer.machine_daily_max, audit sample to a person.
-- Replaces: nothing. Retires: nothing.
-- Reversal without code: aer.machine_mode 1 (shadow) or aer.machine_suspended 1 on Settings > Pipeline settings; admitted rows are withdrawn by the existing machine withdrawal.

set local statement_timeout = '300s'; -- fixed: the validation re-checks every waiting read (about 60 s); one run, inside the deploy's transaction

do $act$
declare v jsonb; vid bigint; t timestamptz := clock_timestamp();
        v_md5 constant text := '945077fe5dc291cc0893976f8fe65aef';
begin
  if md5(pg_catalog.pg_get_functiondef('security.aer_machine_validate_v1()'::regprocedure)) <> v_md5 then
    raise exception 'S673: security.aer_machine_validate_v1 differs from the definition checked on 18 Nov 2026 (md5 %); nothing done', v_md5;
  end if;
  v := security.aer_machine_validate_v1();
  select max(id) into vid from pipeline.aer_machine_validations;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('aer', 'machine_validate', 'aer.machine_mode', (v - 'history_disagreements') || jsonb_build_object('validation_id', vid,
          'secs', round(extract(epoch from clock_timestamp() - t)::numeric, 1),
          'authority', 'Platform Admin standing mandate 18 Nov 2026 19:28 AEDT (S1-AER step 1)',
          'by', 'Integration Controller (migration 20261118237000)'));
  if coalesce((v->>'passed')::boolean, false) then
    raise notice 'S673: validation % passed; aer-machine-admission admits again while aer.machine_mode is 2', vid;
  else
    raise notice 'S673: validation % did not pass; admission stays shadow (%)', vid, v - 'history_disagreements' - 'history';
  end if;
end $act$;

do $p$
begin
  if not exists (select 1 from pipeline.aer_machine_validations where validated_at > now() - make_interval(mins => 10)) then -- fixed: this transaction's own row
    raise exception 'post-check: no validation recorded';
  end if;
  if security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8 or security.pipeline_num_v1('aer.machine_min_quote_chars', -1) <> 8 then
    raise exception 'post-check: AER v1 thresholds must stay 0.8 and 8 (Decision 276)';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $p$;
