CREATE OR REPLACE FUNCTION security.layer4_inbox_items_v2(p_provider_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT NULL::text, p_keys text[] DEFAULT NULL::text[], p_detail boolean DEFAULT true)
 RETURNS TABLE(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamp with time zone, detail jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 Layer 4 Inbox performance (4 Nov 2026): every item that needs a person, one row each, as security.layer4_inbox_items_v1 had them.
  -- A university (p_provider_id), a kind (p_kind) or items ('kind:ref' in p_keys) are chosen inside each source before anything is built;
  -- p_detail false leaves the detail out (counts and keys only).
  with ob as (select distinct on (o.provider_id) o.* from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc),
  cricos_only as (select b.provider_id from pipeline.adapter_builds b where b.wave = 'cricos-only'),
  held_pages as (select f.provider_id from pipeline.enrichment_flags f where f.entity = 'provider' and f.state = 'raised' and f.reason_code = 'course_pages_not_found')
  -- course links and other review items
  -- hotfix 26 Oct 2026: a first run for a university (no page published, conjoint rule) carries its university and its own kind
  select z.k, r.id::text, z.pid,
         coalesce(nullif(c.display_title, ''), c.canonical_title, s.name,
                  case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'No page published: first run'
                       when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'Conjoint or double degrees: first run' end,
                  case r.field_code when 'entry_matrix_first_run' then 'Entry requirements: first read of the provider table'
                                       when 'entry_matrix_change' then 'Entry requirements: the provider table changed'
                                       when 'provider_description' then 'University description from the official page' end,
                  r.field_code),
         -- mandate 3 Nov 2026 20:47 §5: a CRICOS code is named only for Australian providers
         case when coalesce(kc.iso_alpha2, 'AU') <> 'AU' and r.escalation_reason ilike '%CRICOS%'
              then replace(replace(r.escalation_reason, 'this course''s CRICOS code', 'this course''s code'), 'CRICOS code', 'course code')
              else coalesce(nullif(r.escalation_reason, ''), 'Needs a decision') end, null::text, r.created_at,
         case when p_detail then
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,
                            'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,
                            -- UR-05 (1 Nov 2026): the stored copy behind the item, when it was captured, and whether a newer copy of the same page exists
                            'evidence_id', r.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                            'newer_copy', ev.id is not null and exists (select 1 from pipeline.evidence_artifacts n where lower(n.source_url) = lower(ev.source_url) and n.captured_at > ev.captured_at)) end
    from pipeline.layer4_review_items r
    left join catalogue.courses c on r.entity_type = 'course' and c.id = r.entity_id
    left join scholarship.scholarships s on r.entity_type = 'scholarship' and s.id = r.entity_id
    cross join lateral (select case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'no_page_first_run'
              when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'conjoint_first_run'
              when r.field_code = any (security.aer_review_kinds_v1()) then 'aer_review'  -- CF-247 A1-A3 (30 Oct 2026): the AER review path
              when r.entity_type = 'provider' and r.field_code = 'provider_description' then 'provider_description'  -- CF-247 P1 (2 Nov 2026): university descriptions
              when r.entity_type = 'course' and r.field_code = 'course_description_first_read' then 'provider_description'  -- CF-247 Workstream C (3 Nov 2026): course descriptions, the same review (approve as read or reject)
              else 'course_link' end::text k,
              coalesce(c.provider_id, s.provider_id, case when r.entity_type = 'provider' then r.entity_id end) pid) z
    left join pipeline.evidence_artifacts ev on p_detail and ev.id = r.evidence_id
    left join catalogue.providers pv on pv.id = coalesce(c.provider_id, s.provider_id)
    left join ref.countries kc on kc.id = pv.country_id
   where r.status = 'pending'
     and (p_provider_id is null or z.pid = p_provider_id) and (p_kind is null or z.k = p_kind) and (p_keys is null or z.k || ':' || r.id::text = any (p_keys))
  union all
  -- held scholarship pages, with the AI re-check
  select 'held_scholarship', r.id::text, r.provider_id,
         coalesce((select e.answer->>'name' from pipeline.scholarship_ai_extractions e where e.id = r.extraction_ids[array_upper(r.extraction_ids, 1)]), r.url),
         r.reason, r.recheck->>'why', r.created_at,
         case when p_detail then
         jsonb_build_object('url', r.url, 'recommendation', r.recheck->>'recommendation', 'audience_quote', r.recheck->>'audience_quote', 'value_quote', r.recheck->>'value_quote',
                            'extraction_id', (select e.id from pipeline.scholarship_ai_extractions e where e.id = any (r.extraction_ids) and coalesce((e.answer->>'is_scholarship')::boolean, false) order by e.id desc limit 1)) end
    from pipeline.scholarship_ai_reviews r where r.status = 'pending'
     and (p_kind is null or p_kind = 'held_scholarship') and (p_provider_id is null or r.provider_id = p_provider_id)
     and (p_keys is null or 'held_scholarship:' || r.id::text = any (p_keys))
  union all
  -- universities whose onboarding stopped and needs a person
  select z.k, ob.id::text, ob.provider_id, null, coalesce(ob.note, ob.stop_reason), null, ob.updated_at,
         case when p_detail then jsonb_build_object('stop_reason', ob.stop_reason, 'onboarding_id', ob.id) end
    from ob
    cross join lateral (select case ob.stop_reason when 'no_website' then 'website_needed' when 'too_few_pages' then 'too_few_pages' when 'nothing_ready' then 'nothing_ready'
              when 'approve_central' then 'central_to_approve' else 'onboarding_failed' end k) z
   where ob.status = 'stopped' and ob.stop_reason in ('no_website', 'too_few_pages', 'nothing_ready', 'approve_central', 'proposal_failed', 'capture_failed')
     and ob.provider_id not in (select provider_id from cricos_only)
     and not (ob.stop_reason = 'too_few_pages' and ob.provider_id in (select provider_id from held_pages))
     and (p_kind is null or z.k = p_kind) and (p_provider_id is null or ob.provider_id = p_provider_id) and (p_keys is null or z.k || ':' || ob.id::text = any (p_keys))
  union all
  -- provider holds a person lifts
  select z.k, f.id::text, f.provider_id, null, f.reason, null, f.flagged_at, case when p_detail then jsonb_build_object('flag_id', f.id, 'evidence', f.evidence) end
    from pipeline.enrichment_flags f
    cross join lateral (select case f.reason_code when 'course_pages_not_found' then 'pages_not_found' when 'site_unreachable' then 'site_down' else 'fee_check' end k) z
   where f.entity = 'provider' and f.state = 'raised'
     and (f.reason_code in ('course_pages_not_found', 'adapter_fee_fails_check')
          or (f.reason_code = 'site_unreachable' and f.flagged_at < now() - make_interval(days => security.pipeline_num_v1('layer4.site_down_days', 30)::int)))
     and (p_kind is null or z.k = p_kind) and (p_provider_id is null or f.provider_id = p_provider_id) and (p_keys is null or z.k || ':' || f.id::text = any (p_keys))
  union all
  -- course holds a person decides
  select z.k, f.id::text, coalesce(f.provider_id, c.provider_id), coalesce(nullif(c.display_title, ''), c.canonical_title), f.reason, null, f.flagged_at,
         case when p_detail then
         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code,
                            -- mandate 3 Nov 2026 20:47 §5: the stored copy of the course's bound page, so a fee or course hold shows its evidence
                            'evidence_id', g.evidence_id, 'captured_at', gev.captured_at, 'source_url', gev.source_url) end
    -- the course by its key as written (a lower-case uuid, as c.id::text = f.entity_key matched), so its primary key is used
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id = case when f.entity_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then f.entity_key::uuid end
    cross join lateral (select case f.reason_code when 'not_offered' then 'not_offered' when 'not_on_provider_site' then 'not_on_site' else 'fee_check' end k) z
    left join pipeline.coverage_course_pages g on p_detail and g.course_id = c.id
    left join pipeline.evidence_artifacts gev on gev.id = g.evidence_id
   where f.entity = 'course' and f.state = 'raised' and f.reason_code in ('not_offered', 'not_on_provider_site', 'fee_crosscheck')
     and (p_kind is null or z.k = p_kind) and (p_provider_id is null or coalesce(f.provider_id, c.provider_id) = p_provider_id)
     and (p_keys is null or z.k || ':' || f.id::text = any (p_keys))
  union all
  -- Decision 179 (Platform Admin 3 Nov 2026 20:29): courses that need a correct page, while open and still without an official page
  select 'course_page_needed', n.course_id::text, n.provider_id, coalesce(nullif(c.display_title, ''), c.canonical_title),
         'No page of this course has been verified. ' || n.refused || ' page' || case when n.refused = 1 then ' was' else 's were' end || ' found and refused, the last: '
           || coalesce(n.last_refused_reason, 'not proved to be this course''s page'),
         null, n.created_at,
         case when p_detail then
         jsonb_build_object('course_id', c.id, 'course_code', c.course_code, 'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,
                            'proposed', jsonb_build_object('course_url', n.last_refused_url), 'refused', n.refused, 'lane', n.last_refused_lane, 'converted_items', to_jsonb(n.converted_items),
                            'searches_requested', n.searches_requested, 'evidence_id', n.last_refused_evidence, 'captured_at', nev.captured_at, 'source_url', nev.source_url) end
    from pipeline.course_page_needed n join catalogue.courses c on c.id = n.course_id
    left join catalogue.providers pv on pv.id = n.provider_id left join ref.countries kc on kc.id = pv.country_id
    left join pipeline.evidence_artifacts nev on p_detail and nev.id = n.last_refused_evidence
   where n.state = 'open' and c.lifecycle_status = 'active'
     and not exists (select 1 from catalogue.course_links l where l.course_id = n.course_id and l.link_type = 'official_course' and l.status = 'active')
     and (p_kind is null or p_kind = 'course_page_needed') and (p_provider_id is null or n.provider_id = p_provider_id)
     and (p_keys is null or 'course_page_needed:' || n.course_id::text = any (p_keys))
  union all
  -- counsellor reports from Zoho
  select 'counsellor_report', d.id::text, z.pid, coalesce(d.detail->>'label', d.field_code), coalesce(d.detail->>'note', 'Reported by a counsellor'), null, d.created_at,
         case when p_detail then d.detail end
    from pipeline.data_flags d
    cross join lateral (select coalesce((select c.provider_id from catalogue.courses c where d.entity_type = 'course' and c.id = d.entity_id), case when d.entity_type = 'provider' then d.entity_id end) pid) z
   where d.flag_code = 'reported' and d.status = 'open'
     and (p_kind is null or p_kind = 'counsellor_report') and (p_provider_id is null or z.pid = p_provider_id) and (p_keys is null or 'counsellor_report:' || d.id::text = any (p_keys))
  union all
  -- CF-247 20 Oct 2026: providers whose every registered course left the register (from the retired Review queue)
  select 'provider_departure', d.id::text, d.provider_id, coalesce(p.display_name, p.canonical_name),
         'Every registered course left the register (' || d.courses_retired || ' course' || case when d.courses_retired = 1 then '' else 's' end || '). Closed, merged into another provider, or still operating?',
         null, d.created_at, case when p_detail then jsonb_build_object('departure_id', d.id, 'courses_retired', d.courses_retired, 'note', d.note) end
    from pipeline.layer1_provider_departures d left join catalogue.providers p on p.id = d.provider_id where d.status = 'needs_review'
     and (p_kind is null or p_kind = 'provider_departure') and (p_provider_id is null or d.provider_id = p_provider_id)
     and (p_keys is null or 'provider_departure:' || d.id::text = any (p_keys))
$function$
