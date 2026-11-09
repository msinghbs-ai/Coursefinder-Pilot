-- Guards: F-INT D3 forward fix (Platform Admin decision 9 Nov 2026): migration 20261109170000 applied ONCE with the switch ON, on the production-equivalent fixture (2,929 decision rows, 14 named cases).
-- Proves: exactly the expected rows get a revisit time (worked out independently of the migration), nothing else changes in any row, locked / withdrawn / rejected rows are untouched, the record
-- (batch, log, previous and new values), the md5 checksum recomputed from the table, the spread over intake_dates.revisit_days, no switch or setting is changed, the privileges and the register.
\set ON_ERROR_STOP on
\set QUIET on
do $$
declare b record; v_exp uuid[]; v_chg uuid[]; v_log uuid[]; v_days numeric := (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.revisit_days');
        v_sum text; n int; v_left text;
begin
  select count(*) into n from pipeline.intake_revisit_backfill_batches; if n <> 1 then raise exception 'batches: %', n; end if;
  select * into b from pipeline.intake_revisit_backfill_batches;
  -- the expected set, from the state before the migration and the named exclusions only
  select array_agg(p.intake_id order by p.intake_id) into v_exp from public.rb_pre p
   where p.undated_active and p.next_revisit_at is null and p.next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required')
     and p.intake_id not in (select intake_id from public.rb_cases where name in ('locked_by_hand', 'withdrawn_event', 'withdrawn_reason', 'rejected_reading', 'rejected_reason'))
     -- the fixture (as production) also holds courses locked by hand for their intakes: not part of the expected set either
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p.course_id and k.field in ('intakes', 'intake'));
  select array_agg(x order by x) into v_chg from public.rb_diff('seeded') x;
  select array_agg(g.intake_id order by g.intake_id) into v_log from pipeline.intake_revisit_backfill_log g where g.batch_id = b.batch_id;
  if v_exp is distinct from v_chg then raise exception 'changed rows (%) are not the expected rows (%)', cardinality(v_chg), cardinality(v_exp); end if;
  if v_exp is distinct from v_log then raise exception 'logged rows (%) are not the expected rows (%)', cardinality(v_log), cardinality(v_exp); end if;
  if b.status <> 'applied' or b.candidate_count <> cardinality(v_exp) or b.rows_changed <> cardinality(v_exp) or b.switch_value <> 1 or b.migration_version <> '20261109170000' then raise exception 'batch: %', row_to_json(b); end if;
  if cardinality(v_exp) < 2000 then raise exception 'fixture too small: % rows', cardinality(v_exp); end if;
  raise notice 'PASS expected rows: % of the fixture''s decision rows got a revisit time, the same % rows as an independent query over the pre-migration state and the same rows as the log (set equality)', cardinality(v_exp), cardinality(v_exp);

  -- the original predicate selected more rows: the five named exclusions and the fixture's three hand-locked courses are exactly those
  select count(*) into n from public.rb_pre p where p.undated_active and p.next_revisit_at is null and p.next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required')
     and p.intake_id not in (select intake_id from public.rb_cases where name in ('locked_by_hand')) and exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p.course_id and k.field in ('intakes', 'intake'));
  if b.live_predicate_count - b.candidate_count <> 5 + n then raise exception 'original predicate % vs candidates % (expected % apart)', b.live_predicate_count, b.candidate_count, 5 + n; end if;
  raise notice 'PASS bound: the candidates (%) do not exceed the rows the original step-6 predicate selects (%); the % rows apart are the hand-locked, withdrawn and rejected rows (5 named cases and % courses the fixture already holds locked)', b.candidate_count, b.live_predicate_count, b.live_predicate_count - b.candidate_count, n;

  -- nothing else: no other column of any row changed, the excluded and control rows are identical
  if exists (select 1 from public.rb_diff_other('seeded')) then raise exception 'a column other than next_revisit_at changed on % rows', (select count(*) from public.rb_diff_other('seeded')); end if;
  select string_agg(c.name, ',') into v_left from public.rb_cases c where c.intake_id in (select x from public.rb_diff('seeded') x) and c.name not in ('tamper_pick', 'edited_since_a', 'edited_since_b');
  if v_left is not null then raise exception 'cases changed that must be left alone: %', v_left; end if;
  if (select count(*) from public.rb_cases c where c.intake_id in (select x from public.rb_diff('seeded') x)) <> 3 then raise exception 'the three ordinary candidate cases are not the only named cases changed'; end if;
  raise notice 'PASS untouched: no column other than next_revisit_at changed in any of % rows; locked_by_hand, withdrawn_event, withdrawn_reason, withdrawn_status, rejected_reading, rejected_reason, fully_dated, inactive_course, already_timed, other_action and no_action are identical to before', (select count(*) from pipeline.course_intake_dates);

  -- only from null, previous recorded, new value in the spread window
  if exists (select 1 from pipeline.intake_revisit_backfill_log g where g.batch_id = b.batch_id and g.previous_next_revisit_at is not null) then raise exception 'a previous value is not null'; end if;
  if exists (select 1 from pipeline.intake_revisit_backfill_log g join pipeline.course_intake_dates d using (intake_id) where g.batch_id = b.batch_id and d.next_revisit_at is distinct from g.new_next_revisit_at) then raise exception 'log new value differs from the row'; end if;
  if exists (select 1 from pipeline.intake_revisit_backfill_log g where g.batch_id = b.batch_id and (g.new_next_revisit_at < b.created_at or g.new_next_revisit_at > b.created_at + v_days * interval '1 day')) then raise exception 'a new value is outside the spread window'; end if;
  select count(distinct new_next_revisit_at) into n from pipeline.intake_revisit_backfill_log where batch_id = b.batch_id;
  if n < b.candidate_count * 0.8 or (select max(new_next_revisit_at) - min(new_next_revisit_at) from pipeline.intake_revisit_backfill_log where batch_id = b.batch_id) < (v_days - 2) * interval '1 day' then raise exception 'no spread: % distinct values', n; end if;
  raise notice 'PASS spread: every new time lies within intake_dates.revisit_days (% days) of the run, % distinct times over the span (no storm); previous values recorded (all null)', v_days, n;

  -- the checksum, recomputed here from the table
  select md5(string_agg(d.intake_id::text || '=' || to_char(d.next_revisit_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), '|' order by d.intake_id)) into v_sum
    from pipeline.course_intake_dates d where d.intake_id = any (v_exp);
  if v_sum is distinct from b.checksum_expected or v_sum is distinct from b.checksum_after then raise exception 'checksum % vs expected % / after %', v_sum, b.checksum_expected, b.checksum_after; end if;
  raise notice 'PASS checksum: md5 over (row, new value) = % recomputed from the table, equal to the planned and the stored-after checksum', v_sum;
  if b.elapsed_ms is null or b.elapsed_ms > 5000 then raise exception 'elapsed % ms', b.elapsed_ms; end if;
  raise notice 'PASS time: the backfill of % rows took % ms inside the migration (budget 5,000 ms)', b.rows_changed, b.elapsed_ms;
end $$;

-- no switch or setting changed by the migration; the switch is still the value the Platform Admin set
do $$
begin
  if exists (select 1 from (select * from pipeline.platform_toolset_settings except select * from public.rb_set) x) or exists (select 1 from (select * from public.rb_set except select * from pipeline.platform_toolset_settings) y) then
    raise exception 'a setting changed'; end if;
  if security.pipeline_num_v1('intake_dates.revisit_stored_inputs', 0) <> 1 then raise exception 'switch'; end if;
  raise notice 'PASS no self-enabling: every setting (% rows) is identical to before the migration; intake_dates.revisit_stored_inputs is still the value set by the Platform Admin (1)', (select count(*) from pipeline.platform_toolset_settings);
end $$;

-- privileges, comments, register, function surface
do $$
declare t text;
begin
  foreach t in array array['pipeline.intake_revisit_backfill_batches', 'pipeline.intake_revisit_backfill_log'] loop
    if not (select relrowsecurity from pg_class where oid = t::regclass) then raise exception '% has no RLS', t; end if;
    if has_table_privilege('anon', t, 'select') or has_table_privilege('authenticated', t, 'select') or has_table_privilege('anon', t, 'insert') or has_table_privilege('authenticated', t, 'update') then raise exception '% open to anon or authenticated', t; end if;
    if coalesce(obj_description(t::regclass, 'pg_class'), '') = '' then raise exception '% has no purpose', t; end if;
  end loop;
  if has_function_privilege('anon', 'security.intake_revisit_backfill_undo_v1(uuid)', 'execute') or has_function_privilege('authenticated', 'security.intake_revisit_backfill_undo_v1(uuid)', 'execute') then raise exception 'undo open'; end if;
  if has_function_privilege('anon', 'public.admin_intake_revisit_backfill_undo_v1(uuid,text)', 'execute') or not has_function_privilege('authenticated', 'public.admin_intake_revisit_backfill_undo_v1(uuid,text)', 'execute') then raise exception 'admin undo privilege'; end if;
  if (select count(*) from pipeline.component_register where introduced_in = '20261109170000') <> 4 then raise exception 'register'; end if;
  raise notice 'PASS surface: both tables have RLS, a purpose and no anon or authenticated access (same as pipeline.intake_date_rejections); the undo is not executable by anon or authenticated; the Platform Admin call is executable by authenticated only; 4 register rows';
end $$;
insert into public.rb_snap select 'after_first', d.intake_id, to_jsonb(d)::text from pipeline.course_intake_dates d;
