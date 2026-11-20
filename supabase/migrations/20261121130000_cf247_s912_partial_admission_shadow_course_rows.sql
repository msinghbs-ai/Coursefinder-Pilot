-- CF-247 s912 (Platform Admin 21 Nov 2026 09:57 AEDT, chat S1-Coverage-Unlock-UI-Notes): partial entry-table admission is approved,
-- superseding the all-or-nothing completeness hold (D-R3) under Decision 276: "admit all country rows in a university-wide or course entry
-- table that pass domain, identity, and source-evidence checks, while holding only the missing or unverified country rows in Layer 4 for
-- human review. Proceed with the 24-hour shadow report and cutover tomorrow at 09:30 AEDT."
-- The s902 shadow measured university-wide rows only. So that the shadow measures what the cutover will admit, it now counts every proposed
-- row of the read (university-wide and course rows), with the course rows also shown on their own. It still records only; admits nothing.
-- The cutover (22 Nov 2026 09:30 AEDT) is a separate change.
-- Replaces: security.aer_uniwide_partial_shadow_v1 and security.aer_uniwide_partial_shadow_report_v1 (same names; this lane's own s902 functions).
-- Retires: nothing.
-- G1: no job (the rule aer-uniwide-partial-shadow is unchanged). G2: no new setting or number. G3: no consumer object (75/48).
-- Nothing dropped or deleted. No spend.

alter table pipeline.aer_uniwide_partial_shadow add column if not exists course_rows_proposed int not null default 0;
alter table pipeline.aer_uniwide_partial_shadow add column if not exists course_would_admit int not null default 0;
comment on table pipeline.aer_uniwide_partial_shadow is 'CF-247 s902/s912 (shadow, admits nothing): for each entry-matrix item waiting in Layer 4, what the partial admission rule would admit (university-wide and course rows passing every machine row rule when only completeness stops the read; course rows also counted on their own) and the countries the read dropped. Written hourly by security.aer_uniwide_partial_shadow_v1 (rule aer-uniwide-partial-shadow); read by security.aer_uniwide_partial_shadow_report_v1.';

create or replace function security.aer_uniwide_partial_shadow_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare
  v_batch int := greatest(1, security.pipeline_num_v1('batch.aer_uniwide_partial_shadow', 200)::int);
  v_conf numeric := security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9);
  v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int;
  r record; c jsonb; v_run uuid; v_course int; v_course_n int; v_ex jsonb; v_exids uuid[]; v_inh uuid[]; v_cmp uuid[]; v_ok uuid[]; v_held jsonb; v_n int; v_seen int := 0; v_items int := 0; v_rows int := 0;
begin
  if security.pipeline_num_v1('aer.uniwide_partial_shadow_on', 1) < 1 then return jsonb_build_object('on', false); end if;
  for r in select i.id, i.entity_id from pipeline.layer4_review_items i
            where i.status = 'pending' and i.field_code = 'entry_matrix_first_run' and i.entity_type = 'provider'
            order by i.created_at, i.id limit v_batch loop
    v_seen := v_seen + 1;
    c := security.aer_matrix_machine_check_v1(r.id);
    select x.id into v_run from pipeline.entry_matrix_runs x where x.review_item_id = r.id limit 1;
    v_ok := '{}'; v_held := '{}'::jsonb; v_n := 0; v_course := 0; v_course_n := 0;
    if c->>'rule' in ('gate_incomplete', 'completeness') and v_run is not null then
      v_ex := security.aer_matrix_machine_exclusions_v1(v_run);
      v_exids := coalesce(array(select jsonb_array_elements_text(v_ex->'ids')::uuid), '{}'::uuid[]);
      v_inh := coalesce(array(select jsonb_array_elements_text(v_ex->'level_inherit_ids')::uuid), '{}'::uuid[]);
      v_cmp := coalesce(array(select jsonb_array_elements_text(v_ex->'completion_only_ids')::uuid), '{}'::uuid[]);
      -- the machine admission's own row rules, in its order; a row that fails none would be admitted
      with x as (
        select m.id, m.course_id is not null course_row, case
            when m.id = any(v_exids) then 'excluded_by_rule'
            when coalesce(m.confidence, 0) < v_conf then 'low_confidence'
            when length(btrim(coalesce(m.quote, ''))) < v_qmin then 'short_quote'
            when m.study_level_id is null and not (m.id = any(v_inh)) then 'level_unmapped'
            when not (m.id = any(v_cmp)) and not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
            when not (m.id = any(v_cmp)) and not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote'
          end why
          from catalogue.provider_entry_matrix m
         where m.run_id = v_run and m.status = 'proposed')  -- s912: university-wide and course rows of the read (Platform Admin 21 Nov 09:57)
      select coalesce(array_agg(x.id) filter (where x.why is null), '{}'),
             coalesce((select jsonb_object_agg(z.why, z.n) from (select y.why, count(*) n from x y where y.why is not null group by y.why) z), '{}'::jsonb),
             count(*), count(*) filter (where x.why is null and x.course_row), count(*) filter (where x.course_row)
        into v_ok, v_held, v_n, v_course, v_course_n from x;
    elsif v_run is not null then
      select count(*), count(*) filter (where m.course_id is not null) into v_n, v_course_n from catalogue.provider_entry_matrix m where m.run_id = v_run and m.status = 'proposed';
    end if;
    insert into pipeline.aer_uniwide_partial_shadow as s (review_item_id, provider_id, run_id, machine_rule, rows_proposed, would_admit, would_admit_ids, held_back, countries_missing, checks, course_rows_proposed, course_would_admit)
    values (r.id, r.entity_id, v_run, coalesce(c->>'rule', case when (c->>'ok')::boolean then 'machine_admits' else 'unknown' end), v_n, cardinality(v_ok), v_ok, v_held,
            coalesce(array(select jsonb_array_elements_text(c->'checks'->'gate'->'countries_missing')), '{}'), coalesce(c->'checks', '{}'::jsonb), v_course_n, v_course)
    on conflict (review_item_id) do update set run_id = excluded.run_id, machine_rule = excluded.machine_rule, rows_proposed = excluded.rows_proposed,
      would_admit = excluded.would_admit, would_admit_ids = excluded.would_admit_ids, held_back = excluded.held_back, countries_missing = excluded.countries_missing,
      checks = excluded.checks, course_rows_proposed = excluded.course_rows_proposed, course_would_admit = excluded.course_would_admit,
      last_seen_at = now(), times_seen = s.times_seen + 1;
    if cardinality(v_ok) > 0 then v_items := v_items + 1; v_rows := v_rows + cardinality(v_ok); end if;
  end loop;
  return jsonb_build_object('on', true, 'shadow', true, 'admitted', 0, 'looked_at', v_seen, 'items_would_admit', v_items, 'rows_would_admit', v_rows, 'at', now());
end $f$;
revoke all on function security.aer_uniwide_partial_shadow_v1() from public, anon, authenticated;
create or replace function security.aer_uniwide_partial_shadow_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object(
    'items', count(*), 'items_would_admit', count(*) filter (where s.would_admit > 0),
    'providers_would_admit', count(distinct s.provider_id) filter (where s.would_admit > 0),
    'rows_would_admit', coalesce(sum(s.would_admit), 0), 'rows_proposed', coalesce(sum(s.rows_proposed), 0),
    'course_rows_would_admit', coalesce(sum(s.course_would_admit), 0), 'course_rows_proposed', coalesce(sum(s.course_rows_proposed), 0),
    'scope', 'university-wide and course rows (s912)',
    'by_machine_rule', coalesce((select jsonb_object_agg(z.machine_rule, z.n) from (select machine_rule, count(*) n from pipeline.aer_uniwide_partial_shadow group by 1) z), '{}'::jsonb),
    'held_back', coalesce((select jsonb_object_agg(z.k, z.n) from (select e.key k, sum(e.value::int) n from pipeline.aer_uniwide_partial_shadow s2, jsonb_each_text(s2.held_back) e group by 1) z), '{}'::jsonb),
    'countries_missing', coalesce((select jsonb_object_agg(z.cc, z.n) from (select u.cc, count(*) n from pipeline.aer_uniwide_partial_shadow s3, unnest(s3.countries_missing) u(cc) group by 1) z), '{}'::jsonb),
    'first_seen', min(s.first_seen_at), 'last_seen', max(s.last_seen_at), 'admitted', 0)
  from pipeline.aer_uniwide_partial_shadow s
$f$;
revoke all on function security.aer_uniwide_partial_shadow_report_v1() from public, anon, authenticated;
comment on function security.aer_uniwide_partial_shadow_v1() is 'CF-247 s902/s912 (shadow): records, per waiting entry-matrix item, the university-wide and course rows the partial admission rule would admit (only completeness stops the read; every machine row rule passes) and the dropped countries. Admits nothing. Rule aer-uniwide-partial-shadow of admission-rule-runner.';

update pipeline.automation_catalogue
   set description = replace(description, 'records which university-wide rows would be admitted', 'records which university-wide and course rows would be admitted')
 where jobname = 'aer-uniwide-partial-shadow';

-- post-checks: one run records (course rows included) and admits nothing
do $s912$
declare v_res jsonb; v_active int := (select count(*) from catalogue.provider_entry_matrix where status = 'active'); v_jobs int := (select count(*) from cron.job where active);
begin
  v_res := security.aer_uniwide_partial_shadow_v1();
  if (select count(*) from catalogue.provider_entry_matrix where status = 'active') <> v_active then raise exception 'post-check: the shadow changed an entry row'; end if;
  if (select count(*) from cron.job where active) <> v_jobs then raise exception 'post-check: the active job count changed'; end if;
  if (security.aer_uniwide_partial_shadow_report_v1()->>'scope') is null then raise exception 'post-check: the report does not carry the scope'; end if;
  raise notice 's912: shadow run %; report %', v_res, security.aer_uniwide_partial_shadow_report_v1();
end $s912$;
