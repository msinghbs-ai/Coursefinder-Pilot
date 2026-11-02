CREATE OR REPLACE FUNCTION security.layer4_inbox_items_v1()
 RETURNS TABLE(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamp with time zone, detail jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ob as (select distinct on (o.provider_id) o.* from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc),
  cricos_only as (select b.provider_id from pipeline.adapter_builds b where b.wave = 'cricos-only'),
  held_pages as (select f.provider_id from pipeline.enrichment_flags f where f.entity = 'provider' and f.state = 'raised' and f.reason_code = 'course_pages_not_found')
  -- course links and other review items
  -- hotfix 26 Oct 2026: a first run for a university (no page published, conjoint rule) carries its university and its own kind
  select case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'no_page_first_run'
              when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'conjoint_first_run'
              when r.field_code = any (security.aer_review_kinds_v1()) then 'aer_review'  -- CF-247 A1-A3 (30 Oct 2026): the AER review path
              else 'course_link' end::text,
         r.id::text, coalesce(c.provider_id, s.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
         coalesce(nullif(c.display_title, ''), c.canonical_title, s.name,
                  case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'No page published: first run'
                       when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'Conjoint or double degrees: first run' end,
                  case r.field_code when 'entry_matrix_first_run' then 'Entry requirements: first read of the provider table'
                                       when 'entry_matrix_change' then 'Entry requirements: the provider table changed' end,
                  r.field_code),
         coalesce(nullif(r.escalation_reason, ''), 'Needs a decision'), null::text, r.created_at,
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,
                            -- UR-05 (1 Nov 2026): the stored copy behind the item, when it was captured, and whether a newer copy of the same page exists
                            'evidence_id', r.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                            'newer_copy', ev.id is not null and exists (select 1 from pipeline.evidence_artifacts n where lower(n.source_url) = lower(ev.source_url) and n.captured_at > ev.captured_at))
    from pipeline.layer4_review_items r
    left join catalogue.courses c on r.entity_type = 'course' and c.id = r.entity_id
    left join scholarship.scholarships s on r.entity_type = 'scholarship' and s.id = r.entity_id
    left join pipeline.evidence_artifacts ev on ev.id = r.evidence_id
   where r.status = 'pending'
  union all
  -- held scholarship pages, with the AI re-check
  select 'held_scholarship', r.id::text, r.provider_id,
         coalesce((select e.answer->>'name' from pipeline.scholarship_ai_extractions e where e.id = r.extraction_ids[array_upper(r.extraction_ids, 1)]), r.url),
         r.reason, r.recheck->>'why', r.created_at,
         jsonb_build_object('url', r.url, 'recommendation', r.recheck->>'recommendation', 'audience_quote', r.recheck->>'audience_quote', 'value_quote', r.recheck->>'value_quote',
                            'extraction_id', (select e.id from pipeline.scholarship_ai_extractions e where e.id = any (r.extraction_ids) and coalesce((e.answer->>'is_scholarship')::boolean, false) order by e.id desc limit 1))
    from pipeline.scholarship_ai_reviews r where r.status = 'pending'
  union all
  -- universities whose onboarding stopped and needs a person
  select case ob.stop_reason when 'no_website' then 'website_needed' when 'too_few_pages' then 'too_few_pages' when 'nothing_ready' then 'nothing_ready'
              when 'approve_central' then 'central_to_approve' else 'onboarding_failed' end,
         ob.id::text, ob.provider_id, null, coalesce(ob.note, ob.stop_reason), null, ob.updated_at,
         jsonb_build_object('stop_reason', ob.stop_reason, 'onboarding_id', ob.id)
    from ob
   where ob.status = 'stopped' and ob.stop_reason in ('no_website', 'too_few_pages', 'nothing_ready', 'approve_central', 'proposal_failed', 'capture_failed')
     and ob.provider_id not in (select provider_id from cricos_only)
     and not (ob.stop_reason = 'too_few_pages' and ob.provider_id in (select provider_id from held_pages))
  union all
  -- provider holds a person lifts
  select case f.reason_code when 'course_pages_not_found' then 'pages_not_found' when 'site_unreachable' then 'site_down' else 'fee_check' end,
         f.id::text, f.provider_id, null, f.reason, null, f.flagged_at, jsonb_build_object('flag_id', f.id, 'evidence', f.evidence)
    from pipeline.enrichment_flags f
   where f.entity = 'provider' and f.state = 'raised'
     and (f.reason_code in ('course_pages_not_found', 'adapter_fee_fails_check')
          or (f.reason_code = 'site_unreachable' and f.flagged_at < now() - make_interval(days => security.pipeline_num_v1('layer4.site_down_days', 30)::int)))
  union all
  -- course holds a person decides
  select case f.reason_code when 'not_offered' then 'not_offered' when 'not_on_provider_site' then 'not_on_site' else 'fee_check' end,
         f.id::text, coalesce(f.provider_id, c.provider_id), coalesce(nullif(c.display_title, ''), c.canonical_title), f.reason, null, f.flagged_at,
         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code)
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key
   where f.entity = 'course' and f.state = 'raised' and f.reason_code in ('not_offered', 'not_on_provider_site', 'fee_crosscheck')
  union all
  -- counsellor reports from Zoho
  select 'counsellor_report', d.id::text, coalesce((select c.provider_id from catalogue.courses c where d.entity_type = 'course' and c.id = d.entity_id), case when d.entity_type = 'provider' then d.entity_id end),
         coalesce(d.detail->>'label', d.field_code), coalesce(d.detail->>'note', 'Reported by a counsellor'), null, d.created_at, d.detail
    from pipeline.data_flags d where d.flag_code = 'reported' and d.status = 'open'
  union all
  -- CF-247 20 Oct 2026: providers whose every registered course left the register (from the retired Review queue)
  select 'provider_departure', d.id::text, d.provider_id, coalesce(p.display_name, p.canonical_name),
         'Every registered course left the register (' || d.courses_retired || ' course' || case when d.courses_retired = 1 then '' else 's' end || '). Closed, merged into another provider, or still operating?',
         null, d.created_at, jsonb_build_object('departure_id', d.id, 'courses_retired', d.courses_retired, 'note', d.note)
    from pipeline.layer1_provider_departures d left join catalogue.providers p on p.id = d.provider_id where d.status = 'needs_review'
$function$
;
