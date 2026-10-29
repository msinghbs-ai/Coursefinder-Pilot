-- CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53, lane M2): cached snapshots for three slow admin reads, and the actual run time of
-- "Why values are missing". Numbered 20261030150000 at integration (v2.15.373).
-- Approved: "Cached snapshots for the four slow admin reads: APPROVED FOR DESIGN AND IMPLEMENTATION. ... Keep them read-only and derived; no
-- consumer/API or admission behaviour change. Show snapshot generation time and staleness. Define bounded refresh/invalidation and prevent
-- expensive concurrent rebuild stampedes. Preserve permission checks and exact live-detail drilldowns." and "'Why values are missing' run time:
-- APPROVED. Display the actual source run/snapshot time consistently with the hourly reporting correction."
-- Why (measured read-only on 30 Oct 2026, as the Platform Admin): admin_platform_notices_read 3.2 s (security.platform_notices_v1 3.2 to 4.3 s,
-- it re-reads 7 days of cron.job_run_details, about 118,000 rows with no index we can add; security.toolset_sample_notices_v1 0.6 s);
-- admin_progress_read('overview') 2.7 s and ('running') 4.4 s; admin_waiting_read 1.5 s; security.scholarship_publishability_v1 0.7 to 2.8 s
-- (14 s once under load); admin_field_coverage('overview') 1.3 to 1.5 s (providers by country 0.25 to 1.9 s with security.coverage_country per
-- provider, max(computed_at) over 524,732 coverage rows 0.47 s, courses by country 0.1 to 0.4 s, security.ai_spend_today_v1 0.12 to 0.47 s).
-- 78, 19 and 11 statement timeouts in 48 hours.
-- What:
--  1. pipeline.admin_read_snapshots holds one derived snapshot for each slow source: 'platform_notices' (security.platform_notices_v1 and
--     security.toolset_sample_notices_v1), 'scholarship_publishability' (security.scholarship_publishability_v1, every row) and 'field_coverage'
--     (the overview's course and provider figures by country for every country, the coverage build time and today's Enrich fields AI spend).
--     Job admin-read-snapshots (each minute) rebuilds a snapshot when it is older than its setting (snapshots.*_every_minutes), or at once
--     after a person's action makes it out of date (a search resumed or held, a website entered by hand, a scholarship publication batch).
--     Single flight: each build takes a transaction advisory try-lock, so an overlapping run skips it instead of building it twice. The
--     screens never build a snapshot; only before the first build do they read live, exactly as before.
--  2. The reads answer from the snapshot and add only fields: 'snapshot' / 'notices_snapshot' / 'publishability_snapshot' (generation time,
--     age, stale against snapshots.stale_after_minutes, refresh interval, last error). Returned shapes are unchanged.
--  3. Exactness kept where a person acts: permission checks unchanged; notice acknowledgements, publication status and lifecycle are joined
--     live; universities a person has resumed since the snapshot, and providers given a website since, leave the notice's list at once;
--     a notice stamped "now" by its builder is still answered as "now"; a university's own field coverage (provider filter) is read live.
--  4. Why values are missing: job gap-causes now runs security.gap_causes_run_v1(), which builds the same snapshot and records when the run
--     started and finished (pipeline.gap_cause_runs). admin_gap_causes adds 'run' (start, finish, age, stale against
--     gaps.causes_stale_after_minutes, 75 as in the hourly report). The 'at' (the snapshot's hour) is unchanged.
-- Replaces: per-open recomputation of security.platform_notices_v1 and security.toolset_sample_notices_v1 in public.admin_platform_notices_read and public.admin_progress_read('overview'), of security.scholarship_publishability_v1 in public.admin_waiting_read and security.admin_live_activity_v1, and of the provider and course figures, coverage time and AI spend in public.admin_field_coverage('overview'), with snapshots in pipeline.admin_read_snapshots (job admin-read-snapshots); the gap-causes job command "select security.gap_causes_snapshot_v1()" with "select security.gap_causes_run_v1()" (the same snapshot, with its run time recorded)
-- Retires: nothing (the live builders stay as the snapshot sources and as the first-open fallback; no table, job, function or edge function retires)
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266): every edited function is an admin read
-- (public.admin_*, security.admin_live_activity_v1); security.scholarship_publishability_v1, which publishing and the auto-publish job use,
-- is not changed and is still what they read. No admission or publishing behaviour changes.

-- 1. settings (G2): refresh intervals and the stale thresholds
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'snapshots.platform_notices_every_minutes', 'Cached notices: rebuilt every',
  'Toolset notices (Layer pages, Toolsets and limits, Progress) are read from a snapshot rebuilt this often. A person''s fix (Search again, a website entered) rebuilds it within a minute. Each build reads about 3 to 4 seconds.', 'number',
  to_jsonb(5), 1, 60, 'minutes', 788, 'Platform upkeep', 'job admin-read-snapshots; public.admin_platform_notices_read, public.admin_progress_read (overview)',
  'CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): notices took 3 s on every open (78 time-outs in 48 h)'),
 ('pipeline', 'snapshots.scholarship_publishability_every_minutes', 'Cached scholarship publishability: rebuilt every',
  'Which scholarships are ready to publish (Dashboard › Also, live activity) is read from a snapshot rebuilt this often; publication status is read live. A publication batch rebuilds it within a minute.', 'number',
  to_jsonb(10), 1, 120, 'minutes', 789, 'Platform upkeep', 'job admin-read-snapshots; public.admin_waiting_read, security.admin_live_activity_v1',
  'CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): the publishability check took up to 2.8 s on every open (19 time-outs in 48 h)'),
 ('pipeline', 'snapshots.field_coverage_every_minutes', 'Cached field coverage: rebuilt every',
  'Coverage › Every field by country (provider and course figures by country, today''s Enrich fields AI spend) is read from a snapshot rebuilt this often. One university''s figures are always read live.', 'number',
  to_jsonb(10), 1, 120, 'minutes', 790, 'Platform upkeep', 'job admin-read-snapshots; public.admin_field_coverage (overview)',
  'CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): the overview took 1.3 to 1.5 s on every open (11 time-outs in 48 h)'),
 ('pipeline', 'snapshots.stale_after_minutes', 'Cached admin figures: marked stale after',
  'A cached figure older than this is marked Stale on screen (its time and age are always shown). Keep it above the longest rebuild interval.', 'number',
  to_jsonb(30), 5, 240, 'minutes', 791, 'Platform upkeep', 'security.admin_read_snapshot_meta_v1 (notices, publishability, field coverage)',
  'CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): show snapshot generation time and staleness'),
 ('pipeline', 'gaps.causes_stale_after_minutes', 'Why values are missing: marked stale after',
  'Why values are missing shows the time its last run finished and how long ago; older than this it is marked Stale. The job runs every hour at :55.', 'number',
  to_jsonb(75), 30, 1440, 'minutes', 613, 'Enrichment', 'public.admin_gap_causes (security.gap_causes_run_meta_v1); Platform health › Why values are missing',
  'CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): the actual run time, consistent with the hourly report (75 minutes)')
on conflict (toolset_key, key) do nothing;

-- 2. tables
create table if not exists pipeline.admin_read_snapshots (
  key text primary key check (key in ('platform_notices', 'scholarship_publishability', 'field_coverage')),
  payload jsonb not null,
  stamp timestamptz not null,          -- the building transaction's now(): what "now" meant inside the builders
  generated_at timestamptz not null,   -- when this build started reading (shown on screen)
  took_ms integer not null,
  item_count integer,
  refreshed_by text not null check (refreshed_by in ('job', 'migration')),
  last_error text,
  last_error_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table pipeline.admin_read_snapshots is 'CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): derived, read-only snapshots of three slow admin sources (platform notices, scholarship publishability, field coverage by country), rebuilt by job admin-read-snapshots on the snapshots.* settings; admin reads answer from them with their generation time and a stale flag. Never read by the consumer API.';
alter table pipeline.admin_read_snapshots enable row level security;
revoke all on pipeline.admin_read_snapshots from public, anon, authenticated;

create table if not exists pipeline.gap_cause_runs (
  started_at timestamptz primary key,
  at timestamptz not null,             -- the snapshot hour the run wrote (pipeline.gap_cause_snapshots.at)
  finished_at timestamptz not null,
  item_count integer not null,
  source text not null default 'job' check (source in ('job', 'cron_history'))
);
create index if not exists gap_cause_runs_at_idx on pipeline.gap_cause_runs (at, finished_at desc);
comment on table pipeline.gap_cause_runs is 'CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): each successful gap-causes run (security.gap_causes_run_v1) with the snapshot hour it wrote and when it started and finished, so Why values are missing shows the actual run time; kept gaps.cause_keep_days like the snapshots.';
alter table pipeline.gap_cause_runs enable row level security;
revoke all on pipeline.gap_cause_runs from public, anon, authenticated;

-- 3. the snapshot builders, the refresh job and the meta every read shows
create or replace function security.admin_read_snapshot_every_v1(p_key text)
returns numeric language sql stable security definer set search_path = '' as $function$
  select greatest(case p_key
    when 'platform_notices' then security.pipeline_num_v1('snapshots.platform_notices_every_minutes', 5)
    when 'scholarship_publishability' then security.pipeline_num_v1('snapshots.scholarship_publishability_every_minutes', 10)
    when 'field_coverage' then security.pipeline_num_v1('snapshots.field_coverage_every_minutes', 10) end, 1)
$function$;

create or replace function security.admin_read_snapshot_build_v1(p_key text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if p_key = 'platform_notices' then
    return jsonb_build_object('notices', coalesce(security.platform_notices_v1(), '[]'::jsonb), 'samples', coalesce(security.toolset_sample_notices_v1(), '[]'::jsonb));
  elsif p_key = 'scholarship_publishability' then
    return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_object('scholarship_id', x.scholarship_id, 'publishable', x.publishable, 'missing', to_jsonb(x.missing)))
                                                  from security.scholarship_publishability_v1() x), '[]'::jsonb));
  elsif p_key = 'field_coverage' then
    -- the queries of public.admin_field_coverage('overview') for every country and no provider filter (the screen filters by country)
    return jsonb_build_object(
      'courses_by_country', (select coalesce(jsonb_agg(jsonb_build_object('country', x.country_code, 'field', x.attribute, 'total', x.total, 'filled', x.filled,
                                                                        'in_queue', x.in_queue, 'not_stated', x.not_stated, 'in_review', x.in_review)), '[]'::jsonb)
                               from (select a.country_code, a.attribute, count(*) total, count(*) filter (where a.state = 'admitted') filled,
                                            count(*) filter (where a.state = 'in_queue') in_queue, count(*) filter (where a.state = 'not_on_page') not_stated,
                                            count(*) filter (where a.state in ('in_review', 'candidate', 'awaiting_l3')) in_review
                                       from pipeline.course_attribute_coverage a group by 1, 2) x),
      'providers_by_country', (select coalesce(jsonb_agg(jsonb_build_object('country', z.cc, 'field', z.field, 'total', z.total, 'filled', z.filled)), '[]'::jsonb)
                                 from (select p.cc, f.field, count(*) total, count(*) filter (where f.has) filled
                                         from (select p.*, security.coverage_country(p.id) cc from catalogue.providers p
                                                where coalesce(p.lifecycle_status, 'active') = 'active' and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')) p
                                         cross join lateral (values
                                           ('p_website', nullif(btrim(p.website), '') is not null),
                                           ('p_address', nullif(btrim(p.address_line1), '') is not null),
                                           ('p_campuses', exists (select 1 from catalogue.campuses k where k.provider_id = p.id)),
                                           ('p_type', p.provider_type_id is not null),
                                           ('p_international', p.enrols_international is not null),
                                           ('p_logo', nullif(btrim(p.logo_url), '') is not null or exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.asset_type = 'logo')),
                                           ('p_contact', nullif(btrim(p.phone), '') is not null or nullif(btrim(p.email), '') is not null),
                                           ('p_scholarships', exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')),
                                           ('p_description', nullif(btrim(p.description), '') is not null)) f(field, has)
                                        group by 1, 2) z),
      'computed_at', (select max(computed_at) from pipeline.course_attribute_coverage),
      'ai_spent_today_usd', (select x.spent from security.ai_spend_today_v1() x where x.use = 'enrich_fields'));
  end if;
  raise exception 'unknown snapshot %', p_key using errcode = '22023';
end $function$;

create or replace function security.admin_read_snapshots_refresh_v1(p_force boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare k text; v_s pipeline.admin_read_snapshots%rowtype; v_due boolean; v_t timestamptz; v_payload jsonb; v_out jsonb := '{}'::jsonb;
begin
  foreach k in array array['platform_notices', 'scholarship_publishability', 'field_coverage'] loop
    v_s := null;
    select * into v_s from pipeline.admin_read_snapshots s where s.key = k;
    v_due := p_force or v_s.key is null
      -- fixed: fire guard (the job runs each minute; a rebuild due this minute is not put off by a few seconds of start jitter)
      or v_s.generated_at <= clock_timestamp() - make_interval(mins => security.admin_read_snapshot_every_v1(k)::int) + interval '20 seconds'
      -- a person's action since the snapshot: rebuilt on the next run (within a minute), not at the next interval
      or (k = 'platform_notices' and (exists (select 1 from pipeline.firecrawl_search_resumes r where r.resumed_at > v_s.stamp)
                                      or exists (select 1 from pipeline.firecrawl_search_holds h where h.held_at > v_s.stamp)
                                      or exists (select 1 from pipeline.coverage_provider_discovery d where d.site_source = 'manual' and d.site_searched_at > v_s.stamp)))
      or (k = 'scholarship_publishability' and exists (select 1 from pipeline.scholarship_publication_batches b where b.created_at > v_s.stamp));
    if not v_due then v_out := v_out || jsonb_build_object(k, 'fresh'); continue; end if;
    -- single flight: an overlapping run that is already building this snapshot is not joined by a second build
    if not pg_try_advisory_xact_lock(hashtextextended('cf247.w35.admin_read_snapshot.' || k, 0)) then v_out := v_out || jsonb_build_object(k, 'busy'); continue; end if;
    v_t := clock_timestamp();
    begin
      v_payload := security.admin_read_snapshot_build_v1(k);
      insert into pipeline.admin_read_snapshots as s (key, payload, stamp, generated_at, took_ms, item_count, refreshed_by, last_error, last_error_at, updated_at)
      values (k, v_payload, now(), v_t, round(extract(epoch from clock_timestamp() - v_t) * 1000)::int,
              case k when 'platform_notices' then jsonb_array_length(v_payload->'notices') + jsonb_array_length(v_payload->'samples')
                     when 'scholarship_publishability' then jsonb_array_length(v_payload->'rows')
                     else jsonb_array_length(v_payload->'providers_by_country') + jsonb_array_length(v_payload->'courses_by_country') end,
              case when p_force then 'migration' else 'job' end, null, null, clock_timestamp())
      on conflict (key) do update set payload = excluded.payload, stamp = excluded.stamp, generated_at = excluded.generated_at, took_ms = excluded.took_ms,
        item_count = excluded.item_count, refreshed_by = excluded.refreshed_by, last_error = null, last_error_at = null, updated_at = excluded.updated_at;
      v_out := v_out || jsonb_build_object(k, jsonb_build_object('built_ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)::int));
    exception when others then
      -- the last good snapshot stays and turns stale; the error is shown with it
      update pipeline.admin_read_snapshots set last_error = left(sqlerrm, 500), last_error_at = clock_timestamp() where key = k;
      v_out := v_out || jsonb_build_object(k, 'failed: ' || left(sqlerrm, 200));
    end;
  end loop;
  return v_out;
end $function$;

create or replace function security.admin_read_snapshot_meta_v1(p_key text)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select case when s.key is null then jsonb_build_object('source', 'live', 'generated_at', now(), 'age_seconds', 0, 'stale', false)
    else jsonb_build_object('source', 'snapshot', 'generated_at', s.generated_at,
      'age_seconds', greatest(round(extract(epoch from now() - s.generated_at)), 0)::int,
      'stale', now() - s.generated_at > make_interval(mins => security.pipeline_num_v1('snapshots.stale_after_minutes', 30)::int),
      'stale_after_minutes', security.pipeline_num_v1('snapshots.stale_after_minutes', 30),
      'refresh_every_minutes', security.admin_read_snapshot_every_v1(p_key),
      'took_ms', s.took_ms, 'last_error', s.last_error, 'last_error_at', s.last_error_at) end
    from (select p_key k) q left join pipeline.admin_read_snapshots s on s.key = q.k
$function$;

-- the notices as the screens read them: from the snapshot, with today's acknowledgement rule kept and items acted on since left out
create or replace function security.platform_notices_cached_v1(p_with_samples boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_s pipeline.admin_read_snapshots%rowtype;
begin
  select * into v_s from pipeline.admin_read_snapshots s where s.key = 'platform_notices';
  if v_s.key is null then
    -- before the first build only: read live, exactly as before W35
    return coalesce(security.platform_notices_v1(), '[]'::jsonb) || case when p_with_samples then coalesce(security.toolset_sample_notices_v1(), '[]'::jsonb) else '[]'::jsonb end;
  end if;
  return coalesce((
    select jsonb_agg(x.n order by x.o)
      from (select e.o, e.n ? 'items' had_items, it.items,
                   e.n
                   -- a notice its builder stamped "now" is still "now" (so an acknowledgement before this moment does not hide it, as before)
                   || case when (e.n->>'last_at')::timestamptz = v_s.stamp then jsonb_build_object('last_at', now()) else '{}'::jsonb end
                   || case when (e.n->>'first_at')::timestamptz = v_s.stamp then jsonb_build_object('first_at', now()) else '{}'::jsonb end
                   || case when it.items is not null and jsonb_array_length(it.items) < jsonb_array_length(e.n->'items')
                           then jsonb_build_object('items', it.items, 'count', greatest(coalesce((e.n->>'count')::int, 0) - (jsonb_array_length(e.n->'items') - jsonb_array_length(it.items)), 0))
                           else '{}'::jsonb end n
              from jsonb_array_elements(coalesce(v_s.payload->'notices', '[]'::jsonb)
                                        || case when p_with_samples then coalesce(v_s.payload->'samples', '[]'::jsonb) else '[]'::jsonb end) with ordinality e(n, o)
              left join lateral (
                -- exact drill-down: a university a person resumed since the snapshot, or a provider given a website since, leaves the list now
                select coalesce(jsonb_agg(i.v order by i.k), '[]'::jsonb) items
                  from jsonb_array_elements(e.n->'items') with ordinality i(v, k)
                 where not (e.n->>'kind' in ('search_held', 'search_stopped')
                            and exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = (i.v->>'provider_id')::uuid and r.resumed_at > v_s.stamp))
                   and not (e.n->>'kind' = 'no_official_site'
                            and exists (select 1 from catalogue.providers p where p.id = (i.v->>'provider_id')::uuid and nullif(btrim(p.website), '') is not null))
              ) it on jsonb_typeof(e.n->'items') = 'array') x
     where not (x.had_items and jsonb_array_length(x.items) = 0)), '[]'::jsonb);
end $function$;

-- every scholarship's publishability as the admin reads use it: from the snapshot (publication status and lifecycle are joined live by the reads)
create or replace function security.scholarship_publishability_cached_v1()
returns table(scholarship_id uuid, publishable boolean, missing text[]) language sql stable security definer set search_path = '' as $function$
  select x.scholarship_id, x.publishable, x.missing
    from pipeline.admin_read_snapshots s cross join lateral jsonb_to_recordset(s.payload->'rows') x(scholarship_id uuid, publishable boolean, missing text[])
   where s.key = 'scholarship_publishability'
  union all
  -- before the first build only: read live, exactly as before W35
  select p.scholarship_id, p.publishable, p.missing from security.scholarship_publishability_v1() p
   where not exists (select 1 from pipeline.admin_read_snapshots s where s.key = 'scholarship_publishability')
$function$;

-- 4. Why values are missing: the run, with its actual start and finish
create or replace function security.gap_causes_run_v1()
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_start timestamptz := clock_timestamp(); v_rows int; v_end timestamptz;
begin
  v_rows := security.gap_causes_snapshot_v1();
  v_end := clock_timestamp();
  insert into pipeline.gap_cause_runs(started_at, at, finished_at, item_count, source) values (v_start, date_trunc('hour', now()), v_end, coalesce(v_rows, 0), 'job')
  on conflict (started_at) do nothing;
  delete from pipeline.gap_cause_runs where started_at < now() - make_interval(days => security.pipeline_num_v1('gaps.cause_keep_days', 14)::int);
  return jsonb_build_object('rows', v_rows, 'started_at', v_start, 'finished_at', v_end);
end $function$;

create or replace function security.gap_causes_run_meta_v1(p_at timestamptz)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select case when r.started_at is null then jsonb_build_object('recorded', false, 'stale', p_at is null or now() - p_at > make_interval(mins => security.pipeline_num_v1('gaps.causes_stale_after_minutes', 75)::int),
                                                               'stale_after_minutes', security.pipeline_num_v1('gaps.causes_stale_after_minutes', 75))
    else jsonb_build_object('recorded', true, 'started_at', r.started_at, 'finished_at', r.finished_at, 'rows', r.item_count,
      'age_seconds', greatest(round(extract(epoch from now() - r.finished_at)), 0)::int,
      'stale', now() - r.finished_at > make_interval(mins => security.pipeline_num_v1('gaps.causes_stale_after_minutes', 75)::int),
      'stale_after_minutes', security.pipeline_num_v1('gaps.causes_stale_after_minutes', 75)) end
    from (select 1) one left join lateral (select g.* from pipeline.gap_cause_runs g where g.at = p_at order by g.finished_at desc limit 1) r on true
$function$;

revoke all on function security.admin_read_snapshot_every_v1(text) from public, anon, authenticated;
revoke all on function security.admin_read_snapshot_build_v1(text) from public, anon, authenticated;
revoke all on function security.admin_read_snapshots_refresh_v1(boolean) from public, anon, authenticated;
revoke all on function security.admin_read_snapshot_meta_v1(text) from public, anon, authenticated;
revoke all on function security.platform_notices_cached_v1(boolean) from public, anon, authenticated;
revoke all on function security.scholarship_publishability_cached_v1() from public, anon, authenticated;
revoke all on function security.gap_causes_run_v1() from public, anon, authenticated;
revoke all on function security.gap_causes_run_meta_v1(timestamptz) from public, anon, authenticated;

-- 5. md5-guarded edits of the reads (each edit must apply exactly once to the live definition read on 30 Oct 2026)
create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- live md5 afe21315ffa1abb4ca7339cf5d4e356c read on 30 Oct 2026 (lane M2, read-only)
select pg_temp.edit_n('public.admin_platform_notices_read(integer)', 'afe21315ffa1abb4ca7339cf5d4e356c', array[
  array[$o$v := security.platform_notices_v1() || coalesce(security.toolset_sample_notices_v1(), '[]'::jsonb);$o$,
        $n$v := security.platform_notices_cached_v1(true);  -- CF-247 W35: the cached snapshot (job admin-read-snapshots)$n$],
  array[$o$return jsonb_build_object('can_manage', v_rank >= 6, 'generated_at', now(),$o$,
        $n$return jsonb_build_object('can_manage', v_rank >= 6, 'generated_at', now(), 'snapshot', security.admin_read_snapshot_meta_v1('platform_notices'),$n$]],
  array[1, 1]);

-- live md5 e526fbbad139a8dff69e2b60206462ae read on 30 Oct 2026 (lane M2, read-only)
select pg_temp.edit_n('public.admin_progress_read(text,jsonb)', 'e526fbbad139a8dff69e2b60206462ae', array[
  array[$o$from jsonb_array_elements(security.platform_notices_v1()) n where n->>'toolset' in ('firecrawl', 'openrouter')),$o$,
        $n$from jsonb_array_elements(security.platform_notices_cached_v1(false)) n where n->>'toolset' in ('firecrawl', 'openrouter')),$n$],
  array[$o$        'trend', (select coalesce(jsonb_agg(jsonb_build_object('at', s.at,$o$,
        $n$        'notices_snapshot', security.admin_read_snapshot_meta_v1('platform_notices'),
        'trend', (select coalesce(jsonb_agg(jsonb_build_object('at', s.at,$n$]],
  array[1, 1]);

-- live md5 bb02b729324db20302d0b2d70543c091 read on 30 Oct 2026 (lane M2, read-only); also answers admin_read('live_activity') (lane M owns
-- admin_read, which is not edited: its reply gains one field)
select pg_temp.edit_n('security.admin_live_activity_v1()', 'bb02b729324db20302d0b2d70543c091', array[
  array[$o$from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id)$o$,
        $n$from security.scholarship_publishability_cached_v1() p join scholarship.scholarships s on s.id = p.scholarship_id)$n$],
  array[$o$    'now', now(),$o$,
        $n$    'now', now(), 'publishability_snapshot', security.admin_read_snapshot_meta_v1('scholarship_publishability'),$n$]],
  array[1, 1]);

-- live md5 7e1ed8ba5e92d1a85b3993fd38201617 read on 30 Oct 2026 (lane M2, read-only)
select pg_temp.edit_n('public.admin_waiting_read()', '7e1ed8ba5e92d1a85b3993fd38201617', array[
  array[$o$select count(*) into v_n from security.scholarship_publishability_v1() x join scholarship.scholarships s on s.id = x.scholarship_id$o$,
        $n$select count(*) into v_n from security.scholarship_publishability_cached_v1() x join scholarship.scholarships s on s.id = x.scholarship_id$n$],
  array[$o$'href','#scholarships?tab=coverage','min',5);$o$,
        $n$'href','#scholarships?tab=coverage','min',5,
      'snapshot',security.admin_read_snapshot_meta_v1('scholarship_publishability'));$n$]],
  array[1, 1]);

-- live md5 1ffdf56fabb9c40da896a87a87e412a1 read on 30 Oct 2026 (lane M2, read-only); every other action is unchanged
select pg_temp.edit_n('public.admin_field_coverage(text,jsonb)', '1ffdf56fabb9c40da896a87a87e412a1', array[
  array[$o$v_released int := 0; v_r jsonb;$o$,
        $n$v_released int := 0; v_r jsonb; v_snap jsonb;$n$],
  array[$o$  if p_action = 'overview' then
    select * into v_job$o$,
        $n$  if p_action = 'overview' then
    -- CF-247 W35: every country (no provider filter) answers from the cached snapshot; one university's figures are read live
    v_snap := case when v_pid is null then (select s.payload from pipeline.admin_read_snapshots s where s.key = 'field_coverage') end;
    select * into v_job$n$],
  array[$o$      'courses_by_country', (select coalesce($o$,
        $n$      'courses_by_country', case when v_snap is not null then (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(v_snap->'courses_by_country') e where v_cc is null or e->>'country' = v_cc) else (select coalesce($n$],
  array[$o$group by 1, 2) x),$o$,
        $n$group by 1, 2) x) end,$n$],
  array[$o$      'providers_by_country', (select coalesce($o$,
        $n$      'providers_by_country', case when v_snap is not null then (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(v_snap->'providers_by_country') e where v_cc is null or e->>'country' = v_cc) else (select coalesce($n$],
  array[$o$group by 1, 2) z),$o$,
        $n$group by 1, 2) z) end,$n$],
  array[$o$'computed_at', (select max(computed_at) from pipeline.course_attribute_coverage),$o$,
        $n$'computed_at', case when v_snap is not null then (v_snap->>'computed_at')::timestamptz else (select max(computed_at) from pipeline.course_attribute_coverage) end,$n$],
  array[$o$'ai_spent_today_usd', (select x.spent from security.ai_spend_today_v1() x where x.use = 'enrich_fields'),$o$,
        $n$'ai_spent_today_usd', case when v_snap is not null then (v_snap->>'ai_spent_today_usd')::numeric else (select x.spent from security.ai_spend_today_v1() x where x.use = 'enrich_fields') end,$n$],
  array[$o$'can_decide', v_rank >= 4, 'can_manage', v_rank >= 6);$o$,
        $n$'can_decide', v_rank >= 4, 'can_manage', v_rank >= 6,
      'snapshot', case when v_snap is not null then security.admin_read_snapshot_meta_v1('field_coverage') end);$n$]],
  array[1, 1, 1, 1, 1, 1, 1, 1, 1]);

-- live md5 d2bb3adffc373a8bc0208f6f65281882 read on 30 Oct 2026 (lane M2, read-only)
select pg_temp.edit_n('public.admin_gap_causes(text)', 'd2bb3adffc373a8bc0208f6f65281882', array[
  array[$o$return jsonb_build_object('at', v_at, 'previous', v_prev,$o$,
        $n$return jsonb_build_object('at', v_at, 'previous', v_prev, 'run', security.gap_causes_run_meta_v1(v_at),$n$]],
  array[1]);

-- 6. jobs (G1): the snapshot refresh, catalogued first; gap-causes records its run
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('admin-read-snapshots', 'Reports', 61, 'Cached admin figures',
  'Each minute: rebuilds the cached snapshot of toolset notices, scholarship publishability and field coverage by country when it is older than its setting (Pipeline settings › Platform upkeep, Cached …: rebuilt every), or within a minute of a person''s fix (Search again, a website entered, a publication batch). One build at a time per snapshot; a failed build keeps the last snapshot, which is then marked stale. The screens show each snapshot''s time and age.',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('admin-read-snapshots', '* * * * *', $$select security.admin_read_snapshots_refresh_v1()$$);

select cron.alter_job((select jobid from cron.job where jobname = 'gap-causes'), command := $$select security.gap_causes_run_v1()$$);
update pipeline.automation_catalogue set description = description || ' Each run records when it started and finished (CF-247 W35), shown on Why values are missing.'
 where jobname = 'gap-causes' and description not like '%CF-247 W35%';

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'admin-read-snapshots', 'Platform', 'Reports', 'W35: rebuilds the cached snapshots of the slow admin reads (notices, publishability, field coverage)', 'active', '{}', '20261030150000'),
 ('table', 'pipeline.admin_read_snapshots', 'Platform', 'Reports', 'W35: derived snapshots answered by the admin reads, with generation time and stale flag', 'active', '{}', '20261030150000'),
 ('table', 'pipeline.gap_cause_runs', 'Platform', 'Course pages', 'W35: each gap-causes run with its actual start and finish', 'active', '{}', '20261030150000'),
 ('function', 'security.admin_read_snapshots_refresh_v1', 'Platform', 'Reports', 'W35: job admin-read-snapshots (due check, single-flight build)', 'active', '{}', '20261030150000'),
 ('function', 'security.admin_read_snapshot_build_v1', 'Platform', 'Reports', 'W35: builds one snapshot from the live source', 'active', '{}', '20261030150000'),
 ('function', 'security.admin_read_snapshot_meta_v1', 'Platform', 'Reports', 'W35: generation time, age and stale flag the reads add', 'active', '{}', '20261030150000'),
 ('function', 'security.admin_read_snapshot_every_v1', 'Platform', 'Reports', 'W35: rebuild interval of a snapshot (settings)', 'active', '{}', '20261030150000'),
 ('function', 'security.platform_notices_cached_v1', 'Platform', 'Reports', 'W35: notices from the snapshot, items acted on since left out', 'active', '{}', '20261030150000'),
 ('function', 'security.scholarship_publishability_cached_v1', 'Platform', 'Reports', 'W35: publishability rows from the snapshot (admin reads only)', 'active', '{}', '20261030150000'),
 ('function', 'security.gap_causes_run_v1', 'Platform', 'Course pages', 'W35: job gap-causes (snapshot and its run time)', 'active', '{}', '20261030150000'),
 ('function', 'security.gap_causes_run_meta_v1', 'Platform', 'Course pages', 'W35: the run time, age and stale flag of Why values are missing', 'active', '{}', '20261030150000')
on conflict do nothing;

-- 7. first build now (the job repeats it); the last successful gap-causes run is taken from the cron history once, so the screen has a run time at once
select security.admin_read_snapshots_refresh_v1(true);
insert into pipeline.gap_cause_runs(started_at, at, finished_at, item_count, source)
select d.start_time, date_trunc('hour', d.start_time), d.end_time, coalesce((select count(*) from pipeline.gap_cause_snapshots g where g.at = date_trunc('hour', d.start_time)), 0), 'cron_history'
  from cron.job_run_details d join cron.job j on j.jobid = d.jobid
 where j.jobname = 'gap-causes' and d.status = 'succeeded' and d.end_time is not null and d.start_time > now() - make_interval(days => security.pipeline_num_v1('gaps.cause_keep_days', 14)::int)
   and date_trunc('hour', d.start_time) = (select max(g.at) from pipeline.gap_cause_snapshots g)
 order by d.start_time desc limit 1
on conflict (started_at) do nothing;

-- 8. post-check
do $$
declare v_n int;
begin
  select count(*) into v_n from pipeline.admin_read_snapshots where last_error is null;
  if v_n <> 3 then raise exception 'W35 post-check: % of 3 snapshots built', v_n; end if;
  if pg_get_functiondef('public.admin_waiting_read()'::regprocedure) like '%scholarship_publishability_v1()%'
     or pg_get_functiondef('security.admin_live_activity_v1()'::regprocedure) like '%scholarship_publishability_v1()%'
     or pg_get_functiondef('public.admin_platform_notices_read(integer)'::regprocedure) like '%platform_notices_v1()%'
     or pg_get_functiondef('public.admin_progress_read(text,jsonb)'::regprocedure) like '%security.platform_notices_v1()%'
     or pg_get_functiondef('public.admin_field_coverage(text,jsonb)'::regprocedure) not like '%v_snap->''providers_by_country''%'
     or pg_get_functiondef('public.admin_gap_causes(text)'::regprocedure) not like '%gap_causes_run_meta_v1(v_at)%' then
    raise exception 'W35 post-check: a read still recomputes its slow source on every open';
  end if;
  if not exists (select 1 from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname = 'admin-read-snapshots' and j.active) then
    raise exception 'W35 post-check: job admin-read-snapshots is not scheduled and catalogued';
  end if;
  if (select j.command from cron.job j where j.jobname = 'gap-causes') <> 'select security.gap_causes_run_v1()' then
    raise exception 'W35 post-check: job gap-causes does not record its run';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('snapshots.platform_notices_every_minutes',
        'snapshots.scholarship_publishability_every_minutes', 'snapshots.field_coverage_every_minutes', 'snapshots.stale_after_minutes', 'gaps.causes_stale_after_minutes')) <> 5 then
    raise exception 'W35 post-check: settings missing';
  end if;
end $$;
