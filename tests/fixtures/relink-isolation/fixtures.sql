-- CF-247 SS-021 course-relink university isolation: cases on the fixture database run.sh builds. Every case raises on failure.
\set ON_ERROR_STOP 1
create or replace function fx.ok(p boolean, p_label text) returns void language plpgsql as $f$
begin
  if p is distinct from true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok: %', p_label;
end $f$;
create or replace function fx.wi(p_entity text) returns pipeline.work_items language sql as
  $f$ select * from pipeline.work_items where lane = 'course_relink' and entity = p_entity and work_kind = 'relink' $f$;

-- R1 same answers, prepared once: the edited step gives the live step's candidates, sources and binds, and works out title forms once a course
select security.course_relink_provider_v1('00000000-0000-0000-0000-0000000000a2', 100);
select fx.ok((select n from fx.slugs_calls) = 6, 'R1 title forms worked out once a course (6), not once an address and course');
select fx.ok(not exists ((select course_id, provider_id, state, candidates, sources, reason from pipeline.course_relink except select * from fx.before)
                         union all (select * from fx.before except select course_id, provider_id, state, candidates, sources, reason from pipeline.course_relink)), 'R1 the same candidates, sources and states as the live step');
select fx.ok(not exists ((select course_id, url, basis from fx.binds except select * from fx.before_binds) union all (select * from fx.before_binds except select course_id, url, basis from fx.binds)), 'R1 the same binds as the live step');
select fx.ok((select candidates from pipeline.course_relink where course_id = '00000000-0000-0000-0002-000000000001') = '["https://c26.example/old/c26"]'
             and (select state from pipeline.course_relink where course_id = '00000000-0000-0000-0002-000000000006') = 'absent', 'R1 page swap found; the blocked page is not a candidate');
delete from pipeline.course_relink; delete from pipeline.course_link_search; delete from fx.binds; update fx.slugs_calls set n = 0;

-- R2 a university's deadline: it stops between courses and the run goes on to the others
update pipeline.platform_toolset_settings set value = to_jsonb(2) where key = 'wc.relink_university_seconds';  -- fixture only: under its range so the case runs quickly
create temp table r2 as select security.course_relink_tick_v1(100) res;
select fx.ok((select count(*) from pipeline.course_relink where provider_id = '00000000-0000-0000-0000-0000000000a1') between 1 and 2, 'R2 the slow university stopped at its deadline after settling some courses');
select fx.ok((select count(*) from pipeline.course_relink where provider_id = '00000000-0000-0000-0000-0000000000a2') = 6
             and (select count(*) from pipeline.course_relink where provider_id = '00000000-0000-0000-0000-0000000000a3') = 2, 'R2 the universities before and after it were relinked in the same run');
select fx.ok((fx.wi('00000000-0000-0000-0000-0000000000a1')).stage = 'done', 'R2 a university that settled some courses is done for this turn (goes to the back)');
select fx.ok(current_setting('cf247.relink_deadline', true) is null or current_setting('cf247.relink_deadline', true) = '', 'R2 the deadline does not outlive the run');

-- R3 a university that settles nothing within its time is recorded as a transient failure with its evidence
delete from pipeline.course_relink; delete from pipeline.course_link_search; delete from pipeline.work_items where lane = 'course_relink';
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'wc.relink_university_seconds';
create or replace function security.course_relink_slugs_v1(p_title text) returns text[] language plpgsql volatile as $f$
begin
  update fx.slugs_calls set n = n + 1;
  if p_title like '%Slow%' then perform pg_sleep(3); end if;
  return array[regexp_replace(regexp_replace(lower(coalesce(p_title, '')), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g')];
end $f$;
-- fixture only: a time already used up when each university starts, so none settles a course
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'wc.relink_university_seconds';
select security.course_relink_tick_v1(100);
select fx.ok((fx.wi('00000000-0000-0000-0000-0000000000a2')).stage = 'retry_wait' and (fx.wi('00000000-0000-0000-0000-0000000000a2')).failure_class = 'transient'
             and (fx.wi('00000000-0000-0000-0000-0000000000a2')).evidence->-1->>'message' like 'no course settled within%', 'R3 settled nothing in its time: transient failure, backoff, evidence');
select fx.ok(not exists (select 1 from pipeline.course_relink), 'R3 nothing half-done is left');
update pipeline.platform_toolset_settings set value = to_jsonb(20) where key = 'wc.relink_university_seconds';

-- R4 last resort: the statement limit fires inside the slow university; only it is rolled back and recorded; the run commits the others'
delete from pipeline.course_relink; delete from pipeline.course_link_search; delete from pipeline.work_items where lane = 'course_relink';
create or replace function security.course_relink_slugs_v1(p_title text) returns text[] language plpgsql volatile as $f$
begin
  update fx.slugs_calls set n = n + 1;
  if p_title like '%Slow%' then perform pg_sleep(10); end if;  -- one course longer than the statement limit
  return array[regexp_replace(regexp_replace(lower(coalesce(p_title, '')), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g')];
end $f$;
set statement_timeout = '4s';
create temp table r4 as select security.course_relink_tick_v1(100) res;
reset statement_timeout;
select fx.ok((select res->>'stopped' from r4) = 'statement_timeout', 'R4 the run ended at the slow university without failing');
select fx.ok((select count(*) from pipeline.course_relink where provider_id = '00000000-0000-0000-0000-0000000000a2') = 6, 'R4 the university before it stays committed');
select fx.ok(not exists (select 1 from pipeline.course_relink where provider_id = '00000000-0000-0000-0000-0000000000a1'), 'R4 the slow university''s partial work is rolled back');
select fx.ok((fx.wi('00000000-0000-0000-0000-0000000000a1')).stage = 'retry_wait' and (fx.wi('00000000-0000-0000-0000-0000000000a1')).evidence->-1->>'sqlstate' = '57014'
             and (fx.wi('00000000-0000-0000-0000-0000000000a1')).next_eligible_at > now(), 'R4 the slow university is recorded (57014) and waits for its backoff');
-- the next run skips it and relinks the remaining university
set statement_timeout = '4s';
create temp table r5 as select security.course_relink_tick_v1(100) res;
reset statement_timeout;
select fx.ok((select count(*) from pipeline.course_relink where provider_id = '00000000-0000-0000-0000-0000000000a3') = 2
             and not exists (select 1 from pipeline.course_relink where provider_id = '00000000-0000-0000-0000-0000000000a1'), 'R4 the next run relinks the next university and skips the slow one');
-- attempts end in parked (no infinite retries)
update pipeline.work_items set attempts = (select security.pipeline_num_v1('wc.transient_max_attempts', 5))::int - 1, next_eligible_at = now() - interval '1 minute', stage = 'retry_wait'
 where lane = 'course_relink' and entity = '00000000-0000-0000-0000-0000000000a1';
set statement_timeout = '4s';
select security.course_relink_tick_v1(100);
reset statement_timeout;
select fx.ok((fx.wi('00000000-0000-0000-0000-0000000000a1')).stage = 'parked' and (fx.wi('00000000-0000-0000-0000-0000000000a1')).lease_until is null, 'R4 after its attempts the slow university is parked with evidence');
