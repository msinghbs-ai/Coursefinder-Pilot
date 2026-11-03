-- Cases of the classification fix (20261104430000).
create or replace function pg_temp.ok(p boolean, p_msg text) returns void language plpgsql as $$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok %', p_msg; end $$;
-- 1 the duplicate listing item is folded into one case, with a deterministic winner, and counted
do $$
declare v jsonb := security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000001']::uuid[]);
begin
  perform pg_temp.ok((v->>'duplicate_cases')::int = 1 and (select count(*) from pipeline.scholarship_coverage_items
                      where item_key = 'list:1:torrens.edu.au/scholarships/international-scholarships/family-scholarship') = 1,
                     'fix: an address listed twice is one case; the duplicate is counted (duplicate_cases 1)');
end $$;
-- 2 deterministic: the same winner on every run
do $$
declare a text; b text;
begin
  select md5(evidence::text) into a from pipeline.scholarship_coverage_items where item_key like 'list:1:%family%';
  perform security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000001']::uuid[]);
  select md5(evidence::text) into b from pipeline.scholarship_coverage_items where item_key like 'list:1:%family%';
  perform pg_temp.ok(a = b, 'fix: the winner is deterministic');
end $$;
-- 3 a report write that fails never aborts the run; it is tried again on the next run
create or replace function pg_temp.boom() returns trigger language plpgsql as $$
begin if new.entity = '10000000-0000-0000-0000-000000000003' then raise exception 'fixture: work item write refused'; end if; return new; end $$;
create trigger fx_boom before insert or update on pipeline.work_items for each row execute function pg_temp.boom();
insert into scholarship.register_listings(register_code, listing_id, provider_id, name, provider_name, website_url, handoff_status)
values ('au_study_australia', 'bh1', '10000000-0000-0000-0000-000000000003', 'Pathway to Victoria Scholarship', 'Box Hill Institute', 'https://www.boxhillgroup.example/pathway', 'provider_page_off_provider_site');
do $$
declare v jsonb := security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000005']::uuid[]);
begin
  perform pg_temp.ok((v->>'ran')::boolean and (v->>'providers')::int = 2 and (v->>'report_errors')::int >= 1 and v->>'report_error_last' like '%work item write refused%',
                     'fix: a failed report write is counted and the run completes for every provider');
  perform pg_temp.ok((select classified_at > now() - interval '1 minute' from pipeline.scholarship_coverage_providers where provider_id = '10000000-0000-0000-0000-000000000005')
                     and not ((select reported from pipeline.scholarship_coverage_providers where provider_id = '10000000-0000-0000-0000-000000000003') ? 'ownership_conflict'),
                     'fix: other providers progress; the failed report is not recorded as sent');
end $$;
drop trigger fx_boom on pipeline.work_items;
do $$
declare v jsonb := security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000003']::uuid[]);
begin
  perform pg_temp.ok((v->>'report_errors')::int = 0 and (v->>'work_reports')::int >= 1
                     and ((select reported from pipeline.scholarship_coverage_providers where provider_id = '10000000-0000-0000-0000-000000000003') ? 'ownership_conflict'),
                     'fix: the next run sends the report that failed');
end $$;
