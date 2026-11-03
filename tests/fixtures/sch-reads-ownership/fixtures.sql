-- Cases after 20261104210000 (each raises on failure; a notice per case passed)
create or replace function pg_temp.ok(p boolean, p_case text) returns void language plpgsql as $$
begin if not coalesce(p, false) then raise exception 'FAILED: %', p_case; end if; raise notice 'ok: %', p_case; end $$;

-- R1 shipped state: the allowance is 0, so a request is refused and logged; nothing is queued
do $$
declare r jsonb;
begin
  perform pg_temp.ok((select value = '0'::jsonb from pipeline.platform_toolset_settings where key = 'scholarship.single_read_daily_max'), 'R1 single reads ship off (allowance 0)');
  r := security.scholarship_read_request_v1(1323, false, 'Approved read VU 1323 (fixture)', 'Platform Admin, 3 Nov 2026 19:34');
  perform pg_temp.ok(r->>'ok' = 'false' and r->>'why' like 'single reads are off%', 'R1 refused while off: ' || (r->>'why'));
  perform pg_temp.ok((select count(*) = 0 from pipeline.scholarship_ai_queue), 'R1 nothing queued');
  perform pg_temp.ok((select state = 'refused' from pipeline.scholarship_read_requests where id = (r->>'request')::bigint), 'R1 the refusal is logged');
  begin
    perform security.scholarship_read_request_v1(1323, false, 'short', '');
    raise exception 'FAILED: R1 a request without approval was accepted';
  exception when raise_exception then
    if sqlerrm like 'FAILED%' then raise; end if;
    raise notice 'ok: R1 a request must name who approved it and why';
  end;
end $$;

-- R2 the Platform Admin allows two reads: VU 1323 (normal path) and Bond 1230 (fresh); a third is refused; each queues exactly one row
do $$
declare a jsonb; b jsonb; c jsonb; d jsonb;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(2), reason = 'fixture: approved reads' where key = 'scholarship.single_read_daily_max';
  a := security.scholarship_read_request_v1(1323, false, 'Approved read VU 1323 (fixture)', 'Platform Admin, 3 Nov 2026 19:34');
  b := security.scholarship_read_request_v1(1230, true, 'Approved fresh read Bond 1230 (fixture)', 'Platform Admin, 3 Nov 2026 19:34');
  perform pg_temp.ok(a->>'ok' = 'true' and b->>'ok' = 'true', 'R2 both approved reads queued');
  d := security.scholarship_read_request_v1(1230, true, 'A second read of Bond 1230 (fixture)', 'Platform Admin, 3 Nov 2026 19:34');
  perform pg_temp.ok(d->>'why' = 'a read of this item is already queued', 'R2 one open read per held item');
  c := security.scholarship_read_request_v1(1184, false, 'An unapproved third read (fixture)', 'Platform Admin, 3 Nov 2026 19:34');
  perform pg_temp.ok(c->>'why' like '%allowance is used%', 'R2 the third read of the day is refused: ' || (c->>'why'));
  perform pg_temp.ok((select count(*) = 2 from pipeline.scholarship_ai_queue), 'R2 exactly two queue rows');
  perform pg_temp.ok((select count(*) = 2 from pipeline.scholarship_ai_queue q join pipeline.scholarship_read_requests r on r.id = q.read_request_id and r.queue_id = q.id), 'R2 each row is bound to its request');
  perform pg_temp.ok((select fresh_read and run_kind = 'admit' and candidate_id = 6712 and storage_path is null from pipeline.scholarship_ai_queue where read_request_id = (b->>'request')::bigint), 'R2 Bond row is fresh, on the admit path');
  perform pg_temp.ok((select not fresh_read and candidate_id = 7700 from pipeline.scholarship_ai_queue where read_request_id = (a->>'request')::bigint), 'R2 VU row is the normal read');
  perform pg_temp.ok((select before->>'candidate_storage_path' like '%/6712/9d25e2f7.html.gz' from pipeline.scholarship_read_requests where id = (b->>'request')::bigint), 'R2 the old copy is recorded as before');
  perform pg_temp.ok((select count(*) >= 2 from pipeline.fx_calls where fn = 'fire'), 'R2 the scholarship AI job is fired');
end $$;

-- R3 the paid lane held: the fresh Bond row waits (no stored copy counts for it); VU (no copy) waits too
do $$
declare v jsonb;
begin
  perform set_config('fx.lane_hold', 'held', false);
  v := public.svc_scholarship_ai_next(8);
  perform pg_temp.ok(jsonb_array_length(v) = 0, 'R3 while the paid lane is held neither approved read is taken');
  perform pg_temp.ok(not security.scholarship_ai_has_copy_v1((select id from pipeline.scholarship_ai_queue where candidate_id = 6712)), 'R3 the Bond candidate copy does not count for a fresh read');
  perform set_config('fx.lane_hold', '', false);
end $$;

-- R4 lane open: the worker is given no stored copy for Bond (fresh) and none for VU
do $$
declare v jsonb; e jsonb;
begin
  v := public.svc_scholarship_ai_next(8);
  perform pg_temp.ok(jsonb_array_length(v) = 2, 'R4 both taken');
  for e in select * from jsonb_array_elements(v) loop
    perform pg_temp.ok(e->>'storage_path' is null, 'R4 queue ' || (e->>'queue_id') || ' is read from the page (no stored copy given)');
  end loop;
end $$;

-- R5 Bond: step 1 reads the page and settles for admission -> the second model confirms on the fresh copy; the answer goes to held item 1230;
-- nothing is applied or admitted; the request records the outcome with its dates quote
do $$
declare q1 bigint := (select id from pipeline.scholarship_ai_queue where candidate_id = 6712); q2 bigint; r jsonb; v jsonb;
        ans jsonb := '{"name": "The Abedian Foundation Master of Architecture Scholarship", "audience": "both", "offered": "yes", "is_scholarship": true, "dates_quote": "to commence in January 2026 only"}';
begin
  r := public.svc_scholarship_ai_record(q1, ans, '{"name": true, "audience": true}'::jsonb, 'scholarship', 0.0002, 100, 50, 1, null,
         'layer2/AU/scholarships/739948f6/ai/' || q1 || '/fresh.html.gz', 'fresh', 'https://bond.edu.au/scholarship/abedian-foundation-master-of-architecture-scholarship', '{"read_status": "read"}'::jsonb, false);
  perform pg_temp.ok(r->>'escalated_to' = 'gpt-4.1-mini', 'R5 the second model confirms (normal chain)');
  select id into q2 from pipeline.scholarship_ai_queue where root_id = q1;
  perform pg_temp.ok((select read_request_id is not null and not fresh_read and storage_path like '%/fresh.html.gz' from pipeline.scholarship_ai_queue where id = q2), 'R5 step 2 carries the request and the fresh copy');
  perform pg_temp.ok((select storage_path like '%/fresh.html.gz' and evidence_id is not null from pipeline.scholarship_page_candidates where id = 6712), 'R5 the candidate now holds the fresh copy, stored as evidence');
  perform pg_temp.ok((select count(*) = 1 from pipeline.evidence_artifacts where storage_path like '%/fresh.html.gz' and evidence_type = 'scholarship_ai_page'), 'R5 one evidence row for the fresh page');
  v := public.svc_scholarship_ai_next(8);
  perform pg_temp.ok(v->0->>'storage_path' like '%/fresh.html.gz', 'R5 step 2 is given the fresh copy, not the 29 Sep copy');
  r := public.svc_scholarship_ai_record(q2, ans, '{"name": true, "audience": true}'::jsonb, 'scholarship', 0.001, 100, 50, 1, null, null, null, null, null, false);
  perform pg_temp.ok(not exists (select 1 from pipeline.fx_calls where fn in ('apply', 'review_apply')), 'R5 nothing applied, admitted or decided');
  perform pg_temp.ok((select status = 'pending' and storage_path like '%/fresh.html.gz' and cardinality(extraction_ids) = 2 from pipeline.scholarship_ai_reviews where id = 1230), 'R5 held item 1230 now shows the fresh read (2 extractions)');
  perform pg_temp.ok((select state = 'read' and outcome->>'dates_quote' = 'to commence in January 2026 only' and outcome->>'storage_path' like '%/fresh.html.gz'
                        from pipeline.scholarship_read_requests where review_id = 1230 and queue_id = q1), 'R5 request read; the round quote is recorded for the person');
end $$;

-- R6 VU: the page cannot be read -> the request ends at once: one read, no retry, no other model; held item 1323 says so
do $$
declare q bigint := (select id from pipeline.scholarship_ai_queue where candidate_id = 7700); r jsonb;
begin
  r := public.svc_scholarship_ai_record(q, null, null, null, 0, null, null, 1, 'the page could not be read', null, null, 'https://www.vu.edu.au/bachelor-of-it-professional-placement-scholarship-application', '{"read_status": "gone"}'::jsonb, false);
  perform pg_temp.ok((select state = 'done' from pipeline.scholarship_ai_queue where id = q) and not exists (select 1 from pipeline.scholarship_ai_queue where root_id = q), 'R6 no retry and no other model');
  perform pg_temp.ok((select state = 'read_failed' and outcome->>'error' = 'the page could not be read' from pipeline.scholarship_read_requests where review_id = 1323 and state <> 'refused'), 'R6 request read_failed');
  perform pg_temp.ok((select status = 'pending' and reason like 'Approved read: the page could not be read%' from pipeline.scholarship_ai_reviews where id = 1323), 'R6 held item 1323 stays pending with the honest reason');
end $$;

-- R7 a request refused for credits three times ends as refused
do $$
declare r jsonb; q bigint;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(3) where key = 'scholarship.single_read_daily_max';
  update pipeline.scholarship_ai_reviews set status = 'pending' where id = 1184;
  r := security.scholarship_read_request_v1(1184, false, 'Fixture: a read the scraper keeps refusing', 'Platform Admin, fixture');
  q := (r->>'queue_id')::bigint;
  update pipeline.scholarship_ai_queue set attempts = 3 where id = q;
  perform public.svc_scholarship_ai_record(q, null, null, null, 0, null, null, 0, null, null, null, null, null, true);
  perform pg_temp.ok((select state = 'refused' and outcome->>'why' = 'no scraper credit after 3 tries' from pipeline.scholarship_read_requests where id = (r->>'request')::bigint), 'R7 credit refusals end the request');
  perform pg_temp.ok((select state = 'failed' from pipeline.scholarship_ai_queue where id = q), 'R7 the queue row is closed as before');
end $$;

-- R8 regression: a row that is not a request is unchanged: stored copy first, and a settled answer is applied as before
do $$
declare q bigint; v jsonb;
begin
  insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, candidate_id, provider_id, url)
  values ('gpt-4.1-mini', 2, 'admit', 5000, '188103a5-1aba-4f99-bd3e-0416659086d3', 'https://www.mq.edu.au/study/scholarships/regression') returning id into q;
  v := public.svc_scholarship_ai_next(8);
  perform pg_temp.ok(v->0->>'storage_path' like '%/5000/r.html.gz', 'R8 an ordinary row still takes the stored copy');
  perform public.svc_scholarship_ai_record(q, '{"name": "Regression", "audience": "international", "offered": "yes"}'::jsonb, '{"name": true, "audience": true}'::jsonb, 'scholarship', 0, 1, 1, 1, null, null, null, null, null, false);
  perform pg_temp.ok(exists (select 1 from pipeline.fx_calls where fn = 'apply'), 'R8 an ordinary settled answer is applied as before');
end $$;

-- R9 ownership: one proposal per held item on a directory page, with evidence and named institutions of the same country; no change to the items
do $$
declare r jsonb; c jsonb;
begin
  r := security.scholarship_owner_proposals_remedy_v1(null);
  perform pg_temp.ok((r->'evidence'->>'proposed')::int = 4, 'R9 four proposals (the four directory items of the fixture): ' || r::text);
  perform pg_temp.ok((select count(*) = 0 from pipeline.scholarship_ai_reviews where id in (1174, 1176, 1177, 1287) and status <> 'pending'), 'R9 the held items are untouched');
  perform pg_temp.ok(not exists (select 1 from pipeline.fx_calls where fn = 'review_apply'), 'R9 nothing refused or decided');
  c := (select owner_candidates from pipeline.scholarship_owner_proposals where review_id = 1176);
  perform pg_temp.ok(jsonb_array_length(c) = 2 and c->0->>'name' = 'RMIT University Pathways, RMIT UP' and jsonb_array_length(c->1->'holds_same_name') = 1, 'R9 1176 names RMIT UP first; RMIT already holds the bursary');
  c := (select owner_candidates from pipeline.scholarship_owner_proposals where review_id = 1177);
  perform pg_temp.ok(jsonb_array_length(c) = 1 and c->0->>'name' = 'Alphacrucis College', 'R9 1177 names Alphacrucis College (AU), not the NZ record');
  perform pg_temp.ok((select owner_candidates = '[]'::jsonb from pipeline.scholarship_owner_proposals where review_id = 1287), 'R9 a generic word (International) never names an owner');
  perform pg_temp.ok((select owner_candidates = '[]'::jsonb and named = 'ACU Refugee Scholarship' from pipeline.scholarship_owner_proposals where review_id = 1174), 'R9 ACU (no alias held) is left to a person');
  perform pg_temp.ok((select evidence->>'holder' = 'Prime Education Group Pty Ltd' and evidence->>'page_host' = 'coursesearch.studymelbourne.vic.gov.au' and evidence->>'discovery_method' = 'map_search(85)'
                        and (evidence->>'holder_candidates_on_directory_sites')::int = 3 from pipeline.scholarship_owner_proposals where review_id = 1176), 'R9 the evidence names holder, host and how it was found');
  perform pg_temp.ok((security.scholarship_owner_proposals_remedy_v1(null)->'evidence'->>'proposed')::int = 0, 'R9 a second run proposes nothing new');
  perform pg_temp.ok((security.scholarship_sources_verify_v1(null)->>'passed')::boolean, 'R9 verification passes once every item has a proposal');
end $$;

-- R10 owners before credits: a held item with an open owner proposal, or on a directory page, is never read
do $$
declare r jsonb;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(10) where key = 'scholarship.single_read_daily_max';
  r := security.scholarship_read_request_v1(1176, false, 'Fixture: read a directory page', 'Platform Admin, fixture');
  perform pg_temp.ok(r->>'why' like 'directory site%', 'R10 a directory page is refused before any credit');
  insert into pipeline.scholarship_owner_proposals(review_id, url, finding, proposed_action, evidence) values (1230, 'x', 'directory_page', 'refuse_from_holder', '{}');
  r := security.scholarship_read_request_v1(1230, true, 'Fixture: owner in question', 'Platform Admin, fixture');
  perform pg_temp.ok(r->>'why' like 'the owner is in question%', 'R10 an open owner proposal blocks the read');
  delete from pipeline.scholarship_owner_proposals where review_id = 1230;
end $$;

-- R11 a decision on the held item closes its proposal; the report measures each root cause
do $$
declare m jsonb;
begin
  perform security.scholarship_ai_review_apply_v1(1177, 'refuse', null, 'fixture decision', '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  perform security.scholarship_owner_check_v1(10);
  perform pg_temp.ok((select state = 'decided' and decision->>'status' = 'refused' from pipeline.scholarship_owner_proposals where review_id = 1177), 'R11 the decided item''s proposal is closed');
  m := security.scholarship_sources_report_v1();
  perform pg_temp.ok((m->>'held_on_directory_pages')::int = 3 and (m->>'owner_proposals_open')::int = 3, 'R11 report: 3 held on directory pages, 3 proposals open');
  perform pg_temp.ok((m->>'held_duplicating_active')::int = 1, 'R11 report: Macquarie 1184 duplicates active a347e086');
  perform pg_temp.ok((m->>'staging_addresses_active')::int = 1 and (m->>'held_on_staging_addresses')::int = 1, 'R11 report: staging addresses measured');
  perform pg_temp.ok(m->'read_requests' ? 'read' and m->'read_requests' ? 'read_failed' and m->'read_requests' ? 'refused', 'R11 report: requests by state ' || (m->'read_requests')::text);
end $$;

-- R12 registers: root causes and remedies through workstream A's contract; the auto remedy only records
do $$
begin
  perform pg_temp.ok((select count(*) = 5 from pipeline.ops_root_causes where code in ('sch_held_on_directory_page', 'sch_held_read_reuses_old_copy', 'sch_held_duplicates_active', 'sch_source_staging_address', 'course_link_title_only_sibling')), 'R12 five root causes (with IQ-00132, six)');
  perform pg_temp.ok((select authority = 'auto' and action_fn = 'security.scholarship_owner_proposals_remedy_v1(bigint)'::regprocedure from pipeline.ops_remedies where code = 'sch_owner_proposals'), 'R12 sch_owner_proposals is the only auto remedy');
  perform pg_temp.ok((select count(*) = 5 from pipeline.ops_remedies where code in ('sch_owner_decision', 'sch_single_approved_read', 'sch_duplicate_close', 'sch_staging_reread', 'course_link_cricos_identity') and authority in ('admin', 'release')), 'R12 five admin or release remedies');
end $$;

-- E1-E4 (IQ-00132): the enqueue never queues a directory-site candidate or re-read; marks it refused once (not needed); held items are left to Layer 4
do $$
declare n int;
begin
  delete from pipeline.scholarship_ai_queue;
  n := security.scholarship_ai_enqueue_v1('admit', array['159328df-fb4b-4bb8-a6b8-5f24546437a3']::uuid[], null, true);
  perform pg_temp.ok(not exists (select 1 from pipeline.scholarship_ai_queue where security.third_party_host_v1(url)), 'E1 no directory-site row is queued (candidates or re-reads)');
  perform pg_temp.ok(exists (select 1 from pipeline.scholarship_ai_queue where candidate_id = 70002) and exists (select 1 from pipeline.scholarship_ai_queue where scholarship_id = '00000000-0000-0000-0000-00000000aa04'),
                     'E1 the provider''s own pages are still queued');
  perform pg_temp.ok((select admit_status = 'skipped' and admit_reasons = array['directory_site'] from pipeline.scholarship_page_candidates where id = 70001), 'E2 the directory candidate is marked refused once');
  perform pg_temp.ok((select count(*) = 1 from pipeline.scholarship_admission_log where candidate_id = 70001 and action = 'skipped' and detail->>'outcome' = 'not_needed'), 'E2 logged as not needed');
  perform pg_temp.ok((select admit_status is null from pipeline.scholarship_page_candidates where id = 15138), 'E3 a candidate with a pending held item (1174) is left to Layer 4, not marked');
  n := security.scholarship_ai_enqueue_v1('admit', array['159328df-fb4b-4bb8-a6b8-5f24546437a3', '1bdef519-6927-4765-8a06-632d396fa2ae']::uuid[], null, true);
  perform pg_temp.ok((select admit_status = 'skipped' from pipeline.scholarship_page_candidates where id = 15620), 'E3 a candidate whose held item was decided (1177) is marked when met');
  perform pg_temp.ok((select count(*) = 1 from pipeline.scholarship_admission_log where candidate_id = 70001) and not exists (select 1 from pipeline.scholarship_ai_queue where security.third_party_host_v1(url)),
                     'E3 a second enqueue marks nothing again and queues nothing on directory sites');
  perform pg_temp.ok((security.scholarship_sources_report_v1()->>'directory_candidates_queueable')::int = 0, 'E3 report: no directory candidate left queueable');
  -- switched off: queued as before
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'scholarship.enqueue_directory_gate_on';
  update pipeline.scholarship_page_candidates set admit_status = null, admit_reasons = null where id = 70001;
  delete from pipeline.scholarship_ai_queue;
  n := security.scholarship_ai_enqueue_v1('admit', array['159328df-fb4b-4bb8-a6b8-5f24546437a3']::uuid[], null, true);
  perform pg_temp.ok(exists (select 1 from pipeline.scholarship_ai_queue where candidate_id = 70001), 'E4 with the gate off the enqueue behaves as before');
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'scholarship.enqueue_directory_gate_on';
  perform pg_temp.ok((select authority = 'release' from pipeline.ops_remedies where code = 'sch_enqueue_directory_gate')
                     and exists (select 1 from pipeline.ops_root_causes where code = 'sch_enqueue_directory_site'), 'E4 root cause and remedy registered');
end $$;
