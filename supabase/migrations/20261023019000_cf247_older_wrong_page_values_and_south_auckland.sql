-- CF-247 (23 Oct 2026). Platform Admin 16:02 decisions after the wrong-page take-back (migration 20261023017000):
-- 1 "Take back 3,462, re-read 2,023": the take-back covered values read from the course's current page copy only. Values the AI reader
--   took on 14 Oct from an earlier page that was later replaced were missed (the Diploma in Architectural Studies took "3 years" from the
--   Bachelor of Architectural Studies page; the Diploma in Sport, Health and Physical Education from the Bachelor's page).
--   a) a course whose page is now found to be another course's (status mismatch): every AI value from an earlier page is taken back;
--   b) a course that now has its correct page (bound or ambiguous) but whose value came from a different page: the value is taken back
--      and read again from the correct page (one Read with AI job per university, fields as taken back).
--   Values from an older copy of the same page are kept. Each value is recorded in pipeline.enrich_value_retractions. Campus links from
--   those pages are removed by the admin-repo paste file docs/platform/wrong-page-values/PASTE-20261023-older-wrong-page-campus-links.sql,
--   which then queues the campus re-reads (a re-read does not link a campus the course already has, so it must follow the removal).
-- 2 "Add it, Auckland region": the University of Auckland's South Auckland campus (Te Papa Ako o Tai Tonga, 6 Osterley Way, Manukau,
--   from the university's campus page), linked to the Diploma in Arts, whose page names it.
-- Replaces: nothing
-- Retires: nothing

-- 1 values from an earlier, different page, or any earlier page of a course now found to have another course's page ------------------
create temp table _older on commit drop as
select i.id, i.course_id, i.provider_id, i.field, i.value, i.quote, i.evidence_id, e.source_url, g.status cur_status,
       case when g.status = 'mismatch' then 'take_back' else 'read_again' end act
  from pipeline.field_enrich_items i
  join pipeline.evidence_artifacts e on e.id = i.evidence_id
  join pipeline.coverage_course_pages g on g.course_id = i.course_id
 where i.source = 'ai_stored' and i.state = 'filled' and i.course_id is not null and i.evidence_id is distinct from g.evidence_id
   and not exists (select 1 from pipeline.enrich_value_retractions r where r.item_id = i.id)
   and (g.status = 'mismatch'
        or (g.status in ('bound', 'ambiguous')
            and lower(rtrim(e.source_url, '/')) not in (lower(rtrim(g.url, '/')), lower(rtrim(coalesce(g.candidates->>'final_url', ''), '/')))));

insert into pipeline.enrich_value_retractions(item_id, course_id, provider_id, field, value, quote, evidence_id, page_url, page_heading, reason)
select o.id, o.course_id, o.provider_id, o.field, o.value, o.quote, o.evidence_id, o.source_url, null,
       case o.act when 'take_back' then 'read from an earlier page; the course''s page is now found to be another course''s; Platform Admin 23 Oct 2026 16:02: take back'
                  else 'read from an earlier, different page; read again from the course''s own page; Platform Admin 23 Oct 2026 16:02: re-read' end
  from _older o;

update catalogue.courses c set delivery_mode = null, updated_at = now()
  from _older o where o.field = 'delivery' and c.id = o.course_id and c.delivery_mode = o.value->>'mode';
update catalogue.courses c set duration_value = null, duration_unit = null, updated_at = now()
  from _older o where o.field = 'duration' and c.id = o.course_id and c.duration_value = (o.value->>'value')::numeric and c.duration_unit is not distinct from o.value->>'unit';
update catalogue.courses c set open_to_international = null, updated_at = now()
  from _older o where o.field = 'international' and c.id = o.course_id and c.open_to_international = (o.value->>'open')::boolean;
update catalogue.course_intakes ci set status = 'withdrawn'
  from _older o where o.field = 'intakes' and ci.course_id = o.course_id and ci.evidence_id = o.evidence_id and ci.status = 'active'
   and ci.source_intake_key like o.course_id::text || ':ai:%';

update pipeline.enrich_value_retractions r set cleared = true
  from _older o join catalogue.courses c on c.id = o.course_id
 where r.item_id = o.id and ((o.field = 'delivery' and nullif(btrim(c.delivery_mode), '') is null)
     or (o.field = 'duration' and c.duration_value is null) or (o.field = 'international' and c.open_to_international is null)
     or (o.field = 'intakes' and not exists (select 1 from catalogue.course_intakes ci where ci.course_id = o.course_id and ci.evidence_id = o.evidence_id
                                              and ci.status = 'active' and ci.source_intake_key like o.course_id::text || ':ai:%')));

update pipeline.field_enrich_items i set state = 'skipped', updated_at = now(),
       reason = case o.act when 'take_back' then 'taken back: read from an earlier page; the course''s page is another course''s'
                           else 'taken back: read from an earlier, different page; read again from the course''s own page' end
  from _older o where o.id = i.id;

-- read again from the course's own page: one Read with AI job per university, for the fields taken back
create temp table _jobs on commit drop as
select o.provider_id, gen_random_uuid() job_id, jsonb_agg(distinct o.course_id) course_ids, jsonb_agg(distinct o.field) fields, count(distinct o.course_id) n
  from _older o where o.act = 'read_again' and o.field <> 'campus' group by o.provider_id;

insert into pipeline.admin_jobs(id, kind, lane, state, title, args, progress, requested_by, reason, scope)
select j.job_id, 'enrich_fields', 'enrich', 'queued',
       left('Read with AI again from the correct page · ' || coalesce(p.display_name, p.canonical_name), 200),
       jsonb_build_object('read_now', true, 'countries', '[]'::jsonb, 'provider_ids', jsonb_build_array(j.provider_id), 'course_ids', j.course_ids,
                          'fields', j.fields, 'ai', true, 'scraper', false),
       jsonb_build_object('done', 0, 'total', 0), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid,
       'Platform Admin 23 Oct 2026 16:02: values read from an earlier, different page are read again from the course''s own page', j.n || ' courses'
  from _jobs j join catalogue.providers p on p.id = j.provider_id;

insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
select distinct j.job_id, o.provider_id, o.course_id, o.field, 'queued'
  from _older o join _jobs j on j.provider_id = o.provider_id where o.act = 'read_again' and o.field <> 'campus'
on conflict do nothing;

insert into search.refresh_requests(requested_by) select 'Wrong-page values taken back'
 where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'Wrong-page values taken back');

-- 2 the University of Auckland's South Auckland campus ------------------------------------------------------------------------------
insert into catalogue.campuses(stable_key, provider_id, name, country_id, subdivision_id, city, address_line1, status, publication_status)
select 'campus:studysearch:e096aba7-e1eb-4903-9a63-2bfb71e9a8b8:south-auckland', k.provider_id, 'South Auckland', k.country_id, k.subdivision_id,
       'Auckland', '6 Osterley Way, Manukau', 'active', 'published'
  from catalogue.campuses k where k.id = '767d87b9-9c21-454f-9516-6c1fbc975926'
on conflict (stable_key) do nothing;

insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary, evidence_id)
select 'ecae5b4f-0b13-4ef0-ad37-64f7ba208576'::uuid, k.id, 'on_campus', false, 'c987937d-f777-4fa3-9d45-f76de648d368'::uuid
  from catalogue.campuses k where k.stable_key = 'campus:studysearch:e096aba7-e1eb-4903-9a63-2bfb71e9a8b8:south-auckland'
on conflict do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('catalogue', 'campus_added', 'campus:studysearch:e096aba7-e1eb-4903-9a63-2bfb71e9a8b8:south-auckland',
        jsonb_build_object('reason', 'Platform Admin 23 Oct 2026 16:02: Add it, Auckland region', 'source', 'https://www.auckland.ac.nz/en/on-campus/our-campuses/campus-locations/south-auckland-campus.html'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);

select (select count(*) from pipeline.enrich_value_retractions where reason like '%16:02%') || ' older wrong-page values taken back; South Auckland campus added' ok;
