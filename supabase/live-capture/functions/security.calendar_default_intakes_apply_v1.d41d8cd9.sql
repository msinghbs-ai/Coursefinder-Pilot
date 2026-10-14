CREATE OR REPLACE FUNCTION security.calendar_default_intakes_apply_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare r record; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}';
  v_names text[] := array['January','February','March','April','May','June','July','August','September','October','November','December'];
begin
  for r in
    with prov as (
      select distinct x.provider_id, security.calendar_default_months(x.provider_id) months
        from pipeline.provider_policy_proposals x join catalogue.providers pv on pv.id = x.provider_id join ref.countries k on k.id = pv.country_id
       where x.kind = 'intake_calendar' and x.status = 'approved' and k.iso_alpha2 = 'AU' and pv.canonical_name !~* '\muniversity\M'),
    cal as (
      select p.provider_id, p.months, s.evidence_id, s.url, s.content_hash
        from prov p join lateral (select f.evidence_id, f.url, f.content_hash from pipeline.provider_fact_sources f
                                   where f.provider_id = p.provider_id and f.kind = 'intake_calendar' and f.evidence_id is not null and f.content_hash is not null
                                   order by (f.found_via = 'manual') desc, f.rank limit 1) s on true
       where cardinality(p.months) > 0)
    select c.id course_id, cal.provider_id, cal.months, cal.evidence_id, cal.url, cal.content_hash
      from cal join catalogue.courses c on c.provider_id = cal.provider_id
     where c.lifecycle_status = 'active'
       and exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')
       and not exists (select 1 from catalogue.course_intakes i where i.course_id = c.id)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'intakes')
       and not exists (select 1 from pipeline.layer4_review_items l where l.entity_id = c.id and l.field_code = 'course_intake' and l.status = 'pending' and l.proposed_value is not null)
     limit 500
  loop
    begin
      perform security.coverage_apply_course_v1(r.course_id, security.coverage_sweep_source(r.provider_id), r.evidence_id, r.url, r.content_hash,
        jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', v_names[m], 'source_intake_key', 'calendar_default:' || r.course_id || ':' || lower(v_names[m]))) from unnest(r.months) m)));
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if v_ok > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select distinct 'courses', 'course_intake', security.coverage_sweep_source(c.provider_id), 'approved', 'CF-CHG-20260915-247; Decision 241 (college intakes from the approved calendar)', now(), now(), now()
      from catalogue.courses c where c.id = any(v_courses)
       and not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_intake' and g.source_id = security.coverage_sweep_source(c.provider_id));
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('calendar', 'default_intakes', 'Intakes from the approved calendar for college courses whose page names none', jsonb_build_object('courses', v_ok, 'refused', v_err, 'decision', 'Decision 241'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('filled', v_ok, 'refused', v_err, 'last_error', v_last);
end $function$
