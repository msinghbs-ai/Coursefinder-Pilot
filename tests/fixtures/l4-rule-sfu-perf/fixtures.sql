-- CF-247 rule executor bounded: every case after the migration (seed.sql). Each block raises on failure and prints "<id> ok".

-- B1 the level reading alone: the course title and study level against the page address and its read title
do $f$
declare a jsonb := security.layer4_rule_level_v1('c0000000-0000-0000-0000-000000000040', 'https://www.sfu.ca/students/calendar/programs/c40/p.html');
        b jsonb := security.layer4_rule_level_v1('c0000000-0000-0000-0000-000000000043', 'https://www.sfu.ca/students/calendar/programs/c43/p.html');
        c jsonb := security.layer4_rule_level_v1('c0000000-0000-0000-0000-000000000044', 'https://www.sfu.ca/students/calendar/programs/c44/p.html');
begin
  if a <> '{"verdict": "level on the page", "checks": {"page_levels": ["B"], "course_levels": ["B"]}}' then raise exception 'B1: c40 %', a; end if;
  if b <> '{"verdict": "level not confirmed", "checks": {"page_levels": [], "course_levels": ["B"]}}' then raise exception 'B1: c43 %', b; end if;
  if c <> '{"verdict": "level not confirmed", "checks": {"page_levels": ["B"], "course_levels": ["M"]}}' then raise exception 'B1: c44 %', c; end if;
  raise notice 'B1 ok: the level reading alone: same level found, page with no level and page for another level told apart';
end $f$;

-- B2 the executor takes item ids first and validates each on its own: a count of 10 decides nothing and reports each item's result
do $f$
declare r jsonb;
begin
  if position('layer4_course_link_rule_validate_v1(r.code, null)' in pg_get_functiondef('security.layer4_course_link_rule_execute_v1(text,integer,boolean)'::regprocedure)) > 0
    then raise exception 'B2: the executor still validates the whole rule group'; end if;
  r := security.layer4_course_link_rule_execute_v1('sfu_no_term', 10, false);
  raise notice 'B2 %', r;
  if (r->>'would_decide')::int <> 3 or (r->>'decided')::int <> 0 or (r->>'not_reached')::int <> 0 then raise exception 'B2: %', r; end if;
  if (select array_to_string(reasons, '; ') from pipeline.layer4_course_link_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000043')
     <> 'course level not verified on the page (course B, page none)' then raise exception 'B2: c43'; end if;
  if (select array_to_string(reasons, '; ') from pipeline.layer4_course_link_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000044')
     <> 'course level not verified on the page (course M, page B)' then raise exception 'B2: c44'; end if;
  if exists (select 1 from pipeline.layer4_review_items where id::text like '10000000-0000-0000-0000-00000000004%' and status <> 'pending') then raise exception 'B2: a count decided'; end if;
  raise notice 'B2 ok: ids first, then one validation per item; a count decides nothing; a level not confirmed fails with its reason';
end $f$;

-- the level reading made slow for c40 (1.2 s) and broken for c42, around the real one
alter function security.layer4_rule_level_v1(uuid, text) rename to layer4_rule_level_real_v1;
create function security.layer4_rule_level_v1(p_course uuid, p_url text) returns jsonb language plpgsql stable as $s$
begin
  if p_course = 'c0000000-0000-0000-0000-000000000040' then perform pg_sleep(1.2); end if;
  if p_course = 'c0000000-0000-0000-0000-000000000042' then raise exception 'level reading failed'; end if;
  return security.layer4_rule_level_real_v1(p_course, p_url);
end $s$;
update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.rule_execute_time_budget_s';

-- B3 one slow item does not stop the batch: the call ends within its budget, the slow item is decided on its merits, the items not reached stay
-- waiting and come first next time, and a level reading that fails never lets an item pass
do $f$
declare r jsonb; t0 timestamptz := clock_timestamp();
begin
  r := security.layer4_course_link_rule_execute_v1('sfu_no_term', 50, true);
  raise notice 'B3 first call %', r;
  if clock_timestamp() - t0 > interval '3 seconds' then raise exception 'B3: the call ran past its budget'; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000040') <> 'approved' then raise exception 'B3: the slow item'; end if;
  if (r->>'not_reached')::int < 1 then raise exception 'B3: nothing left for the next call %', r; end if;
  if exists (select 1 from pipeline.layer4_review_items where id in ('10000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000042') and status <> 'pending')
     and (select count(*) from pipeline.layer4_course_link_rule_run_items where run_id = (r->>'run_id')::bigint and item_id in ('10000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000042')) = 0
     then raise exception 'B3: an item not reached was decided'; end if;
end $f$;
do $f$
declare r jsonb;
begin
  r := security.layer4_course_link_rule_execute_v1('sfu_no_term', 50, true);
  raise notice 'B3 next call %', r;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000041') <> 'approved' then raise exception 'B3: c41 was not taken next'; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000042') <> 'pending'
     or not exists (select 1 from pipeline.layer4_course_link_rule_run_items where item_id = '10000000-0000-0000-0000-000000000042' and outcome = 'failed'
                    and array_to_string(reasons, ' ') like '%level reading failed%') then raise exception 'B3: a failed level reading'; end if;
  if (select string_agg(status, ',' order by id) from pipeline.layer4_review_items where id in ('10000000-0000-0000-0000-000000000043', '10000000-0000-0000-0000-000000000044')) <> 'pending,pending'
    then raise exception 'B3: an unconfirmed level was decided'; end if;
  if (select count(*) from pipeline.layer4_decisions where review_item_id::text like '10000000-0000-0000-0000-00000000004%') <> 2 then raise exception 'B3: one decision per item'; end if;
  raise notice 'B3 ok: a slow item is decided and the call stops at its budget; the items not reached come first next time; a failed or unconfirmed level never passes';
end $f$;
