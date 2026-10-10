CREATE OR REPLACE FUNCTION public.website_v2_reference()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'ref', 'catalogue', 'scholarship', 'security', 'api'
AS $function$
  select jsonb_build_object(
    'contract_version','website-search-v2',
    'countries', (select jsonb_agg(jsonb_build_object(
        'country_code', c.country_code, 'courses', c.n,
        'study_levels', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', (select sl.name from ref.study_levels sl where sl.code=x.code limit 1), 'courses', x.n) order by x.n desc)
                         from (select study_level_code code, count(*) n from search.course_documents where country_code=c.country_code and study_level_code is not null group by 1) x),
        'study_areas', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'courses', x.n) order by x.n desc)
                        from (select primary_field_code code, min(primary_field_name) name, count(*) n from search.course_documents where country_code=c.country_code and primary_field_code is not null group by 1) x),
        'subdivisions', (select jsonb_agg(jsonb_build_object('code', x.code, 'courses', x.n) order by x.code)
                         from (select s code, count(*) n from search.course_documents d, unnest(d.subdivision_codes) s where d.country_code=c.country_code group by 1) x),
        'cities', (select jsonb_agg(jsonb_build_object('city', x.city, 'metro_area', x.metro, 'courses', x.n) order by x.n desc)
                   from (select security.place_presentable(k.city) city, min(rc.metro_area) metro, count(distinct cc.course_id) n
                         from search.course_documents d join catalogue.course_campuses cc on cc.course_id=d.course_id join catalogue.campuses k on k.id=cc.campus_id
                         left join pipeline.campus_regional_class rc on rc.campus_id=k.id
                         where d.country_code=c.country_code and nullif(btrim(k.city),'') is not null group by 1 having count(distinct cc.course_id) >= 5) x),
        'intake_months', (select jsonb_agg(jsonb_build_object('month', x.m, 'courses', x.n) order by x.m)
                          from (select api.website_v2_label_month(i->>'label') m, count(distinct d.course_id) n from search.course_documents d, jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i
                                where d.country_code=c.country_code and api.website_v2_label_month(i->>'label') is not null group by 1) x),
        'english_tests', (select jsonb_agg(jsonb_build_object('code', x.code, 'courses', x.n) order by x.n desc)
                          from (select upper(e->>'test_code') code, count(distinct d.course_id) n from search.course_documents d, jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e
                                where d.country_code=c.country_code and e->>'test_code' is not null group by 1) x)
      ) order by c.n desc) from (select country_code, count(*) n from search.course_documents group by 1) c),
    'regional_categories', jsonb_build_array(jsonb_build_object('code',1,'name','Major city'), jsonb_build_object('code',2,'name','City or major regional centre'), jsonb_build_object('code',3,'name','Regional centre or other regional area')),
    'university_groups', (select jsonb_agg(jsonb_build_object('code', replace(gic.code,'au_',''), 'name', gic.name,
                           'members', (select count(*) from catalogue.provider_collection_memberships gm where gm.collection_id=gic.id and gm.status='active')))
                          from ref.institution_collections gic where gic.collection_type='university_group' and gic.status='active'),
    'ranking_systems', (select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.ranking_name, 'publisher', s.publisher_name,
                         'editions', (select jsonb_agg(e.edition_year order by e.edition_year desc) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
                         'terms_status', 'management_decision_pending')) from ranking.systems s where exists (select 1 from ranking.editions e where e.system_id=s.id and e.status='accepted')),
    'scholarship_amount_types', jsonb_build_array('percentage_tuition','fixed_amount','full_tuition'),
    'scholarship_study_stages', jsonb_build_array('commencing','current'),
    'scholarship_student_types', jsonb_build_array('international','domestic','both'),
    'course_sorts', jsonb_build_array('relevance','title_asc','tuition_annual_asc','tuition_annual_desc','duration_asc','updated_asc'),
    'provider_sorts', jsonb_build_array('name_asc','qs_rank_asc','the_rank_asc','course_count_desc'),
    'generated_at', now())
$function$
