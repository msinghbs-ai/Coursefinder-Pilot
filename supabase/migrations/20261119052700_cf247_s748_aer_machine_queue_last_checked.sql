-- CF-247 S748 AER course machine queue: a declined or audit-sample result in admit mode records when the item was last checked (session S2-BOOST-AER; Platform Admin 1-day
-- handover directive 19 Nov 2026 06:49 AEDT item 1, "Confirm the ~90 waiting would_admit course reads admitted cleanly"; delivers S1-AER finding S677 of 19 Nov 2026 03:15).
-- Guards: AER course machine admission (rule aer-machine-v1), Decision 276 (a correctness fix only: no reader, threshold, rule or validator changes; aer.machine_min_confidence 0.8 and
--   aer.machine_min_quote_chars 8 unchanged), G3 (CREATE OR REPLACE of one security function; 75 functions and 48 relations post-checked), Decision 260 (housekeeping),
--   "a passing qualification never switches anything on by itself" (aer.machine_mode is not touched; the validation and its renewal are unchanged).
-- Replaces: security.aer_machine_admit_v1 (same name and signature; md5-guarded edit, exactly once)
-- Retires: nothing
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only). S1-AER 03:15 block of docs/CURRENT-STATE.md: since the re-validation of 18 Nov 20:09:59 the job aer-machine-admission
-- (every 30 minutes, succeeding) admitted 2 course reads; 89 reads recorded would_admit still wait, last checked 16:54 to 19:54 on 18 Nov. Read again 19 Nov 06:39 and 07:02 AEDT:
-- 89 would_admit, 0 course reads admitted in the last hour. Cause: security.aer_machine_run_v1 skips an item for 6 hours by its SHADOW ledger row (s.updated_at), but in admit
-- mode security.aer_machine_admit_v1 records a declined or audit-sample result only as an 'admit' row (and only once per outcome and rule), so the same first 60 items in the
-- run's order (45 audit samples, 15 declined) are checked again every run and the run never reaches the 89 (positions 443 to 2,542).
-- What this changes: in admit mode a result that is not 'admitted' also upserts the item's shadow ledger row (the same statement the shadow mode runs), so its last check is
--   recorded and the 6-hour gap applies. The outcome recorded is the rule's own. Nothing is admitted, decided or withdrawn here; a person's decisions are untouched.
-- Not changed: the order of the run, its batch (batch.aer_machine), its 45-second limit, the daily cap, the 6-hour gap, the rule and its thresholds, the validators (md5 pinned by
--   aer-validation-renew.yml), the audit sample.
-- Before -> after (pg_get_functiondef md5):
--   security.aer_machine_admit_v1(uuid, text)   7473f475f1385e4d25765f34b1a7a7c1 -> 89a5c44b7a9de6b4ca07a3f43288f11a

do $g$
begin
  if to_regprocedure('security.aer_machine_admit_v1(uuid, text)') is null or to_regprocedure('security.aer_machine_run_v1()') is null then
    raise exception 'needs the AER course machine functions';
  end if;
end $g$;

do $ad$
declare v_sig constant text := 'security.aer_machine_admit_v1(uuid, text)'; v_before constant text := '7473f475f1385e4d25765f34b1a7a7c1';
        v_def text := pg_get_functiondef('security.aer_machine_admit_v1(uuid, text)'::regprocedure); v_old text; v_new text; v_c int;
begin
  if v_def like '%S748 (19 Nov 2026%' then raise notice '%: already applied', v_sig; return; end if;
  if md5(v_def) <> v_before then raise exception '% differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_old := $o0$    return jsonb_build_object('ok', false, 'mode', 'admit', 'outcome', v_out, 'rule', v->>'rule', 'reason', v->>'reason');$o0$;
  v_new := $n0$    -- S748 (19 Nov 2026; S1-AER finding S677, 19 Nov 2026 03:15): in admit mode a declined or audit-sample result also records when the item was last checked, in its
    -- shadow ledger row as the shadow mode does, so the job's 6-hour gap applies to it and the next run reaches the items behind it (the outcome is the rule's own; nothing is admitted here)
    insert into pipeline.aer_machine_admissions (review_item_id, course_id, provider_id, mode, outcome, reason_code, reason, next_action, checks, evidence_id, content_hash, source_url, actor)
    values (p_item, v_course, v_prov, 'shadow', v_out, v->>'rule', v->>'reason', v->>'next_action', coalesce(v->'checks', '{}'::jsonb),
            nullif(v->'checks'->>'evidence_id', '')::uuid, v->'checks'->>'content_hash', v->'checks'->>'source_url', v_sys)
    on conflict (review_item_id) where mode = 'shadow' do update set outcome = excluded.outcome, reason_code = excluded.reason_code, reason = excluded.reason, next_action = excluded.next_action,
           checks = excluded.checks, evidence_id = excluded.evidence_id, content_hash = excluded.content_hash, source_url = excluded.source_url, updated_at = now();
    return jsonb_build_object('ok', false, 'mode', 'admit', 'outcome', v_out, 'rule', v->>'rule', 'reason', v->>'reason');$n0$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', v_sig, v_c; end if;
  execute replace(v_def, v_old, v_new);
  raise notice '%: applied, md5 now %', v_sig, md5(pg_get_functiondef('security.aer_machine_admit_v1(uuid, text)'::regprocedure));
end $ad$;

insert into pipeline.admin_control_events(area, action, target, detail)
select 'aer', 'machine_queue', 'security.aer_machine_admit_v1',
       jsonb_build_object('change', 'in admit mode a declined or audit-sample result also records the last check in the shadow ledger row, so the 6-hour gap applies and the queue moves',
                          'finding', 'S1-AER S677 (19 Nov 2026 03:15)', 'authority', 'Platform Admin 19 Nov 2026 06:49 (S2-BOOST-AER item 1)', 'migration', '20261119052700')
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'machine_queue' and e.detail->>'migration' = '20261119052700');

do $p$
begin
  if pg_catalog.pg_get_functiondef('security.aer_machine_admit_v1(uuid,text)'::regprocedure) not like '%S748 (19 Nov 2026; S1-AER finding S677%' then raise exception 'post-check: S748 edit missing'; end if;
  if security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8 or security.pipeline_num_v1('aer.machine_min_quote_chars', -1) <> 8 then
    raise exception 'post-check: AER v1 thresholds must stay unchanged (Decision 276)';
  end if;
  if md5(pg_catalog.pg_get_functiondef('security.aer_machine_validate_v1()'::regprocedure)) <> '945077fe5dc291cc0893976f8fe65aef' then
    raise exception 'post-check: the course validator must stay the definition aer-validation-renew.yml pins';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $p$;
