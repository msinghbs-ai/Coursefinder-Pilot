-- Fixture helpers (shape only, no live data): a waiting course read cut at the row limit whose stored corrected read kept all 9 rows (the Diploma of Commerce
-- shape of the aer-technical-holds fixture). With the university's row limit at 9 the replay can recover it, so the replay creates a new waiting item.
\set ON_ERROR_STOP 1
create or replace function public.fx_seed(p_course uuid, p_title text) returns uuid language plpgsql as $f$
declare v_item uuid := gen_random_uuid(); v_job uuid := gen_random_uuid(); i int; q text[] := array[
  'You must have completed an Australian Year 12 or equivalent with a minimum average of 50 percent.', 'You must have completed the Victorian Certificate of Education (VCE) or equivalent.',
  'Successful completion of an approved pathway qualification guarantees entry.', 'You must have completed at least two undergraduate courses at an Australian university.',
  'Equivalent qualifications include the RMIT Foundation Studies program.', 'Prerequisites VCE units 3 and 4: a study score of at least 20 in English.',
  'You may satisfy the academic requirements by completing the STAT multiple choice.', 'There are no prerequisite subjects required for entry into this qualification.',
  'A selection task is not required for entry into this qualification.'];
begin
  insert into catalogue.courses(id, provider_id, canonical_title) values (p_course, 'd1000000-0000-4000-8000-000000000000', p_title);
  insert into pipeline.coverage_course_pages(course_id, provider_id, url) values (p_course, 'd1000000-0000-4000-8000-000000000000', 'https://uni.example/' || p_course);
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, proposed_value, evidence_id)
  values (v_item, 'course', p_course, 'course_entry_first_read', 'pending',
          jsonb_build_object('url', 'https://uni.example/' || p_course, 'rows', 6, 'limit', 6,
            'dropped', (select jsonb_agg(jsonb_build_object('reason', 'over_row_limit', 'kind', 'general_note', 'quote', q[n])) from generate_series(7, 9) n)), null);
  for i in 1 .. 6 loop
    insert into catalogue.course_entry_requirements(course_id, kind, audience, description, quote, confidence, status, provenance)
    values (p_course, case when i = 6 then 'subject_prerequisite' else 'prior_qualification' end, 'all', q[i], q[i], 0.95, 'proposed', jsonb_build_object('review_item_id', v_item));
  end loop;
  insert into pipeline.admin_jobs(id, kind, lane, state, requested_by) values (v_job, 'enrich_fields', 'enrich', 'done', 'c0ffee00-0000-4000-8000-000000000150');
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, reason, value)
  values (v_job, 'd1000000-0000-4000-8000-000000000000', p_course, 'entry_requirements', 'skipped', 'held_partial: over_row_limit: the page has 9 requirements and the limit is 6',
          jsonb_build_object('held', 'over_row_limit', 'limit', 6,
            'rows_read', (select jsonb_agg(jsonb_build_object('kind', case when n = 6 then 'subject_prerequisite' else 'prior_qualification' end, 'audience', 'all', 'description', q[n], 'quote', q[n], 'confidence', 0.95, 'min_entry_score', null)) from generate_series(1, 9) n),
            'dropped', (select jsonb_agg(jsonb_build_object('reason', 'over_row_limit', 'kind', 'general_note', 'quote', q[n])) from generate_series(7, 9) n)));
  -- the readiness run has gated it (the gate holds the read: dropped requirements no row covers)
  insert into pipeline.layer4_item_readiness(item_id, gate, gate_checked_at, readiness) values (v_item, security.course_entry_gate_v1(v_item), now(), 'technical_blocked')
  on conflict (item_id) do update set gate = excluded.gate;
  return v_item;
end $f$;
