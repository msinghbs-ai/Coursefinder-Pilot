CREATE OR REPLACE FUNCTION security.enrichment_flags_refresh_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tail int := 0; v_nf int := 0; v_cap int := security.retry_cap_v1('ai_match'); v_on boolean := security.pipeline_num_v1('enrich.focus_top_n', 50) > 0;
begin
  -- Australian courses of providers outside the focus list that still lack a course page, English or intakes: not searched further
  if v_on then
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    select 'course', d.course_id::text, d.provider_id, 'course_page', 'outside_focus',
           'Not searched further: the provider is outside the top Australian providers by gaps (Pipeline settings › Waste rules); register data only', 'waste-guard'
      from search.course_documents d
     where d.country_code = 'AU' and (d.official_course_url is null or not d.has_english or not d.has_intake)
       and not security.enrich_focus_v1(d.provider_id)
    on conflict (entity, entity_key, field, reason_code) do update set cleared_at = null where pipeline.enrichment_flags.cleared_at is not null;
    get diagnostics v_tail = row_count;
  end if;
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'outside_focus' and f.cleared_at is null and (not v_on or security.enrich_focus_v1(f.provider_id));
  -- courses whose page was not found after the useful AI attempts
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
  select 'course', q.course_id::text, max(q.provider_id::text)::uuid, 'official_url', 'page_not_found',
         format('No course page found after %s AI attempt(s) (no further candidates, or later attempts rarely succeed: Pipeline settings › Waste rules)', count(*)), 'waste-guard'
    from pipeline.coverage_ai_match q
   where not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = q.course_id and p.status = 'bound')
   group by q.course_id
  having (count(*) >= v_cap or bool_or(q.state = 'no_candidates')) and bool_and(q.state in ('none', 'no_candidates', 'error'))
  on conflict (entity, entity_key, field, reason_code) do nothing;
  get diagnostics v_nf = row_count;
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'page_not_found' and f.cleared_at is null
     and exists (select 1 from pipeline.coverage_course_pages p where p.course_id::text = f.entity_key and p.status = 'bound');
  return jsonb_build_object('outside_focus', v_tail, 'page_not_found', v_nf);
end $function$
