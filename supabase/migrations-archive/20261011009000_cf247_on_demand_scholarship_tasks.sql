-- CF-247 (11 Oct 2026, Platform Admin): scholarships on demand, run as tasks, and Task manager shows everything using resources.
--  - Task kinds become a registry table (pipeline.admin_job_kinds) linked to admin_jobs, so every future background feature is
--    added as a row and shows in Task manager (the fixed list was dropped by the Platform Admin's paste file).
--  - New tasks: Find scholarships now (one provider or several, from the provider record or Scholarships > Coverage),
--    Check scholarships for a course (course record) and Read a scholarship again (scholarship record). Each queues its pages
--    first in line, sends the scraper worker the next step each minute and finishes when nothing in scope is left; courses are
--    linked by the evidence rules (Platform Admin decision "Attach by evidence rules"). Cancel only: the pages lose their place.
--  - admin_jobs read returns, on request, everything running now: scheduled jobs, worker calls on their way, credits this hour.
-- md5-checked before and after. No rows are deleted; nothing is dropped by this file.
do $guard$
declare v_expected jsonb := '{"security.admin_job_slice_v1(uuid,integer)": "15a3d3644a2d81af425531a3b9c302fc", "security.admin_job_watch_v1(uuid)": "f06bc1ba1cbff05532f6c4be0bbde6a0", "public.admin_jobs(text,jsonb)": "d2b733462b760610b5d29e3b8743cece", "public.svc_scholarship_read_next(integer)": "e2d5ab79976c3d4ff8dc4cc5ed2072f4", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "29e88df71de57ebe077118c0795cbb63", "public.svc_scholarship_candidate_next(integer)": "2f3ccd5c904ea959007a1d2c2120491f"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 0. The fixed list of task kinds must be gone first (paste-cf247-task-kinds.sql, Platform Admin)
do $chk$ begin
  if exists (select 1 from pg_constraint where conrelid = 'pipeline.admin_jobs'::regclass and conname = 'admin_jobs_kind_check') then
    raise exception 'paste paste-cf247-task-kinds.sql first (it drops the fixed list of task kinds)';
  end if;
end $chk$;

-- 1. Registry of task kinds (Platform Admin, 11 Oct 2026: every background feature registers as a task and shows in Task manager)
create table if not exists pipeline.admin_job_kinds(
  kind text primary key,
  label text not null,
  what text not null default '',
  can_pause boolean not null default false,
  added_at timestamptz not null default now(),
  added_in text not null default '');
alter table pipeline.admin_job_kinds enable row level security;
revoke all on pipeline.admin_job_kinds from anon, authenticated;
insert into pipeline.admin_job_kinds(kind, label, what, can_pause, added_in) values
  ('qualify_adapters', 'Qualify adapters', 'Measures adapters against the admission rules; admits nothing.', true, 'Decision 254'),
  ('admit_qualified', 'Admit passing fields', 'Admits the fields that passed a finished Qualify task.', true, 'Decision 254'),
  ('reread_pages', 'Read pages again', 'Sends universities'' course pages to be read again.', false, 'Decision 254'),
  ('firecrawl_run', 'Firecrawl run', 'A Firecrawl run with its own credit allowance.', true, 'Decision 254'),
  ('adapter_apply', 'Apply an adapter', 'Reads a university''s stored pages again with its adapter.', false, 'Decision 254'),
  ('central_page_read', 'Read a central page', 'Reads a university''s fee, English or dates page.', false, 'Decision 254'),
  ('scholarship_provider_scan', 'Find scholarships now', 'Maps the university''s site through the scraper, screens its candidate pages, admits new scholarships and reads every scholarship page; links courses from the evidence.', false, 'CF-247 11 Oct 2026'),
  ('scholarship_course_check', 'Check scholarships for a course', 'Reads the provider''s scholarship pages again through the scraper and applies the course-link rules; lists what was added or removed for the course.', false, 'CF-247 11 Oct 2026'),
  ('scholarship_reread', 'Read a scholarship again', 'Reads the scholarship''s page again through the scraper now and applies what it states.', false, 'CF-247 11 Oct 2026')
on conflict (kind) do nothing;
do $fk$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.admin_jobs'::regclass and conname = 'admin_jobs_kind_fk') then
    alter table pipeline.admin_jobs add constraint admin_jobs_kind_fk foreign key (kind) references pipeline.admin_job_kinds(kind);
  end if;
end $fk$;

-- 2. On-demand pages and candidates go first in the reader's queue
alter table pipeline.scholarship_pages add column if not exists requested_at timestamptz;
alter table pipeline.scholarship_page_candidates add column if not exists requested_at timestamptz;

-- 3. Prepare an on-demand scholarship task: queue what is in scope at the front, and say what it covers
create or replace function security.scholarship_task_prepare_v1(p_kind text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_prov uuid[]; v_sch uuid[]; v_course uuid; v_before uuid[] := '{}'; v_pages int := 0; v_cands int := 0; v_title text; v_scope text; v_missing text;
begin
  if p_kind = 'scholarship_provider_scan' then
    v_prov := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_prov), 0) = 0 then raise exception 'choose at least one provider'; end if;
    if cardinality(v_prov) > 50 then raise exception 'at most 50 providers in one task'; end if;
    select string_agg(coalesce(p.display_name, p.canonical_name), ', ') into v_missing from catalogue.providers p
     where p.id = any (v_prov) and coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) is null;
    if v_missing is not null then raise exception 'no website is known for %; add it on the provider first', v_missing; end if;
  elsif p_kind = 'scholarship_course_check' then
    v_course := (p_args->>'course_id')::uuid;
    select array[c.provider_id] into v_prov from catalogue.courses c where c.id = v_course;
    if v_prov is null then raise exception 'unknown course'; end if;
    v_before := array(select m.scholarship_id from scholarship.course_mappings m where m.course_id = v_course and m.mapping_state = 'mapped');
  elsif p_kind = 'scholarship_reread' then
    v_sch := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'scholarship_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_sch), 0) = 0 then raise exception 'choose a scholarship'; end if;
    v_prov := array(select distinct s.provider_id from scholarship.scholarships s where s.id = any (v_sch));
    if not exists (select 1 from pipeline.scholarship_pages p where p.scholarship_id = any (v_sch)) then raise exception 'this scholarship has no provider page to read'; end if;
  else
    raise exception 'unknown scholarship task';
  end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = any (v_prov)) then
    raise exception 'a chosen provider is unpublished or archived; publish or restore it first';
  end if;
  if p_kind = 'scholarship_provider_scan' then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status, attempts, updated_at)
    select p.id, coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')), 0, 'on_demand', 'pending', 0, now()
      from catalogue.providers p where p.id = any (v_prov)
    on conflict (provider_id) do update set status = 'pending', priority = 0, attempts = 0, leased_until = null, reason = 'on_demand', updated_at = now();
    update pipeline.scholarship_page_candidates c set next_read_at = now(), attempts = 0, leased_until = null, requested_at = now()
     where c.provider_id = any (v_prov) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register'
       and (c.read_status is null or c.read_status in ('blocked', 'fetch_failed', 'too_thin', 'not_html', 'robots_disallowed', 'scrape_failed', 'waiting_scraper', 'deferred'));
    get diagnostics v_cands = row_count;
  end if;
  update pipeline.scholarship_pages p set requested_at = now(), next_read_at = now(), attempts = 0, leased_until = null
    from scholarship.scholarships s
   where s.id = p.scholarship_id and s.lifecycle_status = 'active'
     and (case when v_sch is not null then s.id = any (v_sch) else s.provider_id = any (v_prov) end);
  get diagnostics v_pages = row_count;
  if v_sch is null then update pipeline.scholarship_listing_pages set next_read_at = now() where active and provider_id = any (v_prov); end if;
  v_title := case p_kind
    when 'scholarship_provider_scan' then 'Find scholarships now: ' || case when cardinality(v_prov) = 1 then (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_prov[1]) else cardinality(v_prov) || ' providers' end
    when 'scholarship_course_check' then 'Check scholarships for ' || (select coalesce(c.display_title, c.canonical_title) || coalesce(' (' || c.course_code || ')', '') from catalogue.courses c where c.id = v_course)
    else 'Read again now: ' || case when cardinality(v_sch) = 1 then (select s.name from scholarship.scholarships s where s.id = v_sch[1]) else cardinality(v_sch) || ' scholarships' end end;
  v_scope := case p_kind
    when 'scholarship_provider_scan' then case when cardinality(v_prov) = 1 then v_prov[1]::text else 'providers:' || md5(array_to_string(array(select x::text from unnest(v_prov) x order by 1), ',')) end
    when 'scholarship_course_check' then v_course::text
    else case when cardinality(v_sch) = 1 then v_sch[1]::text else 'scholarships:' || md5(array_to_string(array(select x::text from unnest(v_sch) x order by 1), ',')) end end;
  return jsonb_build_object('providers', to_jsonb(v_prov), 'scholarship_ids', to_jsonb(coalesce(v_sch, '{}'::uuid[])), 'course_id', v_course, 'before', to_jsonb(v_before),
                            'pages', v_pages, 'candidates', v_cands, 'title', v_title, 'scope', v_scope);
end $f$;
revoke all on function security.scholarship_task_prepare_v1(text, jsonb) from public, anon, authenticated;

-- 4. Send the scraper worker the next step now, unless one for the same step is already on its way
create or replace function security.scholarship_task_fire_v1(p_steps text[])
returns int language plpgsql security definer set search_path to '' as $f$
declare v_step text; v_mode text; v_body jsonb; v_sent int := 0;
begin
  foreach v_step in array coalesce(p_steps, '{}') loop
    v_mode := case when v_step in ('discover', 'candidates') then 'scholarship_discover' else 'scholarship_read' end;
    v_body := case v_step
      when 'discover' then jsonb_build_object('mode', v_mode, 'phase', 'discover', 'limit', 6)
      when 'candidates' then jsonb_build_object('mode', v_mode, 'phase', 'candidates', 'read_limit', 30)
      else jsonb_build_object('mode', v_mode, 'limit', 40) end;
    if not exists (select 1 from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = v_mode and l.created_at > now() - interval '45 seconds'
                    and not exists (select 1 from net._http_response r where r.id = l.request_id)) then
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', v_body);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end $f$;
revoke all on function security.scholarship_task_fire_v1(text[]) from public, anon, authenticated;

-- 5. Everything using resources right now, for Task manager: scheduled jobs running, worker calls on their way, credits this hour
create or replace function security.admin_running_now_v1()
returns jsonb language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object('at', now(),
    'scheduled', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'label', coalesce(c.label, j.jobname), 'area', coalesce(c.area, 'Other'), 'started_at', d.start_time,
                     'seconds', extract(epoch from now() - d.start_time)::int, 'active', j.active, 'schedule', j.schedule, 'control_rank', coalesce(c.control_rank, 6)) order by d.start_time), '[]'::jsonb)
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid left join pipeline.automation_catalogue c on c.jobname = j.jobname
                  where d.status in ('running', 'starting') and d.start_time > now() - interval '6 hours'),
    'worker_calls', (select coalesce(jsonb_agg(jsonb_build_object('function', x.function_name, 'mode', x.mode, 'calls', x.n, 'oldest_at', x.oldest, 'seconds', extract(epoch from now() - x.oldest)::int) order by x.oldest), '[]'::jsonb)
                      from (select l.function_name, coalesce(l.mode, '') mode, count(*) n, min(l.created_at) oldest from pipeline.edge_request_log l
                             where l.created_at > now() - interval '10 minutes' and not exists (select 1 from net._http_response r where r.id = l.request_id) group by 1, 2) x),
    'credits_last_hour', (select coalesce(jsonb_object_agg(u.purpose, u.n), '{}'::jsonb) from (select purpose, sum(units) n from pipeline.coverage_vendor_usage where at > now() - interval '1 hour' group by 1) u))
$f$;
revoke all on function security.admin_running_now_v1() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.admin_job_slice_v1(p_id uuid, p_items integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_next int; v_total int; v_ids uuid[]; v_pid uuid; v_r jsonb; v_min_read numeric; v_min_agree numeric;
        v_done int := 0; v_errs int; v_pass int; v_fields text[]; v_have text[]; v_want text[]; v_claims text; v_res jsonb; v_added text[];
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  if v_j.kind in ('reread_pages', 'firecrawl_run', 'adapter_apply', 'central_page_read', 'scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then return security.admin_job_watch_v1(p_id); end if;
  v_ids := array(select (x)::uuid from jsonb_array_elements_text(v_j.args->'providers') x);
  v_total := coalesce(array_length(v_ids, 1), 0);
  v_next := coalesce((v_j.cursor->>'next')::int, 1);
  v_errs := coalesce((v_j.result->>'errors')::int, 0);
  v_pass := coalesce((v_j.result->>'passing')::int, 0);
  v_min_read := coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5);
  v_min_agree := coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9);
  while v_next <= v_total and v_done < p_items loop
    v_pid := v_ids[v_next];
    begin
      if v_j.kind = 'qualify_adapters' then
        v_r := security.adapter_qualify_one_v1(v_pid, v_min_read, v_min_agree);
        insert into pipeline.adapter_qualifications(job_id, provider_id, pages_read, fields, passing)
          values (p_id, v_pid, (v_r->>'pages_read')::int, v_r->'fields', array(select x from jsonb_array_elements_text(v_r->'passing') x))
          on conflict (job_id, provider_id) do update set measured_at = now(), pages_read = excluded.pages_read, fields = excluded.fields, passing = excluded.passing where pipeline.adapter_qualifications.job_id = excluded.job_id and pipeline.adapter_qualifications.provider_id = excluded.provider_id;
        if jsonb_array_length(v_r->'passing') > 0 then v_pass := v_pass + 1; end if;
      elsif v_j.kind = 'admit_qualified' then
        v_want := array(select x from jsonb_array_elements_text(v_j.args->'fields') x);
        select q.passing into v_fields from pipeline.adapter_qualifications q where q.job_id = coalesce((v_j.args->'qual_jobs'->>v_pid::text)::uuid, (v_j.args->>'qualification_job_id')::uuid) and q.provider_id = v_pid;
        select coalesce(u.admit_fields, '{}') into v_have from pipeline.uni_adapters u where u.provider_id = v_pid;
        v_added := array(select f from unnest(v_fields) f where f = any (v_want) and f <> all (v_have));
        if coalesce(array_length(v_added, 1), 0) > 0 then
          -- as the person who started the job, through the ordinary admission control (its checks and its log entry)
          v_claims := jsonb_build_object('sub', v_j.requested_by::text, 'role', 'authenticated')::text;
          perform set_config('request.jwt.claims', v_claims, true);
          v_res := public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', v_pid, 'admit', true,
                     'fields', to_jsonb(array(select distinct f from unnest(v_have || v_added) f order by f)),
                     'reason', left('Admitted by job ' || p_id::text || ' (' || v_j.title || '): ' || v_j.reason, 400)));
          perform set_config('request.jwt.claims', '', true);
          v_pass := v_pass + 1;
          insert into pipeline.admin_job_events(job_id, note, detail) values (p_id, 'admitted ' || array_to_string(v_added, ', ') || ' for ' || (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_pid), jsonb_build_object('provider_id', v_pid, 'fields', v_res->'fields'));
        end if;
      end if;
    exception when others then
      perform set_config('request.jwt.claims', '', true);
      v_errs := v_errs + 1;
      insert into pipeline.admin_job_events(job_id, note, detail) values (p_id, 'error for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_pid), v_pid::text) || ': ' || left(sqlerrm, 300), jsonb_build_object('provider_id', v_pid));
    end;
    v_next := v_next + 1; v_done := v_done + 1;
  end loop;
  update pipeline.admin_jobs set cursor = jsonb_build_object('next', v_next), progress = jsonb_build_object('done', v_next - 1, 'total', v_total), result = jsonb_build_object('passing', v_pass, 'errors', v_errs), updated_at = now() where id = p_id;
  return v_next > v_total;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_job_watch_v1(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_done int := 0; v_total int := 0; v_fin boolean := false; v_note text := null; v_phase text := null;
        v_n_map int := 0; v_n_cand int := 0; v_extra jsonb; v_sch uuid[]; v_before uuid[]; v_since timestamptz;
        v_last_done int; v_last_at timestamptz; v_stall interval; v_ids uuid[]; r record;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  v_last_done := coalesce((v_j.cursor->>'last_done')::int, -1);
  v_last_at := coalesce((v_j.cursor->>'last_change_at')::timestamptz, v_j.started_at, v_j.created_at);
  if v_j.kind = 'reread_pages' then
    v_stall := interval '30 minutes';
    select * into r from pipeline.university_reread_requests q where q.id = (v_j.args->>'request_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the re-read request is gone';
    elsif r.status = 'cancelled' then v_fin := true; v_note := 'cancelled before every university was sent (' || cardinality(r.done_ids) || ' of ' || cardinality(r.provider_ids) || ' sent)';
    elsif r.status = 'failed' then v_fin := true; v_note := 'the request failed: ' || coalesce(r.last_error, 'no detail');
    elsif r.status in ('waiting', 'sending') then
      v_phase := 'sending'; v_done := cardinality(r.done_ids); v_total := cardinality(r.provider_ids);
    else
      v_phase := 'reading'; v_total := coalesce(r.pages, 0);
      v_ids := r.provider_ids;
      select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = any (v_ids) and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
      if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) sent back and read again'; end if;
    end if;
  elsif v_j.kind = 'firecrawl_run' then
    select * into r from pipeline.firecrawl_runs x where x.id = (v_j.args->>'run_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the run is gone';
    else
      v_done := coalesce(r.done, 0); v_total := coalesce(r.items, 0);
      if r.status <> 'running' then v_fin := true; v_note := 'run ' || r.status || ': ' || v_done || ' of ' || v_total || ' done, ' || coalesce(r.credits_used, 0) || ' credits'; end if;
    end if;
  elsif v_j.kind = 'adapter_apply' then
    v_stall := interval '20 minutes';
    v_total := coalesce((v_j.args->>'pages')::int, 0);
    select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = (v_j.args->>'provider_id')::uuid and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
    if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) read again with the adapter'; end if;
  elsif v_j.kind = 'central_page_read' then
    v_stall := interval '30 minutes'; v_total := 1;
    select * into r from pipeline.provider_fact_sources s where s.id = (v_j.args->>'source_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the central page record is gone';
    elsif r.status in ('read', 'parsed', 'no_values', 'failed') and r.updated_at >= coalesce(v_j.started_at, v_j.created_at) - interval '1 minute' then
      v_done := 1; v_fin := true; v_note := 'page ' || r.status || coalesce(': ' || (r.parse_summary->>'error'), '');
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks. The pages in scope were queued first in line when the task
  -- started; each minute this checks progress, sends the scraper worker the next step (map the site, screen candidate pages, read
  -- scholarship pages) when none is already on its way, and finishes when nothing in scope is left to do.
  elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
    v_stall := interval '30 minutes'; v_since := v_j.created_at;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x);
    v_sch := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x);
    select count(*) filter (where p.requested_at is null and p.read_at >= v_since), count(*) into v_done, v_total
      from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id
     where s.lifecycle_status = 'active'
       and (case when v_j.kind = 'scholarship_reread' then s.id = any (v_sch) else s.provider_id = any (v_ids) end)
       and (p.requested_at is not null or p.read_at >= v_since or s.created_at >= v_since);
    if v_j.kind = 'scholarship_provider_scan' then
      select count(*) into v_n_map from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and d.status = 'pending' and d.attempts < 3;
      select count(*) into v_n_cand from pipeline.scholarship_page_candidates c
       where c.provider_id = any (v_ids) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register' and c.next_read_at <= now() and c.attempts < 3;
    end if;
    v_phase := case when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
    v_extra := jsonb_build_object('phase_detail', v_phase, 'providers_mapping', v_n_map, 'candidates_waiting', v_n_cand,
      'new_scholarships', (select count(*) from scholarship.scholarships s where s.provider_id = any (v_ids) and s.created_at >= v_since),
      'links_changed', (select count(*) from pipeline.scholarship_sweep_changes c join scholarship.scholarships s on s.id = c.scholarship_id
                         where s.provider_id = any (v_ids) and c.field = 'course_links' and c.changed_at >= v_since),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = any (v_ids) and u.purpose like 'sch\_%' and u.at >= v_since));
    if v_j.kind = 'scholarship_course_check' then
      v_before := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'before', '[]'::jsonb)) x);
      v_extra := v_extra || jsonb_build_object('course_id', v_j.args->>'course_id',
        'linked_now', (select count(*) from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped'),
        'added', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id
                   where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped' and not (m.scholarship_id = any (v_before))),
        'removed', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.scholarships s
                     where s.id = any (v_before) and not exists (select 1 from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.scholarship_id = s.id and m.mapping_state = 'mapped')));
    end if;
    if v_n_map = 0 and v_n_cand = 0 and v_done >= v_total then
      v_fin := true;
      v_note := v_done || ' scholarship page(s) read through the scraper' || coalesce(', ' || nullif((v_extra->>'new_scholarships')::int, 0) || ' new scholarship(s) found', '')
             || ', course links changed on ' || (v_extra->>'links_changed') || ', ' || (v_extra->>'credits') || ' credit(s)'
             || case when v_j.kind = 'scholarship_course_check' then '; this course now has ' || (v_extra->>'linked_now') || ' scholarship(s) (' || jsonb_array_length(v_extra->'added') || ' added, ' || jsonb_array_length(v_extra->'removed') || ' removed)' else '' end;
    else
      perform security.scholarship_task_fire_v1(case when v_n_map > 0 then array['discover'] when v_n_cand > 0 then array['candidates'] else array['read'] end);
    end if;
  end if;
  if v_done <> v_last_done then v_last_done := v_done; v_last_at := now(); end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then
    v_fin := true; v_note := coalesce(v_note, v_done || ' of ' || v_total || ' done, nothing more for ' || extract(epoch from v_stall)::int / 60 || ' minutes: the rest wait their turn in the reader');
  end if;
  update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', v_last_done, 'last_change_at', v_last_at), progress = jsonb_build_object('done', v_done, 'total', v_total) || coalesce(jsonb_build_object('phase', v_phase), '{}'::jsonb), result = jsonb_build_object('done', v_done, 'total', v_total, 'errors', case when v_note like 'the request failed%' then 1 else 0 end) || coalesce(jsonb_build_object('note', v_note), '{}'::jsonb) || coalesce(v_extra, '{}'::jsonb), updated_at = now() where id = p_id;
  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_jobs(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_id uuid; v_kind text; v_ids uuid[]; v_j pipeline.admin_jobs%rowtype;
        v_q pipeline.admin_jobs%rowtype; v_fields text[]; v_title text; v_n int; v_res jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'jobs', coalesce((select jsonb_agg(to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0), 'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by)) order by j.created_at desc)
                         from (select * from pipeline.admin_jobs where state in ('queued', 'running', 'paused') or (p_args->>'all')::boolean order by created_at desc limit greatest(1, least(coalesce((p_args->>'limit')::int, 50), 200))) j), '[]'::jsonb),
      'match', case when p_args ? 'kind' then (select to_jsonb(j) - 'args' || jsonb_build_object('providers', coalesce(jsonb_array_length(j.args->'providers'), 0)) from pipeline.admin_jobs j
                      where j.kind = p_args->>'kind' and j.scope is not distinct from nullif(p_args->>'scope', '') and j.state in ('queued', 'running', 'paused') order by j.created_at desc limit 1) end,
      'job', case when p_args ? 'id' then (select to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0),
                    'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by),
                    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc) from (select * from pipeline.admin_job_events e where e.job_id = j.id order by e.id desc limit 200) e), '[]'::jsonb),
                    'qualifications', coalesce((select jsonb_agg(jsonb_build_object('provider_id', q.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(p.id), 'pages_read', q.pages_read, 'fields', q.fields, 'passing', q.passing, 'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = q.provider_id), 'admitted', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.admit)) order by coalesce(p.display_name, p.canonical_name))
                                       from pipeline.adapter_qualifications q join catalogue.providers p on p.id = q.provider_id where (q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid or q.job_id::text = j.args->'qual_jobs'->>q.provider_id::text)), '[]'::jsonb))
                  from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid) end,
      'settings', jsonb_build_object('min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb), 'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)),
      'countries', coalesce((select jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'adapters', n.n) order by k.name) from ref.countries k join (select p.country_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.country_id) n on n.country_id = k.id), '[]'::jsonb),
      'states', coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'country', k.iso_alpha2, 'adapters', n.n) order by s.code) from ref.subdivisions s join ref.countries k on k.id = s.country_id join (select p.subdivision_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.subdivision_id) n on n.subdivision_id = s.id), '[]'::jsonb),
      'can_admit', v_rank >= 6,
      -- 11 Oct 2026: job kinds from the registry, and (Task manager) everything using resources right now
      'kinds', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object('label', k.label, 'can_pause', k.can_pause)), '{}'::jsonb) from pipeline.admin_job_kinds k),
      'running_now', case when coalesce((p_args->>'running')::boolean, false) then security.admin_running_now_v1() end);
  end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    v_kind := p_args->>'kind';
    if v_kind = 'qualify_adapters' then
      if v_rank < 5 then raise exception 'Operator (adapters) or above required' using errcode = '42501'; end if;
      v_ids := security.admin_jobs_resolve_adapters_v1(coalesce(p_args->'args', '{}'::jsonb));
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapters match that choice'; end if;
      v_title := 'Qualify ' || array_length(v_ids, 1) || ' adapter(s)' || coalesce(' in ' || nullif(btrim(coalesce(p_args->'args'->>'state', p_args->'args'->>'country', '')), ''), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), nullif(p_args->'args'->>'state', ''), nullif(p_args->'args'->>'country', '')))
        returning * into v_j;
    elsif v_kind = 'admit_qualified' and not (coalesce(p_args->'args', '{}'::jsonb) ? 'qualification_job_id') then
      -- 6 Oct (Layer 2 › Adapters): admit the ticked adapters, each from its own latest finished Qualify
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      select coalesce(jsonb_object_agg(z.provider_id, z.job_id), '{}'::jsonb), coalesce(array_agg(z.provider_id order by z.provider_id), '{}') into v_res, v_ids
        from (select distinct on (x.provider_id) x.provider_id, x.job_id, x.passing from pipeline.adapter_qualifications x join pipeline.admin_jobs qj on qj.id = x.job_id and qj.kind = 'qualify_adapters' and qj.state = 'done'
               where x.provider_id = any (array(select (y)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) y))
               order by x.provider_id, x.measured_at desc) z
       where z.passing && v_fields and exists (select 1 from pipeline.uni_adapters u where u.provider_id = z.provider_id and u.enabled);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no ticked adapter passed for those fields in its latest Qualify (or it is switched off)'; end if;
      v_title := 'Admit the passing fields of ' || case when array_length(v_ids, 1) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 adapter') else array_length(v_ids, 1) || ' adapters' end || ' (latest Qualify of each)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qual_jobs', v_res, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), case when array_length(v_ids, 1) = 1 then v_ids[1]::text else 'adapters' end))
        returning * into v_j;
      v_res := null;
    elsif v_kind = 'admit_qualified' then
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      select * into v_q from pipeline.admin_jobs q where q.id = (p_args->'args'->>'qualification_job_id')::uuid;
      if v_q.id is null or v_q.kind <> 'qualify_adapters' or v_q.state <> 'done' then raise exception 'choose a finished Qualify job'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      v_ids := array(select q.provider_id from pipeline.adapter_qualifications q where q.job_id = v_q.id and q.passing && v_fields
                      and exists (select 1 from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.enabled)
                      order by q.provider_id);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapter passed for those fields'; end if;
      v_title := 'Admit the passing fields of ' || array_length(v_ids, 1) || ' adapter(s) (from ' || v_q.title || ')';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qualification_job_id', v_q.id, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason, v_q.id::text)
        returning * into v_j;
    elsif v_kind = 'reread_pages' then
      v_res := public.admin_university_reread('queue', coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('reason', v_reason));
      v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) x);
      v_title := 'Read pages again: ' || case when cardinality(v_ids) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 university') else cardinality(v_ids) || ' universities' end
                 || case when coalesce(p_args->'args'->>'which', 'all') = 'not_confirmed' then ' (pages not confirmed)' else '' end || case when coalesce((p_args->'args'->>'central')::boolean, false) then ' with central pages' else '' end;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('request_id', v_res->>'request_id', 'provider_ids', to_jsonb(v_ids), 'which', coalesce(p_args->'args'->>'which', 'all'), 'central', coalesce((p_args->'args'->>'central')::boolean, false)),
                jsonb_build_object('done', 0, 'total', cardinality(v_ids), 'phase', 'sending'), auth.uid(), v_reason, case when cardinality(v_ids) = 1 then v_ids[1]::text else coalesce(nullif(p_args->'args'->>'scope', ''), 'universities') end)
        returning * into v_j;
    elsif v_kind = 'firecrawl_run' then
      v_res := public.admin_firecrawl_write('start', jsonb_build_object('use_case', p_args->'args'->>'use_case', 'reason', v_reason));
      v_title := 'Firecrawl run: ' || replace(coalesce(p_args->'args'->>'use_case', ''), '_', ' ') || ' (' || coalesce(v_res->>'items', '0') || ' pages, cap ' || coalesce(v_res->>'credits_cap', '-') || ' credits)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'firecrawl', v_title, jsonb_build_object('run_id', v_res->>'run_id', 'use_case', p_args->'args'->>'use_case', 'items', (v_res->>'items')::int), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'items')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'use_case')
        returning * into v_j;
      v_ids := '{}';
    elsif v_kind = 'adapter_apply' then
      v_res := public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'reason', v_reason));
      v_title := 'Apply the adapter: ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '') || ' (' || coalesce(v_res->>'pages_read_again', '0') || ' pages)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'pages', coalesce((v_res->>'pages_read_again')::int, 0), 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages_read_again')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    elsif v_kind = 'central_page_read' then
      v_res := public.admin_provider_central_page(coalesce(nullif(p_args->'args'->>'action', ''), 'add'), jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'title', p_args->'args'->>'title', 'reason', v_reason));
      v_title := 'Read a central page: ' || replace(coalesce(p_args->'args'->>'kind', ''), '_', ' ') || ' for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('source_id', v_res->>'source_id', 'provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', 1), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks (provider, several providers, course, scholarship)
    elsif v_kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      v_res := security.scholarship_task_prepare_v1(v_kind, coalesce(p_args->'args', '{}'::jsonb));
      if exists (select 1 from pipeline.admin_jobs j where j.kind = v_kind and j.scope is not distinct from (v_res->>'scope') and j.state in ('queued', 'running', 'paused')) then
        raise exception 'this check is already running; see Scheduled jobs › Task manager';
      end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'scholarships:' || v_kind || ':' || coalesce(v_res->>'scope', ''), v_res->>'title', v_res - 'title' - 'scope', jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages')::int, 0)), auth.uid(), v_reason, v_res->>'scope')
        returning * into v_j;
      v_ids := array(select x::uuid from jsonb_array_elements_text(v_res->'providers') x);
      perform security.scholarship_task_fire_v1(case when v_kind = 'scholarship_provider_scan' then array['discover', 'read'] else array['read'] end);
    else
      raise exception 'unknown job kind';
    end if;
    insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_start', v_j.id::text, jsonb_build_object('kind', v_kind, 'title', v_j.title, 'providers', array_length(v_ids, 1), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_j.id, 'title', v_j.title, 'providers', array_length(v_ids, 1));
  end if;
  v_id := (p_args->>'id')::uuid;
  select * into v_j from pipeline.admin_jobs j where j.id = v_id;
  if v_j.id is null then raise exception 'unknown job'; end if;
  if v_rank < 5 and v_j.requested_by <> auth.uid() then raise exception 'only the person who started it, or an Operator, may change this job' using errcode = '42501'; end if;
  if p_action = 'cancel' then
    if v_j.state in ('done', 'failed', 'cancelled') then raise exception 'the job has already finished'; end if;
    if v_j.kind = 'reread_pages' then
      update pipeline.university_reread_requests set status = 'cancelled', finished_at = now() where id = (v_j.args->>'request_id')::uuid and status in ('waiting', 'sending');
    elsif v_j.kind = 'firecrawl_run' then
      perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason));
    elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      -- the pages lose their place at the front of the queue; they are read again in their normal turn
      update pipeline.scholarship_pages p set requested_at = null from scholarship.scholarships s
       where s.id = p.scholarship_id and p.requested_at is not null
         and (s.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x))
              or s.id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x)));
      update pipeline.scholarship_page_candidates c set requested_at = null
       where c.requested_at is not null and c.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x));
    end if;
    if v_j.state in ('queued', 'paused') then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now(), cancel_requested = true where id = v_id;
      perform security.admin_job_close_v1(v_id);
    else
      update pipeline.admin_jobs set cancel_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'pause' then
    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'; end if;
    if not coalesce((select k.can_pause from pipeline.admin_job_kinds k where k.kind = v_j.kind), false) then raise exception 'this task cannot be paused, only cancelled'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'paused', updated_at = now() where id = v_id;
    else
      update pipeline.admin_jobs set pause_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'resume' then
    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('continue', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    update pipeline.admin_jobs set state = 'queued', pause_requested = false, updated_at = now() where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_id, p_action || ' requested by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_' || p_action, v_id::text, jsonb_build_object('title', v_j.title, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.scholarship_id from pipeline.scholarship_pages p join scholarship.scholarships s on s.id=p.scholarship_id and s.lifecycle_status='active'
     where p.next_read_at<=now() and coalesce(p.leased_until,'-infinity')<now() and p.attempts<5
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (p.requested_at is not null) desc, p.read_at nulls first limit greatest(1,least(coalesce(p_limit,20),40)) for update of p skip locked), -- 11 Oct 2026: on-demand pages first
  upd as (update pipeline.scholarship_pages p set leased_until=now()+interval '10 minutes', attempts=p.attempts+1 from pick where p.scholarship_id=pick.scholarship_id
          returning p.scholarship_id, p.url, p.url_source)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',u.scholarship_id,'url',u.url,'name',s.name,'provider_id',s.provider_id,'currency',scholarship.provider_currency(s.provider_id),'url_source',u.url_source,'names',security.provider_name_list(s.provider_id))),'[]'::jsonb) into v
    from upd u join scholarship.scholarships s on s.id=u.scholarship_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_read_record(p_scholarship_id uuid, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_ev uuid; v_src uuid; v_pid uuid; v_url text; r jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, p.url into v_pid, v_url from scholarship.scholarships s join pipeline.scholarship_pages p on p.scholarship_id=s.id where s.id=p_scholarship_id;
  if p_storage_path is not null and p_read_status='read' then
    v_src:=security.coverage_sweep_source(v_pid);
    -- unchanged page: reuse its evidence; changed page: next capture version, superseding the previous one
    select e.id into v_ev from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id and e.content_hash=p_sha256 order by e.capture_version desc limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key,supersedes_evidence_id)
      select p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
             jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'),
             coalesce((select max(e.capture_version) from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id),0)+1,
             'scholarship:'||p_scholarship_id,
             (select e.id from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id order by e.capture_version desc limit 1)
      returning id into v_ev;
    end if;
  end if;
  update pipeline.scholarship_pages set requested_at=case when p_read_status='waiting_scraper' then requested_at end, read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, evidence_id=case when p_read_status='read' then coalesce(v_ev,evidence_id) else evidence_id end,
         facts=case when p_read_status='read' then coalesce(p_facts,facts) else facts end,
         name_check=case when p_facts ? 'name_check' then p_facts->'name_check' else name_check end,
         -- 11 Oct 2026: pages are read through the scraper only; one waiting for the scraper (no credit or service) is tried again
         -- within the hour and does not use up its attempts; a blocked page is tried again in 2 days
         next_read_at=case when p_read_status='read' then now()+interval '90 days' when p_read_status='name_mismatch' then now()+interval '30 days'
                           when p_read_status='blocked' then now()+interval '2 days' when p_read_status='waiting_scraper' then now()+interval '1 hour' else now()+interval '6 hours' end,
         attempts=case when p_read_status='read' then 0 when p_read_status='waiting_scraper' then greatest(attempts-1,0) else attempts end
   where scholarship_id=p_scholarship_id;
  -- an admitted page that no longer meets the admission rules is withdrawn, not applied
  if p_read_status='read' and p_facts ? 'admission' and coalesce((p_facts->'admission'->>'admit')::boolean,true) is false
     and exists (select 1 from pipeline.scholarship_pages where scholarship_id=p_scholarship_id and url_source='admitted') then
    r:=security.scholarship_admission_withdraw_v1(p_scholarship_id, jsonb_build_object('reasons',p_facts->'admission'->'reasons','extractor',p_facts->>'extractor'));
  elsif p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;
  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried
  if p_read_status='name_mismatch' then
    update pipeline.scholarship_page_candidates c set match_basis='rejected_name_mismatch', matched_scholarship_id=null
      from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id and sp.url_source='discovered' and c.id=sp.candidate_id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
    select p_scholarship_id,'provider_page_rejected',jsonb_build_object('url',sp.url,'url_source',sp.url_source),p_facts->'name_check' from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id;
  end if;
  return coalesce(r,jsonb_build_object('applied',false));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with ranked as (
    select c.id, d.priority, row_number() over (partition by c.provider_id order by (c.url ~* 'international') desc, c.found_at, c.id) rn
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)),  -- v2.15.237: paused while the provider is unpublished or archived
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by (c.requested_at is not null) desc, r.rn, (r.priority not in (0,3)), c.id -- 11 Oct 2026: on-demand candidates first
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

do $post$
declare v_expected jsonb := '{"security.admin_job_slice_v1(uuid,integer)": "577823ad1c4c8d9fbccc64ea9fee295f", "security.admin_job_watch_v1(uuid)": "f166a3fba3b7cdaf9b4a00eb75e3cdc6", "public.admin_jobs(text,jsonb)": "b259a26fadfa83605bb9494900a062d9", "public.svc_scholarship_read_next(integer)": "bd0b48fcf536e56e4e83a739a26e70b5", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "8bd3588ac05703567b7d7050a7224f6d", "public.svc_scholarship_candidate_next(integer)": "0080ad829614bf699f313e71db77417e"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
