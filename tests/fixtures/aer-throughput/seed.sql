-- CF-247 AER throughput fixtures: a production-shaped seed (live counts read 4 Nov 2026 08:26-08:28 AEDT, read only). Fixture data only.
-- 564 waiting course reads and 41 matrix runs (605 against the 600 limit) at 18 universities; RMIT holds 303 course reads. Gate classes of the
-- course reads in live proportion: 169 complete, 162 cut at the row limit, 45 shared page, 163 dropping printed minimums, 25 row level.
-- Readiness as live: 165 complete reads and 37 held items gated (19 course, 18 matrix); 376 held course reads never gated (judgement_ready).
-- 83 held reads already had one refused correction at 02:13; 2 have a correction in progress; 26 reads have no stored copy of the same page.

-- universities (live names; the ten of the mandate first) and their waiting course reads
create temp table u(n int, id uuid, name text, course_items int, matrix_items int);
insert into u values
 (1, '6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'Charles Darwin University', 1, 1), (2, '551383f9-7732-4588-a843-dd2b97c13f6f', 'University of Southern Queensland', 7, 0),
 (3, 'fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'University of New England', 2, 0), (4, 'fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'Torrens University Australia', 7, 0),
 (5, '030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'Australian Catholic University', 2, 0), (6, 'f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6', 'Central Queensland University', 3, 0),
 (7, 'c5c5d225-3d4c-4e41-8275-78eddd261073', 'Deakin University (Deakin)', 6, 0), (8, 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'James Cook University', 8, 0),
 (9, '8e1adb6c-e069-43db-9584-bd054255e702', 'RMIT University (RMIT)', 303, 0), (10, '9109fe0c-9f44-4e2d-a136-eb00dec24701', 'The University of Western Australia', 7, 1),
 (11, gen_random_uuid(), 'Monash University', 66, 0), (12, gen_random_uuid(), 'Auckland University of Technology', 46, 0),
 (13, gen_random_uuid(), 'Queensland University of Technology', 38, 0), (14, gen_random_uuid(), 'Australian National University', 19, 3),
 (15, gen_random_uuid(), 'Victoria University of Wellington', 13, 0), (16, gen_random_uuid(), 'Manukau Institute of Technology and Unitec - MIT', 11, 0),
 (17, gen_random_uuid(), 'Eastern Institute of Technology', 10, 0), (18, gen_random_uuid(), 'University of Auckland', 10, 0),
 (19, gen_random_uuid(), 'Lincoln University', 5, 0);
-- the other matrix runs (36) spread over matrix-only universities, with repeated keys: three universities have two waiting runs each
insert into u select 19 + g, gen_random_uuid(), 'Matrix university ' || g, 0, case when g <= 3 then 2 else 1 end from generate_series(1, 33) g;
insert into catalogue.providers(id, stable_key, canonical_name, country_id) select id, 'p' || n, name, gen_random_uuid() from u;

-- courses with a waiting read, one each
create temp table ci as
  select gen_random_uuid() course_id, gen_random_uuid() item_id, u.id provider_id, u.n, g k, row_number() over (order by u.n, g) rn
    from u cross join lateral generate_series(1, u.course_items) g;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title) select course_id, 'c' || rn, provider_id, 'Course ' || rn from ci;

-- the gate classes in live proportion: RMIT as measured, the rest in the remaining proportion, assigned in a fixed shuffled order
create temp table pool(scope text, cls text, k int);
insert into pool select 'rmit', c, row_number() over (order by md5(c || g)) from (values ('complete', 89), ('row_level', 2), ('row_limit', 94), ('shared_page', 27), ('drops_uncovered', 91)) v(c, m), generate_series(1, v.m) g;
insert into pool select 'other', c, row_number() over (order by md5(c || g || 'o')) from (values ('complete', 80), ('row_level', 23), ('row_limit', 68), ('shared_page', 18), ('drops_uncovered', 72)) v(c, m), generate_series(1, v.m) g;
create temp table cc as
  select ci.*, p.cls from (select ci.*, row_number() over (partition by (ci.n = 9) order by md5(ci.item_id::text)) k2 from ci) ci
    join pool p on p.scope = case when ci.n = 9 then 'rmit' else 'other' end and p.k = ci.k2;
do $$ begin if (select count(*) from cc) <> 564 then raise exception 'seed: % course items', (select count(*) from cc); end if; end $$;

insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, evidence_id, status, created_at)
select item_id, 'course', course_id, 'course_entry_first_read', jsonb_build_object('url', 'https://uni' || n || '.example/c/' || rn), gen_random_uuid(), 'pending',
       now() - interval '3 days' + rn * interval '1 minute' from cc;
insert into fx.gate(item_id, g)
select item_id, case cls
  when 'complete' then '{"rule": "E13", "complete": true, "rows_cut": 0, "shared_page": [], "drops_uncovered": [], "not_requirement": [], "reasons": []}'
  when 'row_limit' then '{"rule": "E13", "complete": false, "rows_cut": 5, "shared_page": [], "drops_uncovered": [], "not_requirement": [], "reasons": ["the reader cut 5 requirement(s) on this page at its row limit, so the read is incomplete: reject it"]}'
  when 'shared_page' then '{"rule": "E13", "complete": false, "rows_cut": 0, "shared_page": ["Master of Example (Advanced)"], "drops_uncovered": [], "not_requirement": [], "reasons": ["the stored page is also the page of 1 other programme(s) (Master of Example (Advanced)), so its rows cannot be told apart by programme: reject the read"]}'
  when 'drops_uncovered' then '{"rule": "E13", "complete": false, "rows_cut": 0, "shared_page": [], "drops_uncovered": [{"reason": "quote_not_on_page", "quote": "a minimum GPA of 5.0"}], "not_requirement": [], "reasons": ["the reader dropped 1 printed requirement(s) that no waiting row covers (quote_not_on_page 1), so the read is incomplete: replace it with a corrected read, or reject it"]}'
  else '{"rule": "E13", "complete": false, "rows_cut": 0, "shared_page": [], "drops_uncovered": [], "not_requirement": [{"id": "x"}], "reasons": ["1 waiting row(s) are not entry requirements: leave them out with Approve except"]}' end::jsonb
  from cc;

-- stored copies: the same page with a stored copy, except 26 reads (no copy, or the course is now bound to another page)
insert into pipeline.coverage_course_pages(course_id, provider_id, url, evidence_id, status)
select course_id, provider_id,
       case when (row_number() over (order by md5(item_id::text || 's'))) <= 13 then 'https://uni' || n || '.example/moved/' || rn else 'https://uni' || n || '.example/c/' || rn end,
       case when (row_number() over (order by md5(item_id::text || 's'))) between 14 and 26 then null else gen_random_uuid() end, 'bound'
  from cc;

-- readiness as live: complete reads gated (due again), 19 held course reads gated technical_blocked, the other held course reads never gated
create temp table gated as select item_id from (select item_id, row_number() over (order by md5(item_id::text || 'g')) r from cc where cls <> 'complete') z where r <= 19;
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route, blockers, gate, gate_checked_at, classified_at)
select cc.item_id, 'course', cc.course_id, 'course_entry_first_read', now() - interval '3 days', 'pending',
       case when g.item_id is not null then 'technical_blocked' else 'judgement_ready' end,
       case when g.item_id is not null then array['completeness_gate'] else '{}' end, 'review', '[]'::jsonb,
       case when cc.cls = 'complete' or g.item_id is not null then f.g end,
       case when cc.cls = 'complete' or g.item_id is not null then now() - interval '3 hours' end,
       case when cc.cls = 'complete' or g.item_id is not null then now() - interval '3 hours' else now() - interval '30 minutes' end
  from cc join fx.gate f on f.item_id = cc.item_id left join gated g on g.item_id = cc.item_id;

-- 83 held reads (dropped minimums, never gated) with one refused correction at 02:13; 2 with a correction in progress
create temp table tried as select item_id, course_id, r from (select cc.item_id, cc.course_id, row_number() over (order by md5(cc.item_id::text || 't')) r
  from cc left join gated g on g.item_id = cc.item_id where cc.cls = 'drops_uncovered' and g.item_id is null) z where r <= 85;
insert into pipeline.aer_read_supersessions(old_item_id, course_id, reason, state, outcome, requested_at, closed_at)
select item_id, course_id, 'Scheduled entry reading (job aer-scheduled-read): the waiting read dropped printed requirements that no row covers; read again from the same stored page',
       case when r <= 83 then 'refused' else 'requested' end, case when r <= 83 then 'the corrected read still drops 2 printed requirement(s)' end,
       now() - interval '6 hours', case when r <= 83 then now() - interval '5 hours' end from tried;
-- earlier corrections that replaced their read (10) or were refused (7) on items no longer waiting
insert into pipeline.aer_read_supersessions(old_item_id, course_id, reason, state, outcome, requested_at, closed_at)
select gen_random_uuid(), gen_random_uuid(), 'Scheduled entry reading (job aer-scheduled-read): earlier', case when g <= 10 then 'superseded' else 'refused' end,
       case when g > 10 then 'the corrected read was cut at the row limit (E13)' end, now() - interval '20 hours', now() - interval '19 hours' from generate_series(1, 17) g;

-- matrix runs: 41 waiting (23 ready, 18 held and gated), three universities with two waiting runs each (repeated keys)
create temp table mi as select gen_random_uuid() item_id, u.id provider_id, g, row_number() over (order by u.n, g) rn from u cross join lateral generate_series(1, u.matrix_items) g;
do $$ begin if (select count(*) from mi) <> 41 then raise exception 'seed: % matrix items', (select count(*) from mi); end if; end $$;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status, created_at)
select item_id, 'provider', provider_id, 'entry_matrix_first_run', '{}'::jsonb, 'pending', now() - interval '4 days' + rn * interval '1 minute' + g * interval '1 hour' from mi;
insert into fx.gate(item_id, g) select item_id, case when rn <= 18 then '{"rule": "D-R3", "complete": false, "reasons": ["rows dropped"]}' else '{"rule": "D-R3", "complete": true, "reasons": []}' end::jsonb from mi;
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route, blockers, gate, gate_checked_at, classified_at)
select mi.item_id, 'provider', mi.provider_id, 'entry_matrix_first_run', now() - interval '4 days', 'pending', case when rn <= 18 then 'technical_blocked' else 'judgement_ready' end,
       case when rn <= 18 then array['completeness_gate'] else '{}' end, 'review', '[]'::jsonb, f.g, now() - interval '3 hours', now() - interval '3 hours'
  from mi join fx.gate f on f.item_id = mi.item_id;

-- the run-as owner (Platform Admin), the balance, AI allowed, the Layer 4 limit and the schedule settings as live
insert into security.roles values ('platform_admin', 6, 'active');
insert into pipeline.field_gap_queue_control values (1, '11111111-1111-1111-1111-111111111111');
insert into security.user_roles values ('11111111-1111-1111-1111-111111111111', 'platform_admin', null);
insert into pipeline.layer3_openrouter_observations(kind, remaining_usd) values ('credits', 80.50);
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
 ('pipeline', 'aer.schedule_layer4_max', 'number', '600'), ('pipeline', 'aer.schedule_daily_max', 'number', '200'), ('pipeline', 'aer.schedule_held_max_tries', 'number', '2'),
 ('pipeline', 'aer.schedule_held_retry_days', 'number', '14'), ('pipeline', 'layer4.gate_batch', 'number', '20'), ('pipeline', 'layer4.readiness_batch', 'number', '1000'),
 ('pipeline', 'layer4.readiness_recheck_minutes', 'number', '120'), ('openrouter', 'credit_floor_usd', 'number', '5')
on conflict (toolset_key, key) do update set value = excluded.value;
-- the scheduled reader's helpers the held step calls (stand-ins: every seeded university is eligible and its country on)
create or replace function security.aer_eligible_v1() returns table(provider_id uuid, country text) language sql stable as $f$ select id, 'AU' from catalogue.providers $f$;
create or replace function security.aer_schedule_country_v1(p text) returns jsonb language sql stable as $f$ select '{"on": true}'::jsonb $f$;
