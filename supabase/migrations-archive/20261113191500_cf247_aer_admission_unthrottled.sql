-- CF-247 AER: reading and admission throttles raised to conclude as soon as possible (Platform Admin 12 Nov 2026 22:05: "Fasten it up to conclude asap
-- dont limit on data admittance make exceptions for it"; with 21:47 "Keep using ai until credit runs out").
-- Guards: G2 (every value stays a setting, changed here with the Platform Admin's reason, within its max_value), G3 (no consumer API object), Decision 260,
--   Layer 4 authority and the admission rules unchanged (quote proof, D-R3 completeness, rule D1 "applicability is never inferred", the 5% random audit and
--   withdrawal stay); only how many reads and admissions run, and how fast, changes.
-- What (from -> to; each update applies only while the value is still the one read on 12 Nov 2026 22:10 AEDT, so a later change by a person is kept):
--   admission    aer.machine_daily_max 1000 -> 5000; batch.aer_machine 60 -> 200; batch.aer_matrix_machine 20 -> 100;
--                aer.grid_machine_admission_on 0 -> 1 (proven grid reads, Sydney, UNSW and UQ, go through the same machine check instead of waiting for a person;
--                explicit Platform Admin instruction, so not a qualification switching itself on)
--   course reads aer.schedule_daily_max 200 -> 5000; aer.schedule_per_provider 5 -> 50; batch.aer_schedule_courses 20 -> 100;
--                aer.schedule_layer4_max 600 -> 10000; aer.schedule_correction_daily_max 100 -> 1000
--   tables       batch.entry_matrix 4 -> 10; batch.aer_schedule_matrix 4 -> 20; entry.attach_per_provider 3 -> 10
--   recovery     aer.replay_daily_max 200 -> 1000; aer.replay_per_provider 10 -> 50; batch.aer_replay 20 -> 100;
--                aer.e13_recover_on 0 -> 1, aer.e13_recover_daily_max 40 -> 200, aer.e13_recover_total_max 40 -> 1000
--   AI guards    openrouter.guard_entry_matrix 2 -> 20; openrouter.guard_enrich_fields 25 -> 50; aer.v2_shadow_daily_usd 3 -> 10
-- Kept as they are (technical safety, G2): reading.entry_pdf_per_call 1 (edge CPU), entry.matrix_attempts, the credit floor (0.50).
-- Reversal without code: each value on Settings › Pipeline settings or Toolsets & limits, with a reason.
-- Replaces: nothing. Retires: nothing.

do $r$
declare v_reason text := 'Platform Admin 12 Nov 2026 22:05: "Fasten it up to conclude asap dont limit on data admittance make exceptions for it"';
        r record; v_n int; v_done jsonb := '[]'::jsonb;
begin
  for r in select * from (values
      ('pipeline', 'aer.machine_daily_max', 1000::numeric, 5000::numeric), ('pipeline', 'batch.aer_machine', 60, 200), ('pipeline', 'batch.aer_matrix_machine', 20, 100),
      ('pipeline', 'aer.grid_machine_admission_on', 0, 1),
      ('pipeline', 'aer.schedule_daily_max', 200, 5000), ('pipeline', 'aer.schedule_per_provider', 5, 50), ('pipeline', 'batch.aer_schedule_courses', 20, 100),
      ('pipeline', 'aer.schedule_layer4_max', 600, 10000), ('pipeline', 'aer.schedule_correction_daily_max', 100, 1000),
      ('pipeline', 'batch.entry_matrix', 4, 10), ('pipeline', 'batch.aer_schedule_matrix', 4, 20), ('pipeline', 'entry.attach_per_provider', 3, 10),
      ('pipeline', 'aer.replay_daily_max', 200, 1000), ('pipeline', 'aer.replay_per_provider', 10, 50), ('pipeline', 'batch.aer_replay', 20, 100),
      ('pipeline', 'aer.e13_recover_on', 0, 1), ('pipeline', 'aer.e13_recover_daily_max', 40, 200), ('pipeline', 'aer.e13_recover_total_max', 40, 1000),
      ('openrouter', 'guard_entry_matrix', 2, 20), ('openrouter', 'guard_enrich_fields', 25, 50), ('pipeline', 'aer.v2_shadow_daily_usd', 3, 10)
    ) v(toolset_key, key, from_v, to_v) loop
    update pipeline.platform_toolset_settings s set value = to_jsonb(r.to_v), reason = v_reason, updated_at = now()
     where s.toolset_key = r.toolset_key and s.key = r.key and (s.value #>> '{}')::numeric = r.from_v
       and (s.max_value is null or r.to_v <= s.max_value::numeric);
    get diagnostics v_n = row_count;
    v_done := v_done || jsonb_build_array(jsonb_build_object('key', r.toolset_key || '.' || r.key, 'from', r.from_v, 'to', r.to_v, 'applied', v_n = 1));
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting_change', 'AER reading and admission throttles', jsonb_build_object('reason', v_reason, 'settings', v_done), null);
  raise notice 'AER throttles: %', v_done;
end $r$;
