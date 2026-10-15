-- CF-247 (15 Oct 2026, Decision 260): component register and weekly hygiene check. Platform Admin, 15 Oct 2026 11:06: "housekeeping is very
-- important so we are not increasing code liabilities, leaving scripts, jobs, ui and database base structure and index bloating and unrequired.
-- always keep the snapshot/documentation what corresponds to what and decommission as we create new approach." Choice: "Live table + generated doc".
-- Replaces: nothing (the usage audit captures of 12–15 Oct were taken by hand; this keeps them going)
-- Retires: nothing
do $guard$
declare v_expected jsonb := '{"security.platform_notices_v1()": "7580ed3340d12b38d379254906a09d8e"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;
-- 1 Settings (Pipeline settings › Housekeeping)   2 Register, usage snapshots, reports   3 Sync, ingest (edge functions and screens from the
-- repository, by the component-register workflow), hygiene check, generated document   4 Job hygiene-check (weekly)   5 First run
-- Nothing dropped or deleted. Components that no longer exist are marked retired, never removed from the register.

-- 1 Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'hygiene.idle_days', 'Unused when nothing has used it for', 'A table with no reads or writes, an index never scanned, an edge function never called or a screen never opened for this long is listed as unused in the weekly hygiene check.', 'number', to_jsonb(14), 7, 90, 'days', 740, 'Platform Admin 15 Oct 2026 (Decision 260)', 'Housekeeping', 'hygiene-check job'),
 ('pipeline', 'hygiene.retire_after_days', 'Keep a retiring component before it is dropped', 'When a change retires a component it is switched off and kept this long; after that, if nothing used it, it is listed for the drop paste file.', 'number', to_jsonb(14), 7, 90, 'days', 741, 'Platform Admin 15 Oct 2026: "Same change, data kept 14 days"', 'Housekeeping', 'component register')
on conflict do nothing;

-- 2 Records
create table if not exists pipeline.component_register (
  kind text not null check (kind in ('job', 'table', 'view', 'edge_function', 'screen')),
  name text not null,
  layer text not null,
  area text,
  purpose text,
  status text not null default 'active' check (status in ('active', 'retiring', 'retired')),
  replaces text[] not null default '{}',
  replaced_by text,
  introduced_in text,
  retire_after date,
  last_used_at timestamptz,
  usage jsonb not null default '{}'::jsonb,
  size_bytes bigint,
  note text,
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (kind, name));
comment on table pipeline.component_register is 'CF-247 Decision 260: every job, table, view, edge function and screen, with its layer, purpose, status (active, retiring, retired), what it replaces, and when it was last used. Generated document: COMPONENT-REGISTER.md.';
create table if not exists pipeline.component_usage_snapshots (
  at timestamptz not null default now(),
  kind text not null,
  name text not null,
  reads bigint,
  writes bigint,
  primary key (at, kind, name));
comment on table pipeline.component_usage_snapshots is 'CF-247 Decision 260: weekly counters of table reads and writes and index scans, so the hygiene check can tell what nothing has used.';
create table if not exists pipeline.hygiene_reports (
  id bigserial primary key,
  at timestamptz not null default now(),
  summary jsonb not null,
  findings jsonb not null);
comment on table pipeline.hygiene_reports is 'CF-247 Decision 260: the weekly hygiene check (unused, insecure, unregistered and ready-to-drop components).';
alter table pipeline.component_register enable row level security;
alter table pipeline.component_usage_snapshots enable row level security;
alter table pipeline.hygiene_reports enable row level security;
revoke all on pipeline.component_register, pipeline.component_usage_snapshots, pipeline.hygiene_reports from anon, authenticated;

-- 3 Rules
CREATE OR REPLACE FUNCTION security.component_layer_v1(p_kind text, p_name text, p_area text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_area in ('Layer 1 register') then 'L1 register'
    when p_area in ('Course pages', 'Layer 2 reading', 'Scholarships') then 'L2 read'
    when p_area in ('Layer 3 AI') then 'L3 interpret'
    when p_area in ('Admission') then 'L4 admit'
    when p_area in ('Search and API') then 'Website API'
    when p_area in ('Reports', 'Platform upkeep') then 'Platform'
    when lower(p_name) ~ '(^|[._-])layer1|register|cricos|nzqa|teqsa|qilt|prisms|statcan|ranking|^ref\.' then 'L1 register'
    when lower(p_name) ~ '(^|[._-])layer3|(^|[._-])ai([._-]|$)|_ai_|central_ai' then 'L3 interpret'
    when lower(p_name) ~ '(^|[._-])layer4|admit|admission|review|publish|exit_award|block' then 'L4 admit'
    when lower(p_name) ~ '(^|[._-])layer2|coverage|firecrawl|course_link|adapter|central|enrich|scholarship|onboarding|discover|site|campus|page' then 'L2 read'
    when lower(p_name) ~ 'website|wix|zoho|^search\.|^api\.|^publishing\.' then 'Website API'
    when lower(p_name) ~ '^catalogue\.' then 'Catalogue'
    else 'Platform' end
$function$;

CREATE OR REPLACE FUNCTION security.component_register_sync_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_jobs int; v_tables int; v_gone int;
begin
  -- jobs: the job catalogue gives the area and purpose (G1)
  insert into pipeline.component_register(kind, name, layer, area, purpose, status, note)
  select 'job', j.jobname, security.component_layer_v1('job', j.jobname, c.area), c.area, coalesce(c.label || coalesce(': ' || c.description, ''), 'Not in the job catalogue'),
         'active', case when c.jobname is null then 'not catalogued' when not j.active then 'switched off' end
    from cron.job j left join pipeline.automation_catalogue c on c.jobname = j.jobname
  on conflict (kind, name) do update set area = excluded.area, purpose = excluded.purpose, note = excluded.note, updated_at = now(),
         layer = case when pipeline.component_register.layer = 'Platform' then excluded.layer else pipeline.component_register.layer end,
         status = case when pipeline.component_register.status = 'retired' then 'active' else pipeline.component_register.status end;
  get diagnostics v_jobs = row_count;
  -- tables and views in the platform's schemas: purpose from the table comment, size from the catalogue
  insert into pipeline.component_register(kind, name, layer, purpose, size_bytes)
  select case c.relkind when 'v' then 'view' when 'm' then 'view' else 'table' end, n.nspname || '.' || c.relname,
         security.component_layer_v1('table', n.nspname || '.' || c.relname, null), obj_description(c.oid, 'pg_class'),
         case when c.relkind in ('r', 'p', 'm') then pg_total_relation_size(c.oid) end
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relkind in ('r', 'p', 'v', 'm')
     and n.nspname not in ('pg_catalog', 'information_schema', 'cron', 'net', 'extensions', 'graphql', 'graphql_public', 'pgbouncer', 'pgsodium', 'pgsodium_masks',
                           'realtime', 'storage', 'supabase_functions', 'supabase_migrations', 'vault', 'auth', 'pg_toast')
     and n.nspname not like 'pg_temp%' and n.nspname not like 'pg_toast%'
     and not c.relispartition
  on conflict (kind, name) do update set purpose = coalesce(excluded.purpose, pipeline.component_register.purpose), size_bytes = excluded.size_bytes, updated_at = now(),
         status = case when pipeline.component_register.status = 'retired' then 'active' else pipeline.component_register.status end;
  get diagnostics v_tables = row_count;
  -- what no longer exists is marked retired (kept in the register)
  update pipeline.component_register r set status = 'retired', note = coalesce(r.note || '; ', '') || 'gone ' || to_char(now(), 'YYYY-MM-DD'), updated_at = now()
   where r.status <> 'retired' and (
         (r.kind = 'job' and not exists (select 1 from cron.job j where j.jobname = r.name))
      or (r.kind in ('table', 'view') and to_regclass(r.name) is null));
  get diagnostics v_gone = row_count;
  return jsonb_build_object('jobs', v_jobs, 'tables_and_views', v_tables, 'gone', v_gone);
end $function$;

CREATE OR REPLACE FUNCTION security.component_register_ingest_v1(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_edge int := 0; v_screens int := 0; v_used int := 0; v_gone int := 0;
begin
  -- from the component-register workflow: edge functions and screens in the repository, and edge function calls in the last day (logs)
  insert into pipeline.component_register(kind, name, layer, purpose)
  select 'edge_function', e->>'name', security.component_layer_v1('edge_function', e->>'name', null), nullif(e->>'purpose', '')
    from jsonb_array_elements(coalesce(p->'edge_functions', '[]'::jsonb)) e
  on conflict (kind, name) do update set purpose = coalesce(excluded.purpose, pipeline.component_register.purpose), updated_at = now(),
         status = case when pipeline.component_register.status = 'retired' then 'active' else pipeline.component_register.status end;
  get diagnostics v_edge = row_count;
  insert into pipeline.component_register(kind, name, layer, area, purpose)
  select 'screen', s->>'name', security.component_layer_v1('screen', s->>'name', null), s->>'page', nullif(s->>'purpose', '')
    from jsonb_array_elements(coalesce(p->'screens', '[]'::jsonb)) s
  on conflict (kind, name) do update set area = excluded.area, purpose = coalesce(excluded.purpose, pipeline.component_register.purpose), updated_at = now(),
         status = case when pipeline.component_register.status = 'retired' then 'active' else pipeline.component_register.status end;
  get diagnostics v_screens = row_count;
  update pipeline.component_register r set last_used_at = greatest(r.last_used_at, (c->>'last')::timestamptz),
         usage = r.usage || jsonb_build_object('calls_last_day', (c->>'calls')::bigint, 'measured_at', now()), updated_at = now()
    from jsonb_array_elements(coalesce(p->'edge_calls', '[]'::jsonb)) c
   where r.kind = 'edge_function' and r.name = c->>'name';
  get diagnostics v_used = row_count;
  if jsonb_array_length(coalesce(p->'edge_functions', '[]'::jsonb)) > 0 then
    update pipeline.component_register r set status = 'retired', note = coalesce(r.note || '; ', '') || 'not in the repository ' || to_char(now(), 'YYYY-MM-DD'), updated_at = now()
     where r.kind = 'edge_function' and r.status <> 'retired'
       and not exists (select 1 from jsonb_array_elements(p->'edge_functions') e where e->>'name' = r.name);
    get diagnostics v_gone = row_count;
  end if;
  return jsonb_build_object('edge_functions', v_edge, 'screens', v_screens, 'edge_used', v_used, 'edge_gone', v_gone);
end $function$;

CREATE OR REPLACE FUNCTION security.hygiene_check_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_idle int := security.pipeline_num_v1('hygiene.idle_days', 14)::int; v_since timestamptz; v_then timestamptz; f jsonb := '{}'::jsonb; s jsonb; v_sync jsonb;
begin
  v_sync := security.component_register_sync_v1();
  -- counters now
  insert into pipeline.component_usage_snapshots(at, kind, name, reads, writes)
  select now(), 'table', t.schemaname || '.' || t.relname, coalesce(t.seq_scan, 0) + coalesce(t.idx_scan, 0), t.n_tup_ins + t.n_tup_upd + t.n_tup_del
    from pg_stat_user_tables t
  union all
  select now(), 'index', i.schemaname || '.' || i.indexrelname, i.idx_scan, null from pg_stat_user_indexes i;
  -- the latest snapshot at least the idle time old
  v_since := now() - make_interval(days => v_idle);
  select max(x.at) into v_then from pipeline.component_usage_snapshots x where x.at <= v_since;
  if v_then is not null then
    f := f || jsonb_build_object('unused_tables', coalesce((select jsonb_agg(jsonb_build_object('name', n.name, 'size', pg_size_pretty(coalesce(r.size_bytes, 0))) order by r.size_bytes desc nulls last)
          from pipeline.component_usage_snapshots n join pipeline.component_usage_snapshots o on o.kind = n.kind and o.name = n.name and o.at = v_then
          left join pipeline.component_register r on r.kind = 'table' and r.name = n.name
         where n.kind = 'table' and n.at = (select max(at) from pipeline.component_usage_snapshots) and n.reads = o.reads and n.writes = o.writes), '[]'::jsonb),
      'unused_indexes', coalesce((select jsonb_agg(jsonb_build_object('name', n.name, 'size', pg_size_pretty(pg_relation_size(to_regclass(n.name)))))
          from pipeline.component_usage_snapshots n join pipeline.component_usage_snapshots o on o.kind = n.kind and o.name = n.name and o.at = v_then
          join pg_index x on x.indexrelid = to_regclass(n.name)
         where n.kind = 'index' and n.at = (select max(at) from pipeline.component_usage_snapshots) and n.reads = o.reads and not x.indisprimary and not x.indisunique), '[]'::jsonb));
  end if;
  f := f || jsonb_build_object(
    'edge_functions_not_called', coalesce((select jsonb_agg(r.name order by r.name) from pipeline.component_register r
         where r.kind = 'edge_function' and r.status = 'active' and (r.last_used_at is null or r.last_used_at < v_since) and r.registered_at < v_since), '[]'::jsonb),
    'jobs_not_catalogued', coalesce((select jsonb_agg(j.jobname) from cron.job j where not exists (select 1 from pipeline.automation_catalogue c where c.jobname = j.jobname)), '[]'::jsonb),
    'jobs_switched_off', coalesce((select jsonb_agg(j.jobname) from cron.job j where not j.active), '[]'::jsonb),
    'tables_without_rls', coalesce((select jsonb_agg(n.nspname || '.' || c.relname order by 1) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where c.relkind in ('r', 'p') and not c.relrowsecurity and not c.relispartition
           and n.nspname in ('public', 'pipeline', 'catalogue', 'search', 'scholarship', 'api', 'publishing', 'ref', 'security', 'workflow', 'ranking', 'private')), '[]'::jsonb),
    'definer_functions_without_search_path', coalesce((select jsonb_agg(n.nspname || '.' || p.proname order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where p.prosecdef and p.proconfig is null and n.nspname in ('public', 'pipeline', 'catalogue', 'search', 'scholarship', 'api', 'publishing', 'security')), '[]'::jsonb),
    'public_functions_open_to_anon', coalesce((select jsonb_agg(p.proname order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.prosecdef and has_function_privilege('anon', p.oid, 'execute')), '[]'::jsonb),
    'tables_without_purpose', (select count(*) from pipeline.component_register r where r.kind = 'table' and r.status = 'active' and r.purpose is null),
    'ready_to_drop', coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'name', r.name, 'replaced_by', r.replaced_by, 'since', r.retire_after)) from pipeline.component_register r
         where r.status = 'retiring' and r.retire_after <= current_date), '[]'::jsonb));
  s := jsonb_build_object('sync', v_sync, 'compared_with', v_then,
    'unused_tables', jsonb_array_length(coalesce(f->'unused_tables', '[]'::jsonb)), 'unused_indexes', jsonb_array_length(coalesce(f->'unused_indexes', '[]'::jsonb)),
    'edge_functions_not_called', jsonb_array_length(f->'edge_functions_not_called'), 'jobs_not_catalogued', jsonb_array_length(f->'jobs_not_catalogued'),
    'tables_without_rls', jsonb_array_length(f->'tables_without_rls'), 'definer_functions_without_search_path', jsonb_array_length(f->'definer_functions_without_search_path'),
    'public_functions_open_to_anon', jsonb_array_length(f->'public_functions_open_to_anon'), 'ready_to_drop', jsonb_array_length(f->'ready_to_drop'),
    'tables_without_purpose', f->'tables_without_purpose');
  insert into pipeline.hygiene_reports(summary, findings) values (s, f);
  return s;
end $function$;

CREATE OR REPLACE FUNCTION security.component_register_markdown_v1()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the generated document: summary by layer and status, then every component (newest hygiene check first)
  select '# StudySearch – Component register (generated)' || E'\n\n'
      || '**Generated:** ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI') || ' Melbourne, from `pipeline.component_register` (Decision 260). Do not edit by hand.' || E'\n\n'
      || '## Summary' || E'\n\n| Layer | Kind | Active | Retiring | Retired |\n|---|---|---|---|---|\n'
      || coalesce((select string_agg(format('| %s | %s | %s | %s | %s |', layer, kind, a, ri, rd), E'\n' order by layer, kind)
                   from (select layer, kind, count(*) filter (where status = 'active') a, count(*) filter (where status = 'retiring') ri, count(*) filter (where status = 'retired') rd
                           from pipeline.component_register group by 1, 2) x), '')
      || E'\n\n## Latest hygiene check\n\n'
      || coalesce((select '```' || E'\n' || jsonb_pretty(h.summary) || E'\n```' from pipeline.hygiene_reports h order by h.at desc limit 1), 'None yet.')
      || E'\n\n## Components\n\n| Kind | Name | Layer | Status | Purpose | Last used | Size | Replaces / replaced by | Note |\n|---|---|---|---|---|---|---|---|---|\n'
      || coalesce((select string_agg(format('| %s | `%s` | %s | %s | %s | %s | %s | %s | %s |', r.kind, r.name, r.layer, r.status,
                          replace(left(coalesce(r.purpose, ''), 160), '|', '/'), coalesce(to_char(r.last_used_at, 'YYYY-MM-DD'), ''),
                          coalesce(pg_size_pretty(r.size_bytes), ''), concat_ws(' / ', nullif(array_to_string(r.replaces, ', '), ''), r.replaced_by),
                          replace(coalesce(r.note, ''), '|', '/')), E'\n' order by r.layer, r.kind, r.name)
                   from pipeline.component_register r), '') || E'\n'
$function$;

revoke execute on function security.component_layer_v1(text, text, text), security.component_register_sync_v1(), security.component_register_ingest_v1(jsonb),
  security.hygiene_check_v1(), security.component_register_markdown_v1() from public, anon, authenticated;


CREATE OR REPLACE FUNCTION security.platform_notices_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w_or int := coalesce((security.toolset_setting('openrouter', 'notice_window_hours'))::text::int, 24);
  w_job int := coalesce((security.toolset_setting('scheduled_jobs', 'notice_window_hours'))::text::int, 24);
  w_edge int := coalesce((security.toolset_setting('edge_functions', 'notice_window_hours'))::text::int, 6);
  v_or_mode text := coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop');
  v jsonb := '[]'::jsonb;
begin
  -- v2.15.258 (bug 12/10-01): OpenRouter notices for the AI uses that run now (Layer 3 retired on 12 Oct 2026). Refused calls
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:refused:' || z.code, 'layer', 2, 'toolset', 'openrouter', 'kind', 'refused', 'severity', 'high',
      'title', case z.code when 'credit' then 'OpenRouter refused calls: out of credit'
                           when 'key_limit' then 'OpenRouter refused calls: the key''s own spending limit was reached'
                           when 'rate' then 'OpenRouter refused calls: rate limit'
                           else 'OpenRouter refused calls: key not accepted' end,
      'detail', format('%s AI calls in the last %s hours were refused; those pages are read again later.', z.n, w_or),
      'hint', case z.code when 'credit' then 'Top up the OpenRouter balance; the refused pages are read again by themselves.'
                          when 'key_limit' then 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in StudySearch. Raise or clear it there.'
                          when 'rate' then 'Usually clears by itself; the pages are read again.'
                          else 'Check the OpenRouter key on Settings.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select case when r.e ilike '%key limit%' or r.e ilike '%weekly limit%' then 'key_limit' when r.e ~ 'HTTP 402' or r.e ilike '%credit%' then 'credit'
                      when r.e ~ 'HTTP 429' then 'rate' else 'key' end code, count(*) n, min(r.at) first_at, max(r.at) last_at
          from (select x.error e, x.at from pipeline.scholarship_ai_extractions x where x.at > now() - make_interval(hours => w_or) and x.error ~ 'HTTP (40[123]|429)'
                union all
                select q.error, coalesce(q.done_at, q.created_at) from pipeline.central_ai_queue q where q.created_at > now() - make_interval(hours => w_or) and q.error ~ 'HTTP (40[123]|429)') r
          group by 1) z), '[]'::jsonb);

  -- OpenRouter balance: below the warning level, below the credit floor, or not read recently (read by the openrouter-balance job)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'openrouter:2:low_balance', 'layer', 2, 'toolset', 'openrouter', 'kind', 'low_balance',
      'severity', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0) then 'high' else 'warning' end,
      'title', format('OpenRouter balance is US$%s', round(o.remaining_usd, 2)),
      'detail', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0)
                     then format('Below the credit floor of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'credit_floor_usd'),
                                 case v_or_mode when 'observe' then 'observe only, so it keeps running until OpenRouter refuses calls' else 'stop at limits, so the scholarship AI and central pages AI have stopped' end)
                     else format('Below the warning level of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'low_balance_warn_usd'),
                                 case v_or_mode when 'observe' then 'observe only' else 'stop at limits' end) end,
      'hint', 'Top up the OpenRouter account the platform''s key uses.',
      'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select * from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1) o
    where o.remaining_usd < greatest(coalesce((security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric, 0),
                                     coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0))
    union all
    select jsonb_build_object('key', 'openrouter:2:not_observed', 'layer', 2, 'toolset', 'openrouter', 'kind', 'not_observed', 'severity', 'warning',
      'title', 'OpenRouter balance has not been read recently',
      'detail', format('Last reading %s.', coalesce(to_char(o.observed_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), 'never')),
      'hint', 'The balance is read every 15 minutes by the scheduled job "Read the OpenRouter balance" (openrouter-balance); check it in Scheduled jobs.',
      'count', 1, 'first_at', o.observed_at, 'last_at', now())
    from (select max(observed_at) observed_at from pipeline.layer3_openrouter_observations where kind = 'credits') o
    where o.observed_at is null or o.observed_at < now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30))
  ) q), '[]'::jsonb);

  -- An AI use past its daily guard today (UTC day)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:over_guard:' || g.use || ':' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'openrouter', 'kind', 'over_guard',
      'severity', case v_or_mode when 'observe' then 'info' else 'warning' end,
      'title', format('%s spent US$%s today, past its guard of US$%s', g.label, g.spent, g.guard),
      'detail', case v_or_mode when 'observe' then 'Observe only: it keeps running. This is recorded for the top-up review.'
                     else 'Stop at limits: it has stopped until the UTC day changes (adapter proposals stop at their own allowance; course-page matching is observed only).' end,
      'hint', 'Change the guard or the mode on Models & services › OpenRouter (AI models) › Daily guards.',
      'count', 1, 'first_at', now(), 'last_at', now()))
    from security.ai_spend_today_v1() g where g.guard > 0 and g.spent >= g.guard), '[]'::jsonb);

  -- Firecrawl balance, scholarship share, course-link search cap (Layer 2)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'firecrawl:2:low_balance', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('Firecrawl has %s credits left this month', o.remaining_units),
      'detail', format('Below the warning level of %s. The period ends %s.', security.toolset_setting('firecrawl', 'low_balance_warn_units'), to_char(o.period_end at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
      'hint', 'Work that needs Firecrawl stops at the reserve set on Scrapers & fetchers.', 'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select v2.* from pipeline.vendor_credit_observations v2 join pipeline.layer2_acquisition_providers p on p.id = v2.provider_id and p.provider_key = 'firecrawl' order by v2.observed_at desc limit 1) o
    where o.remaining_units < coalesce((security.toolset_setting('firecrawl', 'low_balance_warn_units'))::text::numeric, 0)
    union all
    -- v2.15.262: the day's Firecrawl budget (a share, or the billed total) at 80% or more
    select jsonb_build_object('key', 'firecrawl:2:daily:' || b.grp || ':' || to_char(now() at time zone 'Australia/Melbourne', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'daily_budget',
      'severity', case when b.used >= b.cap then 'high' else 'warning' end,
      'title', format('Firecrawl daily budget, %s: %s of %s credits used', b.label, round(b.used), round(b.cap)),
      'detail', case when b.used >= b.cap then 'Used up: this work waits until midnight, Melbourne time.' else 'At 80% or more; this work stops for the day when it is used up.' end,
      'hint', 'Raise the share under Daily budget if this work should carry on today.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select 'total' grp, 'billed today' label, (st->>'billed_today')::numeric used, (st->>'total')::numeric cap, (st->>'on')::boolean is_on from security.fc_budget_status_v1() st
          union all
          select g->>'group', g->>'label', (g->>'used')::numeric, (g->>'share')::numeric, (st->>'on')::boolean
            from security.fc_budget_status_v1() st, jsonb_array_elements(st->'groups') g) b
    where b.is_on and b.cap > 0 and b.used >= 0.8 * b.cap
    union all
    select jsonb_build_object('key', 'firecrawl:2:search_stopped', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_stopped', 'severity', 'warning',
      'title', format('Course-page search stopped for %s universit%s', s.n, case when s.n = 1 then 'y' else 'ies' end),
      'detail', format('No correct course page after %s searches. Usually the website on record is wrong or the site hides its course pages from search.', security.fc_setting_num_v1('search_stop_after', 30)),
      'hint', 'Check the website on record (correct it on the provider if it is wrong), then press Search again.', 'count', s.n, 'first_at', now(), 'last_at', now(), 'items', s.items)
    from (select count(*) n, jsonb_agg(jsonb_build_object('provider_id', f.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
                                                          'searches', f.searches) order by f.searches desc, p.canonical_name) items
            from security.fc_search_stopped_v1() f join catalogue.providers p on p.id = f.provider_id
           where f.searches > 0
             and not exists (select 1 from pipeline.firecrawl_search_holds h where h.provider_id = f.provider_id
                               and not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at))) s where s.n > 0
    union all
    -- v2.15.265: course search held for an adapter check, by name
    select jsonb_build_object('key', 'firecrawl:2:search_held', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_held', 'severity', 'warning',
      'title', format('Course-page search held for %s: %s', count(*), string_agg(coalesce(p.display_name, p.canonical_name), ', ' order by p.canonical_name)),
      'detail', string_agg(coalesce(p.display_name, p.canonical_name) || ': ' || h.reason, '; ' order by p.canonical_name),
      'hint', 'Check the university''s adapter and website, then press Search again.', 'count', count(*), 'first_at', min(h.held_at), 'last_at', now(),
      'items', jsonb_agg(jsonb_build_object('provider_id', h.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website, 'reason', h.reason) order by p.canonical_name))
    from pipeline.firecrawl_search_holds h join catalogue.providers p on p.id = h.provider_id
   where not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at)
  having count(*) > 0
    union all
    -- v2.15.265: Australian providers whose official website was searched for and not found
    select jsonb_build_object('key', 'firecrawl:2:no_official_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'no_official_site', 'severity', 'info',
      'title', format('%s Australian providers have no official website found', count(*)),
      'detail', 'Not in the CRICOS register, TEQSA or training.gov.au, and no site showing their CRICOS code. Course pages and scholarships are not searched for them.',
      'hint', 'Enter a website if you know it: the course-page search starts within minutes. Otherwise nothing to do.', 'count', count(*), 'first_at', min(d.site_searched_at), 'last_at', max(d.site_searched_at),
      'items', jsonb_agg(jsonb_build_object('provider_id', d.provider_id, 'name', coalesce(p.display_name, p.canonical_name)) order by p.canonical_name))
    from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id and p.lifecycle_status = 'active'
   where d.status = 'no_website' and d.site_searched_at is not null and nullif(btrim(p.website), '') is null and security.coverage_country(d.provider_id) = 'AU'
  having count(*) > 0
    union all
    -- v2.15.265: providers sharing one website (pathway colleges on their university's site): their searches read the other's pages
    select jsonb_build_object('key', 'firecrawl:2:shared_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'shared_site', 'severity', 'info',
      'title', format('%s providers share a website with another provider', sum(z.n)),
      'detail', 'Examples: ' || string_agg(z.host, ', ' order by z.n desc) filter (where z.rk <= 5),
      'hint', 'Usually a pathway college on its university''s site. Give the college its own website, or leave it: scholarships are not searched for providers with fewer than 30 courses.', 'count', sum(z.n), 'first_at', now(), 'last_at', now())
    from (select y.host, y.n, row_number() over (order by y.n desc, y.host) rk from (
            select security.fc_spend_host_v1(p.website) host, count(*) n from catalogue.providers p
             where p.lifecycle_status = 'active' and p.website ~* '^https?://' group by 1 having count(*) > 1) y where y.host is not null) z
  having count(*) > 0
    union all
    select jsonb_build_object('key', 'firecrawl:2:scholarship_share', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Scholarship Firecrawl share: %s of %s credits used', s.used, s.cap),
      'detail', format('Fewer than the reserve of %s are left, so newly found scholarship pages that refuse a direct read are not read.', s.reserve),
      'hint', 'Raise the cap on Layer 2 › Scholarships if you want them read.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select (b->>'used')::numeric used, (b->>'cap')::numeric cap, (b->>'reserve')::numeric reserve
          from (select jsonb_build_object(
                  'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
                  'cap', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_cap'),
                  'reserve', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_reserve')) b) q) s
    where s.cap - s.used <= s.reserve
    union all
    select jsonb_build_object('key', 'firecrawl:2:course_link_cap:' || to_char(now(), 'YYYY-MM'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Course-link search used %s of its %s monthly credits', l.used, l.cap),
      'detail', 'Course-link search stops for the rest of the month.', 'hint', 'Change the monthly cap on Jobs › Priority.',
      'count', 1, 'first_at', now(), 'last_at', now())
    from (select (select monthly_credit_cap from pipeline.course_link_search_settings limit 1) cap,
                 (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now())) used) l
    where l.used >= l.cap
  ) q), '[]'::jsonb);

  -- Scheduled jobs that timed out or failed (the job's layer)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'scheduled_jobs:' || z.layer || ':' || z.kind || ':' || z.jobname, 'layer', z.layer, 'toolset', 'scheduled_jobs', 'kind', z.kind,
      'severity', case when z.n >= 5 then 'high' else 'warning' end,
      'title', case z.kind when 'timeout' then format('Job "%s" hit the database time limit %s times', z.jobname, z.n)
                           else format('Job "%s" failed %s times', z.jobname, z.n) end,
      'detail', format('In the last %s hours (%s runs in all). Last message: %s', w_job, z.runs, z.msg),
      'hint', case z.kind when 'timeout' then 'Lower the job''s batch size setting so each run finishes inside the limit.' else 'Usually clears by itself (for example a deadlock); if it repeats, the job needs a fix.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    -- (11 Oct 2026: the run history is read once, last 7 days; only the jobs that failed are ranked for "last three runs succeeded")
    from (with hist as materialized (select h.jobid, h.status, h.return_message, h.start_time, h.end_time
                                       from cron.job_run_details h where h.start_time > now() - interval '7 days'), -- fixed: run history read once, last 7 days
               fd as materialized (select * from hist where status = 'failed' and end_time > now() - make_interval(hours => w_job)),
               fj as materialized (select distinct jobid from fd),
               last3 as (select f.jobid, bool_and(t.status = 'succeeded') ok, count(*) c from fj f
                           cross join lateral (select x.status from hist x where x.jobid = f.jobid and x.status in ('succeeded', 'failed')
                                               order by x.start_time desc limit 3) t group by f.jobid),
               runs as (select x.jobid, count(*) n from hist x where x.jobid in (select jobid from fj)
                          and x.end_time > now() - make_interval(hours => w_job) group by x.jobid)
          select j.jobname, coalesce(l.layer, 2) layer,
                 case when d.return_message ilike '%statement timeout%' then 'timeout' else 'failed' end kind,
                 count(*) n, min(d.end_time) first_at, max(d.end_time) last_at, left(max(d.return_message), 140) msg,
                 max(coalesce(rn.n, 0)) runs
          from fd d join cron.job j on j.jobid = d.jobid left join pipeline.platform_job_layers l on l.jobname = j.jobname
          left join last3 l3 on l3.jobid = d.jobid left join runs rn on rn.jobid = d.jobid
          where not (coalesce(l3.ok, false) and coalesce(l3.c, 0) = 3)
          group by j.jobid, j.jobname, l.layer, 3
          having count(*) >= coalesce((security.toolset_setting('scheduled_jobs', 'min_failures'))::text::int, 1)) z), '[]'::jsonb);

  -- Edge function calls that timed out (platform)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'edge_functions:0:timeout', 'layer', 0, 'toolset', 'edge_functions', 'kind', 'timeout', 'severity', 'warning',
      'title', format('%s edge function calls timed out or hit the worker limit', z.n),
      'detail', format('In the last %s hours.', w_edge), 'hint', 'The worker runs too long per call; lower its per-run limit.',
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select count(*) n, min(r.created) first_at, max(r.created) last_at from net._http_response r
          where r.created > now() - make_interval(hours => w_edge) and (r.timed_out or r.status_code in (504, 546))) z
    where z.n >= coalesce((security.toolset_setting('edge_functions', 'min_timeouts'))::text::int, 1)), '[]'::jsonb);

  -- v2.15.269: a running job with a number written into it (it should read a setting)
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:fixed_value:' || c.jobname, 'layer', 0, 'toolset', 'pipeline', 'kind', 'fixed_value', 'severity', 'warning',
      'title', format('Job "%s" has a number written into it', c.jobname),
      'detail', 'Its size or limit should come from Pipeline settings, so it can be changed on screen.',
      'hint', 'Move the value to the settings register (Pipeline settings).', 'count', 1, 'first_at', now(), 'last_at', now()))
    from security.controls_check_v1() c), '[]'::jsonb);

  -- CF-247 15 Oct 2026 (waste rules): jobs paused for producing nothing, and values frozen after automatic writers disagreed
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:waste_paused:' || w.jobname, 'layer', 0, 'toolset', 'pipeline', 'kind', 'waste_paused', 'severity', 'warning',
      'title', format('Job "%s" paused: it produced nothing', w.jobname),
      'detail', format('Paused %s: no output and nothing waiting for it. It resumes by itself when work arrives.', to_char(w.paused_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI')),
      'hint', 'Nothing to do. The time is on Pipeline settings › Waste rules.', 'count', 1, 'first_at', w.paused_at, 'last_at', w.paused_at))
    from pipeline.job_idle_watch w where w.paused_at is not null), '[]'::jsonb);
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:waste_frozen', 'layer', 0, 'toolset', 'pipeline', 'kind', 'waste_frozen', 'severity', 'warning',
      'title', format('%s course values frozen: automatic writers kept changing them', z.n),
      'detail', 'Each changed more often than Pipeline settings › Waste rules allows; it is kept as it is and left out of automatic updates.',
      'hint', 'Check them and set the right value by hand.', 'count', z.n, 'first_at', z.f, 'last_at', z.l))
    from (select count(*) n, min(f.flagged_at) f, max(f.flagged_at) l from pipeline.enrichment_flags f where f.reason_code = 'flip_flop' and f.cleared_at is null) z where z.n > 0), '[]'::jsonb);

  -- CF-247 15 Oct 2026 (Decision 260): the latest weekly hygiene check, when it found something
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:hygiene', 'layer', 0, 'toolset', 'pipeline', 'kind', 'hygiene', 'severity', 'warning',
      'title', format('Housekeeping: %s unused, %s security items, %s ready to drop', z.unused, z.security, z.drop),
      'detail', format('Weekly hygiene check of %s (component register, Decision 260).', to_char(z.at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI')),
      'hint', 'Retire what is unused, fix the security items, and run the drop paste file for what is ready.', 'count', z.unused + z.security + z.drop, 'first_at', z.at, 'last_at', z.at))
    from (select h.at, coalesce((h.summary->>'unused_tables')::int, 0) + coalesce((h.summary->>'unused_indexes')::int, 0) + coalesce((h.summary->>'edge_functions_not_called')::int, 0) unused,
                 coalesce((h.summary->>'tables_without_rls')::int, 0) + coalesce((h.summary->>'definer_functions_without_search_path')::int, 0) + coalesce((h.summary->>'public_functions_open_to_anon')::int, 0) security,
                 coalesce((h.summary->>'ready_to_drop')::int, 0) drop
            from pipeline.hygiene_reports h order by h.at desc limit 1) z where z.unused + z.security + z.drop > 0), '[]'::jsonb);

  return v;
end $function$;
-- 4 Job
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('hygiene-check', 'Platform upkeep', 92, 'Housekeeping: component register and hygiene check',
  'Weekly: brings the component register up to date with the live jobs, tables and views, records usage counters, and lists what is unused, insecure, unregistered or ready to drop (pipeline.hygiene_reports).', 6, false)
on conflict do nothing;
select cron.schedule('hygiene-check', '23 16 * * 0', 'select security.hygiene_check_v1()');

-- 5 First run
select security.hygiene_check_v1();

do $post$
declare v_expected jsonb := '{"security.platform_notices_v1()": "81bf986bfc60a1525e65cbee733e47f1"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'component register post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
end $post$;

do $dry$
declare t0 timestamptz := clock_timestamp(); v jsonb;
begin
  v := security.hygiene_check_v1();
  raise exception 'DRYRUN %', jsonb_build_object('second_check', v, 'second_s', extract(epoch from clock_timestamp()-t0),
    'register', (select jsonb_object_agg(k, n) from (select kind||':'||layer k, count(*) n from pipeline.component_register group by 1) x),
    'md_len', length(security.component_register_markdown_v1()),
    'rls_missing', (select f->'tables_without_rls' from pipeline.hygiene_reports h, lateral (select h.findings f) z order by h.at desc limit 1),
    'definer_no_path', (select jsonb_array_length(h.findings->'definer_functions_without_search_path') from pipeline.hygiene_reports h order by h.at desc limit 1),
    'anon_fns', (select h.findings->'public_functions_open_to_anon' from pipeline.hygiene_reports h order by h.at desc limit 1),
    'notice', (select count(*) from jsonb_array_elements(security.platform_notices_v1()) e where e->>'kind'='hygiene'));
end $dry$;
