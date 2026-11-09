-- Guards: F-CDESC (Platform Admin decision 10 Nov 2026): the machine rule cdesc-machine-v1 admits a first course description only inside the safe class and writes everything down; every other case stays waiting for a person with
-- the exact reason; the switch off leaves Layer 4 as it was; nothing is admitted twice; a withdrawal restores the empty description; a transient decline is looked at again. Every row is invented.
-- Runs on the production-parity fixture AFTER the base harness and both migrations (run.sh). The fixture of the base harness is cleared first.
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

-- clear the base harness's own rows (scratch database)
truncate pipeline.layer4_review_items, pipeline.field_enrich_items, pipeline.coverage_course_pages, pipeline.manual_locks, pipeline.course_description_machine_admissions, pipeline.course_description_source_checks cascade;
delete from search.course_documents;
delete from catalogue.courses;
delete from catalogue.providers;
delete from pim.entity_registry;
delete from pipeline.evidence_artifacts;
delete from pipeline.admin_jobs;
delete from storage.objects;
delete from pipeline.cdm_hidden;
delete from pipeline.enrichment_flags;
create table if not exists search.refresh_requests(id bigserial primary key, requested_by text, requested_at timestamptz default now(), processed_at timestamptz);

create temporary table g_t(label text primary key, ok boolean);
create function pg_temp.expect(p_label text, p_ok boolean) returns void language plpgsql as $$
begin
  insert into g_t values (p_label, coalesce(p_ok, false));
  raise notice '% [%]', p_label, case when coalesce(p_ok, false) then 'pass' else 'FAIL' end;
end $$;
create function pg_temp.diag(p_label text, p_sql text) returns void language plpgsql as $$ declare r text; begin for r in execute p_sql loop raise notice 'diag % : %', p_label, r; end loop; end $$;
create function pg_temp.cid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-c100-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.eid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-c200-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.rid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-c300-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.pid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-c000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.w(n int, k int) returns text language sql as $$ select translate(substr(md5(n::text || '-' || k), 1, 9), '0123456789', 'ghijklmnop') $$;
create function pg_temp.sents(n int) returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('text', 'The ' || pg_temp.w(n, 1) || ' programme covers ' || pg_temp.w(n, 2) || ', ' || pg_temp.w(n, 3) || ', ' || pg_temp.w(n, 4) || ' and ' || pg_temp.w(n, 5) || ' across the whole degree.',
                       'quote', 'The ' || pg_temp.w(n, 1) || ' programme covers ' || pg_temp.w(n, 2) || ', ' || pg_temp.w(n, 3) || ', ' || pg_temp.w(n, 4) || ' and ' || pg_temp.w(n, 5) || ' across the whole degree.', 'on_page', true),
    jsonb_build_object('text', 'Learners complete a ' || pg_temp.w(n, 6) || ' project in the final stage under academic guidance.',
                       'quote', 'Learners complete a ' || pg_temp.w(n, 6) || ' project in the final stage under academic guidance.', 'on_page', true)) $$;
create function pg_temp.txt(s jsonb) returns text language sql as $$ select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(s) with ordinality e(x, o) $$;
create function pg_temp.strip(s jsonb) returns jsonb language sql as $$ select jsonb_agg(jsonb_build_object('text', x->>'text', 'quote', x->>'quote') order by o) from jsonb_array_elements(s) with ordinality e(x, o) $$;

-- providers: 1 to 4 and 6 live (AU), 5 hidden
insert into pim.entity_registry(id, stable_key) select pg_temp.pid(n), 'cm-p' || n from generate_series(1, 7) n;
insert into catalogue.providers(id, stable_key, canonical_name, country_id)
select pg_temp.pid(n), 'cm-p' || n, 'Cm ' || (array['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf'])[n] || ' College', (select id from ref.countries where iso_alpha2 = 'AU') from generate_series(1, 7) n;
insert into pipeline.cdm_hidden values (pg_temp.pid(5));
insert into pipeline.admin_jobs(id) values ('00000000-0000-4000-c000-0000000000f1'), ('00000000-0000-4000-c000-0000000000f2');

-- one complete waiting case: course (published), stored page (object present, hash in the address), bound and read page, the reading in state review, the Layer 4 item pending
create function pg_temp.mk(n int, prov int, p_item int default null, p_job text default '00000000-0000-4000-c000-0000000000f1') returns void language plpgsql as $$
declare v_hash text := md5(n::text) || md5((n + 1000)::text); v_path text; v_s jsonb := pg_temp.sents(n); v_text text := pg_temp.txt(pg_temp.sents(n)); v_fid bigint; v_url text := 'https://example.test/course/' || n; v_rid uuid := pg_temp.rid(coalesce(p_item, n));
begin
  if p_item is null then
    insert into pim.entity_registry(id, stable_key) values (pg_temp.cid(n), 'cm-c' || n);
    insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status) values (pg_temp.cid(n), 'cm-c' || n, pg_temp.pid(prov), 'Cm Course ' || n, 'published');
    v_path := 'layer2/AU/coverage/src/' || pg_temp.cid(n) || '/' || v_hash || '.html.gz';
    insert into pipeline.evidence_artifacts(id, evidence_type, source_url, storage_path, content_hash, captured_at) values (pg_temp.eid(n), 'page', v_url, v_path, v_hash, now() - interval '3 days');
    insert into storage.objects(bucket_id, name, metadata) values ('evidence', v_path, '{"size": 5000}');
    insert into pipeline.coverage_course_pages(course_id, provider_id, status, identity_basis, url, evidence_id, read_status, read_at) values (pg_temp.cid(n), pg_temp.pid(prov), 'bound', 'course_title_on_page', v_url, pg_temp.eid(n), 'read', now() - interval '3 days');
  end if;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, evidence_id)
  select p_job::uuid, c.provider_id, c.id, 'description', 'review', 'ai_stored',
         jsonb_build_object('about_course', true, 'sentences', v_s, 'text', v_text, 'review_item_id', v_rid), (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = c.id)
    from catalogue.courses c where c.id = pg_temp.cid(n) returning id into v_fid;
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
  select v_rid, 'course', c.id, 'course_description_first_read', g.evidence_id, jsonb_build_object('description', null),
         jsonb_build_object('description', v_text, 'item_id', v_fid, 'source_url', g.url, 'checks', jsonb_build_object('sentences', 2), 'sentences', pg_temp.strip(v_s)),
         jsonb_build_object('source', 'course description reader', 'page', g.url, 'identity_basis', g.identity_basis),
         jsonb_build_object('item_id', v_fid, 'model', 'openai/gpt-4.1-mini', 'prompt', 'course-text-v2', 'worker', 'coverage-sweep-worker-v0.59.13'), 'pending', 'fixture', 'CF-CHG-20260915-247'
    from catalogue.courses c join pipeline.coverage_course_pages g on g.course_id = c.id where c.id = pg_temp.cid(n);
end $$;
-- replace the sentences of a case (the reading and the item together)
create function pg_temp.setsents(n int, s jsonb) returns void language sql as $$
  update pipeline.field_enrich_items set value = value || jsonb_build_object('sentences', s, 'text', pg_temp.txt(s)) where course_id = pg_temp.cid(n) and field = 'description' and state = 'review';
  update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('description', pg_temp.txt(s), 'sentences', pg_temp.strip(s)) where id = pg_temp.rid(n) $$;
create function pg_temp.got(p_rid uuid) returns text language sql as $$
  select coalesce((select 'admitted' from pipeline.course_description_machine_admissions a where a.review_item_id = p_rid and a.outcome = 'admitted' and a.withdrawn_at is null),
                  (select a.reason_code from pipeline.course_description_machine_admissions a where a.review_item_id = p_rid and a.outcome = 'declined'), 'nothing recorded') $$;
create function pg_temp.dsc(n int) returns text language sql as $$ select nullif(btrim(description), '') from catalogue.courses where id = pg_temp.cid(n) $$;
create function pg_temp.pending(n int) returns boolean language sql as $$ select exists (select 1 from pipeline.layer4_review_items where id = pg_temp.rid(n) and status = 'pending') $$;

-- the cases ---------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.mk(n, case when n in (16, 17) then 4 when n in (2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 18, 21, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 1) then 1
                          when n in (14, 15, 19, 20, 22) then 2 when n = 23 then 5 when n in (38, 39) then 3 else 1 end)
  from generate_series(1, 39) n;
-- 44 to 49: identity margin and near duplicates against the catalogue (46 is a clear match and is admitted)
select pg_temp.mk(n, 1) from generate_series(44, 49) n;
-- a described course of another provider that no Layer 4 item holds (95), for the catalogue-wide near-duplicate test
insert into pim.entity_registry(id, stable_key) values (pg_temp.cid(95), 'cm-c95');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status, description) values (pg_temp.cid(95), 'cm-c95', pg_temp.pid(3), 'Cm Course 95', 'published', pg_temp.txt(pg_temp.sents(95)));
-- a second waiting item on course 29
select pg_temp.mk(29, 1, 129, '00000000-0000-4000-c000-0000000000f2');
-- courses with no waiting item that other cases point at: 41 (another course for a reading), 42 (a rejected description), 43 (described)
insert into pim.entity_registry(id, stable_key) select pg_temp.cid(n), 'cm-c' || n from generate_series(41, 43) n;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status) values
  (pg_temp.cid(41), 'cm-c41', pg_temp.pid(1), 'Cm Course 41', 'published'), (pg_temp.cid(42), 'cm-c42', pg_temp.pid(3), 'Cm Course 42', 'published'), (pg_temp.cid(43), 'cm-c43', pg_temp.pid(3), 'Cm Course 43', 'published');

-- 2 evidence captured 100 days ago; 3 the bound copy moved; 4 ambiguous; 5 reading of another course; 6 a claim the quote does not carry; 7 a refused word the quote carries; 8 a figure; 9 quote not on the page
update pipeline.evidence_artifacts set captured_at = now() - interval '100 days' where id = pg_temp.eid(2);
insert into pipeline.evidence_artifacts(id, evidence_type, source_url) values (pg_temp.eid(300), 'page', 'https://example.test/other');
update pipeline.coverage_course_pages set evidence_id = pg_temp.eid(300) where course_id = pg_temp.cid(3);
update pipeline.coverage_course_pages set status = 'ambiguous' where course_id = pg_temp.cid(4);
update pipeline.field_enrich_items set course_id = pg_temp.cid(41) where course_id = pg_temp.cid(5) and field = 'description';
select pg_temp.setsents(6, jsonb_build_array(jsonb_build_object('text', 'The ' || pg_temp.w(6, 1) || ' programme is ranked among the best in the country for ' || pg_temp.w(6, 2) || ' and ' || pg_temp.w(6, 3) || '.',
        'quote', 'The ' || pg_temp.w(6, 1) || ' programme covers ' || pg_temp.w(6, 2) || ' and ' || pg_temp.w(6, 3) || ' in depth for every learner.', 'on_page', true)));
select pg_temp.setsents(7, jsonb_build_array(jsonb_build_object('text', 'The ' || pg_temp.w(7, 1) || ' programme is accredited by the professional body for ' || pg_temp.w(7, 2) || ' and ' || pg_temp.w(7, 3) || '.',
        'quote', 'The ' || pg_temp.w(7, 1) || ' programme is accredited by the professional body for ' || pg_temp.w(7, 2) || ' and ' || pg_temp.w(7, 3) || '.', 'on_page', true)));
select pg_temp.setsents(8, jsonb_build_array(jsonb_build_object('text', 'The ' || pg_temp.w(8, 1) || ' programme runs over 3 years and covers ' || pg_temp.w(8, 2) || ' and ' || pg_temp.w(8, 3) || ' in depth.',
        'quote', 'The ' || pg_temp.w(8, 1) || ' programme runs over 3 years and covers ' || pg_temp.w(8, 2) || ' and ' || pg_temp.w(8, 3) || ' in depth.', 'on_page', true)));
select pg_temp.setsents(9, jsonb_build_array(jsonb_build_object('text', 'The ' || pg_temp.w(9, 1) || ' programme covers ' || pg_temp.w(9, 2) || ' and ' || pg_temp.w(9, 3) || ' in depth for every learner.',
        'quote', 'The ' || pg_temp.w(9, 1) || ' programme covers ' || pg_temp.w(9, 2) || ' and ' || pg_temp.w(9, 3) || ' in depth for every learner.', 'on_page', false)));
-- 10 an empty answer; 11 hand lock; 12 hold on the course; 13 an earlier rejection for the course; 14 a page already rejected; 15 wording already rejected
update pipeline.field_enrich_items set value = value || jsonb_build_object('about_course', false, 'sentences', '[]'::jsonb) where course_id = pg_temp.cid(10) and field = 'description';
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(11), 'description', 'value');
insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason) values ('course', pg_temp.cid(12)::text, 'description', 'manual_hold', 'held by a person');
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at) values
  (pg_temp.rid(213), 'course', pg_temp.cid(13), 'course_description_first_read', pg_temp.eid(13), '{"description": null}', '{"description": "An older reading a person rejected."}', 'rejected', 'x', now() - interval '5 days');
update pipeline.coverage_course_pages set evidence_id = pg_temp.eid(13) where course_id = pg_temp.cid(14);
update pipeline.field_enrich_items set evidence_id = pg_temp.eid(13) where course_id = pg_temp.cid(14);
update pipeline.layer4_review_items set evidence_id = pg_temp.eid(13) where id = pg_temp.rid(14);
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at) values
  (pg_temp.rid(242), 'course', pg_temp.cid(42), 'course_description_first_read', null, '{"description": null}', jsonb_build_object('description', pg_temp.txt(pg_temp.sents(15))), 'rejected', 'x', now() - interval '5 days');
-- 16 and 17 the same wording at one provider; 18 and 19 the same wording at two providers; 20 the wording another course already holds; 21 and 22 almost the same at two providers
select pg_temp.setsents(17, pg_temp.sents(16));
select pg_temp.setsents(19, pg_temp.sents(18));
update catalogue.courses set description = pg_temp.txt(pg_temp.sents(20)) where id = pg_temp.cid(43);
select pg_temp.setsents(22, (select jsonb_set(pg_temp.sents(21), '{1,text}', to_jsonb(replace(pg_temp.sents(21)->1->>'text', pg_temp.w(21, 6), pg_temp.w(22, 6)))) ));
update pipeline.field_enrich_items set value = jsonb_set(value, '{sentences,1,quote}', to_jsonb(replace(pg_temp.sents(21)->1->>'quote', pg_temp.w(21, 6), pg_temp.w(22, 6)))) where course_id = pg_temp.cid(22);
-- 24 the address does not carry the hash; 25 the object is gone; 26 a failed re-read of the page; 27 a confirmed one
update pipeline.evidence_artifacts set content_hash = md5('another') || md5('hash') where id = pg_temp.eid(24);
delete from storage.objects where name like '%' || pg_temp.cid(25)::text || '%';
insert into pipeline.course_description_source_checks(course_id, evidence_id, result, content_hash_read, quotes_total, quotes_found) values
  (pg_temp.cid(26), pg_temp.eid(26), 'quote_missing', md5('26') || md5('1026'), 2, 1), (pg_temp.cid(27), pg_temp.eid(27), 'confirmed', md5('27') || md5('1027'), 2, 2);
-- 28 already described; 30 a proposal over an earlier text; 31 course archived; 32 course not in the feed; 33 the page address moved; 34 the reading text differs; 35 the reader is not recorded; 36 a proof the country does not admit; 37 reading not waiting
update catalogue.courses set description = 'A description that arrived another way and already stands for this course on the site.' where id = pg_temp.cid(28);
update pipeline.layer4_review_items set before_value = '{"description": "an earlier text"}' where id = pg_temp.rid(30);
update catalogue.courses set lifecycle_status = 'archived' where id = pg_temp.cid(31);
insert into pipeline.cdm_not_in_feed values (pg_temp.cid(32));
update catalogue.courses set publication_status = 'unpublished' where id = pg_temp.cid(27); -- the live feed answers for an unpublished course too: the read-back must still match
update pipeline.coverage_course_pages set basis = 'ai_match' where course_id = pg_temp.cid(44);
update pipeline.coverage_course_pages set basis = 'title_match', score = 0.9, runner_up = 0.85 where course_id = pg_temp.cid(45);
update pipeline.coverage_course_pages set basis = 'title_match', score = 0.9, runner_up = 0.6 where course_id = pg_temp.cid(46);
insert into pipeline.course_description_source_checks(course_id, evidence_id, result, content_hash_read, quotes_total, quotes_found, checked_at) values
  (pg_temp.cid(47), pg_temp.eid(47), 'confirmed', md5('another') || md5('copy'), 2, 2, now()),
  (pg_temp.cid(48), pg_temp.eid(48), 'confirmed', md5('48') || md5('1048'), 2, 2, now() - interval '100 days');
select pg_temp.setsents(49, (select jsonb_set(pg_temp.sents(95), '{1,text}', to_jsonb(replace(pg_temp.sents(95)->1->>'text', pg_temp.w(95, 6), pg_temp.w(49, 6))))));
update pipeline.field_enrich_items set value = jsonb_set(value, '{sentences,1,quote}', to_jsonb(replace(pg_temp.sents(95)->1->>'quote', pg_temp.w(95, 6), pg_temp.w(49, 6)))) where course_id = pg_temp.cid(49);
update pipeline.coverage_course_pages set url = 'https://example.test/moved' where course_id = pg_temp.cid(33);
update pipeline.field_enrich_items set value = value || jsonb_build_object('text', 'A different text than the one proposed for this course.') where course_id = pg_temp.cid(34);
update pipeline.layer4_review_items set layer3_state = layer3_state - 'model' where id = pg_temp.rid(35);
update pipeline.coverage_course_pages set identity_basis = 'host_page' where course_id = pg_temp.cid(36);
update pipeline.field_enrich_items set state = 'filled' where course_id = pg_temp.cid(37);

create function pg_temp.fnmd5() returns text language sql as $$ select md5(string_agg(p.oid::regprocedure::text || md5(p.prosrc), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.oid::regprocedure::text like 'website_v2_%' or p.oid::regprocedure::text like 'api.%' $$;
create temporary table g_state as select pg_temp.fnmd5() consumer_fn, (select value from pipeline.platform_toolset_settings where key = 'enrich.course_description_review_first') review_first, (select count(*) from pipeline.layer4_review_items) l4_start;

-- 0. the shipped state ---------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.expect('settings: the machine switch ships 0, on/off 0 to 1, with label, unit and used_by (G2); it is the only new setting',
  (select value = '0'::jsonb and min_value = 0 and max_value = 1 and unit = 'on/off' and label <> '' and used_by like '%course_description_machine_admit_v1%' and reason is not null and control_class = 'human' and help like '%not counted as a person''s trust%course_description_trusted_v1%' and help !~ 'course_text_verify|svc_course_description_source_check' from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on'));
select pg_temp.expect('the job is catalogued (G1) at rank 6 and scheduled with no number in its command',
  (select control_rank = 6 from pipeline.automation_catalogue where jobname = 'course-description-machine') and (select regexp_replace(command, '_v[0-9]+', '', 'g') !~ '[0-9]' from cron.job where jobname = 'course-description-machine'));
select pg_temp.expect('the ledger, the source-check table and the new functions are closed to anon and authenticated; RLS on',
  not has_table_privilege('authenticated', 'pipeline.course_description_machine_admissions', 'select') and not has_table_privilege('anon', 'pipeline.course_description_machine_admissions', 'select')
  and not has_table_privilege('authenticated', 'pipeline.course_description_source_checks', 'select')
  and (select relrowsecurity from pg_class where oid = 'pipeline.course_description_machine_admissions'::regclass) and (select relrowsecurity from pg_class where oid = 'pipeline.course_description_source_checks'::regclass)
  and not has_function_privilege('authenticated', 'security.course_description_machine_admit_v1(uuid,text)', 'execute') and not has_function_privilege('anon', 'security.course_description_machine_run_v1()', 'execute')
  and has_function_privilege('authenticated', 'public.admin_course_description_machine_withdraw_v1(uuid,text)', 'execute') and not has_function_privilege('anon', 'public.admin_course_description_machine_withdraw_v1(uuid,text)', 'execute'));
select pg_temp.expect('both tables carry a purpose (comment on table)',
  obj_description('pipeline.course_description_machine_admissions'::regclass) like 'CF-247 F-CDESC%' and obj_description('pipeline.course_description_source_checks'::regclass) like 'CF-247 F-CDESC%');

-- 1. switch off: Layer 4 behaves exactly as before ------------------------------------------------------------------------------------------------------
select pg_temp.expect('off: run, settle and admit do nothing', (security.course_description_machine_run_v1()->>'on')::boolean is false and (security.course_description_machine_settle_v1()->>'on')::boolean is false
  and security.course_description_machine_admit_v1(pg_temp.rid(1))->>'rule' = 'machine_admission_off' and (select count(*) from pipeline.course_description_machine_admissions) = 0);
-- a fresh reading through the live record function with the switch off: it waits in Layer 4 as before
insert into pim.entity_registry(id, stable_key) select pg_temp.cid(n), 'cm-c' || n from generate_series(60, 64) n;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status) select pg_temp.cid(n), 'cm-c' || n, pg_temp.pid(6), 'Cm Course ' || n, 'published' from generate_series(60, 64) n;
insert into pipeline.evidence_artifacts(id, evidence_type, source_url, storage_path, content_hash, captured_at)
select pg_temp.eid(n), 'page', 'https://example.test/course/' || n, 'layer2/AU/coverage/src/' || pg_temp.cid(n) || '/' || md5(n::text) || md5((n + 1000)::text) || '.html.gz', md5(n::text) || md5((n + 1000)::text), now() from generate_series(60, 64) n;
insert into storage.objects(bucket_id, name) select 'evidence', storage_path from pipeline.evidence_artifacts where id in (select pg_temp.eid(n) from generate_series(60, 64) n);
insert into pipeline.coverage_course_pages(course_id, provider_id, status, identity_basis, url, evidence_id, read_status, read_at)
select pg_temp.cid(n), pg_temp.pid(6), 'bound', 'course_title_on_page', 'https://example.test/course/' || n, pg_temp.eid(n), 'read', now() from generate_series(60, 64) n;
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, evidence_id, attempts) select '00000000-0000-4000-c000-0000000000f1', pg_temp.pid(6), pg_temp.cid(n), 'description', 'ai', 'ai_stored', pg_temp.eid(n), 1 from generate_series(60, 64) n;
create function pg_temp.reading(n int) returns jsonb language sql as $$ select jsonb_build_object('item_id', (select id from pipeline.field_enrich_items where course_id = pg_temp.cid(n) and field = 'description'), 'model', 'openai/gpt-4.1-mini', 'prompt_version', 'course-text-v2', 'worker', 'coverage-sweep-worker-v0.59.13',
  'value', jsonb_build_object('about_course', true, 'sentences', pg_temp.sents(n))) $$;
create temporary table g_rec60 as select security.enrich_course_text_record_v1((pg_temp.reading(60)->>'item_id')::bigint, pg_temp.reading(60)) r;
select pg_temp.expect('off: a fresh reading goes to Layer 4 and waits (today''s behaviour), nothing admitted, no ledger row',
  (select r = 'review' from g_rec60)
  and (select count(*)from pipeline.layer4_review_items where entity_id = pg_temp.cid(60) and status = 'pending') = 1 and pg_temp.dsc(60) is null
  and (select state from pipeline.field_enrich_items where course_id = pg_temp.cid(60)) = 'review' and (select count(*) from pipeline.course_description_machine_admissions) = 0);

-- 2. the shadow report (switch off, read only) ----------------------------------------------------------------------------------------------------------
create temporary table g_exp(rid uuid primary key, want text);
insert into g_exp values
 (pg_temp.rid(1), 'admitted'), (pg_temp.rid(2), 'evidence_stale'), (pg_temp.rid(3), 'evidence_moved'), (pg_temp.rid(4), 'binding_ambiguous'), (pg_temp.rid(5), 'reading_other_course'),
 (pg_temp.rid(6), 'check_unsupported_marketing'), (pg_temp.rid(7), 'policy_refused_word'), (pg_temp.rid(8), 'policy_figure'), (pg_temp.rid(9), 'check_quote_not_on_page'), (pg_temp.rid(10), 'check_not_stated'),
 (pg_temp.rid(11), 'manual_lock'), (pg_temp.rid(12), 'manual_hold'), (pg_temp.rid(13), 'rejected_before_course'), (pg_temp.rid(14), 'rejected_before_page'), (pg_temp.rid(15), 'rejected_before_text'),
 (pg_temp.rid(16), 'check_duplicate_other_course'), (pg_temp.rid(17), 'check_duplicate_other_course'), (pg_temp.rid(18), 'duplicate_exact_waiting'), (pg_temp.rid(19), 'duplicate_exact_waiting'),
 (pg_temp.rid(20), 'duplicate_exact_described'), (pg_temp.rid(21), 'duplicate_near_other_provider'), (pg_temp.rid(22), 'duplicate_near_other_provider'), (pg_temp.rid(23), 'provider_not_live'),
 (pg_temp.rid(24), 'lineage_hash_mismatch'), (pg_temp.rid(25), 'object_missing'), (pg_temp.rid(26), 'source_recheck_failed'), (pg_temp.rid(27), 'admitted'), (pg_temp.rid(28), 'description_already_held'),
 (pg_temp.rid(29), 'another_pending_item'), (pg_temp.rid(129), 'another_pending_item'), (pg_temp.rid(30), 'before_value_not_empty'), (pg_temp.rid(31), 'course_not_active'), (pg_temp.rid(32), 'admitted'),
 (pg_temp.rid(33), 'page_url_changed'), (pg_temp.rid(34), 'text_changed'), (pg_temp.rid(35), 'reader_unrecorded'), (pg_temp.rid(36), 'identity_not_allowed'), (pg_temp.rid(37), 'reading_not_current'),
 (pg_temp.rid(44), 'identity_margin_thin'), (pg_temp.rid(45), 'identity_margin_thin'), (pg_temp.rid(46), 'admitted'), (pg_temp.rid(47), 'source_recheck_unusable'), (pg_temp.rid(48), 'source_recheck_unusable'),
 (pg_temp.rid(49), 'duplicate_near_other_provider'), (pg_temp.rid(38), 'admitted'), (pg_temp.rid(39), 'admitted'), ((select id from pipeline.layer4_review_items where entity_id = pg_temp.cid(60)), 'admitted');
create temporary table g_shadow as select security.course_description_machine_shadow_v1(500, 0) s;
select pg_temp.expect('shadow (switch off): examines every waiting item, would admit the safe class, names the reason for the rest, and writes nothing',
  (select (s->>'waiting_items')::int = (select count(*) from g_exp) and (s->>'examined')::int = (select count(*) from g_exp) and (s->>'would_admit')::int = (select count(*) from g_exp where want = 'admitted')
          and (s->'by_reason'->>'duplicate_exact_waiting')::int = 2 and (s->'by_reason'->>'manual_lock')::int = 1 and jsonb_array_length(s->'sample_would_admit') = 5 and (s->>'switch_on')::boolean is false from g_shadow)
  and (select count(*) from pipeline.course_description_machine_admissions) = 0 and (select count(*) from pipeline.layer4_review_items) = (select l4_start from g_state) + 1 and (select count(*) from catalogue.courses where nullif(btrim(description), '') is not null) = 3);
select pg_temp.expect('shadow: pages (limit 10, offset 10) and says where the next page starts', (select (security.course_description_machine_shadow_v1(10, 10)->>'examined')::int = 10 and (security.course_description_machine_shadow_v1(10, 10)->>'next_offset')::int = 20));
select pg_temp.diag('evaluator differs', $q$select e.want || ' <> ' || coalesce(security.course_description_machine_check_v1(e.rid)->>'rule', 'null') from g_exp e where e.want <> 'admitted' and security.course_description_machine_check_v1(e.rid)->>'rule' is distinct from e.want$q$);
select pg_temp.diag('evaluator not ok', $q$select e.rid::text || ' ' || security.course_description_machine_check_v1(e.rid)::text from g_exp e where e.want = 'admitted' and not coalesce((security.course_description_machine_check_v1(e.rid)->>'ok')::boolean, false)$q$);
select pg_temp.expect('the evaluator names the same reasons the scenarios expect (one by one, read only)',
  (select count(*) = 0 from g_exp e where e.want <> 'admitted' and security.course_description_machine_check_v1(e.rid)->>'rule' is distinct from e.want)
  and (select count(*) = 0 from g_exp e where e.want = 'admitted' and not coalesce((security.course_description_machine_check_v1(e.rid)->>'ok')::boolean, false)));
select pg_temp.expect('the evaluator gives every decline an exact next action', (select count(*) = 0 from g_exp e where e.want <> 'admitted' and nullif(security.course_description_machine_check_v1(e.rid)->>'next_action', '') is null));

-- 3. switch on: one settlement ---------------------------------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on'; -- scratch database only: the release controller turns it on through the audited Admin UI
create temporary table g_run as select security.course_description_machine_settle_v1() r;
select pg_temp.expect('settle: admits exactly what the shadow said it would, leaves the rest for a person',
  (select (r->>'admitted')::int = (select (s->>'would_admit')::int from g_shadow) and (r->>'left_for_a_person')::int = (select (s->>'stay_for_a_person')::int from g_shadow) and (r->>'errors')::int = 0 from g_run));
select pg_temp.diag('case differs', $q$select e.want || ' <> ' || pg_temp.got(e.rid) from g_exp e where pg_temp.got(e.rid) is distinct from e.want$q$);
select pg_temp.diag('declined shape', $q$select e.want || ' ' || coalesce((select i.status || ' / ' || coalesce(i.escalation_reason, 'no reason') from pipeline.layer4_review_items i where i.id = e.rid), 'no item') from g_exp e where e.want <> 'admitted'
  and (not exists (select 1 from pipeline.layer4_review_items i where i.id = e.rid and i.status = 'pending' and i.escalation_reason like 'Machine rule cdesc-machine-v1 did not admit this: ' || e.want || '.%')
       or exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = e.rid)
       or not exists (select 1 from pipeline.course_description_machine_admissions a where a.review_item_id = e.rid and a.outcome = 'declined' and nullif(a.next_action, '') is not null and a.policy_stamp is not null))$q$);
select pg_temp.expect('every case ends as expected (' || (select count(*) from g_exp) || ' cases)', (select count(*) = 0 from g_exp e where pg_temp.got(e.rid) is distinct from e.want));
select pg_temp.expect('declined: still waiting, description still empty, never a decision, the exact reason on the item and in the ledger',
  (select count(*) = 0 from g_exp e where e.want <> 'admitted' and (not exists (select 1 from pipeline.layer4_review_items i where i.id = e.rid and i.status = 'pending' and i.escalation_reason like 'Machine rule cdesc-machine-v1 did not admit this: ' || e.want || '.%')
                                                                         or exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = e.rid)
                                                                         or not exists (select 1 from pipeline.course_description_machine_admissions a where a.review_item_id = e.rid and a.outcome = 'declined' and nullif(a.next_action, '') is not null and a.policy_stamp is not null)))
  and (select count(*) from catalogue.courses where nullif(btrim(description), '') is not null) = 3 + (select count(*) from g_exp where want = 'admitted'));
select pg_temp.expect('transient declines are marked and retried within the hour; permanent ones wait gaps.recheck_days',
  (select transient and retry_after < now() + interval '61 minutes' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(25) and outcome = 'declined')
  and (select not transient and retry_after > now() + interval '59 days' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(11) and outcome = 'declined'));

-- 4. what an admission writes ----------------------------------------------------------------------------------------------------------------------------
select pg_temp.expect('admitted (course 1): the description, the item approved, a machine decision, an event, a refresh signal and the ledger row, all consistent',
  pg_temp.dsc(1) = pg_temp.txt(pg_temp.sents(1)) and (select status = 'approved' and decided_at is not null from pipeline.layer4_review_items where id = pg_temp.rid(1))
  and (select d.actor_id = 'c0ffee00-0000-4000-8000-000000000150'::uuid and d.action = 'approve' and d.layer2_state->>'actor_kind' = 'machine' and d.layer2_state->>'machine_rule' = 'cdesc-machine-v1' and d.final_value = d.proposed_value and d.reason like 'Auto (cdesc-machine-v1%Not a person''s decision.'
              from pipeline.layer4_decisions d where d.review_item_id = pg_temp.rid(1))
  and (select count(*) = 1 from pipeline.admin_control_events e where e.area = 'layer4' and e.action = 'inbox_decide' and e.target = pg_temp.rid(1)::text and e.detail->>'actor_kind' = 'machine' and e.actor = 'c0ffee00-0000-4000-8000-000000000150'::uuid)
  and (select count(*) = 1 from pipeline.search_refresh_signals s join pipeline.layer4_decisions d on d.id = s.review_decision_id where d.review_item_id = pg_temp.rid(1) and s.entity_type = 'course' and s.entity_id = pg_temp.cid(1) and s.status = 'queued')
  and (select a.before_description is null and a.after_description = pg_temp.dsc(1) and a.evidence_id = pg_temp.eid(1) and a.content_hash = md5('1') || md5('1001') and a.source_url = 'https://example.test/course/1' and a.model = 'openai/gpt-4.1-mini'
              and a.prompt_version = 'course-text-v2' and a.worker like 'coverage-sweep-worker%' and a.rule = 'cdesc-machine-v1' and a.actor = 'c0ffee00-0000-4000-8000-000000000150'::uuid and a.consumer_check = 'matched' and a.recovery like 'Withdraw with%'
              and a.text_md5 = md5(pg_temp.dsc(1)) and a.checks->>'decision_id' = (select d.id::text from pipeline.layer4_decisions d where d.review_item_id = pg_temp.rid(1)) and a.storage_path like 'layer2/AU/coverage/%'
         from pipeline.course_description_machine_admissions a where a.review_item_id = pg_temp.rid(1) and a.outcome = 'admitted'));
select pg_temp.expect('admitted: the existing Layer 4 trigger followed (the reading is filled, a refresh was requested), the human route was not used (no human decision, review_first untouched)',
  (select state = 'filled' from pipeline.field_enrich_items where course_id = pg_temp.cid(1) and field = 'description') and exists (select 1 from search.refresh_requests)
  and (select count(*) from pipeline.layer4_decisions where actor_id <> 'c0ffee00-0000-4000-8000-000000000150'::uuid) = 0
  and (select value from pipeline.platform_toolset_settings where key = 'enrich.course_description_review_first') = (select review_first from g_state));
select pg_temp.expect('admitted (27): a recent confirmed re-read of the same page copy is recorded, and the feed (which answers for an unpublished course too) matches; (32): a course not in the feed is admitted and the ledger says so',
  (select checks->>'source_recheck' = 'confirmed' and consumer_check = 'matched' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(27) and outcome = 'admitted')
  and (select consumer_check = 'not_in_feed' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(32) and outcome = 'admitted'));
select pg_temp.expect('two providers are admitted in the same run (not one provider only)', (select count(distinct provider_id) from pipeline.course_description_machine_admissions where outcome = 'admitted') >= 2);

-- 5. idempotence -------------------------------------------------------------------------------------------------------------------------------------------
create temporary table g_before as select count(*) n, md5(string_agg(id::text, '' order by id)) h from pipeline.course_description_machine_admissions where outcome = 'admitted';
create temporary table g_declined_before as select count(*) n, md5(string_agg(id::text || created_at::text, '' order by id)) h from pipeline.course_description_machine_admissions where outcome = 'declined';
create temporary table g_second as select security.course_description_machine_settle_v1() r, security.course_description_machine_admit_v1(pg_temp.rid(1)) a;
select pg_temp.expect('a second settle admits nothing more; an approved item is not admitted again; one live admission for each course',
  (select (r->>'admitted')::int = 0 and a->>'rule' = 'item_not_pending' from g_second)
  and (select count(*) = (select n from g_before) and md5(string_agg(id::text, '' order by id)) = (select h from g_before) from pipeline.course_description_machine_admissions where outcome = 'admitted')
  and (select count(*) = 0 from (select course_id from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null group by 1 having count(*) > 1) z)
  and (select count(*) = 0 from pipeline.course_description_machine_admissions where outcome = 'declined' group by review_item_id having count(*) > 1 limit 1) is not false);
select pg_temp.expect('a second settle leaves declined items alone until the policy changes or the retry time passes (no new ledger rows, same created_at)',
  (select count(*) = (select n from g_declined_before) and md5(string_agg(id::text || created_at::text, '' order by id)) = (select h from g_declined_before) from pipeline.course_description_machine_admissions where outcome = 'declined'));
select pg_temp.expect('only the courses the ledger names were written: every described course is a ledger admission or one of the three that were described before',
  (select count(*) = 0 from catalogue.courses c where nullif(btrim(c.description), '') is not null and c.id not in (pg_temp.cid(28), pg_temp.cid(43), pg_temp.cid(95))
     and not exists (select 1 from pipeline.course_description_machine_admissions a where a.course_id = c.id and a.outcome = 'admitted' and a.withdrawn_at is null and a.after_description = nullif(btrim(c.description), ''))));

-- 6. the fresh reading hook ---------------------------------------------------------------------------------------------------------------------------------
create temporary table g_r61 as select security.enrich_course_text_record_v1((pg_temp.reading(61)->>'item_id')::bigint, pg_temp.reading(61)) r;
select pg_temp.expect('on: a fresh passing reading is admitted as it arrives (course 61), via fresh_reading, with the same record',
  (select r = 'review' from g_r61)
  and pg_temp.dsc(61) = pg_temp.txt(pg_temp.sents(61)) and (select status = 'approved' from pipeline.layer4_review_items where entity_id = pg_temp.cid(61))
  and (select checks->>'via' = 'fresh_reading' and consumer_check = 'matched' from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(61) and outcome = 'admitted')
  and (select state = 'filled' from pipeline.field_enrich_items where course_id = pg_temp.cid(61)));
create function pg_temp.reading_with(n int, s jsonb) returns jsonb language sql as $$ select pg_temp.reading(n) || jsonb_build_object('value', jsonb_build_object('about_course', true, 'sentences', s)) $$;
create temporary table g_r62 as select security.enrich_course_text_record_v1((pg_temp.reading(62)->>'item_id')::bigint, pg_temp.reading_with(62, jsonb_build_array(jsonb_build_object('text', 'The ' || pg_temp.w(62, 1) || ' programme is accredited by the professional body for ' || pg_temp.w(62, 2) || ' and ' || pg_temp.w(62, 3) || '.', 'quote', 'The ' || pg_temp.w(62, 1) || ' programme is accredited by the professional body for ' || pg_temp.w(62, 2) || ' and ' || pg_temp.w(62, 3) || '.', 'on_page', true)))) r;
select pg_temp.expect('on: a fresh reading with a refused word is not admitted: it waits in Layer 4 with the reason on it (course 62)',
  (select r = 'review' from g_r62) and pg_temp.dsc(62) is null
  and (select status = 'pending' and escalation_reason like 'Machine rule cdesc-machine-v1 did not admit this: policy_refused_word.%' from pipeline.layer4_review_items where entity_id = pg_temp.cid(62))
  and (select reason_code = 'policy_refused_word' from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(62) and outcome = 'declined'));
create temporary table g_r63 as select security.enrich_course_text_record_v1((pg_temp.reading(63)->>'item_id')::bigint, pg_temp.reading_with(63, (select jsonb_agg(x || '{"on_page": false}'::jsonb) from jsonb_array_elements(pg_temp.sents(63)) x))) r;
select pg_temp.expect('on: a reading whose quote is not on the page never reaches the machine (held by the existing check, no item, nothing admitted) (course 63)',
  (select r in ('held', 'not_stated') from g_r63) and pg_temp.dsc(63) is null and (select count(*) from pipeline.layer4_review_items where entity_id = pg_temp.cid(63)) = 0
  and (select state = 'skipped' from pipeline.field_enrich_items where course_id = pg_temp.cid(63)) and not exists (select 1 from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(63)));
-- timeout and cost cap: a read that timed out or was cut by the budget has no item; the settle does not make one
update pipeline.field_enrich_items set state = 'failed', reason = 'time budget' where course_id = pg_temp.cid(64);
select pg_temp.expect('a timed-out or budget-cut reading (state failed) is not touched by the machine', pg_temp.dsc(64) is null and not exists (select 1 from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(64)));

-- 7. the cost cap: no more in a run than enrich.course_text_items_per_day (derived), undecided items first -------------------------------------------------
select pg_temp.mk(n, 3) from generate_series(50, 54) n;
update pipeline.platform_toolset_settings set value = '2'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_text_items_per_day';
create temporary table g_cap1 as select security.course_description_machine_settle_v1() r;
select pg_temp.diag('cap run 1', $q$select r::text from g_cap1$q$);
select pg_temp.expect('cap: with 2 items a day the settle takes 2 of the 5 new waiting items a run',
  (select (r->>'admitted')::int = 2 from g_cap1) and (select count(*) from pipeline.layer4_review_items where entity_id in (select pg_temp.cid(n) from generate_series(50, 54) n) and status = 'approved') = 2);
create temporary table g_cap2 as select security.course_description_machine_settle_v1() r;
create temporary table g_cap3 as select security.course_description_machine_settle_v1() r;
select pg_temp.expect('cap: the next run takes 2 more, then the last one', (select (r->>'admitted')::int = 2 from g_cap2) and (select (r->>'admitted')::int = 1 from g_cap3));
update pipeline.platform_toolset_settings set value = '500'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_text_items_per_day';

-- 8. the Website read-back: lag, mismatch, error -------------------------------------------------------------------------------------------------------------
select pg_temp.mk(70, 3); select pg_temp.mk(71, 3); select pg_temp.mk(72, 3);
set cdm.consumer = 'lag';
create temporary table g_lag as select security.course_description_machine_admit_v1(pg_temp.rid(70)) r;
select pg_temp.expect('read-back lag: admitted, recorded as a lag (not a published count)', (select (r->>'ok')::boolean from g_lag) and pg_temp.dsc(70) is not null
  and (select consumer_check = 'lag' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(70) and outcome = 'admitted'));
set cdm.consumer = 'mismatch';
create temporary table g_mm as select security.course_description_machine_admit_v1(pg_temp.rid(71)) r;
select pg_temp.diag('mismatch', $q$select r::text || ' dsc=' || coalesce(pg_temp.dsc(71), 'null') || ' pending=' || pg_temp.pending(71)::text || ' dec=' || (select count(*) from pipeline.layer4_decisions where review_item_id = pg_temp.rid(71))::text
  || ' ev=' || (select count(*) from pipeline.admin_control_events where target = pg_temp.rid(71)::text)::text || ' led=' || coalesce((select reason_code || '/' || transient::text || '/' || coalesce(next_action, 'null') from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(71) and outcome = 'declined'), 'none') from g_mm$q$);
select pg_temp.expect('read-back mismatch: nothing written (the write is rolled back), the item waits, the reason and next action are recorded (course 71)',
  (select r->>'rule' = 'consumer_mismatch' from g_mm) and pg_temp.dsc(71) is null and pg_temp.pending(71)
  and not exists (select 1 from pipeline.layer4_decisions where review_item_id = pg_temp.rid(71)) and not exists (select 1 from pipeline.admin_control_events where target = pg_temp.rid(71)::text)
  and not exists (select 1 from pipeline.search_refresh_signals s join pipeline.layer4_decisions d on d.id = s.review_decision_id where d.review_item_id = pg_temp.rid(71))
  and (select reason_code = 'consumer_mismatch' and transient and nullif(next_action, '') is not null from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(71) and outcome = 'declined'));
set cdm.consumer = 'error';
create temporary table g_er as select security.course_description_machine_admit_v1(pg_temp.rid(72)) r;
select pg_temp.expect('read-back error: the database write is proven on the row, so it is admitted and recorded as error', (select (r->>'ok')::boolean from g_er) and pg_temp.dsc(72) is not null
  and (select consumer_check = 'error' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(72) and outcome = 'admitted'));
set cdm.consumer = '';
update pipeline.course_description_machine_admissions set consumer_checked_at = now() - interval '2 hours' where outcome = 'admitted' and consumer_check in ('lag', 'error'); -- the follow-up waits an hour before it reads a lag again
create temporary table g_rc as select security.course_description_machine_consumer_recheck_v1() r;
select pg_temp.diag('recheck', $q$select r::text from g_rc$q$);
select pg_temp.expect('the follow-up reads the feed again and records what it shows: the lag and the error become matched',
  (select (r->>'matched')::int >= 2 from g_rc) and (select consumer_check = 'matched' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(70) and outcome = 'admitted')
  and (select consumer_check = 'matched' from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(72) and outcome = 'admitted'));
-- a guard that puts the old text back: the write must stop the admission (the catalogue guard restores the value without an error)
select pg_temp.mk(73, 3);
create function pg_temp.guard_all() returns trigger language plpgsql as $$ begin NEW.description := OLD.description; return NEW; end $$;
create trigger cdm_guard before update on catalogue.courses for each row when (new.id = '00000000-0000-4000-c100-000000000073') execute function pg_temp.guard_all();
create temporary table g_gd as select security.course_description_machine_admit_v1(pg_temp.rid(73)) r;
select pg_temp.expect('a guard that keeps the old text stops the admission: nothing is claimed as written (course 73)',
  (select r->>'rule' = 'description_not_written' from g_gd) and pg_temp.dsc(73) is null and pg_temp.pending(73) and not exists (select 1 from pipeline.layer4_decisions where review_item_id = pg_temp.rid(73)));
drop trigger cdm_guard on catalogue.courses;

-- 9. forward recovery -------------------------------------------------------------------------------------------------------------------------------------------
insert into storage.objects(bucket_id, name) select 'evidence', storage_path from pipeline.evidence_artifacts where id = pg_temp.eid(25);
create temporary table g_fr1 as select security.course_description_machine_settle_v1() r;
select pg_temp.expect('a transient decline is not looked at before its time (object back, retry_after not reached)', (select (r->>'admitted')::int = 0 from g_fr1) and pg_temp.pending(25) and pg_temp.dsc(25) is null);
update pipeline.course_description_machine_admissions set retry_after = now() - interval '1 minute' where review_item_id = pg_temp.rid(25) and outcome = 'declined';
create temporary table g_fr2 as select security.course_description_machine_settle_v1() r;
select pg_temp.diag('forward recovery run', $q$select r::text from g_fr2$q$);
select pg_temp.expect('forward recovery: once its time has come the stored page is found and the description is admitted (course 25)', (select (r->>'admitted')::int >= 1 from g_fr2) and pg_temp.dsc(25) is not null
  and pg_temp.got(pg_temp.rid(25)) = 'admitted');
-- a policy change is looked at without waiting: the figures policy (the existing setting) now allows figures the quote carries; course 8 is declined for a figure
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.machine_numbers_allowed';
create temporary table g_fr3 as select security.course_description_machine_settle_v1() r;
select pg_temp.expect('a changed policy re-opens permanent declines: with figures allowed the figure case (8) is admitted at the next run', (select (r->>'admitted')::int >= 1 from g_fr3) and pg_temp.got(pg_temp.rid(8)) = 'admitted' and pg_temp.dsc(8) like '%3 years%');
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.machine_numbers_allowed';
-- a re-read that confirms the page lifts a failed re-read
insert into pipeline.course_description_source_checks(course_id, evidence_id, result, content_hash_read, quotes_total, quotes_found, checked_at) values (pg_temp.cid(26), pg_temp.eid(26), 'confirmed', md5('26') || md5('1026'), 2, 2, now() + interval '1 second');
update pipeline.course_description_machine_admissions set retry_after = now() - interval '1 minute' where review_item_id = pg_temp.rid(26) and outcome = 'declined';
create temporary table g_fr4 as select security.course_description_machine_settle_v1() r;
select pg_temp.expect('a later confirming re-read of the same page lifts a failed one (26)', (select (r->>'admitted')::int >= 1 from g_fr4) and pg_temp.got(pg_temp.rid(26)) = 'admitted');
-- a retry that still fails stays declined with one ledger row per item
select pg_temp.expect('a declined item has one declined ledger row however many runs looked at it', (select count(*) = 0 from (select review_item_id from pipeline.course_description_machine_admissions where outcome = 'declined' group by 1 having count(*) > 1) z));

-- 10. withdrawal ----------------------------------------------------------------------------------------------------------------------------------------------
create function pg_temp.as_user(p_rank int) returns void language plpgsql as $$ begin perform set_config('g.uid', '00000000-0000-4000-a000-000000000001', false); perform set_config('g.rank', p_rank::text, false); end $$;
select pg_temp.as_user(3);
do $$ declare ok boolean := false; begin begin perform public.admin_course_description_machine_withdraw_v1(pg_temp.cid(1), 'try'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.expect('withdraw: a curator (rank 3) is refused, nothing changes', ok and pg_temp.dsc(1) is not null); end $$;
select pg_temp.as_user(6);
create temporary table g_wd as select public.admin_course_description_machine_withdraw_v1(pg_temp.cid(1), 'Wrong wording found on review') r;
create temporary table g_wd2 as select public.admin_course_description_machine_withdraw_v1(pg_temp.cid(1), 'again') r;
select pg_temp.diag('withdraw', $q$select r::text from g_wd$q$);
select pg_temp.expect('withdraw: the Platform Admin restores the empty description, the ledger and the log name the person and why, the refresh is queued on the admission''s own decision',
  (select (r->>'ok')::boolean from g_wd) and pg_temp.dsc(1) is null
  and (select withdrawn_at is not null and withdrawn_by = '00000000-0000-4000-a000-000000000001'::uuid and withdrawn_reason = 'Wrong wording found on review' from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(1) and outcome = 'admitted')
  and exists (select 1 from pipeline.admin_control_events where action = 'cdesc_machine_withdraw' and target = pg_temp.cid(1)::text and actor = '00000000-0000-4000-a000-000000000001'::uuid)
  and (select count(*) = 1 and bool_and(status = 'queued') from pipeline.search_refresh_signals s join pipeline.layer4_decisions d on d.id = s.review_decision_id where d.review_item_id = pg_temp.rid(1))
  and (select r->>'rule' = 'no_live_machine_admission' from g_wd2));
-- the withdrawn course is not left alone: it has no description and its last reading is filled, so the standing gap queue (the production one, from the fixture) offers it for a new reading
select pg_temp.expect('withdraw: the course goes back to the standing gap queue for a fresh read (no counting flag to release), where its new reading is then held for a person',
  exists (select 1 from security.enrich_course_text_gaps_v1(array['description']) q where q.course_id = pg_temp.cid(1))
  and not exists (select 1 from pipeline.enrichment_flags where entity_key = pg_temp.cid(1)::text and state in ('raised', 'counting')));
-- a new reading for the withdrawn course waits for a person
select pg_temp.mk(1, 1, 301, '00000000-0000-4000-c000-0000000000f2');
create temporary table g_wd3 as select security.course_description_machine_admit_v1(pg_temp.rid(301)) r;
select pg_temp.expect('after a withdrawal the course is held out of the machine until a person decides (301)', (select r->>'rule' = 'withdrawn_awaiting_person' from g_wd3) and pg_temp.dsc(1) is null and pg_temp.pending(301));
-- a person's change since the admission is kept; a lock added since is kept
update catalogue.courses set description = 'A person wrote this better description for the course.' where id = pg_temp.cid(38);
create temporary table g_wd4 as select public.admin_course_description_machine_withdraw_v1(pg_temp.cid(38), 'try') r;
select pg_temp.expect('withdraw: a description a person changed since is kept', (select r->>'rule' = 'description_changed_since_admission' from g_wd4) and pg_temp.dsc(38) like 'A person wrote%');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(39), 'description', 'value');
create temporary table g_wd5 as select public.admin_course_description_machine_withdraw_v1(pg_temp.cid(39), 'try') r;
select pg_temp.expect('withdraw: a lock added since is kept and the description stays', (select r->>'rule' = 'manual_lock' from g_wd5) and pg_temp.dsc(39) is not null);
do $$ declare ok boolean := false; begin begin perform security.course_description_machine_withdraw_v1(pg_temp.cid(53), 'x', 'c0ffee00-0000-4000-8000-000000000150'::uuid); exception when others then ok := true; end;
  perform pg_temp.expect('withdraw: the system account is never recorded as the person, and nothing changes', ok and pg_temp.dsc(53) is not null); end $$;

-- 11. a held reading that a decision promotes inside an admission: the chain is bounded; the promoted reading carries no recorded reader, so it waits for a person ----------
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_max';
select pg_temp.mk(80, 7); select pg_temp.mk(81, 7);
update pipeline.field_enrich_items set state = 'skipped', reason = 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved' where course_id = pg_temp.cid(81);
delete from pipeline.layer4_review_items where id = pg_temp.rid(81);
create temporary table g_ph as select security.course_description_machine_admit_v1(pg_temp.rid(80)) r;
select pg_temp.diag('promote', $q$select r::text || ' d80=' || coalesce(pg_temp.dsc(80), 'null') || ' d81=' || coalesce(pg_temp.dsc(81), 'null') || ' items81=' || (select count(*) from pipeline.layer4_review_items where entity_id = pg_temp.cid(81))::text
  || ' led81=' || coalesce((select outcome || '/' || reason_code from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(81) limit 1), 'none') from g_ph$q$);
select pg_temp.expect('promote-held inside an admission: the admission completes; the promoted reading becomes an item that waits for a person because its reader is not recorded (courses 80 and 81)',
  (select (r->>'ok')::boolean from g_ph) and pg_temp.dsc(80) is not null and pg_temp.dsc(81) is null
  and exists (select 1 from pipeline.layer4_review_items where entity_id = pg_temp.cid(81) and status = 'pending')
  and (select reason_code = 'reader_unrecorded' from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(81) and outcome = 'declined'));
update pipeline.platform_toolset_settings set value = '10'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_max';

-- TRUST ACCOUNTING (regression that fails on the old function): security.course_description_trusted_v1 counts the provider's latest decided descriptions as person-trust. A machine approval is an approved item too; it must not
-- count. At review_first 1 a provider whose only decision is a machine approval is NOT trusted; one human approval (older than the machine ones) makes it trusted; the shipped value is restored.
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_review_first';
create temporary table g_trust1 as select security.course_description_trusted_v1(pg_temp.pid(1)) machine_only;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at) values
  (pg_temp.rid(241), 'course', pg_temp.cid(41), 'course_description_first_read', null, '{"description": null}', '{"description": "A person approved this description in Layer 4."}', 'approved', 'x', now() - interval '1 hour');
create temporary table g_trust2 as select security.course_description_trusted_v1(pg_temp.pid(1)) with_human;
update pipeline.platform_toolset_settings set value = to_jsonb((select review_first::text::numeric from g_state)) where toolset_key = 'pipeline' and key = 'enrich.course_description_review_first';
select pg_temp.expect('trust accounting: machine approvals are not person-trust (review_first 1: machine-only provider is not trusted; one human approval makes it trusted); the shipped value is restored and nobody is trusted at it',
  (select machine_only is not true from g_trust1) and (select with_human is true from g_trust2)
  and (select value from pipeline.platform_toolset_settings where key = 'enrich.course_description_review_first') = (select review_first from g_state)
  and not coalesce(security.course_description_trusted_v1(pg_temp.pid(1)), false)
  and (select count(*) > 0 from pipeline.layer4_decisions d where d.layer2_state->>'actor_kind' = 'machine'));

-- THE EXISTING MEASURES (regressions that fail on the old bodies): a machine decision is a Layer 4 decision with status approved, but it is not a person's. Summary (admitted by a person), capacity (decided a day, approved ever),
-- the sample report (approved share) and the reviewer pace must leave it out and show it apart. Course 95 is described (provider 3). Person: items 500 to 506 approved (500 carries the course's own text), 507 rejected,
-- decisions 4 minutes apart. Machine: 7 synthetic approved items (510 to 516) with machine decisions 10 minutes apart, besides the real admissions above. Expected counts are taken from item ids, not from the decision marker.
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at)
select pg_temp.rid(k), 'course', pg_temp.cid(95), 'course_description_first_read', null, '{"description": null}'::jsonb,
       jsonb_build_object('description', case when k = 500 then (select description from catalogue.courses where id = pg_temp.cid(95)) else 'A decided text number ' || k end),
       case when k = 507 then 'rejected' else 'approved' end, 'x', now() - interval '1 hour'
  from generate_series(500, 507) k;
insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, layer2_state, layer3_state, change_control_ref, created_at)
select pg_temp.rid(k), case when k = 507 then 'reject' else 'approve' end, '00000000-0000-4000-a000-000000000001'::uuid, '[other] x', '{}'::jsonb, '{}'::jsonb, 'x', now() - interval '4 minutes' * (508 - k)
  from generate_series(500, 507) k;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at)
select pg_temp.rid(k), 'course', pg_temp.cid(95), 'course_description_first_read', null, '{"description": null}'::jsonb, jsonb_build_object('description', 'A machine text number ' || k), 'approved', 'x', now() - interval '1 hour'
  from generate_series(510, 516) k;
insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, layer2_state, layer3_state, change_control_ref, created_at)
select pg_temp.rid(k), 'approve', 'c0ffee00-0000-4000-8000-000000000150'::uuid, 'Auto (cdesc-machine-v1): x', jsonb_build_object('machine_rule', 'cdesc-machine-v1', 'actor_kind', 'machine'), '{}'::jsonb, 'x', now() - interval '10 minutes' * (517 - k)
  from generate_series(510, 516) k;
create temporary table g_mitems as select i.id from pipeline.layer4_review_items i
 where i.id in (select l.review_item_id from pipeline.course_description_machine_admissions l where l.outcome = 'admitted') or i.id in (select pg_temp.rid(k) from generate_series(510, 516) k);
update pipeline.platform_toolset_settings set value = '1000'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_sample_au';
create temporary table g_ms as select security.course_description_summary_v1(null, false) j;
create temporary table g_mc as select security.course_description_capacity_v1() j;
create temporary table g_mr as select security.course_description_sample_report_v1() j;
create temporary table g_mp as select security.layer4_pace_v1() -> 'course_description_first_read' j;
create temporary table g_mx as select
  (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.status in ('approved', 'edited_approved') and i.id not in (select id from g_mitems)) person_approved,
  (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.status in ('approved', 'edited_approved') and i.id in (select id from g_mitems)) machine_approved,
  (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.status in ('approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
      and i.decided_at > now() - interval '7 days' and i.id not in (select id from g_mitems)) person_decided,
  (select count(*) from pipeline.layer4_review_items i join pipeline.course_description_machine_admissions l on l.review_item_id = i.id
     where l.outcome = 'admitted' and i.status in ('approved', 'edited_approved') and nullif(btrim((select c.description from catalogue.courses c where c.id = i.entity_id)), '') is not distinct from nullif(btrim(i.proposed_value->>'description'), '')) machine_admitted_matching,
  (select count(*) from security.course_description_sample_pool_v1() p join pipeline.layer4_review_items i on i.id = p.item_id where i.status in ('approved', 'edited_approved') and i.id not in (select id from g_mitems)) sample_person_approved,
  (select count(*) from security.course_description_sample_pool_v1() p join pipeline.layer4_review_items i on i.id = p.item_id where i.status in ('approved', 'edited_approved') and i.id in (select id from g_mitems)) sample_machine_approved,
  (select count(*) from security.course_description_sample_pool_v1() p join pipeline.layer4_review_items i on i.id = p.item_id where i.status <> 'pending' and i.id not in (select id from g_mitems)) sample_person_decided;
update pipeline.platform_toolset_settings set value = '30'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_sample_au';
select pg_temp.diag('measures', $q$select 'ms=' || (g_ms.j->>'admitted_by_person') || '/' || coalesce(g_ms.j->>'admitted_by_machine', 'null') || ' mc=' || (g_mc.j->>'approved_ever') || '/' || coalesce(g_mc.j->>'approved_by_machine', 'null') || '/' || (g_mc.j->>'decided_in_window')
  || ' mr=' || (g_mr.j->>'approved') || '/' || coalesce(g_mr.j->>'approved_by_machine', 'null') || '/' || coalesce(g_mr.j->>'approval_share_of_decided', 'null') || ' mp=' || coalesce(g_mp.j::text, 'null')
  || ' mx=' || g_mx.person_approved || '/' || g_mx.machine_approved || '/' || g_mx.person_decided || '/' || g_mx.machine_admitted_matching || '/' || g_mx.sample_person_approved || '/' || g_mx.sample_machine_approved || '/' || g_mx.sample_person_decided from g_ms, g_mc, g_mr, g_mp, g_mx$q$);
select pg_temp.expect('summary: admitted by a person leaves out the machine admissions, which are counted apart (the two add up to what the old count said)',
  (select (j->>'admitted_by_person')::int = 1 and (j->>'admitted_by_machine')::int = (select machine_admitted_matching from g_mx) and (select machine_admitted_matching from g_mx) > 0 from g_ms));
select pg_temp.expect('capacity: approved ever and decided a day leave out the machine decisions, which are counted apart',
  (select (j->>'approved_ever')::int = (select person_approved from g_mx) and (j->>'approved_by_machine')::int = (select machine_approved from g_mx) and (select machine_approved from g_mx) >= 7
          and (j->>'decided_in_window')::int = (select person_decided from g_mx) and (j->>'decided_a_day')::numeric = round((select person_decided from g_mx) / 7.0, 1) from g_mc));
select pg_temp.expect('sample report: the approved count and approval share leave out the machine approvals, which are counted apart',
  (select (j->>'approved')::int = (select sample_person_approved from g_mx) and (j->>'approved_by_machine')::int = (select sample_machine_approved from g_mx) and (select sample_machine_approved from g_mx) >= 7
          and (j->>'approval_share_of_decided')::numeric = round((select sample_person_approved from g_mx)::numeric / (select sample_person_decided from g_mx), 3) from g_mr));
select pg_temp.expect('reviewer pace: machine decisions (10 minutes apart under the system account) are not read as a reviewer: only the person''s 7 gaps of 4 minutes are measured',
  (select (j->>'measured')::int = 7 and (j->>'minutes')::numeric = 4 and j->>'basis' = 'measured' from g_mp));
delete from pipeline.layer4_decisions where review_item_id in (select pg_temp.rid(k) from generate_series(500, 516) k);
delete from pipeline.layer4_review_items where id in (select pg_temp.rid(k) from generate_series(500, 516) k);

-- 12. the report and the consumer API -----------------------------------------------------------------------------------------------------------------------
select pg_temp.expect('the scoreboard counts admissions, withdrawals, providers, the Website state and the reasons',
  (select (r->>'admitted')::int = (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null) and (r->>'withdrawn')::int = 1 and (r->>'admitted_by_provider')::int >= 3
          and (r->'website'->>'matched')::int >= 3 and (r->'declined_by_reason'->>'manual_lock')::int = 1 and (r->>'switch_on')::boolean from (select security.course_description_machine_report_v1() r) z));
select pg_temp.expect('the consumer API objects are unchanged (same bodies), review_first is untouched, no human decision was written, nothing was deleted',
  pg_temp.fnmd5() = (select consumer_fn from g_state) and (select value from pipeline.platform_toolset_settings where key = 'enrich.course_description_review_first') = (select review_first from g_state)
  and (select count(*) from pipeline.layer4_review_items) >= (select l4_start from g_state) and (select count(*) from pipeline.layer4_decisions where actor_id <> 'c0ffee00-0000-4000-8000-000000000150'::uuid) = 0);

do $$ declare n_fail int := (select count(*) from g_t where not ok); n int := (select count(*) from g_t);
begin
  if n_fail > 0 then raise exception 'cdm: % of % checks FAILED', n_fail, n; end if;
  raise notice 'cdm: all % checks passed', n;
end $$;
