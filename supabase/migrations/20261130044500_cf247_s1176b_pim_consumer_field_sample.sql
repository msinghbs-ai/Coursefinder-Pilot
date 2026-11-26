-- CF-247 s1176b (S1-RM-Design; DR-16, SS-Programme-Control 26 Nov 2026 22:51 AEDT, Priority 1: "Implement bounded rotating samples through existing
-- Website and Zoho consumer reads. Verify actual academic entry requirements and course descriptions against canonical values, including
-- international audience applicability ... Report sample size, total applicable population, sampling coverage, verification age and failures
-- separately. Never extrapolate sample verification to the entire population").
--
-- Why a sample: the consumer course reads cost about 1.5 s a course (measured 26 Nov), so 10,062 entry courses and 16,116 described courses cannot
-- be read back in the background count. The website and Zoho sync copies carry no academic entry and no course description (s1176 finding), so the
-- check goes through the reads the consumers actually call.
--
-- What it adds (read-only towards the catalogue and the consumer API; no job, worker, queue or schedule):
--   pipeline.pim_consumer_samples  one row per stream (aer, cdesc) and course: the last check and its outcome.
--   security.pim_consumer_sample_v1(per_stream)  checks the courses not checked for longest (never-checked first), per_stream of each stream,
--     through the existing consumer reads, and records for each read:
--       returned (the read answered with an item), populated (the field has content), matches (every canonical value is in what the read returns),
--       and for academic entry, intl_ok (no domestic-only canonical row is in what the read returns).
--     Reads: public.website_v2_course(key) and public.zoho_v2_course(key) (what the website and Zoho read today: actual delivery), and for academic
--     entry public.website_v3_course(key, country) as an international student (international applicability). The student country is the country
--     most common in the provider's active entry-matrix rows, else across all active matrix rows (read from the data; recorded with the check).
--     Canonical values: academic entry = active course_entry_requirements rows with audience international or all (descriptions compared as
--     normalised text; rows without a description are counted, not compared); domestic-only = audience domestic rows whose text is not part of
--     any international or all row's text. Course description = catalogue.courses.description, normalised.
--     delivery_verified: the website and Zoho reads both returned the item and matched. intl_verified (entry only): the v3 international read
--     returned the international rows and no domestic-only row. Where v3 resolves the course other than by its own rows (a provider matrix, or
--     contact the provider), its match is not compared and the resolution is recorded.
--   security.pim_consumer_fields_v1()  the report: per stream, the applicable population, sampled courses (ever and in the long window), sampling
--     coverage of the population, verification age, counts per read and outcome, failures by reason and the latest failures. It never
--     extrapolates: the sample figures are counts of checked courses only.
--   security.data_delivery_refresh_v1: the sample runs in the existing background count, on a run where neither the PIM progress nor the
--     s1176 jobs read is due, at most every pim.consumer_sample_minutes.
--   security.pim_operations_v1: one key added, consumer_fields (all other keys unchanged).
-- Table: pipeline.pim_consumer_samples. G1: no job. G2: pim.consumer_sample_courses, pim.consumer_sample_minutes, pim.consumer_sample_failures_listed;
-- existing data_delivery.net_long_hours. G3: consumer functions are only called, never changed; 75/48 asserted before and after. Manual locks
-- and cron asserted. AI and spend untouched ($0). Nothing dropped.
-- Replaces: security.pim_operations_v1 (s1176; one key added); security.data_delivery_refresh_v1 (s1176; one block added).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the seeding check reads consumer functions

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
  if md5(pg_get_functiondef('security.pim_operations_v1()'::regprocedure)) <> '8d0a882be7bcbf1bfa1f43aa78a0b091' then raise exception 'guard: security.pim_operations_v1 is not the s1176 definition'; end if;
  if md5(pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) <> '70641d061b1e9671844c98159b090fab' then raise exception 'guard: security.data_delivery_refresh_v1 is not the s1176 definition'; end if;
end $g$;
create temp table s1176b_before on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs, (select count(*) from cron.job) jobs_all;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pim.consumer_sample_courses', 'PIM consumer check: courses read back per stream in one sample run',
  'How many courses of each stream (academic entry, course description) one background sample run reads back through the website and Zoho reads. Each course costs about 1.5 s per read.',
  'number', '2'::jsonb, 1, 20, 'courses', 1610, 'PIM', 'security.pim_consumer_sample_v1 (s1176b)', 'CF-247 s1176b consumer field sample'),
 ('pipeline', 'pim.consumer_sample_minutes', 'PIM consumer check: run a sample at most every',
  'The background count runs the consumer sample on a run where neither the PIM progress nor the jobs read is due, at most this often.',
  'number', '10'::jsonb, 5, 1440, 'minutes', 1611, 'PIM', 'security.data_delivery_refresh_v1 (s1176b)', 'CF-247 s1176b consumer field sample'),
 ('pipeline', 'pim.consumer_sample_failures_listed', 'PIM consumer check: latest failures listed per stream',
  'How many of the latest failed checks the report lists for each stream, with the course and the reason.',
  'number', '10'::jsonb, 1, 100, 'checks', 1612, 'PIM', 'security.pim_consumer_fields_v1 (s1176b)', 'CF-247 s1176b consumer field sample');

create table pipeline.pim_consumer_samples (
  stream text not null check (stream in ('aer', 'cdesc')),
  course_id uuid not null,
  checked_at timestamptz not null,
  student_country text,
  took_ms integer,
  canonical jsonb,
  website jsonb,
  zoho jsonb,
  v3 jsonb,
  delivery_verified boolean,
  intl_verified boolean,
  failures text[],
  primary key (stream, course_id)
);
comment on table pipeline.pim_consumer_samples is 'PIM consumer check (s1176b): the last read-back of one course per stream (aer, cdesc) through the existing consumer reads (website_v2_course, zoho_v2_course, website_v3_course as an international student), with returned, populated, matches and international applicability per read. A rotating sample; never a population figure. Written by security.pim_consumer_sample_v1, reported by security.pim_consumer_fields_v1.';
create index pim_consumer_samples_checked_idx on pipeline.pim_consumer_samples (stream, checked_at);
revoke all on table pipeline.pim_consumer_samples from public, anon, authenticated;
grant select, insert, update on table pipeline.pim_consumer_samples to service_role;

create or replace function security.pim_norm_v1(p text)
returns text
language sql
immutable
set search_path = ''
as $f$ select nullif(lower(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))), '') $f$;
comment on function security.pim_norm_v1(text) is 'PIM consumer check (s1176b): text normalised for comparison (lower case, single spaces, trimmed; empty is null).';

create or replace function security.pim_consumer_text_v1(p_entry jsonb)
returns text
language sql
immutable
set search_path = ''
as $f$
  select security.pim_norm_v1(concat_ws(' · ', p_entry->>'requirements_note',
           (select string_agg(v #>> '{}', ' · ') from jsonb_path_query(coalesce(p_entry, '{}'::jsonb), 'strict $.**.text') v)))
$f$;
comment on function security.pim_consumer_text_v1(jsonb) is 'PIM consumer check (s1176b): every requirement text an entry object carries (requirements_note and each text field at any depth), normalised.';

create or replace function security.pim_consumer_sample_v1(p_per_stream integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_n int := coalesce(p_per_stream, security.pipeline_num_v1('pim.consumer_sample_courses', 2)::int);
  c record; v_t0 timestamptz; v_cc text; v_intl text[]; v_dom text[]; v_untexted int; v_canon text;
  w jsonb; t jsonb; rw jsonb; rt jsonb; rweb jsonb; rzoho jsonb; v_blob text; v_fail text[]; v_done int := 0; v_rule text; v_res jsonb := '[]'::jsonb;
begin
  -- academic entry
  for c in
    select co.id, co.stable_key, co.provider_id
      from catalogue.courses co join catalogue.providers p on p.id = co.provider_id
      left join pipeline.pim_consumer_samples s on s.stream = 'aer' and s.course_id = co.id
     where co.lifecycle_status = 'active' and p.publication_status = 'published'
       and not exists (select 1 from security.provider_hidden_v1 x where x.provider_id = p.id)
       and exists (select 1 from catalogue.course_entry_requirements e where e.course_id = co.id and e.status = 'active' and e.audience in ('international', 'all'))
     order by s.checked_at nulls first, md5(co.id::text || to_char(now(), 'YYYYMMDD'))
     limit v_n
  loop
    v_t0 := clock_timestamp(); v_fail := '{}';
    select coalesce(array_agg(distinct security.pim_norm_v1(e.description)) filter (where security.pim_norm_v1(e.description) is not null), '{}'),
           count(*) filter (where security.pim_norm_v1(e.description) is null)
      into v_intl, v_untexted
      from catalogue.course_entry_requirements e where e.course_id = c.id and e.status = 'active' and e.audience in ('international', 'all');
    select coalesce(array_agg(distinct security.pim_norm_v1(e.description)), '{}') into v_dom
      from catalogue.course_entry_requirements e
     where e.course_id = c.id and e.status = 'active' and e.audience = 'domestic' and security.pim_norm_v1(e.description) is not null
       and not exists (select 1 from unnest(v_intl) i where position(security.pim_norm_v1(e.description) in i) > 0);
    v_cc := coalesce(
      (select m.country_code from catalogue.provider_entry_matrix m where m.provider_id = c.provider_id and m.status = 'active' and m.country_code is not null group by 1 order by count(*) desc, 1 limit 1),
      (select m.country_code from catalogue.provider_entry_matrix m where m.status = 'active' and m.country_code is not null group by 1 order by count(*) desc, 1 limit 1));
    -- website v2 and Zoho v2: what the consumers read today
    foreach v_canon in array array['website', 'zoho'] loop
      begin
        if v_canon = 'website' then w := (public.website_v2_course(c.stable_key))::jsonb; else w := (public.zoho_v2_course(c.stable_key))::jsonb; end if;
        v_blob := security.pim_consumer_text_v1(w->'item'->'entry');
        rw := jsonb_build_object('returned', w ? 'item' and not w ? 'error', 'populated', v_blob is not null,
                'matches', cardinality(v_intl) > 0 and v_blob is not null and not exists (select 1 from unnest(v_intl) x where position(x in v_blob) = 0),
                'intl_ok', v_blob is null or not exists (select 1 from unnest(v_dom) x where position(x in v_blob) > 0),
                'error', w->'error'->>'code');
      exception when others then
        rw := jsonb_build_object('returned', false, 'populated', false, 'matches', false, 'intl_ok', null, 'error', left(sqlerrm, 200));
      end;
      if not (rw->>'returned')::boolean then v_fail := v_fail || (v_canon || '_not_returned'); end if;
      if (rw->>'returned')::boolean and not (rw->>'populated')::boolean then v_fail := v_fail || (v_canon || '_not_populated'); end if;
      if (rw->>'populated')::boolean and not (rw->>'matches')::boolean then v_fail := v_fail || (v_canon || '_not_matching'); end if;
      if (rw->>'intl_ok')::boolean is false then v_fail := v_fail || (v_canon || '_serves_domestic_only_row'); end if;
      if v_canon = 'website' then rweb := rw; else rzoho := rw; end if;
    end loop;
    -- website v3 as an international student: international applicability
    begin
      t := case when v_cc is null then null else (public.website_v3_course(c.stable_key, v_cc))::jsonb end;
      v_blob := security.pim_consumer_text_v1(t->'item'->'entry');
      v_rule := t->'item'->'entry'->'resolution'->>'rule';
      rt := jsonb_build_object('country', v_cc, 'returned', t ? 'item' and not t ? 'error', 'rule', v_rule,
              'populated', coalesce(jsonb_array_length(t->'item'->'entry'->'resolution'->'rows'), 0) > 0,
              'matches', case when v_rule = 'course_override' then cardinality(v_intl) > 0 and v_blob is not null and not exists (select 1 from unnest(v_intl) x where position(x in v_blob) = 0) end,
              'intl_ok', v_blob is null or not exists (select 1 from unnest(v_dom) x where position(x in v_blob) > 0),
              'error', coalesce(t->'error'->>'code', case when v_cc is null then 'no_student_country' end));
    exception when others then
      rt := jsonb_build_object('country', v_cc, 'returned', false, 'populated', false, 'matches', null, 'intl_ok', null, 'error', left(sqlerrm, 200));
    end;
    if not (rt->>'returned')::boolean then v_fail := v_fail || 'v3_international_not_returned'::text; end if;
    if (rt->>'returned')::boolean and not (rt->>'populated')::boolean then v_fail := v_fail || 'v3_international_no_rows'::text; end if;
    if (rt->>'matches')::boolean is false then v_fail := v_fail || 'v3_international_not_matching'::text; end if;
    if (rt->>'intl_ok')::boolean is false then v_fail := v_fail || 'v3_international_serves_domestic_only_row'::text; end if;
    insert into pipeline.pim_consumer_samples as s (stream, course_id, checked_at, student_country, took_ms, canonical, website, zoho, v3, delivery_verified, intl_verified, failures)
    values ('aer', c.id, clock_timestamp(), v_cc, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int,
            jsonb_build_object('international_rows', cardinality(v_intl) + v_untexted, 'compared_texts', cardinality(v_intl), 'without_text', v_untexted, 'domestic_only_texts', cardinality(v_dom)),
            rweb, rzoho, rt,
            coalesce((rweb->>'returned')::boolean and (rweb->>'matches')::boolean and (rzoho->>'returned')::boolean and (rzoho->>'matches')::boolean, false),
            coalesce((rt->>'returned')::boolean and (rt->>'populated')::boolean and coalesce((rt->>'matches')::boolean, true) and coalesce((rt->>'intl_ok')::boolean, false), false),
            nullif(v_fail, '{}'))
    on conflict (stream, course_id) do update set checked_at = excluded.checked_at, student_country = excluded.student_country, took_ms = excluded.took_ms,
      canonical = excluded.canonical, website = excluded.website, zoho = excluded.zoho, v3 = excluded.v3, delivery_verified = excluded.delivery_verified,
      intl_verified = excluded.intl_verified, failures = excluded.failures;
    v_done := v_done + 1;
    v_res := v_res || jsonb_build_object('stream', 'aer', 'course', c.stable_key, 'country', v_cc, 'v3_rule', v_rule, 'failures', to_jsonb(nullif(v_fail, '{}')));
  end loop;
  -- course description
  for c in
    select co.id, co.stable_key, security.pim_norm_v1(co.description) d
      from catalogue.courses co join catalogue.providers p on p.id = co.provider_id
      left join pipeline.pim_consumer_samples s on s.stream = 'cdesc' and s.course_id = co.id
     where co.lifecycle_status = 'active' and p.publication_status = 'published'
       and not exists (select 1 from security.provider_hidden_v1 x where x.provider_id = p.id)
       and security.pim_norm_v1(co.description) is not null
     order by s.checked_at nulls first, md5(co.id::text || to_char(now(), 'YYYYMMDD'))
     limit v_n
  loop
    v_t0 := clock_timestamp(); v_fail := '{}';
    foreach v_canon in array array['website', 'zoho'] loop
      begin
        if v_canon = 'website' then w := (public.website_v2_course(c.stable_key))::jsonb; else w := (public.zoho_v2_course(c.stable_key))::jsonb; end if;
        v_blob := security.pim_norm_v1(w->'item'->>'description');
        rw := jsonb_build_object('returned', w ? 'item' and not w ? 'error', 'has_field', coalesce(w->'item' ? 'description', false), 'populated', v_blob is not null,
                                 'matches', v_blob is not distinct from c.d, 'error', w->'error'->>'code');
      exception when others then
        rw := jsonb_build_object('returned', false, 'has_field', false, 'populated', false, 'matches', false, 'error', left(sqlerrm, 200));
      end;
      if not (rw->>'returned')::boolean then v_fail := v_fail || (v_canon || '_not_returned'); end if;
      if (rw->>'returned')::boolean and not (rw->>'populated')::boolean then v_fail := v_fail || (v_canon || '_not_populated'); end if;
      if (rw->>'populated')::boolean and not (rw->>'matches')::boolean then v_fail := v_fail || (v_canon || '_not_matching'); end if;
      if v_canon = 'website' then rweb := rw; else rzoho := rw; end if;
    end loop;
    insert into pipeline.pim_consumer_samples as s (stream, course_id, checked_at, student_country, took_ms, canonical, website, zoho, v3, delivery_verified, intl_verified, failures)
    values ('cdesc', c.id, clock_timestamp(), null, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int, jsonb_build_object('length', length(c.d)),
            rweb, rzoho, null, coalesce((rweb->>'returned')::boolean and (rweb->>'matches')::boolean and (rzoho->>'returned')::boolean and (rzoho->>'matches')::boolean, false), null, nullif(v_fail, '{}'))
    on conflict (stream, course_id) do update set checked_at = excluded.checked_at, student_country = null, took_ms = excluded.took_ms, canonical = excluded.canonical,
      website = excluded.website, zoho = excluded.zoho, v3 = null, delivery_verified = excluded.delivery_verified, intl_verified = null, failures = excluded.failures;
    v_done := v_done + 1;
    v_res := v_res || jsonb_build_object('stream', 'cdesc', 'course', c.stable_key, 'failures', to_jsonb(nullif(v_fail, '{}')));
  end loop;
  return jsonb_build_object('checked', v_done, 'results', v_res);
end $f$;
comment on function security.pim_consumer_sample_v1(integer) is 'PIM consumer check (s1176b): reads back the courses not checked for longest, per stream, through website_v2_course, zoho_v2_course and (entry) website_v3_course as an international student, and records returned, populated, matches and international applicability in pipeline.pim_consumer_samples. Read-only towards the catalogue and the consumer API.';
revoke all on function security.pim_consumer_sample_v1(integer) from public, anon, authenticated;
grant execute on function security.pim_consumer_sample_v1(integer) to service_role;

create or replace function security.pim_consumer_fields_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
  with st as materialized (select security.pipeline_num_v1('data_delivery.net_long_hours', 168)::int long_h, security.pipeline_num_v1('pim.consumer_sample_failures_listed', 10)::int k),
  pop as materialized (
    select count(*) filter (where exists (select 1 from catalogue.course_entry_requirements e where e.course_id = co.id and e.status = 'active' and e.audience in ('international', 'all'))) aer,
           count(*) filter (where security.pim_norm_v1(co.description) is not null) cdesc
      from catalogue.courses co join catalogue.providers p on p.id = co.provider_id
     where co.lifecycle_status = 'active' and p.publication_status = 'published' and not exists (select 1 from security.provider_hidden_v1 x where x.provider_id = p.id)),
  s as materialized (select x.*, x.checked_at > now() - make_interval(hours => (select long_h from st)) in_window from pipeline.pim_consumer_samples x),
  by_stream as (
    select k.stream,
      jsonb_build_object(
        'population', case k.stream when 'aer' then (select aer from pop) else (select cdesc from pop) end,
        'population_meaning', case k.stream when 'aer' then 'active courses at published providers with at least one active entry row for an international or all audience'
                                            else 'active courses at published providers with a course description' end,
        'sampled_ever', (select count(*) from s where s.stream = k.stream),
        'sampled_in_window', (select count(*) from s where s.stream = k.stream and s.in_window),
        'window_hours', (select long_h from st),
        'coverage_in_window', round((select count(*) from s where s.stream = k.stream and s.in_window)::numeric
                                    / nullif(case k.stream when 'aer' then (select aer from pop) else (select cdesc from pop) end, 0), 4),
        'last_checked', (select max(checked_at) from s where s.stream = k.stream),
        'oldest_check_in_window', (select min(checked_at) from s where s.stream = k.stream and s.in_window),
        'avg_seconds_per_course', (select round(avg(took_ms) / 1000.0, 1) from s where s.stream = k.stream and s.in_window),
        'checked', jsonb_build_object(
          'website', jsonb_build_object('returned', (select count(*) from s where s.stream = k.stream and s.in_window and (s.website->>'returned')::boolean),
                                        'populated', (select count(*) from s where s.stream = k.stream and s.in_window and (s.website->>'populated')::boolean),
                                        'matches', (select count(*) from s where s.stream = k.stream and s.in_window and (s.website->>'matches')::boolean),
                                        'intl_ok', (select count(*) from s where s.stream = k.stream and s.in_window and (s.website->>'intl_ok')::boolean)),
          'zoho', jsonb_build_object('returned', (select count(*) from s where s.stream = k.stream and s.in_window and (s.zoho->>'returned')::boolean),
                                     'populated', (select count(*) from s where s.stream = k.stream and s.in_window and (s.zoho->>'populated')::boolean),
                                     'matches', (select count(*) from s where s.stream = k.stream and s.in_window and (s.zoho->>'matches')::boolean),
                                     'intl_ok', (select count(*) from s where s.stream = k.stream and s.in_window and (s.zoho->>'intl_ok')::boolean)),
          'website_v3_international', case when k.stream = 'aer' then jsonb_build_object(
                                     'returned', (select count(*) from s where s.stream = k.stream and s.in_window and (s.v3->>'returned')::boolean),
                                     'populated', (select count(*) from s where s.stream = k.stream and s.in_window and (s.v3->>'populated')::boolean),
                                     'matches', (select count(*) from s where s.stream = k.stream and s.in_window and (s.v3->>'matches')::boolean),
                                     'not_compared_other_resolution', (select count(*) from s where s.stream = k.stream and s.in_window and (s.v3->>'returned')::boolean and s.v3->'matches' = 'null'::jsonb),
                                     'intl_ok', (select count(*) from s where s.stream = k.stream and s.in_window and (s.v3->>'intl_ok')::boolean)) end),
        'delivery_verified', (select count(*) from s where s.stream = k.stream and s.in_window and s.delivery_verified),
        'international_verified', case when k.stream = 'aer' then (select count(*) from s where s.stream = k.stream and s.in_window and s.intl_verified) end,
        'with_failure', (select count(*) from s where s.stream = k.stream and s.in_window and s.failures is not null),
        'failures_by_reason', coalesce((select jsonb_object_agg(f, n) from (select f, count(*) n from s, unnest(s.failures) f where s.stream = k.stream and s.in_window group by f) y), '{}'::jsonb),
        'latest_failures', coalesce((select jsonb_agg(jsonb_build_object('course', co.stable_key, 'checked_at', x.checked_at, 'country', x.student_country, 'failures', to_jsonb(x.failures)) order by x.checked_at desc)
                                       from (select * from s where s.stream = k.stream and s.in_window and s.failures is not null order by s.checked_at desc limit (select k from st)) x
                                       join catalogue.courses co on co.id = x.course_id), '[]'::jsonb)) v
      from (values ('aer'), ('cdesc')) k(stream))
  select jsonb_build_object(
    'streams', (select jsonb_object_agg(stream, v) from by_stream),
    'meaning', 'A rotating sample read back through the reads the consumers call (website_v2_course and zoho_v2_course: actual delivery; website_v3_course as an international student: international applicability). Every figure counts checked courses only and is never a population figure; coverage_in_window is sampled courses in the window divided by the population. matches: every canonical value is in what the read returns. intl_ok: no domestic-only entry row is in it. delivery_verified: the website and Zoho reads both returned and matched.')
$f$;
comment on function security.pim_consumer_fields_v1() is 'PIM consumer check (s1176b): per stream, population, sampled courses, sampling coverage, verification age, outcome counts per consumer read, failures by reason and the latest failures; never extrapolated.';
revoke all on function security.pim_consumer_fields_v1() from public, anon, authenticated;
grant execute on function security.pim_consumer_fields_v1() to service_role;

-- the background count runs the sample on a run where neither the PIM progress nor the jobs read is due
do $r$
declare d text := pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure);
        a constant text := $a$  -- PIM monitoring (s1176): the jobs read$a$;
        b constant text := $b$  -- PIM consumer check (s1176b): a rotating read-back sample, on a run where neither the PIM progress nor the jobs read is due
  if p_force or (exists (select 1 from pipeline.data_delivery_job_runs j where j.singleton and coalesce(j.pim_failed_at, j.pim_measured_at) >= now() - make_interval(mins => v_every))
                 and exists (select 1 from pipeline.pim_jobs_snapshot x where x.singleton and coalesce(x.failed_at, x.measured_at) >= now() - make_interval(mins => v_every))
                 and not exists (select 1 from pipeline.pim_consumer_samples x where x.checked_at >= now() - make_interval(mins => security.pipeline_num_v1('pim.consumer_sample_minutes', 10)::int))) then
    begin
      perform security.pim_consumer_sample_v1(null);
    exception when others then
      raise warning 'PIM consumer sample failed: %', left(sqlerrm, 300);
    end;
  end if;
  -- PIM monitoring (s1176): the jobs read$b$;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: jobs read anchor not found exactly once'; end if;
  execute replace(d, a, b);
end $r$;

-- pim.operations gains consumer_fields (every other key unchanged)
do $o$
declare d text := pg_get_functiondef('security.pim_operations_v1()'::regprocedure);
        a constant text := $a$    'consumer', coalesce((select jsonb_agg($a$;
        b constant text := $b$    'consumer_fields', security.pim_consumer_fields_v1(),
    'consumer', coalesce((select jsonb_agg($b$;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: consumer anchor not found exactly once'; end if;
  execute replace(d, a, b);
end $o$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); b record; o jsonb; r jsonb;
begin
  select * into b from s1176b_before;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < b.locks then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs or (select count(*) from cron.job) <> b.jobs_all then raise exception 'guard: the scheduler changed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron above 140'; end if;  -- fixed: protected ceiling
  if position('perform security.pim_consumer_sample_v1(null);' in pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) = 0 then raise exception 'guard: the sample is not in the background count'; end if;
  if position('pim_consumer' in pg_get_functiondef('security.data_delivery_v1()'::regprocedure)) > 0 then raise exception 'guard: the screen read runs the sample'; end if;
  r := security.pim_consumer_sample_v1(1);  -- seed: one course per stream, so the first report is not empty
  if (select count(*) from pipeline.pim_consumer_samples) <> 2 then raise exception 'guard: seed sample not recorded: %', r; end if;
  o := security.pim_consumer_fields_v1();
  if (o->'streams'->'aer'->>'population')::int = 0 or (o->'streams'->'cdesc'->>'population')::int = 0 then raise exception 'guard: empty population'; end if;
  raise notice 'seed %, aer %, cdesc %', r, o->'streams'->'aer'->'checked', o->'streams'->'cdesc'->'checked';
end $c$;
