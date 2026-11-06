-- Guards: Platform Admin decision 5 Nov 2026 20:03 (fold intake into the generic progress observer) and the Integration Controller's condition that the
-- scholarship and admission-requirements chains are byte for byte unchanged in their outputs. Isolated PostgreSQL only.
-- 1 Synthetic rows in every table the live security.progress_measure_v1 reads (production shapes, progress-tables.sql): each text column bound by a
--   check takes its allowed values in turn; other text columns take the literals the live measure function compares with, in turn, so the counts are
--   not trivially zero. No production rows.
-- 2 In one transaction (one now()): every existing key measured and the generic observer's reading of the scholarship and AER chains taken with the
--   live definitions (md5 40c0c972 and f11ed22d); migration 20261106400000 applied; the same taken again; both must be identical. Rolled back.
\set ON_ERROR_STOP on
set client_min_messages = warning;
do $$
declare t text; c record; v_err text; v_lits text[]; v_cols text; v_vals text; i int; v_ok int; v_lit text[]; v_val text; v_n int := 0;
begin
  select array_agg(distinct m[1]) into v_lits from regexp_matches(pg_get_functiondef('security.progress_measure_v1(text,timestamp with time zone)'::regprocedure), '''([a-z][a-z0-9_]{1,40})''', 'g') m;
  foreach t in array array['catalogue.course_entry_requirements', 'pipeline.aer_gap_findings', 'pipeline.aer_schedule_runs', 'pipeline.aer_source_inventory', 'pipeline.coverage_provider_reconciliation',
    'pipeline.entry_matrix_runs', 'pipeline.entry_matrix_sources', 'pipeline.layer4_intervention_events', 'pipeline.layer4_interventions', 'pipeline.layer4_item_readiness',
    'pipeline.layer4_readiness_runs', 'pipeline.layer4_review_items', 'pipeline.layer4_supersessions', 'pipeline.release_job_verifications', 'pipeline.scholarship_admission_log',
    'pipeline.scholarship_ai_reviews', 'pipeline.scholarship_coverage_items', 'pipeline.scholarship_coverage_providers', 'pipeline.scholarship_coverage_recoveries',
    'pipeline.scholarship_coverage_state_codes', 'pipeline.scholarship_listing_members', 'pipeline.scholarship_listing_pages', 'pipeline.scholarship_page_candidates',
    'pipeline.work_items', 'scholarship.scholarships'] loop
    v_ok := 0;
    for i in 1 .. 40 loop
      v_cols := ''; v_vals := '';
      for c in select a.attname, format_type(a.atttypid, a.atttypmod) typ, a.attnotnull nn,
                      (select string_agg(pg_get_constraintdef(k.oid), ' ') from pg_constraint k where k.conrelid = a.attrelid and k.contype = 'c' and a.attnum = any (k.conkey)) chk
                 from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
                where a.attrelid = t::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = '' and coalesce(pg_get_expr(d.adbin, d.adrelid), '') !~ '^nextval'
                order by a.attnum loop
        v_lit := array(select m[1] from regexp_matches(coalesce(c.chk, ''), '''([^'']*)''::text', 'g') m);
        v_val := case
          when c.typ = 'uuid' then quote_literal(md5(c.attname || (i % 7))::uuid::text) || '::uuid'
          when c.typ like 'timestamp%' then 'now() - make_interval(hours => ' || (i * 3) || ')'
          when c.typ = 'date' then 'current_date - ' || i
          when c.typ in ('integer', 'bigint', 'smallint') then (i % 5)::text
          when c.typ like 'numeric%' then case when c.attname like '%percentage%' then '50' else ((i % 5) + 1)::text end
          when c.typ = 'boolean' then (i % 2 = 0)::text
          when c.typ = 'jsonb' then quote_literal(jsonb_build_object('classified', i % 3, 'n', i)::text) || '::jsonb'
          when c.typ in ('bigint[]', 'integer[]') then quote_literal('{' || i || '}')
          when c.typ = 'uuid[]' then quote_literal('{' || md5(c.attname || (i % 7))::uuid || '}')
          when c.typ like '%[]' then quote_literal('{' || v_lits[1 + i % cardinality(v_lits)] || '}')
          when c.typ like 'character(%' then quote_literal('AU')
          when c.chk like '%https?%' then quote_literal('https://example.edu.au/' || i)
          when c.chk like '% ~ %' then quote_literal(v_lits[1 + (i * 7 + length(c.attname)) % cardinality(v_lits)])
          when cardinality(v_lit) > 0 then quote_literal(v_lit[1 + i % cardinality(v_lit)])
          when c.attname in ('quote', 'description', 'name', 'title', 'subject', 'reason', 'actor_label', 'owner', 'owner_role', 'next_action', 'release', 'jobname', 'registered_by',
                             'root_cause', 'fingerprint', 'stable_key', 'url', 'url_norm', 'item_key', 'content_hash', 'entity', 'missing_fact', 'shape', 'justified_zero') then quote_literal(c.attname || '-' || i)
          else quote_literal(v_lits[1 + (i * 7 + length(c.attname)) % cardinality(v_lits)]) end;
        if c.chk like '%min_entry_score_basis%' and c.attname = 'min_entry_score' then v_val := 'null'; end if;
        if c.chk like '%grade_scale IS NOT NULL%' and c.attname = 'min_value' then v_val := 'null'; end if;
        v_cols := v_cols || case when v_cols = '' then '' else ', ' end || quote_ident(c.attname);
        v_vals := v_vals || case when v_vals = '' then '' else ', ' end || v_val;
      end loop;
      begin
        execute format('insert into %s (%s) values (%s)', t, v_cols, v_vals); v_ok := v_ok + 1;
      exception when others then v_err := sqlerrm || ' :: ' || left(v_vals, 400);
      end;
    end loop;
    if v_ok = 0 then raise exception 'FAIL synthetic rows: none accepted by % (%)', t, v_err; end if;
    v_n := v_n + v_ok;
  end loop;
  raise notice 'synthetic rows %', v_n;
end $$;
select 'PASS synthetic rows in the 25 tables the generic measure reads: ' || (select sum(n) from (
  select count(*) n from pipeline.work_items union all select count(*) from pipeline.layer4_review_items union all select count(*) from pipeline.scholarship_page_candidates
  union all select count(*) from scholarship.scholarships union all select count(*) from catalogue.course_entry_requirements union all select count(*) from pipeline.aer_gap_findings) x) || ' rows in six of them';

-- before: the live definitions, every existing key, and one reading of the observer (scholarship and AER chains)
begin;
select string_agg(k || '=' || (security.progress_measure_v1(k, now() - interval '24 hours') - case when k = 'first_run_verify' then 'eligible' else '' end)::text, '|' order by k) as m_before,
       security.progress_measure_v1('first_run_verify', now() - interval '24 hours')->>'eligible' as frv_before,
       string_agg(k || ':' || (security.progress_measure_v1(k, now() - interval '24 hours')->>'created'), ' ' order by k) as created_before
  from unnest(array['sch_classification', 'sch_source_recovery', 'sch_listing_traversal', 'sch_candidate_matching', 'sch_reading', 'sch_eligibility', 'sch_layer4',
                    'sch_admission', 'sch_publication', 'aer_source_discovery', 'aer_extraction', 'aer_completeness', 'aer_technical_correction', 'aer_layer4_review',
                    'aer_active_records', 'aer_publication', 'l4_interventions', 'l4_readiness', 'first_run_verify']) k \gset
savepoint s1;
select security.progress_read_v1() is not null as read_ok \gset
select md5(string_agg(row(t.key, t.chain, t.step, t.input_eligible, t.input_processed, t.output_created, t.output_rejected, t.rejected_reasons, t.output_parked, t.parked_next_actions,
              t.downstream_queued, t.output_admitted, t.output_published, t.last_advanced_at, t.zero_reason, t.zero_detail, t.stalled, t.stalled_since, t.measure_error, t.measured_at)::text, '|' order by t.key))
       || md5(coalesce((select string_agg(o.transition_key || o.measures::text || o.zero_reason || o.stalled, '|' order by o.transition_key) from pipeline.progress_observations o), ''))
       || md5(coalesce((select string_agg(i.fingerprint || i.layer || i.workstream || i.severity, '|' order by i.fingerprint) from pipeline.integration_issues i where i.fingerprint like 'stall:%'), '')) as r_before
  from pipeline.progress_transitions t where t.chain in ('scholarship', 'aer') \gset
rollback to savepoint s1;
-- the change
\i supabase/migrations/20261106400000_cf247_intake_automation_progress.sql
select string_agg(k || '=' || (security.progress_measure_v1(k, now() - interval '24 hours') - case when k = 'first_run_verify' then 'eligible' else '' end)::text, '|' order by k) as m_after,
       security.progress_measure_v1('first_run_verify', now() - interval '24 hours')->>'eligible' as frv_after
  from unnest(array['sch_classification', 'sch_source_recovery', 'sch_listing_traversal', 'sch_candidate_matching', 'sch_reading', 'sch_eligibility', 'sch_layer4',
                    'sch_admission', 'sch_publication', 'aer_source_discovery', 'aer_extraction', 'aer_completeness', 'aer_technical_correction', 'aer_layer4_review',
                    'aer_active_records', 'aer_publication', 'l4_interventions', 'l4_readiness', 'first_run_verify']) k \gset
savepoint s2;
select security.progress_read_v1() is not null as read_ok \gset
select md5(string_agg(row(t.key, t.chain, t.step, t.input_eligible, t.input_processed, t.output_created, t.output_rejected, t.rejected_reasons, t.output_parked, t.parked_next_actions,
              t.downstream_queued, t.output_admitted, t.output_published, t.last_advanced_at, t.zero_reason, t.zero_detail, t.stalled, t.stalled_since, t.measure_error, t.measured_at)::text, '|' order by t.key))
       || md5(coalesce((select string_agg(o.transition_key || o.measures::text || o.zero_reason || o.stalled, '|' order by o.transition_key) from pipeline.progress_observations o where o.transition_key not like 'intake%'), ''))
       || md5(coalesce((select string_agg(i.fingerprint || i.layer || i.workstream || i.severity, '|' order by i.fingerprint) from pipeline.integration_issues i where i.fingerprint like 'stall:%' and i.fingerprint not like 'stall:intake%'), '')) as r_after
  from pipeline.progress_transitions t where t.chain in ('scholarship', 'aer') \gset
rollback to savepoint s2;
-- the new definition is the old one with one block inserted: removing the intake branches gives back the live text exactly
select (select pg_get_functiondef('security.progress_measure_v1(text,timestamp with time zone)'::regprocedure)) as def_after \gset
rollback;
-- first_run_verify measures the observer itself: its eligible is the number of transitions it reads, 16 before and 19 after (the intake chain)
select case when :'m_before' = :'m_after' and :'frv_before' = '16' and :'frv_after' = '19'
            then 'PASS regression: all 19 existing measure keys give identical output before and after (md5 ' || md5(:'m_before') || '; created ' || :'created_before' || '); first_run_verify differs only in eligible, the transitions it reads (16 -> 19)'
            else 'FAIL regression: measure output changed (first_run_verify eligible ' || :'frv_before' || ' -> ' || :'frv_after' || ')' end as m_check \gset
\echo :m_check
select case when :'r_before' = :'r_after' then 'PASS regression: the observer''s reading of the scholarship and AER chains (transitions, observations, stall issues with layer and workstream) is identical'
            else 'FAIL regression: observer reading of scholarship or AER changed' end as r_check \gset
\echo :r_check
select case when md5(regexp_replace(:'def_after', E'  -- intake dates \\(Platform Admin decision 5 Nov 2026 20:03.*?(  else\n    raise exception ''no progress measure)', E'\\1', 's')) = '40c0c972abc353be8f6eee35c79750e9'
            then 'PASS structure: the new progress_measure_v1 minus the inserted intake block is the live definition (md5 40c0c972)'
            else 'FAIL structure: progress_measure_v1 changed outside the inserted intake block' end as s_check \gset
\echo :s_check
