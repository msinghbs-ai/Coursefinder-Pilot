-- CF-247, 8 Oct 2026 (Platform Admin: send for review, do not block the hosts). 76 colleges have no website on record, so the course-page search
-- bound some of their courses to third-party course directories (oneuedu.com, findthecourses.com.au, australiancourses.com.au, courses.com.au,
-- search.acir.com.au, higherstudy.com, coursesearch.studymelbourne.vic.gov.au, topaustraliauniversities.com). CRICOS and the other registers confirm
-- the course; finer details (intakes, English, the course page) can only be confirmed on the provider's own course page. Values admitted from
-- those directory pages go to Layer 4 review, one item per course and field, with the directory and page named. The value stays shown until a
-- person decides; Approve keeps it as it is. Nothing is blocked or removed here.
do $p$
declare v_i int; v_e int; v_l int;
  v_hosts text[] := array['oneuedu.com','australiancourses.com.au','findthecourses.com.au','courses.com.au','search.acir.com.au','higherstudy.com','coursesearch.studymelbourne.vic.gov.au','topaustraliauniversities.com'];
begin
  create temporary table dir_pages on commit drop as
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, substring(pg.url from '^https?://(?:www\.)?([^/:?#]+)') host
      from pipeline.coverage_course_pages pg
     where substring(pg.url from '^https?://(?:www\.)?([^/:?#]+)') = any(v_hosts);

  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  select 'course', d.course_id, 'course_intake', d.evidence_id,
         jsonb_agg(distinct i.intake_label),
         jsonb_build_object('intakes', jsonb_agg(distinct jsonb_build_object('intake_label', i.intake_label, 'source_intake_key', null))),
         'pending',
         format('Read from a third-party course directory (%s, %s), not the provider''s own site: no website is on record for this provider. CRICOS confirms the course; confirm the intakes on the provider''s own course page. Approve keeps them as they are; the value stays shown until decided. Platform Admin, 8 Oct 2026.', d.host, d.url),
         'CF-CHG-20260915-247'
    from dir_pages d join catalogue.course_intakes i on i.course_id = d.course_id and i.evidence_id = d.evidence_id and i.status = 'active'
   where not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = d.course_id and r.field_code = 'course_intake' and r.status = 'pending')
   group by d.course_id, d.evidence_id, d.host, d.url;
  get diagnostics v_i = row_count;

  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  select 'course', d.course_id, 'course_english', d.evidence_id,
         jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score)),
         jsonb_build_object('english_requirements', jsonb_agg(jsonb_build_object('notes', 'Third-party directory page, kept after review', 'test_code', t.code, 'overall_score', e.overall_score, 'component_scores', coalesce(e.component_scores, '{}'::jsonb)))),
         'pending',
         format('Read from a third-party course directory (%s, %s), not the provider''s own site: no website is on record for this provider. CRICOS confirms the course; confirm the English requirement on the provider''s own course page. Approve keeps it as it is; the value stays shown until decided. Platform Admin, 8 Oct 2026.', d.host, d.url),
         'CF-CHG-20260915-247'
    from dir_pages d join catalogue.course_english_requirements e on e.course_id = d.course_id and e.evidence_id = d.evidence_id and e.status = 'active'
    join ref.english_tests t on t.id = e.english_test_id
   where not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = d.course_id and r.field_code = 'course_english' and r.status = 'pending')
   group by d.course_id, d.evidence_id, d.host, d.url;
  get diagnostics v_e = row_count;

  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  select distinct on (d.course_id) 'course', d.course_id, 'official_course_url', d.evidence_id,
         jsonb_build_array(l.url), jsonb_build_object('course_url', l.url), 'pending',
         format('The official course page on record is a third-party course directory page (%s), not the provider''s own site: no website is on record for this provider. Find the provider''s own course page and edit the address, or reject. The link stays shown until decided. Platform Admin, 8 Oct 2026.', d.host),
         'CF-CHG-20260915-247'
    from dir_pages d join catalogue.course_links l on l.course_id = d.course_id and l.url = d.url and l.status = 'active'
   where not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = d.course_id and r.field_code = 'official_course_url' and r.status = 'pending')
   order by d.course_id, l.is_primary desc;
  get diagnostics v_l = row_count;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'directory_source_review', 'values read from third-party course directories',
          jsonb_build_object('hosts', v_hosts, 'intake_items', v_i, 'english_items', v_e, 'course_link_items', v_l, 'decision', 'Platform Admin 8 Oct 2026: review, do not block'),
          '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $p$;
