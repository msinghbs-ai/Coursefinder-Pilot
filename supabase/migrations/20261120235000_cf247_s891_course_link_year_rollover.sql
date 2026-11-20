-- CF-247 S1-CourseLink-2027-CRICOS s891 (Platform Admin 20 Nov 2026 22:58 AEDT): rule course_link_year_rollover_v1. A held official course page whose address
-- carries a past curriculum year is tried at the upcoming year (2027), the current year (2026), the year before (2025) and then at the address held; the newest
-- address that answers a plain read on the same host, is not a "not found" or "no longer offered" page, and is proved to be this course's page by the platform's
-- identity rule (the exact CRICOS code in Australia; a programme or adapter code elsewhere) is admitted, with the page kept as a stored copy at once, so the $0
-- deterministic sweeps (AER, ELR, fees and intakes, structure) read it. $0: plain reads only (never Firecrawl), no model.
-- What was read live (20 Nov 2026 23:45-23:59 AEDT, read-only; rolled-back dry runs and the signed-in Layer 4 rule groups):
--   545 Course link items wait; 158 hold a page whose address carries a year ("The page we show carries the year YYYY in its address and may be an archived
--   handbook"): 2012 1, 2014 3, 2015 6, 2016 4, 2017 11, 2018 12, 2019 34, 2020 12, 2021 18, 2022 16, 2023 21, 2024 20. Macquarie 51, ANU 33, Melbourne 27,
--   Sydney 19, La Trobe 18 (for example handbook.latrobe.edu.au/courses/2023/PHDLJ, CRICOS 0100697), 10 others. All 158 carry a CRICOS code; none is under a
--   manual lock. Rule l4-link-accept-v1 holds every one of them (an old year is never used by that rule). Its stored pages: 91 read directly, 55 through
--   Firecrawl, 12 never read.
-- What this change does:
--   1 Settings (Settings > Pipeline settings > Layer 4): switch, batch, pages per call, calls in flight, retry days, minimum page text, the "not found" and
--     "no longer offered" words, fetches at once, and the minutes after which an unanswered call is given up.
--   2 pipeline.link_rollover_requests (one row per worker call) and pipeline.link_rollover_checks (one row per held item: what was tried, what was found,
--     what was decided). Nothing is deleted from either.
--   3 security.link_rollover_claim_v1 (the held items to try), security.link_rollover_record_v1 (decides each answer through the existing decision path,
--     public.layer4_review_decide, under the system automation account as rule l4-link-accept-v1 does; then points the course-page binder at the admitted
--     address and records the stored copy through public.svc_coverage_read_record, so no re-read is needed) and security.link_rollover_tick_v1 (reads the
--     answers back, gives up calls with no answer, sends the next batch to the coverage-sweep worker, mode link_year_rollover).
--   4 No new job: the job link-refresh (every 10 minutes, the course link re-check) runs security.link_refresh_with_rollover_v1, which runs the link refresh
--     exactly as before and then one rollover tick (a rollover error never stops the link refresh). Active cron jobs stay at 136.
--   A page is never admitted when the course's page is locked by hand, the page was refused for the course before, the final address is not on the
--   provider's own host (security.provider_page_host_v1), or the address is an archived handbook (a path segment "archive", worker rule). Everything else stays
--   in Layer 4 with what was tried.
-- Platform Admin decision recorded (22:58): a held address with a past year may be admitted when it answers and proves the exact CRICOS code, removing the
-- blanket year hold for that page; a newer year is always tried first.
-- Not changed: the consumer API (G3 75 functions and 48 relations, read before and after; official course links are data the API already reads), the manual
-- locks (7,585, checked before and after), rule l4-link-accept-v1, the coverage reader. Nothing dropped or deleted.
-- G1: no new job; the catalogue row of link-refresh says what it now runs. G2: every value is a setting; the job command holds no number but a default.
-- Numbering: spec s891 to s893 (s884-s886 S1-ELR-Central, s890 S1-RM-Design); migration 20261120235000, above the live head 20261120231000.
-- Replaces: the command of job link-refresh (security.link_refresh_tick_v1 alone becomes security.link_refresh_with_rollover_v1, which calls it unchanged).
-- Retires: nothing.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'guard: the manual locks are not 7,585 before this change'; end if;
  if to_regprocedure('security.link_refresh_tick_v1(integer)') is null then raise exception 'guard: security.link_refresh_tick_v1(integer) is missing'; end if;
  if (select command from cron.job where jobname = 'link-refresh') is distinct from 'select security.link_refresh_tick_v1(security.pipeline_num_v1(''batch.link_refresh'', 500)::int)' then
    raise exception 'guard: the job link-refresh does not run the command this change was written against';
  end if;
  if to_regprocedure('public.layer4_review_decide(uuid,text,text,jsonb)') is null or to_regprocedure('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)') is null
     or to_regprocedure('pipeline.svc_pilot_submit_nonce(text,jsonb)') is null or to_regprocedure('security.provider_page_host_v1(uuid,text)') is null
     or to_regprocedure('security.layer4_item_page_v1(text,jsonb,jsonb)') is null or to_regprocedure('security.coverage_country(uuid)') is null then
    raise exception 'guard: a function this change calls is missing';
  end if;
end $g$;

-- 1 settings -----------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'link_rollover.on', 'Course link year rollover: on',
  '1: held official course pages whose address carries a past year are tried at the upcoming, current and previous year, then as held, and the newest one that proves this course''s page (exact CRICOS code) is admitted; 0: nothing is sent.',
  'number', '1'::jsonb, 0, 1, 'switch', 520, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_tick_v1, job link-refresh'),
 ('pipeline', 'batch.link_rollover', 'Course link year rollover: items per run',
  'How many held Course link items one run sends to be tried.',
  'number', '60'::jsonb, 1, 400, 'items', 521, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_tick_v1'),
 ('pipeline', 'link_rollover.items_per_call', 'Course link year rollover: items per worker call',
  'Items in one call to the coverage-sweep worker (each tries up to four addresses).',
  'number', '15'::jsonb, 1, 40, 'items', 522, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_tick_v1'),
 ('pipeline', 'link_rollover.in_flight_max', 'Course link year rollover: calls in flight',
  'Worker calls that may wait for an answer at the same time.',
  'number', '4'::jsonb, 1, 20, 'calls', 523, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_tick_v1'),
 ('pipeline', 'link_rollover.retry_days', 'Course link year rollover: days before an item is tried again',
  'An item where no address proved the course waits this many days before it is tried again (a new year''s page may appear).',
  'number', '7'::jsonb, 1, 90, 'days', 524, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_claim_v1'),
 ('pipeline', 'link_rollover.min_chars', 'Course link year rollover: minimum page text',
  'A page with less text than this needs a browser to read (unless the university''s adapter reads its own data), so it is not admitted at $0.',
  'number', '1500'::jsonb, 200, 20000, 'characters', 525, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_tick_v1, worker mode link_year_rollover'),
 ('pipeline', 'link_rollover.page_markers', 'Course link year rollover: words that mean the page is not a live course page',
  'A page whose text contains one of these is not admitted ({year} is the year tried).',
  'list', '["page not found", "page cannot be found", "the page you requested", "no longer offered", "has been discontinued", "is discontinued", "not currently offered", "not offered in {year}", "no longer available"]'::jsonb,
  0, null, 'phrases', 526, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_tick_v1, worker mode link_year_rollover'),
 ('pipeline', 'link_rollover.fetches_at_once', 'Course link year rollover: courses read at once',
  'Courses one worker call reads at the same time (each address of a course is read one after another).',
  'number', '4'::jsonb, 1, 8, 'courses', 527, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'worker mode link_year_rollover'),
 ('pipeline', 'link_rollover.request_lost_minutes', 'Course link year rollover: minutes before an unanswered call is given up',
  'A call with no answer after this long is given up and its items are tried again.',
  'number', '30'::jsonb, 5, 240, 'minutes', 528, 'CF-247 s891, Platform Admin 20 Nov 2026 22:58', 'Layer 4', 'security.link_rollover_tick_v1')
on conflict (toolset_key, key) do nothing;

-- 2 tables --------------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.link_rollover_requests (
  id           bigint primary key,
  items        int not null,
  status       text not null default 'sent' check (status in ('sent', 'done', 'failed', 'lost')),
  submitted_at timestamptz not null default now(),
  finished_at  timestamptz,
  result       jsonb
);
comment on table pipeline.link_rollover_requests is 'CF-247 s891 (Platform Admin 20 Nov 2026 22:58): one row per call of rule course_link_year_rollover_v1 to the coverage-sweep worker (mode link_year_rollover); id is the pg_net request. Written and read by security.link_rollover_tick_v1. Never deleted.';
alter table pipeline.link_rollover_requests enable row level security;
revoke all on pipeline.link_rollover_requests from public, anon, authenticated;

create table if not exists pipeline.link_rollover_checks (
  item_id     uuid primary key,
  course_id   uuid not null,
  held_url    text not null,
  outcome     text not null check (outcome in ('sent', 'admitted_newer_year', 'admitted_held_address', 'not_proved', 'locked', 'refused_before', 'not_own_host',
                                                 'not_waiting', 'decision_refused', 'lost')),
  chosen_url  text,
  chosen_year int,
  identity    text,
  tries       jsonb,
  decision    jsonb,
  request_id  bigint,
  sent_at     timestamptz,
  checked_at  timestamptz not null default now()
);
create index if not exists link_rollover_checks_request on pipeline.link_rollover_checks (request_id) where outcome = 'sent';
comment on table pipeline.link_rollover_checks is 'CF-247 s891 (Platform Admin 20 Nov 2026 22:58): one row per held Course link item tried by rule course_link_year_rollover_v1: the addresses tried (tries), the one proved, and what was decided. Written by security.link_rollover_tick_v1 and security.link_rollover_record_v1; read by the claim (retry after link_rollover.retry_days) and the reports. Never deleted.';
alter table pipeline.link_rollover_checks enable row level security;
revoke all on pipeline.link_rollover_checks from public, anon, authenticated;

-- 3 claim, record, tick -----------------------------------------------------------------------------------------------------------------------------
create or replace function security.link_rollover_claim_v1(p_limit integer)
returns table (item_id uuid, course_id uuid, provider_id uuid, url text, code text, title text, country text)
language sql stable security definer set search_path to '' as $f$
  select r.id, r.entity_id, c.provider_id, u.url, btrim(c.course_code), coalesce(nullif(btrim(c.display_title), ''), c.canonical_title), security.coverage_country(c.provider_id)
    from pipeline.layer4_review_items r
    join catalogue.courses c on c.id = r.entity_id and c.lifecycle_status = 'active'
    cross join lateral (select btrim(coalesce(security.layer4_item_page_v1(r.field_code, r.proposed_value, r.layer2_state), '')) url) u
   where r.status = 'pending' and r.entity_type = 'course' and r.field_code = 'official_course_url'
     and r.escalation_reason like 'The page we show carries the year%'
     and u.url ~* '^https://' and nullif(btrim(c.course_code), '') is not null
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.entity_id and l.field in ('official_url', 'course_url'))
     and not exists (select 1 from pipeline.link_rollover_checks k where k.item_id = r.id
                      and (k.outcome = 'sent' or k.checked_at > now() - make_interval(days => security.pipeline_num_v1('link_rollover.retry_days', 7)::int)))
   order by r.created_at, r.id
   limit greatest(0, least(coalesce(p_limit, 0), 400))  -- fixed: upper bound of the setting's range
$f$;
revoke all on function security.link_rollover_claim_v1(integer) from public, anon, authenticated;
comment on function security.link_rollover_claim_v1(integer) is 'CF-247 s891: the held Course link items rule course_link_year_rollover_v1 tries next (an address with a past year, a course code, no manual lock, not tried within link_rollover.retry_days); reads only.';

create or replace function security.link_rollover_record_v1(p_items jsonb, p_run text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare e jsonb; ch jsonb; r pipeline.layer4_review_items%rowtype; v_held text; v_url text; v_out text; v_res jsonb; v_rec jsonb; v_prev text; v_reason text; v_prov uuid;
        v_sys constant uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_tally jsonb := '{}'::jsonb;
begin
  for e in select x from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x loop
    v_out := null; v_res := null; v_rec := null; ch := e->'chosen'; v_url := nullif(btrim(coalesce(ch->>'url', '')), '');
    select * into r from pipeline.layer4_review_items where id = (e->>'item_id')::uuid for update;
    v_held := btrim(coalesce(security.layer4_item_page_v1(r.field_code, r.proposed_value, r.layer2_state), ''));
    select c.provider_id into v_prov from catalogue.courses c where c.id = r.entity_id;
    if r.id is null or r.status <> 'pending' then v_out := 'not_waiting';
    elsif v_url is null then v_out := 'not_proved';
    elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.entity_id and l.field in ('official_url', 'course_url')) then v_out := 'locked';
    elsif exists (select 1 from pipeline.page_rejections j where j.course_id = r.entity_id and lower(j.url) = lower(v_url)) then v_out := 'refused_before';
    elsif v_url !~* '^https://' or security.provider_page_host_v1(v_prov, v_url) <> 'own' then v_out := 'not_own_host';
    else
      v_reason := left(format('[rule course_link_year_rollover_v1] %s: %s answered on the provider''s own host and proved this course (%s, plain read, $0). Approved by Platform Admin 20 Nov 2026 22:58 (S1-CourseLink-2027-CRICOS)',
                              case when lower(v_url) = lower(v_held) then 'Keep the held page' else 'Set the page of ' || coalesce(ch->>'year', '?') end, v_url, coalesce(ch->>'identity', '?')), 1000);
      v_prev := current_setting('request.jwt.claim.sub', true);
      begin
        perform set_config('request.jwt.claim.sub', v_sys::text, true);
        v_res := case when lower(v_url) = lower(v_held) then public.layer4_review_decide(r.id, 'approve', v_reason, null)
                      else public.layer4_review_decide(r.id, 'edit_and_approve', v_reason, to_jsonb(v_url)) end;
        perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
        -- the stored copy the worker kept becomes the course page's reading at once (the read lane's own recorder), so no re-read is needed
        if exists (select 1 from pipeline.coverage_course_pages p where p.course_id = r.entity_id) and nullif(ch->>'storage_path', '') is not null then
          update pipeline.coverage_course_pages set url = v_url, status = 'bound', bound_at = now() where course_id = r.entity_id;
          v_rec := public.svc_coverage_read_record(r.entity_id, 'read', nullif(ch->>'http', '')::int, 'direct', ch->>'identity', ch->>'storage_path', ch->>'sha256', ch->'candidates');
        end if;
        v_out := case when lower(v_url) = lower(v_held) then 'admitted_held_address' else 'admitted_newer_year' end;
      exception when others then
        perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
        v_out := 'decision_refused'; v_res := jsonb_build_object('error', left(sqlerrm, 300));
      end;
    end if;
    insert into pipeline.link_rollover_checks as k (item_id, course_id, held_url, outcome, chosen_url, chosen_year, identity, tries, decision, checked_at)
    values ((e->>'item_id')::uuid, coalesce(r.entity_id, (e->>'course_id')::uuid), coalesce(nullif(v_held, ''), '?'), v_out, v_url, nullif(ch->>'year', '')::int, ch->>'identity', e->'tries',
            jsonb_build_object('result', v_res, 'stored', v_rec, 'run', p_run), now())
    on conflict (item_id) do update set outcome = excluded.outcome, chosen_url = excluded.chosen_url, chosen_year = excluded.chosen_year, identity = excluded.identity,
           tries = excluded.tries, decision = excluded.decision, checked_at = now();
    v_tally := jsonb_set(v_tally, array[v_out], to_jsonb(coalesce((v_tally->>v_out)::int, 0) + 1));
  end loop;
  return v_tally;
end $f$;
revoke all on function security.link_rollover_record_v1(jsonb, text) from public, anon, authenticated;
comment on function security.link_rollover_record_v1(jsonb, text) is 'CF-247 s891: records the worker''s answers for rule course_link_year_rollover_v1. A proved address on the provider''s own host, not locked and not refused before, is decided through public.layer4_review_decide under the system automation account (the held address approved, or the newer year''s address set), and its stored copy becomes the course page''s reading (public.svc_coverage_read_record). Everything else stays in Layer 4 with what was tried.';

create or replace function security.link_rollover_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare q record; v_res jsonb; v_rec jsonb; v_harv int := 0; v_bad int := 0; v_lost int := 0; v_sent int := 0; v_items int := 0;
        v_open int; v_room int; v_batch int; v_per int; v_all jsonb; v_part jsonb; v_id bigint; v_n int; i int; v_t0 timestamptz := clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:link_rollover')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  -- 1 answered calls
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.link_rollover_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'rule' = 'link-year-rollover-v1' then
      v_rec := security.link_rollover_record_v1(v_res->'items', 'request:' || q.id);
      update pipeline.link_rollover_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.link_rollover_requests set status = 'failed', finished_at = now(),
             result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.link_rollover_checks set outcome = 'lost', checked_at = now() where request_id = q.id and outcome = 'sent';
  end loop;
  -- 2 calls with no answer in time are given up; their items go back to the queue
  with l as (update pipeline.link_rollover_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('link_rollover.request_lost_minutes', 30)::int) returning id)
  update pipeline.link_rollover_checks k set outcome = 'lost', checked_at = now() - make_interval(days => 365) from l where k.request_id = l.id and k.outcome = 'sent';  -- fixed: a lost try is due again at once
  get diagnostics v_lost = row_count;
  -- 3 the next batch
  if security.pipeline_num_v1('link_rollover.on', 1) < 1 then
    return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'items_lost', v_lost, 'sent', 0, 'rollover', 'off');
  end if;
  select count(*) into v_open from pipeline.link_rollover_requests where status = 'sent';
  v_per := security.pipeline_num_v1('link_rollover.items_per_call', 15)::int;
  v_room := security.pipeline_num_v1('link_rollover.in_flight_max', 4)::int - v_open;
  v_batch := least(security.pipeline_num_v1('batch.link_rollover', 60)::int, greatest(v_room, 0) * v_per);
  if v_batch > 0 then
    select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) into v_all from security.link_rollover_claim_v1(v_batch) c;
    v_n := jsonb_array_length(v_all); i := 0;
    while i * v_per < v_n loop
      select jsonb_agg(x.v order by x.o) into v_part from jsonb_array_elements(v_all) with ordinality x(v, o) where x.o > i * v_per and x.o <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'link_year_rollover', 'items', v_part,
                'now_year', extract(year from (now() at time zone 'Australia/Melbourne'))::int,  -- fixed: the current Melbourne year
                'min_chars', security.pipeline_num_v1('link_rollover.min_chars', 1500)::int,
                'markers', coalesce(security.toolset_setting('pipeline', 'link_rollover.page_markers'), '[]'::jsonb),
                'at_once', security.pipeline_num_v1('link_rollover.fetches_at_once', 4)::int));
      insert into pipeline.link_rollover_requests (id, items) values (v_id, jsonb_array_length(v_part));
      insert into pipeline.link_rollover_checks as k (item_id, course_id, held_url, outcome, request_id, sent_at, checked_at)
      select (x->>'item_id')::uuid, (x->>'course_id')::uuid, x->>'url', 'sent', v_id, now(), now() from jsonb_array_elements(v_part) x
      on conflict (item_id) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), checked_at = now();
      v_sent := v_sent + 1; v_items := v_items + jsonb_array_length(v_part); i := i + 1;
    end loop;
  end if;
  return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'items_lost', v_lost, 'calls_sent', v_sent, 'items_sent', v_items, 'open_before', v_open,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $f$;
revoke all on function security.link_rollover_tick_v1() from public, anon, authenticated;
comment on function security.link_rollover_tick_v1() is 'CF-247 s891: one run of rule course_link_year_rollover_v1 (inside the job link-refresh): reads back the worker''s answers (pg_net) and records them, gives up calls with no answer in time, then sends the next held items to the coverage-sweep worker (mode link_year_rollover). $0: plain reads, no model, no Firecrawl.';

-- 4 inside the existing link re-check job -------------------------------------------------------------------------------------------------------------
create or replace function security.link_refresh_with_rollover_v1(p_limit integer) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v jsonb; w jsonb;
begin
  v := security.link_refresh_tick_v1(p_limit);
  begin w := security.link_rollover_tick_v1(); exception when others then w := jsonb_build_object('error', left(sqlerrm, 300)); end;  -- the link refresh never fails because of the rollover
  return coalesce(v, '{}'::jsonb) || jsonb_build_object('year_rollover', w);
end $f$;
revoke all on function security.link_refresh_with_rollover_v1(integer) from public, anon, authenticated;
comment on function security.link_refresh_with_rollover_v1(integer) is 'CF-247 s891: the job link-refresh: security.link_refresh_tick_v1 exactly as before, then one run of rule course_link_year_rollover_v1 (security.link_rollover_tick_v1); a rollover error is reported, never raised.';

select cron.alter_job(j.jobid, command := 'select security.link_refresh_with_rollover_v1(security.pipeline_num_v1(''batch.link_refresh'', 500)::int)')
  from cron.job j where j.jobname = 'link-refresh';

update pipeline.automation_catalogue
   set description = description || ' s891 (Platform Admin 20 Nov 2026 22:58): each run then tries held Course link pages whose address carries a past year at the upcoming, current and previous year, and admits the newest that proves the course (rule course_link_year_rollover_v1, settings link_rollover.*; $0).'
 where jobname = 'link-refresh' and description not like '%course_link_year_rollover_v1%';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('table', 'pipeline.link_rollover_requests', 'Layer 4', 'Course links', 'Worker calls of rule course_link_year_rollover_v1', 'active', '{}', '20261120235000'),
  ('table', 'pipeline.link_rollover_checks', 'Layer 4', 'Course links', 'What rule course_link_year_rollover_v1 tried and decided for each held Course link item', 'active', '{}', '20261120235000'),
  ('function', 'security.link_rollover_claim_v1', 'Layer 4', 'Course links', 'The held Course link items to try at a newer year', 'active', '{}', '20261120235000'),
  ('function', 'security.link_rollover_record_v1', 'Layer 4', 'Course links', 'Decides the proved addresses and keeps their stored copies', 'active', '{}', '20261120235000'),
  ('function', 'security.link_rollover_tick_v1', 'Layer 4', 'Course links', 'One run of rule course_link_year_rollover_v1', 'active', '{}', '20261120235000'),
  ('function', 'security.link_refresh_with_rollover_v1', 'Layer 4', 'Course links', 'Job link-refresh: the link re-check, then one year rollover run', 'active', '{}', '20261120235000')
on conflict do nothing;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'post-check: manual locks changed'; end if;
  if (select command from cron.job where jobname = 'link-refresh') <> 'select security.link_refresh_with_rollover_v1(security.pipeline_num_v1(''batch.link_refresh'', 500)::int)' then
    raise exception 'post-check: the job link-refresh was not changed';
  end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active jobs'; end if;
  if (select count(*) from security.link_rollover_claim_v1(400)) = 0 then raise exception 'post-check: no held item to try'; end if;
end $p$;
