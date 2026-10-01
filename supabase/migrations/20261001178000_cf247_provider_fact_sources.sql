-- CF-247 (Platform Admin approval 3, 1 Oct 2026 16:54 AEST "build it"; Decision 205): institution-level sources for
-- tuition, English and intakes. Course pages rarely state these (24 h before: English not stated on 750 of 752 pages
-- read, intakes on 691 of 1,017); universities publish them centrally (fee schedules, English language policies,
-- academic calendars). This migration:
--   * pipeline.provider_fact_sources: one row per document found for a provider (kind fee_schedule, english_policy or
--     intake_calendar), with the evidence once read, and what was parsed;
--   * pipeline.provider_fact_search: the search queue, seeded with the 150 Australian providers holding the most active
--     courses (three searches each), run by the coverage-sweep worker (mode "provider_facts");
--   * pipeline.provider_fee_rows: fee rows parsed from a fee schedule, each tied to a CRICOS course code on the same row;
--   * worker functions to pick searches and documents and record results.
-- Nothing is written to the catalogue here. Parsed fee rows become a proposal per provider, which a person approves
-- (next migration); a fee is then written only where the course has none, and a different fee goes to Layer 4.

create table if not exists pipeline.provider_fact_sources (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  kind text not null check (kind in ('fee_schedule','english_policy','intake_calendar')),
  url text not null,
  title text,
  rank int not null default 1,
  found_via text not null default 'search' check (found_via in ('search','manual')),
  status text not null default 'found' check (status in ('found','reading','read','parsed','no_values','failed','rejected')),
  http_status int,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  content_hash text,
  read_at timestamptz,
  parse_summary jsonb,
  attempts int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_fact_sources_key unique (provider_id, kind, url)
);
alter table pipeline.provider_fact_sources enable row level security;
create index if not exists provider_fact_sources_status_idx on pipeline.provider_fact_sources(status, kind);

create table if not exists pipeline.provider_fact_search (
  provider_id uuid not null references catalogue.providers(id),
  kind text not null check (kind in ('fee_schedule','english_policy','intake_calendar')),
  state text not null default 'queued' check (state in ('queued','sent','done','none','error')),
  query text,
  attempts int not null default 0,
  queued_at timestamptz not null default now(),
  sent_at timestamptz,
  done_at timestamptz,
  primary key (provider_id, kind)
);
alter table pipeline.provider_fact_search enable row level security;

create table if not exists pipeline.provider_fee_rows (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references pipeline.provider_fact_sources(id),
  provider_id uuid not null references catalogue.providers(id),
  course_code text not null,
  amount numeric not null check (amount > 0),
  currency_code text not null,
  basis text check (basis in ('annual','per_semester','per_trimester','total_indicative')),
  fee_year int,
  column_label text,
  row_text text,
  current boolean not null default true,
  created_at timestamptz not null default now(),
  constraint provider_fee_rows_key unique (source_id, course_code, amount, basis)
);
alter table pipeline.provider_fee_rows enable row level security;

-- Queue: the 150 Australian providers with the most active courses, three kinds each (an Australian provider site only).
insert into pipeline.provider_fact_search(provider_id, kind)
select t.provider_id, k.kind
  from (select c.provider_id from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
         where k.iso_alpha2 = 'AU' and c.lifecycle_status = 'active'
           and exists (select 1 from pipeline.course_link_recipes r where r.provider_id = c.provider_id and r.active)
         group by c.provider_id order by count(*) desc limit 150) t
 cross join (values ('fee_schedule'), ('english_policy'), ('intake_calendar')) k(kind)
on conflict (provider_id, kind) do nothing;

create or replace function public.svc_provider_facts_search_next(p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id, s.kind, r.search_domain
      from pipeline.provider_fact_search s join pipeline.course_link_recipes r on r.provider_id = s.provider_id and r.active
     where s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < 3)
     order by s.queued_at, s.provider_id limit greatest(1, least(coalesce(p_limit, 20), 60))
     for update of s skip locked),
  upd as (
    update pipeline.provider_fact_search s set state = 'sent', sent_at = now(), attempts = s.attempts + 1,
           query = case p.kind when 'fee_schedule' then 'international student tuition fees site:' || p.search_domain
                               when 'english_policy' then 'English language requirements international students site:' || p.search_domain
                               else 'academic calendar key dates intakes site:' || p.search_domain end
      from pick p where s.provider_id = p.provider_id and s.kind = p.kind
    returning s.provider_id, s.kind, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'kind', kind, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $fn$;
revoke all on function public.svc_provider_facts_search_next(int) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_search_next(int) to service_role;

-- p_results: [{url, title}] from the search, best first. Kept: pages on the provider's own site, at most 3 per kind.
create or replace function public.svc_provider_facts_search_record(p_provider_id uuid, p_kind text, p_http int, p_results jsonb, p_error text default null) returns int
language plpgsql security definer set search_path = '' as $fn$
declare v_dom text; v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select r.search_domain into v_dom from pipeline.course_link_recipes r where r.provider_id = p_provider_id;
  if p_http <> 200 then
    update pipeline.provider_fact_search set state = case when attempts >= 3 then 'error' else 'queued' end where provider_id = p_provider_id and kind = p_kind;
    return 0;
  end if;
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank)
  select p_provider_id, p_kind, x.url, left(x.title, 300), x.rk
    from (select e->>'url' url, e->>'title' title, row_number() over () rk
            from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) e
           where (e->>'url') ~* ('^https?://([a-z0-9-]+\.)*' || regexp_replace(coalesce(v_dom, '#'), '([.-])', '\\\1', 'g') || '(/|$)')) x
   where x.rk <= 3
  on conflict (provider_id, kind, url) do nothing;
  get diagnostics v_n = row_count;
  update pipeline.provider_fact_search set state = case when v_n > 0 or exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = p_provider_id and f.kind = p_kind) then 'done' else 'none' end,
         done_at = now() where provider_id = p_provider_id and kind = p_kind;
  return v_n;
end $fn$;
revoke all on function public.svc_provider_facts_search_record(uuid, text, int, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_search_record(uuid, text, int, jsonb, text) to service_role;

create or replace function public.svc_provider_facts_read_next(p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select f.id from pipeline.provider_fact_sources f
     where (f.status = 'found' or (f.status = 'reading' and f.updated_at < now() - interval '20 minutes')) and f.attempts < 3
     order by f.rank, f.created_at limit greatest(1, least(coalesce(p_limit, 10), 30))
     for update skip locked),
  upd as (update pipeline.provider_fact_sources f set status = 'reading', attempts = f.attempts + 1, updated_at = now() from pick where f.id = pick.id
          returning f.id, f.provider_id, f.kind, f.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'kind', u.kind, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'currency', (select a.currency_code from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $fn$;
revoke all on function public.svc_provider_facts_read_next(int) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_read_next(int) to service_role;

-- p_rows (fee schedules): [{course_code, amount, basis, fee_year, column_label, row_text}] parsed by the worker.
create or replace function public.svc_provider_facts_read_record(p_id uuid, p_status text, p_http int, p_storage_path text, p_sha256 text,
                                                                 p_mime text, p_rows jsonb, p_summary jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare f pipeline.provider_fact_sources%rowtype; v_src uuid; v_ev uuid; v_cur text; v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_id for update;
  if f.id is null then raise exception 'source not found'; end if;
  if p_status not in ('read','failed') then raise exception 'status must be read or failed'; end if;
  if p_status = 'failed' then
    update pipeline.provider_fact_sources set status = case when attempts >= 3 then 'failed' else 'found' end, http_status = p_http,
           parse_summary = p_summary, updated_at = now() where id = p_id;
    return jsonb_build_object('status', 'failed');
  end if;
  if p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src := security.coverage_sweep_source(f.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id = v_src and content_hash = p_sha256 and source_url = f.url limit 1;
    if v_ev is null then
      v_ev := public.svc_coursefacts_register_evidence(v_src, f.url, p_storage_path, p_sha256, coalesce(p_mime, 'text/markdown'),
                jsonb_build_object('layer', 2, 'kind', 'provider_' || f.kind, 'worker', 'coverage-sweep', 'provider_fact_source_id', f.id));
    end if;
  end if;
  select a.currency_code into v_cur from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = f.provider_id;
  -- a re-read replaces the rows parsed before (kept, marked not current, for the record)
  update pipeline.provider_fee_rows set current = false where source_id = p_id and current;
  if f.kind = 'fee_schedule' and v_cur is not null then
    insert into pipeline.provider_fee_rows(source_id, provider_id, course_code, amount, currency_code, basis, fee_year, column_label, row_text)
    select p_id, f.provider_id, upper(btrim(r->>'course_code')), (r->>'amount')::numeric, v_cur, nullif(r->>'basis', ''), nullif(r->>'fee_year', '')::int,
           left(r->>'column_label', 120), left(r->>'row_text', 500)
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
     where coalesce(r->>'course_code', '') ~ '^[0-9A-Za-z]{4,12}$' and coalesce(r->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
       and (r->>'amount')::numeric between 1000 and 200000
       and coalesce(nullif(r->>'basis', ''), 'annual') in ('annual','per_semester','per_trimester','total_indicative')
    on conflict on constraint provider_fee_rows_key do update set current = true, fee_year = excluded.fee_year, column_label = excluded.column_label, row_text = excluded.row_text;
    get diagnostics v_n = row_count;
  end if;
  update pipeline.provider_fact_sources set status = case when f.kind <> 'fee_schedule' then 'read' when v_n > 0 then 'parsed' else 'no_values' end,
         http_status = p_http, evidence_id = coalesce(v_ev, evidence_id), content_hash = coalesce(p_sha256, content_hash), read_at = now(),
         parse_summary = coalesce(p_summary, '{}'::jsonb) || jsonb_build_object('fee_rows', v_n), updated_at = now()
   where id = p_id;
  return jsonb_build_object('status', 'read', 'fee_rows', v_n, 'evidence_id', v_ev);
end $fn$;
revoke all on function public.svc_provider_facts_read_record(uuid, text, int, text, text, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_read_record(uuid, text, int, text, text, text, jsonb, jsonb) to service_role;
