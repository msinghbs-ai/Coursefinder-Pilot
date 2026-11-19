-- CF-247 (4 Oct 2026, 01:30 AEST). Platform Admin, 01:24: "Which layer scholarships is configured for data ingest and
-- source urls per country, there can be multiple and other for reference and validation as supplied earlier, review how
-- much ran so far, success, failures and does layer 2 and 3 are configured. I want all [of it] in the UI for
-- scholarship as per layer." Decision 251.
-- Found: the scholarship sources, per-run limits, the re-read interval and the job switches lived in job commands and
-- function text; the four third-party sites reviewed on 3 Oct (internationalscholarships.com, iefa.org,
-- internationalstudent.com, edupass.org) were never registered.
--   1. pipeline.scholarship_layer_settings: the values the scholarship jobs use, each with its layer, limits and the
--      reason for its last change. The discovery, reading and refill jobs and the 30-day re-read read them from here.
--   2. pipeline.scholarship_jobs: what each scholarship job does and which layer it belongs to.
--   3. Every scholarship source carries a role in its metadata: ingest (read into records), provider_pages (a
--      university's own scholarship pages), reference (for looking up) or validation (for comparing with our records).
--      The four reviewed sites are registered as validation or reference sources; nothing reads them automatically.
--   4. public.admin_scholarship_layer_read(layer) and public.admin_scholarship_layer_write(action, args): the
--      Scholarships tab of Layers 1 to 3 and the jobs on Layer 4 › Scholarship publishing. Changes need a Platform Admin
--      and a reason, and are logged. A source added for ingest is registered, not read, until a reader exists for it.

create table if not exists pipeline.scholarship_layer_settings (
  key text primary key,
  layer int not null check (layer between 1 and 4),
  label text not null,
  help text not null,
  value numeric not null,
  min_value numeric not null,
  max_value numeric not null,
  unit text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  reason text
);
alter table pipeline.scholarship_layer_settings enable row level security;
insert into pipeline.scholarship_layer_settings(key, layer, label, help, value, min_value, max_value, unit, reason) values
  ('discover_limit', 2, 'Universities searched per run', 'How many universities the discovery run maps for scholarship pages each time (every 10 minutes).', 6, 1, 6, 'universities', 'Value in the job command until 4 Oct 2026'),
  ('candidate_read_limit', 2, 'Candidate pages read per run', 'How many newly found pages are read and checked for admission in each discovery run.', 30, 1, 60, 'pages', 'Worker default until 4 Oct 2026'),
  ('read_limit', 2, 'Scholarship pages re-read per run', 'How many known scholarship pages are read again each time (every 5 minutes).', 20, 1, 40, 'pages', 'Value in the job command until 4 Oct 2026'),
  ('refill_keep', 2, 'Universities kept waiting for discovery', 'The hourly refill keeps this many universities queued, largest first.', 30, 0, 100, 'universities', 'Value in the job command until 4 Oct 2026'),
  ('reread_days', 2, 'Re-read published and ready pages at least every', 'A published or ready scholarship''s page is read again at least this often.', 30, 7, 180, 'days', 'Value in the function until 4 Oct 2026')
on conflict (key) do nothing;

create or replace function security.scholarship_setting(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = '' as $f$
  select coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key = p_key), p_default)
$f$;
revoke all on function security.scholarship_setting(text, numeric) from public, anon, authenticated;

create table if not exists pipeline.scholarship_jobs (
  jobname text primary key,
  layer int not null check (layer between 1 and 4),
  label text not null,
  what text not null,
  setting_keys text[] not null default '{}',
  sort int not null default 100
);
alter table pipeline.scholarship_jobs enable row level security;
insert into pipeline.scholarship_jobs(jobname, layer, label, what, setting_keys, sort) values
  ('coursefinder-scholarship-etl-scheduler', 1, 'Government feeds', 'Reads the qualified government feeds (Study Australia, Australia Awards) when each is due.', '{}', 10),
  ('coursefinder-scholarship-maintenance', 1, 'Weekly upkeep', 'Weekly tidy-up of scholarship windows and cycles.', '{}', 20),
  ('scholarship-discover', 2, 'Find university scholarship pages', 'Maps the next universities'' sites for scholarship pages, then reads new pages and admits single scholarship pages that are open to international students.', '{discover_limit,candidate_read_limit}', 10),
  ('scholarship-discover-refill', 2, 'Keep the discovery queue filled', 'Queues the next universities in every country with scholarships switched on.', '{refill_keep}', 20),
  ('scholarship-read', 2, 'Re-read scholarship pages', 'Reads known scholarship pages again and applies new values (never a value entered by hand).', '{read_limit}', 30),
  ('scholarship-reread-cadence', 2, 'Re-read cadence', 'Brings forward the next read of published and ready scholarships.', '{reread_days}', 40),
  ('scholarship-audience', 2, 'Who it is for (rules)', 'Reads who each scholarship is for from its wording (Decision 244). Fixed rules, no AI.', '{}', 50),
  ('scholarship-nationality', 2, 'Nationalities (rules)', 'Reads the nationalities a scholarship names (Decision 246). Fixed rules, no AI.', '{}', 60),
  ('scholarship-scope-apply', 2, 'Course links from saved rules', 'Applies saved course-link rules to scholarships.', '{}', 70),
  ('coursefinder-scholarship-ai-change-scheduler', 3, 'AI check on change', 'Sends changed scholarship pages to the AI check when it is switched on with a model that passed its benchmark.', '{}', 10),
  ('scholarship-publication-review', 4, 'Daily publication review', 'Withdraws a published scholarship that no longer passes a check (06:17).', '{}', 10),
  ('scholarship-course-attribute', 4, 'Course scholarships refresh', 'Refreshes the scholarships shown on each course (search, website, Zoho).', '{}', 20),
  ('scholarship-course-attribute-full', 4, 'Course scholarships full refresh', 'Rebuilds every course''s scholarships each night.', '{}', 30),
  ('scholarship-savings', 4, 'Savings', 'Works out the saving a year for each course and scholarship.', '{}', 40)
on conflict (jobname) do nothing;

-- the jobs read their values from the settings
select cron.alter_job((select jobid from cron.job where jobname = 'scholarship-discover'), command := $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_discover','limit',security.scholarship_setting('discover_limit',6)::int,'read_limit',security.scholarship_setting('candidate_read_limit',30)::int))$c$);
select cron.alter_job((select jobid from cron.job where jobname = 'scholarship-read'), command := $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_read','limit',security.scholarship_setting('read_limit',20)::int))$c$);
select cron.alter_job((select jobid from cron.job where jobname = 'scholarship-discover-refill'), command := $c$select security.scholarship_discovery_refill_v1(security.scholarship_setting('refill_keep',30)::int)$c$);

do $g$ declare v_oid oid := 'security.scholarship_reread_cadence_v1()'::regprocedure; v_def text; o text; n text; c int;
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'a1a5a4f3e5849f78300aa3ac3634fc4b' then raise exception 'scholarship_reread_cadence_v1 changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  foreach o in array array[$x$set next_read_at = sp.read_at + interval '30 days' from$x$, $x$> sp.read_at + interval '30 days')$x$] loop
    c := (length(v_def) - length(replace(v_def, o, ''))) / length(o);
    if c <> 1 then raise exception 'reread snippet found % times', c; end if;
    n := replace(o, $x$interval '30 days'$x$, $x$make_interval(days => security.scholarship_setting('reread_days', 30)::int)$x$);
    v_def := replace(v_def, o, n);
  end loop;
  execute v_def;
end $g$;

-- 3. roles on the existing sources
update pipeline.sources set metadata = metadata || jsonb_build_object('scholarship_role', 'ingest') where source_type in ('government_scholarship_program', 'scholarship_catalogue') and metadata->>'scholarship_source_key' in ('au_dfat_australia_awards', 'au_study_australia_scholarships') and metadata->>'scholarship_role' is null;
update pipeline.sources set metadata = metadata || jsonb_build_object('scholarship_role', 'ingest') where source_type = 'scholarship_catalogue' and url = 'https://search.studyaustralia.gov.au/scholarships' and metadata->>'scholarship_role' is null;
update pipeline.sources set metadata = metadata || jsonb_build_object('scholarship_role', 'provider_pages') where source_type in ('scholarship_catalogue', 'scholarship_detail') and metadata->>'scholarship_role' is null;
update pipeline.sources set metadata = metadata || jsonb_build_object('scholarship_role', 'reference') where source_type = 'government_scholarship_program' and metadata->>'scholarship_role' is null;

-- the four sites reviewed on 3 Oct 2026 (docs/scholarships/scholarship-sources-review-2026-10-03.md)
insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
select 'scholarship_reference', (select id from ref.countries where iso_alpha2 = v.cc), v.url, v.label, 30, 'active',
       jsonb_build_object('domain', 'scholarship', 'scholarship_role', v.role, 'decision', 'Decision 251', 'reviewed', '2026-10-03', 'use', v.use_text, 'reader', 'none')
  from (values
    (null, 'https://www.internationalscholarships.com/', 'International Scholarships (aggregator)', 'validation', 'Comparison list only; not a source of record. Details sit behind registration.'),
    (null, 'https://www.iefa.org/', 'IEFA — International Education Financial Aid (aggregator)', 'validation', 'Comparison list and a benchmark for the field-of-study list; not a source of record.'),
    (null, 'https://www.internationalstudent.com/scholarships/', 'InternationalStudent.com scholarships (aggregator)', 'validation', 'Comparison list only; not a source of record.'),
    ('US', 'https://www.edupass.org/finances/databases/', 'EduPASS scholarship databases (US)', 'reference', 'Pointers to funder scholarships for study in the US (Fulbright, AAUW, Aga Khan …); not records.')
  ) v(cc, url, label, role, use_text)
 where not exists (select 1 from pipeline.sources s where s.url = v.url);

-- 4. read and write
create or replace function public.admin_scholarship_layer_read(p_layer int) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  v := jsonb_build_object('layer', p_layer, 'can_manage', v_rank >= 6,
    'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'min', s.min_value, 'max', s.max_value, 'unit', s.unit, 'updated_at', s.updated_at, 'reason', s.reason) order by s.key), '[]'::jsonb)
                   from pipeline.scholarship_layer_settings s where s.layer = p_layer),
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('jobname', j.jobname, 'label', j.label, 'what', j.what, 'settings', j.setting_keys, 'schedule', c.schedule, 'active', c.active,
                     'runs_7d', (select count(*) from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - interval '7 days'),
                     'failed_7d', (select count(*) from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - interval '7 days' and d.status <> 'succeeded'),
                     'last_run', (select max(d.start_time) from cron.job_run_details d where d.jobid = c.jobid),
                     'last_failure', (select left(d.return_message, 200) from cron.job_run_details d where d.jobid = c.jobid and d.status <> 'succeeded' order by d.start_time desc limit 1)) order by j.sort), '[]'::jsonb)
               from pipeline.scholarship_jobs j left join cron.job c on c.jobname = j.jobname where j.layer = p_layer));
  if p_layer = 1 then
    v := v || jsonb_build_object(
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'enabled', k.scholarship_ingestion_enabled, 'currency', k.default_currency_code,
                       'providers', (select count(*) from catalogue.providers p where p.country_id = k.id),
                       'universities_queued', (select count(*) from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = k.id),
                       'scholarships', (select count(*) from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id and s.lifecycle_status = 'active'),
                       'published', (select count(*) from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id and s.lifecycle_status = 'active' and s.publication_status = 'published'),
                       'detail_sources', (select count(*) from pipeline.sources x where x.country_id = k.id and x.source_type = 'scholarship_detail')) order by k.iso_alpha2), '[]'::jsonb)
                     from ref.countries k where k.iso_alpha2 in ('AU', 'NZ', 'CA', 'GB', 'US')),
      'sources', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'country', coalesce(k.iso_alpha2, 'ALL'), 'type', x.source_type, 'role', coalesce(x.metadata->>'scholarship_role', 'reference'),
                     'label', x.label, 'url', x.url, 'status', x.status, 'use', x.metadata->>'use', 'ingestion', x.metadata->>'ingestion', 'reader', x.metadata->>'reader',
                     'qualification', (select q.qualification_status from pipeline.scholarship_source_qualifications q where q.source_key = x.metadata->>'scholarship_source_key' limit 1),
                     'records', (select count(*) from scholarship.scholarships s where s.source_id = x.id and s.lifecycle_status = 'active'),
                     'feed', (select jsonb_build_object('feed', e.feed, 'enabled', e.enabled, 'cadence_hours', e.cadence_hours, 'last_dispatched_at', e.last_dispatched_at, 'next_due_at', e.next_due_at, 'last_error', e.last_error)
                                from pipeline.scholarship_etl_schedules e where e.source_key = x.metadata->>'scholarship_source_key' limit 1))
                     order by coalesce(k.iso_alpha2, 'ZZ'), case coalesce(x.metadata->>'scholarship_role', 'reference') when 'ingest' then 1 when 'provider_pages' then 2 when 'validation' then 3 else 4 end, x.label), '[]'::jsonb)
                   from pipeline.sources x left join ref.countries k on k.id = x.country_id
                  where x.source_type in ('government_scholarship_program', 'scholarship_catalogue', 'scholarship_reference')));
  elsif p_layer = 2 then
    v := v || jsonb_build_object('countries', (
      select coalesce(jsonb_agg(jsonb_build_object('code', k.iso_alpha2,
        'discovery', (select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select d.status, count(*) n from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = k.id group by 1) z),
        'pages_found', (select count(*) from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id),
        'page_reads', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(c.read_status, 'waiting') st, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id group by 1) z),
        'outcomes', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(c.admit_status, case when c.matched_scholarship_id is not null then 'matched_existing' when c.read_status is null then 'waiting' else 'not_decided' end) st, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id group by 1) z),
        'refusals', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.r, 'pages', z.n) order by z.n desc), '[]'::jsonb) from (select r, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id cross join unnest(c.admit_reasons) r where p.country_id = k.id and c.admit_status = 'rejected' group by 1 order by 2 desc limit 6) z),
        'rereads', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(sp.read_status, 'waiting') st, count(*) n from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id group by 1) z)
      ) order by case k.iso_alpha2 when 'AU' then 1 when 'NZ' then 2 when 'CA' then 3 else 4 end), '[]'::jsonb)
      from ref.countries k where k.scholarship_ingestion_enabled and exists (select 1 from catalogue.providers p where p.country_id = k.id)),
      'worker', (select coalesce(jsonb_agg(jsonb_build_object('mode', z.mode, 'sent', z.sent, 'answered', z.answered, 'ok', z.ok, 'failed', z.failed, 'last_failure', z.lf)), '[]'::jsonb) from (
        select l.mode, count(*) sent, count(r.id) answered, count(*) filter (where r.status_code between 200 and 299) ok,
               count(*) filter (where r.status_code >= 300 or r.timed_out or r.error_msg is not null) failed,
               (select left(coalesce(r2.error_msg, r2.content::text), 200) from pipeline.edge_request_log l2 join net._http_response r2 on r2.id = l2.request_id where l2.mode = l.mode and (r2.status_code >= 300 or r2.timed_out or r2.error_msg is not null) order by l2.created_at desc limit 1) lf
          from pipeline.edge_request_log l left join net._http_response r on r.id = l.request_id
         where l.mode like 'scholarship%' and l.created_at > now() - interval '6 hours' group by l.mode) z));
  elsif p_layer = 3 then
    v := v || jsonb_build_object(
      'ai', (select coalesce(jsonb_agg(jsonb_build_object('country', a.country_code, 'enabled', a.enabled, 'state', a.metadata->>'state', 'profile', (select p.code from pipeline.layer3_model_profiles p where p.id = a.default_profile_id),
                 'task', a.default_task_class, 'budget_usd', a.daily_budget_usd, 'max_records', a.max_records_per_run, 'on_change', a.schedule_on_change,
                 'runs', (select count(*) from pipeline.scholarship_ai_runs r where r.country_code = a.country_code)) order by a.country_code), '[]'::jsonb) from pipeline.scholarship_ai_settings a),
      'profiles', (select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'model', p.model_identifier, 'enabled', p.enabled, 'paused', p.paused, 'benchmark_pass', coalesce((p.quality_benchmark->>'pass')::boolean, false)) order by p.code), '[]'::jsonb)
                     from pipeline.layer3_model_profiles p where p.code like '%scholarship%' and p.retired_at is null));
  end if;
  return v;
end $f$;
revoke all on function public.admin_scholarship_layer_read(int) from public, anon;
grant execute on function public.admin_scholarship_layer_read(int) to authenticated;

create or replace function public.admin_scholarship_layer_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_set pipeline.scholarship_layer_settings%rowtype;
        v_num numeric; v_job bigint; v_cc text; v_role text; v_url text; v_id uuid; v_before jsonb; v_after jsonb; v_target text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'setting' then
    select * into v_set from pipeline.scholarship_layer_settings where key = p_args->>'key';
    if v_set.key is null then raise exception 'unknown setting'; end if;
    if coalesce(p_args->>'value', '') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'enter a number'; end if;
    v_num := (p_args->>'value')::numeric;
    if v_num < v_set.min_value or v_num > v_set.max_value then raise exception 'enter a value from % to %', v_set.min_value, v_set.max_value; end if;
    v_before := to_jsonb(v_set.value); v_after := to_jsonb(v_num); v_target := v_set.label;
    update pipeline.scholarship_layer_settings set value = v_num, updated_at = now(), updated_by = auth.uid(), reason = v_reason where key = v_set.key;
  elsif p_action = 'job' then
    if not exists (select 1 from pipeline.scholarship_jobs j where j.jobname = p_args->>'jobname') then raise exception 'unknown job'; end if;
    select jobid, to_jsonb(active) into v_job, v_before from cron.job where jobname = p_args->>'jobname';
    if v_job is null then raise exception 'the job is not scheduled'; end if;
    perform cron.alter_job(v_job, active := (p_args->>'active')::boolean);
    v_after := to_jsonb((p_args->>'active')::boolean); v_target := p_args->>'jobname';
  elsif p_action = 'country' then
    v_cc := upper(coalesce(p_args->>'code', ''));
    select to_jsonb(scholarship_ingestion_enabled) into v_before from ref.countries where iso_alpha2 = v_cc;
    if v_before is null then raise exception 'unknown country'; end if;
    update ref.countries set scholarship_ingestion_enabled = (p_args->>'enabled')::boolean, updated_at = now() where iso_alpha2 = v_cc;
    v_after := to_jsonb((p_args->>'enabled')::boolean); v_target := v_cc;
  elsif p_action = 'feed' then
    select to_jsonb(e) into v_before from pipeline.scholarship_etl_schedules e where e.feed = p_args->>'feed';
    if v_before is null then raise exception 'unknown feed'; end if;
    if p_args ? 'cadence_hours' and ((p_args->>'cadence_hours') !~ '^[0-9]+$' or (p_args->>'cadence_hours')::int not between 24 and 2160) then raise exception 'enter a cadence from 24 to 2160 hours'; end if;
    update pipeline.scholarship_etl_schedules set enabled = coalesce((p_args->>'enabled')::boolean, enabled), cadence_hours = coalesce((p_args->>'cadence_hours')::int, cadence_hours), updated_at = now() where feed = p_args->>'feed';
    select to_jsonb(e) into v_after from pipeline.scholarship_etl_schedules e where e.feed = p_args->>'feed'; v_target := p_args->>'feed';
  elsif p_action = 'source_add' then
    v_role := p_args->>'role'; v_url := btrim(coalesce(p_args->>'url', '')); v_cc := upper(coalesce(p_args->>'country', 'ALL'));
    if v_role not in ('ingest', 'provider_pages', 'reference', 'validation') then raise exception 'choose how the source is used'; end if;
    if v_url !~* '^https?://[^[:space:]]+\.[^[:space:]]+$' then raise exception 'enter the full address, starting with https://'; end if;
    if coalesce(btrim(p_args->>'label'), '') = '' then raise exception 'give the source a name'; end if;
    if v_cc <> 'ALL' and not exists (select 1 from ref.countries where iso_alpha2 = v_cc) then raise exception 'unknown country'; end if;
    if exists (select 1 from pipeline.sources where url = v_url) then raise exception 'this address is already registered'; end if;
    insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
    values (case when v_role in ('reference', 'validation') then 'scholarship_reference' else 'scholarship_catalogue' end,
            (select id from ref.countries where iso_alpha2 = v_cc), v_url, btrim(p_args->>'label'), case when v_role in ('reference', 'validation') then 30 else 80 end,
            case when v_role in ('reference', 'validation') then 'active' else 'registered' end,
            jsonb_build_object('domain', 'scholarship', 'scholarship_role', v_role, 'reader', 'none', 'use', nullif(btrim(coalesce(p_args->>'use', '')), ''), 'added_by', auth.uid(), 'decision', 'Decision 251'))
    returning id into v_id;
    v_after := jsonb_build_object('id', v_id, 'url', v_url, 'role', v_role, 'country', v_cc); v_target := btrim(p_args->>'label');
  elsif p_action in ('source_role', 'source_status') then
    v_id := (p_args->>'id')::uuid;
    select jsonb_build_object('role', metadata->>'scholarship_role', 'status', status), label into v_before, v_target from pipeline.sources where id = v_id and source_type in ('government_scholarship_program', 'scholarship_catalogue', 'scholarship_reference');
    if v_before is null then raise exception 'unknown scholarship source'; end if;
    if p_action = 'source_role' then
      if p_args->>'role' not in ('ingest', 'provider_pages', 'reference', 'validation') then raise exception 'choose how the source is used'; end if;
      update pipeline.sources set metadata = metadata || jsonb_build_object('scholarship_role', p_args->>'role'), updated_at = now() where id = v_id;
    else
      if p_args->>'status' not in ('active', 'paused') then raise exception 'choose on or paused'; end if;
      if v_before->>'status' = 'registered' and p_args->>'status' = 'active' and not exists (select 1 from pipeline.scholarship_etl_schedules e join pipeline.sources x on x.metadata->>'scholarship_source_key' = e.source_key where x.id = v_id) and (select metadata->>'scholarship_role' from pipeline.sources where id = v_id) in ('ingest', 'provider_pages') then
        raise exception 'no reader exists for this source yet; it stays registered';
      end if;
      update pipeline.sources set status = p_args->>'status', updated_at = now() where id = v_id;
      update pipeline.scholarship_etl_schedules e set enabled = (p_args->>'status' = 'active'), updated_at = now() from pipeline.sources x where x.id = v_id and e.source_key = x.metadata->>'scholarship_source_key';
    end if;
    select jsonb_build_object('role', metadata->>'scholarship_role', 'status', status) into v_after from pipeline.sources where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'layer_' || p_action, v_target, jsonb_build_object('before', v_before, 'after', v_after, 'reason', v_reason, 'decision', 'Decision 251'), auth.uid());
  return jsonb_build_object('ok', true, 'action', p_action, 'target', v_target, 'after', v_after);
end $f$;
revoke all on function public.admin_scholarship_layer_write(text, jsonb) from public, anon;
grant execute on function public.admin_scholarship_layer_write(text, jsonb) to authenticated;

-- Canada gets an AI setting row like Australia and New Zealand (off; a model must pass its benchmark first)
insert into pipeline.scholarship_ai_settings(country_code, enabled, schedule_on_change, max_records_per_run, daily_budget_usd, default_task_class, metadata)
select 'CA', false, true, 25, 1.00, 'scholarship_page_classification', jsonb_build_object('state', 'benchmark_required', 'decision', 'Decision 251')
 where not exists (select 1 from pipeline.scholarship_ai_settings where country_code = 'CA');
