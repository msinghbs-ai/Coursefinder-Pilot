-- CF-247 Release B: every case of the change on the migrated fixture database. Each block raises an exception on a wrong result and a notice
-- "ok ..." on a right one.
create table pipeline.fx_flags (course_id uuid, field text, reason text);
create or replace function security.flag_raise_v1(p_entity text, p_key text, p_provider uuid, p_field text, p_code text, p_reason text, a text, b text, c text, d jsonb, e text, f text)
returns void language sql as $$ insert into pipeline.fx_flags values (p_key::uuid, p_field, p_reason) $$;

-- the fixture: one NZ provider; course c1 with a stored, proven page (copy e1, hash h1) missing every page field; course c2 online-only
insert into pipeline.evidence_artifacts(id, storage_path, content_hash) values
 ('00000000-0000-0000-0000-0000000000e1', 'c1/page.gz', 'h1'), ('00000000-0000-0000-0000-0000000000e2', 'c1/page2.gz', 'h1'),
 ('00000000-0000-0000-0000-0000000000e3', 'c1/page3.gz', 'h3'), ('00000000-0000-0000-0000-0000000000e4', 'c2/page.gz', 'h4');
insert into catalogue.courses(id, provider_id, canonical_title, delivery_mode) values
 ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', 'Bachelor of Fixtures', null),
 ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1', 'Online Certificate', 'online'),
 ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1', 'Diploma of Locks', null);
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis, evidence_id, read_at) values
 ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', 'https://x.example/c1', 'bound', 'read', 'exact_title', '00000000-0000-0000-0000-0000000000e1', now() - interval '1 day'),
 ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1', 'https://x.example/c2', 'bound', 'read', 'exact_title', '00000000-0000-0000-0000-0000000000e4', now() - interval '1 day'),
 ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1', 'https://x.example/c3', 'bound', 'read', 'exact_title', '00000000-0000-0000-0000-0000000000e4', now() - interval '1 day');
insert into catalogue.course_intakes(course_id, intake_year, intake_label, status) values ('00000000-0000-0000-0000-0000000000c1', 2027, 'February', 'active');
insert into catalogue.course_english_requirements values ('00000000-0000-0000-0000-0000000000c3', 'active');
insert into pipeline.manual_locks values ('course', '00000000-0000-0000-0000-0000000000c3', 'delivery');

-- 1 the backfill classified the absences settled before the change; the coverage cache shows the class for delivery and duration
do $$
begin
  if (select absence_class from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c0' and field = 'delivery') <> 'not_on_this_page'
     or (select content_hash from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c0' and field = 'delivery') <> 'hash-old' then
    raise exception '1: delivery read and not stated is not_on_this_page with its content hash'; end if;
  if (select absence_class from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c9' and field = 'duration') <> 'needs_source_discovery' then
    raise exception '1: no source at all must be needs_source_discovery (D3), got %', (select absence_class from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c9' and field = 'duration'); end if;
  perform security.course_coverage_build_v1();
  if (select state || '/' || absence_class from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c0' and attribute = 'delivery') <> 'not_on_page/not_on_this_page' then
    raise exception '1: delivery coverage'; end if;
  if (select state || '/' || absence_class from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c9' and attribute = 'duration') <> 'site_known/needs_source_discovery'
     and (select state || '/' || absence_class from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c9' and attribute = 'duration') <> 'no_website/needs_source_discovery' then
    raise exception '1: duration with no source shows the page state, not "not on page": %', (select state || '/' || absence_class from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c9' and attribute = 'duration'); end if;
  raise notice 'ok 1 backfill: read-and-absent delivery is not_on_this_page (hash kept); no-source duration is needs_source_discovery and shows its page state on Coverage';
end $$;

-- 2a the migration ships multi-field reading off (Integration Controller 3 Nov 2026: switched on as a separate, recorded setting change)
do $$ begin
  if (select value from pipeline.platform_toolset_settings where key = 'enrich.multi_field_on') <> '0'::jsonb then raise exception 'FAIL 2a multi-field must ship off'; end if;
  raise notice 'ok 2a multi-field ships off';
end $$;
update pipeline.platform_toolset_settings set value = '1' where key = 'enrich.multi_field_on';
-- 2 one item for intakes on a stored page brings the course's other missing fields onto the same copy (standing task)
insert into pipeline.admin_jobs(id, kind, state, args) values ('00000000-0000-0000-0000-00000000f001', 'enrich_fields', 'running', '{"standing": true, "ai": true}');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) values
 ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', 'intakes');
-- the intake rule must find intakes missing: c1's intake is made inactive for this case
update catalogue.course_intakes set status = 'withdrawn' where course_id = '00000000-0000-0000-0000-0000000000c1';
do $$
declare v text[];
begin
  perform security.enrich_fields_slice_v1('00000000-0000-0000-0000-00000000f001', 10);
  v := array(select field || ':' || state || ':' || source || ':' || coalesce(evidence_id::text, '-') from pipeline.field_enrich_items
              where job_id = '00000000-0000-0000-0000-00000000f001' and course_id = '00000000-0000-0000-0000-0000000000c1' order by field);
  if v <> array['campus:ai:ai_stored:00000000-0000-0000-0000-0000000000e1', 'delivery:ai:ai_stored:00000000-0000-0000-0000-0000000000e1',
                'description:ai:ai_stored:00000000-0000-0000-0000-0000000000e1', 'duration:ai:ai_stored:00000000-0000-0000-0000-0000000000e1',
                'english:ai:ai_stored:00000000-0000-0000-0000-0000000000e1', 'intakes:ai:ai_stored:00000000-0000-0000-0000-0000000000e1',
                'international:ai:ai_stored:00000000-0000-0000-0000-0000000000e1'] then raise exception '2: siblings %', v; end if;
  if not exists (select 1 from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f001' and field = 'campus_list' and state = 'waiting') then
    raise exception '2: a campus sibling brings the university''s campus list item'; end if;
  if exists (select 1 from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f001' and field = 'deadline') then
    raise exception '2: no deadline sibling without an active intake'; end if;
  raise notice 'ok 2 multi-field: one intakes item on the stored copy brings campus, delivery, description, duration, English and international onto the same copy (no deadline: no active intake; campus list item added)';
end $$;

-- 3 the lease takes the course's items together: one page, every field, in one worker call
do $$
declare v jsonb; n int;
begin
  v := public.svc_enrich_ai_next(1);
  n := jsonb_array_length(v->'pages'->0->'items');
  if jsonb_array_length(v->'pages') <> 1 or n <> 7 then raise exception '3: expected one page with 7 items, got % pages, % items', jsonb_array_length(v->'pages'), n; end if;
  if (select count(*) from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f001' and state = 'leased') <> 7 then raise exception '3: all leased'; end if;
  raise notice 'ok 3 lease: svc_enrich_ai_next(1) returns the course''s page once with all 7 fields (it used to return 1)';
end $$;

-- 4 the record: delivery found (admitted), intakes not stated (verified negative with hash and reader version), English quote not proved
--   (below the verified level), description sent on (resolved), a failed duration (evidence pending with a date)
do $$
declare v jsonb; id_of jsonb;
begin
  select jsonb_object_agg(field, id) into id_of from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f001' and course_id = '00000000-0000-0000-0000-0000000000c1';
  v := public.svc_enrich_ai_record(jsonb_build_array(
    jsonb_build_object('item_id', id_of->'delivery', 'value', jsonb_build_object('mode', 'on_campus'), 'quote', 'On campus', 'worker', 'coverage-sweep-worker-v0.59.4', 'prompt_version', 'course-fields-v1', 'model', 'openai/gpt-4.1-mini'),
    jsonb_build_object('item_id', id_of->'intakes', 'value', null, 'reason', 'the page does not state it'),  -- the course-fields answer carries no worker name
    jsonb_build_object('item_id', id_of->'english', 'value', null, 'reason', 'the quote does not name IELTS with a score', 'worker', 'coverage-sweep-worker-v0.59.4', 'prompt_version', 'course-fields-v1', 'model', 'openai/gpt-4.1-mini'),
    jsonb_build_object('item_id', id_of->'description', 'value', jsonb_build_object('about_course', true), 'worker', 'coverage-sweep-worker-v0.59.4', 'prompt_version', 'course-text-v1'),
    jsonb_build_object('item_id', id_of->'duration', 'error', 'HTTP 500: upstream', 'worker', 'coverage-sweep-worker-v0.59.4')));
  update pipeline.field_enrich_items set attempts = 3 where id = (id_of->>'duration')::bigint;
  update pipeline.field_enrich_items set state = 'failed', reason = 'no answer could be recorded after 3 tries' where id = (id_of->>'duration')::bigint;
  if (select absence_class || '/' || content_hash || '/' || reader_version || '/' || confidence from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c1' and field = 'intakes')
     <> 'not_on_this_page/h1/enrich_ai ai_stored openai/gpt-4.1-mini/0.85' then
    raise exception '4: intakes absence %', (select row_to_json(a) from pipeline.course_field_absence a where course_id = '00000000-0000-0000-0000-0000000000c1' and field = 'intakes'); end if;
  if (select absence_class || '/' || confidence from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c1' and field = 'english') <> 'not_on_this_page/0.5' then
    raise exception '4: english absence below the verified level'; end if;
  if exists (select 1 from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c1' and field in ('delivery', 'description') and resolved_at is null) then
    raise exception '4: filled values have no open absence'; end if;
  if (select absence_class from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c1' and field = 'duration') <> 'evidence_pending'
     or (select next_eligible_at from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c1' and field = 'duration') not between now() + interval '23 hours' and now() + interval '25 hours' then
    raise exception '4: failed read is evidence pending, due after absence.pending_recheck_hours'; end if;
  raise notice 'ok 4 record: filled values leave no absence; "not stated" on copy e1 is a verified negative (hash h1, reader version from the central model when the answer names none, 0.85); an unproved quote is below the verified level (0.5); a failed read is evidence pending for 24 hours';
end $$;

-- 5 D2: an unchanged copy (another evidence row, same content hash) is not read again for intakes; a changed copy is
insert into pipeline.admin_jobs(id, kind, state, args) values ('00000000-0000-0000-0000-00000000f002', 'enrich_fields', 'running', '{"standing": true, "ai": true}');
update pipeline.coverage_course_pages set evidence_id = '00000000-0000-0000-0000-0000000000e2', read_at = now() where course_id = '00000000-0000-0000-0000-0000000000c1';
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) values
 ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', 'intakes'),
 ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', 'english');
do $$
begin
  perform security.enrich_fields_slice_v1('00000000-0000-0000-0000-00000000f002', 10);
  if (select state || ':' || reason from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f002' and field = 'intakes')
     <> 'skipped:the same page copy was read for this before and did not state it' then raise exception '5: unchanged copy read again'; end if;
  if (select state from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f002' and field = 'english') <> 'ai' then
    raise exception '5: a negative below the verified level is read again'; end if;
  if (select absence_class from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c1' and field = 'intakes') <> 'not_on_this_page' then
    raise exception '5: the earlier classification is kept'; end if;
  if exists (select 1 from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f002' and field in ('intakes', 'duration', 'campus') and state = 'ai') then
    raise exception '5: siblings: no intakes (verified negative on this content), no duration (evidence pending not due), no campus (in flight)'; end if;
  raise notice 'ok 5 D2: a copy with the same content (e2, h1) is not read again for intakes and not added as a sibling; English (unproved before) is read; duration waits for its date';
end $$;
insert into pipeline.admin_jobs(id, kind, state, args) values ('00000000-0000-0000-0000-00000000f003', 'enrich_fields', 'running', '{"standing": true, "ai": true}');
update pipeline.coverage_course_pages set evidence_id = '00000000-0000-0000-0000-0000000000e3', read_at = now() where course_id = '00000000-0000-0000-0000-0000000000c1';
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) values
 ('00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', 'intakes');
do $$
begin
  if not security.field_absence_due_v1('00000000-0000-0000-0000-0000000000c1', 'intakes', '00000000-0000-0000-0000-0000000000e3') then raise exception '5b: a changed copy makes it due'; end if;
  perform security.enrich_fields_slice_v1('00000000-0000-0000-0000-00000000f003', 10);
  if (select state from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f003' and field = 'intakes') <> 'ai' then raise exception '5b: changed copy not read'; end if;
  raise notice 'ok 5b D2: a changed copy (e3, h3) makes intakes due and it is read again';
end $$;

-- 6 a person's task keeps to the fields they chose; a field locked by hand never becomes a sibling; switched off, nothing is added or grouped
insert into pipeline.admin_jobs(id, kind, state, args) values ('00000000-0000-0000-0000-00000000f004', 'enrich_fields', 'running', '{"ai": true, "fields": ["intakes", "duration"]}');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) values
 ('00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3', 'intakes');
do $$
declare v text[];
begin
  perform security.enrich_fields_slice_v1('00000000-0000-0000-0000-00000000f004', 10);
  v := array(select field from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f004' order by field);
  if v <> array['duration', 'intakes'] then raise exception '6: manual task siblings %', v; end if;
  raise notice 'ok 6 a person''s task (fields intakes, duration) gets only duration added; delivery (locked by hand) and fields they did not choose are not';
end $$;
insert into pipeline.admin_jobs(id, kind, state, args) values ('00000000-0000-0000-0000-00000000f005', 'enrich_fields', 'running', '{"standing": true, "ai": true}');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) values
 ('00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3', 'international');
do $$
begin
  if exists (select 1 from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f005' and field = 'delivery') then raise exception '6b: locked'; end if;
  update pipeline.platform_toolset_settings set value = '0' where key = 'enrich.multi_field_on';
  perform security.enrich_fields_slice_v1('00000000-0000-0000-0000-00000000f005', 10);
  if (select count(*) from pipeline.field_enrich_items where job_id = '00000000-0000-0000-0000-00000000f005') <> 1 then raise exception '6b: switched off adds nothing'; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'enrich.multi_field_on';
  raise notice 'ok 6b switched off (enrich.multi_field_on 0), one field at a time as before';
end $$;

-- 7 D3 and the other classes: no source is never a negative and raises no hold; identity, rolling, no intake, online campus, held, other page
insert into pipeline.admin_jobs(id, kind, state, args) values ('00000000-0000-0000-0000-00000000f006', 'enrich_fields', 'running', '{"standing": true}');
insert into pipeline.uni_adapter_results(course_id, fields, at) values ('00000000-0000-0000-0000-0000000000c3', '{"extra": {"duration": "2 years"}}', now());
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, evidence_id) values
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c9', 'english', 'queued', null, null),
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c2', 'campus', 'ai', 'ai_stored', '00000000-0000-0000-0000-0000000000e4'),
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c2', 'deadline', 'ai', 'ai_stored', '00000000-0000-0000-0000-0000000000e4'),
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3', 'duration', 'ai', 'ai_stored', '00000000-0000-0000-0000-0000000000e4'),
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3', 'deadline', 'ai', 'ai_stored', '00000000-0000-0000-0000-0000000000e4'),
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3', 'description', 'ai', 'ai_stored', '00000000-0000-0000-0000-0000000000e4'),
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3', 'campus', 'ai', 'ai_stored', null);
do $$
declare c text;
begin
  delete from pipeline.fx_flags;
  perform security.enrich_fields_slice_v1('00000000-0000-0000-0000-00000000f006', 10);  -- c9 english: no stored page, no allowed source
  if (select absence_class from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c9' and field = 'english') <> 'needs_source_discovery' then raise exception '7: no source'; end if;
  if exists (select 1 from pipeline.fx_flags) then raise exception '7: "no allowed source" must not raise the no-value hold (D3)'; end if;
  update pipeline.field_enrich_items set state = 'skipped', reason = 'the page names no campus' where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c2' and field = 'campus';
  update pipeline.field_enrich_items set state = 'skipped', reason = 'the page says applications are rolling (no date to hold)' where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c2' and field = 'deadline';
  update pipeline.field_enrich_items set state = 'skipped', reason = 'the page does not state it' where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c3' and field = 'duration';
  update pipeline.field_enrich_items set state = 'skipped', reason = 'no active intake to hold a deadline' where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c3' and field = 'deadline';
  update pipeline.field_enrich_items set state = 'skipped', reason = 'held: sentence_count: 6 sentence(s), outside the set range' where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c3' and field = 'description';
  update pipeline.field_enrich_items set state = 'skipped', reason = 'the page names no campus' where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c3' and field = 'campus';
  select string_agg(course_id::text || ':' || field || ':' || absence_class, ' ' order by course_id, field) into c from pipeline.course_field_absence
   where course_id in ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c3');
  if c <> '00000000-0000-0000-0000-0000000000c2:campus:not_applicable 00000000-0000-0000-0000-0000000000c2:deadline:explicitly_not_stated '
          || '00000000-0000-0000-0000-0000000000c3:campus:evidence_pending 00000000-0000-0000-0000-0000000000c3:deadline:not_applicable 00000000-0000-0000-0000-0000000000c3:duration:on_other_stored_page' then
    raise exception '7: classes %', c; end if;
  raise notice 'ok 7 D3: no stored source is needs_source_discovery and raises no hold; a campus "not on page" without its read copy (no evidence id) is never a negative (evidence pending); online-only campus is not_applicable; rolling is explicitly_not_stated; no intake is not_applicable; a duration in the adapter reading is on_other_stored_page; a held description keeps its previous state';
end $$;
do $$
begin
  update pipeline.field_enrich_items set state = 'skipped', reason = 'no correct course page: the page found is for another course'
   where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c9';
  -- (already skipped: a new item settles with the identity reason)
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values
   ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c9', 'intakes', 'queued');
  update pipeline.field_enrich_items set state = 'skipped', reason = 'no proven course page: the page found is not proved to be this course''s (E16)'
   where job_id = '00000000-0000-0000-0000-00000000f006' and course_id = '00000000-0000-0000-0000-0000000000c9' and field = 'intakes';
  if (select absence_class from pipeline.course_field_absence where course_id = '00000000-0000-0000-0000-0000000000c9' and field = 'intakes') <> 'identity_unresolved' then raise exception '7b'; end if;
  raise notice 'ok 7b an unproven page (E16) is identity_unresolved, due again when the course''s page identity changes';
end $$;

-- 8 the coverage cache: the class decides the state for delivery and duration; other fields keep their state
do $$
begin
  update catalogue.courses set delivery_mode = 'on_campus' where id = '00000000-0000-0000-0000-0000000000c1';  -- what the admission stub stands for
  perform security.course_coverage_build_v1();
  if (select state || '/' || absence_class from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c3' and attribute = 'duration') <> 'candidate/on_other_stored_page' then
    raise exception '8: duration on another stored page shows candidate'; end if;
  if (select state from pipeline.course_attribute_coverage where course_id = '00000000-0000-0000-0000-0000000000c1' and attribute = 'delivery') <> 'admitted' then raise exception '8: admitted'; end if;
  raise notice 'ok 8 coverage: duration found in another stored reading shows "candidate" (not "not on page"); filled delivery is admitted';
end $$;

-- 9 the gap queue's next batch: due when no standing task is open and the last run is old enough, sooner when work remains
do $$
begin
  update pipeline.admin_jobs set state = 'done' where kind = 'enrich_fields';
  if not security.field_gap_queue_due_v1() then raise exception '9: no run yet: due'; end if;
  insert into pipeline.admin_jobs(kind, state, args) values ('enrich_fields', 'running', '{"standing": true}');
  if security.field_gap_queue_due_v1() then raise exception '9: a standing task is open: not due'; end if;
  update pipeline.admin_jobs set state = 'done' where kind = 'enrich_fields';
  insert into pipeline.field_gap_queue_runs(run_at, outcome, items) values (now() - interval '30 minutes', 'done', 500);
  if security.field_gap_queue_due_v1() then raise exception '9: 30 minutes after a run: not due'; end if;
  update pipeline.field_gap_queue_runs set run_at = now() - interval '59 minutes 50 seconds';
  if not security.field_gap_queue_due_v1() then raise exception '9: the next hour after a run that found work: due'; end if;
  update pipeline.field_gap_queue_runs set outcome = 'idle', items = 0;
  if security.field_gap_queue_due_v1() then raise exception '9: a pass that found nothing waits gaps.idle_rerun_minutes'; end if;
  update pipeline.field_gap_queue_checkpoint set cursor_course_id = '00000000-0000-0000-0000-0000000000c1';
  if not security.field_gap_queue_due_v1() then raise exception '9: an unfinished pass continues'; end if;
  update pipeline.field_gap_queue_checkpoint set cursor_course_id = null;
  update pipeline.field_gap_queue_runs set run_at = now() - interval '6 hours';
  if not security.field_gap_queue_due_v1() then raise exception '9: after gaps.idle_rerun_minutes: due'; end if;
  if (select schedule || ' | ' || command from cron.job where jobname = 'field-gap-queue') <> '23 * * * * | select security.field_gap_queue_run_v1() where security.field_gap_queue_due_v1()' then
    raise exception '9: job'; end if;
  if (select description from pipeline.automation_catalogue where jobname = 'field-gap-queue') not like 'Checked every hour (CF-247 Release B): %field_gap_queue_due_v1%' then raise exception '9: catalogue'; end if;
  raise notice 'ok 9 gap queue: checked hourly; runs when no standing task is open and gaps.advance_minutes have passed with work remaining (or gaps.idle_rerun_minutes after an empty pass); catalogue updated';
end $$;

-- 10 every new setting has a label, a range or list, a unit and a used_by line
do $$
begin
  if exists (select 1 from pipeline.platform_toolset_settings where key in ('enrich.multi_field_on', 'enrich.multi_field_fields', 'enrich.multi_field_max_per_page',
               'absence.verified_min_confidence', 'absence.pending_recheck_hours', 'absence.coverage_fields', 'gaps.advance_minutes', 'gaps.idle_rerun_minutes')
              and (label = '' or unit is null or used_by is null or (kind = 'number' and (min_value is null or max_value is null)))) then raise exception '10: settings'; end if;
  raise notice 'ok 10 settings: label, range, unit and used_by on all eight';
end $$;

-- 11 job source-proof-feed records every run: nothing waiting (idle, no_page_proof_input); a course routed to course-relink (done); nothing new (held)
do $$
declare v jsonb;
begin
  delete from pipeline.course_page_proofs;
  v := security.source_proof_feed_v1();
  if (select outcome || '/' || hold_reason from pipeline.source_proof_feed_runs order by id desc limit 1) <> 'idle/no_page_proof_input' then raise exception '11: idle run'; end if;
  insert into pipeline.course_page_proofs values ('00000000-0000-0000-0000-0000000000c9', 'k1', false, now());
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis) values
   ('00000000-0000-0000-0000-0000000000c9', '00000000-0000-0000-0000-0000000000b1', 'https://x.example/c9', 'mismatch', 'identity_mismatch', null);
  v := security.source_proof_feed_v1();
  if (select outcome || '/' || coalesce(hold_reason, '-') || '/' || (routed->>'relink') from pipeline.source_proof_feed_runs order by id desc limit 1) <> 'done/-/1' then
    raise exception '11: routed run %', (select row_to_json(r) from pipeline.source_proof_feed_runs r order by id desc limit 1); end if;
  v := security.source_proof_feed_v1();
  if (select outcome || '/' || hold_reason from pipeline.source_proof_feed_runs order by id desc limit 1) <> 'held/requests_open' then
    raise exception '11: open request %', (select row_to_json(r) from pipeline.source_proof_feed_runs r order by id desc limit 1); end if;
  if (select count(*) from pipeline.source_proof_feed_runs) <> 3 or v <> jsonb_build_object('settled', 0, 'routed', '{}'::jsonb, 'ms', v->'ms') then raise exception '11: answer unchanged, one row a run'; end if;
  if (select description from pipeline.automation_catalogue where jobname = 'source-proof-feed') not like '%source_proof_feed_runs%' then raise exception '11: catalogue'; end if;
  raise notice 'ok 11 source-proof-feed: one run row each time, idle with no_page_proof_input when no course waits, done when a course is routed to course-relink, held with requests_open when every waiting course has an open request; its answer is unchanged';
end $$;

-- 12 a run held for courses waiting for page proof advances the next hour (the feed is not starved between gap runs)
do $$
begin
  update pipeline.admin_jobs set state = 'done' where kind = 'enrich_fields';
  delete from pipeline.field_gap_queue_runs;
  insert into pipeline.field_gap_queue_runs(run_at, outcome, hold_reason, items) values (now() - interval '61 minutes', 'held', 'waiting_for_page_proof', 0);
  if not security.field_gap_queue_due_v1() then raise exception '12: held for page proof: due the next hour'; end if;
  raise notice 'ok 12 a gap run held for page proof is due again after gaps.advance_minutes, so page proofs keep reaching source-proof-feed';
end $$;
