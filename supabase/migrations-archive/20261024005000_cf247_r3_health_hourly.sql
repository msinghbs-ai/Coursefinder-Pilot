-- CF-247 (24 Oct 2026). R3 — Speed 2 hourly delta (plan item 7, schema change 5; Platform Admin 24 Oct 2026 09:55 "then R3 (health-hourly
-- at :11, provisional headline target from its first week)"; record: admin repo docs/platform/nz-enrichment-brief/2026-10-24-au-builds-and-enrichment-jobs.md).
-- Every hour at :11 security.health_hourly_v1() writes one row per metric into pipeline.health_snapshots, all from what the platform already
-- keeps: the 15-minute stats (field counts per country), the R1 worker ledger (calls, items, failures per mode), the R1 queue-wait
-- function, the work-queue watchdog state (why each lane is idle) and the Layer 4 queue. The metrics: headline (pages read and values
-- admitted in the hour against health.headline_target), fields_delta per country (the hour and the day), lane_wait, ledger, idle,
-- bound_empty (bound pages with a stored copy and no admitted value after health.bound_empty_hours), negative_movers (a binding-rate
-- fall, Layer 4 or quarantine growth, a lane with no progress, a field count that fell over the day — each with the window so the
-- cause can be found in admin_control_events or the migrations applied in it) and budget_burn (Firecrawl and AI day shares).
-- The hourly report (scheduled task "StudySearch hourly stats") reads the latest hour from this table; no new panel.
-- health.headline_target starts at 0 ("not yet set"): the first full week of rows gives the provisional target, set by the Platform Admin.
-- Replaces: nothing
-- Retires: nothing

create table if not exists pipeline.health_snapshots (
  at timestamptz not null,
  country text not null default 'ALL',
  metric text not null,
  value jsonb not null,
  primary key (at, country, metric)
);
comment on table pipeline.health_snapshots is 'R3 (24 Oct 2026): hourly delta rollups for the health report — headline, fields_delta per country, lane_wait, ledger, idle, bound_empty, negative_movers, budget_burn; written by health-hourly at :11; 90-day retention (ledger-retention)';
create index if not exists health_snapshots_metric_at_idx on pipeline.health_snapshots (metric, at desc);
alter table pipeline.health_snapshots enable row level security;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'retention.health_snapshots_days', 'Health snapshots: kept for', 'Hourly health rows older than this are removed by the daily ledger-retention job.', 'number', '90'::jsonb, '30', '365', 'days', 772, 'Platform upkeep', 'job ledger-retention', 'R3'),
 ('pipeline', 'health.bound_empty_hours', 'Health: bound but empty after', 'A bound course page with a stored copy and no admitted fee, English score or intake after this many hours is counted as bound-but-empty.', 'number', '12'::jsonb, '2', '72', 'hours', 773, 'Health report', 'security.health_hourly_v1', 'R3'),
 ('pipeline', 'health.stuck_hours', 'Health: lane stuck after', 'A work queue with work waiting and no progress for this many hours is a negative mover.', 'number', '4'::jsonb, '1', '24', 'hours', 774, 'Health report', 'security.health_hourly_v1', 'R3'),
 ('pipeline', 'health.binding_drop_pct', 'Health: binding-rate fall', 'Pages bound in the last day fewer than the day before by this share is a negative mover.', 'number', '10'::jsonb, '1', '50', '%', 775, 'Health report', 'security.health_hourly_v1', 'R3'),
 ('pipeline', 'health.growth_pct', 'Health: review-queue growth', 'Layer 4 rows (or a field count falling) by this share over a day is a negative mover.', 'number', '20'::jsonb, '5', '100', '%', 776, 'Health report', 'security.health_hourly_v1', 'R3'),
 ('pipeline', 'health.burn_warn_pct', 'Health: budget burn warning', 'Share of a day''s Firecrawl or AI allowance used at which the hour is marked.', 'number', '80'::jsonb, '50', '100', '%', 777, 'Health report', 'security.health_hourly_v1', 'R3'),
 ('pipeline', 'health.headline_target', 'Health: headline target', 'Pages read and values admitted the platform should reach in 24 hours; 0 means not yet set (set from the first full week of hourly rows).', 'number', '0'::jsonb, '0', '100000', 'per 24 h', 778, 'Health report', 'security.health_hourly_v1', 'R3: a provisional target, set by the Platform Admin, never by a passing check')
on conflict (toolset_key, key) do nothing;

create or replace function security.health_hourly_v1() returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_at timestamptz := date_trunc('hour', now()); v_hour timestamptz := now() - interval '1 hour'; v_day timestamptz := now() - interval '24 hours';
        v_latest jsonb; v_hour_ago jsonb; v_day_ago jsonb; v_cc text; v_n int := 0; v_target numeric := security.pipeline_num_v1('health.headline_target', 0);
        v_pages int; v_values int; v_movers jsonb := '[]'::jsonb; v_b_now int; v_b_prev int; v_l4_now int; v_l4_prev int; r record;
        v_growth numeric := security.pipeline_num_v1('health.growth_pct', 20); v_drop numeric := security.pipeline_num_v1('health.binding_drop_pct', 10);
        v_stuck numeric := security.pipeline_num_v1('health.stuck_hours', 4); v_burn numeric := security.pipeline_num_v1('health.burn_warn_pct', 80);
begin
  select data into v_latest from pipeline.stats_15m order by at desc limit 1;
  select data into v_hour_ago from pipeline.stats_15m where at <= v_hour order by at desc limit 1;
  select data into v_day_ago from pipeline.stats_15m where at <= v_day order by at desc limit 1;

  -- headline: pages read (ledger, mode read) and values admitted (field counts up over the hour, every country)
  select coalesce(sum(items), 0) into v_pages from pipeline.mode_outcome_ledger where mode = 'read' and run_at > v_hour;
  select coalesce(sum(greatest(0, (v_latest->'countries'->c->'now'->>f)::int - coalesce((v_hour_ago->'countries'->c->'now'->>f)::int, (v_latest->'countries'->c->'now'->>f)::int))), 0) into v_values
    from jsonb_object_keys(coalesce(v_latest->'countries', '{}'::jsonb)) c, unnest(array['fee', 'english', 'intakes', 'official_page', 'campus', 'delivery', 'duration']) f;
  insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, 'ALL', 'headline',
    jsonb_build_object('pages_read', v_pages, 'values_admitted', v_values, 'target_24h', v_target,
                       'pace_24h', (select coalesce(sum((value->>'pages_read')::int + (value->>'values_admitted')::int), 0) from pipeline.health_snapshots where metric = 'headline' and at > v_day) + v_pages + v_values,
                       'target_set', v_target > 0))
  on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;

  -- fields_delta per country: the hour and the day, from the 15-minute stats
  for v_cc in select jsonb_object_keys(coalesce(v_latest->'countries', '{}'::jsonb)) loop
    insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, v_cc, 'fields_delta',
      jsonb_build_object('now', v_latest->'countries'->v_cc->'now',
        'hour', (select jsonb_object_agg(k, (v_latest->'countries'->v_cc->'now'->>k)::int - coalesce((v_hour_ago->'countries'->v_cc->'now'->>k)::int, (v_latest->'countries'->v_cc->'now'->>k)::int)) from jsonb_object_keys(v_latest->'countries'->v_cc->'now') k),
        'day', (select jsonb_object_agg(k, (v_latest->'countries'->v_cc->'now'->>k)::int - coalesce((v_day_ago->'countries'->v_cc->'now'->>k)::int, (v_latest->'countries'->v_cc->'now'->>k)::int)) from jsonb_object_keys(v_latest->'countries'->v_cc->'now') k)))
    on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;
    -- a field count that fell over the day beyond the growth share is a negative mover (the cause is in admin_control_events or a migration of the window)
    for r in select k, (v_latest->'countries'->v_cc->'now'->>k)::int now_v, (v_day_ago->'countries'->v_cc->'now'->>k)::int prev_v from jsonb_object_keys(v_latest->'countries'->v_cc->'now') k loop
      if r.prev_v > 0 and r.now_v < r.prev_v * (1 - v_growth / 100) then
        v_movers := v_movers || jsonb_build_object('kind', 'field_fell', 'country', v_cc, 'field', r.k, 'from', r.prev_v, 'to', r.now_v, 'window', jsonb_build_array(v_day, now()),
                                                   'look_in', 'pipeline.admin_control_events and supabase_migrations.schema_migrations applied in the window');
      end if;
    end loop;
  end loop;

  -- lane_wait and ledger
  insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, 'ALL', 'lane_wait', (select coalesce(jsonb_agg(to_jsonb(w)), '[]'::jsonb) from security.lane_queue_wait_v1(1) w))
  on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;
  insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, 'ALL', 'ledger',
    (select coalesce(jsonb_object_agg(mode, jsonb_build_object('calls', calls, 'items', items, 'ok', ok, 'failed', failed, 'avg_ms', avg_ms)), '{}'::jsonb)
       from (select mode, count(*) calls, sum(items) items, sum(ok) ok, sum(failed) failed, round(avg(ms)) avg_ms from pipeline.mode_outcome_ledger where run_at > v_hour group by mode) z))
  on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;

  -- idle: every watched queue that is not simply moving, with its why-idle line
  insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, 'ALL', 'idle',
    (select coalesce(jsonb_agg(jsonb_build_object('queue', w.key, 'label', w.label, 'state', s.state, 'waiting', s.pending, 'why', security.lane_why_idle_v1(w.key)) order by w.sort), '[]'::jsonb)
       from pipeline.queue_watch w join pipeline.queue_watch_state s on s.key = w.key where w.enabled and (s.state <> 'moving' or coalesce(array_length(s.jobs_paused, 1), 0) > 0 or coalesce(s.done_window, 0) = 0)))
  on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;
  -- a lane with work waiting and no progress for health.stuck_hours is a negative mover
  for r in select w.key, s.pending, s.last_progress from pipeline.queue_watch w join pipeline.queue_watch_state s on s.key = w.key
            where w.enabled and coalesce(s.pending, 0) > 0 and coalesce(s.last_progress, '-infinity') < now() - make_interval(hours => v_stuck::int) loop
    v_movers := v_movers || jsonb_build_object('kind', 'lane_no_progress', 'queue', r.key, 'waiting', r.pending, 'last_progress', r.last_progress, 'why', security.lane_why_idle_v1(r.key));
  end loop;

  -- bound_empty per country: a bound page with a stored copy, read more than health.bound_empty_hours ago, whose course holds no fee, English score or intake
  for r in select k.iso_alpha2 cc, count(*) n
             from pipeline.coverage_course_pages p join pipeline.evidence_artifacts e on e.id = p.evidence_id and e.storage_path is not null
             join catalogue.providers pr on pr.id = p.provider_id join ref.countries k on k.id = pr.country_id
            where p.status = 'bound' and p.read_status = 'read' and p.read_at < now() - make_interval(hours => security.pipeline_num_v1('health.bound_empty_hours', 12)::int)
              and not exists (select 1 from catalogue.course_fees f where f.course_id = p.course_id and f.status = 'active' and f.audience = 'international')
              and not exists (select 1 from catalogue.course_english_requirements q where q.course_id = p.course_id and q.status = 'active')
              and not exists (select 1 from catalogue.course_intakes i where i.course_id = p.course_id and i.status = 'active')
            group by 1 loop
    insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, r.cc, 'bound_empty', jsonb_build_object('pages', r.n, 'after_hours', security.pipeline_num_v1('health.bound_empty_hours', 12)))
    on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;
  end loop;

  -- binding rate and Layer 4 growth over the day against the day before
  select count(*) filter (where bound_at > v_day), count(*) filter (where bound_at between v_day - interval '24 hours' and v_day) into v_b_now, v_b_prev from pipeline.coverage_course_pages where bound_at > v_day - interval '24 hours';
  if v_b_prev > 0 and v_b_now < v_b_prev * (1 - v_drop / 100) then
    v_movers := v_movers || jsonb_build_object('kind', 'binding_rate_fell', 'from', v_b_prev, 'to', v_b_now);
  end if;
  select count(*) filter (where created_at > v_day), count(*) filter (where created_at between v_day - interval '24 hours' and v_day) into v_l4_now, v_l4_prev from pipeline.layer4_review_items where created_at > v_day - interval '24 hours';
  if v_l4_now > greatest(10, v_l4_prev * (1 + v_growth / 100)) then
    v_movers := v_movers || jsonb_build_object('kind', 'layer4_grew', 'from', v_l4_prev, 'to', v_l4_now, 'pending_total', (select count(*) from pipeline.layer4_review_items where status = 'pending'));
  end if;
  insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, 'ALL', 'negative_movers', v_movers)
  on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;

  -- budget burn from the latest 15-minute stats
  insert into pipeline.health_snapshots(at, country, metric, value) values (v_at, 'ALL', 'budget_burn',
    jsonb_build_object(
      'firecrawl', (select jsonb_agg(jsonb_build_object('group', g->>'group', 'used', (g->>'used')::numeric, 'share', (g->>'share')::numeric,
                                                        'warn', (g->>'share')::numeric > 0 and (g->>'used')::numeric >= (g->>'share')::numeric * v_burn / 100))
                      from jsonb_array_elements(coalesce(v_latest->'firecrawl'->'groups', '[]'::jsonb)) g),
      'ai', (select jsonb_agg(jsonb_build_object('use', a->>'use', 'spent_usd', (a->>'spent_usd')::numeric, 'guard_usd', (a->>'guard_usd')::numeric,
                                                 'warn', (a->>'guard_usd')::numeric > 0 and (a->>'spent_usd')::numeric >= (a->>'guard_usd')::numeric * v_burn / 100))
               from jsonb_array_elements(coalesce(v_latest->'ai', '[]'::jsonb)) a),
      'warn_pct', v_burn))
  on conflict (at, country, metric) do update set value = excluded.value; v_n := v_n + 1;

  return jsonb_build_object('at', v_at, 'rows', v_n, 'pages_read', v_pages, 'values_admitted', v_values, 'negative_movers', jsonb_array_length(v_movers));
end $function$;
comment on function security.health_hourly_v1() is 'R3: hourly delta rollup into pipeline.health_snapshots (headline, fields_delta, lane_wait, ledger, idle, bound_empty, negative_movers, budget_burn); read by the hourly report';

-- the latest hour for the report, one call
create or replace function security.health_latest_v1() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(country || ':' || metric, value), '{}'::jsonb) from pipeline.health_snapshots where at = (select max(at) from pipeline.health_snapshots)
$$;

-- retention: the ledger-retention job (R1) also removes old health rows (the R1 definition is replaced whole, md5-checked)
do $g$ begin
  if md5(pg_get_functiondef('security.ledger_retention_v1()'::regprocedure)) <> '5b5d9103d3d3ec4b90f11f1b06429ace' then
    raise exception 'live security.ledger_retention_v1 differs from the R1 definition this change replaces';
  end if;
end $g$;
create or replace function security.ledger_retention_v1() returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare n_ledger int; n_zy int; n_h int;
begin
  delete from pipeline.mode_outcome_ledger where run_at < now() - make_interval(days => security.pipeline_num_v1('retention.mode_outcome_ledger_days', 90)::int);
  get diagnostics n_ledger = row_count;
  delete from pipeline.zero_yield_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.zero_yield_snapshots_days', 90)::int);
  get diagnostics n_zy = row_count;
  delete from pipeline.health_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.health_snapshots_days', 90)::int);
  get diagnostics n_h = row_count;
  return jsonb_build_object('mode_outcome_ledger', n_ledger, 'zero_yield_snapshots', n_zy, 'health_snapshots', n_h);
end $function$;

-- the 15-minute stats cover the countries named in a setting (the job command carried array['NZ', 'CA'] in code); AU joins them
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'stats.countries', 'Stats: countries measured', 'Country codes the 15-minute stats and the hourly health rows cover.', 'list', '["NZ","AU","CA"]'::jsonb, null, null, 'countries', 779, 'Health report', 'job stats-15m', 'R3: the list lived in the job command')
on conflict (toolset_key, key) do nothing;
do $g$ declare v_id bigint; begin
  select jobid into v_id from cron.job where jobname = 'stats-15m';
  if v_id is null then raise exception 'job stats-15m not found'; end if;
  perform cron.alter_job(v_id, command := $$select security.stats_15m_v1(array(select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'stats.countries'), '["NZ","CA"]'::jsonb))))$$);
end $g$;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('health-hourly', 'Platform upkeep', 96, 'Health: hourly delta', 'Hourly at :11: writes the hour''s health rows (pages read and values admitted against Health: headline target, field changes per country over the hour and the day, queue wait per lane, worker calls per mode, idle lanes with why, bound-but-empty pages, negative movers, budget burn) into pipeline.health_snapshots for the hourly report.', 6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('health-hourly', '11 * * * *', $$select security.health_hourly_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.health_snapshots', 'Layer 2', 'R3 hourly health rows', 'active', '{}', '20261024005000'),
 ('function', 'security.health_hourly_v1', 'Layer 2', 'R3 hourly delta rollup', 'active', '{}', '20261024005000'),
 ('function', 'security.health_latest_v1', 'Layer 2', 'latest hour for the report', 'active', '{}', '20261024005000'),
 ('job', 'health-hourly', 'Layer 2', 'hourly health rollup at :11', 'active', '{}', '20261024005000')
on conflict (kind, name) do nothing;

select 'R3: health_snapshots, health_hourly_v1 at :11, settings, retention' ok;
