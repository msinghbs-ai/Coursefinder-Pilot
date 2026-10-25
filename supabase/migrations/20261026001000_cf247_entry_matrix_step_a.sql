-- CF-247 Track C, entry requirements Step A (drafted 25 Oct 2026 overnight; merge position fixed by the Platform Admin 18:54, amended 22:27:
-- #694 gate consolidation → SP-1 (#696) → this; extraction runs start after Track B release 1). Design: admin repo docs/platform/ENTRY-REQUIREMENTS.md 1.1 and
-- docs/platform/ENTRY-REQUIREMENTS-IMPLEMENTATION.md Part 2 (2.1 tables, 2.2 matrix reader, 2.5 step A), decisions 25 Oct 14:50 (7–10).
--
-- Declared file boundary (outcomes record 25 Oct 19:02): the matrix and course-requirement tables, the new reader (worker mode entry_ai,
-- its svc next/record), central-page discovery's page-type list, and Layer 4 first-run items. NOTHING in the search picker, stop gates,
-- course_events or the blade.
--
-- 1. catalogue.provider_entry_matrix: one row = one published minimum (country of prior education × study level × qualification), with
--    its verbatim quote, edition and provenance. No numeric value without a scale (B1 rule) is a table check.
-- 2. catalogue.course_entry_requirements: the B1 table (plural, like course_english_requirements) with the design's additions
--    (override, general_note, min_entry_score + basis, benchmark_band, provenance). Nothing writes it in step A (B1 extension, later).
-- 3. pipeline.entry_matrix_runs: one AI read of one stored entry-requirements page version (fact source × content hash).
-- 4. Central-page discovery gains the page type entry_requirements (the worker's central.ts rules; suggestions land in
--    pipeline.provider_central_search.found as for the other kinds). The reader keeps its own page list, pipeline.entry_matrix_sources
--    (found suggestions attached by its job, at most entry.attach_per_provider; known pages seeded by the Platform Admin), so the
--    shared provider-facts lane and its kind check are not touched. Stored first: a page already held in evidence is used as is;
--    otherwise a direct read (robots.txt respected, never bypassed), and Firecrawl only when the site refuses a direct read.
--    PDFs wait for step B.
-- 5. Layer 4: field codes entry_matrix_first_run (no admitted matrix yet) and entry_matrix_change (a changed page), entity provider.
--    Every run with rows goes to a person while entry.matrix_first_run_review is 1 (it stays 1). Approve admits the run's rows
--    (edit-and-approve may exclude rows: {"exclude_row_ids": [...]}) and supersedes the provider's earlier rows from that page; reject,
--    more evidence and returns quarantine the run's rows (status inactive; nothing deleted).
-- 6. Job entry-matrix-read (catalogued; cron INACTIVE, entry.matrix_enabled 0). Activation is a separate, deliberate step after
--    Track B release 1 lands; a passing test never activates it.
-- 7. AI spend line entry_matrix in security.ai_spend_today_v1 (and its daily guard), so the reader is inside the AI stop.
--
-- Status vocabulary deviation (recorded): rows waiting for the first-run review are 'proposed' (the design listed active / inactive /
-- superseded / unverified only; a row cannot be active before a person approves it).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched in step A (the additive entry
-- fields ship with the consumer API step, under the 14:36 approval).

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

-- ---------------------------------------------------------------- 1–3 tables
create table pipeline.entry_matrix_sources (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  url text not null check (url ~ '^https?://'),
  title text,
  rank int not null default 1,
  found_via text not null check (found_via in ('search', 'manual')),
  status text not null default 'found' check (status in ('found', 'reading', 'read', 'failed', 'robots_disallowed', 'pdf_step_b', 'inactive')),
  read_via text check (read_via in ('stored', 'direct', 'firecrawl')),
  http_status int,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  content_hash text,
  attempts int not null default 0,
  read_at timestamptz,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider_id, url)
);
comment on table pipeline.entry_matrix_sources is 'CF-247 Track C: the entry matrix reader''s own page list (one entry-requirements page per row: found by central-page discovery or seeded by the Platform Admin), with its stored copy (evidence) and how it was read (stored, direct with robots.txt respected, or Firecrawl when the site refuses a direct read).';
create index entry_matrix_sources_status_idx on pipeline.entry_matrix_sources (status, updated_at);
create index entry_matrix_sources_evidence_idx on pipeline.entry_matrix_sources (evidence_id);
alter table pipeline.entry_matrix_sources enable row level security;

create table catalogue.provider_entry_matrix (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  course_id uuid references catalogue.courses(id),
  course_label text,
  matrix_kind text not null default 'provider_minimum' check (matrix_kind in ('provider_minimum', 'band_ladder', 'course_minimum', 'rank_band')),
  benchmark_band text,
  level_label text,
  study_level_id uuid references ref.study_levels(id),
  country_id uuid not null references ref.countries(id),
  country_code text not null,
  qualification_name text not null,
  min_grade text,
  min_value numeric,
  grade_scale text check (grade_scale in ('percentage', 'points', 'aggregate', 'gpa', 'letter', 'rank', 'none')),
  conditions jsonb not null default '{}'::jsonb,
  audience text not null default 'international' check (audience in ('international', 'domestic', 'all')),
  edition text,
  intake_year int,
  quote text not null check (length(quote) between 1 and 300),
  source_url text not null,
  source_id uuid references pipeline.entry_matrix_sources(id),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  content_hash text,
  run_id uuid,
  confidence numeric,
  as_at date not null default current_date,
  status text not null default 'proposed' check (status in ('proposed', 'active', 'inactive', 'superseded', 'unverified')),
  status_reason text,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_entry_matrix_value_needs_scale check (min_value is null or (grade_scale is not null and grade_scale <> 'none'))
);
comment on table catalogue.provider_entry_matrix is 'CF-247 Track C (entry requirements step A): one published academic entry minimum per provider (or per course), country of prior education, study level and qualification, with its verbatim quote, edition and provenance. Rows arrive proposed and are admitted by a person in Layer 4 (entry_matrix_first_run / entry_matrix_change). Design: admin docs/platform/ENTRY-REQUIREMENTS.md 1.1.';
create index provider_entry_matrix_provider_idx on catalogue.provider_entry_matrix (provider_id, status);
create index provider_entry_matrix_country_idx on catalogue.provider_entry_matrix (country_id) where status = 'active';
create index provider_entry_matrix_run_idx on catalogue.provider_entry_matrix (run_id);
create index provider_entry_matrix_course_idx on catalogue.provider_entry_matrix (course_id) where course_id is not null;
create index provider_entry_matrix_source_idx on catalogue.provider_entry_matrix (source_id);
create index provider_entry_matrix_evidence_idx on catalogue.provider_entry_matrix (evidence_id);
alter table catalogue.provider_entry_matrix enable row level security;

create table catalogue.course_entry_requirements (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id),
  kind text not null check (kind in ('prior_qualification', 'minimum_grade', 'subject_prerequisite', 'portfolio_interview', 'work_experience', 'other', 'override', 'general_note')),
  audience text not null default 'international' check (audience in ('international', 'domestic', 'all')),
  country_id uuid references ref.countries(id),
  description text not null,
  min_grade text,
  min_value numeric,
  grade_scale text check (grade_scale in ('percentage', 'points', 'aggregate', 'gpa', 'letter', 'rank', 'none')),
  min_entry_score numeric,
  min_entry_score_basis text,
  benchmark_band text,
  quote text not null check (length(quote) between 1 and 300),
  source_url text,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  confidence numeric,
  as_at date not null default current_date,
  status text not null default 'proposed' check (status in ('proposed', 'active', 'inactive', 'superseded', 'unverified')),
  status_reason text,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_entry_requirements_value_needs_scale check (min_value is null or (grade_scale is not null and grade_scale <> 'none')),
  constraint course_entry_requirements_score_needs_basis check (min_entry_score is null or nullif(trim(min_entry_score_basis), '') is not null)
);
comment on table catalogue.course_entry_requirements is 'CF-247 entry requirements (B1 course-level table, extended by Track C): a course''s own academic entry requirements (prior qualification, minimum grade, prerequisites, selection tasks, override, general note, minimum entry score with its basis, benchmark band) with quote and provenance. Written by the B1 course-page reader (later step); empty in step A.';
create index course_entry_requirements_course_idx on catalogue.course_entry_requirements (course_id, status);
create index course_entry_requirements_evidence_idx on catalogue.course_entry_requirements (evidence_id);
alter table catalogue.course_entry_requirements enable row level security;

create table pipeline.entry_matrix_runs (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  source_id uuid not null references pipeline.entry_matrix_sources(id),
  content_hash text not null,
  state text not null default 'queued' check (state in ('queued', 'leased', 'done', 'failed')),
  attempts int not null default 0,
  leased_until timestamptz,
  model_code text,
  slices int,
  rows_admitted int,
  rows_dropped int,
  result jsonb,
  cost_usd numeric not null default 0,
  error text,
  review_item_id uuid references pipeline.layer4_review_items(id),
  created_at timestamptz not null default now(),
  done_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (source_id, content_hash)
);
comment on table pipeline.entry_matrix_runs is 'CF-247 Track C: one AI read (pinned model entry.matrix_model) of one stored entry-requirements page version. Rows land in catalogue.provider_entry_matrix as proposed; the run''s Layer 4 item admits or quarantines them. An unchanged page (same content hash) is never read twice.';
create index entry_matrix_runs_source_idx on pipeline.entry_matrix_runs (source_id);
create index entry_matrix_runs_state_idx on pipeline.entry_matrix_runs (state, created_at);
create index entry_matrix_runs_review_idx on pipeline.entry_matrix_runs (review_item_id);
create index entry_matrix_runs_provider_idx on pipeline.entry_matrix_runs (provider_id);
alter table pipeline.entry_matrix_runs enable row level security;

-- ---------------------------------------------------------------- settings (G2: every tunable)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.matrix_enabled', 'Entry matrices: reader on', 'Turns the entry matrix reader on (1) or off (0): attaching found entry-requirements pages, fetching them (stored copy first) and reading them with AI. Off until the Platform Admin activates it after Track B release 1.', 'number', '0'::jsonb, 0, 1, 'on/off', 900, 'Entry requirements', 'security.entry_matrix_enabled_v1, job entry-matrix-read', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.countries', 'Entry matrices: countries', 'Countries whose providers'' entry-requirements pages are read.', 'list', '["AU","NZ"]'::jsonb, null, null, 'countries', 901, 'Entry requirements', 'security.entry_matrix_enabled_v1', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.matrix_model', 'Entry matrices: pinned model', 'The one model that reads entry matrices (OpenRouter id). Pinned: never an automatic router; changing it is a qualification decision.', 'text', '"openai/gpt-4.1-mini"'::jsonb, null, null, null, 902, 'Entry requirements', 'public.svc_entry_matrix_next', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.matrix_min_confidence', 'Entry matrices: minimum confidence', 'A row the model gives a lower confidence than this is not proposed (counted as dropped, reason low_confidence).', 'number', '0.85'::jsonb, 0.5, 1, 'confidence', 903, 'Entry requirements', 'public.svc_entry_matrix_record', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.matrix_max_rows_per_page', 'Entry matrices: rows a slice', 'A large one-page table is read in slices of at most this many lines (rows); every slice is one AI call.', 'number', '400'::jsonb, 50, 2000, 'rows', 904, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.matrix_first_run_review', 'Entry matrices: changes to a person', '1: every read with rows goes to Layer 4 (first run and changed pages). 0: a changed page whose rows all meet the confidence is admitted without a person. A first run always goes to a person.', 'number', '1'::jsonb, 0, 1, 'on/off', 905, 'Entry requirements', 'public.svc_entry_matrix_record', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.matrix_refresh_days', 'Entry matrices: re-fetch after', 'An entry-requirements page read this many days ago is fetched again; it is read with AI again only when its content changed.', 'number', '30'::jsonb, 7, 180, 'days', 906, 'Entry requirements', 'security.entry_matrix_fire_v1', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.matrix_attempts', 'Entry matrices: tries a page', 'An AI read that fails is tried again up to this many times.', 'number', '3'::jsonb, 1, 10, 'tries', 907, 'Entry requirements', 'public.svc_entry_matrix_next, public.svc_entry_matrix_record, public.svc_entry_matrix_fetch_next', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'entry.attach_per_provider', 'Entry matrices: pages tried a provider', 'At most this many found entry-requirements pages are attached for one provider.', 'number', '3'::jsonb, 1, 10, 'pages', 908, 'Entry requirements', 'security.entry_matrix_attach_v1', 'CF-247 Track C step A (25 Oct 2026)'),
 ('pipeline', 'batch.entry_matrix', 'Entry matrices: pages a run', 'Entry-requirements pages read with AI in one worker call.', 'number', '4'::jsonb, 1, 20, 'pages a run', 909, 'Entry requirements', 'job entry-matrix-read', 'CF-247 Track C step A (25 Oct 2026)'),
 ('openrouter', 'guard_entry_matrix', 'Daily guard: entry matrices with AI', 'The entry matrix reader stops for the day when its AI spend reaches this (UTC day), inside the overall credit floor.', 'number', '2'::jsonb, 0, 500, 'US$ a day', 49, 'Daily guards', 'security.ai_use_allowed_v1(''entry_matrix'')', 'CF-247 Track C step A (25 Oct 2026)')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- reader gate, attach, enqueue
create or replace function security.entry_matrix_enabled_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select security.pipeline_num_v1('entry.matrix_enabled', 0) >= 1
     and exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id
                  where p.id = p_provider
                    and coalesce(security.toolset_setting('pipeline', 'entry.countries'), '["AU","NZ"]'::jsonb) ? k.iso_alpha2::text)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)
$$;
comment on function security.entry_matrix_enabled_v1(uuid) is 'CF-247 Track C: the entry matrix reader works on this provider (entry.matrix_enabled on, country in entry.countries, provider published).';

-- found entry-requirements suggestions (central_find) become reader sources, best first, at most entry.attach_per_provider a provider
create or replace function security.entry_matrix_attach_v1() returns int
language plpgsql security definer set search_path to '' as $$
declare v_n int := 0; v_max int := security.pipeline_num_v1('entry.attach_per_provider', 3)::int;
begin
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return 0; end if;
  insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
  select x.provider_id, x.url, x.title, x.rn, 'search'
    from (select s.provider_id, e->>'url' url, left(e->>'title', 200) title,
                 row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc, length(e->>'url')) rn
            from pipeline.provider_central_search s, jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
           where e->>'kind' = 'entry_requirements' and e->>'url' ~ '^https?://'
             and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
             and security.entry_matrix_enabled_v1(s.provider_id)) x
   where x.rn <= v_max
     and (select count(*) from pipeline.entry_matrix_sources m where m.provider_id = x.provider_id) < v_max
  on conflict (provider_id, url) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- a person may seed known entry pages (the 19 HTML providers of Part 1); Platform Admin only, logged
create or replace function public.admin_entry_matrix_seed(p_rows jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_n int;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'reason required'; end if;
  insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
  select (r->>'provider_id')::uuid, r->>'url', left(r->>'title', 200), 1, 'manual'
    from jsonb_array_elements(p_rows) r
   where exists (select 1 from catalogue.providers p where p.id = (r->>'provider_id')::uuid) and r->>'url' ~ '^https?://'
  on conflict (provider_id, url) do nothing;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'seed', 'pipeline.entry_matrix_sources', jsonb_build_object('rows', jsonb_array_length(p_rows), 'added', v_n, 'reason', trim(p_reason)), auth.uid());
  return jsonb_build_object('ok', true, 'added', v_n);
end $$;
revoke all on function public.admin_entry_matrix_seed(jsonb, text) from public, anon;
grant execute on function public.admin_entry_matrix_seed(jsonb, text) to authenticated;

-- stored first: a page whose address is already held in evidence (a copy younger than entry.matrix_refresh_days) is taken from storage, not fetched
create or replace function security.entry_matrix_use_stored_v1() returns int
language plpgsql security definer set search_path to '' as $$
declare v_n int;
begin
  with c as (select s.id, (select a.id from pipeline.evidence_artifacts a
                            where a.source_url = s.url and a.storage_path is not null
                              and coalesce(a.captured_at, a.created_at) > now() - make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int)
                            order by coalesce(a.captured_at, a.created_at) desc limit 1) eid
                from pipeline.entry_matrix_sources s where s.status = 'found' and security.entry_matrix_enabled_v1(s.provider_id))
  update pipeline.entry_matrix_sources s set status = 'read', read_via = 'stored', evidence_id = e.id, content_hash = coalesce(e.content_hash, e.id::text),
         read_at = now(), error = null, updated_at = now()
    from c join pipeline.evidence_artifacts e on e.id = c.eid
   where s.id = c.id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- pages not held: the worker reads them (direct first, robots.txt respected; Firecrawl only when the site refuses); PDFs wait for step B
create or replace function public.svc_entry_matrix_fetch_next(p_limit integer) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return '[]'::jsonb; end if;
  update pipeline.entry_matrix_sources s set status = 'pdf_step_b', updated_at = now()
   where s.status = 'found' and s.url ~* '\.pdf($|[?#])';
  with pick as (select s.id from pipeline.entry_matrix_sources s
                 where (s.status = 'found' or (s.status = 'reading' and s.updated_at < now() - interval '20 minutes'))  -- fixed: claim timer
                   and s.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3)
                   and security.entry_matrix_enabled_v1(s.provider_id)
                 order by s.rank, s.created_at limit greatest(1, least(coalesce(p_limit, 4), 20)) for update skip locked),
  upd as (update pipeline.entry_matrix_sources s set status = 'reading', attempts = s.attempts + 1, updated_at = now() from pick where s.id = pick.id returning s.*)
  select coalesce(jsonb_agg(jsonb_build_object('source_id', u.id, 'provider_id', u.provider_id, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $$;
revoke all on function public.svc_entry_matrix_fetch_next(integer) from public, anon, authenticated;
grant execute on function public.svc_entry_matrix_fetch_next(integer) to service_role;

create or replace function public.svc_entry_matrix_fetch_record(p_source_id uuid, p_status text, p_via text, p_http integer, p_storage_path text,
                                                                p_sha256 text, p_mime text, p_error text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare s pipeline.entry_matrix_sources%rowtype; v_src uuid; v_ev uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into s from pipeline.entry_matrix_sources where id = p_source_id for update;
  if s.id is null then raise exception 'source not found'; end if;
  if p_status = 'read' and p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src := security.coverage_sweep_source(s.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id = v_src and content_hash = p_sha256 and source_url = s.url limit 1;
    if v_ev is null then
      v_ev := public.svc_coursefacts_register_evidence(v_src, s.url, p_storage_path, p_sha256, coalesce(p_mime, 'text/html'),
                jsonb_build_object('layer', 2, 'kind', 'provider_entry_requirements', 'worker', 'coverage-sweep', 'entry_matrix_source_id', s.id, 'read_via', p_via));
    end if;
    update pipeline.entry_matrix_sources set status = 'read', read_via = p_via, http_status = p_http, evidence_id = v_ev, content_hash = p_sha256,
           read_at = now(), error = null, updated_at = now() where id = s.id;
    return jsonb_build_object('status', 'read', 'evidence_id', v_ev);
  end if;
  update pipeline.entry_matrix_sources set
         status = case when p_status = 'robots_disallowed' then 'robots_disallowed'
                       when attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) then 'failed' else 'found' end,
         http_status = p_http, error = left(coalesce(p_error, p_status), 400), updated_at = now()
   where id = s.id;
  return jsonb_build_object('status', p_status);
end $$;
revoke all on function public.svc_entry_matrix_fetch_record(uuid, text, text, integer, text, text, text, text) from public, anon, authenticated;
grant execute on function public.svc_entry_matrix_fetch_record(uuid, text, text, integer, text, text, text, text) to service_role;

-- each stored entry page version not read yet is queued once (same content hash = never read again)
create or replace function security.entry_matrix_enqueue_v1() returns int
language plpgsql security definer set search_path to '' as $$
declare v_n int;
begin
  insert into pipeline.entry_matrix_runs(provider_id, source_id, content_hash)
  select s.provider_id, s.id, coalesce(s.content_hash, s.evidence_id::text)
    from pipeline.entry_matrix_sources s
   where s.status = 'read' and s.evidence_id is not null and security.entry_matrix_enabled_v1(s.provider_id)
  on conflict (source_id, content_hash) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------------------------------------------------------------- worker next / record
create or replace function public.svc_entry_matrix_next(p_limit integer) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v jsonb; v_model text := coalesce(security.toolset_setting('pipeline', 'entry.matrix_model') #>> '{}', 'openai/gpt-4.1-mini');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 or not security.ai_use_allowed_v1('entry_matrix') then return '[]'::jsonb; end if;
  with pick as (select r.id from pipeline.entry_matrix_runs r
                 where (r.state = 'queued' or (r.state = 'leased' and r.leased_until < now()))
                   and r.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3)
                   and security.entry_matrix_enabled_v1(r.provider_id)
                 order by r.created_at limit greatest(1, least(coalesce(p_limit, 4), 20)) for update skip locked),
  upd as (update pipeline.entry_matrix_runs r set state = 'leased', leased_until = now() + interval '5 minutes',  -- fixed: lease timer
                 attempts = r.attempts + 1, model_code = v_model, updated_at = now() from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('run_id', u.id, 'source_id', u.source_id, 'provider_id', u.provider_id,
           'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'url', s.url, 'storage_path', e.storage_path, 'mime', e.mime_type,
           'model', v_model, 'model_code', split_part(v_model, '/', 2),
           'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int)), '[]'::jsonb) into v
    from upd u join pipeline.entry_matrix_sources s on s.id = u.source_id join pipeline.evidence_artifacts e on e.id = s.evidence_id
    join catalogue.providers p on p.id = u.provider_id left join ref.countries k on k.id = p.country_id;
  return v;
end $$;
revoke all on function public.svc_entry_matrix_next(integer) from public, anon, authenticated;
grant execute on function public.svc_entry_matrix_next(integer) to service_role;

-- the provider's own label → reference study level, where it maps plainly (else null; the label is kept)
create or replace function security.entry_level_map_v1(p_label text) returns uuid
language sql stable security definer set search_path to '' as $$
  select l.id from ref.study_levels l
   where l.code = case
     when p_label ~* 'phd|doctor' then 'doctorate'
     when p_label ~* 'master|postgrad' then 'masters'
     when p_label ~* 'graduate diploma' then 'graduate_diploma'
     when p_label ~* 'graduate certificate' then 'graduate_certificate'
     when p_label ~* 'associate degree' then 'associate_degree'
     when p_label ~* 'bachelor|degree|undergrad' then 'bachelor'
     when p_label ~* 'advanced diploma' then 'advanced_diploma'
     when p_label ~* 'diploma' then 'diploma'
     when p_label ~* 'foundation|pathway' then 'foundation'
     when p_label ~* 'certificate' then 'certificate'
   end
$$;

create or replace function public.svc_entry_matrix_record(p_run_id uuid, p_result jsonb, p_cost numeric, p_error text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare r pipeline.entry_matrix_runs%rowtype; f pipeline.entry_matrix_sources%rowtype; x jsonb; v_country uuid; v_conf numeric;
        v_min_conf numeric := security.pipeline_num_v1('entry.matrix_min_confidence', 0.85);
        v_in int := 0; v_dropped jsonb := coalesce(p_result->'dropped', '[]'::jsonb); v_item uuid; v_first boolean; v_field text;
        v_all_conf boolean := true;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.entry_matrix_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown run'); end if;
  if p_error is not null then
    update pipeline.entry_matrix_runs set
           state = case when p_error = 'time budget' then 'queued' when attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) then 'failed' else 'queued' end,
           attempts = case when p_error = 'time budget' then greatest(attempts - 1, 0) else attempts end,
           leased_until = null, error = left(p_error, 400), cost_usd = cost_usd + coalesce(p_cost, 0), updated_at = now()
     where id = r.id;
    return jsonb_build_object('ok', true, 'status', 'error');
  end if;
  select * into f from pipeline.entry_matrix_sources where id = r.source_id;
  v_first := not exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = r.provider_id and m.status = 'active');
  for x in select * from jsonb_array_elements(coalesce(p_result->'rows', '[]'::jsonb)) loop
    select k.id into v_country from ref.countries k where k.iso_alpha2 = upper(x->>'country_code');
    v_conf := nullif(x->>'confidence', '')::numeric;
    if v_country is null then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'unknown_country', 'country', x->>'country_name')); continue; end if;
    if coalesce(v_conf, 0) < v_min_conf then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'low_confidence', 'country', x->>'country_code')); continue; end if;
    if nullif(trim(x->>'quote'), '') is null or nullif(trim(x->>'qualification_name'), '') is null then
      v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'missing_quote_or_qualification', 'country', x->>'country_code')); continue; end if;
    if (x->>'min_value') is not null and coalesce(x->>'grade_scale', 'none') = 'none' then
      v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'value_without_scale', 'country', x->>'country_code')); continue; end if;
    insert into catalogue.provider_entry_matrix(provider_id, course_label, matrix_kind, benchmark_band, level_label, study_level_id, country_id, country_code,
             qualification_name, min_grade, min_value, grade_scale, conditions, edition, intake_year, quote, source_url, source_id, evidence_id,
             content_hash, run_id, confidence, status, provenance)
    values (r.provider_id, nullif(trim(x->>'course_name'), ''),
            case when nullif(trim(x->>'course_name'), '') is not null then 'course_minimum' when x->>'grade_scale' = 'rank' then 'rank_band'
                 when nullif(trim(x->>'benchmark_band'), '') is not null then 'band_ladder' else 'provider_minimum' end,
            nullif(trim(x->>'benchmark_band'), ''), nullif(trim(x->>'study_level'), ''), security.entry_level_map_v1(x->>'study_level'),
            v_country, upper(x->>'country_code'), left(trim(x->>'qualification_name'), 300), nullif(trim(x->>'min_grade'), ''),
            (x->>'min_value')::numeric, coalesce(nullif(x->>'grade_scale', ''), 'none'), coalesce(x->'conditions', '{}'::jsonb),
            nullif(trim(p_result->>'edition'), ''), nullif(p_result->>'intake_year', '')::int, left(trim(x->>'quote'), 300), f.url, f.id, f.evidence_id,
            r.content_hash, r.id, v_conf, 'proposed',
            jsonb_build_object('reader', 'entry_ai', 'model', r.model_code, 'run_id', r.id, 'worker', p_result->>'worker', 'prompt', p_result->>'prompt_version'));
    v_in := v_in + 1;
  end loop;
  if v_in > 0 then
    v_field := case when v_first then 'entry_matrix_first_run' else 'entry_matrix_change' end;
    if v_first or security.pipeline_num_v1('entry.matrix_first_run_review', 1) >= 1 then
      insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state,
                                               status, escalation_reason, change_control_ref)
      values ('provider', r.provider_id, v_field, f.evidence_id,
              jsonb_build_object('active_rows', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = r.provider_id and m.status = 'active')),
              jsonb_build_object('run_id', r.id, 'url', f.url, 'rows', v_in, 'dropped', jsonb_array_length(v_dropped),
                'countries', (select count(distinct m.country_id) from catalogue.provider_entry_matrix m where m.run_id = r.id),
                'sample', (select jsonb_agg(jsonb_build_object('id', m.id, 'country', m.country_code, 'level', m.level_label, 'qualification', m.qualification_name,
                                   'min_grade', m.min_grade, 'scale', m.grade_scale, 'band', m.benchmark_band, 'quote', m.quote) order by m.country_code, m.level_label)
                             from (select * from catalogue.provider_entry_matrix m2 where m2.run_id = r.id order by m2.country_code, m2.level_label limit 12) m)),
              jsonb_build_object('source', 'entry matrix reader', 'page', f.url, 'entry_matrix_source_id', f.id), jsonb_build_object('run_id', r.id, 'model', r.model_code),
              'pending',
              case when v_first then 'Entry matrix first run: a person approves the matrix before any row is admitted (entry.matrix_first_run_review)'
                   else 'Entry matrix page changed: the new reading replaces the admitted rows only on approval' end,
              'CF-CHG-20260915-247')
      returning id into v_item;
    else
      -- changed page, review of changes off: admitted only when every row met the confidence (the first run always went to a person)
      perform security.entry_matrix_review_apply_v1(null, 'approve', null, 'entry.matrix_first_run_review 0: changed page admitted', r.id);
    end if;
  end if;
  update pipeline.entry_matrix_runs set state = 'done', done_at = now(), leased_until = null, error = null, rows_admitted = v_in,
         rows_dropped = jsonb_array_length(v_dropped), slices = nullif(p_result->>'slices', '')::int,
         result = jsonb_build_object('dropped', v_dropped, 'edition', p_result->'edition', 'worker', p_result->'worker'),
         cost_usd = cost_usd + coalesce(p_cost, 0), review_item_id = v_item, updated_at = now()
   where id = r.id;
  return jsonb_build_object('ok', true, 'status', case when v_in = 0 then 'no_rows' when v_item is not null then 'layer4' else 'admitted' end,
                            'rows', v_in, 'dropped', jsonb_array_length(v_dropped), 'review_item_id', v_item);
end $$;
revoke all on function public.svc_entry_matrix_record(uuid, jsonb, numeric, text) from public, anon, authenticated;
grant execute on function public.svc_entry_matrix_record(uuid, jsonb, numeric, text) to service_role;

-- ---------------------------------------------------------------- 5 Layer 4: approve admits, anything else quarantines
create or replace function security.entry_matrix_review_apply_v1(p_item uuid, p_action text, p_final jsonb, p_reason text, p_run uuid default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0;
begin
  if p_item is not null then select * into r from pipeline.entry_matrix_runs where review_item_id = p_item;
  else select * into r from pipeline.entry_matrix_runs where id = p_run; end if;
  if r.id is null then raise exception 'no entry matrix run for this review item'; end if;
  if p_action = 'approve' then
    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');
    update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'replaced by run ' || r.id, updated_at = now()
     where m.provider_id = r.provider_id and m.source_id = r.source_id and m.status = 'active' and m.run_id is distinct from r.id;
    get diagnostics v_sup = row_count;
    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'excluded by the reviewer: ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed' and m.id = any(v_ex);
    get diagnostics v_off = row_count;
    update catalogue.provider_entry_matrix m set status = 'active', status_reason = null, updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_on = row_count;
  else
    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_off = row_count;
  end if;
  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup);
end $$;

create or replace function security.entry_matrix_review_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if new.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded') then
    perform security.entry_matrix_review_apply_v1(new.id, new.status, null, 'Layer 4 ' || new.status);
  end if;
  return new;
end $$;
create trigger layer4_review_items_entry_matrix after update of status on pipeline.layer4_review_items
  for each row when (old.status = 'pending' and new.status <> 'pending' and new.field_code in ('entry_matrix_first_run', 'entry_matrix_change'))
  execute function security.entry_matrix_review_trg_v1();

select pg_temp.edit_n('security.layer4_review_decide_impl(uuid,text,text,jsonb)', 'd9d8d79e7b78229eb5d49addfcada178', array[
  array[$o$    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$o$,
        $n$    elsif v_item.entity_type='provider' and v_item.field_code in ('entry_matrix_first_run','entry_matrix_change') then
      -- CF-247 Track C: approving an entry matrix run admits its rows (edit-and-approve may exclude rows); reject etc. quarantine by trigger
      v_scalar:=security.entry_matrix_review_apply_v1(v_item.id,'approve',v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$n$]], array[1]);

select pg_temp.edit_n('security.layer4_review_desk_v1_impl(text,integer)', '049688a9f32dca45f7131be17f9eee41', array[
  array[$o$      else b.entity_type='course' end,false),$o$,
        $n$      when b.field_code in ('entry_matrix_first_run','entry_matrix_change') then jsonb_typeof(b.proposed_value)='object'
      else b.entity_type='course' end,false),$n$]], array[1]);

-- ---------------------------------------------------------------- 7 AI spend line (inside the AI stop)
select pg_temp.edit_n('security.ai_spend_today_v1()', '345684f929fed2d079bd256f25116d93', array[
  array[$o$from pipeline.fee_reader_queue x, d where coalesce(x.finished_at, x.created_at) >= d.t and coalesce(x.cost_usd, 0) > 0)$o$,
        $n$from pipeline.fee_reader_queue x, d where coalesce(x.finished_at, x.created_at) >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'entry_matrix', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.entry_matrix_runs x, d where x.updated_at >= d.t and coalesce(x.cost_usd, 0) > 0)$n$],
  array[$o$('fee_ai', 'Fee reader with AI', 6))$o$, $n$('fee_ai', 'Fee reader with AI', 6), ('entry_matrix', 'Entry matrices with AI', 7))$n$]], array[1, 1]);

-- ---------------------------------------------------------------- 6 job entry-matrix-read (catalogued, inactive)
create or replace function security.entry_matrix_fire_v1() returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_att int := 0; v_ref int := 0; v_st int := 0; v_q int := 0; v_due int; v_open int; v_sent int := 0;
begin
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  v_att := security.entry_matrix_attach_v1();
  -- an entry page read longer ago than entry.matrix_refresh_days is fetched again (read again with AI only if it changed)
  update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, updated_at = now()
   where f.status = 'read' and f.read_via <> 'stored'
     and f.read_at < now() - make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int)
     and security.entry_matrix_enabled_v1(f.provider_id);
  get diagnostics v_ref = row_count;
  v_st := security.entry_matrix_use_stored_v1();
  v_q := security.entry_matrix_enqueue_v1();
  if not security.ai_use_allowed_v1('entry_matrix') then return jsonb_build_object('attached', v_att, 'refetch', v_ref, 'stored', v_st, 'queued', v_q, 'ai', 'stopped'); end if;
  select count(*) into v_due from pipeline.entry_matrix_runs r where (r.state = 'queued' or (r.state = 'leased' and r.leased_until < now()))
     and r.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3);
  v_due := v_due + (select count(*) from pipeline.entry_matrix_sources s where s.status = 'found' and security.entry_matrix_enabled_v1(s.provider_id));
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'entry_ai' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if v_due > 0 and v_open = 0 then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'entry_ai', 'limit', security.pipeline_num_v1('batch.entry_matrix', 4)::int));
    v_sent := 1;
  end if;
  return jsonb_build_object('attached', v_att, 'refetch', v_ref, 'stored', v_st, 'queued', v_q, 'due', v_due, 'sent', v_sent);
end $$;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('entry-matrix-read', 'Course pages', 37, 'Entry matrices: find and read',
  'Every 5 minutes while Entry matrices: reader on is 1 (off until the Platform Admin activates it): attaches found entry-requirements pages, takes a stored copy where one is held, otherwise has the worker read the page (direct first with robots.txt respected; Firecrawl only when the site refuses), and sends each new page version to the pinned model (Entry matrices: pinned model). Every row needs a quote that is on the page and a scale for any number; the first run per provider (and, while Entry matrices: changes to a person is 1, every changed page) goes to Layer 4, where a person admits or quarantines the rows.',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('entry-matrix-read', '4-59/5 * * * *', $$select security.entry_matrix_fire_v1()$$);
select cron.alter_job((select jobid from cron.job where jobname = 'entry-matrix-read'), active := false);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'catalogue.provider_entry_matrix', 'Layer 3', 'Track C: published entry minimums per provider/course, country, level', 'active', '{}', '20261026001000'),
 ('table', 'catalogue.course_entry_requirements', 'Layer 3', 'Track C / B1: course-level entry requirements (written by the B1 extension)', 'active', '{}', '20261026001000'),
 ('table', 'pipeline.entry_matrix_sources', 'Layer 2', 'Track C: the reader''s own entry page list and stored copies', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_matrix_use_stored_v1', 'Layer 2', 'Track C: stored copy before a fetch', 'active', '{}', '20261026001000'),
 ('function', 'public.svc_entry_matrix_fetch_next', 'Layer 2', 'Track C worker fetch lease', 'active', '{}', '20261026001000'),
 ('function', 'public.svc_entry_matrix_fetch_record', 'Layer 2', 'Track C worker fetch record (evidence)', 'active', '{}', '20261026001000'),
 ('table', 'pipeline.entry_matrix_runs', 'Layer 2', 'Track C: one AI read of one stored entry page version', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_matrix_enabled_v1', 'Layer 2', 'Track C reader gate', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_matrix_attach_v1', 'Layer 2', 'Track C: found entry pages become fact sources', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_matrix_enqueue_v1', 'Layer 2', 'Track C: new stored page versions queued once', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_matrix_fire_v1', 'Layer 2', 'Track C: job entry-matrix-read', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_level_map_v1', 'Layer 2', 'Track C: provider level label to reference study level', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_matrix_review_apply_v1', 'Layer 4', 'Track C: admit or quarantine a run''s rows', 'active', '{}', '20261026001000'),
 ('function', 'security.entry_matrix_review_trg_v1', 'Layer 4', 'Track C: non-approval decisions quarantine the run', 'active', '{}', '20261026001000'),
 ('function', 'public.svc_entry_matrix_next', 'Layer 2', 'Track C worker lease', 'active', '{}', '20261026001000'),
 ('function', 'public.svc_entry_matrix_record', 'Layer 2', 'Track C worker record', 'active', '{}', '20261026001000'),
 ('function', 'public.admin_entry_matrix_seed', 'Layer 2', 'Track C: Platform Admin seeds known entry pages', 'active', '{}', '20261026001000'),
 ('job', 'entry-matrix-read', 'Layer 2', 'Track C entry matrix reader (inactive until activated)', 'active', '{}', '20261026001000')
on conflict (kind, name) do nothing;
