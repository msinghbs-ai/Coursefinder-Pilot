-- Guards: F-CDESC cdesc-source-grounded-v1 (Platform Admin 11 Nov 2026, Admin PR #430 COURSE-DESCRIPTION-PRODUCTION-DESIGN.md): copied sentences, generic phrases and unverified claims are held; a reading an earlier prompt made that a check held
-- (or Layer 4 superseded) is read once more with the released prompt; a waiting first description an earlier prompt made that the machine declined for good under the current policy is superseded and read again; a person's decision, a lock,
-- a description the released prompt made, a transient decline or one at an old policy is never superseded. Every row is invented. Runs after the cdesc-machine prelude (tests/fixtures/cdesc-machine/scenarios.sql lines 5 to 88).
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

-- ---- 1. the per-sentence tests ------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.expect('REGRESSION copied: a sentence that repeats 14 words of its source in order is held (copied_sentence)',
  pg_temp.fault('The course has you study design thinking, user research, prototyping and usability testing in the studio units.',
                'You study design thinking, user research, prototyping and usability testing in the studio units across three years.') = 'copied_sentence');
select pg_temp.expect('paraphrase: an original sentence its source supports passes (no run of 10 words)',
  pg_temp.fault('Studio units cover design thinking and user research, then prototyping and usability testing.',
                'You study design thinking, user research, prototyping and usability testing in the studio units across three years.') = 'ok');
select pg_temp.expect('REGRESSION generic: "comprehensive program" is held even when the page says it (generic_phrase)',
  pg_temp.fault('This comprehensive program covers design thinking and user research in studio units.',
                'This comprehensive program covers design thinking and user research in studio units over three years.') = 'generic_phrase');
select pg_temp.expect('REGRESSION generic: "designed to equip" is held (generic_phrase)',
  pg_temp.fault('The degree is designed to equip you with design thinking and user research methods.',
                'The degree is designed to equip you with design thinking and user research methods.') = 'generic_phrase');
select pg_temp.expect('kept: the earlier tests still run first (a sentence off the page is quote_not_on_page)',
  coalesce(security.cdesc_sentence_fault_v1('Studio units cover design thinking.', '', false, '[]'::jsonb, '[]'::jsonb, 0.6)->>'rule', 'ok') = 'quote_not_on_page');
select pg_temp.expect('kept: an incomplete sentence is still incomplete_sentence',
  pg_temp.fault('Studio units cover design thinking and user research', 'Studio units cover design thinking and user research over three years.') = 'incomplete_sentence');
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_copy_run_words';
select pg_temp.expect('setting: copy_run_words 0 switches the copy test off',
  pg_temp.fault('The course has you study design thinking, user research, prototyping and usability testing in the studio units.',
                'You study design thinking, user research, prototyping and usability testing in the studio units across three years.') = 'ok');
update pipeline.platform_toolset_settings set value = '13'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_copy_run_words';
select pg_temp.expect('setting: copy_run_words 13 holds the 14-word run',
  pg_temp.fault('The course has you study design thinking, user research, prototyping and usability testing in the studio units.',
                'You study design thinking, user research, prototyping and usability testing in the studio units across three years.') = 'copied_sentence');
update pipeline.platform_toolset_settings set value = '15'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_copy_run_words';
select pg_temp.expect('setting: copy_run_words 15 lets the same 14-word run pass',
  pg_temp.fault('The course has you study design thinking, user research, prototyping and usability testing in the studio units.',
                'You study design thinking, user research, prototyping and usability testing in the studio units across three years.') = 'ok');
update pipeline.platform_toolset_settings set value = '10'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_copy_run_words';

-- ---- 2. unverified claims -----------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.newpage(801, 1);
create function pg_temp.chk(p_unverified jsonb) returns text language sql as $$
  select security.course_description_check_v1(pg_temp.cid(801), jsonb_build_object('about_course', true, 'unverified_claims', p_unverified, 'sentences', jsonb_build_array(
    jsonb_build_object('text', 'Studio units cover design thinking and user research, then prototyping and usability testing.', 'quote', 'You study design thinking, user research, prototyping and usability testing in the studio units across three years.', 'on_page', true),
    jsonb_build_object('text', 'The final year centres on an industry brief completed with a design team.', 'quote', 'In the final year you complete an industry brief in a design team.', 'on_page', true))))->>'rule' $$;
select pg_temp.expect('ok: a source-backed description with no unverified claim passes the check', pg_temp.chk('[]'::jsonb) = 'ok');
select pg_temp.expect('ok: an unverified claim the description leaves out does not hold it', pg_temp.chk('["Graduates are hired by leading agencies within six months."]'::jsonb) = 'ok');
select pg_temp.expect('REGRESSION unverified: a description that carries a claim the writer could not tie to the page is held (unverified_claims)',
  pg_temp.chk('["The final year centres on an industry brief completed with a design team."]'::jsonb) = 'unverified_claims');

-- ---- 3. read again with the released prompt -----------------------------------------------------------------------------------------------------------------------------
select pg_temp.newpage(n, 2) from generate_series(701, 707) n;
select pg_temp.last(701, 2, 'skipped', 'held: copied_sentence: a sentence repeats 10 or more words', jsonb_build_object('reader', jsonb_build_object('model', 'm', 'prompt', 'course-text-v2')));
select pg_temp.last(702, 2, 'skipped', 'held: unsupported_sentence: a sentence is not supported', jsonb_build_object('prompt_version', 'cdesc-source-grounded-v1', 'reader', jsonb_build_object('model', 'm', 'prompt', 'cdesc-source-grounded-v1')));
select pg_temp.last(703, 2, 'skipped', 'not admitted in Layer 4 (rejected)', jsonb_build_object('reader', jsonb_build_object('model', 'm', 'prompt', 'course-text-v2')));
select pg_temp.last(704, 2, 'skipped', 'superseded: declined for good under course-text-v2; read again with cdesc-source-grounded-v1', '{}'::jsonb);
select pg_temp.last(705, 2, 'skipped', 'held_first_admission: the provider''s first descriptions wait in Layer 4', jsonb_build_object('reader', jsonb_build_object('model', 'm', 'prompt', 'course-text-v1')));
select pg_temp.last(706, 2, 'skipped', 'insufficient_verified_course_facts', jsonb_build_object('prompt_version', 'cdesc-source-grounded-v1'));
select pg_temp.last(707, 2, 'skipped', 'the page does not state it', jsonb_build_object('reader', jsonb_build_object('model', 'm', 'prompt', 'course-text-v2')));
select pg_temp.expect('REGRESSION re-read: a reading course-text-v2 made that a check held is read again', pg_temp.picked(701));
select pg_temp.expect('REGRESSION re-read: a reading superseded in Layer 4 is read again', pg_temp.picked(704));
select pg_temp.expect('REGRESSION re-read: a reading course-text-v1 made that waits behind the provider places is read again', pg_temp.picked(705));
select pg_temp.expect('not re-read: a reading the released prompt made and a check held waits for the usual recheck days', not pg_temp.picked(702));
select pg_temp.expect('not re-read: a description a person rejected in Layer 4 is never read again on a prompt change', not pg_temp.picked(703));
select pg_temp.expect('not re-read: insufficient_verified_course_facts under the released prompt waits for the recheck days', not pg_temp.picked(706));
select pg_temp.expect('not re-read: a page that did not state it waits for the recheck days (not a hold)', not pg_temp.picked(707));
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(701), 'description', 'value');
select pg_temp.expect('not re-read: a locked course is never read again', not pg_temp.picked(701));

-- ---- 4. supersede the waiting descriptions an earlier prompt made that the machine declined for good ------------------------------------------------------------------------
select pg_temp.mk(n, 3) from generate_series(901, 906) n;
select pg_temp.decline(901);                                      -- course-text-v2, declined for good now: superseded
select pg_temp.decline(902, true);                                -- a transient decline: stays
select pg_temp.decline(903, false, 'an-older-policy-stamp');      -- declined under an older policy: stays until the machine looks again
-- 904: no decline (the machine has not decided): stays
update pipeline.layer4_review_items set layer3_state = layer3_state || '{"prompt": "cdesc-source-grounded-v1"}' where id = pg_temp.rid(905);
select pg_temp.decline(905);                                      -- made by the released prompt: a genuine exception, stays for a person
select pg_temp.decline(906);
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(906), 'description', 'value');  -- locked: stays
create temporary table cdsg_run as select security.cdesc_prompt_supersede_v1() r;
select pg_temp.expect('supersede: one run supersedes exactly the one qualifying item', (select (r->>'superseded')::int = 1 from cdsg_run));
select pg_temp.expect('REGRESSION supersede: a course-text-v2 description declined for good is superseded', pg_temp.status(901) = 'superseded');
select pg_temp.expect('supersede: recorded as decided_before in layer4_supersessions with both prompt versions',
  exists (select 1 from pipeline.layer4_supersessions s where s.item_id = pg_temp.rid(901) and s.reason = 'decided_before' and s.mode = 'reconcile'
            and s.evidence->>'prompt_before' = 'course-text-v2' and s.evidence->>'prompt_after' = 'cdesc-source-grounded-v1'));
select pg_temp.expect('supersede: its reading is marked to be read again and is picked by the gap queue',
  pg_temp.rreason(901) like 'superseded:%cdesc-source-grounded-v1' and pg_temp.picked(901));
select pg_temp.expect('kept: a transient decline is not superseded', pg_temp.status(902) = 'pending');
select pg_temp.expect('kept: a decline under an older policy is not superseded (the machine looks again first)', pg_temp.status(903) = 'pending');
select pg_temp.expect('kept: a description the machine has not decided is not superseded', pg_temp.status(904) = 'pending');
select pg_temp.expect('kept: a description the released prompt made waits for a person', pg_temp.status(905) = 'pending');
select pg_temp.expect('kept: a locked course is not superseded', pg_temp.status(906) = 'pending');
select pg_temp.expect('kept: no description is written by superseding', (select count(*) from catalogue.courses where id in (select pg_temp.cid(n) from generate_series(901, 906) n) and nullif(btrim(description), '') is not null) = 0);
create temporary table cdsg_run2 as select security.cdesc_prompt_supersede_v1() r;
select pg_temp.expect('supersede: a second run changes nothing', (select (r->>'superseded')::int = 0 from cdsg_run2));
-- the batch: two more qualifying items, a batch of one
select pg_temp.mk(n, 4) from generate_series(907, 908) n;
select pg_temp.decline(907); select pg_temp.decline(908);
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, unit, used_by) values ('pipeline', 'layer4.reconcile_batch', 'x', 'number', '200'::jsonb, 'items', 'x') on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'layer4.reconcile_batch';
create temporary table cdsg_one as select security.cdesc_prompt_supersede_v1() r;
select pg_temp.expect('setting: layer4.reconcile_batch 1 supersedes one item a run',
  (select (r->>'superseded')::int = 1 from cdsg_one) and (select count(*) from pipeline.layer4_review_items where id in (pg_temp.rid(907), pg_temp.rid(908)) and status = 'pending') = 1);
update pipeline.platform_toolset_settings set value = '200'::jsonb where toolset_key = 'pipeline' and key = 'layer4.reconcile_batch';
-- the job: the prompt step runs first; the machine then looks again at the decline under the older policy (903), and once it declines it for good under the current policy the next run supersedes it
create temporary table cdsg_job as select security.course_description_machine_run_v1() r;
select pg_temp.expect('REGRESSION job: course-description-machine reports the prompt step first', (select r ? 'prompt' and (r->'prompt') ? 'superseded' from cdsg_job));

do $$ begin
  if exists (select 1 from g_t where not ok) then raise notice 'cdsg: % FAIL', (select count(*) from g_t where not ok); else raise notice 'cdsg: all % pass', (select count(*) from g_t); end if;
end $$;
