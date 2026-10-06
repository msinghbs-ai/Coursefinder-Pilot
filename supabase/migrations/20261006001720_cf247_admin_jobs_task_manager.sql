-- CF-247 Decision 254 (6 Oct 2026, Platform Admin 06:59 "mature the pressing button across ui to have same experience ...
-- progress, status updates even when page is refreshed and admin action cancellation power by selecting ongoing task
-- from ui like task manager", and 10:56 "Yes, start now" with Qualify adapters as the first job). Phase A of the job
-- system:
--   pipeline.admin_jobs            one row per long-running admin action: kind, args, lane, state, progress, result
--   pipeline.admin_job_events      what each job did, as it happened
--   pipeline.adapter_qualifications  the measured result of a Qualify run, one row per adapter and field
--   public.admin_jobs(action, args)  start, cancel, pause, resume and read jobs (Operators read and qualify, Platform
--                                  Admins admit)
--   security.admin_jobs_tick_v1    the dispatcher, run every minute by pg_cron: one job at a time per lane, a bounded
--                                  slice of work per tick, progress written to the row, so a page can be refreshed and
--                                  still show where the job is. Cancel and pause take effect at the next provider boundary,
--                                  never half way through a provider.
-- Two job kinds tonight:
--   qualify_adapters   read-only. For the adapters chosen by country, state, provider kind and adapter state, measure each
--                      field against the admission rules (read on at least the "Field found on at least" share of read
--                      pages, and where the catalogue holds values at least "Admit when at least ... agree" of them agree)
--                      and store pass or fail with the counts. Nothing is admitted by this job.
--   admit_qualified    the deliberate step. For a finished Qualify job, admit the passing fields through the existing
--                      admin_uni_adapter_control('admit') as the person who started the job, one logged event per
--                      provider. Fields already admitted stay admitted. Values entered by hand are never touched (the
--                      existing admission rules keep that).
-- No text value in this file contains a semicolon.

-- thresholds live in settings, not in the page
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section)
values ('firecrawl', 'qualify_agree_share', 'Admit when at least this share agree', 'When the catalogue already holds values for a field, a Qualify run passes the field only if at least this share of the adapter readings agree with them. The read share is "Field found on at least" above.', 'number', '0.9'::jsonb, 0, 1, 'share', 430, 'Decision 254, job system Phase A (6 Oct 2026)', 'Adapter evaluation')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.admin_jobs (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('qualify_adapters', 'admit_qualified')),
  lane text not null default 'adapters',
  state text not null default 'queued' check (state in ('queued', 'running', 'paused', 'done', 'failed', 'cancelled')),
  title text not null,
  args jsonb not null default '{}'::jsonb,
  cursor jsonb not null default '{}'::jsonb,
  progress jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  error text,
  cancel_requested boolean not null default false,
  pause_requested boolean not null default false,
  requested_by uuid not null,
  reason text not null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  updated_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists admin_jobs_lane_state_idx on pipeline.admin_jobs(lane, state, created_at);
alter table pipeline.admin_jobs enable row level security;
revoke all on table pipeline.admin_jobs from anon, authenticated;

create table if not exists pipeline.admin_job_events (
  id bigserial primary key,
  job_id uuid not null references pipeline.admin_jobs(id),
  at timestamptz not null default now(),
  note text not null,
  detail jsonb
);
create index if not exists admin_job_events_job_idx on pipeline.admin_job_events(job_id, id);
alter table pipeline.admin_job_events enable row level security;
revoke all on table pipeline.admin_job_events from anon, authenticated;

create table if not exists pipeline.adapter_qualifications (
  job_id uuid not null references pipeline.admin_jobs(id),
  provider_id uuid not null references catalogue.providers(id),
  measured_at timestamptz not null default now(),
  pages_read integer not null default 0,
  fields jsonb not null default '{}'::jsonb,
  passing text[] not null default '{}',
  primary key (job_id, provider_id)
);
create index if not exists adapter_qualifications_provider_idx on pipeline.adapter_qualifications(provider_id, measured_at desc);
alter table pipeline.adapter_qualifications enable row level security;
revoke all on table pipeline.adapter_qualifications from anon, authenticated;

-- One adapter measured against the admission rules. Pages counted: read, with an identity, not excluded for the field.
-- A delivery reading that normalises to on_campus_and_online is a required mix the reader did not understand: unclear.
create or replace function security.adapter_qualify_one_v1(p_provider_id uuid, p_min_read numeric, p_min_agree numeric) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_pages int; v_fields jsonb := '{}'::jsonb; v_pass text[] := '{}'; r record; v_f jsonb; v_share numeric; v_agree_share numeric; v_ok boolean; v_why text;
begin
  select count(*) into v_pages from pipeline.coverage_course_pages pg where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null;
  for r in
    with pg as (
      select pg.course_id, pg.candidates c from pipeline.coverage_course_pages pg
       where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null),
    m as (
      select 'intakes' field,
             count(*) filter (where x.rd and not x.ex) rd, count(*) filter (where x.rd and not x.ex and x.held and x.eq) ag, count(*) filter (where x.rd and not x.ex and x.held and not x.eq) df, count(*) filter (where x.rd and not x.ex and not x.held) nw, count(*) filter (where x.ex) ex, 0 un
        from (select (pg.c->>'intakes_by' = 'adapter') rd, security.uni_adapter_excluded(pg.course_id, 'intakes') ex,
                     h.itk is not null held, (h.itk = a.itk) eq
                from pg
                cross join lateral (select array_agg(distinct m order by m) itk from jsonb_array_elements_text(coalesce(pg.c->'intakes', '[]'::jsonb)) m) a
                cross join lateral (select array_agg(distinct i.intake_label order by i.intake_label) itk from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') h) x
      union all
      select 'fee',
             count(*) filter (where x.rd and not x.ex), count(*) filter (where x.rd and not x.ex and x.held and x.eq), count(*) filter (where x.rd and not x.ex and x.held and not x.eq), count(*) filter (where x.rd and not x.ex and not x.held), count(*) filter (where x.ex), 0
        from (select (pg.c->>'fee_by' = 'adapter' and nullif(pg.c->'fee'->>'value', '') is not null) rd, security.uni_adapter_excluded(pg.course_id, 'fee') ex,
                     exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international') held,
                     exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount = nullif(pg.c->'fee'->>'value', '')::numeric) eq
                from pg) x
      union all
      select 'english',
             count(*) filter (where x.rd and not x.ex), count(*) filter (where x.rd and not x.ex and x.held and x.eq), count(*) filter (where x.rd and not x.ex and x.held and not x.eq), count(*) filter (where x.rd and not x.ex and not x.held), count(*) filter (where x.ex), 0
        from (select (pg.c->>'english_by' = 'adapter' and nullif(pg.c->'english'->>'ielts_overall', '') is not null) rd, security.uni_adapter_excluded(pg.course_id, 'english') ex,
                     h.score is not null held, (h.score = nullif(pg.c->'english'->>'ielts_overall', '')::numeric) eq
                from pg
                cross join lateral (select max(e.overall_score) score from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id and t.code = 'IELTS' where e.course_id = pg.course_id and e.status = 'active') h) x
      union all
      select 'delivery',
             count(*) filter (where x.rd and not x.ex), count(*) filter (where x.rd and not x.ex and x.held and x.eq), count(*) filter (where x.rd and not x.ex and x.held and not x.eq), count(*) filter (where x.rd and not x.ex and not x.held), count(*) filter (where x.ex), count(*) filter (where x.un and not x.ex)
        from (select (x0.mode is not null and x0.mode <> 'on_campus_and_online') rd, (x0.mode = 'on_campus_and_online') un, security.uni_adapter_excluded(pg.course_id, 'delivery') ex,
                     co.delivery_mode is not null held, (co.delivery_mode = x0.mode) eq
                from pg join catalogue.courses co on co.id = pg.course_id
                cross join lateral (select security.delivery_mode_from_text(pg.c->'adapter_extra'->>'mode') mode) x0) x)
    select * from m
  loop
    v_share := case when (v_pages - r.ex) > 0 then round(r.rd::numeric / (v_pages - r.ex), 3) else 0 end;
    v_agree_share := case when (r.ag + r.df) > 0 then round(r.ag::numeric / (r.ag + r.df), 3) else null end;
    v_ok := r.rd > 0 and v_share >= p_min_read and (v_agree_share is null or v_agree_share >= p_min_agree);
    v_why := case when r.rd = 0 then 'not read by the adapter'
                  when v_share < p_min_read then 'read on ' || r.rd || ' of ' || (v_pages - r.ex) || ' pages, under the share needed'
                  when v_agree_share is not null and v_agree_share < p_min_agree then r.df || ' of ' || (r.ag + r.df) || ' readings differ from the catalogue'
                  when r.un > 0 then 'passes, but ' || r.un || ' page(s) print a required mix the reader did not understand'
                  else 'passes' end;
    v_f := jsonb_build_object('read', r.rd, 'agree', r.ag, 'differ', r.df, 'new', r.nw, 'excluded', r.ex, 'unclear', r.un, 'read_share', v_share, 'agree_share', v_agree_share, 'pass', v_ok, 'why', v_why);
    v_fields := v_fields || jsonb_build_object(r.field, v_f);
    if v_ok then v_pass := v_pass || r.field; end if;
  end loop;
  return jsonb_build_object('pages_read', v_pages, 'fields', v_fields, 'passing', to_jsonb(v_pass));
end $f$;
revoke all on function security.adapter_qualify_one_v1(uuid, numeric, numeric) from public, anon, authenticated;

-- The providers a Qualify job covers: by country, state (subdivision code), provider kind and adapter state.
create or replace function security.admin_jobs_resolve_adapters_v1(p_args jsonb) returns uuid[]
language plpgsql stable security definer set search_path = '' as $f$
declare v_country text := upper(nullif(btrim(coalesce(p_args->>'country', '')), '')); v_state text := upper(nullif(btrim(coalesce(p_args->>'state', '')), ''));
        v_kind text := coalesce(nullif(p_args->>'provider_kind', ''), 'any'); v_adapter text := coalesce(nullif(p_args->>'adapter_state', ''), 'enabled');
        v_pat text := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
        v_ids uuid[];
begin
  if p_args ? 'provider_ids' and jsonb_typeof(p_args->'provider_ids') = 'array' and jsonb_array_length(p_args->'provider_ids') > 0 then
    return array(select distinct (x)::uuid from jsonb_array_elements_text(p_args->'provider_ids') x
                  where exists (select 1 from pipeline.uni_adapters u where u.provider_id = (x)::uuid));
  end if;
  v_ids := array(
    select p.id from catalogue.providers p
      join ref.countries k on k.id = p.country_id
      left join ref.subdivisions s on s.id = p.subdivision_id
      join pipeline.uni_adapters u on u.provider_id = p.id
     where (v_country is null or k.iso_alpha2 = v_country)
       and (v_state is null or upper(s.code) = v_state)
       and (v_kind <> 'university' or coalesce(p.display_name, p.canonical_name) ~* v_pat)
       and (v_adapter = 'any' or (v_adapter = 'enabled' and u.enabled) or (v_adapter = 'testing' and u.enabled and not u.admit) or (v_adapter = 'admitting' and u.enabled and u.admit))
     order by coalesce(p.display_name, p.canonical_name));
  return v_ids;
end $f$;
revoke all on function security.admin_jobs_resolve_adapters_v1(jsonb) from public, anon, authenticated;

create or replace function public.admin_jobs(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_id uuid; v_kind text; v_ids uuid[]; v_j pipeline.admin_jobs%rowtype;
        v_q pipeline.admin_jobs%rowtype; v_fields text[]; v_title text; v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'jobs', coalesce((select jsonb_agg(to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0), 'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by)) order by j.created_at desc)
                         from (select * from pipeline.admin_jobs order by created_at desc limit greatest(1, least(coalesce((p_args->>'limit')::int, 50), 200))) j), '[]'::jsonb),
      'job', case when p_args ? 'id' then (select to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0),
                    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc) from (select * from pipeline.admin_job_events e where e.job_id = j.id order by e.id desc limit 200) e), '[]'::jsonb),
                    'qualifications', coalesce((select jsonb_agg(jsonb_build_object('provider_id', q.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(p.id), 'pages_read', q.pages_read, 'fields', q.fields, 'passing', q.passing, 'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = q.provider_id), 'admitted', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.admit)) order by coalesce(p.display_name, p.canonical_name))
                                       from pipeline.adapter_qualifications q join catalogue.providers p on p.id = q.provider_id where q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid), '[]'::jsonb))
                  from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid) end,
      'settings', jsonb_build_object('min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb), 'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)),
      'countries', coalesce((select jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'adapters', n.n) order by k.name) from ref.countries k join (select p.country_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.country_id) n on n.country_id = k.id), '[]'::jsonb),
      'states', coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'country', k.iso_alpha2, 'adapters', n.n) order by s.code) from ref.subdivisions s join ref.countries k on k.id = s.country_id join (select p.subdivision_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.subdivision_id) n on n.subdivision_id = s.id), '[]'::jsonb),
      'can_admit', v_rank >= 6);
  end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    v_kind := p_args->>'kind';
    if v_kind = 'qualify_adapters' then
      if v_rank < 5 then raise exception 'Operator (adapters) or above required' using errcode = '42501'; end if;
      v_ids := security.admin_jobs_resolve_adapters_v1(coalesce(p_args->'args', '{}'::jsonb));
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapters match that choice'; end if;
      v_title := 'Qualify ' || array_length(v_ids, 1) || ' adapter(s)' || coalesce(' in ' || nullif(btrim(coalesce(p_args->'args'->>'state', p_args->'args'->>'country', '')), ''), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason)
        values (v_kind, 'adapters', v_title, coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason)
        returning * into v_j;
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
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qualification_job_id', v_q.id, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason)
        returning * into v_j;
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
    if v_j.state in ('queued', 'paused') then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now(), cancel_requested = true where id = v_id;
    else
      update pipeline.admin_jobs set cancel_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'pause' then
    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'; end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'paused', updated_at = now() where id = v_id;
    else
      update pipeline.admin_jobs set pause_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'resume' then
    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'; end if;
    update pipeline.admin_jobs set state = 'queued', pause_requested = false, updated_at = now() where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_id, p_action || ' requested by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_' || p_action, v_id::text, jsonb_build_object('title', v_j.title, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id);
end $f$;
revoke all on function public.admin_jobs(text, jsonb) from public, anon;
grant execute on function public.admin_jobs(text, jsonb) to authenticated;

-- One slice of one job: at most p_items providers, then back to the dispatcher. Returns true when the job is finished.
create or replace function security.admin_job_slice_v1(p_id uuid, p_items integer) returns boolean
language plpgsql security definer set search_path = '' as $f$
declare v_j pipeline.admin_jobs%rowtype; v_next int; v_total int; v_ids uuid[]; v_pid uuid; v_r jsonb; v_min_read numeric; v_min_agree numeric;
        v_done int := 0; v_errs int; v_pass int; v_fields text[]; v_have text[]; v_want text[]; v_claims text; v_res jsonb; v_added text[];
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
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
        select q.passing into v_fields from pipeline.adapter_qualifications q where q.job_id = (v_j.args->>'qualification_job_id')::uuid and q.provider_id = v_pid;
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
end $f$;
revoke all on function security.admin_job_slice_v1(uuid, integer) from public, anon, authenticated;

-- The dispatcher: one job per lane per tick, a bounded slice each.
create or replace function security.admin_jobs_tick_v1(p_items integer default 10) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_lane text; v_j pipeline.admin_jobs%rowtype; v_fin boolean; v_out jsonb := '[]'::jsonb;
begin
  for v_lane in select distinct lane from pipeline.admin_jobs where state in ('queued', 'running') loop
    select * into v_j from pipeline.admin_jobs j where j.lane = v_lane and j.state in ('queued', 'running')
     order by (j.state = 'running') desc, j.created_at limit 1 for update skip locked;
    if v_j.id is null then continue; end if;
    if v_j.cancel_requested then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'cancelled at a provider boundary, work done so far kept');
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'cancelled'); continue;
    end if;
    if v_j.pause_requested then
      update pipeline.admin_jobs set state = 'paused', pause_requested = false, updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'paused at a provider boundary');
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'paused'); continue;
    end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'running', started_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'started');
    end if;
    begin
      v_fin := security.admin_job_slice_v1(v_j.id, p_items);
    exception when others then
      update pipeline.admin_jobs set state = 'failed', error = left(sqlerrm, 500), finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'failed: ' || left(sqlerrm, 300));
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'failed'); continue;
    end;
    if v_fin then
      update pipeline.admin_jobs set state = 'done', finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'finished', (select j.result from pipeline.admin_jobs j where j.id = v_j.id));
    end if;
    v_out := v_out || jsonb_build_object('id', v_j.id, 'state', case when v_fin then 'done' else 'running' end);
  end loop;
  return v_out;
end $f$;
revoke all on function security.admin_jobs_tick_v1(integer) from public, anon, authenticated;

select cron.schedule('admin-jobs', '* * * * *', $c$select security.admin_jobs_tick_v1(10)$c$)
 where not exists (select 1 from cron.job where jobname = 'admin-jobs');
