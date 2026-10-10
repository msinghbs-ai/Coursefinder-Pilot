-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 17:04, decided 18:04).
-- A provider attribute: the lowest and highest indicative whole-course international tuition across the provider's
-- courses, in the currency of the provider's country ("Indicative whole-course fees, where listed").
-- Decided 18:04:
--   1. The provider's current published fees come first, the official register total (CRICOS) is the fallback.
--   2. Award courses only (study levels outside the excluded list, which the Platform Admin controls).
--   3. Published per provider: a range is never shown outside the admin screens until a Platform Admin switches it on.
-- Each course's whole-course fee (first that applies):
--   a. the whole-course total printed on the course page (current fee, basis total_indicative),
--   b. the current annual fee x full-time years (per semester x 2, per trimester x 3 a year), years from the catalogue
--      duration, else the years or duration read on the course page,
--   c. the registered total course tuition (CRICOS), dated by its snapshot.
-- Left out and counted: other currencies (never converted), no course length, ambiguous lengths ("1-2 years",
-- "2 years or 4 years"), under one year when the setting leaves those out, and whole fees below the floor in the
-- settings (the register holds $1 placeholders for fee-waived research degrees). Excluded fee readings and courses not
-- open to international students are left out. Values set by hand are never overwritten. Refreshed every hour.
-- No text value in this file contains a semicolon.

create table if not exists pipeline.provider_fee_range_settings (
  id int primary key default 1 check (id = 1),
  include_under_one_year boolean not null default true,
  min_courses int not null default 5 check (min_courses between 1 and 500),
  min_fee_year int not null default 2026 check (min_fee_year between 2020 and 2100),
  min_whole_fee numeric(12,2) not null default 1000 check (min_whole_fee >= 0),
  excluded_level_codes text[] not null default array['non_aqf_award', 'vocational_short_course', 'foundation', 'primary_school_studies', 'junior_secondary_studies', 'senior_secondary_certificate'],
  updated_by uuid,
  updated_at timestamptz not null default now(),
  reason text
);
alter table pipeline.provider_fee_range_settings enable row level security;
revoke all on table pipeline.provider_fee_range_settings from anon, authenticated;
insert into pipeline.provider_fee_range_settings(id, reason) values (1, 'Decision 254 defaults (5 Oct 2026 18:04)') on conflict (id) do nothing;

create table if not exists catalogue.provider_fee_ranges (
  provider_id uuid primary key references catalogue.providers(id),
  currency_code text,
  low_amount numeric(12,2),
  high_amount numeric(12,2),
  low_course_id uuid references catalogue.courses(id),
  high_course_id uuid references catalogue.courses(id),
  low_source text,
  high_source text,
  course_count int not null default 0,
  source_counts jsonb not null default '{}'::jsonb,
  skipped jsonb not null default '{}'::jsonb,
  fee_year_from int,
  fee_year_to int,
  register_as_of date,
  meets_minimum boolean not null default false,
  computed_at timestamptz,
  manual_low numeric(12,2),
  manual_high numeric(12,2),
  manual_note text,
  manual_by uuid,
  manual_at timestamptz,
  published boolean not null default false,
  published_by uuid,
  published_at timestamptz,
  publish_reason text,
  check (manual_low is null or manual_high is null or manual_low <= manual_high),
  check (manual_low is null or manual_low > 0),
  check (manual_high is null or manual_high > 0)
);
alter table catalogue.provider_fee_ranges enable row level security;
revoke all on table catalogue.provider_fee_ranges from anon, authenticated;

-- Full-time years from a printed duration. Part-time clauses are set aside first. A range or a choice of lengths
-- gives no answer. "1 year 6 months" = 1.5, "18 months" = 1.5, "78 weeks" = 1.5, "3 semesters" = 1.5, "2" = 2.
create or replace function security.course_years_from_text(p_text text) returns numeric
language plpgsql immutable set search_path = '' as $f$
declare
  s text := lower(coalesce(p_text, ''));
  u text := '(years?|yrs?|months?|weeks?|semesters?|trimesters?)';
  m text[]; n numeric; y numeric;
begin
  if s ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then n := btrim(s)::numeric; return case when n > 0 and n <= 10 then n end; end if;
  s := regexp_replace(s, '(up to\s*)?[0-9]+(\.[0-9]+)?\s*' || u || '\s*,?\s*(of\s+)?part[ -]time', ' ', 'g');
  s := regexp_replace(s, 'up to\s*[0-9]+(\.[0-9]+)?\s*' || u, ' ', 'g');
  s := regexp_replace(s, 'part[ -]time[^0-9]{0,40}[0-9]+(\.[0-9]+)?\s*' || u, ' ', 'g');
  if s ~ '[0-9](\.[0-9]+)?\s*(–|—|-|to)\s*[0-9]' then return null; end if;
  if s ~ ('[0-9]\s*' || u || '[^0-9]{0,60}\mor\M[^0-9]{0,30}[0-9]+(\.[0-9]+)?\s*' || u) then return null; end if;
  m := regexp_match(s, '([0-9]+(?:\.[0-9]+)?)\s*' || u);
  if m is null then return null; end if;
  n := m[1]::numeric;
  y := case when m[2] ~ '^month' then n / 12 when m[2] ~ '^week' then n / 52 when m[2] ~ '^semester' then n / 2 when m[2] ~ '^trimester' then n / 3 else n end;
  if m[2] ~ '^(year|yr)' then
    m := regexp_match(s, '[0-9]+(?:\.[0-9]+)?\s*(?:years?|yrs?)\s*(?:and\s*)?([0-9]+)\s*months?');
    if m is not null then y := y + m[1]::numeric / 12; end if;
  end if;
  y := round(y, 2);
  return case when y > 0 and y <= 10 then y end;
end $f$;
revoke all on function security.course_years_from_text(text) from public, anon, authenticated;

-- Every course of a provider (or of all providers) with a qualifying fee, its whole-course fee and how it was worked
-- out. skip is null when the course counts towards the range.
create or replace function security.provider_course_whole_fees_v1(p_provider_id uuid)
returns table(provider_id uuid, course_id uuid, title text, level_code text, country_currency text, currency_code text,
              whole_fee numeric, source text, fee_amount numeric, fee_basis text, fee_year int, years numeric, years_from text,
              register_as_of date, skip text)
language sql stable security definer set search_path = '' as $f$
  with st as (select * from pipeline.provider_fee_range_settings where id = 1),
  c as (
    select co.id, co.provider_id, co.canonical_title, sl.code level_code, cn.default_currency_code ccy,
           case co.duration_unit when 'weeks' then co.duration_value / 52.0 when 'months' then co.duration_value / 12.0 when 'years' then co.duration_value
                                 when 'semesters' then co.duration_value / 2.0 when 'trimesters' then co.duration_value / 3.0 end cat_years,
           pg.candidates->'adapter_extra' ax
      from catalogue.courses co
      join catalogue.providers p on p.id = co.provider_id
      join ref.countries cn on cn.id = p.country_id
      join ref.study_levels sl on sl.id = co.study_level_id
      cross join st
      left join pipeline.coverage_course_pages pg on pg.course_id = co.id
     where (p_provider_id is null or co.provider_id = p_provider_id)
       and co.lifecycle_status = 'active' and co.open_to_international is not false
       and sl.code <> all (st.excluded_level_codes)
       and not security.uni_adapter_excluded(co.id, 'fee')),
  cur as (
    select distinct on (f.course_id) f.course_id, f.amount, f.basis, coalesce(f.fee_year, extract(year from now())::int) fy, f.currency_code
      from catalogue.course_fees f join c on c.id = f.course_id cross join st
     where f.fee_type = 'provider_current_tuition' and f.status = 'active' and f.audience in ('international', 'all') and f.amount > 0
       and coalesce(f.fee_year, extract(year from now())::int) between st.min_fee_year and extract(year from now())::int + 1
     order by f.course_id, coalesce(f.fee_year, extract(year from now())::int) desc, (f.basis = 'total_indicative') desc, f.amount desc),
  reg as (
    select distinct on (f.course_id) f.course_id, f.amount, f.currency_code, coalesce(f.source_snapshot_at::date, f.valid_from) as_of
      from catalogue.course_fees f join c on c.id = f.course_id
     where f.fee_type = 'tuition' and f.basis = 'registered_total_course' and f.status = 'active' and f.audience in ('international', 'all') and f.amount > 0
     order by f.course_id, coalesce(f.source_snapshot_at::date, f.valid_from) desc nulls last, f.amount desc),
  y as (
    select c.*, security.course_years_from_text(c.ax->>'course_years') ax_years, security.course_years_from_text(c.ax->>'duration') ax_dur from c),
  x as (
    select y.*, coalesce(round(y.cat_years, 2), y.ax_years, y.ax_dur) yrs,
           case when y.cat_years is not null then 'catalogue' when y.ax_years is not null then 'course page (years)' when y.ax_dur is not null then 'course page (duration)' end yfrom,
           cur.amount c_amt, cur.basis c_basis, cur.fy c_fy, cur.currency_code c_ccy, reg.amount r_amt, reg.currency_code r_ccy, reg.as_of r_asof
      from y left join cur on cur.course_id = y.id left join reg on reg.course_id = y.id
     where cur.course_id is not null or reg.course_id is not null),
  z as (
    select x.*,
           case when x.c_amt is not null and x.c_basis = 'total_indicative' then 'current_total'
                when x.c_amt is not null and x.yrs is not null then 'current_annual_x_years'
                when x.r_amt is not null then 'register_total' end src,
           case x.c_basis when 'per_semester' then 2 when 'per_trimester' then 3 else 1 end per_year
      from x)
  select z.provider_id, z.id, z.canonical_title, z.level_code, z.ccy,
         case z.src when 'register_total' then z.r_ccy else z.c_ccy end,
         case z.src when 'current_total' then z.c_amt when 'current_annual_x_years' then round(z.c_amt * z.per_year * z.yrs, 2) when 'register_total' then z.r_amt end,
         z.src,
         case z.src when 'register_total' then z.r_amt else z.c_amt end,
         case z.src when 'register_total' then 'registered_total_course' else z.c_basis end,
         case when z.src in ('current_total', 'current_annual_x_years') then z.c_fy end,
         z.yrs, z.yfrom,
         case when z.src = 'register_total' then z.r_asof end,
         case when z.src is null then 'no_course_length'
              when (case z.src when 'register_total' then z.r_ccy else z.c_ccy end) is distinct from z.ccy then 'other_currency'
              when not st.include_under_one_year and z.yrs is not null and z.yrs < 1 then 'under_one_year'
              when (case z.src when 'current_total' then z.c_amt when 'current_annual_x_years' then round(z.c_amt * z.per_year * z.yrs, 2) when 'register_total' then z.r_amt end) < st.min_whole_fee then 'below_floor' end
    from z cross join (select * from pipeline.provider_fee_range_settings where id = 1) st
$f$;
revoke all on function security.provider_course_whole_fees_v1(uuid) from public, anon, authenticated;

-- Works the range out again for one provider (or all). Only the worked-out columns change: values set by hand and the
-- publish switch are kept. Providers with no qualifying course keep their row with no range.
create or replace function security.provider_fee_ranges_refresh_v1(p_provider_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_n int; v_min int := (select s.min_courses from pipeline.provider_fee_range_settings s where s.id = 1);
begin
  with rws as materialized (select * from security.provider_course_whole_fees_v1(p_provider_id)),
  w as (select * from rws r where r.skip is null),
  a as (
    select w.provider_id, max(w.country_currency) ccy, count(*) n, min(w.whole_fee) lo, max(w.whole_fee) hi,
           jsonb_build_object('current_total', count(*) filter (where w.source = 'current_total'),
                              'current_annual_x_years', count(*) filter (where w.source = 'current_annual_x_years'),
                              'register_total', count(*) filter (where w.source = 'register_total')) sc,
           min(w.fee_year) fy_from, max(w.fee_year) fy_to, max(w.register_as_of) reg_asof
      from w group by w.provider_id),
  lo as (select distinct on (w.provider_id) w.provider_id, w.course_id, w.source from w order by w.provider_id, w.whole_fee asc, w.course_id),
  hi as (select distinct on (w.provider_id) w.provider_id, w.course_id, w.source from w order by w.provider_id, w.whole_fee desc, w.course_id),
  sk as (select k.provider_id, jsonb_object_agg(k.skip, k.n) j from (select r.provider_id, r.skip, count(*) n from rws r where r.skip is not null group by 1, 2) k group by k.provider_id),
  allp as (select r.provider_id from rws r group by r.provider_id
           union select f.provider_id from catalogue.provider_fee_ranges f where p_provider_id is null or f.provider_id = p_provider_id)
  insert into catalogue.provider_fee_ranges(provider_id, currency_code, low_amount, high_amount, low_course_id, high_course_id, low_source, high_source, course_count, source_counts, skipped, fee_year_from, fee_year_to, register_as_of, meets_minimum, computed_at)
  select allp.provider_id, a.ccy, a.lo, a.hi, lo.course_id, hi.course_id, lo.source, hi.source, coalesce(a.n, 0), coalesce(a.sc, '{}'::jsonb), coalesce(sk.j, '{}'::jsonb), a.fy_from, a.fy_to, a.reg_asof, coalesce(a.n, 0) >= v_min, now()
    from allp left join a on a.provider_id = allp.provider_id left join lo on lo.provider_id = allp.provider_id left join hi on hi.provider_id = allp.provider_id left join sk on sk.provider_id = allp.provider_id
  on conflict (provider_id) do update set currency_code = excluded.currency_code, low_amount = excluded.low_amount, high_amount = excluded.high_amount, low_course_id = excluded.low_course_id, high_course_id = excluded.high_course_id, low_source = excluded.low_source, high_source = excluded.high_source, course_count = excluded.course_count, source_counts = excluded.source_counts, skipped = excluded.skipped, fee_year_from = excluded.fee_year_from, fee_year_to = excluded.fee_year_to, register_as_of = excluded.register_as_of, meets_minimum = excluded.meets_minimum, computed_at = excluded.computed_at;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'providers', v_n);
end $f$;
revoke all on function security.provider_fee_ranges_refresh_v1(uuid) from public, anon, authenticated;

select cron.schedule('provider-fee-ranges-refresh', '57 * * * *', 'select security.provider_fee_ranges_refresh_v1(null)');

-- The range as shown: values set by hand first, then the worked-out range.
create or replace function security.provider_fee_range_json_v1(p_provider_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('provider_id', r.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', trim(cn.iso_alpha2::text),
           'currency', coalesce(r.currency_code, cn.default_currency_code),
           'low', coalesce(r.manual_low, r.low_amount), 'high', coalesce(r.manual_high, r.high_amount),
           'by_hand', r.manual_low is not null or r.manual_high is not null,
           'computed', jsonb_build_object('low', r.low_amount, 'high', r.high_amount, 'low_course_id', r.low_course_id, 'high_course_id', r.high_course_id,
                         'low_course', lc.canonical_title, 'high_course', hc.canonical_title, 'low_source', r.low_source, 'high_source', r.high_source,
                         'courses', r.course_count, 'sources', r.source_counts, 'skipped', r.skipped, 'fee_year_from', r.fee_year_from, 'fee_year_to', r.fee_year_to,
                         'register_as_of', r.register_as_of, 'meets_minimum', r.meets_minimum, 'computed_at', r.computed_at),
           'manual', jsonb_build_object('low', r.manual_low, 'high', r.manual_high, 'note', r.manual_note, 'at', r.manual_at),
           'published', r.published, 'published_at', r.published_at, 'publish_reason', r.publish_reason)
    from catalogue.provider_fee_ranges r join catalogue.providers p on p.id = r.provider_id join ref.countries cn on cn.id = p.country_id
    left join catalogue.courses lc on lc.id = r.low_course_id left join catalogue.courses hc on hc.id = r.high_course_id
   where r.provider_id = p_provider_id
$f$;
revoke all on function security.provider_fee_range_json_v1(uuid) from public, anon, authenticated;

create or replace function public.admin_provider_fee_range(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
  v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_res jsonb; v_r catalogue.provider_fee_ranges%rowtype;
  v_low numeric; v_high numeric; v_levels text[];
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'read' then
    if v_pid is null then
      return jsonb_build_object('settings', (select to_jsonb(s) - 'id' from pipeline.provider_fee_range_settings s where s.id = 1),
               'levels', (select jsonb_agg(jsonb_build_object('code', l.code, 'name', l.name) order by l.sort_order) from ref.study_levels l where l.status = 'active'),
               'ranges', coalesce((select jsonb_agg(security.provider_fee_range_json_v1(r.provider_id)) from catalogue.provider_fee_ranges r
                                    where p_args->>'scope' = 'all' or exists (select 1 from pipeline.uni_adapters a where a.provider_id = r.provider_id)), '[]'::jsonb));
    end if;
    return jsonb_build_object('range', security.provider_fee_range_json_v1(v_pid),
             'courses', coalesce((select jsonb_agg(to_jsonb(w) order by w.skip nulls first, w.whole_fee) from (select * from security.provider_course_whole_fees_v1(v_pid) limit 2000) w), '[]'::jsonb));
  end if;
  if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'refresh' then
    v_res := security.provider_fee_ranges_refresh_v1(v_pid);
  elsif p_action = 'publish' then
    select * into v_r from catalogue.provider_fee_ranges r where r.provider_id = v_pid;
    if v_r.provider_id is null then raise exception 'no range for this provider yet (refresh first)'; end if;
    if coalesce(v_r.manual_low, v_r.low_amount) is null or coalesce(v_r.manual_high, v_r.high_amount) is null then raise exception 'no range to publish'; end if;
    if not v_r.meets_minimum and v_r.manual_low is null and v_r.manual_high is null then raise exception 'fewer courses than the minimum in the settings: set the range by hand or lower the minimum'; end if;
    update catalogue.provider_fee_ranges set published = true, published_by = auth.uid(), published_at = now(), publish_reason = v_reason where provider_id = v_pid;
    v_res := jsonb_build_object('ok', true, 'published', true);
  elsif p_action = 'unpublish' then
    update catalogue.provider_fee_ranges set published = false, published_by = auth.uid(), published_at = now(), publish_reason = v_reason where provider_id = v_pid;
    v_res := jsonb_build_object('ok', true, 'published', false);
  elsif p_action = 'set' then
    v_low := nullif(p_args->>'low', '')::numeric; v_high := nullif(p_args->>'high', '')::numeric;
    if v_low is null or v_high is null or v_low <= 0 or v_high < v_low then raise exception 'give a lowest and a highest amount (lowest no more than highest)'; end if;
    insert into catalogue.provider_fee_ranges(provider_id) values (v_pid) on conflict (provider_id) do nothing;
    update catalogue.provider_fee_ranges set manual_low = v_low, manual_high = v_high, manual_note = nullif(btrim(coalesce(p_args->>'note', '')), ''), manual_by = auth.uid(), manual_at = now() where provider_id = v_pid;
    v_res := jsonb_build_object('ok', true);
  elsif p_action = 'release' then
    update catalogue.provider_fee_ranges set manual_low = null, manual_high = null, manual_note = null, manual_by = auth.uid(), manual_at = now() where provider_id = v_pid;
    v_res := jsonb_build_object('ok', true);
  elsif p_action = 'settings' then
    select array_agg(x) into v_levels from jsonb_array_elements_text(coalesce(p_args->'excluded_level_codes', '[]'::jsonb)) x;
    if exists (select 1 from unnest(coalesce(v_levels, '{}')) x where x not in (select l.code from ref.study_levels l)) then raise exception 'unknown study level'; end if;
    update pipeline.provider_fee_range_settings set include_under_one_year = coalesce((p_args->>'include_under_one_year')::boolean, include_under_one_year), min_courses = coalesce((p_args->>'min_courses')::int, min_courses), min_fee_year = coalesce((p_args->>'min_fee_year')::int, min_fee_year), min_whole_fee = coalesce((p_args->>'min_whole_fee')::numeric, min_whole_fee), excluded_level_codes = coalesce(v_levels, excluded_level_codes), updated_by = auth.uid(), updated_at = now(), reason = v_reason where id = 1;
    v_res := security.provider_fee_ranges_refresh_v1(null);
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('coverage', 'fee_range_' || p_action, coalesce(v_pid::text, 'all'), jsonb_build_object('result', v_res, 'args', p_args), auth.uid());
  return v_res;
end $f$;
revoke all on function public.admin_provider_fee_range(text, jsonb) from public, anon;
grant execute on function public.admin_provider_fee_range(text, jsonb) to authenticated;

select security.provider_fee_ranges_refresh_v1(null);
