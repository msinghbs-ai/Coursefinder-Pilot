-- CF-247 SS-021 part 3 (20261104320000): the live shapes the adopted lanes read, beside the work-continuity fixture database
-- (../work-continuity/run.sh steps 1-2). Shapes only: columns and functions the edited definitions call, with fixture-controlled answers
-- (schema fx). Nothing here is a live definition; the definitions this change edits are in live/ and checked against their live md5.

-- AER scheduled reading (security.aer_schedule_tick_v1)
create table if not exists pipeline.aer_schedule_runs (id bigserial primary key, ran_at timestamptz not null default now(), course_reads int, corrections int, matrix_pages int,
  layer4_waiting int, in_progress int, back_pressure boolean, used_before int, room int, refusal text, estimate_usd numeric, detail jsonb);
create table if not exists pipeline.aer_schedule_checks (item_id uuid primary key, checked_at timestamptz, outcome text);
create table if not exists pipeline.entry_matrix_sources (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, read_via text, read_at timestamptz,
  attempts int default 0, updated_at timestamptz);
create table if not exists pipeline.layer4_item_readiness (item_id uuid primary key, entity_type text, entity_id uuid, field_code text, item_created_at timestamptz,
  item_status text, readiness text not null, reasons text[] not null default '{}', route text not null default 'none', blockers jsonb not null default '[]'::jsonb);
create table if not exists pipeline.field_gap_queue_control (id int primary key, owner uuid);
create table if not exists security.roles (code text primary key, rank int, status text);
create table if not exists security.user_roles (user_id uuid, role_code text, expires_at timestamptz);
create table if not exists fx.aer_candidates (n serial, course_id uuid, provider_id uuid);
create table if not exists fx.calls (id bigserial, fn text, arg jsonb, at timestamptz default now());

create or replace function security.course_entry_cost_v1() returns numeric language sql stable as $$ select 0.01::numeric $$;
create or replace function security.entry_matrix_enabled_v1(p uuid) returns boolean language sql stable as $$ select true $$;
create or replace function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable as $$ select false $$;
create or replace function security.aer_schedule_held_v1(p int) returns table(item_id uuid, course_id uuid, provider_id uuid, country text, eligible boolean, outcome text)
language sql stable as $$ select null::uuid, null::uuid, null::uuid, null::text, false, null::text where false $$;
create or replace function security.aer_schedule_courses_v1(p_limit int, p_preview boolean default false)
returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, turn bigint)
language sql stable as $$
  select a.course_id, a.provider_id, 'AU', 'University ' || left(a.provider_id::text, 4), 1, a.n::bigint from fx.aer_candidates a
   where not exists (select 1 from pipeline.field_enrich_items f where f.course_id = a.course_id and f.field = 'entry_requirements')
   order by a.n limit p_limit $$;
create or replace function security.course_entry_read_enqueue_v1(p_course uuid, p_owner uuid, p_reason text) returns uuid language plpgsql as $$
begin
  insert into pipeline.field_enrich_items(provider_id, course_id, state, field, attempts, created_at, updated_at)
  select a.provider_id, a.course_id, 'queued', 'entry_requirements', 0, now(), now() from fx.aer_candidates a where a.course_id = p_course limit 1;
  insert into fx.calls(fn, arg) values ('entry_read', jsonb_build_object('course', p_course));
  return gen_random_uuid();
end $$;
create or replace function security.course_entry_correction_v1(p_item uuid, p_owner uuid, p_reason text) returns jsonb language sql as $$ select jsonb_build_object('job_id', gen_random_uuid()) $$;

-- fee reader (security.fee_reader_tick_v1)
create table if not exists pipeline.provider_fact_sources (id uuid primary key default gen_random_uuid(), provider_id uuid, kind text, url text, title text, rank int,
  found_via text, status text, content_hash text, evidence_id uuid, unique (provider_id, kind, url));
alter table pipeline.provider_central_search add column if not exists found jsonb;
create table if not exists pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), storage_path text);
create table if not exists pipeline.fee_reader_rows (course_id uuid, provider_id uuid, qualification text, outcome text);
alter table pipeline.fee_reader_queue add column if not exists fact_source_id uuid;
alter table pipeline.fee_reader_queue add column if not exists content_hash text;
alter table pipeline.fee_reader_queue add column if not exists created_at timestamptz default now();
do $u$ begin
  if not exists (select 1 from pg_constraint where conname = 'fx_fee_reader_queue_src') then
    alter table pipeline.fee_reader_queue add constraint fx_fee_reader_queue_src unique (fact_source_id, content_hash);
  end if;
end $u$;
create or replace function security.fee_reader_in_scope_v1(p uuid) returns boolean language sql stable as $$ select true $$;
create or replace function security.fee_reader_finding_v1(p_provider uuid, p_source uuid, p_kind text, p_key text, p_detail jsonb) returns void language sql as $$ select $$;
create or replace function security.fee_course_pages_enqueue_v1() returns int language sql as $$ select 0 $$;
create or replace function security.ai_use_allowed_v1(p text) returns boolean language sql stable as $$ select true $$;
create or replace function pipeline.svc_pilot_submit_nonce(p_fn text, p_body jsonb) returns void language sql as $$ insert into fx.calls(fn, arg) values ('worker:' || p_fn, p_body) $$;

-- course page search (security.course_link_search_tick_v1)
alter table pipeline.course_link_search add column if not exists query text;
alter table pipeline.course_link_search add column if not exists req_id bigint;
alter table pipeline.course_link_search add column if not exists sent_at timestamptz;
alter table pipeline.coverage_course_pages add column if not exists http_status int;
alter table pipeline.coverage_course_pages add column if not exists basis text;
create table if not exists pipeline.course_link_search_settings (id int primary key, enabled boolean, monthly_credit_cap numeric, send_via text);
create table if not exists pipeline.course_link_recipes (provider_id uuid, active boolean, search_domain text);
create table if not exists pipeline.provider_priority (provider_id uuid, rank int);
create or replace function public.svc_coverage_usage(p_units int, p_purpose text, p_provider uuid, p_ref text) returns void language sql as $$ select $$;
create or replace function security.course_link_pick_v1(p_provider uuid, p_urls text[]) returns text[] language sql stable as $$ select p_urls[1:1] $$;
create or replace function security.course_link_bind_v1(p_course uuid, p_provider uuid, p_url text, p_basis text) returns void language plpgsql as $$
begin
  if p_url like '%refuse%' then raise exception 'bind refused for %', p_url; end if;  -- the fixture's bind refusal
  insert into fx.calls(fn, arg) values ('bind', jsonb_build_object('course', p_course, 'url', p_url));
end $$;
create or replace function security.search_pass_advance_v1() returns void language sql as $$ select $$;
create or replace function public.svc_coverage_firecrawl() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
create or replace function security.course_held_v1(p uuid) returns boolean language sql stable as $$ select false $$;

-- Find course pages tasks (security.page_find_continuity_v1)
create table if not exists pipeline.admin_job_events (id bigserial primary key, job_id uuid, note text, at timestamptz default now());
create or replace function security.admin_job_close_v1(p_id uuid) returns void language sql as $$ insert into fx.calls(fn, arg) values ('close', jsonb_build_object('job', p_id)) $$;
create or replace function security.pipeline_list_v1(p_key text, p_default jsonb) returns text[] language sql stable as $$
  select array(select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default))) $$;
