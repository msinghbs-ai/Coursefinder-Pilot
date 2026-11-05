-- Guards: Platform Admin mandate 5 Nov 2026 17:31 §10 case 15 (backward compatibility with the existing Course Catalogue) and case 11 (search,
-- filters and paging): courses_page before and after the migration for 13 argument sets the screen sends. Same rows, same order, every existing
-- field equal, same total; the new fields are added only.
\set ON_ERROR_STOP on
create or replace function pg_temp.page(p_args jsonb) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', md5('admin')::uuid::text, true); set local role authenticated;
  r := public.admin_read('courses_page', p_args); reset role; return r; end $$;
create table if not exists public.ccol_baseline (n int primary key, args jsonb not null, result jsonb);
select :'phase' = 'before' as before \gset
\if :before
insert into public.ccol_baseline(n, args) values
 (1, '{"limit": 50, "offset": 0, "sort": "course", "direction": "asc", "lifecycle_status": "active"}'),
 (2, '{"limit": 50, "offset": 50, "sort": "course", "direction": "asc", "lifecycle_status": "active"}'),
 (3, '{"limit": 50, "offset": 0, "sort": "provider", "direction": "desc", "lifecycle_status": "active"}'),
 (4, '{"limit": 50, "offset": 100, "sort": "city", "direction": "asc", "lifecycle_status": "active"}'),
 (5, '{"limit": 50, "offset": 0, "sort": "course", "direction": "asc", "query": "Kestrel"}'),
 (6, ('{"limit": 50, "offset": 0, "sort": "course", "direction": "asc", "provider_id": "' || md5('pk')::uuid || '"}')::jsonb),
 (7, '{"limit": 50, "offset": 0}'),
 (8, '{"limit": 50, "offset": 0, "sort": "modified", "direction": "desc", "lifecycle_status": "active"}'),
 (9, '{"limit": 50, "offset": 0, "sort": "verified", "direction": "asc", "lifecycle_status": "active"}'),
 (10, '{"limit": 50, "offset": 0, "sort": "fee", "direction": "asc"}'),
 (11, '{"limit": 50, "offset": 0, "sort": "course", "direction": "asc", "has_fee": "true", "level_code": "lvl2", "country_code": "AU", "lifecycle_status": "active"}'),
 (12, '{"limit": 50, "offset": 0, "sort": "intl_fee", "direction": "desc", "country_code": "NZ"}'),
 (13, '{"limit": 50, "offset": 0, "sort": "field", "direction": "asc", "query": "100001A"}');
update public.ccol_baseline set result = pg_temp.page(args);
\else
do $$
declare b record; a jsonb; n_new text[] := array['last_modified_at', 'last_admitted_at', 'last_admitted', 'duration_unit', 'cities', 'adapter', 'page', 'field_states', 'layer4_open', 'enrichment'];
  bad int; begin
  for b in select * from public.ccol_baseline order by n loop
    a := pg_temp.page(b.args);
    if a ->> 'total' is distinct from b.result ->> 'total' then raise exception 'FAIL set %: total % became %', b.n, b.result ->> 'total', a ->> 'total'; end if;
    if jsonb_array_length(a -> 'items') <> jsonb_array_length(b.result -> 'items') then raise exception 'FAIL set %: page length changed', b.n; end if;
    select count(*) into bad from jsonb_array_elements(b.result -> 'items') with ordinality x(e, o)
      join jsonb_array_elements(a -> 'items') with ordinality y(e, o) using (o) where (y.e - n_new) <> x.e;
    if bad > 0 then raise exception 'FAIL set %: % rows differ from before (order or an existing field)', b.n, bad; end if;
    if (a - 'items' - 'columns_profile') <> (b.result - 'items') then raise exception 'FAIL set %: page metadata changed', b.n; end if;
    if jsonb_array_length(a -> 'items') > 0 and not (a -> 'items' -> 0 ?& n_new) then raise exception 'FAIL set %: new fields missing', b.n; end if;
    raise notice 'PASS compatibility set % (%): % rows, total %, same order and fields, new fields added', b.n, b.args ->> 'sort', jsonb_array_length(a -> 'items'), a ->> 'total';
  end loop;
end $$;
\endif
