-- CF-247 (22 Oct 2026). Platform Admin 21:57: "When a course page read is submitted to firecrawl, how long does it take? I have seen some
-- background task just stuck on page reads like 2 out 3 stuck for long time. How is the progress going for nz courses. Give me stat's and
-- toolset usuage every 15 minutes. Keep the lesson learnt and find gaps quickly".
-- Found:
-- * Page reads are quick: worker read calls took 4.0 s on average (90% under 9.4 s, longest 86 s) for a batch of pages; a page read
--   through the scraper takes about 6 s (scholarship reads 5.8 s average). Nothing waits on Firecrawl for long.
-- * "2 of 3" was a Fill in from website task at its third step, finding central pages: it fired the central page search every minute,
--   but the search takes only providers that were asked for or are due again, and this one was neither (held until due), so it never
--   moved (95 empty central searches in 3 hours). A task now asks for the search (requested), so it is taken next.
-- * "0 of N" Find course pages tasks from automatic enrichment plans wait their turn: 2,789 asked-for course searches, about 160 an hour.
-- 1 security.admin_job_watch_v1 (md5-guarded): Fill in from website marks its central page search as asked for.
-- 2 pipeline.stats_15m and security.stats_15m_v1 (job stats-15m, every 15 minutes): per country (NZ, CA) the active courses and each
--   field held, with the change in 15 minutes and 24 hours; the toolset use (Firecrawl units by share in 15 minutes and today, AI spend
--   by use against its guard, worker calls by kind with failures and time); the watchdog states; and the gaps found by rule (a field
--   that has not moved in 24 hours, a share used up or refusing, worker failures or slow calls, tasks waiting more than an hour,
--   queues stuck). security.stats_15m_report_v1 gives the latest snapshot for the 15-minute report.
-- Replaces: security.admin_job_watch_v1 (md5-guarded edit)
-- Retires: nothing

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'stats.slow_call_seconds', '15-minute stats: slow worker call', 'A kind of worker call whose slowest call in the 15 minutes took longer than this is listed as a gap.', 'number', to_jsonb(60), 10, 150, 'seconds', 770, 'CF-247 22 Oct 2026 (15-minute stats)', 'Platform upkeep', 'security.stats_15m_v1'),
 ('pipeline', 'stats.task_wait_minutes', '15-minute stats: task waiting too long', 'A Task manager task that has not moved for this many minutes is listed as a gap.', 'number', to_jsonb(60), 15, 1440, 'minutes', 771, 'CF-247 22 Oct 2026 (15-minute stats)', 'Platform upkeep', 'security.stats_15m_v1'),
 ('pipeline', 'stats.flat_field_hours', '15-minute stats: field not moving after', 'A field below its target that has not gained a course in this many hours is listed as a gap.', 'number', to_jsonb(24), 1, 168, 'hours', 772, 'CF-247 22 Oct 2026 (15-minute stats)', 'Platform upkeep', 'security.stats_15m_v1')
on conflict do nothing;

-- 1 Fill in from website asks for its central page search --------------------------------------------------------------------------
do $edit$
declare v_def text := pg_get_functiondef('security.admin_job_watch_v1(uuid)'::regprocedure);
        v_old text := $o$          v_phase := 'finding central pages';
          perform security.provider_task_fire_v1('central_find');$o$;
begin
  if position('fill asks for its central page search' in v_def) > 0 then return; end if;
  if md5(v_def) <> '33f0a68bffa354b09fc6d3576b088846' then raise exception 'live security.admin_job_watch_v1 differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'central page step must occur once'; end if;
  execute replace(v_def, v_old, $n$          v_phase := 'finding central pages';
          -- CF-247 22 Oct 2026: a fill asks for its central page search (the search takes only asked-for or due providers)
          update pipeline.provider_central_search s set requested_at = now() where s.provider_id = v_pid and s.state = 'queued' and s.requested_at is null;
          perform security.provider_task_fire_v1('central_find');$n$);
end $edit$;

-- 2 15-minute stats ------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.stats_15m (
  at timestamptz primary key default now(),
  data jsonb not null
);
comment on table pipeline.stats_15m is 'CF-247 22 Oct 2026: a snapshot every 15 minutes (job stats-15m) of course progress per country, toolset use, worker calls, watchdog states and the gaps found; read by the 15-minute report.';

create or replace function security.stats_15m_fields_v1(p_country text)
returns jsonb language sql stable security definer set search_path = '' as $function$
  with c as materialized (select co.id, co.study_level_id, co.delivery_mode, co.duration_value, co.primary_field_id
                            from catalogue.courses co where co.lifecycle_status = 'active' and security.coverage_country(co.provider_id) = p_country)
  select jsonb_build_object(
    'courses', (select count(*) from c),
    'official_page', (select count(*) from c where exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')),
    'fee', (select count(*) from c where exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.status = 'active')),
    'english', (select count(*) from c where exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and e.status = 'active')),
    'intakes', (select count(*) from c where exists (select 1 from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active')),
    'campus', (select count(*) from c where exists (select 1 from catalogue.course_campuses k where k.course_id = c.id)),
    'level', (select count(*) from c where c.study_level_id is not null),
    'delivery', (select count(*) from c where c.delivery_mode is not null),
    'duration', (select count(*) from c where c.duration_value is not null),
    'field_of_study', (select count(*) from c where c.primary_field_id is not null))
$function$;
revoke all on function security.stats_15m_fields_v1(text) from public, anon, authenticated;

create or replace function security.stats_15m_v1(p_countries text[] default array['NZ', 'CA'])
returns jsonb language plpgsql security definer set search_path = '' set statement_timeout to '120s' as $function$
declare
  v_now timestamptz := now(); v_prev jsonb; v_day jsonb; v_countries jsonb := '{}'::jsonb; v_c text; v_f jsonb; v_gaps jsonb := '[]'::jsonb; v_data jsonb;
  v_slow numeric := security.pipeline_num_v1('stats.slow_call_seconds', 60);
  v_wait interval := make_interval(mins => security.pipeline_num_v1('stats.task_wait_minutes', 60)::int);
  v_flat interval := make_interval(hours => security.pipeline_num_v1('stats.flat_field_hours', 24)::int);
  v_fc jsonb; v_ai jsonb; v_calls jsonb; v_queues jsonb; v_tasks jsonb; v_old jsonb; k text;
begin
  select s.data into v_prev from pipeline.stats_15m s where s.at > v_now - interval '25 minutes' order by s.at desc limit 1;  -- fixed: the previous 15-minute snapshot
  select s.data into v_day from pipeline.stats_15m s where s.at <= v_now - interval '24 hours' order by s.at desc limit 1;  -- fixed: the same time yesterday
  select s.data into v_old from pipeline.stats_15m s where s.at <= v_now - v_flat order by s.at desc limit 1;  -- fixed: one snapshot
  foreach v_c in array p_countries loop
    v_f := security.stats_15m_fields_v1(v_c);
    v_countries := v_countries || jsonb_build_object(v_c, jsonb_build_object('now', v_f,
      'change_15m', (select jsonb_object_agg(e.key, (e.value)::numeric - coalesce((v_prev->'countries'->v_c->'now'->>e.key)::numeric, (e.value)::numeric)) from jsonb_each(v_f) e),
      'change_24h', case when v_day is null then null else (select jsonb_object_agg(e.key, (e.value)::numeric - coalesce((v_day->'countries'->v_c->'now'->>e.key)::numeric, (e.value)::numeric)) from jsonb_each(v_f) e) end));
    -- gap: a field below every course that has not moved since the snapshot stats.flat_field_hours ago
    if v_old is not null then
      for k in select e.key from jsonb_each(v_f) e where e.key <> 'courses' and (e.value)::numeric < (v_f->>'courses')::numeric
                 and (e.value)::numeric <= coalesce((v_old->'countries'->v_c->'now'->>e.key)::numeric, -1) loop
        v_gaps := v_gaps || jsonb_build_object('kind', 'field_flat', 'country', v_c, 'field', k, 'held', (v_f->>k)::numeric, 'courses', (v_f->>'courses')::numeric,
                                               'note', v_c || ' ' || k || ' has not gained a course in ' || extract(epoch from v_flat)::int / 3600 || ' hours');
      end loop;
    end if;
  end loop;

  -- Firecrawl: units in the last 15 minutes and today by share
  v_fc := security.fc_budget_status_v1() || jsonb_build_object('last_15m', (select coalesce(jsonb_object_agg(g, n), '{}'::jsonb) from (
            select security.fc_purpose_group_v1(u.purpose) g, sum(u.units) n from pipeline.coverage_vendor_usage u where u.at > v_now - interval '15 minutes' group by 1) z));  -- fixed: the 15-minute window
  for k in select x->>'group' from jsonb_array_elements(v_fc->'groups') x where (x->>'share')::numeric > 0 and ((x->>'used')::numeric >= (x->>'share')::numeric or (x->>'refused')::numeric > 0) loop
    v_gaps := v_gaps || (select jsonb_build_object('kind', 'firecrawl_share', 'group', x->>'group', 'used', (x->>'used')::numeric, 'share', (x->>'share')::numeric, 'refused', (x->>'refused')::numeric,
                                 'note', 'Firecrawl share "' || (x->>'label') || '": ' || (x->>'used') || ' of ' || (x->>'share') || ' used today, ' || (x->>'refused') || ' refused')
                           from jsonb_array_elements(v_fc->'groups') x where x->>'group' = k);
  end loop;

  -- AI spend today by use against its guard
  v_ai := (select coalesce(jsonb_agg(jsonb_build_object('use', a.use, 'label', a.label, 'spent_usd', a.spent, 'guard_usd', a.guard, 'calls', a.calls)), '[]'::jsonb) from security.ai_spend_today_v1() a);
  v_gaps := v_gaps || (select coalesce(jsonb_agg(jsonb_build_object('kind', 'ai_guard', 'use', a.use, 'note', 'AI guard reached for ' || a.label || ': US$' || a.spent || ' of ' || a.guard)), '[]'::jsonb)
                         from security.ai_spend_today_v1() a where coalesce(a.guard, 0) > 0 and a.spent >= a.guard);

  -- worker calls in the last 15 minutes by kind
  with r as (select l.mode, x.status_code, x.timed_out, x.error_msg, case when x.content like '{%' then (x.content::jsonb->>'ms')::numeric end ms
               from pipeline.edge_request_log l left join net._http_response x on x.id = l.request_id
              where l.function_name = 'coverage-sweep' and l.created_at > v_now - interval '15 minutes')  -- fixed: the 15-minute window
  select coalesce(jsonb_object_agg(mode, jsonb_build_object('calls', calls, 'failed', failed, 'no_answer', no_answer, 'avg_s', avg_s, 'max_s', max_s)), '{}'::jsonb) into v_calls
    from (select coalesce(r.mode, '?') mode, count(*) calls, count(*) filter (where r.status_code >= 400 or r.timed_out or r.error_msg is not null) failed,
                 count(*) filter (where r.status_code is null and r.error_msg is null) no_answer,
                 round(avg(r.ms) / 1000, 1) avg_s, round(max(r.ms) / 1000, 1) max_s from r group by 1) z;
  v_gaps := v_gaps || (select coalesce(jsonb_agg(jsonb_build_object('kind', 'worker', 'mode', e.key, 'note', 'Worker ' || e.key || ': ' || (e.value->>'failed') || ' of ' || (e.value->>'calls') || ' calls failed, slowest ' || coalesce(e.value->>'max_s', '?') || ' s')), '[]'::jsonb)
                         from jsonb_each(v_calls) e where (e.value->>'failed')::int > 0 or coalesce((e.value->>'max_s')::numeric, 0) > v_slow);

  -- watchdog states and tasks waiting
  v_queues := (select coalesce(jsonb_object_agg(s.key, jsonb_build_object('state', s.state, 'waiting', s.pending, 'per_hour', s.per_hour, 'eta_hours', s.eta_hours)), '{}'::jsonb) from pipeline.queue_watch_state s);
  v_gaps := v_gaps || (select coalesce(jsonb_agg(jsonb_build_object('kind', 'queue', 'queue', s.key, 'state', s.state, 'note', w.label || ': ' || s.state || coalesce(' (' || s.reason || ')', ''))), '[]'::jsonb)
                         from pipeline.queue_watch_state s join pipeline.queue_watch w on w.key = s.key where s.state in ('stuck', 'failing', 'out_of_toolset'));
  v_tasks := (select jsonb_build_object('running', count(*) filter (where j.state = 'running'), 'queued', count(*) filter (where j.state = 'queued'),
                     'not_moving', count(*) filter (where j.state in ('running', 'queued') and j.updated_at < v_now - v_wait),
                     'by_kind', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb) from (select j2.kind, count(*) n from pipeline.admin_jobs j2 where j2.state in ('running', 'queued') group by 1) z))
                from pipeline.admin_jobs j);
  v_gaps := v_gaps || (select coalesce(jsonb_agg(jsonb_build_object('kind', 'task', 'id', j.id, 'note', j.title || ': no progress since ' || to_char(j.updated_at at time zone 'Australia/Melbourne', 'HH24:MI') || coalesce(' (' || (j.progress->>'phase') || ')', ''))), '[]'::jsonb)
                         from pipeline.admin_jobs j where j.state in ('running', 'queued') and coalesce((j.progress->>'done')::numeric, 0) = coalesce((select (p.data->'task_progress'->>(j.id::text))::numeric from pipeline.stats_15m p where p.at <= v_now - v_wait order by p.at desc limit 1), -1)  -- fixed: one snapshot
                           and j.created_at < v_now - v_wait);

  v_data := jsonb_build_object('at', v_now, 'countries', v_countries, 'firecrawl', v_fc, 'ai', v_ai, 'worker_calls_15m', v_calls, 'queues', v_queues, 'tasks', v_tasks,
    'task_progress', (select coalesce(jsonb_object_agg(j.id::text, coalesce((j.progress->>'done')::numeric, 0)), '{}'::jsonb) from pipeline.admin_jobs j where j.state in ('running', 'queued')),
    'gaps', v_gaps);
  insert into pipeline.stats_15m(at, data) values (v_now, v_data);
  return jsonb_build_object('at', v_now, 'gaps', jsonb_array_length(v_gaps));
end $function$;
revoke all on function security.stats_15m_v1(text[]) from public, anon, authenticated;

create or replace function security.stats_15m_report_v1()
returns jsonb language sql stable security definer set search_path = '' as $function$
  select s.data - 'task_progress' from pipeline.stats_15m s order by s.at desc limit 1  -- fixed: the latest snapshot
$function$;
revoke all on function security.stats_15m_report_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('stats-15m', 'Reports', 30, '15-minute stats', 'Every 15 minutes: active courses and fields held for New Zealand and Canada with the change in 15 minutes and 24 hours, Firecrawl and AI use against their shares and guards, worker calls with failures and time, watchdog states, tasks waiting, and the gaps found (pipeline.stats_15m). Settings stats.*.', 4, false, null)
on conflict (jobname) do nothing;
select cron.schedule('stats-15m', '1-59/15 * * * *', $c$select security.stats_15m_v1(array['NZ', 'CA'])$c$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.stats_15m', 'Platform', '15-minute stats snapshots', 'active', '{}', '20261022038000'),
 ('function', 'security.stats_15m_v1', 'Platform', '15-minute stats snapshot', 'active', '{}', '20261022038000'),
 ('function', 'security.stats_15m_fields_v1', 'Platform', 'Fields held per country', 'active', '{}', '20261022038000'),
 ('function', 'security.stats_15m_report_v1', 'Platform', 'Latest 15-minute stats', 'active', '{}', '20261022038000')
on conflict (kind, name) do nothing;

do $dry$ declare t timestamptz := clock_timestamp(); r jsonb; d jsonb; begin
  r := security.stats_15m_v1(array['NZ','CA']); d := security.stats_15m_report_v1();
  raise exception 'DRYRUN OK ms=% r=% NZ=% FC15=% CALLS=% TASKS=% GAPS=% EDIT=%', round(extract(epoch from clock_timestamp()-t)*1000), r, d->'countries'->'NZ'->'now', d->'firecrawl'->'last_15m', left((d->'worker_calls_15m')::text,400), d->'tasks', left((d->'gaps')::text, 900),
   position('fill asks for its central page search' in pg_get_functiondef('security.admin_job_watch_v1(uuid)'::regprocedure))>0;
end $dry$;
