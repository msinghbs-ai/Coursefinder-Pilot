-- CF-247 s711: API v3 read path, PR D of the API v3 data admission plan (S2-Build; Platform Admin 18 Nov 2026 17:55 and 21:58; admin
-- docs/platform/API-V3-DATA-ADMISSION-PLAN-2026-11-17.md section 3: "website_v3_* provider and course payloads read is_primary / primary_basis,
-- accreditations[], study_load and empty_reason_code").
--
-- What was read live (19 Nov 2026 03:50 AEDT): Pilot #1257 already serves study_load, empty_reason_code, campuses[].locality and
-- provider.accreditations on every v3 course item, and accreditations on the v3 provider item. v3 course campuses carry is_primary but not
-- why; v3 provider campuses carry neither. 356 campuses are primary, all on basis cricos_head_office (PR A). The v3 destination careers carry
-- no employment count, although the JSA OSCA rows hold one (1,577 rows, "Employment in main job").
--
-- What it changes (v3 only: open to additions until the website goes live on it, Decision 277; v2 and the frozen consumer API untouched)
--   * security.course_v3_fields_v1: each v3 course campus marked primary carries primary_basis (from catalogue.campuses: the provider's primary
--     campus with the same postcode and city).
--   * public.website_v3_provider_item: each v3 provider campus carries is_primary and primary_basis.
--   * security.destination_read_v1: each v3 destination career row carries employment_count.
-- All three are md5-guarded single edits. Nothing is dropped or deleted. G3 untouched (75 functions, 48 tables).
-- Replaces: nothing (additions only).
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

-- 1. v3 course campuses: why a campus is primary
select pg_temp.cf_edit('security.course_v3_fields_v1(jsonb,uuid)'::regprocedure, 'c9f20991af5606d99280a737bee4c9c7',
  $o$case when v_cc is not null and nullif(btrim(coalesce(k->>'postcode', '')), '') is not null then security.destination_locality_for_postcode_v1(v_cc, k->>'postcode') end)$o$,
  $n$case when v_cc is not null and nullif(btrim(coalesce(k->>'postcode', '')), '') is not null then security.destination_locality_for_postcode_v1(v_cc, k->>'postcode') end,
                  -- 20261119042000 (PR D): why the campus is primary (the provider's primary campus at this postcode and city)
                  'primary_basis', case when coalesce((k->>'is_primary')::boolean, false) then
                    (select c.primary_basis from catalogue.campuses c where c.provider_id = v_provider and c.is_primary
                        and c.postcode is not distinct from nullif(btrim(coalesce(k->>'postcode', '')), '')
                        and lower(btrim(coalesce(c.city, ''))) = lower(btrim(coalesce(k->>'city', ''))) order by c.id limit 1) end)$n$,
  '20261119042000 (PR D): why the campus is primary');

-- 2. v3 provider campuses: is_primary and primary_basis
select pg_temp.cf_edit('public.website_v3_provider_item(jsonb)'::regprocedure, '9fa6d618d17b0d182495efc050943f79',
  $o$'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0),$o$,
  $n$'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0),
           'is_primary', coalesce(k.is_primary, false), 'primary_basis', k.primary_basis,  -- 20261119042000 (PR D)$n$,
  '20261119042000 (PR D)');
-- the campus CTE of website_v3_provider_item reads the two columns
do $c$
declare v_sig constant regprocedure := 'public.website_v3_provider_item(jsonb)'::regprocedure; v_src text; v_def text;
  v_old constant text := 'select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id, k.country_id';
  v_new constant text := 'select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id, k.country_id, k.is_primary, k.primary_basis';
begin
  v_src := (select prosrc from pg_proc where oid = v_sig);
  if position(v_new in v_src) > 0 then return; end if;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then raise exception 'website_v3_provider_item: campus select not found once'; end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  execute replace(v_def, v_old, v_new);
  if md5((select prosrc from pg_proc where oid = v_sig)) <> md5(replace(v_src, v_old, v_new)) then raise exception 'website_v3_provider_item after the edit is not the expected body'; end if;
end $c$;

-- 3. v3 destination careers: the employment count
select pg_temp.cf_edit('security.destination_read_v1(jsonb,integer,integer)'::regprocedure, '40b256e6aed77969fac06c2b15249626',
  $o$'employment_rate_pct', q.employment_rate_pct, 'reference_period'$o$,
  $n$'employment_rate_pct', q.employment_rate_pct, 'employment_count', q.employment_count, 'reference_period'$n$,
  $m$'employment_count', q.employment_count$m$);

-- post-checks: the fields are served; the consumer API is unchanged
do $$
declare v jsonb; v_c jsonb;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v := security.destination_read_v1('{"country":"AU"}'::jsonb, 1, 1);
  if not ((v->'career_outcomes'->0) ? 'employment_count') then raise exception 'post-check: employment_count on v3 careers (%)', left(v::text, 300); end if;
  if (select count(*) from catalogue.campuses where is_primary) > 0 and position('primary_basis' in (select prosrc from pg_proc where oid = 'public.website_v3_provider_item(jsonb)'::regprocedure)) = 0 then
    raise exception 'post-check: provider campuses carry primary_basis';
  end if;
  v_c := security.consumer_api_check_v1();
  v_c := case when jsonb_typeof(v_c) = 'array' then v_c else coalesce(v_c->'drift', '[]'::jsonb) end;
  if jsonb_array_length(v_c) > 0 then raise exception 'post-check: consumer API drift %', v_c; end if;
end $$;
