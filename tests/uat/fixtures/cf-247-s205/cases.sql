-- CF-247 UR-18 slice 1: isolated fixture cases (local Postgres only). Run by run-fixture.sh after schema.sql, the two *.before.sql files and
-- the migration. Seeds one Australian university with 7 campuses and 130 courses, then runs each case in its own transaction, rolled back,
-- so every case starts from the same seed. A case that fails raises an exception and stops the run (psql ON_ERROR_STOP).
\set ON_ERROR_STOP 1
\pset tuples_only on
create schema fx;
create function fx.id(t text) returns uuid language sql immutable as $$ select md5(t)::uuid $$;
create function fx.as_user(t text) returns void language sql as $$ select set_config('request.jwt.claim.sub', fx.id(t)::text, true) $$;
create function fx.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'FAIL %: got %, expected %', label, a, b; end if; end $$;
create function fx.raises(q text, pattern text, label text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if sqlerrm !~* pattern then raise exception 'FAIL %: error "%" does not match "%"', label, sqlerrm, pattern; end if; return;
  end;
  raise exception 'FAIL %: no error (expected "%")', label, pattern;
end $$;
create function fx.l4(a text, args jsonb) returns jsonb language sql as $$ select public.admin_layer4_inbox(a, args) $$;
create function fx.prev(f text, v jsonb, extra jsonb default '{}') returns jsonb language sql as $$
  select fx.l4('bulk_preview', jsonb_build_object('provider_id', fx.id('P1'), 'field', f, 'value', v, 'limit', 500) || extra) $$;
create function fx.apply(f text, v jsonb, fp text, extra jsonb default '{}') returns jsonb language sql as $$
  select fx.l4('bulk_apply', jsonb_build_object('provider_id', fx.id('P1'), 'field', f, 'value', v, 'fingerprint', fp, 'reason', 'Fixture: official course pages state this') || extra) $$;
create function fx.set(k text, v numeric) returns void language sql as $$ update pipeline.platform_toolset_settings set value = to_jsonb(v) where toolset_key = 'pipeline' and key = k $$;
create function fx.cls(p jsonb, title text) returns text language sql as $$ select r->>'class' from jsonb_array_elements(p->'rows') r where r->>'title' = title $$;

-- seed
insert into auth.users values (fx.id('admin'), 'admin@fixture'), (fx.id('curator'), 'curator@fixture'), (fx.id('operator'), 'operator@fixture');
insert into security.user_roles values (fx.id('admin'), 'platform_admin', null), (fx.id('curator'), 'curator', null), (fx.id('operator'), 'pipeline_operator', null);
insert into pipeline.sources(id, source_type) values (fx.id('src-l4'), 'layer4_human_review'), (fx.id('src-site'), 'provider_site');
insert into ref.countries values (fx.id('AU'), 'AU', 'Australia'), (fx.id('NZ'), 'NZ', 'New Zealand');
insert into ref.subdivisions values (fx.id('AU-NSW'), fx.id('AU'), 'AU-NSW', 'New South Wales'), (fx.id('AU-VIC'), fx.id('AU'), 'AU-VIC', 'Victoria'),
  (fx.id('AU-QLD'), fx.id('AU'), 'AU-QLD', 'Queensland'), (fx.id('AU-TAS'), fx.id('AU'), 'AU-TAS', 'Tasmania'), (fx.id('NZ-AUK'), fx.id('NZ'), 'NZ-AUK', 'Auckland');
insert into ref.study_levels(id, code, name) values (fx.id('UG'), 'ug', 'Bachelor'), (fx.id('PG'), 'pg', 'Master');
insert into catalogue.providers values (fx.id('P1'), 'Fixture University', null, fx.id('AU')), (fx.id('P2'), 'Fixture Two', null, fx.id('AU'));
insert into pipeline.evidence_artifacts(id, source_id, evidence_type, source_url, storage_path, captured_at)
select fx.id('ev-' || c), fx.id('src-site'), 'campus_page', 'https://fixture.edu.au/campuses', 'fixture/campuses.html.gz', '2026-10-20T00:00:00Z' from unnest(array['C1','C2','C4','C6','C7']) c;
insert into catalogue.campuses(id, provider_id, name, campus_code, country_id, subdivision_id, city, postcode, source_id, evidence_id) values
 (fx.id('C1'), fx.id('P1'), 'Melbourne City Campus', 'MEL', fx.id('AU'), null, 'Melbourne', '3000', fx.id('src-site'), fx.id('ev-C1')),
 (fx.id('C2'), fx.id('P1'), 'Sydney Campus', 'SYD', fx.id('AU'), fx.id('AU-NSW'), 'Sydney', '2000', fx.id('src-site'), fx.id('ev-C2')),
 (fx.id('C3'), fx.id('P1'), 'Brisbane Campus', 'BNE', fx.id('AU'), null, 'Brisbane', '4000', null, null),
 (fx.id('C4'), fx.id('P1'), 'Geelong Campus', 'GEE', fx.id('AU'), null, 'Geelong', '3220', fx.id('src-site'), fx.id('ev-C4')),
 (fx.id('C6'), fx.id('P1'), 'Ballarat Campus', 'BAL', fx.id('AU'), null, 'Ballarat', '3350', fx.id('src-site'), fx.id('ev-C6')),
 (fx.id('C7'), fx.id('P1'), 'Hobart Campus', 'HOB', fx.id('AU'), null, 'Hobart', '7000', fx.id('src-site'), fx.id('ev-C7')),
 (fx.id('C8'), fx.id('P1'), 'Perth Campus', 'PER', fx.id('AU'), null, 'Perth', null, fx.id('src-site'), null),
 (fx.id('Q1'), fx.id('P2'), 'Sydney', null, fx.id('AU'), fx.id('AU-NSW'), null, '2000', fx.id('src-site'), null),
 (fx.id('Q2'), fx.id('P2'), 'Sydney Manly Beach', null, fx.id('AU'), fx.id('AU-NSW'), null, '2095', fx.id('src-site'), null);
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('campus', fx.id('C4'), 'subdivision_id', 'value');
insert into pipeline.campus_region_cleared(campus_id, reason) values (fx.id('C6'), 'fixture: region copied from the provider, campus elsewhere');

-- 120 plain courses that state the Melbourne City Campus and on-campus delivery, plus 10 special cases (S1 to S10)
create function fx.course(k text, lvl text, campus text, mode text, page boolean default true) returns void language plpgsql as $$
begin
  insert into catalogue.courses(id, provider_id, canonical_title, course_code, study_level_id) values (fx.id(k), fx.id('P1'), 'Course ' || k, k, fx.id(lvl));
  if page then
    insert into pipeline.evidence_artifacts(id, source_id, evidence_type, source_url, storage_path, captured_at)
    values (fx.id('page-' || k), fx.id('src-site'), 'course_page', 'https://fixture.edu.au/courses/' || lower(k), 'fixture/' || k || '.html.gz', '2026-10-21T00:00:00Z');
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, evidence_id) values (fx.id(k), fx.id('P1'), 'https://fixture.edu.au/courses/' || lower(k), 'bound', fx.id('page-' || k));
    insert into pipeline.uni_adapter_results(provider_id, course_id, fields, at)
    values (fx.id('P1'), fx.id(k), jsonb_build_object('extra', jsonb_strip_nulls(jsonb_build_object('campus', campus, 'mode', mode)), 'fee', null), '2026-10-21T01:00:00Z');
  end if;
end $$;
select fx.course('K' || lpad(g::text, 3, '0'), case when g % 3 = 0 then 'PG' else 'UG' end, 'Melbourne City Campus', 'On campus') from generate_series(1, 120) g;
select fx.course('S1', 'UG', 'Sydney Campus', 'Face to face');
select fx.course('S2', 'UG', 'Online', 'Online');
select fx.course('S3', 'UG', 'Melbourne City Campus', 'On campus');
select fx.course('S4', 'UG', 'Melbourne City Campus', 'On campus');
select fx.course('S5', 'UG', null, null, false);
select fx.course('S6', 'UG', null, null);
select fx.course('S7', 'UG', 'Melbourne City Campus', 'On campus');
select fx.course('S8', 'UG', 'Melbourne City Campus', 'On campus');
select fx.course('S9', 'UG', 'Melbourne City Campus', 'On campus');
select fx.course('S10', 'PG', 'Melbourne City Campus', 'Blended Learning Online');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', fx.id('S3'), 'delivery_mode', 'value');
insert into pipeline.uni_adapter_delivery_exclusions values (fx.id('S4'), fx.id('P1'), true, 'fixture: delivery differs by intake');
insert into catalogue.course_campuses values (fx.id('S7'), fx.id('C1'), 'on_campus', true, fx.id('src-site'), null);
update catalogue.courses set delivery_mode = 'on_campus' where id = fx.id('S7');
update catalogue.courses set delivery_mode = 'online' where id = fx.id('S8');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status) values ('course', fx.id('S9'), 'official_course_url', 'pending');

\echo seed: 130 courses, 9 campuses

-- 1. D-B3 deterministic preview: the same inputs give the same rows, order, counts and fingerprint; previewing writes nothing
begin;
select fx.as_user('curator');
do $$ declare a jsonb; b jsonb; n1 bigint; n2 bigint; begin
  select count(*) + (select count(*) from pipeline.layer4_review_items) + (select count(*) from pipeline.layer4_bulk_operations) into n1 from pipeline.admin_control_events;
  a := fx.prev('campus', jsonb_build_object('campus_id', fx.id('C1')));
  b := fx.prev('campus', jsonb_build_object('campus_id', fx.id('C1')));
  perform fx.eq(a, b, 'campus preview twice');
  perform fx.eq(a->>'fingerprint', b->>'fingerprint', 'fingerprint twice');
  perform fx.eq(fx.prev('location', '{"mode":"on_campus"}'), fx.prev('location', '{"mode":"on_campus"}'), 'location preview twice');
  perform fx.eq(fx.prev('state', '{"state":"VIC"}'), fx.prev('state', '{"state":"VIC"}'), 'state preview twice');
  perform fx.eq(length(a->>'fingerprint'), 32, 'fingerprint is an md5');
  -- paging over the same plan reaches every row once, in the same order
  perform fx.eq((select jsonb_agg(r) from (select jsonb_array_elements(fx.prev('campus', jsonb_build_object('campus_id', fx.id('C1')), jsonb_build_object('limit', 50, 'offset', o))->'rows') r
                                           from generate_series(0, 100, 50) o) z), a->'rows', 'three pages equal the whole list');
  select count(*) + (select count(*) from pipeline.layer4_review_items) + (select count(*) from pipeline.layer4_bulk_operations) into n2 from pipeline.admin_control_events;
  perform fx.eq(n1, n2, 'preview writes nothing');
  perform fx.eq((a->>'can_apply')::boolean, false, 'a curator is told it cannot apply');
  perform fx.eq((a->>'enabled')::boolean, false, 'the switch reads off');
  a := fx.prev('campus', '{}');
  perform fx.eq((a->>'needs_value')::boolean, true, 'no value: choose first');
  perform fx.eq(jsonb_array_length(a->'campuses'), 7, 'the university''s active campuses to choose from');
  perform fx.eq(a->>'country', 'AU', 'the university''s country');
end $$;
rollback;
\echo PASS 1 deterministic preview, read only

-- 2. D-B3 exact eligible / excluded / protected counts, each row with its course-level evidence and applicability
begin;
select fx.as_user('curator');
do $$ declare a jsonb; begin
  a := fx.prev('campus', jsonb_build_object('campus_id', fx.id('C1')));
  perform fx.eq(a->'counts', '{"candidate":130,"eligible":122,"unchanged":1,"protected":2,"excluded_exception":2,"excluded_conflict":1,"excluded_unsupported":2,"courses_affected":122}'::jsonb, 'campus counts');
  perform fx.eq(fx.cls(a, 'Course S1'), 'excluded_exception', 'S1 names another campus');
  perform fx.eq(fx.cls(a, 'Course S2'), 'excluded_exception', 'S2 online only: no physical campus');
  perform fx.eq((select r->>'reason' from jsonb_array_elements(a->'rows') r where r->>'title' = 'Course S2'), 'the course page says online only', 'S2 reason');
  perform fx.eq(fx.cls(a, 'Course S5'), 'excluded_unsupported', 'S5 no page');
  perform fx.eq(fx.cls(a, 'Course S6'), 'excluded_unsupported', 'S6 page names no campus');
  perform fx.eq(fx.cls(a, 'Course S7'), 'unchanged', 'S7 already linked');
  perform fx.eq(fx.cls(a, 'Course S9'), 'excluded_conflict', 'S9 page waits for review');
  perform fx.eq((select r->'evidence'->>'page_url' from jsonb_array_elements(a->'rows') r where r->>'title' = 'Course K001'), 'https://fixture.edu.au/courses/k001', 'K001 evidence page');
  perform fx.eq((select r->'evidence'->>'stated_campus' from jsonb_array_elements(a->'rows') r where r->>'title' = 'Course K001'), 'Melbourne City Campus', 'K001 applicability: the page names the campus');
  perform fx.eq((select (r->'evidence'->>'evidence_id')::uuid from jsonb_array_elements(a->'rows') r where r->>'title' = 'Course K001'), fx.id('page-K001'), 'K001 stored copy');
  perform fx.eq((select r->>'class' from jsonb_array_elements(a->'rows') r limit 1), 'eligible', 'eligible rows first');
  a := fx.prev('location', '{"mode":"on_campus"}');
  perform fx.eq(a->'counts', '{"candidate":130,"eligible":121,"unchanged":1,"protected":2,"excluded_exception":2,"excluded_conflict":2,"excluded_unsupported":2,"courses_affected":121}'::jsonb, 'location counts');
  perform fx.eq(fx.cls(a, 'Course S1'), 'eligible', 'S1 face to face');
  perform fx.eq(fx.cls(a, 'Course S8'), 'excluded_conflict', 'S8 holds online');
  perform fx.eq(fx.cls(a, 'Course S10'), 'excluded_exception', 'S10 blended online is not clear');
  a := fx.prev('location', '{"mode":"online"}');
  perform fx.eq(fx.cls(a, 'Course S2'), 'eligible', 'S2 online');
  perform fx.eq((a->'counts'->>'eligible')::int, 1, 'only S2 is online');
  a := fx.prev('state', '{"state":"VIC"}');
  perform fx.eq(a->'counts', '{"candidate":7,"eligible":1,"unchanged":0,"protected":1,"excluded_exception":2,"excluded_conflict":1,"excluded_unsupported":2,"courses_affected":1}'::jsonb, 'state counts (C1 links S7)');
  perform fx.eq(fx.cls(a, 'Melbourne City Campus'), 'eligible', 'C1 3000 is VIC');
  perform fx.eq(fx.cls(a, 'Sydney Campus'), 'excluded_conflict', 'C2 holds NSW');
  perform fx.eq(fx.cls(a, 'Brisbane Campus'), 'excluded_unsupported', 'C3 no official record');
  perform fx.eq(fx.cls(a, 'Geelong Campus'), 'protected', 'C4 locked');
  perform fx.eq(fx.cls(a, 'Ballarat Campus'), 'excluded_exception', 'C6 cleared on purpose');
  perform fx.eq(fx.cls(a, 'Hobart Campus'), 'excluded_exception', 'C7 postcode is TAS');
  perform fx.eq(fx.cls(a, 'Perth Campus'), 'excluded_unsupported', 'C8 no postcode: city alone is not used');
  a := fx.prev('state', '{"state":"NSW"}');
  perform fx.eq(fx.cls(a, 'Sydney Campus'), 'unchanged', 'C2 already NSW');
  a := fx.prev('country', '{"country":"AU"}');
  perform fx.eq((a->'counts'->>'unchanged')::int, 7, 'every campus already AU');
  a := fx.prev('country', '{"country":"NZ"}');
  perform fx.eq(fx.cls(a, 'Sydney Campus'), 'excluded_conflict', 'C2 state belongs to AU');
  perform fx.eq(fx.cls(a, 'Brisbane Campus'), 'excluded_unsupported', 'C3 no record');
  perform fx.eq((a->'counts'->>'eligible')::int, 5, 'NZ eligible campuses');
end $$;
rollback;
\echo PASS 2 exact counts with course-level evidence

-- 3. D-B1: only country, state, campus and location; AER, intake and English are refused; an unclear campus name is refused
begin;
select fx.as_user('admin');
select fx.raises($q$select fx.prev('english', '{}')$q$, 'country, state, campus and location only', 'english refused');
select fx.raises($q$select fx.prev('entry_requirements', '{}')$q$, 'academic entry requirements are never bulk-approved', 'AER refused');
select fx.raises($q$select fx.prev('intake', '{}')$q$, 'intake and English follow later', 'intake refused');
select fx.raises($q$select fx.l4('bulk_preview', jsonb_build_object('provider_id', fx.id('P2'), 'field', 'campus', 'value', jsonb_build_object('campus_id', fx.id('Q1'))))$q$,
                 'cannot be told apart', 'Sydney vs Sydney Manly Beach');
select fx.raises($q$select fx.prev('campus', jsonb_build_object('campus_id', fx.id('Q1')))$q$, 'active campuses', 'another university''s campus');
rollback;
\echo PASS 3 eligible-field policy

-- 4. D-B2 and D-B3: a non-admin cannot apply or reverse; disabled refuses and changes nothing
begin;
select fx.as_user('operator');
do $$ declare fp text := fx.prev('location', '{"mode":"on_campus"}')->>'fingerprint'; begin
  perform fx.set('layer4.bulk_review_enabled', 1);
  perform fx.raises(format($q$select fx.apply('location', '{"mode":"on_campus"}', %L)$q$, fp), 'Platform Admin role required', 'operator apply');
  perform fx.raises($q$select fx.l4('bulk_reverse', '{"operation_key":"x","reason":"undo it please"}')$q$, 'Platform Admin role required', 'operator reverse');
end $$;
select fx.as_user('admin');
do $$ declare fp text := fx.prev('location', '{"mode":"on_campus"}')->>'fingerprint'; begin
  perform fx.set('layer4.bulk_review_enabled', 0);
  perform fx.raises(format($q$select fx.apply('location', '{"mode":"on_campus"}', %L)$q$, fp), 'bulk apply is switched off', 'disabled refuses');
  perform fx.eq((select count(*) from pipeline.layer4_bulk_operations), 0::bigint, 'no operation');
  perform fx.eq((select count(*) from catalogue.courses where delivery_mode is not null), 2::bigint, 'nothing written (only the seeded S7 and S8 values)');
end $$;
rollback;
\echo PASS 4 role boundary and switch

-- 5. D-B3 conflict detection: a stale fingerprint refuses the whole apply; a row changed between batches is reported conflicted
begin;
select fx.as_user('admin');
do $$ declare fp text; r jsonb; v_late uuid; begin
  perform fx.set('layer4.bulk_review_enabled', 1);
  fp := fx.prev('location', '{"mode":"on_campus"}')->>'fingerprint';
  update catalogue.courses set delivery_mode = 'blended' where id = fx.id('K007');   -- another reviewer, after the preview
  perform fx.raises(format($q$select fx.apply('location', '{"mode":"on_campus"}', %L)$q$, fp), 'plan has changed since the preview', 'stale value');
  fp := fx.prev('location', '{"mode":"on_campus"}')->>'fingerprint';
  insert into pipeline.uni_adapter_results(provider_id, course_id, fields, at) values (fx.id('P1'), fx.id('K008'), '{"extra":{"campus":"Melbourne City Campus","mode":"On campus"}}', '2026-10-22T00:00:00Z');
  perform fx.raises(format($q$select fx.apply('location', '{"mode":"on_campus"}', %L)$q$, fp), 'plan has changed since the preview', 'stale evidence (page read again)');
  fp := fx.prev('location', '{"mode":"on_campus"}')->>'fingerprint';
  perform fx.raises($q$select fx.apply('location', '{"mode":"on_campus"}', 'deadbeefdeadbeefdeadbeefdeadbeef')$q$, 'plan has changed', 'made-up fingerprint');
  r := fx.apply('location', '{"mode":"on_campus"}', fp);                     -- first batch of 50
  perform fx.eq(r->>'state', 'partial', 'first batch partial');
  select i.entity_id into v_late from pipeline.layer4_bulk_operation_items i where i.selected and i.outcome is null order by i.entity_id desc limit 1;
  update catalogue.courses set delivery_mode = 'online' where id = v_late;     -- another reviewer, before its batch
  perform fx.set('layer4.bulk_batch_size', 200);
  r := fx.apply('location', '{"mode":"on_campus"}', fp);
  perform fx.eq((select x->>'outcome' from jsonb_array_elements(r->'this_call') x where (x->>'entity_id')::uuid = v_late), 'conflicted', 'late change conflicted');
  perform fx.eq((select delivery_mode from catalogue.courses where id = v_late), 'online', 'left as the other reviewer set it');
  perform fx.eq(r->'totals'->>'conflicted', '1', 'one conflict');
  perform fx.eq(r->>'state', 'done', 'done with the conflict reported');
end $$;
rollback;
\echo PASS 5 stale fingerprint and per-row conflict

-- 6. D-B3 idempotent bounded application, per-course audit through the existing decision path, 100+ eligible courses
begin;
select fx.as_user('admin');
do $$ declare fp text; r jsonb; k text; n int; begin
  perform fx.set('layer4.bulk_review_enabled', 1);
  fp := fx.prev('campus', jsonb_build_object('campus_id', fx.id('C1')))->>'fingerprint';
  r := fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), fp);
  k := r->>'operation_key';
  perform fx.eq(jsonb_array_length(r->'this_call'), 50, 'batch of 50 (setting layer4.bulk_batch_size)');
  perform fx.eq(r->'totals', '{"applied":50,"unchanged":1,"excluded":7,"conflicted":0,"failed":0,"remaining":72}'::jsonb, 'first batch totals');
  r := fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), fp);
  perform fx.eq(r->>'operation_key', k, 'same key');
  r := fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), fp);
  perform fx.eq(r->>'state', 'done', 'done after three batches');
  perform fx.eq(r->'totals', '{"applied":122,"unchanged":1,"excluded":7,"conflicted":0,"failed":0,"remaining":0}'::jsonb, 'final totals');
  -- the same key again writes nothing
  r := fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), fp);
  perform fx.eq(jsonb_array_length(r->'this_call'), 0, 'retry writes nothing');
  perform fx.eq((select count(*) from catalogue.course_campuses where campus_id = fx.id('C1'))::int, 123, 'one link per course (122 new + S7)');
  perform fx.eq((select count(*) from (select course_id from catalogue.course_campuses where campus_id = fx.id('C1') group by 1 having count(*) > 1) z)::int, 0, 'no duplicates');
  -- per course: one review item, decided once through layer4_review_decide_impl, one decision, one search signal, one audit event
  perform fx.eq((select count(*) from pipeline.layer4_review_items where change_control_ref = 'UR-18 bulk ' || k and status = 'approved' and field_code = 'bulk_course_campus')::int, 122, 'review items approved');
  perform fx.eq((select count(*) from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id where i.change_control_ref = 'UR-18 bulk ' || k and d.action = 'approve' and d.actor_id = fx.id('admin'))::int, 122, 'decisions');
  perform fx.eq((select count(*) from pipeline.search_refresh_signals where change_control_ref = 'UR-18 bulk ' || k)::int, 122, 'search signals');
  perform fx.eq((select count(*) from pipeline.admin_control_events where action = 'bulk_item_applied' and detail->>'operation_key' = k)::int, 122, 'one audit event per course');
  perform fx.eq((select count(*) from pipeline.admin_control_events where action in ('bulk_operation_start', 'bulk_apply') and detail->>'operation_key' = k)::int, 5, 'start event and one event per call');
  perform fx.eq((select count(distinct c) from search.refresh_calls, unnest(course_ids) c)::int, 122, 'search refreshed for the applied courses');
  -- protected courses never written
  perform fx.eq((select count(*) from catalogue.course_campuses where course_id in (fx.id('S3'), fx.id('S4')))::int, 0, 'locked and excluded courses untouched');
  perform fx.eq((select count(*) from pipeline.layer4_bulk_operation_items i join pipeline.layer4_bulk_operations o on o.id = i.operation_id where o.operation_key = k)::int, 130, 'every candidate recorded with its class');
  perform fx.eq((select (evidence_id, review_item_id is not null, decision_id is not null, outcome) from pipeline.layer4_bulk_operation_items where entity_id = fx.id('K001')),
                (fx.id('page-K001'), true, true, 'applied'::text), 'K001 item lineage');
  perform fx.eq((select evidence_id from catalogue.course_campuses where course_id = fx.id('K001') and campus_id = fx.id('C1')), fx.id('page-K001'), 'link carries the course page evidence');
end $$;
rollback;
\echo PASS 6 idempotent, bounded, audited per course

-- 7. D-B3 partial failure and retry with the same key; destination read back (a guard that skips silently is a failure)
begin;
select fx.as_user('admin');
create function fx.boom() returns trigger language plpgsql as $$ begin raise exception 'fixture: database error on this course'; end $$;
create trigger fx_boom before update on catalogue.courses for each row when (new.id = md5('K005')::uuid) execute function fx.boom();
create function fx.skip() returns trigger language plpgsql as $$ begin new.delivery_mode := old.delivery_mode; return new; end $$;
create trigger fx_skip before update on catalogue.courses for each row when (new.id = md5('K010')::uuid) execute function fx.skip();
do $$ declare fp text; r jsonb; k text; begin
  perform fx.set('layer4.bulk_review_enabled', 1);
  perform fx.set('layer4.bulk_batch_size', 200);
  fp := fx.prev('location', '{"mode":"on_campus"}')->>'fingerprint';
  r := fx.apply('location', '{"mode":"on_campus"}', fp);
  k := r->>'operation_key';
  perform fx.eq(r->>'state', 'partial', 'partial, never done');
  perform fx.eq(r->'totals', '{"applied":119,"unchanged":1,"excluded":8,"conflicted":0,"failed":2,"remaining":0}'::jsonb, 'first run totals');
  perform fx.eq((select outcome_reason from pipeline.layer4_bulk_operation_items where entity_id = fx.id('K005')), 'fixture: database error on this course', 'K005 failed with the error');
  perform fx.eq((select outcome_reason like 'the destination does not show the value after the write%' from pipeline.layer4_bulk_operation_items where entity_id = fx.id('K010')), true, 'K010 read back failed');
  perform fx.eq((select delivery_mode from catalogue.courses where id = fx.id('K010')), null::text, 'K010 not written');
  perform fx.eq((select count(*) from pipeline.layer4_review_items where entity_id in (fx.id('K005'), fx.id('K010')))::int, 0, 'failed rows leave no review item or decision');
  perform fx.eq((select count(*) from pipeline.admin_control_events where action = 'bulk_item_failed' and detail->>'operation_key' = k)::int, 2, 'failures audited');
  drop trigger fx_boom on catalogue.courses; drop trigger fx_skip on catalogue.courses;
  r := fx.apply('location', '{"mode":"on_campus"}', fp);
  perform fx.eq(r->>'state', 'done', 'retry finishes');
  perform fx.eq(jsonb_array_length(r->'this_call'), 2, 'retry writes only the two that failed');
  perform fx.eq(r->'totals', '{"applied":121,"unchanged":1,"excluded":8,"conflicted":0,"failed":0,"remaining":0}'::jsonb, 'retry totals');
  perform fx.eq((select count(*) from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id where i.change_control_ref = 'UR-18 bulk ' || k)::int, 121, 'no duplicate decisions');
  perform fx.eq((select attempts from pipeline.layer4_bulk_operation_items where entity_id = fx.id('K005')), 2, 'K005 tried twice');
  perform fx.eq((select count(*) from catalogue.courses where delivery_mode = 'on_campus')::int, 122, '121 written plus S7');
end $$;
rollback;
\echo PASS 7 partial failure, retry, read-back

-- 8. D-B3 reversible remediation: each applied row is restored through the same path; a row changed since is left and reported
begin;
select fx.as_user('admin');
do $$ declare fp text; r jsonb; k text; begin
  perform fx.set('layer4.bulk_review_enabled', 1);
  perform fx.set('layer4.bulk_batch_size', 200);
  fp := fx.prev('location', '{"mode":"on_campus"}')->>'fingerprint';
  k := fx.apply('location', '{"mode":"on_campus"}', fp)->>'operation_key';
  update catalogue.courses set delivery_mode = 'blended' where id = fx.id('K003');   -- changed after the apply
  perform fx.raises(format($q$select fx.l4('bulk_reverse', jsonb_build_object('operation_key', %L, 'reason', 'x'))$q$, k), 'give a reason', 'reason needed');
  r := fx.l4('bulk_reverse', jsonb_build_object('operation_key', k, 'reason', 'Fixture: wrong delivery for this university'));
  perform fx.eq(r->'reversal', '{"reversed":120,"conflicted":1}'::jsonb, 'reversal counts');
  perform fx.eq(r->>'state', 'reversed', 'reversed');
  perform fx.eq((select count(*) from catalogue.courses where delivery_mode = 'on_campus')::int, 1, 'only S7 (held before) remains on_campus');
  perform fx.eq((select delivery_mode from catalogue.courses where id = fx.id('K003')), 'blended', 'K003 left as changed');
  perform fx.eq((select count(*) from pipeline.layer4_review_items where change_control_ref = 'UR-18 bulk ' || k and layer2_state->>'source' = 'UR-18 bulk review reversal' and status = 'approved')::int, 120, 'reversal decided per course');
  perform fx.eq((select count(*) from pipeline.admin_control_events where action like 'bulk_reverse_%' and detail->>'operation_key' = k)::int, 121, 'reversal audited per course');
  perform fx.raises(format($q$select fx.apply('location', '{"mode":"on_campus"}', %L)$q$, fp), 'this operation was reversed', 'a reversed operation is not re-applied by key');
  -- state and campus link reversal
  fp := fx.prev('state', '{"state":"VIC"}')->>'fingerprint';
  k := fx.apply('state', '{"state":"VIC"}', fp)->>'operation_key';
  perform fx.eq((select subdivision_id from catalogue.campuses where id = fx.id('C1')), fx.id('AU-VIC'), 'C1 VIC');
  perform fx.eq((select subdivision_id from catalogue.campuses where id = fx.id('C4')), null::uuid, 'C4 locked: untouched');
  perform fx.l4('bulk_reverse', jsonb_build_object('operation_key', k, 'reason', 'Fixture: undo the state'));
  perform fx.eq((select subdivision_id from catalogue.campuses where id = fx.id('C1')), null::uuid, 'C1 restored');
  fp := fx.prev('campus', jsonb_build_object('campus_id', fx.id('C1')))->>'fingerprint';
  k := fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), fp, jsonb_build_object('course_ids', jsonb_build_array(fx.id('K001'), fx.id('K002'))))->>'operation_key';
  perform fx.eq((select count(*) from catalogue.course_campuses where campus_id = fx.id('C1'))::int, 3, 'two ticked links plus S7');
  perform fx.l4('bulk_reverse', jsonb_build_object('operation_key', k, 'reason', 'Fixture: undo the links'));
  perform fx.eq((select array_agg(course_id) from catalogue.course_campuses where campus_id = fx.id('C1')), array[fx.id('S7')], 'only the link held before remains');
end $$;
rollback;
\echo PASS 8 reversal

-- 9. bounded by settings: at most layer4.bulk_max_courses rows; only eligible rows can be ticked; one operation per university and field at a time
begin;
select fx.as_user('admin');
do $$ declare fp text; begin
  perform fx.set('layer4.bulk_review_enabled', 1);
  perform fx.set('layer4.bulk_max_courses', 100);
  fp := fx.prev('campus', jsonb_build_object('campus_id', fx.id('C1')))->>'fingerprint';
  perform fx.raises(format($q$select fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), %L)$q$, fp), 'more than 100 rows', 'max rows');
  perform fx.raises(format($q$select fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), %L, jsonb_build_object('course_ids', jsonb_build_array(fx.id('S3'))))$q$, fp),
                    'only eligible rows', 'protected row cannot be ticked');
  perform fx.set('layer4.bulk_batch_size', 1);
  perform fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), fp, jsonb_build_object('course_ids', jsonb_build_array(fx.id('K001'), fx.id('K002'))));
  perform fx.raises(format($q$select fx.apply('campus', jsonb_build_object('campus_id', fx.id('C1')), %L, jsonb_build_object('course_ids', jsonb_build_array(fx.id('K003'))))$q$, fp),
                    'another bulk operation for this university and field is not finished', 'one controller');
end $$;
rollback;
\echo PASS 9 bounds and one controller

-- 10. the new field codes are written only inside a Platform Admin bulk apply, never by a plain Layer 4 decision
begin;
select fx.as_user('admin');
do $$ declare v uuid; begin
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, before_value, proposed_value) values ('course', fx.id('K001'), 'bulk_course_location', '{"mode":null}', '{"mode":"online"}') returning id into v;
  perform fx.raises(format($q$select security.layer4_review_decide_impl(%L, 'approve', 'try it directly', null)$q$, v), 'written only inside a bulk apply or reversal', 'direct decide refused');
  perform fx.as_user('curator');
  perform fx.raises(format($q$select security.layer4_review_decide_impl(%L, 'approve', 'try it directly', null)$q$, v), 'Platform Admin role required', 'curator refused');
  perform fx.eq((select delivery_mode from catalogue.courses where id = fx.id('K001')), null::text, 'nothing written');
end $$;
rollback;
\echo PASS 10 apply path closed outside bulk

-- 11. a passing run switches nothing on
select fx.eq((select value from pipeline.platform_toolset_settings where key = 'layer4.bulk_review_enabled'), '0'::jsonb, 'switch still 0');
select fx.eq((select (min_value, max_value, unit, section) from pipeline.platform_toolset_settings where key = 'layer4.bulk_review_enabled'), (0::numeric, 1::numeric, 'on/off'::text, 'Layer 4'::text), 'switch range');
select fx.eq((select count(*) from pipeline.layer4_bulk_operations)::int, 0, 'no operation kept');
\echo PASS 11 switch stays off
\echo ALL CASES PASSED
