-- Guards: F-CDESC visible results (Platform Admin decision 10 Nov 2026): the machine rule declines a reading taken from a requirements, entry, fees, how-to-apply or programme-structure page
-- (wrong_page_kind) and leaves it for a person, without touching any other rule; and Data Delivery counts the course description stages exactly (security.data_delivery_cdesc_stages_v1), machine and
-- person kept apart, "unpublished course" and Zoho never shown as 0.
-- Run by run.sh after the prelude of scenarios.sql (the helper functions and the providers): once on the migrated database (every check must pass) and once on the database from before
-- 20261110100000, where the page kind checks must FAIL (a regression that fails on the old evaluator body).
\set ON_ERROR_STOP 1
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on'; -- scratch database only
create table if not exists pipeline.zoho_sync_items(entity text, item_key text, ref_id uuid, hash text, seq bigint, seq_at timestamptz, removed_at timestamptz, item jsonb); -- the live columns; a stand-in for the feed table the base fixture does not hold
create function pg_temp.setpage(n int, p_url text) returns void language sql as $$
  update pipeline.coverage_course_pages set url = p_url where course_id = pg_temp.cid(n);
  update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('source_url', p_url) where id = pg_temp.rid(n) $$;

-- 201 to 205 are taken from pages that are not the course overview (the 201 address is the live shape: a requirements page with a query); 206 to 209 are course pages, among them the three
-- addresses that only look like a kind (a slug that starts with entry-, a word in the query, a word in the fragment)
select pg_temp.mk(n, 1) from generate_series(201, 209) n;
select pg_temp.setpage(201, 'https://example.test/explore/postgraduate-programmes/master-of-public-policy/requirements?programme=postgraduate-certificate-in-public-policy');
select pg_temp.setpage(202, 'https://example.test/study/bachelor-of-arts/Entry-Requirements');
select pg_temp.setpage(203, 'https://example.test/study/bachelor-of-arts/fees/');
select pg_temp.setpage(204, 'https://example.test/study/bachelor-of-arts/how-to-apply');
select pg_temp.setpage(205, 'https://example.test/study/bachelor-of-arts/programme-structure#year-1');
select pg_temp.setpage(206, 'https://example.test/courses/qualifications/bachelor-of-pharmacy');
select pg_temp.setpage(207, 'https://example.test/explore/postgraduate-programmes/master-of-data-science/overview');
select pg_temp.setpage(208, 'https://example.test/course/entry-level-nursing');
select pg_temp.setpage(209, 'https://example.test/course/overview?section=requirements#fees');

create temporary table g_k as select n, security.course_description_machine_admit_v1(pg_temp.rid(n)) r from generate_series(201, 209) n;
select pg_temp.diag('page kind', $q$select n || ' ' || (r->>'rule') || coalesce(' / ' || left(r->>'reason', 90), '') from g_k order by n$q$);
select pg_temp.expect('page kind: requirements, entry-requirements, fees, how-to-apply and programme-structure pages are declined wrong_page_kind (query, case, trailing slash and fragment left out)',
  (select count(*) = 5 from g_k where n between 201 and 205 and r->>'rule' = 'wrong_page_kind' and (r->>'ok')::boolean is false)
  and (select count(*) = 5 from pipeline.course_description_machine_admissions where outcome = 'declined' and reason_code = 'wrong_page_kind')
  and (select r->>'reason' like '%part "requirements"%' and r->>'next_action' = 'A person decides in Layer 4.' from g_k where n = 201));
select pg_temp.expect('page kind: a reading declined for its page kind stays waiting for a person and writes no description',
  (select count(*) = 5 from generate_series(201, 205) n where pg_temp.pending(n) and pg_temp.dsc(n) is null));
select pg_temp.expect('page kind: ordinary course pages are still admitted, including addresses that only look like a kind (entry-level slug, a word in the query or the fragment)',
  (select count(*) = 4 from g_k where n between 206 and 209 and (r->>'ok')::boolean) and (select count(*) = 4 from generate_series(206, 209) n where pg_temp.dsc(n) is not null));

-- the stages: add what the migration reads besides the cases above. A person's approval on a described course (210), a described course that no item holds (211), the Website's published status on one
-- admitted course (207), a withdrawal (206), two held readings, and a Zoho feed whose items carry no description field
insert into pim.entity_registry(id, stable_key) select pg_temp.cid(n), 'cm-c' || n from generate_series(210, 211) n;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status, description) values
  (pg_temp.cid(210), 'cm-c210', pg_temp.pid(2), 'Cm Course 210', 'published', 'A person approved this description in Layer 4 for course 210.'),
  (pg_temp.cid(211), 'cm-c211', pg_temp.pid(2), 'Cm Course 211', 'published', 'A description that arrived by another route for course 211.');
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at) values
  (pg_temp.rid(210), 'course', pg_temp.cid(210), 'course_description_first_read', null, '{"description": null}', '{"description": "A person approved this description in Layer 4 for course 210."}', 'approved', 'x', now() - interval '1 hour');
insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, layer2_state, layer3_state, change_control_ref) values
  (pg_temp.rid(210), 'approve', '00000000-0000-4000-a000-000000000001', '[other] x', '{}', '{}', 'x');
insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, description)
select pg_temp.cid(n), pg_temp.pid(1), (select id from ref.countries where iso_alpha2 = 'AU'), 'Cm Alpha College', 'Cm Course ' || n, 'x', to_tsvector('x'), case when n = 207 then 'published' else 'unpublished' end, pg_temp.dsc(n)
  from generate_series(206, 209) n;
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, reason, value) values
  ('00000000-0000-4000-c000-0000000000f1', pg_temp.pid(2), pg_temp.cid(211), 'description', 'skipped', 'ai_stored', 'held_first_admission: the provider''s first descriptions wait in Layer 4', '{}'),
  ('00000000-0000-4000-c000-0000000000f1', pg_temp.pid(2), pg_temp.cid(210), 'description', 'skipped', 'ai_stored', 'held: length: 900 characters, over the limit', '{}');
insert into pipeline.zoho_sync_items(entity, item_key, seq, removed_at, item) values ('course', 'cm-c207', 1, null, '{"title": "x"}'), ('course', 'cm-c208', 2, null, '{"title": "y"}');
create function pg_temp.as_user(p_rank int) returns void language plpgsql as $$ begin perform set_config('g.uid', '00000000-0000-4000-a000-000000000001', false); perform set_config('g.rank', p_rank::text, false); end $$;
select pg_temp.as_user(6);
create temporary table g_wd as select public.admin_course_description_machine_withdraw_v1(pg_temp.cid(206), 'Page was not the course overview') r;
select pg_temp.expect('stages: the withdrawal used for the counts worked (course 206)', (select (r->>'ok')::boolean from g_wd) and pg_temp.dsc(206) is null);

create temporary table g_st as select security.data_delivery_cdesc_stages_v1() j;
select pg_temp.diag('stages', $q$select j::text from g_st$q$);
select pg_temp.expect('stages: the counts are exact and add up (3 admitted by the machine, 1 withdrawn, 1 by a person, 5 declined for their page kind; 5 described courses: 3 + 1 + 1 by another route)',
  (select j->>'known' = 'true'
      and (j->'proposal'->>'waiting_in_layer4')::int = 5 and (j->'proposal'->>'held_behind_provider_cap')::int = 1 and (j->'proposal'->>'held_by_a_check')::int = 1
      and (j->'source'->>'proposals_from_a_stored_page')::int = 9
      and (j->'validation'->>'declined_by_machine')::int = 5 and (j->'validation'->>'not_yet_checked_by_machine')::int = 0
      and (j->'admitted'->>'by_machine')::int = 3 and (j->'admitted'->>'by_person')::int = 1 and (j->'admitted'->>'withdrawn')::int = 1
      and (j->'admitted'->>'described_courses')::int = 5 and (j->'admitted'->>'described_other_route')::int = 1 from g_st)
  and (select count(*) from catalogue.courses where nullif(btrim(description), '') is not null) = 5
  and (select count(*) from pipeline.layer4_review_items where status = 'approved') = 5); -- 207 to 209 and the withdrawn 206 by the machine, 210 by a person
select pg_temp.expect('stages: the machine rule''s declines come with their top reasons and a sample reason',
  (select jsonb_array_length(j->'validation'->'top_decline_reasons') = 1 and j->'validation'->'top_decline_reasons'->0->>'code' = 'wrong_page_kind' and (j->'validation'->'top_decline_reasons'->0->>'n')::int = 5
      and j->'validation'->'top_decline_reasons'->0->>'example' like '%page%' from g_st));
select pg_temp.expect('stages: Website published and unpublished course are counted apart (1 published of 5 described); the machine read-back is the recorded one; Zoho is not counted, with the reason, never 0',
  (select (j->'consumers'->>'website_published')::int = 1 and (j->'consumers'->>'unpublished_course')::int = 4
      and (j->'consumers'->'machine_readback'->>'matched')::int = 3 and (j->'consumers'->'machine_readback'->>'not_in_feed')::int = 0
      and j->'consumers'->'zoho'->>'known' = 'false' and j->'consumers'->'zoho'->>'reason' like '%no description field%' and not (j->'consumers'->'zoho' ? 'with_description') from g_st));
-- a failure to count is shown as such (known false with the error), never as 0, and is not an exception for the caller
alter table pipeline.zoho_sync_items rename to zoho_sync_items_away;
create temporary table g_st2 as select security.data_delivery_cdesc_stages_v1() j;
alter table pipeline.zoho_sync_items_away rename to zoho_sync_items;
select pg_temp.expect('stages: a count that cannot be made returns known false with the error, not 0 and not an exception',
  (select j->>'known' = 'false' and j->>'reason' like 'The stage counts could not be read:%' and not (j ? 'admitted') from g_st2));

do $$ declare n_fail int := (select count(*) from g_t where not ok); n int := (select count(*) from g_t);
begin
  if n_fail > 0 then raise exception 'cdv: % of % checks FAILED', n_fail, n; end if;
  raise notice 'cdv: all % checks passed', n;
end $$;
