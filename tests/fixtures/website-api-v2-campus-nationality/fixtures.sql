-- After the migration: every case checked; a failed check raises and stops run.sh.
do $t$
declare v jsonb; b jsonb; x jsonb; kk text; st text; exp text;
begin
  -- C1: one item per campus, never merged by city
  v := api.website_v2_provider_campuses(fx.i('P1'));
  if jsonb_array_length(v) <> 3 then raise exception 'C1: P1 must return 3 campuses (A, B, C), got %: %', jsonb_array_length(v), v; end if;
  if (select array_agg(e->>'campus_id' order by o) from jsonb_array_elements(v) with ordinality t(e, o))
     <> array['campus:fx:p1:city-campus','campus:fx:p1:grafton-campus','campus:fx:p1:newmarket'] then
    raise exception 'C1: order or identity wrong: %', v; end if;
  -- counts: A = c1, c2 (c1 linked twice counts once; c3 not returned; c4 held back; c5 another provider's); B = c1 (c6 not active); C = 0
  if (select array_agg((e->>'course_count')::int order by o) from jsonb_array_elements(v) with ordinality t(e, o)) <> array[2,1,0] then
    raise exception 'C1: course_count wrong: %', v; end if;
  -- names: stored name; a blank name is null, never invented from the city
  if v->0->>'campus_name' <> 'City Campus' or v->1->>'campus_name' <> 'Grafton Campus' or v->2->'campus_name' <> 'null'::jsonb then
    raise exception 'C1: campus_name wrong: %', v; end if;
  -- excluded as before: no city, inactive
  if v::text like '%campus:fx:p1:online%' or v::text like '%campus:fx:p1:closed%' then raise exception 'C1: a campus without a city or an inactive campus is returned'; end if;
  -- compatibility: every item keeps the six existing keys with the same values; with the three new keys taken away, the distinct items are
  -- exactly the items returned before
  if exists (select 1 from jsonb_array_elements(v) e where not (e ?& array['city','postcode','subdivision_code','metro_area','regional_category','regional_category_name','campus_id','campus_name','course_count'])) then
    raise exception 'C1: a key is missing'; end if;
  for kk in select unnest(array['P1','P2','P3']) loop
    b := (select j from fx.before where kind = 'campus' and fx.before.k = kk);
    x := api.website_v2_provider_campuses(fx.i(kk));
    if (select coalesce(jsonb_agg(distinct e - 'campus_id' - 'campus_name' - 'course_count'), '[]'::jsonb) from jsonb_array_elements(x) e)
       is distinct from (select coalesce(jsonb_agg(distinct e), '[]'::jsonb) from jsonb_array_elements(b) e) then
      raise exception 'C1: % existing campus values changed: before %, after %', kk, b, x; end if;
  end loop;
  if api.website_v2_provider_campuses(fx.i('P2')) <> '[]'::jsonb then raise exception 'C1: a provider without campuses must return []'; end if;
  if (api.website_v2_provider_campuses(fx.i('P3'))->0->>'course_count')::int <> 1 then raise exception 'C1: P3 count wrong'; end if;
  raise notice 'ok C1 campuses: 3 items for P1 (was %), counts 2/1/0, blank name null, no-city and inactive excluded as before, existing values unchanged for 3 providers',
    jsonb_array_length((select j from fx.before where k = 'P1'));

  -- N1: nationality_eligibility_status
  for kk, exp in select * from (values ('S1','restricted'),('S2','restricted'),('S3','unknown'),('S4','unrestricted'),('S5','under_review'),
                                      ('S6','restricted'),('S7','restricted'),('S8','under_review'),('S9','unknown'),('S10','unknown')) e(a, b) loop
    x := api.website_v2_scholarship_item(fx.i(kk));
    st := x->>'nationality_eligibility_status';
    if st is distinct from exp then raise exception 'N1: % expected %, got %', kk, exp, st; end if;
    b := (select j from fx.before where kind = 'scholarship' and fx.before.k = kk);
    if (x - 'nationality_eligibility_status') <> b then raise exception 'N1: % other fields changed: before %, after %', kk, b, x; end if;
  end loop;
  -- region kept as a region, never expanded into countries
  if api.website_v2_scholarship_item(fx.i('S2'))->'citizenship_eligibility' <> '["R-SASIA"]'::jsonb then raise exception 'N1: region code changed'; end if;
  -- an empty list is never unrestricted
  if api.website_v2_scholarship_item(fx.i('S3'))->'citizenship_eligibility' <> '[]'::jsonb then raise exception 'N1: S3 list changed'; end if;
  raise notice 'ok N1 nationality: restricted (country, region, domestic-only, criteria list), unrestricted only with explicit evidence, empty list unknown, open review under_review, unrelated or closed review ignored; every other field identical for 10 scholarships';
end $t$;
