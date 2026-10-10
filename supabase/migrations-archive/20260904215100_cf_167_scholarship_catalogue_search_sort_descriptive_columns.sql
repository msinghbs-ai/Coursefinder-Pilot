create or replace function public.ui_scholarships_page(p_limit integer default 50,p_offset integer default 0,p_query text default null,p_country_code text default null,p_lifecycle_status text default null,p_publication_status text default null,p_sort text default 'scholarship',p_direction text default 'asc')
returns jsonb language plpgsql stable security definer
set search_path='public','scholarship','catalogue','ref','pipeline','auth' as $$
declare v_limit int:=least(greatest(coalesce(p_limit,50),1),200);v_offset int:=greatest(coalesce(p_offset,0),0);v_sort text:=lower(coalesce(p_sort,'scholarship'));v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 if security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 return (with base as (
  select s.id,s.stable_key,s.name,s.scholarship_type,s.description,s.audience,s.award_value_text,s.award_value_type,s.award_percentage,s.award_amount,s.award_currency_code,s.academic_year,s.application_required,s.application_open_date,s.application_close_date,s.lifecycle_status,s.publication_status,s.source_url,s.created_at,s.updated_at,s.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
   (select count(*)::int from scholarship.offering_cycles oc where oc.scholarship_id=s.id) cycle_count,
   (select count(*)::int from scholarship.application_windows aw where aw.scholarship_id=s.id) window_count,
   (select count(*)::int from pipeline.evidence_artifacts e where e.entity_id=s.id)+case when s.evidence_id is not null then 1 else 0 end evidence_count,
   (select count(*)::int from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped') mapped_course_count,
   (select count(*)::int from scholarship.course_mapping_candidates mc where mc.scholarship_id=s.id and mc.status='needs_review') review_course_count,
   left(regexp_replace(coalesce(s.description,''),'\s+',' ','g'),220) description_excerpt
  from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id left join ref.countries co on co.id=p.country_id
  where (nullif(trim(coalesce(p_query,'')),'') is null or s.name ilike '%'||trim(p_query)||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%' or coalesce(s.stable_key,'') ilike '%'||trim(p_query)||'%' or coalesce(s.description,'') ilike '%'||trim(p_query)||'%' or coalesce(s.award_value_text,'') ilike '%'||trim(p_query)||'%' or coalesce(s.scholarship_type,'') ilike '%'||trim(p_query)||'%' or coalesce(s.academic_year::text,'') ilike '%'||trim(p_query)||'%')
   and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
   and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or s.lifecycle_status=trim(p_lifecycle_status))
   and (nullif(trim(coalesce(p_publication_status,'')),'') is null or s.publication_status=trim(p_publication_status))
 ), numbered as(select *,count(*) over() total_count from base), ordered as(select * from numbered order by
   case when v_sort='scholarship' and v_dir='asc' then lower(name) end asc,case when v_sort='scholarship' and v_dir='desc' then lower(name) end desc,
   case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,
   case when v_sort='award' and v_dir='asc' then coalesce(award_percentage,award_amount) end asc nulls last,case when v_sort='award' and v_dir='desc' then coalesce(award_percentage,award_amount) end desc nulls last,
   case when v_sort='year' and v_dir='asc' then academic_year end asc nulls last,case when v_sort='year' and v_dir='desc' then academic_year end desc nulls last,
   case when v_sort='close' and v_dir='asc' then application_close_date end asc nulls last,case when v_sort='close' and v_dir='desc' then application_close_date end desc nulls last,
   case when v_sort='courses' and v_dir='asc' then mapped_course_count end asc,case when v_sort='courses' and v_dir='desc' then mapped_course_count end desc,
   case when v_sort='evidence' and v_dir='asc' then evidence_count end asc,case when v_sort='evidence' and v_dir='desc' then evidence_count end desc,
   case when v_sort='updated' and v_dir='asc' then updated_at end asc,case when v_sort='updated' and v_dir='desc' then updated_at end desc,
   lower(name),id limit v_limit offset v_offset)
 select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o);
end $$;