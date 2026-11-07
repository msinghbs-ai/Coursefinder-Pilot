-- Guards: "No unauthorised Layer 4 admission" (Platform Admin P0 mandate 3 Nov 2026 10:44 section 7) and the held_first_admission promise (a provider's
-- first descriptions "wait in Layer 4; admitted once they are approved"): migration 20261107120000 lets a held reading take a place a decision frees,
-- as a pending item for a person, and nothing more.
-- Runs on the production-parity fixture (../course-description-parity/manifest.json) AFTER 20261106500000 and 20261107120000. Every row is invented.
\set ON_ERROR_STOP 1
set search_path to "$user", public, extensions;
alter table pipeline.field_enrich_items disable trigger field_enrich_items_gate;
alter table pipeline.field_enrich_items disable trigger ai_spend_capture;
alter table pipeline.field_enrich_items disable trigger field_enrich_items_absence;
alter table pipeline.field_enrich_items disable trigger field_enrich_items_flag;
alter table pipeline.layer4_review_items disable trigger layer4_review_items_zz_arrival;
alter table pipeline.layer4_review_items disable trigger layer4_review_items_zz_evidence;
alter table pipeline.layer4_review_items disable trigger layer4_review_items_reroute;
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host_zz_cricos;

-- stand-in for the table the existing trigger writes to (the fixture does not carry it): columns as the trigger uses them
create table if not exists search.refresh_requests(id bigserial primary key, requested_by text, requested_at timestamptz default now(), processed_at timestamptz);

-- stand-ins for the two tables security.coverage_identity_allowed reads (the fixture does not carry them): the AU proof course_title_on_page admits description
create table if not exists pipeline.uni_adapters(provider_id uuid, enabled boolean, admit boolean, admit_fields text[]);
create table if not exists pipeline.coverage_admission_countries(country_id uuid, active boolean, identities jsonb);
insert into pipeline.coverage_admission_countries select id, true, '{"description": ["course_title_on_page"]}'::jsonb from ref.countries where iso_alpha2 = 'AU';

create temporary table g_t(label text primary key, ok boolean);
create function pg_temp.expect(p_label text, p_ok boolean) returns void language plpgsql as $$
begin
  insert into g_t values (p_label, coalesce(p_ok, false));
  raise notice '% [%]', p_label, case when coalesce(p_ok, false) then 'pass' else 'FAIL' end;
end $$;
create function pg_temp.cid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-b100-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.eid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-b200-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.rid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-b300-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.pend(p uuid) returns int language sql as $$
  select count(*)::int from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
   where q.field_code = 'course_description_first_read' and q.status = 'pending' and c.provider_id = p $$;
create function pg_temp.st(n int) returns text language sql as $$ select state from pipeline.field_enrich_items where course_id = pg_temp.cid(n) and field = 'description' order by id desc limit 1 $$;
create function pg_temp.w(n int, k int) returns text language sql as $$ select translate(substr(md5(n::text || '-' || k), 1, 9), '0123456789', 'ghijklmnop') $$;
create function pg_temp.good(n int) returns jsonb language sql as $$
  select jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(
    jsonb_build_object('text', 'Promote Course ' || n || ' covers ' || pg_temp.w(n, 1) || ', ' || pg_temp.w(n, 2) || ', ' || pg_temp.w(n, 3) || ', ' || pg_temp.w(n, 4) || ', ' || pg_temp.w(n, 5) || ' and ' || pg_temp.w(n, 6) || ' across the degree.',
                       'quote', 'Promote Course ' || n || ' covers ' || pg_temp.w(n, 1) || ', ' || pg_temp.w(n, 2) || ', ' || pg_temp.w(n, 3) || ', ' || pg_temp.w(n, 4) || ', ' || pg_temp.w(n, 5) || ' and ' || pg_temp.w(n, 6) || ' across the degree.', 'on_page', true),
    jsonb_build_object('text', 'You complete a capstone project in the final year with guidance from teaching staff in your area of study.',
                       'quote', 'You complete a capstone project in the final year with guidance from teaching staff in your area of study.', 'on_page', true))) $$;

-- providers: P1 and P2 (AU), fixed cap of 2 waiting items per provider, every description waits for a person (the live setting)
update pipeline.platform_toolset_settings set value = '2'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_max';
update pipeline.platform_toolset_settings set value = '100000'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_review_first';
insert into pim.entity_registry(id, stable_key) values ('00000000-0000-4000-b000-000000000001', 'g-ph-p1'), ('00000000-0000-4000-b000-000000000002', 'g-ph-p2');
insert into catalogue.providers(id, stable_key, canonical_name, country_id) values
  ('00000000-0000-4000-b000-000000000001', 'g-ph-p1', 'Promote University One', (select id from ref.countries where iso_alpha2 = 'AU')),
  ('00000000-0000-4000-b000-000000000002', 'g-ph-p2', 'Promote University Two', (select id from ref.countries where iso_alpha2 = 'AU'));
insert into pipeline.admin_jobs(id) values ('00000000-0000-4000-b000-0000000000f1');
-- P1: courses 1-2 wait in Layer 4, 3-5 held (good), 6 held but locked, 7 held but its page changed, 8 held and now fails a check, 9 held and already has a description
-- P2: course 11 waits, 12-13 held (a second provider must not be touched by P1 decisions)
insert into pim.entity_registry(id, stable_key) select pg_temp.cid(n), 'g-ph-c' || n from (select generate_series(1, 9) n union all select generate_series(11, 13)) x;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title)
select pg_temp.cid(n), 'g-ph-c' || n, case when n < 10 then '00000000-0000-4000-b000-000000000001'::uuid else '00000000-0000-4000-b000-000000000002'::uuid end, 'Promote Course ' || n
  from (select generate_series(1, 9) n union all select generate_series(11, 13)) x;
update catalogue.courses set description = 'An older adapter description of this course that already stands on the site and is not from this reader.' where id = pg_temp.cid(9);
insert into pipeline.evidence_artifacts(id, evidence_type) select pg_temp.eid(n), 'page' from generate_series(1, 80) n;
insert into pipeline.coverage_course_pages(course_id, provider_id, status, identity_basis, url, evidence_id)
select c.id, c.provider_id, 'bound', 'course_title_on_page', 'https://example.test/course/' || right(c.stable_key, 2),
       pg_temp.eid(case when c.id = pg_temp.cid(7) then 70 else regexp_replace(c.stable_key, '\D', '', 'g')::int end)
  from catalogue.courses c where c.stable_key like 'g-ph-c%';
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(6), 'description', 'value');

-- waiting items (reading in review, proposal pending), as enrich_course_text_record_v1 writes them
create function pg_temp.waiting(n int) returns void language plpgsql as $$
declare v_item bigint; v_text text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(pg_temp.good(n)->'sentences') with ordinality e(x, o));
begin
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, evidence_id)
  select '00000000-0000-4000-b000-0000000000f1', c.provider_id, c.id, 'description', 'review', 'ai_stored', pg_temp.good(n) || jsonb_build_object('text', v_text), pg_temp.eid(n)
    from catalogue.courses c where c.id = pg_temp.cid(n) returning id into v_item;
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  values (pg_temp.rid(n), 'course', pg_temp.cid(n), 'course_description_first_read', pg_temp.eid(n), jsonb_build_object('description', null),
          jsonb_build_object('description', v_text, 'item_id', v_item), 'pending', 'fixture', 'CF-CHG-20260915-247');
end $$;
-- held readings: the text is stored with the reading, as the record function does
create function pg_temp.held(n int, reading jsonb) returns void language sql as $$
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, evidence_id, reason)
  select '00000000-0000-4000-b000-0000000000f1', c.provider_id, c.id, 'description', 'skipped', 'ai_stored',
         reading || jsonb_build_object('text', (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(reading->'sentences') with ordinality e(x, o))),
         pg_temp.eid(n), 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved'
    from catalogue.courses c where c.id = pg_temp.cid(n) $$;
select pg_temp.waiting(n) from unnest(array[1, 2, 11]) n;
select pg_temp.held(n, pg_temp.good(n)) from unnest(array[3, 4, 5, 6, 7, 9, 12, 13]) n;
select pg_temp.held(8, jsonb_build_object('about_course', true, 'sentences', (select jsonb_agg(pg_temp.good(8)->'sentences'->0) from generate_series(1, 5))));
-- 8's reading breaks the sentence range now (five sentences)

-- 0. nothing happens by itself: the held readings stay held until a person decides something
select pg_temp.expect('start: P1 has 2 waiting and 7 held', pg_temp.pend('00000000-0000-4000-b000-000000000001') = 2
  and (select count(*) from pipeline.field_enrich_items where provider_id = '00000000-0000-4000-b000-000000000001' and reason like 'held_first_admission:%') = 7);

-- 1. a person approves course 1: one place frees, the lowest-id held reading that passes everything (course 3) takes it; 6 (locked), 7 (page changed),
--    8 (fails a check) and 9 (has a description) never do; the other provider is untouched
update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = pg_temp.rid(1);
select pg_temp.expect('approve 1: course 1 item settled', pg_temp.st(1) = 'filled');
select pg_temp.expect('approve 1: held course 3 now waits for a person', pg_temp.st(3) = 'review'
  and exists (select 1 from pipeline.layer4_review_items where entity_id = pg_temp.cid(3) and status = 'pending' and field_code = 'course_description_first_read'));
select pg_temp.expect('approve 1: the cap holds (2 waiting)', pg_temp.pend('00000000-0000-4000-b000-000000000001') = 2);
select pg_temp.expect('approve 1: course 4 and 5 still held', pg_temp.st(4) = 'skipped' and pg_temp.st(5) = 'skipped');
select pg_temp.expect('approve 1: the promoted proposal carries the stored page, text and quotes', (select proposed_value->>'description' = (select value->>'text' from pipeline.field_enrich_items where course_id = pg_temp.cid(3))
    and jsonb_array_length(proposed_value->'sentences') = 2 and evidence_id = pg_temp.eid(3) from pipeline.layer4_review_items where entity_id = pg_temp.cid(3) and status = 'pending'));
select pg_temp.expect('approve 1: the other provider is untouched', pg_temp.pend('00000000-0000-4000-b000-000000000002') = 1 and pg_temp.st(12) = 'skipped' and pg_temp.st(13) = 'skipped');

-- 2. a rejection frees a place too
update pipeline.layer4_review_items set status = 'rejected', decided_at = now() where id = pg_temp.rid(2);
select pg_temp.expect('reject 2: item settled as not admitted', pg_temp.st(2) = 'skipped' and (select reason from pipeline.field_enrich_items where course_id = pg_temp.cid(2) and field = 'description') like 'not admitted in Layer 4%');
select pg_temp.expect('reject 2: course 4 takes the place', pg_temp.st(4) = 'review' and pg_temp.pend('00000000-0000-4000-b000-000000000001') = 2);

-- 3. the ones that can never be promoted stay where they are, however many places free
update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id in (select id from pipeline.layer4_review_items where entity_id in (pg_temp.cid(3), pg_temp.cid(4)));
select pg_temp.expect('approve 3 and 4: course 5 is promoted', pg_temp.st(5) = 'review');
select pg_temp.expect('locked (6), page-changed (7), failing (8) and already-described (9) stay held, still with their reading',
  pg_temp.st(6) = 'skipped' and pg_temp.st(7) = 'skipped' and pg_temp.st(8) = 'skipped' and pg_temp.st(9) = 'skipped'
  and (select count(*) from pipeline.field_enrich_items where course_id in (pg_temp.cid(6), pg_temp.cid(7), pg_temp.cid(8), pg_temp.cid(9)) and reason like 'held_first_admission:%') = 4
  and (select reason from pipeline.field_enrich_items where course_id = pg_temp.cid(8)) like 'held_first_admission:%');

-- 4. nothing is admitted without a person: no description is written by promotion, and every place taken is a pending item
select pg_temp.expect('no description was written by the promotion', (select count(*) from catalogue.courses where provider_id = '00000000-0000-4000-b000-000000000001' and nullif(btrim(description), '') is not null) = 1
  and (select description from catalogue.courses where id = pg_temp.cid(5)) is null);
select pg_temp.expect('nothing was decided by the promotion', (select count(*) from pipeline.layer4_review_items where status = 'pending' and decided_at is not null) = 0);

-- 5. the switch: off, a decision frees a place and nothing is promoted
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_promote_held_on';
update pipeline.layer4_review_items set status = 'approved', decided_at = now() where entity_id = pg_temp.cid(5);
update pipeline.layer4_review_items set status = 'approved', decided_at = now() where entity_id = pg_temp.cid(11);
select pg_temp.expect('switch off: P2 held readings stay held after a decision', pg_temp.st(12) = 'skipped' and pg_temp.st(13) = 'skipped' and pg_temp.pend('00000000-0000-4000-b000-000000000002') = 0);
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_promote_held_on';
-- 6. a trusted provider's readings are the release function's, not queued: make P2 trusted and decide again
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_review_first';
select pg_temp.expect('trusted provider: promotion is a no-op', security.course_description_promote_held_v1('00000000-0000-4000-b000-000000000002') = 0);
select pg_temp.expect('the function can be called by nobody but the owner', not has_function_privilege('authenticated', 'security.course_description_promote_held_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'security.course_description_promote_held_v1(uuid)', 'execute'));

do $$ declare v_bad int; begin
  select count(*) into v_bad from g_t where not ok;
  if v_bad > 0 then raise exception '% promote-held check(s) failed', v_bad; end if;
  raise notice 'promote-held: all % checks passed', (select count(*) from g_t);
end $$;
