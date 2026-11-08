-- Cases after 20261108160000. Each block raises on failure and prints NOTICE "ok ..." on success.
create or replace function pg_temp.ok(p boolean, p_msg text) returns void language plpgsql as $$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok %', p_msg; end $$;
create or replace function pg_temp.set(p_key text, p_v numeric) returns void language sql as $$
  update pipeline.platform_toolset_settings set value = to_jsonb(p_v) where toolset_key = 'pipeline' and key = p_key $$;
create or replace function pg_temp.pst(p text) returns text language sql as $$ select state from pipeline.scholarship_coverage_items where provider_id = p::uuid and item_key = 'provider' and present $$;
create or replace function pg_temp.pstate(p text) returns text language sql as $$ select provider_state from pipeline.scholarship_coverage_providers where provider_id = p::uuid $$;
create or replace function pg_temp.days(p_id bigint) returns numeric language sql as $$ select round(extract(epoch from (next_read_at - now())) / 86400) from pipeline.scholarship_listing_pages where id = p_id $$;
create or replace function pg_temp.cand(p_id bigint) returns text language sql as $$ select attempts || '/' || read_status from pipeline.scholarship_page_candidates where id = p_id $$;

-- 1 the switches and the settings --------------------------------------------------------------------------------------------------------------------
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where key in ('sch_cov.recover_listings_on', 'retry.scholarship_transient_recover_on') and (value #>> '{}')::numeric = 0) = 2,
                  'the two switches that spend ship 0');
select pg_temp.ok((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'sch_cov.scope_states_on') = 1, 'the classification-only switch ships 1');
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where key in ('sch_cov.scope_states_on', 'reread.scholarship_listing_unchanged_days', 'retry.scholarship_transient_recover_on',
                   'retry.scholarship_transient_park_hours', 'retry.scholarship_transient_cycles_max', 'batch.scholarship_transient_recover')
                   and label is not null and unit is not null and used_by is not null and min_value is not null and max_value is not null and reason is not null) = 6, 'G2: six new settings, each with label, range, unit, used_by and reason');
select pg_temp.ok((select count(*) from pipeline.scholarship_coverage_state_codes) = 15 and (select count(*) from pipeline.scholarship_coverage_state_codes where code in ('searched_none', 'not_in_scope') and resolved and escalate_when = 'never') = 2,
                  '15 coverage states; the two new ones are resolved and never escalate');
select pg_temp.ok(not exists (select 1 from cron.job where jobname in ('scholarship-listing-accept', 'scholarship-transient-recover') and command ~ '[(,]\s*[0-9]'), 'G2: the two job commands carry no number');
select pg_temp.ok((select count(*) from pipeline.automation_catalogue where jobname in ('scholarship-listing-accept', 'scholarship-transient-recover')) = 2, 'G1: both jobs are catalogued');

-- 2 why a provider is in or out of scholarship search -------------------------------------------------------------------------------------------------
select pg_temp.ok(security.scholarship_scope_v1('20000000-0000-0000-0000-000000000001') = 'in_scope', 'scope: Alpha is in scope');
select pg_temp.ok(security.scholarship_scope_v1('20000000-0000-0000-0000-000000000011') = 'country_or_type_not_admitted', 'scope: a Canadian private provider is not admitted');
select pg_temp.ok(security.scholarship_scope_v1('20000000-0000-0000-0000-000000000004') = 'no_website', 'scope: no website');
select pg_temp.ok(security.scholarship_scope_v1('20000000-0000-0000-0000-000000000005') = 'no_active_courses', 'scope: no active course');
select pg_temp.ok(security.scholarship_scope_v1('20000000-0000-0000-0000-000000000007') = 'discovery_not_eligible', 'scope: discovery not eligible');
select pg_temp.ok(security.scholarship_scope_v1('20000000-0000-0000-0000-000000000012') = 'in_scope', 'scope: a university with a website and courses and no discovery row yet is in scope');
select pg_temp.ok(security.scholarship_scope_v1('00000000-0000-0000-0000-00000000dead') = 'unknown_provider', 'scope: an unknown provider is named, not guessed');

-- 3 the provider cases: out of scope, searched none, not discovered --------------------------------------------------------------------------------------
select security.scholarship_coverage_classify_v1(array['20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000012']::uuid[]);
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000001') = 'searched_none', 'Alpha: a successful map with nothing kept reads searched_none');
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000002') = 'source_not_discovered', 'Beta: an "empty" row whose method is map:budget is not a search, it stays source_not_discovered');
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000011') = 'not_in_scope', 'Lambda: a Canadian private provider (type not admitted) reads not_in_scope');
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000004') = 'not_in_scope', 'Delta: no website reads not_in_scope');
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000005') = 'not_in_scope', 'Epsilon: no active course reads not_in_scope');
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000012') = 'source_not_discovered', 'Mu: in scope and never queued stays source_not_discovered (a real gap)');
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000007') = 'not_in_scope', 'Eta: discovery not_eligible reads not_in_scope');
select pg_temp.ok(pg_temp.pstate('20000000-0000-0000-0000-000000000001') = 'searched_none' and pg_temp.pstate('20000000-0000-0000-0000-000000000011') = 'not_in_scope'
                  and pg_temp.pstate('20000000-0000-0000-0000-000000000002') = 'source_not_discovered', 'the provider state follows the case');
select pg_temp.ok((select evidence->>'scope' from pipeline.scholarship_coverage_items where provider_id = '20000000-0000-0000-0000-000000000004' and item_key = 'provider') = 'no_website', 'the case evidence names the scope reason');
select pg_temp.ok(not exists (select 1 from pipeline.work_items where lane = 'sch_coverage' and work_kind in ('state:searched_none', 'state:not_in_scope') and stage not in ('succeeded', 'closed')),
                  'a resolved state opens no work item that stays open');
select pg_temp.ok(exists (select 1 from pipeline.work_items where lane = 'sch_coverage' and entity = '20000000-0000-0000-0000-000000000002' and work_kind = 'state:source_not_discovered'),
                  'Beta (a refused map) still has its open work item: the real defect is not hidden');
-- the switch off restores the old reading
select pg_temp.set('sch_cov.scope_states_on', 0);
select security.scholarship_coverage_classify_v1(array['20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000011']::uuid[]);
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000001') = 'source_not_discovered' and pg_temp.pst('20000000-0000-0000-0000-000000000011') = 'source_not_discovered', 'sch_cov.scope_states_on 0: every such provider reads source_not_discovered again');
select pg_temp.set('sch_cov.scope_states_on', 1);
select security.scholarship_coverage_classify_v1(array['20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000011']::uuid[]);
select pg_temp.ok(pg_temp.pst('20000000-0000-0000-0000-000000000001') = 'searched_none', 'switched back on, the states return');

-- 4 suggested listings of eligible providers (sch_cov.recover_listings_on) ------------------------------------------------------------------------------
create or replace function pg_temp.acc() returns jsonb language sql as $$ select security.scholarship_listing_accept_v1() $$;
create or replace function pg_temp.n_acc() returns int language sql as $$ select count(*)::int from pipeline.scholarship_listing_pages where source = 'auto' and active and id <= 8 $$;
select pg_temp.ok((pg_temp.acc()->>'ran')::boolean is false and pg_temp.n_acc() = 0, 'R0 switch 0: nothing is accepted');
select pg_temp.set('sch_cov.recover_listings_on', 1);
insert into pipeline.fx_lane_hold values ('sch_scrape', 'daily scholarship share spent');
select pg_temp.ok((pg_temp.acc()->>'ran')::boolean is false and pg_temp.acc()->>'hold' = 'daily scholarship share spent' and pg_temp.n_acc() = 0, 'R1 the scholarship Firecrawl share is held: nothing is accepted');
delete from pipeline.fx_lane_hold;
insert into pipeline.fx_held values ('20000000-0000-0000-0000-000000000010');
do $$
declare v jsonb := pg_temp.acc();
begin
  perform pg_temp.ok((v->>'accepted')::int = 3 and (v->>'skipped')::int = 4, 'R2 three of Theta (the per-provider cap); Iota (search off), Gamma (not admitted), both Kappa (held) skipped: ' || v::text);
  perform pg_temp.ok((select count(*) from pipeline.scholarship_listing_pages where id in (1, 2, 3) and source = 'auto' and active and status = 'waiting' and next_read_at <= now()) = 3
                     and (select source from pipeline.scholarship_listing_pages where id = 4) = 'suggested', 'the oldest three Theta pages are listing sources due now; the fourth waits');
end $$;
update catalogue.providers set publication_status = 'draft' where id = '20000000-0000-0000-0000-000000000010';
delete from pipeline.fx_held;
select pg_temp.set('batch.sch_coverage_recover', 1);
do $$
declare v jsonb := pg_temp.acc();
begin
  perform pg_temp.ok((v->>'accepted')::int = 1 and (select source from pipeline.scholarship_listing_pages where id = 4) = 'auto' and (select source from pipeline.scholarship_listing_pages where id = 7) = 'suggested',
                     'R3 batch cap 1 and Kappa hidden: only Theta''s fourth page is accepted: ' || v::text);
end $$;
update catalogue.providers set publication_status = 'published' where id = '20000000-0000-0000-0000-000000000010';
select pg_temp.set('batch.sch_coverage_recover', 10);
do $$
declare v jsonb := pg_temp.acc();
begin
  perform pg_temp.ok((v->>'accepted')::int = 1 and (select source from pipeline.scholarship_listing_pages where id = 7) = 'auto', 'R4 Kappa''s own-site page is accepted once published: ' || v::text);
  perform pg_temp.ok((select source from pipeline.scholarship_listing_pages where id = 8) = 'suggested' and (select source from pipeline.scholarship_listing_pages where id = 5) = 'suggested'
                     and (select source from pipeline.scholarship_listing_pages where id = 6) = 'suggested', 'a page off the provider''s own site, a switched-off provider and a non-admitted provider stay suggested');
  v := pg_temp.acc();
  perform pg_temp.ok((v->>'accepted')::int = 0, 'R5 a second run accepts nothing more');
  perform pg_temp.ok((select count(*) from pipeline.scholarship_coverage_recoveries where action = 'promote_listing') = 5 and (select count(distinct item_key) from pipeline.scholarship_coverage_recoveries where action = 'promote_listing') = 5,
                     'each accepted listing is recorded once (promote_listing)');
end $$;
select pg_temp.set('sch_cov.recover_listings_on', 0);

-- 5 an unchanged catalogue is not read every week ---------------------------------------------------------------------------------------------------------
do $$
declare w jsonb := '{"state": "complete", "pages_read": 2, "total_stated": 2}'::jsonb; ab jsonb := '[{"name": "Alpha Award"}, {"name": "Beta Award"}]'::jsonb;
begin
  perform public.svc_scholarship_listing_record_v2(9, 'read', 200, ab, null, w);
  perform pg_temp.ok(pg_temp.days(9) = 7, 'the first read of a catalogue is read again in 7 days');
  perform public.svc_scholarship_listing_record_v2(9, 'read', 200, ab, null, w);
  perform pg_temp.ok(pg_temp.days(9) = 30, 'the same complete catalogue is read again in 30 days (reread.scholarship_listing_unchanged_days)');
  perform public.svc_scholarship_listing_record_v2(9, 'read', 200, '[{"name": "Alpha Award"}, {"name": "Gamma Award"}]'::jsonb, null, w);
  perform pg_temp.ok(pg_temp.days(9) = 7, 'a changed catalogue keeps the 7-day cadence');
  perform pg_temp.set('reread.scholarship_listing_unchanged_days', 45);
  perform public.svc_scholarship_listing_record_v2(9, 'read', 200, '[{"name": "Alpha Award"}, {"name": "Gamma Award"}]'::jsonb, null, w);
  perform pg_temp.ok(pg_temp.days(9) = 45, 'the unchanged interval is the setting, not code');
  perform pg_temp.set('reread.scholarship_listing_unchanged_days', 30);
  perform public.svc_scholarship_listing_record_v2(9, 'read', 200, '[{"name": "Alpha Award"}, {"name": "Gamma Award"}]'::jsonb, null, '{"state": "partial", "pages_read": 1, "total_stated": 5, "next_url": "https://www.zeta.edu.au/scholarships?page=2"}'::jsonb);
  perform pg_temp.ok(pg_temp.days(9) = 0, 'a partly read catalogue keeps its own (hourly) cadence even when the names match');
  perform public.svc_scholarship_listing_record_v2(9, 'failed', 500, null, 'server error', null);
  perform pg_temp.ok(pg_temp.days(9) = 1, 'a failed read keeps the retry cadence');
end $$;

-- 6 park and recover (IQ-00129) ------------------------------------------------------------------------------------------------------------------------------
-- earlier cycles: candidate 6 had its one cycle and failed again; candidate 9 was retried and then read
insert into pipeline.scholarship_read_retry_cycles(candidate_id, cycle, provider_id, reason_class, http_status, released_at, outcome, outcome_at) values
  (6, 1, '20000000-0000-0000-0000-000000000008', 'server', 500, now() - interval '8 days', 'failed_again', now() - interval '7 days');
insert into pipeline.scholarship_read_retry_cycles(candidate_id, cycle, provider_id, reason_class, http_status, released_at) values
  (9, 1, '20000000-0000-0000-0000-000000000008', 'server', 500, now() - interval '2 days');
create or replace function pg_temp.rec() returns jsonb language sql as $$ select security.scholarship_transient_recover_v1() $$;
do $$
declare v jsonb := pg_temp.rec();
begin
  perform pg_temp.ok((v->>'ran')::boolean is false and (v->>'outcomes_recorded')::int = 1 and (select outcome from pipeline.scholarship_read_retry_cycles where candidate_id = 9) = 'read',
                     'T0 switch 0: nothing is retried, but the outcome of an earlier cycle is recorded (read)');
  perform pg_temp.ok(pg_temp.cand(1) = '3/scrape_failed' and pg_temp.cand(2) = '3/scrape_failed' and pg_temp.cand(7) = '3/scrape_failed', 'T0 no page was touched');
end $$;
select pg_temp.set('retry.scholarship_transient_recover_on', 1);
insert into pipeline.fx_lane_hold values ('sch_scrape', 'daily scholarship share spent');
do $$
declare v jsonb := pg_temp.rec();
begin
  perform pg_temp.ok((v->>'ran')::boolean is false and pg_temp.cand(1) = '3/scrape_failed', 'T1 the scholarship Firecrawl share is held: nothing is retried');
end $$;
delete from pipeline.fx_lane_hold;
do $$
declare v jsonb := pg_temp.rec();
begin
  perform pg_temp.ok((v->>'released')::int = 3 and (v->>'skipped')::int = 3, 'T2 three pages released (the per-provider cap); Gamma (not admitted), Iota (search off) and the aggregator page skipped: ' || v::text);
  perform pg_temp.ok(pg_temp.cand(1) = '0/scrape_failed' and pg_temp.cand(2) = '0/scrape_failed' and pg_temp.cand(7) = '0/scrape_failed', 'the released pages go back to the normal reader with a fresh set of reads');
  perform pg_temp.ok(pg_temp.cand(3) = '3/scrape_failed', 'a page that failed an hour ago is still parked (retry.scholarship_transient_park_hours)');
  perform pg_temp.ok(pg_temp.cand(4) = '3/blocked' and pg_temp.cand(5) = '3/gone', 'a refusal (403) and a missing page (404) are not transient and are left');
  perform pg_temp.ok(pg_temp.cand(6) = '3/scrape_failed' and (select count(*) from pipeline.scholarship_read_retry_cycles where candidate_id = 6) = 1, 'a page that has used its cycle is not released again');
  perform pg_temp.ok((select reason_class from pipeline.scholarship_read_retry_cycles where candidate_id = 1) = 'server' and (select reason_class from pipeline.scholarship_read_retry_cycles where candidate_id = 2) = 'budget'
                     and (select reason_class from pipeline.scholarship_read_retry_cycles where candidate_id = 7) = 'no_answer', 'each cycle records its failure class (server, budget, no answer)');
  perform pg_temp.ok(pg_temp.cand(10) = '3/scrape_failed' and pg_temp.cand(11) = '3/scrape_failed' and pg_temp.cand(12) = '3/scrape_failed', 'no page of an ineligible, switched-off or aggregator source is released');
end $$;
do $$
declare v jsonb := pg_temp.rec();
begin
  perform pg_temp.ok((v->>'released')::int = 1 and (select reason_class from pipeline.scholarship_read_retry_cycles where candidate_id = 8) = 'timeout', 'T3 the next run releases the fourth Theta page (a timeout), within the cap');
  v := pg_temp.rec();
  perform pg_temp.ok((v->>'released')::int = 0, 'T3b a further run releases nothing: pages awaiting their outcome are not retried');
end $$;
-- candidate 1 fails again after its cycle; candidate 2 is read
update pipeline.scholarship_page_candidates set attempts = 3, read_status = 'scrape_failed', http_status = 500, read_at = now() - interval '3 days' where id = 1;
update pipeline.scholarship_page_candidates set read_status = 'read', http_status = 200, attempts = 1, read_at = now() where id = 2;
do $$
declare v jsonb := pg_temp.rec();
begin
  perform pg_temp.ok((v->>'released')::int = 0 and (v->>'outcomes_recorded')::int = 2 and (select outcome from pipeline.scholarship_read_retry_cycles where candidate_id = 1 and cycle = 1) = 'failed_again'
                     and (select outcome from pipeline.scholarship_read_retry_cycles where candidate_id = 2 and cycle = 1) = 'read',
                     'T4 outcomes are recorded (failed again, read) and a page at its cycle limit is not released again: ' || v::text);
end $$;
select pg_temp.set('retry.scholarship_transient_cycles_max', 2);
do $$
declare v jsonb := pg_temp.rec();
begin
  perform pg_temp.ok((v->>'released')::int = 2 and (select count(*) from pipeline.scholarship_read_retry_cycles where cycle = 2) = 2, 'T5 raising the cycle limit to 2 gives the two pages that failed again one more cycle: ' || v::text);
  perform pg_temp.ok(pg_temp.cand(4) = '3/blocked' and pg_temp.cand(5) = '3/gone', 'a refusal and a missing page are never released, whatever the limit');
end $$;
select pg_temp.set('retry.scholarship_transient_recover_on', 0);
select pg_temp.set('retry.scholarship_transient_cycles_max', 1);
