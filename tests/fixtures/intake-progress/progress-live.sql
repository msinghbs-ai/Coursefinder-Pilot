-- Guards: Platform Admin decision 5 Nov 2026 20:03: the live generic progress contract functions, as defined in production fxcwkweaxjtknorudmwp (read 5 Nov 2026 20:05 AEDT):
-- security.progress_measure_v1 40c0c972abc353be8f6eee35c79750e9, security.progress_zero_reason_v1 746d7baedb0a79dc0a6fbfead82f67c2, security.progress_read_v1 f11ed22d149eb06aa10387e67467ec6f.
-- Rebuilt from migrations 20261104460000 and 20261104520000 and written out with pg_get_functiondef; run.sh checks each md5 before any change.
CREATE OR REPLACE FUNCTION security.progress_measure_v1(p_key text, p_since timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §4): one transition counted from the tables its producers already write, movement since p_since. Keys: eligible,
-- processed, created, rejected, rejected_reasons, excluded (correct exclusions among the rejected), parked, parked_next, downstream, admitted,
-- published, last_output_at, cap (a valid cap holds the transition) and cap_detail, basis (what each count reads). A key left out is not measured.
declare v jsonb; v_l4max numeric := security.pipeline_num_v1('aer.schedule_layer4_max', 600);
begin
  case p_key
  when 'sch_classification' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.coverage_provider_reconciliation l where l.domain = 'scholarship' and l.disposition not in ('not_applicable', 'out_of_scope')),
      'providers_with_candidates', (select count(distinct c.provider_id) from pipeline.scholarship_page_candidates c),
      'providers_classified', (select count(*) from pipeline.scholarship_coverage_providers),
      'processed', (select count(*) from pipeline.scholarship_coverage_providers p where p.classified_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.classified_at >= p_since),
      'parked', (select count(*) from pipeline.scholarship_coverage_items i join pipeline.scholarship_coverage_state_codes s on s.code = i.state where i.present and not s.resolved),
      'parked_next', (select coalesce(jsonb_object_agg(z.state, z.n), '{}'::jsonb) from (select i.state, count(*) n from pipeline.scholarship_coverage_items i
                        join pipeline.scholarship_coverage_state_codes s on s.code = i.state where i.present and not s.resolved group by 1) z),
      'downstream', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state in ('source_found_unread', 'traversal_incomplete', 'rejected_incorrectly')),
      'last_output_at', (select max(i.classified_at) from pipeline.scholarship_coverage_items i),
      'basis', 'eligible: in-scope providers of the scholarship coverage ledger (coverage_provider_reconciliation, not applicable and out of scope excluded); providers_with_candidates: providers with any candidate page ever found (the 755 read on 4 Nov, a subset, not an eligibility count); created: coverage cases classified; parked: unresolved cases by state; downstream: recoverable cases') into v;
  when 'sch_source_recovery' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state in ('source_found_unread', 'traversal_incomplete', 'rejected_incorrectly')
                     and not exists (select 1 from pipeline.scholarship_coverage_recoveries r where r.item_key = i.item_key)),
      'processed', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.at >= p_since),
      'created', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'succeeded' and r.outcome_at >= p_since),
      'rejected', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'failed' and r.outcome_at >= p_since),
      'rejected_reasons', jsonb_build_object('case did not move', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'failed' and r.outcome_at >= p_since)),
      'downstream', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome is null),
      'last_output_at', (select max(r.outcome_at) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'succeeded'),
      'basis', 'eligible: recoverable coverage cases with no recovery yet; created: recoveries whose case moved; downstream: recoveries awaiting their verification') into v;
  when 'sch_listing_traversal' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_listing_pages l where l.active and coalesce(l.status, '') <> 'suggested' and (l.next_read_at is null or l.next_read_at <= now())),
      'processed', (select count(*) from pipeline.scholarship_listing_pages l where l.read_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_listing_members m where m.first_seen >= p_since),
      'rejected', (select count(*) from pipeline.scholarship_listing_pages l where l.read_at >= p_since and l.error is not null),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select left(l.error, 60) r, count(*) n from pipeline.scholarship_listing_pages l
                             where l.read_at >= p_since and l.error is not null group by 1 order by 2 desc limit 10) z),
      'parked', (select count(*) from pipeline.scholarship_listing_pages l where l.status = 'suggested'),
      'parked_next', jsonb_build_object('listing suggested, not yet a listing source (promote_listing, sch_cov.recover_listings_on)',
                                        (select count(*) from pipeline.scholarship_listing_pages l where l.status = 'suggested')),
      'downstream', (select count(*) from pipeline.scholarship_listing_members m where m.present and m.candidate_id is null),
      'last_output_at', (select max(m.first_seen) from pipeline.scholarship_listing_members m),
      'basis', 'eligible: active listing sources due a read; created: listing items found; parked: suggested listings; downstream: items not yet candidates') into v;
  when 'sch_candidate_matching' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_listing_members m where m.present and m.candidate_id is null),
      'processed', (select count(*) from pipeline.scholarship_page_candidates c where c.found_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_page_candidates c where c.found_at >= p_since),
      'downstream', (select count(*) from pipeline.scholarship_page_candidates c where c.read_status is null and c.read_at is null),
      'last_output_at', (select max(c.found_at) from pipeline.scholarship_page_candidates c),
      'basis', 'eligible: listing items not yet candidates; created: candidate pages found; downstream: candidates never read') into v;
  when 'sch_reading' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at is null and (c.next_read_at is null or c.next_read_at <= now())),
      'processed', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= p_since and c.http_status between 200 and 299),
      'rejected', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= p_since and c.http_status is distinct from null and c.http_status not between 200 and 299),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select coalesce(c.read_status, 'http ' || c.http_status) r, count(*) n
                             from pipeline.scholarship_page_candidates c where c.read_at >= p_since and c.http_status not between 200 and 299 group by 1 order by 2 desc limit 10) z),
      'downstream', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at is not null and c.http_status between 200 and 299 and c.admit_status is null),
      'last_output_at', (select max(c.read_at) from pipeline.scholarship_page_candidates c where c.http_status between 200 and 299),
      'basis', 'eligible: candidates never read and due; created: pages read (HTTP 2xx); downstream: read pages awaiting an admission decision') into v;
  when 'sch_eligibility' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at is not null and c.http_status between 200 and 299 and c.admit_status is null),
      'processed', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since),
      'created', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'rejected', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action in ('rejected', 'skipped', 'duplicate')),
      'excluded', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action in ('skipped', 'duplicate')),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select a.action || ': ' || coalesce(left(coalesce(a.detail->>'reason', a.detail->>'skip_reason',
                             a.detail->>'reasons'), 50), 'not stated') r, count(*) n from pipeline.scholarship_admission_log a
                             where a.at >= p_since and a.action in ('rejected', 'skipped', 'duplicate') group by 1 order by 2 desc limit 10) z),
      'parked', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'parked_next', jsonb_build_object('held for a person (Layer 4)', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending')),
      'downstream', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'admitted', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'last_output_at', (select max(a.at) from pipeline.scholarship_admission_log a where a.action = 'admitted'),
      'basis', 'eligible: read pages with no admission decision; created/admitted: admission log admitted; excluded: skipped (directory site) and duplicates') into v;
  when 'sch_layer4' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'processed', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status = 'admitted'),
      'rejected', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status in ('refused', 'superseded')),
      'excluded', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status = 'superseded'),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.s, z.n), '{}'::jsonb) from (select r.status s, count(*) n from pipeline.scholarship_ai_reviews r
                             where r.decided_at >= p_since and r.status in ('refused', 'superseded') group by 1) z),
      'parked', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'parked_next', jsonb_build_object('a person decides in Layer 4', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending')),
      'admitted', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status = 'admitted'),
      'last_output_at', (select max(r.decided_at) from pipeline.scholarship_ai_reviews r where r.status = 'admitted'),
      'basis', 'scholarship AI reviews held for a person: pending, admitted, refused, superseded') into v;
  when 'sch_admission' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'processed', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'created', (select count(*) from scholarship.scholarships s where s.created_at >= p_since and s.lifecycle_status = 'active'),
      'admitted', (select count(*) from scholarship.scholarships s where s.created_at >= p_since and s.lifecycle_status = 'active'),
      'downstream', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status not in ('published', 'withdrawn')),
      'last_output_at', (select max(s.created_at) from scholarship.scholarships s where s.lifecycle_status = 'active'),
      'basis', 'admitted: active catalogue scholarships created (scholarship.scholarships, read only); downstream: active, not published, not withdrawn') into v;
  when 'sch_publication' then
    select jsonb_build_object(
      'eligible', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status not in ('published', 'withdrawn')),
      'processed', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.updated_at >= p_since),
      'created', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published' and s.updated_at >= p_since),
      'published', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published' and s.updated_at >= p_since),
      'published_total', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published'),
      'last_output_at', (select max(s.updated_at) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published'),
      'basis', 'published: active scholarships marked published and changed in the window (updated_at); consumer read-back (Website API v2, Zoho) is verified separately') into v;
  when 'aer_source_discovery' then
    select jsonb_build_object(
      'eligible', (select count(distinct g.provider_id) from pipeline.aer_gap_findings g where g.state = 'open' and g.root_cause = 'no_source'),
      'processed', (select count(*) from pipeline.aer_source_inventory s where s.recorded_at >= p_since) + (select count(*) from pipeline.entry_matrix_sources e where e.created_at >= p_since),
      'created', (select count(*) from pipeline.entry_matrix_sources e where e.created_at >= p_since),
      'parked', (select count(*) from pipeline.aer_gap_findings g where g.state = 'open' and g.root_cause = 'no_source'),
      'parked_next', (select coalesce(jsonb_object_agg(z.a, z.n), '{}'::jsonb) from (select coalesce(left(g.next_action, 60), 'no next action') a, count(*) n from pipeline.aer_gap_findings g
                        where g.state = 'open' and g.root_cause = 'no_source' group by 1 order by 2 desc limit 5) z),
      'downstream', (select count(*) from pipeline.entry_matrix_sources e where e.read_at is null and coalesce(e.status, '') <> 'failed'),
      'last_output_at', (select max(e.created_at) from pipeline.entry_matrix_sources e),
      'basis', 'eligible: providers with an open no_source AER gap; created: AER matrix sources found; downstream: sources not yet read') into v;
  when 'aer_extraction' then
    select jsonb_build_object(
      'eligible', (select count(distinct e.provider_id) from pipeline.entry_matrix_sources e where e.status = 'read'),
      'processed', coalesce((select sum(r.course_reads) from pipeline.aer_schedule_runs r where r.ran_at >= p_since), 0)
                   + (select count(*) from pipeline.entry_matrix_runs m where m.created_at >= p_since),
      'created', (select count(*) from catalogue.course_entry_requirements c where c.created_at >= p_since),
      'rejected', (select count(*) from pipeline.entry_matrix_runs m where m.created_at >= p_since and m.error is not null),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select left(m.error, 60) r, count(*) n from pipeline.entry_matrix_runs m
                             where m.created_at >= p_since and m.error is not null group by 1 order by 2 desc limit 10) z),
      'downstream', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'cap', coalesce((select r.back_pressure or r.refusal is not null from pipeline.aer_schedule_runs r order by r.ran_at desc limit 1), false),
      'cap_detail', (select jsonb_build_object('ran_at', r.ran_at, 'back_pressure', r.back_pressure, 'room', r.room, 'layer4_waiting', r.layer4_waiting, 'refusal', r.refusal,
                       'layer4_limit', v_l4max) from pipeline.aer_schedule_runs r order by r.ran_at desc limit 1),
      'last_output_at', (select max(c.created_at) from catalogue.course_entry_requirements c),
      'basis', 'eligible: providers with a read AER source; processed: scheduled course reads and matrix runs; created: course entry rows proposed; cap: the last scheduled run''s back-pressure or refusal') into v;
  when 'aer_completeness' then
    select jsonb_build_object(
      'eligible', (select count(*) from catalogue.course_entry_requirements c where c.created_at >= p_since),
      'processed', (select count(*) from catalogue.course_entry_requirements c where c.created_at >= p_since),
      'created', (select count(*) from pipeline.layer4_review_items i where i.created_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'rejected', coalesce((select sum(m.rows_dropped) from pipeline.entry_matrix_runs m where m.created_at >= p_since), 0),
      'rejected_reasons', jsonb_build_object('rows dropped by the completeness gate (matrix runs)', coalesce((select sum(m.rows_dropped) from pipeline.entry_matrix_runs m where m.created_at >= p_since), 0)),
      'downstream', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'last_output_at', (select max(i.created_at) from pipeline.layer4_review_items i where i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'basis', 'eligible: course entry rows proposed; created: AER Layer 4 items raised; rejected: matrix rows dropped') into v;
  when 'aer_technical_correction' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'eligible'),
      'processed', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.last_attempt_at >= p_since),
      'created', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.recovered_at >= p_since),
      'parked', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'parked'),
      'parked_next', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select coalesce(w.failure_class, 'unclassified') || case when w.next_eligible_at is null then ' (no next time)' else '' end k,
                        count(*) n from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'parked' group by 1) z),
      'last_output_at', (select max(w.recovered_at) from pipeline.work_items w where w.lane = 'aer_technical'),
      'basis', 'work items of lane aer_technical: eligible, attempted, recovered, parked by failure class') into v;
  when 'aer_layer4_review' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'processed', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'created', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                    and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'rejected', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                     and i.status in ('rejected', 'superseded', 'returned')),
      'excluded', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run') and i.status = 'superseded'),
      'parked', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'parked_next', jsonb_build_object('a person decides in Layer 4; reading pauses at the limit', v_l4max),
      'downstream', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                       and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'last_output_at', (select max(i.decided_at) from pipeline.layer4_review_items i where i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                           and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'basis', 'Layer 4 AER items (course first read, matrix first run): pending, decided for admission, rejected or superseded') into v;
  when 'aer_active_records' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                     and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'processed', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status in ('active', 'inactive')),
      'created', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'admitted', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'active_total', (select count(*) from catalogue.course_entry_requirements c where c.status = 'active'),
      'last_output_at', (select max(c.updated_at) from catalogue.course_entry_requirements c where c.status = 'active'),
      'basis', 'admitted: course entry rows made active in the window (catalogue.course_entry_requirements, read only)') into v;
  when 'aer_publication' then
    select jsonb_build_object(
      'eligible', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'processed', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'created', (select count(*) from catalogue.course_entry_requirements c join catalogue.courses k on k.id = c.course_id join catalogue.providers p on p.id = k.provider_id
                    where c.updated_at >= p_since and c.status = 'active' and p.publication_status = 'published'),
      'published', (select count(*) from catalogue.course_entry_requirements c join catalogue.courses k on k.id = c.course_id join catalogue.providers p on p.id = k.provider_id
                      where c.updated_at >= p_since and c.status = 'active' and p.publication_status = 'published'),
      'last_output_at', (select max(c.updated_at) from catalogue.course_entry_requirements c join catalogue.courses k on k.id = c.course_id join catalogue.providers p on p.id = k.provider_id
                           where c.status = 'active' and p.publication_status = 'published'),
      'basis', 'published: active entry rows of published providers, which the consumer API reads; read-back through Website API v2 and Zoho is verified separately') into v;
  -- job output contracts (pipeline.job_output_contracts; direction 4 Nov 2026 10:00 §6): created is the run's measurable output
  when 'l4_interventions' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_interventions i where i.status in ('ai_pending', 'awaiting_input', 'resuming') or i.created_at >= p_since),
      'interventions_created', (select count(*) from pipeline.layer4_interventions i where i.created_at >= p_since),
      'reused', (select count(*) from pipeline.layer4_interventions i where i.created_at < p_since and i.last_seen_at >= p_since),
      'resolved', (select count(*) from pipeline.layer4_interventions i where i.status in ('resolved', 'auto_resolved', 'not_published') and coalesce(i.verified_at, i.updated_at) >= p_since),
      'returned_to_recovery', (select count(*) from pipeline.layer4_interventions i where i.status = 'returned_technical' and i.updated_at >= p_since),
      'awaiting_human_input', (select count(*) from pipeline.layer4_interventions i where i.status = 'awaiting_input'),
      'processed', (select count(*) from pipeline.layer4_interventions i where i.updated_at >= p_since or i.last_seen_at >= p_since),
      'created', (select count(*) from pipeline.layer4_interventions i where i.created_at >= p_since or i.last_seen_at >= p_since
                    or (i.status in ('resolved', 'auto_resolved', 'not_published', 'returned_technical') and coalesce(i.verified_at, i.updated_at) >= p_since)),
      'downstream', (select count(*) from pipeline.layer4_interventions i where i.status = 'resuming'),
      'human_decided', (select count(*) from pipeline.layer4_intervention_events e where e.at >= p_since and e.actor is not null),
      'last_output_at', (select max(greatest(i.created_at, i.last_seen_at)) from pipeline.layer4_interventions i),
      'basis', 'created: interventions created, reused (repeat or changed evidence), resolved or returned to recovery since the run; awaiting_human_input: open now') into v;
  when 'l4_readiness' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending'),
      'processed', (select count(*) from pipeline.layer4_readiness_runs r where r.at >= p_since),
      'checked', (select coalesce(sum((r.result->>'classified')::numeric), 0) from pipeline.layer4_readiness_runs r where r.at >= p_since),
      'created', (select coalesce(sum((r.result->>'classified')::numeric), 0) from pipeline.layer4_readiness_runs r where r.at >= p_since),
      'newly_classified', (select count(*) from pipeline.layer4_item_readiness x where x.classified_at >= p_since and x.item_created_at >= p_since),
      'technical_blocked', (select count(*) from pipeline.layer4_item_readiness x where x.classified_at >= p_since and x.readiness = 'technical_blocked'),
      'judgement_ready', (select count(*) from pipeline.layer4_item_readiness x where x.classified_at >= p_since and x.readiness = 'judgement_ready'),
      'superseded', (select count(*) from pipeline.layer4_supersessions s where s.at >= p_since and s.reversed_at is null),
      'downstream', (select count(*) from pipeline.layer4_item_readiness x where x.readiness = 'judgement_ready'),
      'last_output_at', (select max(r.at) from pipeline.layer4_readiness_runs r where coalesce((r.result->>'classified')::numeric, 0) > 0),
      'basis', 'checked: items classified by the runs since (layer4_readiness_runs); newly classified: items that arrived since; technical-blocked and judgement-ready: classified since; superseded: settled without a person') into v;
  when 'first_run_verify' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.progress_transitions),
      'processed', (select count(*) from pipeline.progress_observations o where o.measured_at >= p_since),
      'created', (select count(*) from pipeline.progress_observations o where o.measured_at >= p_since),
      'transitions_read', (select count(*) from pipeline.progress_observations o where o.measured_at >= p_since),
      'releases_judged', (select count(*) from pipeline.release_job_verifications r where r.checked_at >= p_since),
      'last_output_at', (select max(o.measured_at) from pipeline.progress_observations o),
      'basis', 'transitions read (progress_observations) and release jobs judged since the run') into v;
  else
    raise exception 'no progress measure for transition %', p_key using errcode = '22023';
  end case;
  return v;
end $function$

;
CREATE OR REPLACE FUNCTION security.progress_zero_reason_v1(p_key text, m jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §4 "a zero-output run must have a reason"): why a transition created nothing, in order: its producing jobs are
-- all paused, or every switch it depends on is off (blocked_authority); a valid cap holds it (cap_reached); nothing is eligible
-- (no_eligible_work); everything processed was correctly excluded (correctly_excluded); otherwise technical_failure. Null when it created output.
declare t pipeline.progress_transitions; v_jobs int; v_active int; v_off text[];
begin
  select * into t from pipeline.progress_transitions where key = p_key;
  if t.key is null then  -- a job output contract (pipeline.job_output_contracts)
    select c.measure_key, array[c.jobname], c.switch_keys into t.key, t.producer_jobs, t.switch_keys from pipeline.job_output_contracts c where c.measure_key = p_key;
  end if;
  if coalesce((m->>'created')::numeric, 0) > 0 then return null; end if;
  select count(*), count(*) filter (where j.active) into v_jobs, v_active from cron.job j where j.jobname = any (t.producer_jobs);
  if v_jobs > 0 and v_active = 0 then
    return jsonb_build_object('reason', 'blocked_authority', 'detail', 'producing job(s) paused: ' || array_to_string(t.producer_jobs, ', '));
  end if;
  select coalesce(array_agg(k), '{}') into v_off from unnest(t.switch_keys) k where security.pipeline_num_v1(k, 0) < 1;
  if cardinality(t.switch_keys) > 0 and cardinality(v_off) = cardinality(t.switch_keys) then
    return jsonb_build_object('reason', 'blocked_authority', 'detail', 'switched off: ' || array_to_string(v_off, ', '));
  end if;
  if coalesce((m->>'cap')::boolean, false) then return jsonb_build_object('reason', 'cap_reached', 'detail', coalesce(m->>'cap_detail', 'a valid cap')); end if;
  if coalesce((m->>'eligible')::numeric, 0) = 0 then return jsonb_build_object('reason', 'no_eligible_work', 'detail', 'nothing eligible: ' || coalesce(m->>'basis', '')); end if;
  if coalesce((m->>'processed')::numeric, 0) > 0 and coalesce((m->>'excluded')::numeric, 0) >= (m->>'processed')::numeric then
    return jsonb_build_object('reason', 'correctly_excluded', 'detail', 'every processed input was excluded by a recorded rule');
  end if;
  return jsonb_build_object('reason', 'technical_failure', 'detail', coalesce(m->>'eligible', '?') || ' eligible, ' || coalesce(m->>'processed', '0') || ' processed, nothing created');
end $function$

;
CREATE OR REPLACE FUNCTION security.progress_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §4): reads every transition (each isolated: one that fails to read is recorded and the others still read), keeps
-- the reading on pipeline.progress_transitions and in pipeline.progress_observations, and raises a stalled transition by fingerprint
-- stall:<transition> (eligible input, a technical zero, no advancement for progress.stall_hours), whatever its producing job reports.
declare t pipeline.progress_transitions; m jsonb; z jsonb; v_since timestamptz := now() - make_interval(hours => security.pipeline_num_v1('progress.window_hours', 24)::int);
        v_stall_h int := security.pipeline_num_v1('progress.stall_hours', 6)::int; v_last timestamptz; v_stalled boolean; v_res jsonb; v_issue bigint;
        v_n int := 0; v_err int := 0; v_st int := 0; v_jobs jsonb;
begin
  if security.pipeline_num_v1('progress.on', 1) < 1 then return jsonb_build_object('off', true); end if;
  for t in select * from pipeline.progress_transitions order by chain, step loop
    begin
      m := security.progress_measure_v1(t.key, v_since);
      z := security.progress_zero_reason_v1(t.key, m);
      v_last := greatest(t.last_advanced_at, case when coalesce((m->>'created')::numeric, 0) > 0 then (m->>'last_output_at')::timestamptz end);
      v_stalled := z is not null and z->>'reason' = 'technical_failure' and coalesce((m->>'eligible')::numeric, 0) > 0
                   and coalesce(v_last, '-infinity'::timestamptz) < now() - make_interval(hours => v_stall_h);
      v_issue := t.issue_id;
      if v_stalled then
        select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'active', j.active)), '[]'::jsonb) into v_jobs from cron.job j where j.jobname = any (t.producer_jobs);
        v_res := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'stall:' || t.key,
          'title', 'Pipeline transition stalled: ' || t.chain || ' ' || lower(t.title) || ' (' || coalesce(m->>'eligible', '?') || ' eligible, nothing created for ' || v_stall_h || ' h)',
          'layer', case t.chain when 'aer' then 'AER' else 'Scholarships' end, 'subsystem', 'progress contract: ' || t.key,
          'failure', coalesce(z->>'detail', 'no output') || '; last advanced ' || coalesce(v_last::text, 'never') || '; producing jobs ' || v_jobs::text,
          'expected', 'Eligible input advances to the next stage (' || coalesce(t.next_key, 'end of chain') || '), or the zero has a valid reason',
          'source', 'first-run-verify (progress contract)', 'validation_layer', 'V4', 'severity', 'P2', 'root_cause_class', 'unclassified', 'workstream', 'A7',
          'evidence', jsonb_build_object('transition', t.key, 'measures', m, 'zero_reason', z, 'jobs', v_jobs, 'window_start', v_since), 'observed_at', now()),
          'first-run-verify');
        v_issue := (v_res->>'id')::bigint; v_st := v_st + 1;
      end if;
      update pipeline.progress_transitions set measured_at = now(), window_start = v_since,
             input_eligible = (m->>'eligible')::numeric, input_processed = (m->>'processed')::numeric, output_created = (m->>'created')::numeric,
             output_rejected = (m->>'rejected')::numeric, rejected_reasons = m->'rejected_reasons', output_parked = (m->>'parked')::numeric, parked_next_actions = m->'parked_next',
             downstream_queued = (m->>'downstream')::numeric, output_admitted = (m->>'admitted')::numeric, output_published = (m->>'published')::numeric,
             last_advanced_at = v_last, zero_reason = z->>'reason', zero_detail = z->>'detail',
             stalled = v_stalled, stalled_since = case when v_stalled then coalesce(t.stalled_since, now()) end, issue_id = v_issue, measure_error = null
       where key = t.key;
      insert into pipeline.progress_observations(transition_key, window_start, measures, zero_reason, stalled) values (t.key, v_since, m || jsonb_build_object('zero', z), z->>'reason', v_stalled);
      v_n := v_n + 1;
    exception when others then
      update pipeline.progress_transitions set measure_error = left(sqlerrm, 300), measured_at = now() where key = t.key;
      v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('read', v_n, 'errors', v_err, 'stalled', v_st, 'since', v_since);
end $function$

;
revoke all on function security.progress_measure_v1(text, timestamptz), security.progress_zero_reason_v1(text, jsonb), security.progress_read_v1() from public, anon, authenticated;
