CREATE OR REPLACE FUNCTION security.enrich_item_held_v1(p_course uuid, p_field text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 31 Oct 2026 (StudySearch D5a): a course whose page binding is a mismatch is held until a page is bound again (0 of 11,332 such items filled in 4 days)
  select exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.status = 'mismatch' and coalesce(g.basis, '') <> 'manual')
      or exists (select 1 from pipeline.enrichment_flags f
                  where f.entity = 'course' and f.entity_key = p_course::text and f.field in (p_field, '')
                    and ((f.state = 'raised' and f.reason_code in ('enrich_no_value', 'manual_hold'))
                         or (f.state = 'counting' and f.reason_code = 'enrich_no_value'
                             and f.flagged_at > now() - make_interval(days => security.pipeline_num_v1('gaps.recheck_days', 60)::int)
                             and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.evidence_id is not null
                                               and g.evidence_id::text is distinct from f.input_mark and g.read_at > f.flagged_at))))
$function$
