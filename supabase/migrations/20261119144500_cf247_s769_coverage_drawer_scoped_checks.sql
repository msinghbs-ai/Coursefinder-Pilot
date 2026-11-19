-- CF-247 s769, part 2: the Scholarships › Coverage provider drawer and its actions read the publishing checks for that provider only
-- (Platform Admin 19 Nov 2026 13:04 AEDT, chat S1-Build; ref 8XEY7B).
-- Found in the live check of v2.16.51 (19 Nov 2026 14:10 AEDT): with the list fixed (20261119130000), opening The University of Sydney
-- took 8.7 s and the drawer did not open. public.admin_scholarship_coverage_provider reads security.scholarship_publishability_v1(), which
-- works out the publishing checks for every scholarship (2,800+; 7.5 to 13.8 s under load) and then keeps one provider's. The same
-- full read sits in admin_scholarship_coverage_write's Publish action. security.scholarship_publishability_for_v1(p_ids) already gives the
-- same checks for chosen scholarships, ranking editions within their providers exactly as the full read does: for Sydney's 274
-- records the rows are identical (0 differences, read only) in 0.6 s.
-- Each function is changed by one fragment only, applied to its live definition after an md5 check, so nothing else in it is retyped.
-- Replaces: the all-scholarship publishing read in the Coverage drawer and the Publish action.
-- Retires: nothing.
-- No table, column, index or job. G1: no job. G2: no setting. G3: untouched (neither function is consumer API; signatures and grants unchanged).

do $$
declare v_def text; v_old text; v_new text;
begin
  -- the drawer: one provider's scholarships only
  v_def := pg_get_functiondef('public.admin_scholarship_coverage_provider(uuid)'::regprocedure);
  if md5(v_def) <> 'f985f7798729801cf172b70641947ee7' then
    raise exception 'pre-check: public.admin_scholarship_coverage_provider changed since it was read (19 Nov 2026 14:12)';
  end if;
  v_old := 'pub as (select * from security.scholarship_publishability_v1() x where x.scholarship_id in (select s.id from scholarship.scholarships s where s.provider_id = p_provider_id)),';
  v_new := 'pub as (select * from security.scholarship_publishability_for_v1(array(select s.id from scholarship.scholarships s where s.provider_id = p_provider_id))),';
  if array_length(string_to_array(v_def, v_old), 1) <> 2 then raise exception 'pre-check: the drawer fragment is not there exactly once'; end if;
  execute replace(v_def, v_old, v_new);

  -- Publish: the one scholarship's checks only
  v_def := pg_get_functiondef('public.admin_scholarship_coverage_write(text,jsonb)'::regprocedure);
  if md5(v_def) <> 'f11d5963a6518b917871a75f53d15738' then
    raise exception 'pre-check: public.admin_scholarship_coverage_write changed since it was read (19 Nov 2026 14:12)';
  end if;
  v_old := 'if not coalesce((select x.publishable from security.scholarship_publishability_v1() x where x.scholarship_id = v_sid), false) then';
  v_new := 'if not coalesce((select x.publishable from security.scholarship_publishability_for_v1(array[v_sid]) x where x.scholarship_id = v_sid), false) then';
  if array_length(string_to_array(v_def, v_old), 1) <> 2 then raise exception 'pre-check: the Publish fragment is not there exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $$;

-- post-checks
do $$
declare v_t timestamptz; v_ms numeric; v_d int; v_pid uuid := '68022bdf-43e8-44b3-ac14-e9eed9f71e83';  -- The University of Sydney (274 records)
begin
  if position('scholarship_publishability_v1()' in (select prosrc from pg_proc where oid = 'public.admin_scholarship_coverage_provider(uuid)'::regprocedure)) > 0
     or position('scholarship_publishability_v1()' in (select prosrc from pg_proc where oid = 'public.admin_scholarship_coverage_write(text,jsonb)'::regprocedure)) > 0 then
    raise exception 'post-check: a Coverage function still reads every scholarship''s publishing checks';
  end if;
  if position('scholarship_publishability_for_v1(array(select s.id from scholarship.scholarships s where s.provider_id = p_provider_id))' in
              (select prosrc from pg_proc where oid = 'public.admin_scholarship_coverage_provider(uuid)'::regprocedure)) = 0
     or position('scholarship_publishability_for_v1(array[v_sid])' in (select prosrc from pg_proc where oid = 'public.admin_scholarship_coverage_write(text,jsonb)'::regprocedure)) = 0 then
    raise exception 'post-check: the scoped publishing read is not in place';
  end if;
  -- the scoped read gives the provider's rows exactly as the full read did
  select count(*) into v_d from (
    (select * from security.scholarship_publishability_for_v1(array(select s.id from scholarship.scholarships s where s.provider_id = v_pid))
     except all select * from security.scholarship_publishability_v1() x where x.scholarship_id in (select s.id from scholarship.scholarships s where s.provider_id = v_pid))
    union all
    (select * from security.scholarship_publishability_v1() x where x.scholarship_id in (select s.id from scholarship.scholarships s where s.provider_id = v_pid)
     except all select * from security.scholarship_publishability_for_v1(array(select s.id from scholarship.scholarships s where s.provider_id = v_pid)))) z;
  if v_d <> 0 then raise exception 'post-check: the scoped publishing read differs from the full read on % rows', v_d; end if;
  v_t := clock_timestamp();
  perform security.scholarship_publishability_for_v1(array(select s.id from scholarship.scholarships s where s.provider_id = v_pid));
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  raise notice 's769 part 2: Sydney publishing checks in % ms', round(v_ms);
  if v_ms > 4000 then raise exception 'post-check: the scoped publishing read took % ms', round(v_ms); end if;  -- fixed: post-check bound
end $$;
