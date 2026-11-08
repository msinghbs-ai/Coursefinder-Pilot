-- Guards: Platform Admin Firecrawl priority order 8 Nov 2026 and the hold-message wording (a floor hold is not a "tomorrow" hold); consumer API and Firecrawl budget functions untouched.
-- After migration 20261108150100: the two messages, in the daily-share case and the floor case. Every block raises on a failed check.
\set ON_ERROR_STOP 1
set client_min_messages = notice;
create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$ begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create function pg_temp.setv(p_k text, p_v numeric) returns void language sql as $f$ insert into public.fx_settings values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
insert into pipeline.course_link_search values ('d1000000-0000-4000-8000-000000000000', 'queued', now(), null);

do $t$ declare a jsonb; b jsonb; begin
  -- share used up, floor not binding (room above the floor): the old wording stays, and it is true (live 8 Nov 2026: room 98,711, share 0)
  perform pg_temp.setv('share_left', 0); perform pg_temp.setv('priority_floor_course_search', 1500); perform pg_temp.setv('room', 98711);
  a := security.link_search_block_v1('d1000000-0000-4000-8000-000000000000'); b := public.admin_course_search_queue('d1000000-0000-4000-8000-000000000000');
  perform pg_temp.ok(a->>'code' = 'day_budget' and a->>'words' = 'Today''s Firecrawl share for course search is used' and a->>'fix' = 'Waits for tomorrow''s share', 'task hold unchanged: ' || a::text);
  perform pg_temp.ok(b->>'why' = 'today''s Firecrawl share for course search is used up; it continues tomorrow' and not (b->>'runs')::boolean, 'queue line unchanged: ' || b::text);
  raise notice 'PASS daily share used, floor not binding: the message is as before';
end $t$;

do $t$ declare a jsonb; b jsonb; begin
  -- the floor binds (room under one search): the message says so, names the floor and does not say tomorrow
  perform pg_temp.setv('room', 0.5); perform pg_temp.setv('share_left', 5000);
  a := security.link_search_block_v1('d1000000-0000-4000-8000-000000000000'); b := public.admin_course_search_queue('d1000000-0000-4000-8000-000000000000');
  perform pg_temp.ok(a->>'code' = 'day_budget', 'the hold code is unchanged (policy-hold lists read it): ' || a::text);
  perform pg_temp.ok(a->>'words' like '%higher-priority work%kept back: 1500%' and a->>'fix' like '%back above the floor%Credits kept back from course page search%' and a::text !~* 'tomorrow', 'task hold names the floor: ' || a::text);
  perform pg_temp.ok(b->>'why' like '%priority floor%back above the floor%' and b->>'why' !~* 'tomorrow' and not (b->>'runs')::boolean, 'queue line names the floor: ' || b::text);
  raise notice 'PASS floor holds: the message names the priority floor';
end $t$;

do $t$ declare a jsonb; b jsonb; begin
  -- both bound (share used and floor): the floor is named (it is what a new day does not release)
  perform pg_temp.setv('share_left', 0); perform pg_temp.setv('room', -20);
  a := security.link_search_block_v1('d1000000-0000-4000-8000-000000000000'); b := public.admin_course_search_queue('d1000000-0000-4000-8000-000000000000');
  perform pg_temp.ok(a->>'words' like '%higher-priority work%' and b->>'why' like '%priority floor%', 'floor named when under the floor: ' || a::text);
  raise notice 'PASS under the floor';
end $t$;

do $t$ declare a jsonb; b jsonb; begin
  -- no fresh balance / floor off: room is null, the share wording as before
  perform pg_temp.setv('share_left', 0); delete from public.fx_settings where k = 'room';
  a := security.link_search_block_v1('d1000000-0000-4000-8000-000000000000'); b := public.admin_course_search_queue('d1000000-0000-4000-8000-000000000000');
  perform pg_temp.ok(a->>'fix' = 'Waits for tomorrow''s share' and b->>'why' like '%continues tomorrow', 'no floor in force: the share wording: ' || a::text);
  raise notice 'PASS under the floor, and no floor in force';
end $t$;
