-- Guards: F-CDESC first-cycle check of Pilot #1047 (migration 20261112190000): a description reading marked reread:, or superseded in Layer 4, is read again whatever prompt made it; a held reading the released prompt made is not;
-- "students" as the subject of a supported sentence no longer holds it while rankings, outcomes and accreditation still do; the relabel marks only worker v0.72.0's unsupported_sentence and quote_not_on_page holds. Every row is
-- invented. Runs after the cdesc-machine prelude and the helper functions of tests/fixtures/cdesc-source-grounded/scenarios.sql (from pg_temp.fault to the start of section 1).
create function pg_temp.fault(t text, q text) returns text language sql as $$
  select coalesce(security.cdesc_sentence_fault_v1(t, q, true, security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), 0.6)->>'rule', 'ok') $$;
create function pg_temp.newpage(n int, prov int) returns void language plpgsql as $$
declare v_hash text := md5(n::text) || md5((n + 1000)::text); v_path text := 'layer2/AU/coverage/src/' || pg_temp.cid(n) || '/' || md5(n::text) || md5((n + 1000)::text) || '.html.gz';
begin
  insert into pim.entity_registry(id, stable_key) values (pg_temp.cid(n), 'cm-c' || n);
  insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status, lifecycle_status) values (pg_temp.cid(n), 'cm-c' || n, pg_temp.pid(prov), 'Cm Course ' || n, 'published', 'active');
  insert into pipeline.evidence_artifacts(id, evidence_type, source_url, storage_path, content_hash, captured_at) values (pg_temp.eid(n), 'page', 'https://example.test/course/' || n, v_path, v_hash, now() - interval '3 days');
  insert into storage.objects(bucket_id, name, metadata) values ('evidence', v_path, '{"size": 5000}');
  insert into pipeline.coverage_course_pages(course_id, provider_id, status, identity_basis, url, evidence_id, read_status, read_at)
  values (pg_temp.cid(n), pg_temp.pid(prov), 'bound', 'course_title_on_page', 'https://example.test/course/' || n, pg_temp.eid(n), 'read', now() - interval '3 days');
end $$;
-- one recent reading of a course: state, reason and the prompt that made it (value.prompt_version for the released prompt, value.reader.prompt for a held reading of course-text-v*)
create function pg_temp.last(n int, prov int, p_state text, p_reason text, p_value jsonb) returns void language sql as $$
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, reason, value, evidence_id, updated_at)
  values ('00000000-0000-4000-c000-0000000000f1', pg_temp.pid(prov), pg_temp.cid(n), 'description', p_state, 'ai_stored', p_reason, p_value, pg_temp.eid(n), now() - interval '1 hour') $$;
create function pg_temp.picked(n int) returns boolean language sql as $$
  select exists (select 1 from security.enrich_course_text_gaps_v1(array['description']) g where g.course_id = pg_temp.cid(n)) $$;
create function pg_temp.decline(n int, p_transient boolean default false, p_stamp text default null) returns void language sql as $$
  insert into pipeline.course_description_machine_admissions(course_id, provider_id, review_item_id, rule, outcome, reason_code, transient, policy_stamp, actor)
  select q.entity_id, c.provider_id, q.id, 'cdesc-machine-v1', 'declined', 'policy_refused_word', p_transient, coalesce(p_stamp, security.course_description_machine_policy_stamp_v1()), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
    from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id where q.id = pg_temp.rid(n) $$;
create function pg_temp.status(n int) returns text language sql as $$ select status from pipeline.layer4_review_items where id = pg_temp.rid(n) $$;
create function pg_temp.rreason(n int) returns text language sql as $$ select reason from pipeline.field_enrich_items where course_id = pg_temp.cid(n) and field = 'description' order by id desc limit 1 $$;

-- ---- 1. read again on a recorded mark, whatever the prompt -------------------------------------------------------------------------------------------------------------------
select pg_temp.newpage(n, 2) from generate_series(711, 715) n;
select pg_temp.last(711, 2, 'skipped', 'reread: v0.72.0 mapping: held: quote_not_on_page: a sentence''s words are not on the course page', jsonb_build_object('prompt_version', 'cdesc-source-grounded-v1', 'reader', jsonb_build_object('model', 'm', 'prompt', 'cdesc-source-grounded-v1', 'worker', 'coverage-sweep-worker-v0.72.0')));
select pg_temp.last(712, 2, 'skipped', 'superseded: declined for good under cdesc-source-grounded-v1', jsonb_build_object('prompt_version', 'cdesc-source-grounded-v1'));
select pg_temp.last(713, 2, 'skipped', 'held: copied_sentence: a sentence repeats 10 or more words', jsonb_build_object('prompt_version', 'cdesc-source-grounded-v1', 'reader', jsonb_build_object('model', 'm', 'prompt', 'cdesc-source-grounded-v1')));
select pg_temp.last(714, 2, 'skipped', 'held: unsupported_sentence: x', jsonb_build_object('reader', jsonb_build_object('model', 'm', 'prompt', 'course-text-v2')));
select pg_temp.last(715, 2, 'skipped', 'not admitted in Layer 4 (rejected)', jsonb_build_object('prompt_version', 'cdesc-source-grounded-v1'));
select pg_temp.expect('REGRESSION reread: a reading the released prompt made and marked reread: is read again', pg_temp.picked(711));
select pg_temp.expect('REGRESSION reread: a reading superseded in Layer 4 is read again whatever prompt made it', pg_temp.picked(712));
select pg_temp.expect('kept: a held reading the released prompt made is not read again (it waits for the recheck days)', not pg_temp.picked(713));
select pg_temp.expect('kept: a held reading an earlier prompt made is still read again', pg_temp.picked(714));
select pg_temp.expect('kept: a description a person rejected is never read again', not pg_temp.picked(715));
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(711), 'description', 'value');
select pg_temp.expect('kept: a locked course is never read again', not pg_temp.picked(711));

-- ---- 2. "students" -----------------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.expect('REGRESSION students: "Students study ..." supported by its spans is no longer an unsupported claim',
  pg_temp.fault('Students study typography, user research and prototyping across three years of studio units.', 'The degree covers typography, user research and prototyping in studio units across three years.') = 'ok');
select pg_temp.expect('kept: a ranking the spans do not hold is still unsupported_claim',
  pg_temp.fault('The degree is ranked for typography, user research and prototyping in studio units.', 'The degree covers typography, user research and prototyping in studio units across three years.') = 'unsupported_claim');
select pg_temp.expect('kept: accreditation the spans do not hold is still unsupported_claim',
  pg_temp.fault('The accredited degree covers typography, user research and prototyping in studio units.', 'The degree covers typography, user research and prototyping in studio units across three years.') = 'unsupported_claim');

do $$ begin
  if exists (select 1 from g_t where not ok) then raise notice 'cdrr: % FAIL', (select count(*) from g_t where not ok); else raise notice 'cdrr: all % pass', (select count(*) from g_t); end if;
end $$;
