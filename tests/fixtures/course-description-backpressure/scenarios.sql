-- Guards (setup copied from ../course-description-promote-held): "No unauthorised Layer 4 admission" (Platform Admin P0 mandate 3 Nov 2026 10:44 section 7) and the held_first_admission promise (a provider's
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


-- providers: P1 (3 waiting, 2 held), P2 (2 waiting), P3 (four waiting items that cannot be approved as read), all AU
update pipeline.platform_toolset_settings set value = '100000'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_review_first';
insert into pim.entity_registry(id, stable_key) values ('00000000-0000-4000-b000-000000000001', 'g-cd-p1'), ('00000000-0000-4000-b000-000000000002', 'g-cd-p2'), ('00000000-0000-4000-b000-000000000003', 'g-cd-p3');
insert into catalogue.providers(id, stable_key, canonical_name, country_id) values
  ('00000000-0000-4000-b000-000000000001', 'g-cd-p1', 'Pack University One', (select id from ref.countries where iso_alpha2 = 'AU')),
  ('00000000-0000-4000-b000-000000000002', 'g-cd-p2', 'Pack University Two', (select id from ref.countries where iso_alpha2 = 'AU')),
  ('00000000-0000-4000-b000-000000000003', 'g-cd-p3', 'Pack University Three', (select id from ref.countries where iso_alpha2 = 'AU'));
insert into pipeline.admin_jobs(id) values ('00000000-0000-4000-b000-0000000000f1');
-- P1: 1-3 wait (1 clean, 2 will carry a claim word, 3 a price), 4-5 held.  P2: 11-12 wait (12 gets the words of 11).  P3: 21 inactive, 22 described another way, 23 page changed, 24 locked
-- 31: an ordinary gap with a readable stored page (for the back-pressure checks)
create temporary table g_courses(n int primary key, prov int);
insert into g_courses values (1,1),(2,1),(3,1),(4,1),(5,1),(11,2),(12,2),(21,3),(22,3),(23,3),(24,3),(31,2);
insert into pim.entity_registry(id, stable_key) select pg_temp.cid(n), 'g-cd-c' || n from g_courses;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title)
select pg_temp.cid(n), 'g-cd-c' || n, ('00000000-0000-4000-b000-00000000000' || prov)::uuid, 'Pack Course ' || n from g_courses;
insert into pipeline.evidence_artifacts(id, evidence_type) select pg_temp.eid(n), 'page' from generate_series(1, 80) n;
insert into pipeline.coverage_course_pages(course_id, provider_id, status, identity_basis, url, evidence_id)
select c.id, c.provider_id, 'bound', 'course_title_on_page', 'https://example.test/course/' || right(c.stable_key, 2),
       pg_temp.eid(case when c.id = pg_temp.cid(23) then 70 else regexp_replace(c.stable_key, '\D', '', 'g')::int end)
  from catalogue.courses c where c.stable_key like 'g-cd-c%';
update pipeline.coverage_course_pages set read_status = 'read', read_at = now() - interval '1 day' where course_id = pg_temp.cid(31);
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(24), 'description', 'value');

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
create function pg_temp.held(n int, reading jsonb) returns void language sql as $$
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, evidence_id, reason)
  select '00000000-0000-4000-b000-0000000000f1', c.provider_id, c.id, 'description', 'skipped', 'ai_stored',
         reading || jsonb_build_object('text', (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(reading->'sentences') with ordinality e(x, o))),
         pg_temp.eid(n), 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved'
    from catalogue.courses c where c.id = pg_temp.cid(n) $$;
select pg_temp.waiting(n) from unnest(array[1, 2, 3, 11, 12, 21, 22, 23, 24]) n;
select pg_temp.held(n, pg_temp.good(n)) from unnest(array[4, 5]) n;
-- 2 carries a claim word, 3 a price, 12 has exactly the words of 11 (wording shared with another course of the same university)
update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('description', (proposed_value->>'description') || ' The programme is ranked highly.') where id = pg_temp.rid(2);
update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('description', (proposed_value->>'description') || ' Fees are $9,000 a year.') where id = pg_temp.rid(3);
update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('description', (select proposed_value->>'description' from pipeline.layer4_review_items where id = pg_temp.rid(11))) where id = pg_temp.rid(12);
-- 1 is clean (the sample sentence of the fixture mentions teaching staff, a claim word the quote supports)
update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('description', 'Pack Course 1 covers modules in accounting and finance across the first two years.') where id = pg_temp.rid(1);
-- the P3 cases: 21's course is archived, 22 was described another way, 23's page is a different stored copy (set above), 24 is locked (set above)
update catalogue.courses set lifecycle_status = 'archived' where id = pg_temp.cid(21);
update catalogue.courses set description = 'A description that arrived another way and already stands on the site for this course.' where id = pg_temp.cid(22);

create function pg_temp.pending() returns int language sql as $$ select count(*)::int from pipeline.layer4_review_items where field_code = 'course_description_first_read' and status = 'pending' $$;

-- 0. the shipped state: both new switches are off, with a label, a range, a unit and a used_by line (G2)
select pg_temp.expect('settings: back-pressure ships 0 (off), range 0 to 20000, with label, unit and used_by',
  (select value = '0'::jsonb and min_value = 0 and max_value = 20000 and unit = 'descriptions' and label <> '' and used_by like '%enrich_course_text_gaps_v1%' from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_global_max'));
select pg_temp.expect('settings: stale-retire switch ships 0 (off), on/off',
  (select value = '0'::jsonb and min_value = 0 and max_value = 1 and unit = 'on/off' and used_by like '%retire_stale%' from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'enrich.course_description_stale_supersede_on'));
select pg_temp.expect('the job is catalogued (G1) and scheduled with no number in its command',
  exists (select 1 from pipeline.automation_catalogue where jobname = 'course-description-stale-retire')
  and (select command !~ '(^|[^a-z0-9_])[0-9]' from cron.job where jobname = 'course-description-stale-retire'));
select pg_temp.expect('start: 9 waiting, nothing decided', pg_temp.pending() = 9 and (select count(*) from pipeline.layer4_review_items where status <> 'pending') = 0);

-- 1. capacity: counts, the measured pace of the stub (2 minutes), hours and items a day
create temporary table g_cap as select security.course_description_capacity_v1() c;
select pg_temp.expect('capacity: pending 9, ready 5 (the four P3 items are not ready), held first readings 2',
  (select (c->>'pending')::int = 9 and (c->>'ready')::int = 5 and (c->>'not_ready')::int = 4 and (c->>'held_first_readings_behind_the_provider_cap')::int = 2
          and (c->>'would_wait_for_a_person_after_the_cap_frees')::int = 11 from g_cap));
select pg_temp.expect('capacity: minutes an item come from the measured Layer 4 pace; hours and items a day follow',
  (select (c->>'minutes_an_item')::numeric = 2 and c->>'pace_basis' = 'measured' and (c->>'hours_to_clear_waiting')::numeric = 0.3
          and (c->>'target_days')::numeric = 7 and (c->>'items_a_day_to_clear_waiting_in_target')::int = 2 from g_cap));
select pg_temp.expect('capacity: nothing decided yet, so no days to clear is claimed', (select (c->>'decided_in_window')::int = 0 and c->'days_to_clear_at_current_decisions' = 'null'::jsonb from g_cap));
select pg_temp.expect('capacity: back-pressure off', (select (c->'back_pressure'->>'on')::boolean = false and (c->'back_pressure'->>'new_readings_paused')::boolean = false from g_cap));

-- 2. the pack: universities that free the most held readings first; clean items first within a university; objective flags; only ready items
create temporary table g_pack as select security.course_description_pack_v1(null, 0) p;
select pg_temp.expect('pack: only the 5 ready items, none of the stale ones', (select (p->>'total')::int = 5 and jsonb_array_length(p->'items') = 5 from g_pack));
select pg_temp.expect('pack: University One first (its decision can free 2 held readings), then University Two',
  (select p->'items'->0->>'provider' = 'Pack University One' and p->'items'->2->>'provider' = 'Pack University One' and p->'items'->3->>'provider' = 'Pack University Two' from g_pack));
select pg_temp.expect('pack: within University One the item with no flag comes first',
  (select p->'items'->0->>'ref' = pg_temp.rid(1)::text and jsonb_array_length(p->'items'->0->'detail'->'pack'->'flags') = 0 from g_pack));
select pg_temp.expect('pack: claim word and price flagged, as flags only',
  (select p->'items'->1->'detail'->'pack'->'flags' ? 'claim_word' and p->'items'->2->'detail'->'pack'->'flags' ? 'money_or_year' from g_pack));
select pg_temp.expect('pack: shared wording flagged on both courses that share it',
  (select (select count(*) from jsonb_array_elements(p->'items') i where i->'detail'->'pack'->'flags' ? 'same_words_elsewhere') = 2 from g_pack));
select pg_temp.expect('pack: the unlock count and the item shape the Inbox renders are present',
  (select (p->'items'->0->'detail'->'pack'->>'held_readings_this_decision_can_free')::int = 2 and p->'items'->0->>'kind' = 'provider_description' and p->'items'->0->'detail'->'proposed' ? 'description'
          and p->'items'->0->'detail'->>'field_code' = 'course_description_first_read' from g_pack));
select pg_temp.expect('pack: one university on its own', (select (security.course_description_pack_v1('00000000-0000-4000-b000-000000000002', 0)->>'total')::int = 2));

-- 3. the Admin entry point: rank gate, the two new actions, the old ones kept
set g.uid = '00000000-0000-4000-b000-0000000000aa';
set g.rank = '3';
do $$ begin
  begin perform public.admin_course_description_queue('capacity', '{}'::jsonb); raise exception 'rank 3 was allowed'; exception when insufficient_privilege then null; end;
end $$;
set g.rank = '4';
select pg_temp.expect('entry point: Pipeline Operator reads capacity and pack; summary is still served',
  (public.admin_course_description_queue('capacity')->>'pending')::int = 9 and (public.admin_course_description_queue('pack')->>'total')::int = 5
  and (public.admin_course_description_queue('summary')->>'pending')::int = 9);
do $$ begin
  begin perform public.admin_course_description_queue('approve_everything', '{}'::jsonb); raise exception 'an unknown action was allowed'; exception when invalid_parameter_value then null; end;
end $$;
select pg_temp.expect('entry point: rank gate and unknown action refused', true);
set g.rank = '0';

-- 4. back-pressure in the standing gap queue
select pg_temp.expect('gaps: with the switch off the ordinary gap (31) is queued for a description', (select count(*) from security.enrich_course_text_gaps_v1(array['description']) g where g.course_id = pg_temp.cid(31)) = 1);
update pipeline.platform_toolset_settings set value = to_jsonb(pg_temp.pending()) where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_global_max';
select pg_temp.expect('gaps: as many waiting as the limit, so no new description reading is queued', (select count(*) from security.enrich_course_text_gaps_v1(array['description']) g) = 0);
select pg_temp.expect('gaps: the deadline field is not held back by it', (select count(*) from security.enrich_course_text_gaps_v1(array['deadline']) g where g.course_id = pg_temp.cid(31)) = 1);
select pg_temp.expect('capacity: reports the pause', (security.course_description_capacity_v1()->'back_pressure'->>'new_readings_paused')::boolean);
update pipeline.platform_toolset_settings set value = to_jsonb(pg_temp.pending() + 1) where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_global_max';
select pg_temp.expect('gaps: room below the limit, queueing resumes', (select count(*) from security.enrich_course_text_gaps_v1(array['description']) g where g.course_id = pg_temp.cid(31)) = 1);
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_global_max';

-- 5. retire proposals that can no longer be approved: off counts only; on supersedes the archived and the described-another-way, never the page-changed or locked
create temporary table g_off as select security.course_description_retire_stale_v1() r;
select pg_temp.expect('retire off: counts the 2 it could settle and settles none', (select (r->>'on')::boolean = false and (r->>'examined')::int = 2 and (r->>'superseded')::int = 0 from g_off) and pg_temp.pending() = 9);
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_stale_supersede_on';
create temporary table g_on as select security.course_description_retire_stale_v1() r;
select pg_temp.expect('retire on: supersedes the archived (21) and the already-described (22) proposals', (select (r->>'superseded')::int = 2 from g_on)
  and (select status from pipeline.layer4_review_items where id = pg_temp.rid(21)) = 'superseded' and (select status from pipeline.layer4_review_items where id = pg_temp.rid(22)) = 'superseded');
select pg_temp.expect('retire on: the reasons are recorded in the supersession log, no approval or rejection exists',
  (select count(*) from pipeline.layer4_supersessions where reason = 'entity_retired' and entity_id = pg_temp.cid(21)) = 1
  and (select count(*) from pipeline.layer4_supersessions where reason = 'covered_by_active' and entity_id = pg_temp.cid(22)) = 1
  and (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) = 0);
select pg_temp.expect('retire on: page-changed (23) and locked (24) stay with a person', (select count(*) from pipeline.layer4_review_items where id in (pg_temp.rid(23), pg_temp.rid(24)) and status = 'pending') = 2);
select pg_temp.expect('retire on: the settled readings follow the existing trigger (skipped, not admitted)',
  (select count(*) from pipeline.field_enrich_items where course_id in (pg_temp.cid(21), pg_temp.cid(22)) and state = 'skipped' and reason like 'not admitted in Layer 4 (superseded)%') = 2);
select pg_temp.expect('retire on: no catalogue description was written', (select count(*) from catalogue.courses where nullif(btrim(description), '') is not null) = 1);
select pg_temp.expect('retire on: a second run settles nothing more', (security.course_description_retire_stale_v1()->>'superseded')::int = 0);
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_stale_supersede_on';

-- 6. access
select pg_temp.expect('the three new functions can be called by nobody but the owner',
  not has_function_privilege('authenticated', 'security.course_description_capacity_v1()', 'execute') and not has_function_privilege('anon', 'security.course_description_capacity_v1()', 'execute')
  and not has_function_privilege('authenticated', 'security.course_description_pack_v1(uuid,integer)', 'execute') and not has_function_privilege('anon', 'security.course_description_pack_v1(uuid,integer)', 'execute')
  and not has_function_privilege('authenticated', 'security.course_description_retire_stale_v1()', 'execute') and not has_function_privilege('anon', 'security.course_description_retire_stale_v1()', 'execute'));
select pg_temp.expect('review_first untouched and nothing admitted by any of it', (select value = '100000'::jsonb from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'enrich.course_description_review_first'));

do $$ declare v_bad int; begin
  select count(*) into v_bad from g_t where not ok;
  if v_bad > 0 then raise exception '% cdesc check(s) failed', v_bad; end if;
  raise notice 'cdesc: all % checks passed', (select count(*) from g_t);
end $$;
