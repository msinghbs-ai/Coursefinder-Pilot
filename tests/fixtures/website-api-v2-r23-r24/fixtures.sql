-- After the migration: every case checked; a failed check raises and stops run.sh.
do $t$
declare v jsonb; b jsonb; a jsonb; x jsonb; kk text; st text; exp text; i int;
begin
  -- R23: one item per campus, never merged by city
  v := api.website_v2_provider_campuses(fx.i('P1'));
  if jsonb_array_length(v) <> 3 then raise exception 'R23: P1 must return 3 campuses, got %: %', jsonb_array_length(v), v; end if;
  if (select array_agg(e->>'campus_id' order by o) from jsonb_array_elements(v) with ordinality t(e, o))
     <> array['campus:fx:p1:city-campus','campus:fx:p1:grafton-campus','campus:fx:p1:newmarket'] then
    raise exception 'R23: order or identity wrong: %', v; end if;
  -- counts: City = c1 (two delivery-mode rows, counted once), c2, c8 (block released); not c3 (not returned), c4 (Layer 4 search block),
  -- c5 (another provider's course). Grafton = c1 (c6 is withdrawn). Newmarket = 0.
  if (select array_agg((e->>'course_count')::int order by o) from jsonb_array_elements(v) with ordinality t(e, o)) <> array[3,1,0] then
    raise exception 'R23: course_count wrong: %', v; end if;
  if exists (select 1 from jsonb_array_elements(v) e where jsonb_typeof(e->'course_count') <> 'number') then raise exception 'R23: course_count is not a number'; end if;
  -- names: the stored name; a blank name is null (not held), never invented from the city
  if v->0->>'campus_name' <> 'City Campus' or v->1->>'campus_name' <> 'Grafton Campus' or v->2->'campus_name' <> 'null'::jsonb then
    raise exception 'R23: campus_name wrong: %', v; end if;
  if v::text like '%campus:fx:p1:online%' or v::text like '%campus:fx:p1:closed%' then raise exception 'R23: a campus without a city or an inactive campus is returned'; end if;
  if exists (select 1 from jsonb_array_elements(v) e where not (e ?& array['city','postcode','subdivision_code','metro_area','regional_category','regional_category_name','campus_id','campus_name','course_count'])
             or (select count(*) from jsonb_object_keys(e)) <> 9) then
    raise exception 'R23: an item does not have exactly the six existing keys and the three new ones'; end if;
  -- every provider: with the three new keys taken away, the distinct items are exactly the items returned before
  for kk in select unnest(array['P1','P2','P3','P4']) loop
    b := (select j from fx.before where kind = 'campus' and fx.before.k = kk);
    x := api.website_v2_provider_campuses(fx.i(kk));
    if (select coalesce(jsonb_agg(distinct e - 'campus_id' - 'campus_name' - 'course_count'), '[]'::jsonb) from jsonb_array_elements(x) e)
       is distinct from (select coalesce(jsonb_agg(distinct e), '[]'::jsonb) from jsonb_array_elements(b) e) then
      raise exception 'R23: % existing campus values changed: before %, after %', kk, b, x; end if;
  end loop;
  if api.website_v2_provider_campuses(fx.i('P2')) <> '[]'::jsonb then raise exception 'R23: a provider without campuses must return []'; end if;
  if (api.website_v2_provider_campuses(fx.i('P3'))->0->>'course_count')::int <> 1 then raise exception 'R23: P3 count wrong'; end if;
  -- the Published switch: a provider switched off has its courses held back, so its campus counts none
  if (api.website_v2_provider_campuses(fx.i('P4'))->0->>'course_count')::int <> 0 then raise exception 'R23: a hidden provider''s course is counted'; end if;
  raise notice 'ok R23 builder: P1 3 items (was 1), counts 3/1/0, blank name null, no-city and inactive excluded, Layer 4 block, release, withdrawn, other provider and Published-off handled; existing values unchanged for 4 providers';

  -- R24: nationality_eligibility_status, every other field byte-identical
  for kk, exp in select * from (values ('S1','restricted'),('S2','restricted'),('S3','unknown'),('S4','unrestricted'),('S5','under_review'),
      ('S6','restricted'),('S7','restricted'),('S8','under_review'),('S9','unknown'),('S10','unknown'),('S11','restricted'),('S12','unknown'),
      ('S13','under_review')) e(a, b) loop
    x := api.website_v2_scholarship_item(fx.i(kk));
    st := x->>'nationality_eligibility_status';
    if st is distinct from exp then raise exception 'R24: % expected %, got %', kk, exp, st; end if;
    b := (select j from fx.before where kind = 'item' and fx.before.k = kk);
    if (x - 'nationality_eligibility_status')::text <> b::text then raise exception 'R24: % other fields changed: before %, after %', kk, b, x; end if;
  end loop;
  if api.website_v2_scholarship_item(fx.i('S14')) is not null then raise exception 'R24: an unpublished scholarship is built'; end if;
  if api.website_v2_scholarship_item(fx.i('S2'))->'citizenship_eligibility' <> '["R-SASIA"]'::jsonb then raise exception 'R24: region code changed'; end if;
  if api.website_v2_scholarship_item(fx.i('S11'))->'citizenship_eligibility' <> '[]'::jsonb then raise exception 'R24: S11 list changed'; end if;
  raise notice 'ok R24 builder: 13 cases (country, region, domestic-only, criteria-only, explicit any, open Layer 4 and AI review, unrelated or closed review, withdrawn criterion) and every other field byte-identical';
end $t$;

-- end to end through the consumer wrappers, as service_role (the edge function's role)
set role service_role;
do $e$
declare b jsonb; a jsonb; i int; kk text;
begin
  -- providers: every key except campuses byte-identical; campuses as for the builder; same providers in the same order; the Published
  -- switch still decides which providers are returned
  for kk in select unnest(array['all','auckland']) loop
    b := (select j from fx.before where kind = 'providers' and k = kk);
    a := case kk when 'all' then public.website_v2_providers('{}'::jsonb, 1, 50, null) else public.website_v2_providers('{"cities":["Auckland"]}'::jsonb, 1, 50, 'course_count_desc') end;
    if (a - 'items')::text <> (b - 'items')::text then raise exception 'providers %: envelope changed', kk; end if;
    if jsonb_array_length(a->'items') <> jsonb_array_length(b->'items') then raise exception 'providers %: item count changed', kk; end if;
    for i in 0 .. jsonb_array_length(a->'items') - 1 loop
      if ((a->'items'->i) - 'campuses')::text <> ((b->'items'->i) - 'campuses')::text then raise exception 'providers %: item % changed outside campuses', kk, i; end if;
      if (select coalesce(jsonb_agg(distinct e - 'campus_id' - 'campus_name' - 'course_count'), '[]'::jsonb) from jsonb_array_elements(a->'items'->i->'campuses') e)
         is distinct from (select coalesce(jsonb_agg(distinct e), '[]'::jsonb) from jsonb_array_elements(b->'items'->i->'campuses') e) then
        raise exception 'providers %: item % existing campus values changed', kk, i; end if;
      if exists (select 1 from jsonb_array_elements(a->'items'->i->'campuses') e where (e->>'course_count')::int > (a->'items'->i->>'course_count')::int) then
        raise exception 'providers %: a campus counts more courses than its provider', kk; end if;
    end loop;
  end loop;
  a := public.website_v2_providers('{}'::jsonb, 1, 50, null);
  if a::text like '%provider:fx:hidden%' then raise exception 'providers: a provider with the Published switch off is returned'; end if;
  if jsonb_array_length((select e->'campuses' from jsonb_array_elements(a->'items') e where e->>'provider_id' = 'provider:nzqa:7001')) <> 3 then
    raise exception 'providers: P1 must carry 3 campuses'; end if;
  -- scholarships list and detail: every key except the new one byte-identical; filter results unchanged; not-found unchanged
  for kk in select unnest(array['all','nat']) loop
    b := (select j from fx.before where kind = 'scholarships' and k = kk);
    a := case kk when 'all' then public.website_v2_scholarships('{}'::jsonb, 1, 50) else public.website_v2_scholarships('{"nationality_codes":["VN","R-SASIA","CN"]}'::jsonb, 1, 50) end;
    if (a - 'items')::text <> (b - 'items')::text then raise exception 'scholarships %: envelope changed', kk; end if;
    if (select jsonb_agg(e - 'nationality_eligibility_status' order by o) from jsonb_array_elements(a->'items') with ordinality t(e, o))::text
       <> (b->'items')::text then raise exception 'scholarships %: an item changed outside nationality_eligibility_status', kk; end if;
    if exists (select 1 from jsonb_array_elements(a->'items') e where not e ? 'nationality_eligibility_status') then raise exception 'scholarships %: status missing', kk; end if;
  end loop;
  for kk in select unnest(array['S1','S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S12','S13','S14']) loop
    b := (select j from fx.before where kind = 'detail' and k = kk);
    a := public.website_v2_scholarship('scholarship:fx:'||lower(kk));
    if b ? 'error' then
      if a::text <> b::text then raise exception 'detail %: not-found reply changed', kk; end if;
    elsif (a #- '{item,nationality_eligibility_status}')::text <> b::text or not (a->'item') ? 'nationality_eligibility_status' then
      raise exception 'detail %: changed outside nationality_eligibility_status', kk; end if;
  end loop;
  if public.website_v2_scholarship('scholarship:fx:s12')->'error'->>'code' <> 'NOT_FOUND' then raise exception 'a hidden provider''s scholarship is returned'; end if;
  -- the builders stay closed to service_role, as on live
  begin perform api.website_v2_provider_campuses(fx.i('P1')); raise exception 'service_role can run api.website_v2_provider_campuses';
  exception when insufficient_privilege then null; end;
  begin perform api.website_v2_scholarship_item(fx.i('S1')); raise exception 'service_role can run api.website_v2_scholarship_item';
  exception when insufficient_privilege then null; end;
  raise notice 'ok end to end as service_role: providers (2 requests) and scholarships (2 lists, 14 details) byte-identical apart from the additions; Published switch and not-found unchanged; builders not executable by service_role';
end $e$;
reset role;
