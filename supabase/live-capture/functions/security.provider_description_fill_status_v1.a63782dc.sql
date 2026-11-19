CREATE OR REPLACE FUNCTION security.provider_description_fill_status_v1(p_ids uuid[], p_feeds boolean, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return (
    with q as (select * from security.provider_description_quality_v1(p_ids, p_feeds)),
    lr as (
      select distinct on (r.provider_id) r.provider_id, r.id read_id, r.state, r.rule, r.reason, r.tries, r.updated_at, r.next_try_at, r.review_item_id, r.evidence_id, r.source_url, r.read_via, r.ai_calls, r.model, r.content_hash, r.source_captured_at
        from pipeline.provider_description_reads r where r.provider_id = any(p_ids) order by r.provider_id, r.created_at desc, r.id desc
    ), lt as (
      select distinct on (m.provider_id) m.provider_id, c.id cohort_id, c.state cohort_state, c.run_id, c.created_at, c.reason, (c.requested_by = p_actor) mine, c.selection->>'fill_mode' fill_mode,
             j.state run_state, j.outcome run_outcome, j.finished_at run_finished_at
        from pipeline.provider_description_cohort_members m
        join pipeline.provider_description_cohorts c on c.id = m.cohort_id
        left join pipeline.admin_jobs j on j.id = c.run_id
       where m.provider_id = any(p_ids) order by m.provider_id, c.created_at desc, c.id desc
    ), mc as (
      -- the latest machine decision of each provider (migration 20261110210000): admitted, or declined with the reason and what the sentence-subset recovery found
      select distinct on (a.provider_id) a.provider_id, a.outcome, a.tier, a.reason, a.created_at, a.review_item_id, a.checks
        from pipeline.provider_description_machine_admissions a where a.provider_id = any(p_ids) and a.withdrawn_at is null order by a.provider_id, a.created_at desc, a.id desc
    )
    select jsonb_build_object('as_at', now(), 'feeds', p_feeds, 'providers', coalesce(jsonb_agg(jsonb_build_object(
      'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'stable_key', p.stable_key, 'country', k.iso_alpha2::text, 'type', pt.code,
      'lifecycle_status', p.lifecycle_status, 'publication_status', p.publication_status,
      'description_present', q.description_filled, 'current_description', p.description, 'quality_class', q.quality_class,
      'source_tier', q.source_tier, 'admission_state', q.admission_state, 'admitted_at', q.admitted_at, 'admitted_by', q.admitted_by, 'evidence_id', coalesce(q.evidence_id, lr.evidence_id), 'source_url', coalesce(q.source_url, lr.source_url),
      'reader', jsonb_build_object('read_id', lr.read_id, 'state', lr.state, 'rule', lr.rule, 'reason', lr.reason, 'tries', lr.tries, 'updated_at', lr.updated_at, 'read_via', lr.read_via, 'ai_calls', lr.ai_calls, 'model', lr.model, 'source_captured_at', lr.source_captured_at, 'content_hash', lr.content_hash),
      'hold_reason', coalesce(q.hold_reason, case when lr.state in ('held', 'rejected', 'dead_letter') then coalesce(nullif(lr.reason, ''), lr.rule) end), 'next_retry_at', coalesce(q.next_retry_at, case when lr.state in ('queued', 'held') then lr.next_try_at end),
      'last_read_ok_at', q.last_read_ok_at, 'l4_status', q.l4_status, 'review_item_id', lr.review_item_id,
      'website_state', q.website_state, 'zoho_state', q.zoho_state, 'website_publication', q.website_publication, 'zoho_publication', q.zoho_publication, 'readback_at', q.readback_at,
      'missing_fields', to_jsonb(q.missing_fields),
      'locked', exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')),
      'machine', case when mc.provider_id is null then null else jsonb_build_object('outcome', mc.outcome, 'tier', mc.tier, 'reason', mc.reason, 'at', mc.created_at, 'review_item_id', mc.review_item_id,
        'current_reading', mc.review_item_id is not distinct from lr.review_item_id,
        'subset', case when mc.checks ? 'subset_of_reading' then jsonb_build_object('kept_sentences', mc.checks->'subset_of_reading'->'kept_sentences', 'given_sentences', mc.checks->'subset_of_reading'->'given_sentences',
          'dropped', (select coalesce(jsonb_agg(d - 'quote'), '[]'::jsonb) from jsonb_array_elements(mc.checks->'subset_of_reading'->'dropped') d)) end,
        'subset_result', mc.checks->'subset_recovery'->>'result') end,
      'latest_task', case when lt.cohort_id is null then null else jsonb_build_object('cohort_id', lt.cohort_id, 'state', lt.cohort_state, 'run_id', lt.run_id, 'created_at', lt.created_at, 'reason', lt.reason,
        'requested_by_me', lt.mine, 'fill_mode', lt.fill_mode, 'run_state', lt.run_state, 'run_outcome', lt.run_outcome, 'run_finished_at', lt.run_finished_at) end
    ) order by coalesce(p.display_name, p.canonical_name)), '[]'::jsonb))
    from q join catalogue.providers p on p.id = q.provider_id join ref.countries k on k.id = p.country_id left join ref.provider_types pt on pt.id = p.provider_type_id
    left join lr on lr.provider_id = p.id left join lt on lt.provider_id = p.id left join mc on mc.provider_id = p.id
  );
end
$function$
