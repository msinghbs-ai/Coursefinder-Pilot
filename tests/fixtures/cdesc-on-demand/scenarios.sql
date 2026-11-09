-- Scenarios for Fill / Recheck description on demand (migration 20261110070000). Every check prints PASS or FAIL; run.sh fails on any FAIL or ERROR.
\set ON_ERROR_STOP 1
create schema if not exists g;
create or replace function g.ok(p_name text, p_cond boolean) returns void language plpgsql as $$ begin
  if coalesce(p_cond, false) then raise notice 'PASS %', p_name; else raise notice 'FAIL %', p_name; end if; end $$;
create or replace function g.as_user(p_rank int) returns void language sql as $$ select set_config('g.uid', '99999999-0000-4000-8000-000000000001', false), set_config('g.rank', p_rank::text, false) $$;
create or replace function g.fails(p_sql text, p_like text) returns boolean language plpgsql as $$ begin execute p_sql; return false; exception when others then return sqlerrm like p_like; end $$;
create or replace function g.cid(n int) returns uuid language sql immutable as $$ select ('c0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function g.eid(n int) returns uuid language sql immutable as $$ select ('e0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function g.pid(n int) returns uuid language sql immutable as $$ select ('a0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;

-- seed (triggers that production runs on provider and course inserts are not part of what is tested here) -------------------------------------------------------
set session_replication_role = replica;
insert into pim.entity_registry(id, stable_key) select g.pid(n), 'prov-' || n from generate_series(1, 4) n;
insert into catalogue.providers(id, stable_key, canonical_name, display_name, country_id, lifecycle_status)
select g.pid(n), 'prov-' || n, 'Provider ' || n, 'Provider ' || n, (select id from ref.countries where iso_alpha2 = case when n = 2 then 'NZ' else 'AU' end), 'active' from generate_series(1, 4) n;  -- 1 AU, 2 NZ, 3 AU hidden, 4 AU (scope of the capacity scenario)
insert into pipeline.g_hidden_providers values (g.pid(3));
insert into pim.entity_registry(id, stable_key) select g.cid(n), 'course-' || n from generate_series(1, 60) n;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, description, lifecycle_status)
select g.cid(n), 'course-' || n,
       case when n = 9 then g.pid(3) when n = 19 then g.pid(2) when n between 40 and 49 then g.pid(4) else g.pid(1) end,
       'Course ' || n, case when n in (10, 31, 32, 33, 34) then 'An existing description of course ' || n || ', held by a person or an earlier route, long enough to be real.' end,
       case when n = 16 then 'retired' else 'active' end from generate_series(1, 60) n;
insert into pipeline.evidence_artifacts(id, evidence_type) select g.eid(n), 'course_page_html' from generate_series(1, 60) n;
insert into pipeline.evidence_artifacts(id, evidence_type) values (g.eid(70), 'course_page_html'), (g.eid(71), 'course_page_html');
-- the stored page of each course: bound, read, proved (the standing queue's rule), except where the scenario says otherwise
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis, evidence_id, read_at, bound_at, next_read_at)
select g.cid(n), (select provider_id from catalogue.courses where id = g.cid(n)), 'https://example.edu.au/course/' || n, 'bound', 'read', 'exact_title', g.eid(n), now() - interval '90 days', now() - interval '90 days', null
  from generate_series(1, 60) n where n not in (6, 7, 17, 19, 20);
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis, evidence_id, read_at, bound_at)
values (g.cid(7), g.pid(1), 'https://example.edu.au/course/7', 'mismatch', 'read', 'exact_title', g.eid(7), now() - interval '90 days', now() - interval '90 days'),
       (g.cid(17), g.pid(1), 'https://example.edu.au/course/17', 'bound', 'read', 'exact_title', null, now() - interval '90 days', now() - interval '90 days'),
       (g.cid(19), g.pid(2), 'https://example.edu.nz/course/19', 'bound', 'read', 'cricos_code', g.eid(19), now() - interval '90 days', now() - interval '90 days'),
       (g.cid(20), g.pid(1), 'https://example.edu.au/course/20', 'bound', 'read', 'exact_title', g.eid(20), now() - interval '1 day', now() - interval '90 days');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', g.cid(8), 'description', 'value');
-- history: one finished task, items made 30 or more days ago (so today's count starts at zero)
insert into pipeline.admin_jobs(id, kind, lane, state, title, args, requested_by, reason) values ('b0000000-0000-4000-8000-000000000001', 'enrich_fields', 'enrich', 'done', 'history', '{}', '99999999-0000-4000-8000-000000000001', 'history');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, reason, evidence_id, created_at, updated_at)
select 'b0000000-0000-4000-8000-000000000001', p.provider_id, g.cid(h.n), 'description', h.st, h.rs, p.evidence_id, now() - (h.age || ' days')::interval, now() - (h.age || ' days')::interval
  from (values (2, 'skipped', 'held: length: 31 characters, outside the set range (held whole, never cut)', 10), (3, 'skipped', 'held: sentence_count: 6 sentence(s), outside the set range', 70),
               (4, 'failed', 'no answer could be recorded after 3 tries', 10), (5, 'skipped', 'the page does not state it', 10),
               (11, 'review', null, 10), (12, 'ai', null, 1), (13, 'skipped', 'held: unsupported_claim: a ranking claim', 10), (14, 'skipped', 'the page does not state it', 10),
               (15, 'skipped', 'held: unsupported_claim: an outcome claim', 10), (18, 'skipped', 'held_first_admission: the provider''s first descriptions wait in Layer 4', 10),
               (20, 'skipped', 'held: length: 12 characters, outside the set range (held whole, never cut)', 10), (21, 'skipped', 'held: length: 10 characters, outside the set range', 10),
               (22, 'skipped', 'held: length: 10 characters, outside the set range', 20), (23, 'skipped', 'held: length: 10 characters, outside the set range', 70),
               (24, 'skipped', 'held: length: 10 characters, outside the set range', 15), (25, 'skipped', 'held: unsupported_claim: x', 10)) h(n, st, rs, age)
  join pipeline.coverage_course_pages p on p.course_id = g.cid(h.n);
-- Layer 4: course 11 waits; 13 was rejected on the page copy it still has; 26 was rejected on an older copy; 31 was approved by a person
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, status) values
  ('course', g.cid(11), 'course_description_first_read', g.eid(11), 'pending'), ('course', g.cid(13), 'course_description_first_read', g.eid(13), 'rejected'),
  ('course', g.cid(26), 'course_description_first_read', g.eid(70), 'rejected'), ('course', g.cid(31), 'course_description_first_read', g.eid(31), 'approved');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, reason, evidence_id, created_at, updated_at)
select 'b0000000-0000-4000-8000-000000000001', g.pid(1), g.cid(26), 'description', 'skipped', 'held: unsupported_claim: x', g.eid(26), now() - interval '10 days', now() - interval '10 days';
-- 5 and 14: the same page copy was read and did not state it (the item carries the evidence); 14 also has a raised flag
set session_replication_role = origin;
select security.flag_raise_v1('course', g.cid(14)::text, g.pid(1), 'description', 'enrich_no_value', 'Enrich fields: the page does not state it', 'hard', 'enrich-fields', 'auto', '{}', g.eid(14)::text, null);
select security.flag_raise_v1('course', g.cid(15)::text, g.pid(1), 'description', 'enrich_no_value', 'Enrich fields: the page does not state it', 'soft', 'enrich-fields', 'auto', '{}', g.eid(15)::text, null);
select security.flag_raise_v1('course', g.cid(25)::text, g.pid(1), 'description', 'enrich_no_value', 'Enrich fields: the page does not state it', 'soft', 'enrich-fields', 'auto', '{}', g.eid(25)::text, null);
-- 4: an ENTITY-level counting flag (field '') as well: the engine's own gate holds a description item for it too, so a Recheck must release it
select security.flag_raise_v1('course', g.cid(4)::text, g.pid(1), '', 'enrich_no_value', 'Enrich fields: nothing found for this course', 'soft', 'enrich-fields', 'auto', '{}', g.eid(4)::text, null);
select security.flag_raise_v1('course', g.cid(27)::text, g.pid(1), 'description', 'manual_hold', 'held by a person', 'hard', 'person', 'person', '{}', null, null);
-- the cases of the other descriptions: published, with feed rows
insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, course_stable_key)
select g.cid(n), (select provider_id from catalogue.courses where id = g.cid(n)), (select p.country_id from catalogue.courses c join catalogue.providers p on p.id = c.provider_id where c.id = g.cid(n)), 'P', 'C', 'x', to_tsvector('x'), 'published', 'sk-' || n
  from generate_series(1, 60) n where n in (10, 31, 32, 34, 19);
insert into pipeline.zoho_sync_items(entity, item_key, ref_id, item) values ('course', 'sk-10', g.cid(10), '{"name":"x"}'), ('course', 'sk-31', g.cid(31), '{"description":"An existing description of course 31, held by a person or an earlier route, long enough to be real."}'),
  ('course', 'sk-32', g.cid(32), '{"description":"other words"}');
select g.as_user(4);

-- 1. the state of each course: headline, why Fill and Recheck leave it out ---------------------------------------------------------------------------------------------
create temp table st as select * from security.cdesc_state_v1(array(select g.cid(n) from generate_series(1, 60) n), null);
select g.ok('state: every seeded course is described', (select count(*) from st) = 60);
select g.ok('state c01 never tried: source_ready, Fill ok, Recheck nothing_to_recheck', (select state = 'source_ready' and fill_block is null and recheck_block = 'nothing_to_recheck' and last_item_id is null and next_retry_at is null and source_url = 'https://example.edu.au/course/1' and evidence_id = g.eid(1) from st where course_id = g.cid(1)));
select g.ok('state c02 held 10 days ago: held, Fill waits (recent_attempt), Recheck ok, next retry = last attempt + 60 days', (select state = 'held' and fill_block = 'recent_attempt' and recheck_block is null and next_retry_at between last_attempt_at + interval '59 days 23 hours' and last_attempt_at + interval '60 days 1 hour' from st where course_id = g.cid(2)));
select g.ok('state c03 held 70 days ago: Fill ok (older than gaps.recheck_days) and Recheck ok', (select state = 'held' and fill_block is null and recheck_block is null from st where course_id = g.cid(3)));
select g.ok('state c04 failed 10 days ago: failed, Fill waits, Recheck ok', (select state = 'failed' and fill_block = 'recent_attempt' and recheck_block is null from st where course_id = g.cid(4)));
select g.ok('state c05 same page copy did not state it: not_stated, both leave it out', (select state = 'not_stated' and fill_block = 'same_page_not_stated' and recheck_block = 'same_page_not_stated' from st where course_id = g.cid(5)));
select g.ok('state c06 no stored page: missing, no_source/no_page', (select state = 'missing' and fill_block = 'no_source' and recheck_block = 'no_source' and source_reason = 'no_page' and not source_ready from st where course_id = g.cid(6)));
select g.ok('state c07 page mismatch: no_source/page_mismatch', (select fill_block = 'no_source' and source_reason = 'page_mismatch' from st where course_id = g.cid(7)));
select g.ok('state c08 locked by hand: locked in both modes', (select state = 'locked' and fill_block = 'locked' and recheck_block = 'locked' and locked from st where course_id = g.cid(8)));
select g.ok('state c09 unpublished university: provider_hidden in both modes', (select fill_block = 'provider_hidden' and recheck_block = 'provider_hidden' and hidden from st where course_id = g.cid(9)));
select g.ok('state c10 already described (source unknown): present, nothing to fill', (select state = 'present' and has_description and fill_block = 'already_has_description' and machine_admitted is null from st where course_id = g.cid(10)));
select g.ok('state c11 reading waits in Layer 4: ai_read, waiting_for_person', (select state = 'ai_read' and fill_block = 'waiting_for_person' and recheck_block = 'waiting_for_person' from st where course_id = g.cid(11)));
select g.ok('state c12 item in flight: queued, in_flight', (select state = 'queued' and fill_block = 'in_flight' and recheck_block = 'in_flight' from st where course_id = g.cid(12)));
select g.ok('state c13 rejected on the same page copy: rejected_same_evidence in both modes', (select fill_block = 'rejected_same_evidence' and recheck_block = 'rejected_same_evidence' from st where course_id = g.cid(13)));
select g.ok('state c14 raised flag: held_for_person in both modes, held_kind raised', (select fill_block = 'held_for_person' and recheck_block in ('held_for_person', 'same_page_not_stated') and held_kind = 'raised' from st where course_id = g.cid(14)));
select g.ok('state c15 counting flag within 60 days: Fill waits, Recheck ok, one flag to release', (select fill_block = 'recent_attempt' and recheck_block is null and held_kind = 'counting' and cardinality(release_flag_ids) = 1 from st where course_id = g.cid(15)));
select g.ok('state c16 retired course: not_active', (select state = 'inactive' and fill_block = 'not_active' from st where course_id = g.cid(16)));
select g.ok('state c17 page read but no evidence: no_source/no_evidence', (select fill_block = 'no_source' and source_reason = 'no_evidence' from st where course_id = g.cid(17)));
select g.ok('state c18 first-admission hold: held_first_admission in both modes', (select state = 'held' and fill_block = 'held_first_admission' and recheck_block = 'held_first_admission' and held_kind = 'held_first_admission' from st where course_id = g.cid(18)));
select g.ok('state c19 NZ course proved only by a CRICOS code: no_source/identity_not_admitted', (select fill_block = 'no_source' and source_reason = 'identity_not_admitted' from st where course_id = g.cid(19)));
select g.ok('state c20 page read again after the last attempt: Fill ok although the attempt is recent, next retry due now', (select fill_block is null and recheck_block is null and next_retry_at is null from st where course_id = g.cid(20)));
select g.ok('state c26 rejected on an OLDER page copy: not blocked by the rejection', (select fill_block = 'recent_attempt' and recheck_block is null from st where course_id = g.cid(26)));
select g.ok('state c27 manual hold flag: held_for_person, held_kind manual_hold', (select held_kind = 'manual_hold' and fill_block = 'held_for_person' from st where course_id = g.cid(27)));
select g.ok('state c31 approved by a person in Layer 4: human_decision', (select state = 'human_decision' from st where course_id = g.cid(31)));

-- 2. the standing gap queue and Fill agree: Fill never reaches a course the queue would not, and every difference has a named, narrower reason ---------------------------------
create temp table gap as select course_id from security.enrich_course_text_gaps_v1(array['description']);
select g.ok('parity: every course Fill would queue is a course the standing queue would queue', not exists (select 1 from st s where s.fill_block is null and s.course_id not in (select course_id from gap)));
select g.ok('parity: a course the queue would queue but Fill leaves out has a narrower named reason',
  not exists (select 1 from st s where s.course_id in (select course_id from gap) and s.fill_block is not null
                and s.fill_block not in ('same_page_not_stated', 'rejected_same_evidence', 'held_first_admission', 'no_source', 'held_for_person')));

-- 3. preview -----------------------------------------------------------------------------------------------------------------------------------------------------------
create temp table pv as select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1), g.cid(2), g.cid(3), g.cid(6), g.cid(8), g.cid(20), g.cid(99)))) j;
select g.ok('preview fill: totals, queue, blocked reasons and the unknown id', (select (j->>'total')::int = 6 and (j->>'eligible')::int = 3 and (j->>'to_queue')::int = 3 and j->'blocked' = '{"locked": 1, "no_source": 1, "recent_attempt": 1}'::jsonb
   and j->'missing' = to_jsonb(array[g.cid(99)]) from pv));
select g.ok('preview fill: estimate and limits come from existing settings', (select (j->'limit'->>'courses_per_request')::int = 20 and (j->'limit'->>'items_per_day')::int = 500 and (j->'estimate'->>'usd_per_item')::numeric = 0.0031 and (j->'estimate'->>'usd')::numeric = 0.0093 and (j->'estimate'->>'scraper_credits')::int = 0 from pv));
select g.ok('preview rows carry the plain-words reason and next action of the blocked courses', (select count(*) = 6 and count(*) filter (where r->>'block' is not null) = 3 and bool_and((r->>'block' is null) or (r->'block_info'->>'label') is not null and (r->'block_info'->>'next') is not null) from pv, jsonb_array_elements(j->'courses') r));
select g.ok('preview refuses more courses than run_now.pilot_cap', g.fails($$select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', (select jsonb_agg(g.cid(n)) from generate_series(1, 21) n)))$$, '%at most 20 courses%'));
select g.ok('preview refuses no mode, both scopes, no scope', g.fails($$select public.admin_enrich_fields('preview', jsonb_build_object('course_ids', jsonb_build_array(g.cid(1))))$$, '%choose Fill description or Recheck description%')
  and g.fails($$select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1)), 'provider_ids', jsonb_build_array(g.pid(1))))$$, '%not both%')
  and g.fails($$select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill'))$$, '%choose up to 20 courses, or one university%')
  and g.fails($$select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'provider_ids', jsonb_build_array(g.pid(1), g.pid(4))))$$, '%choose up to 20 courses, or one university%'));
select g.ok('preview recheck: Recheck takes the held, failed and counting-flag courses, not the never-tried', (select (j->>'eligible')::int from (select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'recheck', 'course_ids', jsonb_build_array(g.cid(1), g.cid(2), g.cid(4), g.cid(15), g.cid(5), g.cid(13)))) j) z) = 3);
select g.as_user(2);
select g.ok('preview needs rank 3 (Curator)', g.fails($$select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1))))$$, '%Curator role or above required%'));
select g.as_user(3);
select g.ok('rank 3 can preview but not start', (select (public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1))))->>'eligible')::int = 1)
  and g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1)), 'reason', 'a good reason'))$$, '%Pipeline Operator role or above required%'));
select g.as_user(4);

-- 4. start fill: an ordinary Enrich fields task -------------------------------------------------------------------------------------------------------------------------
select g.ok('start refuses a missing or short reason', g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1)), 'reason', 'no'))$$, '%give a reason%'));
select g.ok('start with nothing eligible refuses and says why, and makes no task', g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(2), g.cid(8)), 'reason', 'try these'))$$, '%nothing to queue: %Locked by hand (1)%')
  and (select count(*) from pipeline.admin_jobs where args->>'on_demand' = 'true') = 0);
create temp table s1 as select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1), g.cid(3), g.cid(20), g.cid(2)), 'reason', 'Fill the first three for the Platform Admin check', 'idempotency_key', 'k-001')) j;
select g.ok('start fill: returns the task, 3 items, not a repeat', (select (j->>'items')::int = 3 and (j->>'repeat')::boolean = false and j->'blocked' = '{"recent_attempt": 1}'::jsonb from s1));
select g.ok('start fill: the task is an ordinary enrich_fields task in the enrich lane, queued, with a reason, scope and on-demand arguments',
  (select kind = 'enrich_fields' and lane = 'enrich' and state = 'queued' and reason = 'Fill the first three for the Platform Admin check' and requested_by = '99999999-0000-4000-8000-000000000001'
          and args->'fields' = '["description"]'::jsonb and (args->>'ai')::boolean and not (args->>'scraper')::boolean and args->>'mode' = 'fill' and args->>'on_demand' = 'true'
          and args->>'idempotency_key' = 'k-001' and progress = '{"done": 0, "total": 3}'::jsonb and scope = '3 courses' and title like 'Fill description%'
          from pipeline.admin_jobs where id = (select (j->>'job_id')::uuid from s1)));
select g.ok('start fill: one queued description item per eligible course, none for the held one', (select count(*) = 3 and bool_and(state = 'queued' and field = 'description') and bool_and(course_id in (g.cid(1), g.cid(3), g.cid(20))) from pipeline.field_enrich_items where job_id = (select (j->>'job_id')::uuid from s1)));
select g.ok('start fill: an audit line and a job event carry the reason', (select count(*) = 1 from pipeline.admin_control_events where area = 'enrich_fields' and action = 'on_demand_fill' and detail->>'reason' like 'Fill the first three%')
  and (select count(*) = 1 from pipeline.admin_job_events where job_id = (select (j->>'job_id')::uuid from s1) and note = '3 item(s) to settle'));
select g.ok('start fill: no flag was released by a Fill', (select count(*) = 0 from pipeline.enrichment_flags where state = 'released'));
create temp table s1b as select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1), g.cid(3), g.cid(20), g.cid(2)), 'reason', 'a second click of the same button', 'idempotency_key', 'k-001')) j;
select g.ok('idempotency: the same key returns the same task and adds nothing', (select (b.j->>'job_id') = (a.j->>'job_id') and (b.j->>'repeat')::boolean and (b.j->>'items')::int = 3 from s1 a, s1b b)
  and (select count(*) from pipeline.admin_jobs where args->>'on_demand' = 'true') = 1 and (select count(*) from pipeline.field_enrich_items where field = 'description' and created_at > now() - interval '1 hour') = 3);
select g.ok('the courses are in an open task now: a second Fill finds nothing to queue and says so', g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(g.cid(1), g.cid(3)), 'reason', 'again without a key'))$$, '%nothing to queue: %Already in an open task (2)%'));
create temp table s1c as select public.admin_enrich_fields('start', jsonb_build_object('mode', 'recheck', 'course_ids', jsonb_build_array(g.cid(21), g.cid(22)), 'reason', 'no key given: the key comes from the mode and the courses')) j;
create temp table s1d as select public.admin_enrich_fields('start', jsonb_build_object('mode', 'recheck', 'course_ids', jsonb_build_array(g.cid(22), g.cid(21)), 'reason', 'the same request again while the task is open')) j;
select g.ok('idempotency without a key: the same mode and courses while the task is open return the same task', (select (a.j->>'job_id') = (b.j->>'job_id') and (b.j->>'repeat')::boolean and (a.j->>'items')::int = 2 and (b.j->>'items')::int = 2 from s1c a, s1d b)
  and (select count(*) from pipeline.field_enrich_items where job_id = (select (j->>'job_id')::uuid from s1c)) = 2);

-- 5. start recheck: bypasses the wait, never the guards -----------------------------------------------------------------------------------------------------------------
do $$ declare j uuid := gen_random_uuid(); n int; begin
  insert into pipeline.admin_jobs(id, kind, lane, state, title, requested_by, reason) values (j, 'enrich_fields', 'enrich', 'done', 'control', '99999999-0000-4000-8000-000000000001', 'control');
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) values (j, g.pid(1), g.cid(25), 'description');
  select count(*) into n from pipeline.field_enrich_items where job_id = j;
  perform g.ok('control: without the release the engine''s own gate drops an item for a course on a counting flag', n = 0);
end $$;
create temp table s2 as select public.admin_enrich_fields('start', jsonb_build_object('mode', 'recheck', 'course_ids',
    jsonb_build_array(g.cid(2), g.cid(4), g.cid(15), g.cid(1), g.cid(5), g.cid(8), g.cid(9), g.cid(13), g.cid(14), g.cid(6), g.cid(11), g.cid(12), g.cid(18), g.cid(27)), 'reason', 'Recheck the held, failed and waiting courses')) j;
select g.ok('start recheck: 3 items (held, failed, counting-flag); every guard still holds', (select (j->>'items')::int = 3 from s2)
  and (select count(*) = 3 and bool_and(course_id in (g.cid(2), g.cid(4), g.cid(15))) from pipeline.field_enrich_items where job_id = (select (j->>'job_id')::uuid from s2)));
select g.ok('start recheck: left out for the exact reasons (already queued, same copy, lock, hidden, rejection, raised flag, no page, waiting, in flight, first admission, manual hold)',
  (select j->'blocked' = '{"locked": 1, "no_source": 1, "in_flight": 2, "provider_hidden": 1, "held_for_person": 2, "held_first_admission": 1, "waiting_for_person": 1, "same_page_not_stated": 1, "rejected_same_evidence": 1}'::jsonb from s2));
select g.ok('start recheck: the counting flag of course 15 is released as a person''s release, in the flag history; no other flag is touched',
  (select state = 'released' and release_kind = 'person' and released_by = '99999999-0000-4000-8000-000000000001' and release_reason like 'Recheck description requested:%' from pipeline.enrichment_flags where entity_key = g.cid(15)::text)
  and (select state = 'raised' from pipeline.enrichment_flags where entity_key = g.cid(14)::text) and (select state = 'raised' from pipeline.enrichment_flags where entity_key = g.cid(27)::text)
  and (select state = 'counting' from pipeline.enrichment_flags where entity_key = g.cid(25)::text)
  and (select count(*) = 1 from pipeline.enrichment_flag_events e join pipeline.enrichment_flags f on f.id = e.flag_id where f.entity_key = g.cid(15)::text and e.action = 'released' and e.actor_kind = 'person'));
select g.ok('start recheck: the ENTITY-level counting flag (field empty) of course 4 is released too, so its item got past the engine''s own gate',
  (select state = 'released' and release_kind = 'person' from pipeline.enrichment_flags where entity_key = g.cid(4)::text and field = '') and (select count(*) = 1 from pipeline.field_enrich_items where job_id = (select (j->>'job_id')::uuid from s2) and course_id = g.cid(4)));
select g.ok('start recheck: audit line says recheck and keeps the reason', (select count(*) = 1 from pipeline.admin_control_events where action = 'on_demand_recheck' and detail->>'reason' like 'Recheck the held%'));
select g.ok('recheck with only guarded courses refuses, makes no task and releases nothing', g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'recheck', 'course_ids', jsonb_build_array(g.cid(14), g.cid(8), g.cid(13), g.cid(9)), 'reason', 'all guarded?'))$$, '%nothing to queue%')
  and (select count(*) from pipeline.admin_jobs where args->>'on_demand' = 'true') = 3 and (select state = 'raised' from pipeline.enrichment_flags where entity_key = g.cid(14)::text));

-- 6. one university, bounded by the headroom under the existing daily ceiling ---------------------------------------------------------------------------------------------
create temp table room as select (public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'provider_ids', jsonb_build_array(g.pid(4))))->'limit'->>'room_today')::int r;
select g.ok('university preview: the room is the standing ceiling less the description items made today (any route)', (select r from room) = 500 - (select count(*) from pipeline.field_enrich_items where field = 'description' and created_at > now() - interval '1 day'));
update pipeline.platform_toolset_settings set value = to_jsonb(6) where key = 'enrich.course_text_items_per_day';
create temp table up as select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'provider_ids', jsonb_build_array(g.pid(4)))) j;
select g.ok('university preview: today already holds more items than the ceiling, so nothing is queued and the reason is daily_capacity', (select (j->'limit'->>'room_today')::int = 0 and (j->>'to_queue')::int = 0 and (j->'blocked'->>'daily_capacity')::int = 10 from up));
update pipeline.platform_toolset_settings set value = to_jsonb(10) where key = 'enrich.course_text_items_per_day';
create temp table up2 as select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'provider_ids', jsonb_build_array(g.pid(4)))) j;
select g.ok('university preview: the ceiling leaves room for exactly the remainder; the rest wait for the next request', (select (j->'limit'->>'room_today')::int = 10 - (select count(*) from pipeline.field_enrich_items where field = 'description' and created_at > now() - interval '1 day')
   and (j->>'to_queue')::int = (j->'limit'->>'room_today')::int and (j->>'left_for_later')::int = 10 - (j->>'to_queue')::int and (j->>'eligible')::int = 10 from up2));
create temp table us as select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'provider_ids', jsonb_build_array(g.pid(4)), 'reason', 'Provider 4 on demand', 'idempotency_key', 'k-uni-1')) j;
select g.ok('university start: queues exactly the room, one task, items only for that university''s missing-description courses',
  (select (j->>'items')::int = (select (j2->'limit'->>'room_today')::int from (select j j2 from up2) z) from us)
  and (select count(*) = (select (j->>'items')::int from us) and bool_and(provider_id = g.pid(4)) from pipeline.field_enrich_items where job_id = (select (j->>'job_id')::uuid from us))
  and (select scope = 'Provider 4' and args->>'scope' = 'university' and title like 'Fill description · Provider 4%' from pipeline.admin_jobs where id = (select (j->>'job_id')::uuid from us)));
update pipeline.platform_toolset_settings set value = to_jsonb(500) where key = 'enrich.course_text_items_per_day';

-- 6b. an idempotency key is for one request; the room caps chosen courses too; the Layer 4 back-pressure is honoured ----------------------------------------------------------
select g.ok('a key used before for a Fill is refused for a Recheck (not answered with the Fill task)', g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'recheck', 'course_ids', jsonb_build_array(g.cid(3)), 'reason', 'same key, other mode', 'idempotency_key', 'k-001'))$$, '%idempotency key was already used for a different request%'));
select g.ok('a key used before for chosen courses is refused for a university', g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'provider_ids', jsonb_build_array(g.pid(4)), 'reason', 'same key, other scope', 'idempotency_key', 'k-001'))$$, '%idempotency key was already used for a different request%'));
create temp table two as select array_agg(course_id) ids from (select course_id from security.cdesc_state_v1(array(select id from catalogue.courses), null) where fill_block is null order by course_id limit 2) z;
select g.ok('control: two untouched courses are Fill-eligible', (select cardinality(ids) = 2 from two));
select set_config('g.room_cap', (select count(*) + 1 from pipeline.field_enrich_items where field = 'description' and created_at > now() - interval '1 day')::text, false);
update pipeline.platform_toolset_settings set value = to_jsonb(current_setting('g.room_cap')::int) where key = 'enrich.course_text_items_per_day';
create temp table cp as select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', to_jsonb((select ids from two)))) j;
select g.ok('chosen courses are capped by the day''s room too: room 1 queues 1 and leaves the other out as daily_capacity', (select (j->'limit'->>'room_today')::int = 1 and (j->>'to_queue')::int = 1 and j->'blocked' = '{"daily_capacity": 1}'::jsonb from cp));
update pipeline.platform_toolset_settings set value = to_jsonb(current_setting('g.room_cap')::int - 1) where key = 'enrich.course_text_items_per_day';
select g.ok('chosen courses with no room left: nothing is queued and a start refuses', (select (j->>'to_queue')::int = 0 from (select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', to_jsonb((select ids from two)))) j) z)
  and g.fails(format($q$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', %L::jsonb, 'reason', 'no room'))$q$, to_jsonb((select ids from two))::text), '%nothing to queue%Over today''s limit%'));
update pipeline.platform_toolset_settings set value = to_jsonb(500) where key = 'enrich.course_text_items_per_day';
select g.ok('control: the Layer 4 back-pressure setting ships off', coalesce((select value from pipeline.platform_toolset_settings where key = 'enrich.course_description_pending_global_max'), '0'::jsonb) = '0'::jsonb
  and (select count(*) > 0 from pipeline.layer4_review_items where entity_type = 'course' and field_code = 'course_description_first_read' and status = 'pending'));
update pipeline.platform_toolset_settings set value = to_jsonb((select count(*)::int from pipeline.layer4_review_items where entity_type = 'course' and field_code = 'course_description_first_read' and status = 'pending')) where key = 'enrich.course_description_pending_global_max';
create temp table bp as select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', to_jsonb((select ids from two)))) j;
select g.ok('back-pressure on (as many waiting as the limit): every course is left out as review_backlog and none is queued, as the standing queue would not read either',
  (select (j->>'to_queue')::int = 0 and j->'blocked' = '{"review_backlog": 2}'::jsonb and j->'blocked_info'->'review_backlog'->>'label' like 'Too many descriptions%' from bp)
  and not exists (select 1 from security.enrich_course_text_gaps_v1(array['description']) t));
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'enrich.course_description_pending_global_max';
select g.ok('back-pressure off again: the two courses are eligible again', (select (j->>'to_queue')::int = 2 from (select public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', to_jsonb((select ids from two)))) j) z));
-- the standing queue and an on-demand task keep each other's courses out (what is already committed)
select g.ok('standing queue: a course an on-demand task already holds is not selected by the standing queue', not exists (select 1 from security.enrich_course_text_gaps_v1(array['description']) t where t.course_id in (g.cid(1), g.cid(3), g.cid(20))));
do $$ declare j uuid := gen_random_uuid(); c uuid := (select ids[1] from two); begin
  insert into pipeline.admin_jobs(id, kind, lane, state, title, args, requested_by, reason) values (j, 'enrich_fields', 'enrich-standing', 'queued', 'standing', '{"standing": true}', '99999999-0000-4000-8000-000000000001', 'standing');
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) select j, provider_id, c, 'description' from catalogue.courses where id = c;
  perform g.ok('a course the standing queue holds (open item) is left out of an on-demand Fill as in_flight', (select (public.admin_enrich_fields('preview', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(c)))->'blocked') = '{"in_flight": 1}'::jsonb));
  perform g.ok('and a start for it refuses and adds no second item', g.fails(format($q$select public.admin_enrich_fields('start', jsonb_build_object('mode', 'fill', 'course_ids', jsonb_build_array(%L), 'reason', 'while the standing queue holds it'))$q$, c::text), '%nothing to queue%Already in an open task%')
    and (select count(*) = 1 from pipeline.field_enrich_items where course_id = c and field = 'description' and state in ('queued', 'waiting', 'ai', 'leased', 'review')));
  delete from pipeline.field_enrich_items where job_id = j; delete from pipeline.admin_jobs where id = j;
end $$;

-- 7. verify: catalogue, Website, Zoho and HTTP are separate states; not applicable is not a failure; unknown is not zero -----------------------------------------------
create temp table vf as select public.admin_enrich_fields('verify', jsonb_build_object('course_ids', jsonb_build_array(g.cid(10), g.cid(31), g.cid(32), g.cid(33), g.cid(34), g.cid(1), g.cid(19)))) j;
create or replace function g.vrow(n int) returns jsonb language sql stable as $$ select r from vf, jsonb_array_elements(j->'courses') r where (r->>'course_id')::uuid = g.cid(n) $$;
select g.ok('verify c10 (described, published, Zoho item without a description field): website matched, zoho not_carried, http not_checked', (select g.vrow(10)->'website'->>'state' = 'matched' and g.vrow(10)->'zoho'->>'state' = 'not_carried' and g.vrow(10)->'http'->>'state' = 'not_checked' and g.vrow(10)->'catalogue'->>'state' = 'present'));
select g.ok('verify c31 (Zoho item holds the same words): zoho matched', (select g.vrow(31)->'zoho'->>'state' = 'matched'));
select g.ok('verify c32 (Zoho item holds other words): zoho differs', (select g.vrow(32)->'zoho'->>'state' = 'differs'));
select g.ok('verify c33 (described, not in the published set, not in the Zoho feed): website and zoho are pending, not failed', (select g.vrow(33)->'website'->>'state' = 'pending' and g.vrow(33)->'zoho'->>'state' = 'pending'));
select g.ok('verify c1 (no description): everything not_applicable, catalogue missing', (select g.vrow(1)->'catalogue'->>'state' = 'missing' and g.vrow(1)->'website'->>'state' = 'not_applicable' and g.vrow(1)->'zoho'->>'state' = 'not_applicable'));
update search.course_documents set course_stable_key = 'boom' where course_id = g.cid(34);
select g.ok('verify: a Website read-back that fails is unknown, never matched or zero', (select public.admin_enrich_fields('verify', jsonb_build_object('course_ids', jsonb_build_array(g.cid(34))))->'courses'->0->'website'->>'state' = 'unknown'));
update catalogue.courses set description = 'A described NZ course whose words are long enough to be real and are carried on.' where id = g.cid(19);
select g.ok('verify: an NZ course is not applicable to Zoho (not in zoho.sync_countries), never a failure', (select public.admin_enrich_fields('verify', jsonb_build_object('course_ids', jsonb_build_array(g.cid(19))))->'courses'->0->'zoho'->>'state' = 'not_applicable'));
select g.ok('verify: summary counts per state, and an unknown id is listed as missing', (select j->'summary'->'website' ? 'matched' and j->'summary'->'zoho' ? 'not_carried' and jsonb_array_length(j->'courses') = 7 from vf)
  and (select public.admin_enrich_fields('verify', jsonb_build_object('course_ids', jsonb_build_array(g.cid(99))))->'missing' = to_jsonb(array[g.cid(99)])));
select g.ok('verify refuses more than ten courses (each read-back costs about 255 ms; 8 second limit) and an empty list', g.fails($$select public.admin_enrich_fields('verify', jsonb_build_object('course_ids', (select jsonb_agg(g.cid(n)) from generate_series(1, 11) n)))$$, '%at most 10 courses%')
  and g.fails($$select public.admin_enrich_fields('verify', '{}')$$, '%choose the courses to check%'));
select g.ok('verify changed nothing', (select count(*) from catalogue.courses where description is not null) = 6 /* 5 seeded + the NZ course the previous check described */);

-- 8. the read-only state RPC -------------------------------------------------------------------------------------------------------------------------------------------
select g.as_user(2);
select g.ok('state RPC needs rank 3', g.fails($$select public.admin_course_description_state_v1(array[g.cid(1)])$$, '%Curator role or above required%'));
select g.as_user(3);
create temp table rs as select public.admin_course_description_state_v1(array[g.cid(1), g.cid(26), g.cid(10), g.cid(31)]) j;
select g.ok('state RPC: rows with the reasons in words, the ledger is reported as absent, machine_admitted is null (unknown), not false', (select jsonb_array_length(j->'courses') = 4 and (j->>'machine_ledger')::boolean = false and j->>'recheck_days' = '60'
   and (select bool_and(c->'machine_admitted' = 'null'::jsonb) from jsonb_array_elements(j->'courses') c) and (select c->'fill_info'->>'label' from jsonb_array_elements(j->'courses') c where c->>'title' = 'Course 26') = 'Tried recently' from rs));
select g.ok('state RPC: bounded to one screen page and empty input is empty', g.fails($$select public.admin_course_description_state_v1((select array_agg(g.cid(n)) from generate_series(1, 60) n, generate_series(1, 4)))$$, '%at most 200 courses%')
  and (select public.admin_course_description_state_v1('{}') = '{"courses": []}'::jsonb));
\i ledger.sql
-- agent D1's real ledger: course 10 is live-admitted; course 31 (a person approved it in Layer 4) was declined by the machine first; course 26's admission was withdrawn; course 1 has a declined row only
insert into pipeline.course_description_machine_admissions(course_id, provider_id, rule, outcome, actor) select g.cid(n), c.provider_id, 'cdesc-machine-v1', o, '99999999-0000-4000-8000-000000000001'
  from (values (10, 'admitted'), (31, 'declined'), (1, 'declined')) v(n, o) join catalogue.courses c on c.id = g.cid(v.n);
insert into pipeline.course_description_machine_admissions(course_id, provider_id, rule, outcome, actor, withdrawn_at, withdrawn_by, withdrawn_reason) select g.cid(26), c.provider_id, 'cdesc-machine-v1', 'admitted', '99999999-0000-4000-8000-000000000001', now(), '99999999-0000-4000-8000-000000000001', 'withdrawn by a person'
  from catalogue.courses c where c.id = g.cid(26);
create temp table lg as select c->>'title' t, c->>'state' st, c->'machine_admitted' ma from jsonb_array_elements(public.admin_course_description_state_v1(array[g.cid(10), g.cid(31), g.cid(26), g.cid(1)])->'courses') c;
select g.ok('machine ledger (real shape): a LIVE admission is Machine-admitted', (select st = 'machine_admitted' and ma = 'true'::jsonb from lg where t = 'Course 10'));
select g.ok('machine ledger: declined, then approved by a person, is Human decision and not Machine-admitted', (select st = 'human_decision' and ma = 'false'::jsonb from lg where t = 'Course 31'));
select g.ok('machine ledger: a declined row alone is not an admission', (select st <> 'machine_admitted' and ma = 'false'::jsonb from lg where t = 'Course 1'));
select g.ok('machine ledger: a withdrawn admission is not an admission', (select st <> 'machine_admitted' and ma = 'false'::jsonb from lg where t = 'Course 26'));
select g.ok('machine ledger present: the state RPC says so', (public.admin_course_description_state_v1(array[g.cid(10)])->>'machine_ledger')::boolean);
alter table pipeline.course_description_machine_admissions rename column withdrawn_at to withdrawn_when;
select g.ok('machine ledger of another shape: unknown (null), never false, and no error is hidden', (select c->'machine_admitted' = 'null'::jsonb from jsonb_array_elements(public.admin_course_description_state_v1(array[g.cid(10)])->'courses') c)
  and security.cdesc_machine_ids_v1(array[g.cid(10)]) is null);
alter table pipeline.course_description_machine_admissions rename column withdrawn_when to withdrawn_at;
alter table pipeline.course_description_machine_admissions rename column outcome to result;
select g.ok('machine ledger without outcome: unknown (null)', security.cdesc_machine_ids_v1(array[g.cid(10)]) is null);
alter table pipeline.course_description_machine_admissions rename column result to outcome;
select g.ok('machine ledger restored: answers again', security.cdesc_machine_ids_v1(array[g.cid(10), g.cid(31)]) = array[g.cid(10)]);
drop table pipeline.course_description_machine_admissions;
select g.ok('no ledger: unknown (null)', security.cdesc_machine_ids_v1(array[g.cid(10)]) is null);
select g.as_user(4);

-- 9. the old actions run the old text -----------------------------------------------------------------------------------------------------------------------------------
select g.ok('old path: start without mode or course_ids runs the old text (it asks for fields)', g.fails($$select public.admin_enrich_fields('start', jsonb_build_object('reason', 'old way', 'countries', jsonb_build_array('AU')))$$, '%choose at least one field%'));
select g.ok('old path: retry of an unknown task, and the task list (which shows the on-demand tasks)', g.fails($$select public.admin_enrich_fields('retry', jsonb_build_object('job_id', gen_random_uuid(), 'reason', 'old way'))$$, '%unknown task%')
  and (select count(*) >= 4 from jsonb_array_elements(public.admin_enrich_fields('jobs', '{}')->'jobs') t where t->'args'->>'on_demand' = 'true'));
select g.ok('old path: an unknown action still raises', g.fails($$select public.admin_enrich_fields('nope', '{}')$$, '%unknown action nope%'));
select g.ok('the standing queue, its settings and the other tables are untouched: no on-demand item is flagged standing', (select count(*) = 0 from pipeline.admin_jobs where args->>'standing' is not null and args->>'on_demand' = 'true'));
select g.ok('state RPC tells the screen the per-request bound from the existing setting', (select (public.admin_course_description_state_v1(array[g.cid(1)])->>'courses_per_request')::int = security.pipeline_num_v1('run_now.pilot_cap', 20)::int));
select g.ok('description_tasks: on-demand tasks only, newest first, at most ten, rank 3 and above', (select jsonb_array_length(public.admin_enrich_fields('description_tasks', '{}')->'tasks') between 1 and 10)
  and (select bool_and(t->>'id' is not null and t->>'mode' in ('fill', 'recheck')) from jsonb_array_elements(public.admin_enrich_fields('description_tasks', '{}')->'tasks') t));
select g.ok('description_tasks: filtered to the tasks that held a course', (select jsonb_array_length(public.admin_enrich_fields('description_tasks', jsonb_build_object('course_ids', jsonb_build_array(g.cid(1))))->'tasks') >= 1)
  and (select jsonb_array_length(public.admin_enrich_fields('description_tasks', jsonb_build_object('course_ids', jsonb_build_array(gen_random_uuid())))->'tasks') = 0));
select g.as_user(2);
select g.ok('description_tasks needs rank 3', g.fails($$select public.admin_enrich_fields('description_tasks', '{}')$$, '%Curator role or above required%'));
select g.as_user(4);
do $$ begin raise notice 'cdesc on demand: all scenarios ran'; end $$;
