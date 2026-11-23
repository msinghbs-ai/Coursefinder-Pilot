-- CF-247 s1027 (S1-Build; Platform Admin 24 Nov 2026 06:03, 06:10, 06:27 and 09:06 AEDT; UI-UX plan v1.2 slice 8): event-driven freshness through
-- Firecrawl Monitor (/v2/monitor). Firecrawl re-reads a watched page on its own weekly schedule and calls firecrawl-monitor-webhook when it changes.
-- 1. Watch set as rows: pipeline.monitor_watch_providers (Victoria University, Adelaide University, The University of Newcastle, The University of
--    Notre Dame Australia, Monash, Melbourne, Macquarie, QUT; search monitors for Monash and Adelaide) and pipeline.monitor_watch_courses (the
--    feedback-4 test course VU EBCL). security.monitor_watchlist_plan_v1 picks each university's pages (test courses first, then the course pages
--    holding the most live fee and intake rows), round-robin across universities, until the weekly credit cap (firecrawl.monitor_weekly_credits,
--    150, Platform Admin 24 Nov 2026 "own weekly credit cap"); pages beyond it are held_budget. Firecrawl's monthly estimate is recorded on
--    registration.
-- 2. pipeline.monitor_events: every delivery, once (webhook id, url, event); outcome per page.
-- 3. Evidence first (Platform Admin 06:10): a changed or new page is archived by the function to storage evidence/aer-artifacts/<provider>/monitor/
--    <sha256>.json.gz and registered here in pipeline.evidence_artifacts (storage path, SHA-256, source URL) before anything is routed; without the
--    stored copy the page is held (held_no_evidence) and nothing is routed.
-- 4. Routing (Platform Admin 24 Nov 2026 "Layer 4 review"; where an item is already waiting for that course and field, the reading is logged
--    against it in pipeline.preadmission_gate_events and counted as attached): Firecrawl's JSON values come from Firecrawl's own model, not a qualified pinned model,
--    so nothing is admitted by the machine. A locked tuition or intake value goes to Locked Field Update (s1023). An unlocked changed tuition,
--    intake or English value goes through the pre-admission gate checks (s1020) and becomes one pending Layer 4 item (provider_current_tuition,
--    course_intake or course_english, the shapes their approve paths read) with the gate result; a person approves it.
-- 5. Credits: each completed check adds pages x firecrawl.monitor_credits_per_url to the week (Melbourne); over the cap the function pauses the
--    monitors (HELD:BUDGET_GATE) and the status read says so.
-- 6. public.admin_monitor_status_v1 (rank 4+): watchlist, the week's credits against the cap, outcomes. Screen: S1-API-Frontend-Delivery.
-- G1: no cron job (Firecrawl schedules the checks; firecrawl.monitor_cron). G2: cap, page count, credits per page, schedule, retention and search
-- size are settings. G3: no consumer object changed (checked). Manual locks and active cron checked unchanged. Nothing dropped or deleted.
-- Replaces: the adapter reroute of items raised by the pre-admission gates (s1020 fix, see below).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if to_regprocedure('security.locked_field_update_raise_v1(text,jsonb,jsonb)') is null or to_regprocedure('security.preadmission_gate_raise_v1(text,text,uuid,text,uuid,jsonb,text,text,text,jsonb)') is null then
    raise exception 'guard: s1020 and s1023 are not live';
  end if;
end $g$;
create temp table s1027_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1027_cron on commit drop as select count(*) n from cron.job where active;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('firecrawl', 'monitor_weekly_credits', 'Monitor: credits per week',
        'The most Firecrawl credits the Monitor watchlist may use in one week (Melbourne). The watchlist is planned within it; if a week''s checks go over it, the monitors are paused and the Monitor status says HELD:BUDGET_GATE.',
        'number', to_jsonb(150), 0, 5000, 'credits', 9100, 'Firecrawl Monitor', 'security.monitor_watchlist_plan_v1, public.svc_monitor_event_v1', 'CF-247 s1027: Platform Admin 24 Nov 2026 (own weekly credit cap, 150)'),
       ('firecrawl', 'monitor_credits_per_url', 'Monitor: credits per watched page per check',
        'Credits one weekly check of one watched page costs with structured (JSON) change tracking. Used to plan the watchlist and to count each week''s checks.',
        'number', to_jsonb(5), 1, 20, 'credits', 9101, 'Firecrawl Monitor', 'security.monitor_watchlist_plan_v1, public.svc_monitor_event_v1', 'CF-247 s1027: slice 8'),
       ('firecrawl', 'monitor_urls_per_provider', 'Monitor: pages watched per university',
        'How many course pages of each watched university are watched (its test courses first, then the pages holding the most live fees and intakes).',
        'number', to_jsonb(3), 1, 20, 'pages', 9102, 'Firecrawl Monitor', 'security.monitor_watchlist_plan_v1', 'CF-247 s1027: slice 8'),
       ('firecrawl', 'monitor_search_results', 'Monitor: results per search monitor',
        'How many results a search monitor follows per check (Firecrawl charges 2 credits per 10 results).',
        'number', to_jsonb(10), 1, 50, 'results', 9103, 'Firecrawl Monitor', 'security.monitor_watchlist_plan_v1, firecrawl-monitor-webhook', 'CF-247 s1027: slice 8'),
       ('firecrawl', 'monitor_cron', 'Monitor: weekly check time (cron, UTC)',
        'When Firecrawl checks the watched pages, as a cron line in UTC. 17 16 * * 0 is Monday 03:17 in Melbourne during daylight saving.',
        'text', to_jsonb('17 16 * * 0'::text), null, null, 'cron (UTC)', 9104, 'Firecrawl Monitor', 'firecrawl-monitor-webhook (register)', 'CF-247 s1027: slice 8'),
       ('firecrawl', 'monitor_retention_days', 'Monitor: days Firecrawl keeps check history',
        'How long Firecrawl keeps each monitor''s checks and diffs. The platform keeps its own copy of every changed page in evidence storage.',
        'number', to_jsonb(30), 1, 365, 'days', 9105, 'Firecrawl Monitor', 'firecrawl-monitor-webhook (register)', 'CF-247 s1027: slice 8')
on conflict do nothing;

create table if not exists pipeline.monitor_watch_providers (
  provider_id uuid primary key,
  sort int not null,
  search_queries text[],
  search_domain text,
  note text
);
comment on table pipeline.monitor_watch_providers is 'CF-247 s1027: the universities whose pages Firecrawl Monitor watches (Tier 1 watchlist, Platform Admin 24 Nov 2026), with any search monitor; {next_year} in a query is filled at registration.';
insert into pipeline.monitor_watch_providers (provider_id, sort, search_queries, search_domain, note) values
  ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7', 10, null, null, 'Victoria University (CRICOS 00124K); feedback-4'),
  ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 20, array['Adelaide University international tuition fees {next_year}', 'Adelaide University {next_year} intakes international students'], 'adelaide.edu.au', 'Adelaide University; feedback-4'),
  ('1822b40a-8b13-44dc-8c37-106ae31bb447', 30, null, null, 'The University of Newcastle; feedback-4'),
  ('dce54a01-39c1-4bdf-877d-b67da3afc81e', 40, null, null, 'The University of Notre Dame Australia; feedback-4'),
  ('543b87b8-f0dd-4bc7-80d6-76252cfaabec', 50, array['Monash University international tuition fees {next_year}', 'Monash University {next_year} intakes international students'], 'monash.edu', 'Monash University'),
  ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2', 60, null, null, 'The University of Melbourne'),
  ('188103a5-1aba-4f99-bd3e-0416659086d3', 70, null, null, 'Macquarie University'),
  ('2c4f515c-c146-4e90-ba8a-294130aa1f40', 80, null, null, 'Queensland University of Technology')
on conflict do nothing;
alter table pipeline.monitor_watch_providers enable row level security;
revoke all on pipeline.monitor_watch_providers from public, anon, authenticated;

create table if not exists pipeline.monitor_watch_courses (
  course_id uuid primary key,
  reason text not null
);
comment on table pipeline.monitor_watch_courses is 'CF-247 s1027: courses always watched first for their university (benchmark test courses).';
insert into pipeline.monitor_watch_courses (course_id, reason) values ('d75b54d3-a88c-4a48-a41a-b62d9b4d9386', 'UAT feedback-4 test course VU EBCL') on conflict do nothing;
alter table pipeline.monitor_watch_courses enable row level security;
revoke all on pipeline.monitor_watch_courses from public, anon, authenticated;

create table if not exists pipeline.monitor_watchlist (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null,
  target_type text not null check (target_type in ('scrape', 'search')),
  url text,
  queries text[],
  course_id uuid,
  rank int not null,
  est_credits numeric not null,
  status text not null default 'planned' check (status in ('planned', 'held_budget', 'registered', 'paused', 'error', 'retired')),
  monitor_id text,
  est_month_credits int,
  planned_at timestamptz not null default now(),
  registered_at timestamptz,
  last_event_at timestamptz,
  note text
);
comment on table pipeline.monitor_watchlist is 'CF-247 s1027: the pages and searches Firecrawl Monitor watches, planned within the weekly credit cap, with their Firecrawl monitor.';
create unique index if not exists monitor_watchlist_target_uq on pipeline.monitor_watchlist (provider_id, target_type, coalesce(url, ''));
alter table pipeline.monitor_watchlist enable row level security;
revoke all on pipeline.monitor_watchlist from public, anon, authenticated;

create table if not exists pipeline.monitor_events (
  id bigint generated always as identity primary key,
  received_at timestamptz not null default now(),
  webhook_id text not null,
  event_type text not null,
  monitor_id text,
  check_id text,
  provider_id uuid,
  url text,
  page_status text,
  is_meaningful boolean,
  diff jsonb,
  payload jsonb,
  credits_est numeric not null default 0,
  evidence_id uuid,
  storage_path text,
  sha256 text,
  outcome text not null default 'received',
  outcome_detail jsonb not null default '{}'::jsonb,
  processed_at timestamptz
);
comment on table pipeline.monitor_events is 'CF-247 s1027: every Firecrawl Monitor webhook delivery (once per delivery, page and event), its stored copy and where it was routed.';
create unique index if not exists monitor_events_delivery_uq on pipeline.monitor_events (webhook_id, event_type, coalesce(url, ''));
create index if not exists monitor_events_received_idx on pipeline.monitor_events (received_at desc);
alter table pipeline.monitor_events enable row level security;
revoke all on pipeline.monitor_events from public, anon, authenticated;

insert into pipeline.pilot_nonce_functions (function_name) values ('firecrawl-monitor-webhook') on conflict do nothing;

CREATE OR REPLACE FUNCTION security.monitor_url_key_v1(p_url text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select nullif(lower(regexp_replace(regexp_replace(regexp_replace(btrim(coalesce(p_url, '')), '#.*$', ''), '^https?://(www\.)?', ''), '/+(\?|$)', '\1')), '')
$function$;

CREATE OR REPLACE FUNCTION security.monitor_setting_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((select case when jsonb_typeof(s.value) = 'number' then (s.value #>> '{}')::numeric end
                     from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default)
$function$;

-- The week's credits (Melbourne week), from completed checks
CREATE OR REPLACE FUNCTION security.monitor_week_credits_v1()
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(sum(e.credits_est), 0) from pipeline.monitor_events e
   where e.received_at >= (date_trunc('week', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne')
$function$;

CREATE OR REPLACE FUNCTION security.monitor_watchlist_plan_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap numeric := security.monitor_setting_v1('monitor_weekly_credits', 150); v_per numeric := security.monitor_setting_v1('monitor_credits_per_url', 5);
        v_n int := security.monitor_setting_v1('monitor_urls_per_provider', 3)::int; v_res int := security.monitor_setting_v1('monitor_search_results', 10)::int;
        v_search numeric; v_planned int; v_held int; v_week numeric;
begin
  v_search := 2 * ceil(v_res / 10.0);  -- fixed: Firecrawl's price, 2 credits per 10 search results
  create temp table if not exists _plan (provider_id uuid, target_type text, url text, queries text[], course_id uuid, rk int, psort int, est numeric) on commit drop;
  truncate _plan;
  insert into _plan
  select y.provider_id, 'scrape', y.course_url, null, y.id, y.rk, y.sort, v_per from (
    select x.*, row_number() over (partition by x.provider_id order by x.golden desc, x.score desc, x.id) rk from (
      -- one row per page (sibling courses can share a page): the page's best course
      select distinct on (c.provider_id, security.monitor_url_key_v1(c.course_url)) c.id, c.provider_id, c.course_url, w.sort, (g.course_id is not null) golden,
             (select count(*) from catalogue.course_fees f where f.course_id = c.id and f.status = 'active' and f.fee_type = 'provider_current_tuition')
             + (select count(*) from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active') score
        from catalogue.courses c join pipeline.monitor_watch_providers w on w.provider_id = c.provider_id
        left join pipeline.monitor_watch_courses g on g.course_id = c.id
       where c.lifecycle_status = 'active' and c.course_url ~* '^https://'
       order by c.provider_id, security.monitor_url_key_v1(c.course_url), (g.course_id is not null) desc,
                (select count(*) from catalogue.course_fees f where f.course_id = c.id and f.status = 'active' and f.fee_type = 'provider_current_tuition')
                + (select count(*) from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active') desc, c.id) x) y
   where y.rk <= v_n;
  insert into _plan
  select w.provider_id, 'search', null, w.search_queries, null, 1, w.sort, v_search from pipeline.monitor_watch_providers w where cardinality(w.search_queries) > 0;
  -- round-robin across universities, within the weekly cap
  insert into pipeline.monitor_watchlist (provider_id, target_type, url, queries, course_id, rank, est_credits, status, planned_at)
  select p.provider_id, p.target_type, p.url, p.queries, p.course_id, p.rk, p.est,
         case when sum(p.est) over (order by p.rk, p.psort, p.target_type desc, p.url) <= v_cap then 'planned' else 'held_budget' end, now()
    from _plan p
  on conflict (provider_id, target_type, coalesce(url, '')) do update
    set queries = excluded.queries, course_id = excluded.course_id, rank = excluded.rank, est_credits = excluded.est_credits, planned_at = now(),
        status = case when pipeline.monitor_watchlist.status in ('registered', 'paused') and excluded.status = 'planned' then pipeline.monitor_watchlist.status else excluded.status end;
  update pipeline.monitor_watchlist m set status = 'retired', planned_at = now()
   where m.status in ('planned', 'held_budget') and not exists (select 1 from _plan p where p.provider_id = m.provider_id and p.target_type = m.target_type and coalesce(p.url, '') = coalesce(m.url, ''));
  select count(*) filter (where status in ('planned', 'registered')), count(*) filter (where status = 'held_budget'), coalesce(sum(est_credits) filter (where status in ('planned', 'registered')), 0)
    into v_planned, v_held, v_week from pipeline.monitor_watchlist;
  return jsonb_build_object('planned', v_planned, 'held_budget', v_held, 'est_week_credits', v_week, 'weekly_cap', v_cap);
end $function$;
revoke all on function security.monitor_watchlist_plan_v1() from public, anon, authenticated;

-- For the function (service role): plan, then the targets to register, with the settings
CREATE OR REPLACE FUNCTION public.svc_monitor_watchlist_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_plan jsonb := security.monitor_watchlist_plan_v1(); v_next text := ((extract(year from now() at time zone 'Australia/Melbourne'))::int + 1)::text;
begin
  return jsonb_build_object('plan', v_plan,
    'settings', jsonb_build_object('cron', coalesce((select s.value #>> '{}' from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'monitor_cron'), '17 16 * * 0'),
                                   'retention_days', security.monitor_setting_v1('monitor_retention_days', 30), 'search_results', security.monitor_setting_v1('monitor_search_results', 10),
                                   'weekly_cap', security.monitor_setting_v1('monitor_weekly_credits', 150), 'week_credits', security.monitor_week_credits_v1()),
    'providers', coalesce((select jsonb_agg(jsonb_build_object('provider_id', w.provider_id,
        'name', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = w.provider_id),
        'scrape', (select jsonb_build_object('monitor_id', max(m.monitor_id), 'urls', jsonb_agg(m.url order by m.rank))
                     from pipeline.monitor_watchlist m where m.provider_id = w.provider_id and m.target_type = 'scrape' and m.status in ('planned', 'registered')),
        'search', (select jsonb_build_object('monitor_id', m.monitor_id, 'queries', (select jsonb_agg(replace(q, '{next_year}', v_next)) from unnest(m.queries) q), 'domain', w.search_domain)
                     from pipeline.monitor_watchlist m where m.provider_id = w.provider_id and m.target_type = 'search' and m.status in ('planned', 'registered') limit 1)) order by w.sort)
      from pipeline.monitor_watch_providers w), '[]'::jsonb));
end $function$;
revoke all on function public.svc_monitor_watchlist_v1() from public, anon, authenticated;
grant execute on function public.svc_monitor_watchlist_v1() to service_role;

CREATE OR REPLACE FUNCTION public.svc_monitor_registered_v1(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  update pipeline.monitor_watchlist m
     set status = coalesce(nullif(p->>'status', ''), 'registered'), monitor_id = coalesce(nullif(p->>'monitor_id', ''), m.monitor_id),
         est_month_credits = coalesce(nullif(p->>'est_month_credits', '')::int, m.est_month_credits),
         registered_at = case when p->>'status' = 'registered' then now() else m.registered_at end, note = left(p->>'note', 1000)
   where ((m.provider_id = (p->>'provider_id')::uuid and m.target_type = p->>'target_type') or (nullif(p->>'provider_id', '') is null and m.monitor_id = p->>'monitor_id'))
     and m.status in ('planned', 'registered', 'paused', 'error');
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'rows', v_n);
end $function$;
revoke all on function public.svc_monitor_registered_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_monitor_registered_v1(jsonb) to service_role;

-- One delivery, once. A completed check counts the week's credits; over the cap the function pauses the monitors.
CREATE OR REPLACE FUNCTION public.svc_monitor_event_v1(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id bigint; v_prov uuid; v_cred numeric := 0; v_type text := p->>'event_type'; v_status text := p->>'page_status'; v_week numeric; v_cap numeric;
begin
  v_prov := coalesce(nullif(p->>'provider_id', '')::uuid, (select m.provider_id from pipeline.monitor_watchlist m where m.monitor_id = p->>'monitor_id' limit 1));
  if v_type = 'monitor.check.completed' then
    v_cred := coalesce((p->'summary'->>'totalPages')::numeric, 0) * security.monitor_setting_v1('monitor_credits_per_url', 5);
  end if;
  insert into pipeline.monitor_events (webhook_id, event_type, monitor_id, check_id, provider_id, url, page_status, is_meaningful, diff, payload, credits_est, outcome)
  values (p->>'webhook_id', v_type, p->>'monitor_id', p->>'check_id', v_prov, nullif(p->>'url', ''), v_status, (p->>'is_meaningful')::boolean, p->'diff', p->'payload', v_cred,
          case when v_type = 'monitor.check.completed' then 'check_completed' when v_status in ('changed', 'new') then 'received' when v_status = 'same' then 'no_change' else coalesce(v_status, 'received') end)
  on conflict (webhook_id, event_type, coalesce(url, '')) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('duplicate', true); end if;
  if nullif(p->>'url', '') is not null then
    update pipeline.monitor_watchlist m set last_event_at = now() where m.provider_id = v_prov and security.monitor_url_key_v1(m.url) = security.monitor_url_key_v1(p->>'url');
  end if;
  v_week := security.monitor_week_credits_v1(); v_cap := security.monitor_setting_v1('monitor_weekly_credits', 150);
  return jsonb_build_object('duplicate', false, 'id', v_id, 'provider_id', v_prov, 'route', v_type = 'monitor.page' and v_status in ('changed', 'new'),
                            'week_credits', v_week, 'weekly_cap', v_cap, 'over_cap', v_type = 'monitor.check.completed' and v_week > v_cap,
                            'monitor_ids', (select jsonb_agg(distinct m.monitor_id) from pipeline.monitor_watchlist m where m.status = 'registered' and m.monitor_id is not null));
end $function$;
revoke all on function public.svc_monitor_event_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_monitor_event_v1(jsonb) to service_role;

-- Evidence first, then routing. Nothing is admitted here: every change becomes a person's decision.
CREATE OR REPLACE FUNCTION public.svc_monitor_route_v1(p_event_id bigint, p_evidence jsonb, p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e pipeline.monitor_events; v_ev uuid; v_courses uuid[]; v_c uuid; f jsonb; v_row jsonb; v_y int; v_ahead int; v_ok boolean; v_why text; v_held int;
        v_ints jsonb; v_new jsonb; v_eng jsonb; v_ielts boolean; v_att boolean; v_n jsonb := jsonb_build_object('locked', 0, 'proposed', 0, 'held', 0, 'unchanged', 0, 'attached', 0);
        v_snap jsonb := case when jsonb_typeof(p_snapshot) = 'object' then p_snapshot else '{}'::jsonb end;
begin
  select * into e from pipeline.monitor_events where id = p_event_id for update;
  if not found then return jsonb_build_object('ok', false, 'why', 'no such event'); end if;
  if nullif(p_evidence->>'storage_path', '') is null or coalesce(p_evidence->>'sha256', '') !~ '^[0-9a-f]{64}$' then
    update pipeline.monitor_events set outcome = 'held_no_evidence', processed_at = now(), outcome_detail = jsonb_build_object('why', coalesce(p_evidence->>'error', 'no stored copy')) where id = e.id;
    return jsonb_build_object('ok', true, 'outcome', 'held_no_evidence');
  end if;
  insert into pipeline.evidence_artifacts (evidence_type, source_url, storage_path, content_hash, mime_type, captured_at, metadata)
  values ('firecrawl_monitor_snapshot', e.url, p_evidence->>'storage_path', p_evidence->>'sha256', 'application/json', now(),
          jsonb_build_object('capture', 'firecrawl-monitor-webhook', 'bucket', 'evidence', 'container', 'gzip', 'monitor_id', e.monitor_id, 'check_id', e.check_id,
                             'event_id', e.id, 'page_status', e.page_status, 'provider_id', e.provider_id, 'bytes', (p_evidence->>'bytes')::int))
  returning id into v_ev;
  update pipeline.monitor_events set evidence_id = v_ev, storage_path = p_evidence->>'storage_path', sha256 = p_evidence->>'sha256' where id = e.id;

  select array_agg(distinct x) into v_courses from (
    select m.course_id x from pipeline.monitor_watchlist m where m.course_id is not null and security.monitor_url_key_v1(m.url) = security.monitor_url_key_v1(e.url)
    union select c.id from catalogue.courses c where c.lifecycle_status = 'active' and security.monitor_url_key_v1(c.course_url) = security.monitor_url_key_v1(e.url)) z;
  if coalesce(cardinality(v_courses), 0) = 0 then
    update pipeline.monitor_events set outcome = 'no_course', processed_at = now(), outcome_detail = jsonb_build_object('evidence_id', v_ev) where id = e.id;
    return jsonb_build_object('ok', true, 'outcome', 'no_course', 'evidence_id', v_ev);
  end if;
  v_y := extract(year from now() at time zone 'Australia/Melbourne')::int; v_ahead := security.pipeline_num_v1('gates.fee_year_ahead', 1)::int;

  foreach v_c in array v_courses loop
    -- tuition (international)
    for f in select x from jsonb_array_elements(case when jsonb_typeof(v_snap->'tuition_fees') = 'array' then v_snap->'tuition_fees' else '[]'::jsonb end) x loop
      continue when coalesce(f->>'amount', '') !~ '^[0-9]+(\.[0-9]+)?$' or (f->>'amount')::numeric <= 0 or coalesce(f->>'audience', 'international') <> 'international';
      v_row := jsonb_build_object('course_id', v_c, 'fee_year', (nullif(f->>'fee_year', ''))::int, 'audience', 'international', 'fee_type', 'provider_current_tuition',
                                  'amount', (f->>'amount')::numeric, 'currency_code', upper(coalesce(nullif(f->>'currency', ''), 'AUD')), 'basis', coalesce(nullif(f->>'basis', ''), 'annual'),
                                  'status', 'active', 'evidence_id', v_ev);
      if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = v_c and l.field = 'tuition') then
        if security.locked_field_update_raise_v1('tuition', v_row, null) is not null then v_n := jsonb_set(v_n, '{locked}', to_jsonb((v_n->>'locked')::int + 1)); end if;
        continue;
      end if;
      if exists (select 1 from catalogue.course_fees l where l.course_id = v_c and l.status = 'active' and l.fee_type = 'provider_current_tuition' and l.audience = 'international'
                  and l.fee_year is not distinct from (v_row->>'fee_year')::int and l.amount = (v_row->>'amount')::numeric and l.currency_code = v_row->>'currency_code') then
        v_n := jsonb_set(v_n, '{unchanged}', to_jsonb((v_n->>'unchanged')::int + 1)); continue;
      end if;
      select max(l.fee_year) into v_held from catalogue.course_fees l where l.course_id = v_c and l.status = 'active' and l.fee_type = 'provider_current_tuition' and l.audience = 'international'
         and l.fee_year between v_y and v_y + v_ahead;
      v_ok := (v_row->>'fee_year') is not null and (v_row->>'fee_year')::int between v_y and v_y + v_ahead and (v_row->>'fee_year')::int >= coalesce(v_held, v_y);
      v_why := case when (v_row->>'fee_year') is null then 'the page states no fee year'
                    when (v_row->>'fee_year')::int not between v_y and v_y + v_ahead then format('the fee year %s is outside %s to %s', v_row->>'fee_year', v_y, v_y + v_ahead)
                    when not v_ok then format('the fee year %s is older than the year held (%s)', v_row->>'fee_year', v_held)
                    else 'Firecrawl Monitor read a tuition fee that differs from the live one' end;
      v_att := exists (select 1 from pipeline.layer4_review_items l4 where l4.entity_type = 'course' and l4.entity_id = v_c and l4.field_code = 'provider_current_tuition' and l4.status = 'pending');  -- logged against the item already waiting
      perform security.preadmission_gate_raise_v1('monitor_fee', 'course', v_c, 'provider_current_tuition', v_ev,
        jsonb_build_object('amount', (v_row->>'amount')::numeric, 'currency', v_row->>'currency_code', 'basis', v_row->>'basis', 'fee_year', (v_row->>'fee_year')::int, 'audience', 'international', 'page', e.url),
        v_why, case when v_ok then 'proposed' else 'held' end, e.id::text, jsonb_build_object('via', 'firecrawl_monitor', 'monitor_id', e.monitor_id, 'check_id', e.check_id, 'gate_passed', v_ok));
      v_n := jsonb_set(v_n, case when v_att then '{attached}'::text[] when v_ok then '{proposed}'::text[] else '{held}'::text[] end, to_jsonb((v_n->>(case when v_att then 'attached' when v_ok then 'proposed' else 'held' end))::int + 1));
    end loop;

    -- intakes
    v_ints := coalesce((select jsonb_agg(jsonb_build_object('intake_year', (nullif(x->>'intake_year', ''))::int, 'intake_label', nullif(btrim(x->>'intake_label'), ''),
                                                             'start_date', case when coalesce(x->>'start_date', '') ~ '^\d{4}-\d{2}-\d{2}$' then x->>'start_date' end))
                          from jsonb_array_elements(case when jsonb_typeof(v_snap->'intakes') = 'array' then v_snap->'intakes' else '[]'::jsonb end) x
                         where nullif(btrim(x->>'intake_label'), '') is not null or coalesce(x->>'start_date', '') ~ '^\d{4}-\d{2}-\d{2}$'), '[]'::jsonb);
    select coalesce(jsonb_agg(n), '[]'::jsonb) into v_new from jsonb_array_elements(v_ints) n
     where not exists (select 1 from catalogue.course_intakes i where i.course_id = v_c and i.status = 'active'
                        and i.intake_year is not distinct from (n->>'intake_year')::int and i.intake_label is not distinct from n->>'intake_label'
                        and i.start_date is not distinct from (n->>'start_date')::date);
    if jsonb_array_length(v_new) > 0 then
      if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = v_c and l.field = 'intakes') then
        for f in select x from jsonb_array_elements(v_new) x loop
          if security.locked_field_update_raise_v1('intakes', f || jsonb_build_object('course_id', v_c, 'status', 'active', 'evidence_id', v_ev), null) is not null then
            v_n := jsonb_set(v_n, '{locked}', to_jsonb((v_n->>'locked')::int + 1));
          end if;
        end loop;
      else
        v_ok := not exists (select 1 from jsonb_array_elements(v_new) n where (n->>'start_date') is not null and (n->>'intake_year') is not null
                                                                          and extract(year from (n->>'start_date')::date)::int <> (n->>'intake_year')::int);
        v_att := exists (select 1 from pipeline.layer4_review_items l4 where l4.entity_type = 'course' and l4.entity_id = v_c and l4.field_code = 'course_intake' and l4.status = 'pending');  -- logged against the item already waiting
      perform security.preadmission_gate_raise_v1('monitor_intake', 'course', v_c, 'course_intake', v_ev,
          jsonb_build_object('intakes', (select jsonb_agg(n || jsonb_build_object('source_intake_key', null)) from jsonb_array_elements(v_ints) n), 'page', e.url),
          case when v_ok then 'Firecrawl Monitor read intakes that differ from the live ones' else 'a start date is in a different year from its intake year' end,
          case when v_ok then 'proposed' else 'held' end, e.id::text, jsonb_build_object('via', 'firecrawl_monitor', 'new', v_new, 'gate_passed', v_ok));
        v_n := jsonb_set(v_n, case when v_att then '{attached}'::text[] when v_ok then '{proposed}'::text[] else '{held}'::text[] end, to_jsonb((v_n->>(case when v_att then 'attached' when v_ok then 'proposed' else 'held' end))::int + 1));
      end if;
    end if;

    -- English (IELTS, PTE, TOEFL iBT); a locked English field is left to the person who locked it
    v_eng := coalesce((select jsonb_agg(jsonb_build_object('test_code', upper(x->>'test'), 'overall_score', (x->>'overall')::numeric,
                         'component_scores', jsonb_strip_nulls(jsonb_build_object('listening', x->'listening', 'reading', x->'reading', 'writing', x->'writing', 'speaking', x->'speaking'))))
                         from jsonb_array_elements(case when jsonb_typeof(v_snap->'english') = 'array' then v_snap->'english' else '[]'::jsonb end) x
                        where upper(coalesce(x->>'test', '')) in ('IELTS', 'PTE', 'TOEFL_IBT') and coalesce(x->>'overall', '') ~ '^[0-9]+(\.[0-9]+)?$'), '[]'::jsonb);
    if jsonb_array_length(v_eng) > 0 and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = v_c and l.field = 'english')
       and exists (select 1 from jsonb_array_elements(v_eng) n where not exists (
             select 1 from catalogue.course_english_requirements r join ref.english_tests t on t.id = r.english_test_id
              where r.course_id = v_c and r.status = 'active' and t.code = n->>'test_code' and r.overall_score = (n->>'overall_score')::numeric)) then
      v_ielts := exists (select 1 from jsonb_array_elements(v_eng) n where n->>'test_code' = 'IELTS')
              or exists (select 1 from catalogue.course_english_requirements r join ref.english_tests t on t.id = r.english_test_id where r.course_id = v_c and r.status = 'active' and t.code = 'IELTS');
      v_ok := not v_ielts or not exists (select 1 from jsonb_array_elements(v_eng) n where n->>'test_code' in ('PTE', 'TOEFL_IBT')
                                         and (select count(*) from jsonb_object_keys(n->'component_scores')) < 4);
      v_att := exists (select 1 from pipeline.layer4_review_items l4 where l4.entity_type = 'course' and l4.entity_id = v_c and l4.field_code = 'course_english' and l4.status = 'pending');  -- logged against the item already waiting
      perform security.preadmission_gate_raise_v1('monitor_english', 'course', v_c, 'course_english', v_ev, jsonb_build_object('english_requirements', v_eng, 'page', e.url),
        case when v_ok then 'Firecrawl Monitor read English requirements that differ from the live ones' else 'a PTE or TOEFL iBT requirement has no four band scores where IELTS is held' end,
        case when v_ok then 'proposed' else 'held' end, e.id::text, jsonb_build_object('via', 'firecrawl_monitor', 'gate_passed', v_ok));
      v_n := jsonb_set(v_n, case when v_att then '{attached}'::text[] when v_ok then '{proposed}'::text[] else '{held}'::text[] end, to_jsonb((v_n->>(case when v_att then 'attached' when v_ok then 'proposed' else 'held' end))::int + 1));
    end if;
  end loop;

  update pipeline.monitor_events set outcome = case when (v_n->>'locked')::int + (v_n->>'proposed')::int + (v_n->>'held')::int > 0 then 'routed' else 'no_field_change' end,
         processed_at = now(), outcome_detail = v_n || jsonb_build_object('evidence_id', v_ev, 'courses', to_jsonb(v_courses)) where id = e.id;
  return jsonb_build_object('ok', true, 'outcome', 'routed', 'evidence_id', v_ev, 'counts', v_n);
end $function$;
revoke all on function public.svc_monitor_route_v1(bigint, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.svc_monitor_route_v1(bigint, jsonb, jsonb) to service_role;

-- s1020 fix: an item raised by a pre-admission gate (and so by this monitor) is a person's decision (Platform Admin 24 Nov 2026 "Hold, grouped
-- cards" and "Layer 4 review"). The adapter reroute (security.layer4_reroute_trg_v1, CF-247 v2.15.250) superseded new course_english and
-- course_intake items on courses with an admitting adapter and queued the page to be read again; for a gate item the adapter's own reading is
-- what was held, so it would be re-read and held again in a loop. Gate items now arrive pending; every other item is rerouted as before.
-- md5-guarded edit (live fd3e6afe, 24 Nov 2026), the condition text replaced exactly once.
do $rr$
declare d text := pg_get_functiondef('security.layer4_reroute_trg_v1'::regproc);
        x text := 'security.layer4_reroute_course_v1(new.entity_id, new.field_code, true)';
begin
  if md5(replace(d, chr(13), '')) <> 'fd3e6afef1b826533ab124bdcf48dfed' then raise exception 'guard: security.layer4_reroute_trg_v1 is not the definition this change was written against'; end if;
  if (length(d) - length(replace(d, x, ''))) / length(x) <> 1 then raise exception 'guard: the reroute condition is not found exactly once'; end if;
  execute replace(d, x, $c$coalesce(new.layer2_state->>'source', '') <> 'preadmission_gate' and $c$ || x);
end $rr$;

-- Status for the Integrations / Services & limits screen (rank 4+)
CREATE OR REPLACE FUNCTION public.admin_monitor_status_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_week numeric := security.monitor_week_credits_v1(); v_cap numeric := security.monitor_setting_v1('monitor_weekly_credits', 150);
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then  -- fixed: Pipeline Operator (rank 4) reads integrations
    raise exception 'Pipeline Operator (rank 4) or above is needed' using errcode = '42501';
  end if;
  return jsonb_build_object('weekly_cap', v_cap, 'week_credits', v_week, 'held', case when v_week > v_cap then 'HELD:BUDGET_GATE' end,
    'planned_week_credits', (select coalesce(sum(est_credits), 0) from pipeline.monitor_watchlist where status in ('planned', 'registered')),
    'watchlist', coalesce((select jsonb_agg(jsonb_build_object('provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = m.provider_id),
        'provider_id', m.provider_id, 'target_type', m.target_type, 'url', m.url, 'queries', to_jsonb(m.queries), 'status', m.status, 'est_credits', m.est_credits,
        'est_month_credits', m.est_month_credits, 'registered_at', m.registered_at, 'last_event_at', m.last_event_at, 'note', m.note) order by m.provider_id, m.target_type, m.rank)
      from pipeline.monitor_watchlist m where m.status <> 'retired'), '[]'::jsonb),
    'outcomes_7d', coalesce((select jsonb_object_agg(o, n) from (select outcome o, count(*) n from pipeline.monitor_events where received_at > now() - interval '7 days' group by 1) z), '{}'::jsonb),  -- fixed: the screen's 7-day view
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', r.received_at, 'event', r.event_type, 'url', r.url, 'page_status', r.page_status, 'outcome', r.outcome,
        'evidence_id', r.evidence_id, 'detail', r.outcome_detail) order by r.received_at desc) from (select * from pipeline.monitor_events order by received_at desc limit 50) r), '[]'::jsonb));  -- fixed: the screen's recent list
end $function$;
revoke all on function public.admin_monitor_status_v1() from public, anon;
grant execute on function public.admin_monitor_status_v1() to authenticated, service_role;

do $post$
declare v_api jsonb := security.consumer_api_check_v1(); v_plan jsonb;
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1027_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1027_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if not exists (select 1 from pipeline.pilot_nonce_functions where function_name = 'firecrawl-monitor-webhook') then raise exception 'post-check: the function is not allow-listed'; end if;
  if position('preadmission_gate' in pg_get_functiondef('security.layer4_reroute_trg_v1'::regproc)) = 0 then raise exception 'post-check: gate items are still rerouted'; end if;
  v_plan := security.monitor_watchlist_plan_v1();
  if (v_plan->>'est_week_credits')::numeric > (v_plan->>'weekly_cap')::numeric then raise exception 'post-check: the planned watchlist is over the weekly cap: %', v_plan; end if;
end $post$;
