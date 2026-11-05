-- Guards: Platform Admin mandate 5 Nov 2026 17:31 §8 and §10 case 14 (performance with many selected columns at production volume).
-- courses_page as a signed-in person over 35,700 courses: every new column is in every page, so "many selected columns" is every page. Each
-- argument set runs three times (the middle time is reported) and must stay inside the 3,000 ms budget courses_page has under load (W34).
\set ON_ERROR_STOP on
create or replace function pg_temp.page(p_args jsonb) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', md5('admin')::uuid::text, true); set local role authenticated;
  r := public.admin_read('courses_page', p_args); reset role; return r; end $$;
do $$
declare a jsonb; t timestamptz; ms numeric[]; m numeric; i int; budget numeric := 3000; r jsonb;
begin
  for a in select x from jsonb_array_elements('[
    {"limit": 50, "offset": 0, "sort": "course", "direction": "asc", "lifecycle_status": "active"},
    {"limit": 50, "offset": 0, "sort": "admitted", "direction": "desc", "lifecycle_status": "active"},
    {"limit": 50, "offset": 17000, "sort": "admitted", "direction": "asc", "lifecycle_status": "active"},
    {"limit": 50, "offset": 0, "sort": "adapter", "direction": "asc", "lifecycle_status": "active"},
    {"limit": 50, "offset": 0, "sort": "modified", "direction": "desc", "lifecycle_status": "active"},
    {"limit": 50, "offset": 0, "sort": "city", "direction": "asc", "lifecycle_status": "active"},
    {"limit": 50, "offset": 0, "sort": "provider", "direction": "asc", "lifecycle_status": "active"},
    {"limit": 200, "offset": 0, "sort": "admitted", "direction": "desc", "lifecycle_status": "active"},
    {"limit": 50, "offset": 0, "sort": "admitted", "direction": "desc", "country_code": "AU", "subdivision_code": "AU-VIC"}]'::jsonb) x loop
    ms := '{}';
    for i in 1 .. 3 loop t := clock_timestamp(); r := pg_temp.page(a); ms := ms || round(extract(epoch from clock_timestamp() - t) * 1000, 1); end loop;
    select x into m from unnest(ms) x order by x offset 1 limit 1;
    if m > budget then raise exception 'FAIL benchmark %: % ms is over the % ms budget', a, m, budget; end if;
    raise notice 'PASS benchmark sort % %, limit %, offset %: % ms (runs % ms), total %', a ->> 'sort', a ->> 'direction', a ->> 'limit', a ->> 'offset', m, ms, r ->> 'total';
  end loop;
end $$;
