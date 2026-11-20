-- CF-247 s914 to s916 (Platform Admin 21 Nov 2026 10:03 AEDT, chat S1-Fast-Admission, "accelerate verified data admission into live canonical
-- tables today"): the partial entry-table admission goes live now instead of after a 24-hour shadow; verified course entry reads are no longer
-- held back as audit samples; the admission and reconcile jobs run every 15 minutes; the $0 deterministic sweeps take three times the work.
-- This decision brings forward the cutover the Platform Admin approved at 09:57 for 22 Nov 2026 09:30 AEDT (s912, chat S1-Coverage-Unlock-UI-Notes):
-- that cutover is this change and is not made again.
--
-- s914  Partial entry-table admission, live (rule aer-partial-admit of admission-rule-runner, every 15 minutes; it replaces the shadow
--       aer-uniwide-partial-shadow, s902/s912). For an entry-matrix first read waiting in Layer 4 that the machine admission stops only at the
--       completeness gate (D-R3 gate_incomplete or the completeness guard), every earlier check has passed: no manual lock, no earlier rejection,
--       not claimed, stored copy present and current, fetched from the official address, source on the provider's own website host, host not
--       shared (security.aer_matrix_machine_check_v1, unchanged). Of its proposed rows (university-wide and course rows, as s912 measured), a row
--       is admitted only when it passes every machine row rule (not excluded, confidence, quote length, mapped level, a published minimum on a
--       grade scale, the minimum in the verbatim quote) and also: its course (for a course row) has no manual lock, no active row of another
--       source or provider has its identity (decision D4 C2), and no other passing row of the read shares its identity. An active row of the same
--       source with the same identity is superseded, as Approve except does (D4). Everything else stays proposed, and the item stays in Layer 4
--       with a reason naming the countries the read did not cover and the rows held. A grid read stays held while aer.grid_machine_admission_on
--       is 0. Ledger: pipeline.aer_matrix_machine_admissions (rule aer-partial-v1), so security.aer_matrix_machine_withdraw_v1 reverses it.
-- s915  Course entry reads (rule aer-machine-v1) and entry tables (aer-matrix-machine-v1): the audit sample is set to 0 per cent. 491 reads
--       (1,450 rows) passed every check and were waiting only because they were drawn for the sample; they are admitted by the next runs. Their
--       audit_sample ledger rows stay, so a person can still check them after admission and withdraw one (a withdrawal suspends the rule).
--       Job aer-machine-admission moves from :24 and :54 to every 15 minutes (:06, :21, :36, :51). The deterministic proposer takes 150 courses
--       a tick (was 50) and up to 1,200 waiting items (was 400; it was held at the cap of 400).
-- s916  Job aer-reconcile moves from :27 to every 15 minutes (:12, :27, :42, :57; single flight, 84 s p50). aer-det-sweep: a NUL escape in a
--       page's text failed every collected answer from 03:00 AEDT (71 of 72 calls), so the same 40 pages were sent again on every tick; the escape
--       is now dropped before the cast (md5-guarded edit of security.aer_det_sweep_v1). Throughput three times: aer_det.sweep_calls 3 to 9 and
--       sweep_max_open 4 to 12 (40 pages a call, unchanged); elr_det.in_flight_max 8 to 24, batch.elr_det_sweep 200 to 600 (25 pages a call,
--       unchanged); batch.elr_central 6 to 18 (one central call at a time, unchanged). Each range is widened to take the new value.
--
-- Found live (rolled-back probes, 21 Nov 2026 10:08 to 10:40 AEDT; head 20261121130000, 2,242 rows; G3 75/48; manual locks 7,585; 137 active
-- jobs, 0 unregistered): Layer 4 waits 1,065 course entry reads (2,721 proposed rows) and 73 entry-matrix reads; the s912 shadow would admit
-- 1,141 rows at 27 providers (Charles Sturt 7); course reads wait for: audit sample 491, every row held 285, gate incomplete 257, no bound page 41,
-- identity not admitted 19; 15 admitted in 24 hours. Decision 276 (AER v1 frozen): no reader, word list or recovery path is added; this is
-- admission policy over existing reads and settings, and one correctness fix.
-- Replaces: rule aer-uniwide-partial-shadow (s902/s912; switched off and retiring, its table kept); the :24/:54 minutes of aer-machine-admission
-- and the :27 minute of aer-reconcile; the 5 per cent audit samples; the aer_det, elr_det and elr_central throughput values above.
-- Retires: rule aer-uniwide-partial-shadow and functions security.aer_uniwide_partial_shadow_v1 and security.aer_uniwide_partial_shadow_report_v1
-- (retiring, retire after 14 days; nothing dropped).
-- G1: the new rule is catalogued and registered; no cron job added (active jobs unchanged). G2: every value is a setting; no number in a job or
-- rule call. G3: no consumer object (75/48). Nothing dropped or deleted. No spend (no model, no Firecrawl).
set local lock_timeout = '5s'; -- fixed: lock wait guard for the cron, setting and function updates below

-- 0. preconditions: the live definitions this change edits are the ones it was written against
do $pre$
begin
  if md5(pg_get_functiondef('security.aer_det_sweep_v1()'::regprocedure)) <> '9856b441c16e408184e069bd5d8f1cbe' then
    raise exception 's916 precondition: security.aer_det_sweep_v1 is not the s835 definition this change edits (md5 9856b441)';
  end if;
  if not exists (select 1 from cron.job where jobname = 'aer-machine-admission' and schedule = '24,54 * * * *' and command = 'select security.aer_machine_run_v1()' and active) then
    raise exception 's915 precondition: aer-machine-admission is not at 24,54 with its expected command';
  end if;
  if not exists (select 1 from cron.job where jobname = 'aer-reconcile' and schedule = '27 * * * *' and active
                   and command = 'select security.aer_reconcile_v1(security.pipeline_num_v1(''batch.aer_reconcile'', 5000)::int)') then
    raise exception 's916 precondition: aer-reconcile is not at :27 with its expected command';
  end if;
  if not exists (select 1 from pipeline.admission_rules where rule_code = 'aer-uniwide-partial-shadow' and enabled) then
    raise exception 's914 precondition: the shadow rule aer-uniwide-partial-shadow is not registered and on';
  end if;
end $pre$;

-- 1. s914 settings
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.partial_admit_on', 'Entry requirements: admit verified rows of an incomplete entry table',
  '1: every 15 minutes, for an entry-table read stopped only by completeness, admit each university-wide or course row that passes every machine row rule (official host, stored copy, verbatim quote with the minimum, mapped level and grade scale, no manual lock, no conflicting active row); the countries the read did not cover and the rows held stay in Layer 4. 0: off.',
  'number', '1'::jsonb, 0, 1, 'on/off', 1501, 'Entry requirements', 'security.aer_partial_admit_v1 (rule aer-partial-admit)',
  'CF-247 s914 (Platform Admin 21 Nov 2026 10:03, S1-Fast-Admission): partial admission live today, no 24-hour shadow'),
 ('pipeline', 'batch.aer_partial_admit', 'Entry requirements: entry-table reads looked at a run (partial admission)',
  'Most entry-matrix reads waiting in Layer 4 that one partial admission run looks at, oldest first.',
  'number', '200'::jsonb, 1, 500, 'items', 1502, 'Entry requirements', 'security.aer_partial_admit_v1 (rule aer-partial-admit)',
  'CF-247 s914 (Platform Admin 21 Nov 2026 10:03)')
on conflict (toolset_key, key) do nothing;

-- 2. s914 the rule
create or replace function security.aer_partial_admit_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare
  v_batch int := greatest(1, security.pipeline_num_v1('batch.aer_partial_admit', 200)::int);
  v_conf numeric := security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9);
  v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int;
  v_grid int := security.pipeline_num_v1('aer.grid_machine_admission_on', 0)::int;
  v_sys uuid := security.system_actor_id();
  v_t0 timestamptz := clock_timestamp();
  r record; c jsonb; v_run pipeline.entry_matrix_runs%rowtype; v_ex jsonb; v_exids uuid[]; v_inh uuid[]; v_cmp uuid[];
  v_ok uuid[]; v_held jsonb; v_heldn int; v_miss text[]; v_on int; v_sup int; v_after int; v_reason text;
  v_seen int := 0; v_items int := 0; v_rows int := 0; v_err int := 0; v_last text;
begin
  if security.pipeline_num_v1('aer.partial_admit_on', 1) < 1 then return jsonb_build_object('on', false); end if;
  if security.aer_matrix_machine_effective_v1() < 2 then return jsonb_build_object('on', true, 'held', 'matrix_machine_not_admitting'); end if;
  for r in select i.id, i.entity_id from pipeline.layer4_review_items i
            where i.status = 'pending' and i.field_code = 'entry_matrix_first_run' and i.entity_type = 'provider'
              and i.claimed_at is null and i.assigned_to is null
              -- a read already partly admitted by this rule is not looked at again (a new read is a new item)
              and not exists (select 1 from pipeline.aer_matrix_machine_admissions a where a.review_item_id = i.id and a.rule = 'aer-partial-v1' and a.withdrawn_at is null)
              -- a read the machine admission last stopped for another reason than completeness is left to it
              and coalesce((select d.reason_code from pipeline.aer_matrix_machine_admissions d where d.review_item_id = i.id and d.mode = 'admit' order by d.id desc limit 1),
                           'gate_incomplete') in ('gate_incomplete', 'completeness')
            order by i.created_at, i.id limit v_batch loop
    exit when clock_timestamp() - v_t0 > interval '40 seconds';  -- fixed: a run stays inside the rule's time budget (60 s)
    v_seen := v_seen + 1;
    begin
      c := security.aer_matrix_machine_check_v1(r.id);
      continue when coalesce(c->>'rule', '') not in ('gate_incomplete', 'completeness');
      select * into v_run from pipeline.entry_matrix_runs x where x.review_item_id = r.id;
      continue when v_run.id is null;
      continue when coalesce(v_run.result->>'reader', '') = 'pdf-grid-v1' and v_grid < 1;
      v_ex := security.aer_matrix_machine_exclusions_v1(v_run.id);
      v_exids := coalesce(array(select jsonb_array_elements_text(v_ex->'ids')::uuid), '{}'::uuid[]);
      v_inh := coalesce(array(select jsonb_array_elements_text(v_ex->'level_inherit_ids')::uuid), '{}'::uuid[]);
      v_cmp := coalesce(array(select jsonb_array_elements_text(v_ex->'completion_only_ids')::uuid), '{}'::uuid[]);
      -- the machine admission's row rules in its order, then a course lock, a conflicting active row (D4 C2) and a shared identity (D4 C1)
      with x as (
        select m.id, m.row_hash, case
            when m.id = any(v_exids) then 'excluded_by_rule'
            when coalesce(m.confidence, 0) < v_conf then 'low_confidence'
            when length(btrim(coalesce(m.quote, ''))) < v_qmin then 'short_quote'
            when m.study_level_id is null and not (m.id = any(v_inh)) then 'level_unmapped'
            when not (m.id = any(v_cmp)) and not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
            when not (m.id = any(v_cmp)) and not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote'
            when m.course_id is not null and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field in ('entry_requirements', 'all')) then 'course_locked'
            when exists (select 1 from catalogue.provider_entry_matrix a where a.row_hash = m.row_hash and a.status = 'active' and a.id <> m.id
                           and not coalesce(a.provider_id = v_run.provider_id and a.source_id = v_run.source_id and a.run_id is distinct from v_run.id, false)) then 'conflicting_active'
          end why
          from catalogue.provider_entry_matrix m
         where m.run_id = v_run.id and m.status = 'proposed'),
      y as (select x.id, case when x.why is null and count(*) filter (where x.why is null) over (partition by x.row_hash) > 1 then 'duplicate_identity' else x.why end why from x)
      select coalesce(array_agg(y.id) filter (where y.why is null), '{}'),
             coalesce((select jsonb_object_agg(z.why, z.n) from (select y2.why, count(*) n from y y2 where y2.why is not null group by y2.why) z), '{}'::jsonb),
             count(*) filter (where y.why is not null)
        into v_ok, v_held, v_heldn from y;
      continue when cardinality(v_ok) = 0;
      v_miss := coalesce(array(select jsonb_array_elements_text(c->'checks'->'gate'->'countries_missing')), '{}');
      -- D4: an active row of the same source with the same identity is replaced by the admitted row
      update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'replaced by run ' || v_run.id,
             provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('aer_supersede', jsonb_build_object('review_item_id', r.id, 'run_id', v_run.id,
               'replaced_by_row_id', p.id, 'decision', 'partial admission (aer-partial-v1, s914)', 'at', now())),
             updated_at = now()
        from catalogue.provider_entry_matrix p
       where p.id = any(v_ok) and p.row_hash = m.row_hash
         and m.provider_id = v_run.provider_id and m.source_id = v_run.source_id and m.status = 'active' and m.run_id is distinct from v_run.id;
      get diagnostics v_sup = row_count;
      update catalogue.provider_entry_matrix m set status = 'active', status_reason = null,
             provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('partial_admission', jsonb_build_object('rule', 'aer-partial-v1', 'change', 's914',
               'review_item_id', r.id, 'run_id', v_run.id, 'countries_not_read', to_jsonb(v_miss), 'at', now())),
             updated_at = now()
       where m.id = any(v_ok) and m.status = 'proposed';
      get diagnostics v_on = row_count;
      select count(*) into v_after from catalogue.provider_entry_matrix m where m.id = any(v_ok) and m.status = 'active';
      if v_on <> cardinality(v_ok) or v_after <> cardinality(v_ok) then
        raise exception 'aer-partial: read-back found % active of % admitted rows', v_after, cardinality(v_ok);
      end if;
      v_reason := format('Partial admission (aer-partial-v1, s914, Platform Admin 21 Nov 2026 10:03): %s row(s) of this read admitted from the provider''s own source %s (host %s, content hash %s); each passed every machine row rule. Held for a person: countries not read: %s; %s row(s) held (%s).',
                         v_on, coalesce(c->'checks'->>'source_url', ''), coalesce(security.site_host_v1(c->'checks'->>'source_url'), '?'), left(coalesce(c->'checks'->>'content_hash', ''), 12),  -- fixed: a short hash prefix for reading
                         coalesce(nullif(array_to_string(v_miss, ', '), ''), 'none named'), v_heldn, v_held::text);
      insert into pipeline.aer_matrix_machine_admissions (review_item_id, provider_id, run_id, mode, outcome, rule, reason_code, reason, checks, rows_admitted, actor)
      values (r.id, r.entity_id, v_run.id, 'admit', 'admitted', 'aer-partial-v1', 'partial', v_reason,
              coalesce(c->'checks', '{}'::jsonb) || jsonb_build_object('admitted_row_ids', to_jsonb(v_ok), 'held_back', v_heldn, 'held_back_by_rule', v_held,
                                                                     'countries_not_read', to_jsonb(v_miss), 'superseded', v_sup, 'machine_rule', c->>'rule'),
              v_on, v_sys);
      update pipeline.layer4_review_items
         set escalation_reason = left(format('Partial admission (aer-partial-v1): %s row(s) admitted. Still for a person: countries not read (%s) and %s row(s) held.',
                                             v_on, coalesce(nullif(array_to_string(v_miss, ', '), ''), 'none named'), v_heldn)
                                      || ' | ' || coalesce(escalation_reason, ''), 1000)  -- fixed: the column shows 1000 characters
       where id = r.id and status = 'pending';
      insert into pipeline.admin_control_events (area, action, target, detail, actor)
      values ('layer4', 'aer_partial_admit', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', r.id, 'provider_id', r.entity_id, 'run_id', v_run.id,
              'rows_admitted', v_on, 'superseded', v_sup, 'held_back', v_heldn, 'countries_not_read', to_jsonb(v_miss), 'rule', 'aer-partial-v1', 'change', 's914',
              'auto', true, 'actor_kind', 'machine'), v_sys);
      v_items := v_items + 1; v_rows := v_rows + v_on;
    exception when others then
      v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  return jsonb_build_object('on', true, 'looked_at', v_seen, 'items_admitted', v_items, 'rows_admitted', v_rows, 'errors', v_err, 'last_error', v_last,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $f$;
revoke all on function security.aer_partial_admit_v1() from public, anon, authenticated;
comment on function security.aer_partial_admit_v1() is 'CF-247 s914 (Platform Admin 21 Nov 2026 10:03): rule aer-partial-admit (aer-partial-v1). For an entry-matrix first read waiting in Layer 4 that the machine admission stops only at completeness, admits each proposed university-wide or course row that passes every machine row rule, has no course manual lock, no conflicting active row and no shared identity; the rest and the countries not read stay with a person. Ledger aer_matrix_machine_admissions (reversible by security.aer_matrix_machine_withdraw_v1), control event, Layer 4 reason.';

insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-partial-admit', 'Admission', 22, 'Entry requirements: admit verified rows of an incomplete entry table',
  'Every 15 minutes (:14, :29, :44, :59), as a rule of admission-rule-runner: while aer.partial_admit_on is 1, looks at up to batch.aer_partial_admit entry-matrix reads waiting in Layer 4 that only completeness stops, and admits each university-wide or course row that passes every machine row rule (official host, current stored copy, verbatim quote with the minimum, mapped level and grade scale, no manual lock, no conflicting active row). The countries the read did not cover and the rows held stay in Layer 4 (s914, live 21 Nov 2026; replaces the shadow aer-uniwide-partial-shadow).',
  6, true, null)
on conflict (jobname) do nothing;

insert into pipeline.admission_rules (rule_code, legacy_job, call_sql, call_md5, schedule, priority, mode, budget_ms, expected_ms, note)
values ('aer-partial-admit', 'aer-partial-admit', 'select security.aer_partial_admit_v1()', md5('select security.aer_partial_admit_v1()'),
        '14,29,44,59 * * * *', 60, 'live', 60000, 30000, 'CF-247 s914: partial entry-table admission, live 21 Nov 2026 (Platform Admin 10:03, S1-Fast-Admission); replaces the shadow aer-uniwide-partial-shadow')
on conflict (rule_code) do nothing;

-- the shadow is replaced: switched off, its rows kept, retiring after the retention window
update pipeline.admission_rules set enabled = false, note = coalesce(note, '') || ' | switched off by s914 (20261121150000): replaced by aer-partial-admit', updated_at = now()
 where rule_code = 'aer-uniwide-partial-shadow' and enabled;
update pipeline.platform_toolset_settings set value = to_jsonb(0), updated_at = now(),
       reason = 'CF-247 s914 (Platform Admin 21 Nov 2026 10:03): the shadow is replaced by the live rule aer-partial-admit (aer.partial_admit_on)'
 where toolset_key = 'pipeline' and key = 'aer.uniwide_partial_shadow_on' and value = to_jsonb(1);
update pipeline.component_register set status = 'retiring', replaced_by = case when name = 'pipeline.aer_uniwide_partial_shadow' then 'nothing: kept as the shadow record' else 'security.aer_partial_admit_v1 (rule aer-partial-admit)' end,
       retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now(),
       note = 'switched off by s914 (20261121150000): the partial admission went live without the 24-hour shadow (Platform Admin 21 Nov 2026 10:03)'
 where name in ('aer-uniwide-partial-shadow', 'security.aer_uniwide_partial_shadow_v1', 'security.aer_uniwide_partial_shadow_report_v1') and status = 'active';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'aer-partial-admit', 'Layer 4', 'Admission', 'CF-247 s914: partial entry-table admission (admission-rule-runner rule, every 15 minutes)', 'active', '{aer-uniwide-partial-shadow}', '20261121150000'),
 ('function', 'security.aer_partial_admit_v1', 'Layer 4', 'Admission', 'CF-247 s914: the partial admission run', 'active', '{security.aer_uniwide_partial_shadow_v1}', '20261121150000')
on conflict do nothing;

-- 3. s915 audit samples off; admission every 15 minutes; the proposer takes three times the work
update pipeline.platform_toolset_settings set value = to_jsonb(0), updated_at = now(),
       reason = 'CF-247 s915 (Platform Admin 21 Nov 2026 10:03): a read that passes every check is admitted, not held for a sample; its audit_sample ledger row stays for a check after admission'
 where toolset_key = 'pipeline' and key in ('aer.machine_audit_pct', 'aer.matrix_machine_audit_pct') and value = to_jsonb(5);
update pipeline.platform_toolset_settings set value = to_jsonb(150), updated_at = now(), reason = 'CF-247 s915 (Platform Admin 21 Nov 2026 10:03): three times the courses proposed a tick'
 where toolset_key = 'pipeline' and key = 'aer_det.propose_per_run' and value = to_jsonb(50);
update pipeline.platform_toolset_settings set value = to_jsonb(1200), updated_at = now(), reason = 'CF-247 s915 (Platform Admin 21 Nov 2026 10:03): the proposer was held at 400 waiting items; three times the room'
 where toolset_key = 'pipeline' and key = 'aer_det.propose_max_pending' and value = to_jsonb(400);

-- 4. s916 throughput of the $0 deterministic sweeps (each range widened to take the new value)
update pipeline.platform_toolset_settings set max_value = 12, value = to_jsonb(9), updated_at = now(), reason = 'CF-247 s916 (Platform Admin 21 Nov 2026 10:03): three times the worker calls a tick (40 pages a call, unchanged)'
 where toolset_key = 'pipeline' and key = 'aer_det.sweep_calls' and value = to_jsonb(3);
update pipeline.platform_toolset_settings set max_value = 16, value = to_jsonb(12), updated_at = now(), reason = 'CF-247 s916 (Platform Admin 21 Nov 2026 10:03): three times the calls open at once'
 where toolset_key = 'pipeline' and key = 'aer_det.sweep_max_open' and value = to_jsonb(4);
update pipeline.platform_toolset_settings set max_value = 24, value = to_jsonb(24), updated_at = now(), reason = 'CF-247 s916 (Platform Admin 21 Nov 2026 10:03): three times the English reader calls in flight (25 pages a call, unchanged)'
 where toolset_key = 'pipeline' and key = 'elr_det.in_flight_max' and value = to_jsonb(8);
update pipeline.platform_toolset_settings set max_value = 600, value = to_jsonb(600), updated_at = now(), reason = 'CF-247 s916 (Platform Admin 21 Nov 2026 10:03): three times the English pages claimed a tick'
 where toolset_key = 'pipeline' and key = 'batch.elr_det_sweep' and value = to_jsonb(200);
update pipeline.platform_toolset_settings set max_value = 20, value = to_jsonb(18), updated_at = now(), reason = 'CF-247 s916 (Platform Admin 21 Nov 2026 10:03): three times the central English sources in one call (one call at a time, unchanged)'
 where toolset_key = 'pipeline' and key = 'batch.elr_central' and value = to_jsonb(6);

-- 5. s916 aer-det-sweep: a NUL escape no longer fails the whole answer (md5-guarded above; only the cast line changes)
create or replace function security.aer_det_sweep_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_ext constant text := 'aer-det-v1.3';  -- fixed: the reader version the worker must answer with (a worker still on an older version is refused, so nothing from it is recorded)
  v_on int := security.pipeline_num_v1('aer_det.sweep_on', 1)::int;
  v_calls int := security.pipeline_num_v1('aer_det.sweep_calls', 3)::int;
  v_max_open int := security.pipeline_num_v1('aer_det.sweep_max_open', 4)::int;
  v_lost int := security.pipeline_num_v1('aer_det.call_lost_minutes', 15)::int;
  v_per int := security.pipeline_num_v1('batch.aer_det_read', 40)::int;
  c record; resp record; v_body jsonb; v_pages jsonb; v_rec jsonb; v_open int; v_n int; v_sent int := 0; v_got int := 0; v_open_ids uuid[]; v_items jsonb; v_id bigint; v_prop jsonb := null; i int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.maintenance_hold_v1() then return jsonb_build_object('held', 'maintenance'); end if;
  -- 1. collect the answers of earlier calls
  for c in select * from pipeline.aer_det_sweep_calls where collected_at is null order by sent_at loop
    select r.status_code, r.timed_out, r.error_msg, r.content::text as content into resp from net._http_response r where r.id = c.request_id;
    if not found then
      if c.sent_at < now() - make_interval(mins => v_lost) then update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'lost' where request_id = c.request_id; end if;
      continue;
    end if;
    begin
      if resp.timed_out or resp.error_msg is not null or resp.status_code >= 300 then raise exception 'call failed'; end if;
      -- s916 (21 Nov 2026): a NUL escape (\u0000) in a page's text cannot be cast to jsonb, which failed the whole call and sent the same pages
      -- again on every tick (71 of 72 calls failed from 03:00 AEDT); the escape is dropped before the cast, nothing else is changed
      v_body := regexp_replace(resp.content, '(?<!\\)\\u0000', '', 'g')::jsonb;
      if v_body->>'extractor' is distinct from v_ext then
        update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'wrong_extractor' where request_id = c.request_id; continue;
      end if;
      select coalesce(jsonb_agg(p || jsonb_build_object('extractor', v_ext)), '[]'::jsonb) into v_pages from jsonb_array_elements(coalesce(v_body->'pages', '[]'::jsonb)) p;
      v_rec := security.aer_det_record_v2(v_pages);
      update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'ok', pages = (v_rec->>'pages')::int, readings = (v_rec->>'readings')::int where request_id = c.request_id;
      v_got := v_got + 1;
    exception when others then
      update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'failed' where request_id = c.request_id;
    end;
  end loop;
  -- 2. send the next stored pages (the base is the one the workflow runner reads: a stored page of an active course that has no active rule)
  select count(*) into v_open from pipeline.aer_det_sweep_calls where collected_at is null;
  v_n := least(v_calls, v_max_open - v_open);
  if v_on = 1 and v_n > 0 then
    select coalesce(array_agg(x::uuid), '{}') into v_open_ids from pipeline.aer_det_sweep_calls o, jsonb_array_elements_text(o.course_ids) x where o.collected_at is null;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', t.course_id, 'evidence_id', t.evidence_id, 'storage_path', t.storage_path) order by t.course_id), '[]'::jsonb) into v_items
      from (select g.course_id, g.evidence_id, e.storage_path
              from pipeline.coverage_course_pages g
              join catalogue.courses c2 on c2.id = g.course_id and c2.lifecycle_status = 'active'
              join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
             where g.evidence_id is not null and g.read_status is not null and g.status = 'bound'
               and not (g.course_id = any (v_open_ids))
               and not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = g.course_id and r.status = 'active')
               and not exists (select 1 from pipeline.aer_det_academic_pages d where d.course_id = g.course_id and d.evidence_id = g.evidence_id and d.extractor = v_ext)
             order by g.course_id limit v_per * v_n) t;
    for i in 0 .. v_n - 1 loop
      exit when i * v_per >= jsonb_array_length(v_items);
      select coalesce(jsonb_agg(e.item), '[]'::jsonb) into v_pages from jsonb_array_elements(v_items) with ordinality e(item, o) where e.o > i * v_per and e.o <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'aer_det_read', 'items', v_pages));
      insert into pipeline.aer_det_sweep_calls (request_id, course_ids, status) values (v_id, (select coalesce(jsonb_agg(p->>'course_id'), '[]'::jsonb) from jsonb_array_elements(v_pages) p), 'sent');
      v_sent := v_sent + 1;
    end loop;
  end if;
  -- 3. propose what has been read
  v_prop := security.aer_det_propose_v1();
  return jsonb_build_object('collected', v_got, 'calls_sent', v_sent, 'open_calls', v_open, 'propose', v_prop);
end $f$;
comment on function security.aer_det_sweep_v1() is 'CF-247 s835/s916: one tick of the job aer-det-sweep. Collects the answers of earlier worker calls (mode aer_det_read, no model, no Firecrawl; a NUL escape in page text is dropped before the cast, s916), records the academic readings, sends the next stored pages, then proposes the readings through security.aer_det_propose_v1. No AI or Firecrawl spend.';
revoke all on function security.aer_det_sweep_v1() from public, anon, authenticated;

-- 6. s915/s916 schedules: same commands, every 15 minutes
do $sched$
declare v_adm bigint; v_rec bigint;
begin
  select jobid into v_adm from cron.job where jobname = 'aer-machine-admission' and command = 'select security.aer_machine_run_v1()';
  select jobid into v_rec from cron.job where jobname = 'aer-reconcile' and command = 'select security.aer_reconcile_v1(security.pipeline_num_v1(''batch.aer_reconcile'', 5000)::int)';
  perform cron.alter_job(v_adm, schedule => '6,21,36,51 * * * *');
  perform cron.alter_job(v_rec, schedule => '12,27,42,57 * * * *');
  update pipeline.automation_catalogue set description = description || ' Every 15 minutes from 21 Nov 2026 (:06, :21, :36, :51; s915, was :24 and :54).'
   where jobname = 'aer-machine-admission' and description not like '%s915%';
  update pipeline.automation_catalogue set description = description || ' Every 15 minutes from 21 Nov 2026 (:12, :27, :42, :57; s916, was hourly at :27).'
   where jobname = 'aer-reconcile' and description not like '%s916%';
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scheduler', 'job_reschedule', 'aer-machine-admission', jsonb_build_object('change', 's915', 'from', '24,54 * * * *', 'to', '6,21,36,51 * * * *'), null),
         ('scheduler', 'job_reschedule', 'aer-reconcile', jsonb_build_object('change', 's916', 'from', '27 * * * *', 'to', '12,27,42,57 * * * *'), null),
         ('admission', 'rule_cutover', 'aer-partial-admit', jsonb_build_object('change', 's914', 'replaces', 'aer-uniwide-partial-shadow', 'decision', 'Platform Admin 21 Nov 2026 10:03 AEDT, S1-Fast-Admission'), null);
end $sched$;

-- 7. post-checks, then the first partial admission run now (the cutover is live on deploy)
do $s914$
declare v_jobs int := (select count(*) from cron.job where active); v_locks int := (select count(*) from pipeline.manual_locks); v_res jsonb; v_bad text;
begin
  if (select schedule from cron.job where jobname = 'aer-machine-admission') <> '6,21,36,51 * * * *'
     or (select schedule from cron.job where jobname = 'aer-reconcile') <> '12,27,42,57 * * * *' then raise exception 'post-check: a job did not take its new schedule'; end if;
  if exists (select 1 from cron.job where jobname in ('aer-machine-admission', 'aer-reconcile') and not active) then raise exception 'post-check: a moved job is off'; end if;
  select string_agg(k, ', ') into v_bad from (values ('aer.machine_audit_pct', 0::numeric), ('aer.matrix_machine_audit_pct', 0), ('aer_det.propose_per_run', 150), ('aer_det.propose_max_pending', 1200),
      ('aer_det.sweep_calls', 9), ('aer_det.sweep_max_open', 12), ('elr_det.in_flight_max', 24), ('batch.elr_det_sweep', 600), ('batch.elr_central', 18),
      ('aer.partial_admit_on', 1), ('batch.aer_partial_admit', 200), ('aer.uniwide_partial_shadow_on', 0)) t(k, v)
   where security.pipeline_num_v1(k, -1) <> v
      or exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = t.k and (s.value #>> '{}')::numeric not between s.min_value and s.max_value);
  if v_bad is not null then raise exception 'post-check: setting(s) not at the new value or outside the range: %', v_bad; end if;
  if not exists (select 1 from pipeline.admission_rules where rule_code = 'aer-partial-admit' and enabled and mode = 'live' and call_md5 = md5(call_sql)) then raise exception 'post-check: the live rule is not registered'; end if;
  if exists (select 1 from pipeline.admission_rules where rule_code = 'aer-uniwide-partial-shadow' and enabled) then raise exception 'post-check: the shadow rule is still on'; end if;
  if position('regexp_replace(resp.content' in pg_get_functiondef('security.aer_det_sweep_v1()'::regprocedure)) = 0 then raise exception 'post-check: the sweep fix is not in place'; end if;
  if (select count(*) from cron.job j where j.active and not exists (select 1 from pipeline.automation_catalogue a where a.jobname = j.jobname)) > 0 then raise exception 'post-check: an active job is not catalogued'; end if;
  v_res := security.aer_partial_admit_v1();
  if coalesce((v_res->>'errors')::int, 0) > 0 then raise exception 'post-check: the first partial admission run had errors: %', v_res; end if;
  if (select count(*) from cron.job where active) <> v_jobs then raise exception 'post-check: the active job count changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> v_locks then raise exception 'post-check: the manual locks changed'; end if;
  if exists (select 1 from catalogue.provider_entry_matrix m join pipeline.aer_matrix_machine_admissions a on m.id::text in (select jsonb_array_elements_text(a.checks->'admitted_row_ids'))
              where a.rule = 'aer-partial-v1' and a.created_at >= now() and m.course_id is not null
                and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field in ('entry_requirements', 'all'))) then
    raise exception 'post-check: a row of a locked course was admitted'; end if;
  raise notice 's914-s916: first partial admission run %; % active jobs; % manual locks', v_res, v_jobs, v_locks;
end $s914$;
