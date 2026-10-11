CREATE OR REPLACE FUNCTION public.admin_scholarship_record_read(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return (
    -- 11 Oct 2026: publishing checks for this scholarship only (was every scholarship, about 3.6 s); the evidence journey added
    with pub as (select * from security.scholarship_publishability_for_v1(array[p_id]) x where x.scholarship_id = p_id),
    pg as (select * from pipeline.scholarship_pages sp where sp.scholarship_id = p_id),
    ev as (select e.* from pipeline.evidence_artifacts e where e.id = (select pg.evidence_id from pg))
    select jsonb_build_object(
      'id', s.id, 'name', s.name, 'provider_id', s.provider_id, 'provider', coalesce(pr.display_name, pr.canonical_name),
      'can_edit', v_rank >= 3,
      'status', case when s.lifecycle_status <> 'active' then 'inactive' when s.publication_status = 'published' then 'published' when coalesce((select publishable from pub), false) then 'ready' else 'held' end,
      'held_reasons', coalesce((select missing from pub), '{}'::text[]),
      'publication_status', s.publication_status, 'lifecycle_status', s.lifecycle_status,
      'value_label', scholarship.value_label(s.id), 'page_words', s.award_value_text,
      'award_amount', s.award_amount, 'award_percentage', s.award_percentage, 'award_value_type', s.award_value_type, 'is_maximum', s.award_value_is_maximum,
      'tiers', (select coalesce(jsonb_agg(jsonb_build_object('label', t.label, 'percentage', t.percentage, 'amount', t.amount, 'currency', t.currency_code) order by t.display_order), '[]'::jsonb) from scholarship.award_tiers t where t.scholarship_id = s.id),
      'audience', s.audience,
      'audience_phrase', (select coalesce(a.phrase_both, nullif(concat_ws(' + ', a.phrase_international, a.phrase_domestic), '')) from scholarship.audience_readings a where a.scholarship_id = s.id),
      'nationalities', s.nationalities,
      'nationality_phrases', (select r.phrases from scholarship.nationality_readings r where r.scholarship_id = s.id),
      'nationality_terms', (select jsonb_agg(jsonb_build_object('code', t.code, 'name', split_part(t.names, '|', 1)) order by t.region, split_part(t.names, '|', 1)) from ref.nationality_terms t),
      'duration_basis', s.award_duration_basis,
      'application_required', s.application_required, 'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date,
      'application_open_precision', s.application_open_precision, 'application_close_precision', s.application_close_precision,
      'study_start_label', s.study_start_label, 'study_start_date', s.study_start_date,
      'page', s.source_url,
      'page_read_at', (select sp.read_at from pipeline.scholarship_pages sp where sp.scholarship_id = s.id),
      'courses', (select count(*) from scholarship.course_mappings m where m.scholarship_id = s.id and m.mapping_state = 'mapped'),
      'course_list', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'level', x.level, 'code', x.course_code, 'basis', x.mapping_basis, 'proof', x.proof, 'by_hand', x.mapped_by is not null) order by x.so, x.title), '[]'::jsonb)
                        from (select co.id, coalesce(co.display_title, co.canonical_title) title, sl.name level, coalesce(sl.sort_order, 99) so, co.course_code, m.mapping_basis, m.proof, m.mapped_by
                                from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                               where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active'
                               order by coalesce(sl.sort_order, 99), coalesce(co.display_title, co.canonical_title) limit 200) x),
      'course_levels', (select coalesce(jsonb_agg(jsonb_build_object('level', y.level, 'courses', y.n) order by y.so), '[]'::jsonb)
                          from (select coalesce(sl.name, 'Other') level, min(coalesce(sl.sort_order, 99)) so, count(*) n
                                  from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                                 where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active' group by 1) y),
      'criteria', (select coalesce(jsonb_agg(to_jsonb(cr) order by cr.criterion_type), '[]'::jsonb) from scholarship.criteria cr where cr.scholarship_id = s.id and cr.status = 'active'),
      -- the evidence journey: provider page, scraper read, saved copy, what was read from it and what it changed
      'evidence', (select jsonb_build_object(
          'url', pg.url, 'final_url', pg.final_url, 'found_by', pg.url_source, 'read_status', pg.read_status, 'fetched_via', pg.fetched_via,
          'http_status', pg.http_status, 'read_at', pg.read_at, 'next_read_at', pg.next_read_at, 'attempts', pg.attempts,
          'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'sch_scrape' and u.url = pg.url),
          'saved', (select jsonb_build_object('evidence_id', ev.id, 'captured_at', ev.captured_at, 'version', ev.capture_version, 'hash', ev.content_hash, 'path', ev.storage_path) from ev),
          'versions', (select count(*) from pipeline.evidence_artifacts e2 where e2.evidence_group_key = 'scholarship:' || p_id),
          'extractor', pg.facts->>'extractor', 'name_check', pg.name_check,
          'facts', case when pg.facts is null then null else jsonb_build_object(
              'value', pg.facts->'value', 'dates', pg.facts->'dates', 'deadline', pg.facts->'deadline', 'study_start', pg.facts->'study_start',
              'levels', pg.facts->'levels', 'levels_text', pg.facts->'levels_text', 'fields', pg.facts->'fields', 'fields_text', pg.facts->'fields_text',
              'faculties', pg.facts->'faculties', 'named_courses', pg.facts->'named_courses', 'international', pg.facts->'international',
              'not_offered', pg.facts->'not_offered', 'page_title', pg.facts->'page_title') end,
          'applied_at', pg.applied_at, 'apply_result', pg.apply_result,
          'changes', (select coalesce(jsonb_agg(jsonb_build_object('at', c.changed_at, 'field', c.field, 'before', c.before_value, 'after', c.after_value) order by c.changed_at desc), '[]'::jsonb)
                        from (select * from pipeline.scholarship_sweep_changes c where c.scholarship_id = p_id order by c.changed_at desc limit 12) c))
        from pg),
      'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id),
      'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'reason', h.reason) order by h.at desc), '[]'::jsonb)
                    from (select * from pipeline.manual_edit_log l where l.entity = 'scholarship' and l.entity_id = s.id order by l.at desc limit 10) h))
    from scholarship.scholarships s left join catalogue.providers pr on pr.id = s.provider_id where s.id = p_id);
end $function$
