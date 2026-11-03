-- CF-247 Release B: before the migration. A course whose delivery was skipped as "the page does not state it" (the coverage cache's blanket
-- "not on page") and one whose duration had no source at all; today's behaviour is shown on the live definitions, then the migration
-- classifies both (backfill) and the coverage cache shows the class.
insert into catalogue.providers(id, country_id, canonical_name) values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a2', 'Fixture Polytechnic');
insert into pipeline.evidence_artifacts(id, storage_path, content_hash) values ('00000000-0000-0000-0000-0000000000e0', 'old/page.gz', 'hash-old');
insert into catalogue.courses(id, provider_id, canonical_title) values
 ('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-0000000000b1', 'Old Course'),
 ('00000000-0000-0000-0000-0000000000c9', '00000000-0000-0000-0000-0000000000b1', 'No Page Course');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis, evidence_id, read_at) values
 ('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-0000000000b1', 'https://x.example/old', 'bound', 'read', 'exact_title', '00000000-0000-0000-0000-0000000000e0', now() - interval '3 days');
insert into pipeline.admin_jobs(id, kind, state, args) values ('00000000-0000-0000-0000-00000000f000', 'enrich_fields', 'done', '{"standing": true}');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, evidence_id, reason) values
 ('00000000-0000-0000-0000-00000000f000', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c0', 'delivery', 'skipped', 'ai_stored', '00000000-0000-0000-0000-0000000000e0', 'the page does not state it'),
 ('00000000-0000-0000-0000-00000000f000', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c9', 'duration', 'skipped', null, null, 'no allowed source had a value');
do $$
declare v jsonb;
begin
  perform security.course_coverage_build_v1();
  if (select state from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c0' and attribute = 'delivery') <> 'not_on_page'
     or (select state from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c9' and attribute = 'duration') <> 'not_on_page' then
    raise exception 'before: expected the blanket not_on_page'; end if;
  raise notice 'before: delivery read and not stated, and duration with no source at all, are both "not_on_page" (the blanket state)';
  if security.field_sources_for_v1('NZ', 'delivery') <> array['adapter', 'ai_stored'] then raise exception 'before: source rules'; end if;
end $$;
