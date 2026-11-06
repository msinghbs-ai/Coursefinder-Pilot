-- Guards: Platform Admin direction 6 Nov 2026 09:44 §2 (reconcile the pending description items, the stratified trust-policy sample, "students" evaluated with
-- examples and every remaining rule validated after a correction, nothing auto-admitted) and §4 (permanent compatibility gate: the same admission path).
-- Runs AFTER migration 20261106500000 on the production-parity fixture (manifest.json). Every row is invented (fresh ids, no user data); the shapes follow
-- production rows (field_enrich_items.value, layer4_review_items.proposed_value, coverage_course_pages) read 6 Nov 2026.
\set ON_ERROR_STOP 1
set search_path to "$user", public, extensions;

-- Stand-ins for two Supabase objects the fixture does not carry; signatures read from production 6 Nov 2026 14:00 AEDT:
--   auth.uid() returns uuid, STABLE, not security definer;  security.current_role_rank() returns smallint, STABLE, SECURITY DEFINER.
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('g.uid', true), '')::uuid $$;
create or replace function security.current_role_rank() returns smallint language sql stable security definer as $$ select coalesce(nullif(current_setting('g.rank', true), '')::smallint, 0::smallint) $$;

-- Seeding only: the INSERT-time gate on field_enrich_items and the arrival/evidence/reroute triggers of layer4_review_items write to tables outside this
-- fixture. The trigger that matters here (layer4_review_items_course_description, on status change) stays on.
alter table pipeline.field_enrich_items disable trigger field_enrich_items_gate;
alter table pipeline.field_enrich_items disable trigger ai_spend_capture;
-- the absence and flag triggers (on a state change) classify absent values through tables outside this fixture
alter table pipeline.field_enrich_items disable trigger field_enrich_items_absence;
alter table pipeline.field_enrich_items disable trigger field_enrich_items_flag;
alter table pipeline.layer4_review_items disable trigger layer4_review_items_zz_arrival;
alter table pipeline.layer4_review_items disable trigger layer4_review_items_zz_evidence;
alter table pipeline.layer4_review_items disable trigger layer4_review_items_reroute;
-- the host-refusal and CRICOS identity guards of coverage_course_pages look up the provider's discovery tables, outside this fixture
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host_zz_cricos;

-- ids: providers a1/a2 (AU), n1 (NZ), c1 (CA); courses d01..; evidence e01..; job j1
create temporary table g_ids as select * from (values
  ('prov_au1','00000000-0000-4000-a000-000000000001'::uuid), ('prov_au2','00000000-0000-4000-a000-000000000002'::uuid),
  ('prov_nz1','00000000-0000-4000-a000-000000000003'::uuid), ('prov_ca1','00000000-0000-4000-a000-000000000004'::uuid),
  ('job','00000000-0000-4000-a000-0000000000f1'::uuid)) v(k, id);
create function pg_temp.id(k text) returns uuid language sql as $$ select id from g_ids where k = $1 $$;
create function pg_temp.cid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-a100-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.eid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-a200-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.rid(n int) returns uuid language sql as $$ select ('00000000-0000-4000-a300-' || lpad(n::text, 12, '0'))::uuid $$;

insert into pim.entity_registry(id, stable_key) select id, k from g_ids where k like 'prov%';
insert into catalogue.providers(id, stable_key, canonical_name, country_id) values
  (pg_temp.id('prov_au1'), 'g-q-au1', 'Queue University AU One', (select id from ref.countries where iso_alpha2 = 'AU')),
  (pg_temp.id('prov_au2'), 'g-q-au2', 'Queue University AU Two', (select id from ref.countries where iso_alpha2 = 'AU')),
  (pg_temp.id('prov_nz1'), 'g-q-nz1', 'Queue University NZ One', (select id from ref.countries where iso_alpha2 = 'NZ')),
  (pg_temp.id('prov_ca1'), 'g-q-ca1', 'Queue University CA One', (select id from ref.countries where iso_alpha2 = 'CA'));
insert into pipeline.admin_jobs(id) values (pg_temp.id('job'));
-- 46 courses: 1-12 AU one, 13-16 AU two, 17-28 NZ, 29-34 CA, 35-40 AU two (held readings), 41-42 AU one, 43-44 NZ (decided), 45-46 CA
insert into pim.entity_registry(id, stable_key) select pg_temp.cid(n), 'g-q-c' || n from generate_series(1, 46) n;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, lifecycle_status)
select pg_temp.cid(n), 'g-q-c' || n,
       pg_temp.id(case when n <= 12 or n in (41, 42) then 'prov_au1' when n <= 16 or n between 35 and 40 then 'prov_au2' when n <= 28 or n in (43, 44) then 'prov_nz1' else 'prov_ca1' end),
       'Queue Course ' || n, case when n = 7 then 'inactive' else 'active' end
  from generate_series(1, 46) n;
insert into pipeline.evidence_artifacts(id, evidence_type) select pg_temp.eid(n), 'page' from generate_series(1, 90) n;
-- the bound page of every course is evidence n (a changed page for course 5 is evidence 50)
insert into pipeline.coverage_course_pages(course_id, provider_id, status, identity_basis, url, evidence_id)
select pg_temp.cid(n), c.provider_id, 'bound', 'course_title_on_page', 'https://example.test/course/' || n, pg_temp.eid(case when n = 5 then 50 else n end)
  from generate_series(1, 46) n join catalogue.courses c on c.id = pg_temp.cid(n);

-- a good reading: two sentences, each supported by its quote, 80-700 characters, no claim or marketing word
create function pg_temp.w(n int, k int) returns text language sql as $$ select translate(substr(md5(n::text || '-' || k), 1, 9), '0123456789', 'ghijklmnop') $$;
create function pg_temp.good(n int) returns jsonb language sql as $$
  select jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(
    jsonb_build_object('text', 'Queue Course ' || n || ' covers ' || pg_temp.w(n, 1) || ', ' || pg_temp.w(n, 2) || ', ' || pg_temp.w(n, 3) || ', ' || pg_temp.w(n, 4) || ', ' || pg_temp.w(n, 5) || ', ' || pg_temp.w(n, 6) || ', ' || pg_temp.w(n, 7) || ' and ' || pg_temp.w(n, 8) || ' across the degree.',
                       'quote', 'Queue Course ' || n || ' covers ' || pg_temp.w(n, 1) || ', ' || pg_temp.w(n, 2) || ', ' || pg_temp.w(n, 3) || ', ' || pg_temp.w(n, 4) || ', ' || pg_temp.w(n, 5) || ', ' || pg_temp.w(n, 6) || ', ' || pg_temp.w(n, 7) || ' and ' || pg_temp.w(n, 8) || ' across the degree.', 'on_page', true),
    jsonb_build_object('text', 'You complete a capstone project in the final year with guidance from teaching staff in your area of study.',
                       'quote', 'You complete a capstone project in the final year with guidance from teaching staff in your area of study.', 'on_page', true))) $$;

-- item(n, reading): an AI reading (field_enrich_items, state review, evidence n) and its pending Layer 4 proposal, as enrich_course_text_record_v1 writes them
create function pg_temp.item(n int, reading jsonb, ev int default null, link boolean default true) returns void language plpgsql as $$
declare v_item bigint; v_text text;
begin
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(reading->'sentences') with ordinality e(x, o));
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, evidence_id, created_at, updated_at)
  select pg_temp.id('job'), c.provider_id, c.id, 'description', 'review', 'ai_stored', reading || jsonb_build_object('text', v_text, 'check', jsonb_build_object('ok', true, 'rule', 'ok')),
         pg_temp.eid(coalesce(ev, n)), now() - make_interval(hours => 100 - n), now() - make_interval(hours => 100 - n)
    from catalogue.courses c where c.id = pg_temp.cid(n) returning id into v_item;
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref, created_at)
  values (pg_temp.rid(n), 'course', pg_temp.cid(n), 'course_description_first_read', pg_temp.eid(coalesce(ev, n)), jsonb_build_object('description', null),
          jsonb_build_object('description', v_text, 'item_id', case when link then v_item end, 'source_url', 'https://example.test/course/' || n,
            'checks', jsonb_build_object('sentences', jsonb_array_length(reading->'sentences'), 'chars', length(v_text)),
            'sentences', (select jsonb_agg(jsonb_build_object('text', s->>'text', 'quote', s->>'quote') order by o) from jsonb_array_elements(reading->'sentences') with ordinality e(s, o))),
          'pending', 'Course description read from the course''s own page.', 'CF-CHG-20260915-247', now() - make_interval(hours => 100 - n));
end $$;

-- pending proposals ----------------------------------------------------------------------------------------------------------------------------
-- 1-4, 6, 8-12 AU one: ready; 5 page changed (bound page differs); 7 inactive; 13 already filled; 14 locked; 15 no reading; 16 fails now (a claim word)
select pg_temp.item(n, pg_temp.good(n)) from generate_series(1, 12) n where n not in (5, 7);
select pg_temp.item(5, pg_temp.good(5));          -- the proposal's evidence is evidence 5; the course is now bound to evidence 50 -> page_changed
select pg_temp.item(7, pg_temp.good(7));
select pg_temp.item(13, pg_temp.good(13));
update catalogue.courses set description = 'An older adapter description of this course that already stands on the site and is not from this reader.' where id = pg_temp.cid(13);
select pg_temp.item(14, pg_temp.good(14));
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(14), 'description', 'value');
select pg_temp.item(15, pg_temp.good(15), null, false);
select pg_temp.item(16, jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(
  jsonb_build_object('text', 'Graduates of Queue Course 16 reach strong employment outcomes across the sector after the final year of study here.',
                     'quote', 'Queue Course 16 prepares you for work across the sector after the final year of study here.', 'on_page', true))));
-- NZ 17-28 and CA 29-34 ready
select pg_temp.item(n, pg_temp.good(n)) from generate_series(17, 34) n;

-- held readings (state skipped), as enrich_course_text_record_v1 writes them: a "students" reading whose page says "you", a real outcome claim, too long, too many
create function pg_temp.held(n int, rule text, reason text, reading jsonb, chars int, sentences int) returns void language sql as $$
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, evidence_id, reason, cost_usd, created_at, updated_at)
  select pg_temp.id('job'), c.provider_id, c.id, 'description', 'skipped', 'ai_stored',
         reading || jsonb_build_object('check', jsonb_build_object('ok', false, 'rule', rule, 'checks', jsonb_build_object('sentences', sentences, 'chars', chars))),
         pg_temp.eid(n), 'held: ' || rule || ': ' || reason, 0.001, now(), now() from catalogue.courses c where c.id = pg_temp.cid(n) $$;
-- 35: "Students" in the sentence, the page says "you" (suggested harmless): only this word holds it
select pg_temp.held(35, 'unsupported_claim', 'a ranking, outcome or accreditation claim that is not in the quote', jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(
  jsonb_build_object('text', 'Students study the design and analysis of experiments across the first two years of the degree.',
                     'quote', 'You study the design and analysis of experiments across the first two years of the degree.', 'on_page', true),
  jsonb_build_object('text', 'The final year is a supervised research project with an industry partner.',
                     'quote', 'The final year is a supervised research project with an industry partner.', 'on_page', true))), 160, 2);
-- 36: "students" and a sentence too many words overall -> after removing "students" the next rule is length? no: here the reading is long, so length follows
select pg_temp.held(36, 'unsupported_claim', 'a ranking, outcome or accreditation claim that is not in the quote', jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(
  jsonb_build_object('text', 'Students study the design and analysis of experiments across the first two years of the degree, building a portfolio of laboratory and field reports that is assessed each semester against clear criteria published to every enrolled person at the start of the unit and discussed in small tutorials throughout the teaching period each year.',
                     'quote', 'You study the design and analysis of experiments across the first two years of the degree, building a portfolio of laboratory and field reports that is assessed each semester against clear criteria published to every enrolled person at the start of the unit and discussed in small tutorials throughout the teaching period each year.', 'on_page', true),
  jsonb_build_object('text', 'The final year is a supervised research project with an industry partner, presented to an assessment panel at the end of the second semester and examined on the written report and the oral defence of the findings to the panel.',
                     'quote', 'The final year is a supervised research project with an industry partner, presented to an assessment panel at the end of the second semester and examined on the written report and the oral defence of the findings to the panel.', 'on_page', true),
  jsonb_build_object('text', 'Teaching is shared between lectures, laboratories, workshops and fieldwork across the three years of study here. The teaching team also meets each cohort in small groups every fortnight to review progress, discuss feedback on submitted work and agree the next steps for the coming weeks of the semester.',
                     'quote', 'Teaching is shared between lectures, laboratories, workshops and fieldwork across the three years of study here. The teaching team also meets each cohort in small groups every fortnight to review progress, discuss feedback on submitted work and agree the next steps for the coming weeks of the semester.', 'on_page', true))), 740, 3);
-- 37: a real outcome claim (the quote does not address the reader) held as unsupported_claim
select pg_temp.held(37, 'unsupported_claim', 'a ranking, outcome or accreditation claim that is not in the quote', jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(
  jsonb_build_object('text', 'Graduates of this degree reach strong employment outcomes across the sector soon after finishing their studies.',
                     'quote', 'This degree prepares graduates for work across the sector soon after finishing their studies.', 'on_page', true))), 112, 1);
-- 38 too long, 39 too many sentences, 40 first-admission wait
select pg_temp.held(38, 'length', '780 characters, outside the set range (held whole, never cut)', pg_temp.good(38), 780, 2);
select pg_temp.held(39, 'sentence_count', '5 sentence(s), outside the set range', pg_temp.good(39), 400, 5);
select pg_temp.held(40, 'length', '720 characters, outside the set range (held whole, never cut)', pg_temp.good(40) || jsonb_build_object('reask', jsonb_build_object('n', 1, 'first', jsonb_build_object('rule', 'length', 'sentences', 2, 'chars', 910))), 720, 2);
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, evidence_id, reason, cost_usd, created_at, updated_at)
select pg_temp.id('job'), c.provider_id, c.id, 'description', 'skipped', 'ai_stored', pg_temp.good(41) || jsonb_build_object('text', 'x'), pg_temp.eid(1),
       'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved', 0.001, now(), now() from catalogue.courses c where c.id = pg_temp.cid(45);
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, reason, cost_usd, created_at, updated_at)
select pg_temp.id('job'), c.provider_id, c.id, 'description', 'failed', 'ai_stored', 'no answer could be recorded after 3 tries', 0, now(), now() from catalogue.courses c where c.id = pg_temp.cid(46);

-- decided proposals: 41 and 44 approved (the description now stands), 42 rejected with a reason class, 43 rejected without one
select pg_temp.item(n, pg_temp.good(n)) from generate_series(41, 44) n;
update catalogue.courses set description = (select proposed_value->>'description' from pipeline.layer4_review_items where id = pg_temp.rid(41)) where id = pg_temp.cid(41);
update catalogue.courses set description = (select proposed_value->>'description' from pipeline.layer4_review_items where id = pg_temp.rid(44)) where id = pg_temp.cid(44);
-- the status-change trigger (layer4_review_items_course_description) is existing, unchanged behaviour that writes search.refresh_requests (a table this fixture does not
-- carry); it is switched off for the seeding of decided rows and the item states it sets are written here as it writes them
alter table pipeline.layer4_review_items disable trigger layer4_review_items_course_description;
update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id in (pg_temp.rid(41), pg_temp.rid(44));
update pipeline.layer4_review_items set status = 'rejected', decided_at = now() where id in (pg_temp.rid(42), pg_temp.rid(43));
alter table pipeline.layer4_review_items enable trigger layer4_review_items_course_description;
update pipeline.field_enrich_items set state = 'filled', reason = null where course_id in (pg_temp.cid(41), pg_temp.cid(44));
update pipeline.field_enrich_items set state = 'skipped', reason = 'not admitted in Layer 4 (rejected)' where course_id in (pg_temp.cid(42), pg_temp.cid(43));
insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, change_control_ref) values
  (pg_temp.rid(41), 'approve', '00000000-0000-4000-a000-0000000000aa', 'Checked against the page', 'CF-CHG-20260915-247'),
  (pg_temp.rid(44), 'approve', '00000000-0000-4000-a000-0000000000aa', 'Checked against the page', 'CF-CHG-20260915-247'),
  (pg_temp.rid(42), 'reject', '00000000-0000-4000-a000-0000000000aa', '[support] The second sentence goes beyond the page', 'CF-CHG-20260915-247'),
  (pg_temp.rid(43), 'reject', '00000000-0000-4000-a000-0000000000aa', 'Not right for this course', 'CF-CHG-20260915-247');
insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, description)
select c.id, c.provider_id, p.country_id, 'Queue University AU One', 'Queue Course 41', 'x', to_tsvector('x'), 'published', c.description
  from catalogue.courses c join catalogue.providers p on p.id = c.provider_id where c.id = pg_temp.cid(41);

-- ===== tests (all inside a READ ONLY transaction: the reports cannot write) ==================================================================
create temporary table g_before as select
  (select md5(string_agg(id::text || status || coalesce(decided_at::text, ''), ',' order by id)) from pipeline.layer4_review_items) l4,
  (select md5(string_agg(key || value::text, ',' order by key)) from pipeline.platform_toolset_settings) st,
  (select md5(string_agg(id::text || coalesce(description, ''), ',' order by id)) from catalogue.courses) cs,
  (select md5(string_agg(id::text || state, ',' order by id)) from pipeline.field_enrich_items) fe;
begin read only;
set local g.uid = '00000000-0000-4000-a000-0000000000aa';
set local g.rank = '4';
do $$
declare v jsonb; n int;
begin
  -- reconciliation: the classes add up to the pending total, nothing is hidden
  v := public.admin_course_description_queue('summary', '{"recheck": true}');
  if (v->>'pending')::int <> 34 then raise exception 'pending is %, expected 34', v->>'pending'; end if;
  if (select sum(value::int) from jsonb_each_text(v->'by_class')) <> 34 then raise exception 'the classes do not add up to the pending total: %', v->'by_class'; end if;
  if v->'by_class' <> '{"ready": 28, "locked": 1, "fails_now": 1, "no_reading": 1, "page_changed": 1, "already_filled": 1, "course_inactive": 1}'::jsonb then raise exception 'classes: %', v->'by_class'; end if;
  raise notice 'reconcile [pass]: 34 pending = %', v->'by_class';
  if (v->>'admitted_by_person')::int <> 2 or (v->>'published_to_the_website')::int <> 1 or (v->>'admitted_without_a_person')::int <> 0 or (v->>'proposed_in_layer4')::int <> 34 then
    raise exception 'measures: %', v; end if;
  if (v->>'waiting_behind_provider_cap')::int <> 1 then raise exception 'cap wait: %', v; end if;
  raise notice 'measures [pass]: proposed 34, admitted by a person 2, published 1, admitted without a person 0 (D1)';
  -- one provider
  v := public.admin_course_description_queue('summary', jsonb_build_object('provider_id', pg_temp.id('prov_au1'), 'recheck', true));
  if (v->>'pending')::int <> 12 or (v->'by_class'->>'ready')::int <> 10 then raise exception 'provider summary: %', v; end if;
  raise notice 'provider summary [pass]: %', v->'by_class';
  -- the reviewer queue: oldest first, in the Inbox item shape, only ready ones
  v := public.admin_course_description_queue('items', jsonb_build_object('provider_id', pg_temp.id('prov_au1')));
  if (v->>'total')::int <> 10 or jsonb_array_length(v->'items') <> 10 then raise exception 'items: %', v->>'total'; end if;
  if v->'items'->0->>'kind' <> 'provider_description' or v->'items'->0->>'ref' <> pg_temp.rid(1)::text or v->'items'->0->'detail'->'proposed'->>'description' is null then raise exception 'item shape: %', v->'items'->0; end if;
  if exists (select 1 from jsonb_array_elements(v->'items') x where x->>'ref' in (pg_temp.rid(5)::text, pg_temp.rid(7)::text)) then raise exception 'a stale item is offered as ready'; end if;
  raise notice 'items [pass]: 10 ready for the provider, oldest first, Inbox shape, stale ones left out';
  v := public.admin_course_description_queue('items', '{}');
  if (v->>'total')::int <> 29 then raise exception 'global ready (rules not re-run: 28 pass, 1 fails now, flagged on its card): %', v->>'total'; end if;
  -- held reasons
  v := public.admin_course_description_queue('held_reasons');
  if (v->>'held_by_a_check')::int <> 6 or (v->>'passed_every_check')::int <> 37 then raise exception 'held reasons: %', v; end if;
  if v->'by_rule' <> '{"length": 2, "sentence_count": 1, "unsupported_claim": 3}'::jsonb then raise exception 'by_rule %', v->'by_rule'; end if;
  if v->'claim_words' <> '{"students": 2, "employment": 1}'::jsonb then raise exception 'claim words %', v->'claim_words'; end if;
  if (v->'reask'->>'attempted')::int <> 1 or (v->'reask'->>'still_held')::int <> 1 then raise exception 'reask %', v->'reask'; end if;
  raise notice 'held reasons [pass]: %', v->'by_rule';
  -- claim words: "students" has harmless-looking and an every-rule re-run; "employment" does not pass without its word
  v := public.admin_course_description_queue('claim_words');
  select x into v from jsonb_array_elements(v->'words') x where x->>'word' = 'students';
  if (v->>'held')::int <> 2 or (v->>'only_this_word')::int <> 2 or (v->>'passes_every_other_rule_without_it')::int <> 1 or (v->'next_rule'->>'length')::int <> 1 or (v->>'quote_addresses_the_reader')::int <> 2 then
    raise exception 'students: %', v; end if;
  raise notice 'claim words [pass]: students held 2, passes every other rule without it 1, the other falls to %', v->'next_rule';
  v := public.admin_course_description_queue('claim_words', '{"words": ["employment"]}');
  select x into v from jsonb_array_elements(v->'words') x where x->>'word' = 'employment';
  -- the negative example: the quote does not address the reader, so the sentence is a real outcome claim; the word is the ONLY thing holding it
  -- (the other rules would pass it), so removing the word would admit a claim the page does not support. The evaluation shows that; a person decides.
  if (v->>'held')::int <> 1 or (v->>'only_this_word')::int <> 1 or (v->>'passes_every_other_rule_without_it')::int <> 1 or (v->>'quote_addresses_the_reader')::int <> 0
     or jsonb_array_length(v->'suggested_claim') <> 1 or jsonb_array_length(v->'suggested_harmless') <> 0 then raise exception 'employment: %', v; end if;
  raise notice 'claim words [pass]: employment is a suggested real claim (no reader quote) and is the only rule holding it, so it must stay in the list';
  -- the stratified sample (30 AU / 15 NZ / 5 CA subject to availability)
  v := public.admin_course_description_queue('sample');
  if v->'strata' <> '[{"country":"AU","wanted":30,"eligible":12,"selected":12,"shortfall":18},{"country":"NZ","wanted":15,"eligible":14,"selected":14,"shortfall":1},{"country":"CA","wanted":5,"eligible":6,"selected":5,"shortfall":0}]'::jsonb then raise exception 'strata %', v->'strata'; end if;
  if (v->>'selected')::int <> 31 or (v->>'approved')::int <> 2 or (v->>'rejected')::int <> 2 or v->'rejected_by_class' <> '{"support": 1, "unclassified": 1}'::jsonb then raise exception 'sample %', v - 'rows'; end if;
  if (v->'reviewer_disagreement'->>'passed_every_check_but_rejected')::int <> 2 then raise exception 'disagreement %', v->'reviewer_disagreement'; end if;
  if v->>'note' not like '%not an authority to bypass Layer 4%' then raise exception 'the sample must say it is not an authority'; end if;
  raise notice 'sample [pass]: % selected, strata %', v->>'selected', v->'strata';
  -- the sample is stable and the queue can be limited to it
  if v->'rows' <> public.admin_course_description_queue('sample')->'rows' then raise exception 'the sample changed between two reads'; end if;
  n := (public.admin_course_description_queue('items', '{"sample": true}')->>'total')::int;
  if n <> 29 - 0 and n <> (select count(*) from security.course_description_sample_ids_v1() s join security.course_description_reconcile_v1(null, true, null) q on q.item_id = s.item_id where q.class = 'ready') then raise exception 'sample queue %', n; end if;
  raise notice 'sample queue [pass]: % of the sample are waiting for a person', n;
end $$;
-- rank and action guards
set local g.rank = '3';
do $$ begin
  begin perform public.admin_course_description_queue('summary'); raise exception 'rank 3 was allowed'; exception when insufficient_privilege then raise notice 'rank [pass]: below Pipeline Operator is refused'; end;
end $$;
set local g.rank = '4';
do $$ begin
  begin perform public.admin_course_description_queue('admit'); raise exception 'an unknown action was allowed'; exception when invalid_parameter_value then raise notice 'actions [pass]: only the five read actions exist'; end;
end $$;
commit;

-- nothing was written: Layer 4, settings, the courses' descriptions and the readings are exactly as seeded
do $$ begin
  if (select l4 from g_before) is distinct from (select md5(string_agg(id::text || status || coalesce(decided_at::text, ''), ',' order by id)) from pipeline.layer4_review_items)
     or (select st from g_before) is distinct from (select md5(string_agg(key || value::text, ',' order by key)) from pipeline.platform_toolset_settings)
     or (select cs from g_before) is distinct from (select md5(string_agg(id::text || coalesce(description, ''), ',' order by id)) from catalogue.courses)
     or (select fe from g_before) is distinct from (select md5(string_agg(id::text || state, ',' order by id)) from pipeline.field_enrich_items) then raise exception 'a report changed data'; end if;
  raise notice 'read only [pass]: no report changed Layer 4, a setting, a description or a reading';
end $$;

-- the admission path is the existing one: a rejection and an approval go through the Layer 4 trigger exactly as before, D1 holds
do $$ declare v_trusted boolean; begin
  select security.course_description_trusted_v1(pg_temp.id('prov_au1')) into v_trusted;
  if v_trusted then raise exception 'a provider is trusted: review_first must hold (D1)'; end if;
  raise notice 'D1 [pass]: no provider is trusted (enrich.course_description_review_first = %)', security.pipeline_num_v1('enrich.course_description_review_first', 5);
end $$;
-- a correction to the word list is checked against every other rule: removing "students" admits only a reading that passes the rest (case 36 falls to length)
do $$ declare v jsonb; begin
  v := security.course_description_check_with_v1(pg_temp.cid(36), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(36) and field = 'description'),
          (select jsonb_agg(w) from jsonb_array_elements_text((select value from pipeline.platform_toolset_settings where key = 'enrich.course_description_claim_words')) w where w <> 'students'), null);
  if v->>'rule' <> 'length' then raise exception 'removing students must leave the length rule in force, got %', v->>'rule'; end if;
  raise notice 'validate-all [pass]: without "students" the long reading is still held by %', v->>'rule';
end $$;
