-- CF-247 consumer API update (see 20260929160000): checksum-guarded patches of the live consumer functions, with
-- consumer snapshots before and after in the same transaction.
do $patch$
declare v text; v_before jsonb; v_after jsonb;
begin
  v_before:=security.consumer_api_snapshot_v1();

  -- 1. website course search
  if (select md5(prosrc) from pg_proc where oid='public.website_edge_course_search_v1(jsonb,int,int)'::regprocedure)<>'2ba07114c90a83926c038dac50fed2af' then
    raise exception 'website_edge_course_search_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.website_edge_course_search_v1(jsonb,int,int)'::regprocedure);
  if position('select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id' in v)=0
     or position('(v_cities is null or lower(btrim(k.city)) = any(v_cities))' in v)=0
     or position($o$'provider',jsonb_build_object('provider_id',p.provider_stable_key,'name',p.provider_name)$o$ in v)=0
     or position($o$'campus_city',(select k.city from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id$o$ in v)=0
     or position($o$left join ref.subdivisions s on s.id=k.subdivision_id$o$ in v)=0
     or position($o$jsonb_build_object('city',k.city,'postcode',k.postcode,'subdivision_code',s.code,'is_primary',coalesce(cc.is_primary,false))$o$ in v)=0
     or position($o$jsonb_build_object('test_code',e->>'test_code','test_name',e->>'test_name','min_overall_score',e->'overall_score')$o$ in v)=0
     or position($o$'entry_requirements',jsonb_build_object('summary',null)$o$ in v)=0
     or position($o$      'campuses',coalesce($o$ in v)=0 then
    raise exception 'search anchors not found'; end if;
  -- city filter matches the locality or the metro area
  v:=replace(v,'select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id',
               'select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id = k.id');
  v:=replace(v,'(v_cities is null or lower(btrim(k.city)) = any(v_cities))','(v_cities is null or lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))');
  -- matching campus first (locality or metro area)
  v:=replace(v,'(v_cities is not null and lower(btrim(k.city)) = any(v_cities))','(v_cities is not null and (lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities)))');
  v:=replace(v,$o$'campus_city',(select k.city from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id$o$,
               $n$'campus_city',(select k.city from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id=k.id$n$);
  v:=replace(v,$o$left join ref.subdivisions s on s.id=k.subdivision_id$o$,$n$left join ref.subdivisions s on s.id=k.subdivision_id left join pipeline.campus_regional_class rc on rc.campus_id=k.id$n$);
  v:=replace(v,$o$jsonb_build_object('city',k.city,'postcode',k.postcode,'subdivision_code',s.code,'is_primary',coalesce(cc.is_primary,false))$o$,
               $n$jsonb_build_object('city',k.city,'postcode',k.postcode,'subdivision_code',s.code,'is_primary',coalesce(cc.is_primary,false),'metro_area',rc.metro_area,'regional_category',rc.category,'regional_category_name',rc.category_name)$n$);
  v:=replace(v,$o$      'campuses',coalesce($o$,
               $n$      'campus_metro_area',(select rc.metro_area from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id=k.id
                     where cc.course_id=p.course_id and nullif(btrim(k.city),'') is not null
                     order by (v_cities is not null and (lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))) desc, (v_postcodes is not null and btrim(k.postcode) = any(v_postcodes)) desc, cc.is_primary desc nulls last, k.city limit 1),
      'campuses',coalesce($n$);
  -- presentable provider name; registered name kept
  v:=replace(v,$o$'provider',jsonb_build_object('provider_id',p.provider_stable_key,'name',p.provider_name)$o$,
               $n$'provider',jsonb_build_object('provider_id',p.provider_stable_key,'name',security.provider_presentable_name(p.provider_name),'legal_name',p.provider_name)$n$);
  -- English: minimum band and a plain summary
  v:=replace(v,$o$jsonb_build_object('test_code',e->>'test_code','test_name',e->>'test_name','min_overall_score',e->'overall_score')$o$,
               $n$jsonb_build_object('test_code',e->>'test_code','test_name',e->>'test_name','min_overall_score',e->'overall_score','min_band_score',(select min(z.v::numeric) from jsonb_each_text(case when jsonb_typeof(e->'component_scores')='object' then e->'component_scores' else '{}'::jsonb end) z(k2,v) where z.v ~ '^[0-9]+(\.[0-9]+)?$'))$n$);
  v:=replace(v,$o$'entry_requirements',jsonb_build_object('summary',null)$o$,
               $n$'entry_requirements',jsonb_build_object('summary',(select 'English: '||string_agg(
                   case e->>'test_code' when 'IELTS' then 'IELTS '||to_char((e->>'overall_score')::numeric,'FM90.0')
                          ||coalesce(' (no band below '||to_char((select min(z.v::numeric) from jsonb_each_text(case when jsonb_typeof(e->'component_scores')='object' then e->'component_scores' else '{}'::jsonb end) z(k2,v) where z.v ~ '^[0-9]+(\.[0-9]+)?$'),'FM90.0')||')','')
                        when 'PTE' then 'PTE Academic '||trim(to_char((e->>'overall_score')::numeric,'FM999'))
                        when 'TOEFL_IBT' then 'TOEFL iBT '||trim(to_char((e->>'overall_score')::numeric,'FM999'))
                        else coalesce(e->>'test_name',e->>'test_code')||' '||(e->>'overall_score') end, ', '
                   order by case e->>'test_code' when 'IELTS' then 1 when 'PTE' then 2 when 'TOEFL_IBT' then 3 else 4 end)
                 from jsonb_array_elements(coalesce(p.english_requirement_options,'[]'::jsonb)) e where (e->>'overall_score') ~ '^[0-9]+(\.[0-9]+)?$'),
                 'basis',case when jsonb_array_length(coalesce(p.english_requirement_options,'[]'::jsonb))>0 then 'english_only' end)$n$);
  execute v;

  -- 2. scholarship search: presentable provider name
  if (select md5(prosrc) from pg_proc where oid='public.website_edge_scholarship_search_v1(jsonb,int,int)'::regprocedure)<>'6d7c9a760474e5e6efe556e2d5ab9fd1' then
    raise exception 'website_edge_scholarship_search_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.website_edge_scholarship_search_v1(jsonb,int,int)'::regprocedure);
  if (length(v)-length(replace(v,$o$coalesce(nullif(pr.display_name,''), pr.canonical_name) provider_name$o$,'')))/length($o$coalesce(nullif(pr.display_name,''), pr.canonical_name) provider_name$o$)<>1 then
    raise exception 'scholarship provider-name anchor not found exactly once'; end if;
  execute replace(v,$o$coalesce(nullif(pr.display_name,''), pr.canonical_name) provider_name$o$,
                    $n$security.provider_presentable_name(coalesce(nullif(pr.display_name,''), pr.canonical_name)) provider_name$n$);

  -- 3. reference bundle: provider display_name presentable (name stays the registered name)
  if (select md5(prosrc) from pg_proc where oid='security.zoho_reference_bundle_live_v1()'::regprocedure)<>'23cc58d705d320b7203022530005153d' then
    raise exception 'zoho_reference_bundle_live_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.zoho_reference_bundle_live_v1()'::regprocedure);
  if (length(v)-length(replace(v,$o$'display_name', p.display_name,$o$,'')))/length($o$'display_name', p.display_name,$o$)<>1 then
    raise exception 'bundle display_name anchor not found exactly once'; end if;
  execute replace(v,$o$'display_name', p.display_name,$o$,$n$'display_name', security.provider_presentable_name(p.display_name),$n$);
  perform security.refresh_reference_bundle_cache_v1();

  v_after:=security.consumer_api_snapshot_v1();
  insert into pipeline.consumer_api_baselines(label,snapshot) values
    ('before consumer API update for the website developer (names, regional class, English summary)',v_before),
    ('after consumer API update for the website developer (names, regional class, English summary)',v_after);
end $patch$;
