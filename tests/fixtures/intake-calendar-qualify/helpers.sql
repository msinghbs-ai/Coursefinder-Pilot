-- Guards: F-INT.01/SRC-01 (9 Nov 2026): the helpers shared by the calendar qualification cases and the performance proof (fixture builders only; nothing here is part of a migration)
\set ON_ERROR_STOP on

create or replace function public.cq_assert(p_name text, p_ok boolean, p_detail text default null) returns void language plpgsql as $f$
begin
  if p_ok is not true then raise exception 'FAIL % %', p_name, coalesce(p_detail, ''); end if;
  raise notice 'PASS %', p_name;
end $f$;

-- the year of the Federation-like positive case: the real 2027 dates until 31 Jan 2027, the next year's afterwards (the route takes starts within intake_dates.max_months_ahead)
create or replace function public.cq_y() returns int language sql stable as $f$
  select greatest(2027, extract(year from current_date)::int + case when current_date > make_date(extract(year from current_date)::int, 1, 31) then 1 else 0 end) $f$;

create table if not exists public.cq_cases (name text primary key, provider_id uuid not null, proposal_id uuid not null, expect text not null);

create or replace function public.cq_provider(p_key text, p_name text, p_site text) returns uuid language plpgsql as $f$
declare v uuid := gen_random_uuid(); c uuid := (select id from ref.countries order by id limit 1);
begin
  insert into pim.entity_registry(id) values (v);
  insert into catalogue.providers(id, stable_key, canonical_name, display_name, website, country_id, lifecycle_status, publication_status) values (v, 'provider:fixture:' || p_key, p_name, p_name, p_site, c, 'active', 'published');
  return v;
end $f$;

-- a stored page (evidence) and the fact source that points at it
create or replace function public.cq_source(p_prov uuid, p_url text, p_title text default null, p_age_days int default 2) returns uuid language plpgsql as $f$
declare e uuid := gen_random_uuid(); s uuid;
begin
  insert into pipeline.evidence_artifacts(id, evidence_type, source_url, content_hash, captured_at) values (e, 'page', p_url, md5(p_url), now() - make_interval(days => p_age_days));
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status, attempts, evidence_id, content_hash, read_at)
  values (p_prov, 'intake_calendar', p_url, p_title, 1, 'search', 'parsed', 1, e, md5(p_url), now() - make_interval(days => p_age_days)) returning id into s;
  return s;
end $f$;

-- periods: [{"p":"semester 1","d":"2027-03-01","q":"<quote>"}]; v21 = calendar-v2.1 shape (a `starts` array), otherwise the earlier shape (months and quotes only)
create or replace function public.cq_periods(p_spec jsonb, p_v21 boolean default false) returns jsonb language sql stable as $f$
  select jsonb_build_object('scope', 'main_teaching', 'periods', coalesce(jsonb_agg(
    jsonb_build_object('period', s->>'p', 'months', jsonb_build_array(extract(month from (s->>'d')::date)::int), 'years', jsonb_build_array(extract(year from (s->>'d')::date)::int), 'quotes', jsonb_build_array(q.q))
    || case when p_v21 then jsonb_build_object('starts', jsonb_build_array(jsonb_build_object('year', extract(year from (s->>'d')::date)::int, 'month', extract(month from (s->>'d')::date)::int,
              'day', extract(day from (s->>'d')::date)::int, 'date', s->>'d', 'quote', q.q, 'meaning', 'teaching_start')), 'deadlines', '[]'::jsonb) else '{}'::jsonb end), '[]'::jsonb))
    from jsonb_array_elements(p_spec) s, lateral (select coalesce(s->>'q', (s->>'p') || ' | ' || to_char((s->>'d')::date, 'FMDD FMMonth YYYY')) q) q $f$;

create or replace function public.cq_proposal(p_prov uuid, p_src uuid, p_parser text, p_periods jsonb, p_status text default 'proposed', p_style text default null) returns uuid language plpgsql as $f$
declare v uuid; u text := (select url from pipeline.provider_fact_sources where id = p_src);
begin
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status, decided_at)
  values (p_prov, p_src, 'intake_calendar', p_parser, md5(u || clock_timestamp()::text), (select evidence_id from pipeline.provider_fact_sources where id = p_src), u, p_style, p_periods, p_status,
          case when p_status in ('approved', 'rejected') then now() end) returning id into v;
  return v;
end $f$;

create or replace function public.cq_case(p_name text, p_prov uuid, p_prop uuid, p_expect text) returns void language sql as $f$
  insert into public.cq_cases values (p_name, p_prov, p_prop, p_expect) $f$;

create or replace function public.cq_set(p_key text, p_val numeric) returns void language sql as $f$
  update pipeline.platform_toolset_settings set value = to_jsonb(p_val) where toolset_key = 'pipeline' and key = p_key $f$;
