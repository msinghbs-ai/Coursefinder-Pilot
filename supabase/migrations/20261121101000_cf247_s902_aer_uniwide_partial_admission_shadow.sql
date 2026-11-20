-- CF-247 s902 (Platform Admin 21 Nov 2026 07:48 AEDT, chat S1-Coverage-Unlock-UI-Notes; decision "New auto-admit rule, in shadow first for
-- 24 hours"): university-wide entry rows of an incomplete read, in shadow. Nothing is admitted by this change.
-- Live read 21 Nov 2026 09:30 AEDT (rolled back): 3,245 university-wide entry rows (course_id is null) are proposed at 55 providers. Of the 79
-- entry-matrix items waiting in Layer 4, the machine admission (security.aer_matrix_machine_check_v1) stops 57 at the completeness gate D-R3
-- (gate_incomplete): every check before the gate has passed for them (no manual lock, no earlier rejection, stored copy present and current,
-- fetched from the official address, source on the provider's own website host, host not shared with another provider), but the reader
-- dropped a published row, so the whole read stays with a person. Charles Sturt University is one: 7 rows read, Hong Kong dropped.
-- The rule this shadow measures: for such an item (stopped only by completeness), admit every proposed university-wide row that passes every
-- row rule of the machine admission (confidence, quote length, mapped level, a published minimum, the minimum in the quote, no exclusion), and
-- leave the countries the read dropped as a gap for a person. In shadow it records, once an hour, what it would admit and why
-- (pipeline.aer_uniwide_partial_shadow) and admits nothing. A cutover is a separate change after a 24-hour shadow and the Platform Admin's
-- decision; this change cannot switch it on (A passing qualification never switches anything on by itself).
-- Decision 276 (AER v1 frozen): no reader, word list or recovery path is added; this is an admission measurement over existing reads.
-- Runs as a rule of admission-rule-runner (no new cron job: the active job count is unchanged).
-- Replaces: nothing.
-- Retires: nothing.
-- G1: the rule is catalogued (pipeline.automation_catalogue) and registered. G2: switch aer.uniwide_partial_shadow_on and batch
-- batch.aer_uniwide_partial_shadow are settings; no number in the call. G3: no consumer object (75/48). Nothing dropped or deleted. No spend.

create table if not exists pipeline.aer_uniwide_partial_shadow (
  review_item_id uuid primary key,
  provider_id uuid not null,
  run_id uuid,
  machine_rule text not null,
  rows_proposed int not null default 0,
  would_admit int not null default 0,
  would_admit_ids uuid[] not null default '{}',
  held_back jsonb not null default '{}'::jsonb,
  countries_missing text[] not null default '{}',
  checks jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  times_seen int not null default 1
);
comment on table pipeline.aer_uniwide_partial_shadow is 'CF-247 s902 (shadow, admits nothing): for each entry-matrix item waiting in Layer 4, what the university-wide partial admission rule would admit (rows passing every machine row rule when only completeness stops the read) and the countries the read dropped. Written hourly by security.aer_uniwide_partial_shadow_v1 (rule aer-uniwide-partial-shadow); read by security.aer_uniwide_partial_shadow_report_v1.';
create index if not exists aer_uniwide_partial_shadow_provider_idx on pipeline.aer_uniwide_partial_shadow (provider_id);
alter table pipeline.aer_uniwide_partial_shadow enable row level security;
revoke all on table pipeline.aer_uniwide_partial_shadow from public, anon, authenticated;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.uniwide_partial_shadow_on', 'Entry requirements: measure university-wide partial admission (shadow)',
  '1: once an hour, record which proposed university-wide entry rows would be admitted when only completeness stops a read (rows passing every machine row rule; the dropped countries stay with a person). Records only; admits nothing. 0: off.',
  'number', '1'::jsonb, 0, 1, 'on/off', 1499, 'Entry requirements', 'security.aer_uniwide_partial_shadow_v1 (rule aer-uniwide-partial-shadow)',
  'CF-247 s902 (Platform Admin 21 Nov 2026 07:48): 24-hour shadow before any cutover'),
 ('pipeline', 'batch.aer_uniwide_partial_shadow', 'Entry requirements: items measured a run (university-wide partial admission shadow)',
  'Most entry-matrix items waiting in Layer 4 that one shadow run looks at, oldest first.',
  'number', '200'::jsonb, 1, 500, 'items', 1500, 'Entry requirements', 'security.aer_uniwide_partial_shadow_v1 (rule aer-uniwide-partial-shadow)',
  'CF-247 s902 (Platform Admin 21 Nov 2026 07:48)')
on conflict (toolset_key, key) do nothing;

create or replace function security.aer_uniwide_partial_shadow_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare
  v_batch int := greatest(1, security.pipeline_num_v1('batch.aer_uniwide_partial_shadow', 200)::int);
  v_conf numeric := security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9);
  v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int;
  r record; c jsonb; v_run uuid; v_ex jsonb; v_exids uuid[]; v_inh uuid[]; v_cmp uuid[]; v_ok uuid[]; v_held jsonb; v_n int; v_seen int := 0; v_items int := 0; v_rows int := 0;
begin
  if security.pipeline_num_v1('aer.uniwide_partial_shadow_on', 1) < 1 then return jsonb_build_object('on', false); end if;
  for r in select i.id, i.entity_id from pipeline.layer4_review_items i
            where i.status = 'pending' and i.field_code = 'entry_matrix_first_run' and i.entity_type = 'provider'
            order by i.created_at, i.id limit v_batch loop
    v_seen := v_seen + 1;
    c := security.aer_matrix_machine_check_v1(r.id);
    select x.id into v_run from pipeline.entry_matrix_runs x where x.review_item_id = r.id limit 1;
    v_ok := '{}'; v_held := '{}'::jsonb; v_n := 0;
    if c->>'rule' in ('gate_incomplete', 'completeness') and v_run is not null then
      v_ex := security.aer_matrix_machine_exclusions_v1(v_run);
      v_exids := coalesce(array(select jsonb_array_elements_text(v_ex->'ids')::uuid), '{}'::uuid[]);
      v_inh := coalesce(array(select jsonb_array_elements_text(v_ex->'level_inherit_ids')::uuid), '{}'::uuid[]);
      v_cmp := coalesce(array(select jsonb_array_elements_text(v_ex->'completion_only_ids')::uuid), '{}'::uuid[]);
      -- the machine admission's own row rules, in its order; a row that fails none would be admitted
      with x as (
        select m.id, case
            when m.id = any(v_exids) then 'excluded_by_rule'
            when coalesce(m.confidence, 0) < v_conf then 'low_confidence'
            when length(btrim(coalesce(m.quote, ''))) < v_qmin then 'short_quote'
            when m.study_level_id is null and not (m.id = any(v_inh)) then 'level_unmapped'
            when not (m.id = any(v_cmp)) and not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
            when not (m.id = any(v_cmp)) and not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote'
          end why
          from catalogue.provider_entry_matrix m
         where m.run_id = v_run and m.status = 'proposed' and m.course_id is null)
      select coalesce(array_agg(x.id) filter (where x.why is null), '{}'),
             coalesce((select jsonb_object_agg(z.why, z.n) from (select y.why, count(*) n from x y where y.why is not null group by y.why) z), '{}'::jsonb),
             count(*)
        into v_ok, v_held, v_n from x;
    elsif v_run is not null then
      select count(*) into v_n from catalogue.provider_entry_matrix m where m.run_id = v_run and m.status = 'proposed' and m.course_id is null;
    end if;
    insert into pipeline.aer_uniwide_partial_shadow as s (review_item_id, provider_id, run_id, machine_rule, rows_proposed, would_admit, would_admit_ids, held_back, countries_missing, checks)
    values (r.id, r.entity_id, v_run, coalesce(c->>'rule', case when (c->>'ok')::boolean then 'machine_admits' else 'unknown' end), v_n, cardinality(v_ok), v_ok, v_held,
            coalesce(array(select jsonb_array_elements_text(c->'checks'->'gate'->'countries_missing')), '{}'), coalesce(c->'checks', '{}'::jsonb))
    on conflict (review_item_id) do update set run_id = excluded.run_id, machine_rule = excluded.machine_rule, rows_proposed = excluded.rows_proposed,
      would_admit = excluded.would_admit, would_admit_ids = excluded.would_admit_ids, held_back = excluded.held_back, countries_missing = excluded.countries_missing,
      checks = excluded.checks, last_seen_at = now(), times_seen = s.times_seen + 1;
    if cardinality(v_ok) > 0 then v_items := v_items + 1; v_rows := v_rows + cardinality(v_ok); end if;
  end loop;
  return jsonb_build_object('on', true, 'shadow', true, 'admitted', 0, 'looked_at', v_seen, 'items_would_admit', v_items, 'rows_would_admit', v_rows, 'at', now());
end $f$;
revoke all on function security.aer_uniwide_partial_shadow_v1() from public, anon, authenticated;
comment on function security.aer_uniwide_partial_shadow_v1() is 'CF-247 s902 (shadow): records, per waiting entry-matrix item, the university-wide rows the partial admission rule would admit (only completeness stops the read; every machine row rule passes) and the dropped countries. Admits nothing. Rule aer-uniwide-partial-shadow of admission-rule-runner.';

create or replace function security.aer_uniwide_partial_shadow_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object(
    'items', count(*), 'items_would_admit', count(*) filter (where s.would_admit > 0),
    'providers_would_admit', count(distinct s.provider_id) filter (where s.would_admit > 0),
    'rows_would_admit', coalesce(sum(s.would_admit), 0), 'rows_proposed', coalesce(sum(s.rows_proposed), 0),
    'by_machine_rule', coalesce((select jsonb_object_agg(z.machine_rule, z.n) from (select machine_rule, count(*) n from pipeline.aer_uniwide_partial_shadow group by 1) z), '{}'::jsonb),
    'held_back', coalesce((select jsonb_object_agg(z.k, z.n) from (select e.key k, sum(e.value::int) n from pipeline.aer_uniwide_partial_shadow s2, jsonb_each_text(s2.held_back) e group by 1) z), '{}'::jsonb),
    'countries_missing', coalesce((select jsonb_object_agg(z.cc, z.n) from (select u.cc, count(*) n from pipeline.aer_uniwide_partial_shadow s3, unnest(s3.countries_missing) u(cc) group by 1) z), '{}'::jsonb),
    'first_seen', min(s.first_seen_at), 'last_seen', max(s.last_seen_at), 'admitted', 0)
  from pipeline.aer_uniwide_partial_shadow s
$f$;
revoke all on function security.aer_uniwide_partial_shadow_report_v1() from public, anon, authenticated;
comment on function security.aer_uniwide_partial_shadow_report_v1() is 'CF-247 s902: the shadow report of the university-wide partial admission rule (items, providers and rows it would admit, rows held back by row rule, countries dropped). Read for the 24-hour cutover decision.';

-- the rule: a live dispatcher target whose call only records (it is the shadow)
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-uniwide-partial-shadow', 'Admission', 21, 'Entry requirements: university-wide partial admission (shadow)',
  'Every hour at :33, as a rule of admission-rule-runner: while aer.uniwide_partial_shadow_on is 1, looks at up to batch.aer_uniwide_partial_shadow entry-matrix items waiting in Layer 4 and records which university-wide rows would be admitted when only completeness stops the read (every machine row rule passes; dropped countries stay with a person). Records only; admits nothing (24-hour shadow, s902).',
  6, true, null)
on conflict (jobname) do nothing;

insert into pipeline.admission_rules (rule_code, legacy_job, call_sql, call_md5, schedule, priority, mode, budget_ms, expected_ms, note)
values ('aer-uniwide-partial-shadow', 'aer-uniwide-partial-shadow', 'select security.aer_uniwide_partial_shadow_v1()', md5('select security.aer_uniwide_partial_shadow_v1()'),
        '33 * * * *', 60, 'live', 60000, 15000, 'CF-247 s902: shadow measurement only (records, admits nothing); added 21 Nov 2026 (Platform Admin 07:48)')
on conflict (rule_code) do nothing;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'aer-uniwide-partial-shadow', 'Layer 4', 'Admission', 'CF-247 s902: university-wide partial admission of entry rows, in shadow (admission-rule-runner rule; records only)', 'active', '{}', '20261121101000'),
 ('table', 'pipeline.aer_uniwide_partial_shadow', 'Layer 4', 'Admission', 'CF-247 s902: what the university-wide partial admission rule would admit, per waiting item', 'active', '{}', '20261121101000'),
 ('function', 'security.aer_uniwide_partial_shadow_v1', 'Layer 4', 'Admission', 'CF-247 s902: the shadow run (records only)', 'active', '{}', '20261121101000'),
 ('function', 'security.aer_uniwide_partial_shadow_report_v1', 'Layer 4', 'Admission', 'CF-247 s902: the shadow report', 'active', '{}', '20261121101000')
on conflict do nothing;

-- post-checks: one run records and admits nothing; the active job count is unchanged
do $s902$
declare v_res jsonb; v_active_before int := (select count(*) from catalogue.provider_entry_matrix where status = 'active'); v_jobs int := (select count(*) from cron.job where active);
begin
  v_res := security.aer_uniwide_partial_shadow_v1();
  if (select count(*) from catalogue.provider_entry_matrix where status = 'active') <> v_active_before then raise exception 'post-check: the shadow changed an entry row'; end if;
  if (select count(*) from cron.job where active) <> v_jobs then raise exception 'post-check: the active job count changed'; end if;
  if not exists (select 1 from pipeline.admission_rules where rule_code = 'aer-uniwide-partial-shadow' and enabled and call_md5 = md5(call_sql)) then
    raise exception 'post-check: the rule is not registered';
  end if;
  raise notice 's902: first shadow run %; report %', v_res, security.aer_uniwide_partial_shadow_report_v1();
end $s902$;
