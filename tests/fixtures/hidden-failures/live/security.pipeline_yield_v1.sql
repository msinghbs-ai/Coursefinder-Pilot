create or replace function security.pipeline_yield_v1(p_hours int default null) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '20s' as $function$
-- Platform Admin direction 2 Nov 2026 23:24 §3: every stage distinguished, per lane, over the window (existing tables only). Read-back is what the
-- consumer projection holds for the records published in the window (search.course_documents for course links; published scholarships and
-- provider descriptions of published providers; active entry rows of published providers).
declare v_h int := coalesce(p_hours, security.pipeline_num_v1('integration.yield_window_hours', 24)::int); v_since timestamptz; v jsonb;
begin
  v_since := now() - make_interval(hours => v_h);
  v := jsonb_build_object('window_hours', v_h, 'since', v_since, 'lanes', jsonb_build_array(
    -- scholarships
    jsonb_build_object('lane', 'scholarships', 'label', 'Scholarships', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode in ('scholarship_discover', 'scholarship_listing', 'scholarship_read', 'scholarship_ai')),
      'source_accessed', (select count(*) from pipeline.scholarship_discovery_providers d where d.discovered_at >= v_since)
                         + (select count(*) from pipeline.scholarship_listing_pages p where p.read_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.scholarship_page_candidates c where c.found_at >= v_since),
      'read_completely', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= v_since and c.read_status = 'read')
                         + (select count(*) from pipeline.scholarship_pages p where p.read_at >= v_since and p.read_status = 'read'),
      'extracted', (select count(*) from pipeline.scholarship_ai_extractions e where e.at >= v_since and e.error is null),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where c.admit_status = 'admitted'), 'held', count(*) filter (where c.admit_status = 'matched_held'),
                                                     'rejected', count(*) filter (where c.admit_status in ('rejected', 'duplicate', 'withdrawn', 'skipped')))
                             from pipeline.scholarship_page_candidates c where c.admitted_at >= v_since or (c.admit_status is not null and c.read_at >= v_since)),
      'published', (select count(*) from scholarship.scholarships s where s.updated_at >= v_since and s.publication_status = 'published' and s.lifecycle_status = 'active'),
      'consumer_read_back', (select count(*) from scholarship.scholarships s where s.updated_at >= v_since and s.publication_status = 'published' and s.lifecycle_status = 'active'
                               and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)))),
    -- course pages (official course links)
    jsonb_build_object('lane', 'course_pages', 'label', 'Course pages and official links', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode in ('link_search', 'ai_match', 'read', 'reidentify', 'course_list_read', 'source_find', 'discover')),
      'source_accessed', (select count(*) from pipeline.coverage_course_pages p where p.read_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.coverage_course_pages p where p.bound_at >= v_since),
      'read_completely', (select count(*) from pipeline.coverage_course_pages p where p.read_at >= v_since and p.read_status = 'read'),
      'extracted', (select count(*) from pipeline.coverage_course_pages p where p.l3_handoff_at >= v_since),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where k.status = 'active'), 'held', count(*) filter (where k.status = 'unverified'))
                             from catalogue.course_links k where k.link_type = 'official_course' and k.created_at >= v_since)
                          || jsonb_build_object('held_in_layer4', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'official_course_url' and i.created_at >= v_since)),
      'published', (select count(*) from catalogue.course_links k where k.link_type = 'official_course' and k.status = 'active' and k.is_primary and k.updated_at >= v_since),
      'consumer_read_back', (select count(*) from catalogue.course_links k join search.course_documents d on d.course_id = k.course_id and d.official_course_url = k.url and d.publication_status = 'published'
                              where k.link_type = 'official_course' and k.status = 'active' and k.is_primary and k.updated_at >= v_since))),
    -- academic entry requirements (AER)
    jsonb_build_object('lane', 'aer', 'label', 'Academic entry requirements', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode in ('entry_ai', 'entry_inspect')),
      'source_accessed', (select count(*) from pipeline.entry_matrix_sources m where m.read_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.entry_matrix_sources m where m.created_at >= v_since),
      'read_completely', (select count(*) from pipeline.entry_matrix_runs m where m.done_at >= v_since and m.state = 'done'),
      'extracted', (select count(*) from catalogue.provider_entry_matrix x where x.created_at >= v_since) + (select count(*) from catalogue.course_entry_requirements x where x.created_at >= v_since),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where x.status = 'active'), 'held', count(*) filter (where x.status in ('proposed', 'unverified')))
                             from catalogue.provider_entry_matrix x where x.updated_at >= v_since),
      'published', (select count(*) from catalogue.provider_entry_matrix x where x.status = 'active' and x.updated_at >= v_since)
                   + (select count(*) from catalogue.course_entry_requirements x where x.status = 'active' and x.updated_at >= v_since),
      'consumer_read_back', (select count(*) from catalogue.provider_entry_matrix x where x.status = 'active' and x.updated_at >= v_since
                               and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)))),
    -- university descriptions
    jsonb_build_object('lane', 'descriptions', 'label', 'University descriptions', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode = 'provider_description'),
      'source_accessed', (select count(*) from pipeline.provider_description_reads r where r.source_captured_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.provider_description_reads r where r.created_at >= v_since and r.source_url is not null),
      'read_completely', (select count(*) from pipeline.provider_description_reads r where r.updated_at >= v_since and r.evidence_id is not null),
      'extracted', (select count(*) from pipeline.provider_description_reads r where r.updated_at >= v_since and r.proposal is not null),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where r.state in ('admitted', 'verified')), 'held', count(*) filter (where r.state in ('proposed', 'held')),
                                                     'rejected', count(*) filter (where r.state in ('rejected', 'dead_letter')))
                             from pipeline.provider_description_reads r where r.updated_at >= v_since),
      'published', (select count(*) from pipeline.provider_description_reads r where r.published_at >= v_since),
      'consumer_read_back', (select count(*) from pipeline.provider_description_reads r join catalogue.providers p on p.id = r.provider_id
                              where r.published_at >= v_since and nullif(btrim(p.description), '') is not null and p.publication_status = 'published' and p.lifecycle_status = 'active')))));
  return v;
end $function$
