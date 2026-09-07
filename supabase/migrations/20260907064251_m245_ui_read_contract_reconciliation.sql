create or replace function security.admin_scholarships_page(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','public','security','scholarship','catalogue','ref','pipeline','auth'
as $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'scholarship'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return (
    with base as (
      select s.id,s.stable_key,s.name,s.scholarship_type,s.description,s.audience,s.award_value_text,s.award_value_type,s.award_percentage,s.award_amount,s.award_currency_code,s.academic_year,s.application_required,s.application_open_date,s.application_close_date,s.lifecycle_status,s.publication_status,s.source_url,s.created_at,s.updated_at,s.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
        (select count(*)::int from scholarship.offering_cycles oc where oc.scholarship_id=s.id) cycle_count,
        (select count(*)::int from scholarship.application_windows aw where aw.scholarship_id=s.id) window_count,
        (select count(*)::int from pipeline.evidence_artifacts e where e.entity_id=s.id)+case when s.evidence_id is not null then 1 else 0 end evidence_count,
        (select count(*)::int from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped') mapped_course_count,
        (select count(*)::int from scholarship.course_mapping_candidates mc where mc.scholarship_id=s.id and mc.status='needs_review') review_course_count,
        left(regexp_replace(coalesce(s.description,''),'\s+',' ','g'),220) description_excerpt
      from scholarship.scholarships s
      left join catalogue.providers p on p.id=s.provider_id
      left join ref.countries co on co.id=p.country_id
      where (nullif(trim(coalesce(p_args->>'query','')),'') is null
          or s.name ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.description,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.award_value_text,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.scholarship_type,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.academic_year::text,'') ilike '%'||trim(p_args->>'query')||'%')
        and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code'))
        and (v_provider_id is null or s.provider_id=v_provider_id)
        and (nullif(p_args->>'lifecycle_status','') is null or s.lifecycle_status=p_args->>'lifecycle_status')
        and (nullif(p_args->>'publication_status','') is null or s.publication_status=p_args->>'publication_status')
    ), numbered as (select *,count(*) over() total_count from base), ordered as (
      select * from numbered order by
        case when v_sort='scholarship' and v_dir='asc' then lower(name) end asc,
        case when v_sort='scholarship' and v_dir='desc' then lower(name) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,
        case when v_sort='type' and v_dir='asc' then lower(coalesce(scholarship_type,'')) end asc,
        case when v_sort='type' and v_dir='desc' then lower(coalesce(scholarship_type,'')) end desc,
        case when v_sort='audience' and v_dir='asc' then lower(coalesce(audience::text,'')) end asc,
        case when v_sort='audience' and v_dir='desc' then lower(coalesce(audience::text,'')) end desc,
        case when v_sort='award' and v_dir='asc' then coalesce(award_percentage,award_amount) end asc nulls last,
        case when v_sort='award' and v_dir='desc' then coalesce(award_percentage,award_amount) end desc nulls last,
        case when v_sort='year' and v_dir='asc' then academic_year end asc nulls last,
        case when v_sort='year' and v_dir='desc' then academic_year end desc nulls last,
        case when v_sort='close' and v_dir='asc' then application_close_date end asc nulls last,
        case when v_sort='close' and v_dir='desc' then application_close_date end desc nulls last,
        case when v_sort='courses' and v_dir='asc' then mapped_course_count end asc,
        case when v_sort='courses' and v_dir='desc' then mapped_course_count end desc,
        case when v_sort='evidence' and v_dir='asc' then evidence_count end asc,
        case when v_sort='evidence' and v_dir='desc' then evidence_count end desc,
        case when v_sort='publication' and v_dir='asc' then lower(coalesce(publication_status,'')) end asc,
        case when v_sort='publication' and v_dir='desc' then lower(coalesce(publication_status,'')) end desc,
        case when v_sort='updated' and v_dir='asc' then updated_at end asc,
        case when v_sort='updated' and v_dir='desc' then updated_at end desc,
        lower(name),id limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o
  );
end
$function$;
revoke all on function security.admin_scholarships_page(jsonb) from public;

create or replace function security.admin_catalogue_page(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','public','security','catalogue','ref','scholarship','auth'
as $function$
declare
  v_rank integer:=0; v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200); v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0); v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'name')); v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end; v_result jsonb; v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid; v_has_fee boolean:=case when nullif(p_args->>'has_fee','') is null then null else (p_args->>'has_fee')::boolean end; v_has_intake boolean:=case when nullif(p_args->>'has_intake','') is null then null else (p_args->>'has_intake')::boolean end; v_has_english boolean:=case when nullif(p_args->>'has_english','') is null then null else (p_args->>'has_english')::boolean end; v_has_scholarship boolean:=case when nullif(p_args->>'has_scholarship','') is null then null else (p_args->>'has_scholarship')::boolean end; v_has_state boolean:=case when nullif(p_args->>'has_state','') is null then null else (p_args->>'has_state')::boolean end; v_has_link boolean:=case when nullif(p_args->>'has_link','') is null then null else (p_args->>'has_link')::boolean end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if; select security.current_role_rank() into v_rank; if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='providers_page' then return security.admin_providers_page(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),coalesce(nullif(p_args->>'sort',''),'provider'),v_dir);
  elsif p_operation='courses_page' then return public.ui_courses_decision_page(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),v_has_fee,v_has_intake,v_has_english,v_has_scholarship,nullif(p_args->>'min_completeness','')::numeric,nullif(p_args->>'freshness',''),coalesce(nullif(p_args->>'sort',''),'course'),v_dir,v_has_state,v_has_link);
  elsif p_operation='scholarships_page' then return security.admin_scholarships_page(p_args);
  elsif p_operation='campuses_page' then
    with base as (select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,sd.code subdivision_code,sd.name subdivision_name,ca.city,ca.status,ca.publication_status,ca.last_verified_at,ca.created_at,ca.updated_at,(select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=p.country_id left join ref.subdivisions sd on sd.id=ca.subdivision_id where (nullif(trim(coalesce(p_args->>'query','')),'') is null or ca.name ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.campus_code,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.stable_key,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.city,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%') and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code')) and (nullif(p_args->>'subdivision_code','') is null or sd.code=upper(p_args->>'subdivision_code')) and (v_provider_id is null or ca.provider_id=v_provider_id) and (nullif(p_args->>'status','') is null or ca.status=p_args->>'status') and (nullif(p_args->>'publication_status','') is null or ca.publication_status=p_args->>'publication_status')), numbered as(select *,count(*) over() total_count from base), ordered as(select * from numbered order by case when v_sort in ('name','campus') and v_dir='asc' then lower(name) end asc,case when v_sort in ('name','campus') and v_dir='desc' then lower(name) end desc,case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,case when v_sort='city' and v_dir='asc' then lower(coalesce(city,'')) end asc,case when v_sort='city' and v_dir='desc' then lower(coalesce(city,'')) end desc,case when v_sort='courses' and v_dir='asc' then course_count end asc,case when v_sort='courses' and v_dir='desc' then course_count end desc,case when v_sort='modified' and v_dir='asc' then updated_at end asc,case when v_sort='modified' and v_dir='desc' then updated_at end desc,lower(name),id limit v_limit offset v_offset) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) into v_result from ordered o; return v_result;
  else raise exception 'unsupported catalogue page operation: %',p_operation using errcode='22023'; end if;
end
$function$;

create or replace function security.admin_ranking_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','security','ranking','catalogue','ref','auth'
as $function$
declare v_rank integer:=0; v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200); v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0); v_system text:=nullif(p_args->>'system_code',''); v_year integer:=nullif(p_args->>'edition_year','')::integer; v_provider uuid:=nullif(p_args->>'provider_id','')::uuid; v_query text:=nullif(btrim(p_args->>'query'),''); v_sort text:=case when lower(coalesce(nullif(p_args->>'sort',''),'rank')) in ('institution','provider','rank','score','country','status','edition','system') then lower(coalesce(nullif(p_args->>'sort',''),'rank')) else 'rank' end; v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if; select security.current_role_rank() into v_rank; if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='ranking_summary' then return jsonb_build_object('systems',coalesce((select jsonb_agg(jsonb_build_object('code',s.code,'publisher_name',s.publisher_name,'ranking_name',s.ranking_name,'official_url',s.official_url,'latest_edition',(select max(e.edition_year) from ranking.editions e where e.system_id=s.id and e.status='accepted'),'accepted_editions',(select count(*) from ranking.editions e where e.system_id=s.id and e.status='accepted'),'observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted')),'mapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') and o.provider_id is not null),'unmapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') and o.provider_id is null),'total_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted')) order by s.code) from ranking.systems s where s.active),'[]'::jsonb),'manual_imports',case when v_rank>=4 then (select jsonb_build_object('total',count(*),'uploaded',count(*) filter(where status='uploaded'),'needs_review',count(*) filter(where status='needs_review'),'applied',count(*) filter(where status='applied')) from ranking.manual_imports) else null end);
  elsif p_operation='ranking_filters' then return jsonb_build_object('systems',coalesce((select jsonb_agg(jsonb_build_object('code',code,'label',ranking_name) order by code) from ranking.systems where active and (v_system is null or code=v_system)),'[]'::jsonb),'years',coalesce((select jsonb_agg(y order by y desc) from (select distinct e.edition_year y from ranking.editions e join ranking.systems s on s.id=e.system_id where e.status='accepted' and (v_system is null or s.code=v_system)) q),'[]'::jsonb),'editions',coalesce((select jsonb_agg(jsonb_build_object('year',q.edition_year,'observations',q.observations,'mapped_observations',q.mapped_observations) order by q.edition_year desc) from (select e.edition_year,count(o.id)::integer observations,count(o.id) filter(where o.provider_id is not null)::integer mapped_observations from ranking.editions e join ranking.systems s on s.id=e.system_id left join ranking.observations o on o.edition_id=e.id where e.status='accepted' and (v_system is null or s.code=v_system) group by e.id,e.edition_year) q),'[]'::jsonb),'statuses',jsonb_build_array('ranked_exact','ranked_band','reporter','unranked','not_eligible','unknown'));
  elsif p_operation='ranking_observations' then return (with filtered as(select o.id,s.code system_code,s.publisher_name,s.ranking_name,e.edition_year,e.methodology_version,e.methodology_url,e.source_url,pi.institution_name publisher_institution_name,pi.country_text,o.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,o.rank_display,o.rank_exact,o.rank_low,o.rank_high,o.is_tied,o.rank_status,o.overall_score,o.evidence_artifact_id from ranking.observations o join ranking.editions e on e.id=o.edition_id join ranking.systems s on s.id=e.system_id join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id left join catalogue.providers p on p.id=o.provider_id where e.status='accepted' and (v_system is null or s.code=v_system) and (v_year is null or e.edition_year=v_year) and (v_provider is null or o.provider_id=v_provider or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id and opl.provider_id=v_provider)) and (v_query is null or pi.institution_name ilike '%'||v_query||'%' or coalesce(p.display_name,p.canonical_name) ilike '%'||v_query||'%')), ordered as(select * from filtered order by case when v_sort='institution' and v_dir='asc' then lower(publisher_institution_name) end asc,case when v_sort='institution' and v_dir='desc' then lower(publisher_institution_name) end desc,case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,case when v_sort='rank' and v_dir='asc' then coalesce(rank_exact,rank_low,999999) end asc,case when v_sort='rank' and v_dir='desc' then coalesce(rank_exact,rank_low,-1) end desc,case when v_sort='score' and v_dir='asc' then overall_score end asc nulls last,case when v_sort='score' and v_dir='desc' then overall_score end desc nulls last,case when v_sort='country' and v_dir='asc' then lower(coalesce(country_text,'')) end asc,case when v_sort='country' and v_dir='desc' then lower(coalesce(country_text,'')) end desc,case when v_sort='status' and v_dir='asc' then lower(coalesce(rank_status,'')) end asc,case when v_sort='status' and v_dir='desc' then lower(coalesce(rank_status,'')) end desc,case when v_sort='edition' and v_dir='asc' then edition_year end asc,case when v_sort='edition' and v_dir='desc' then edition_year end desc,case when v_sort='system' and v_dir='asc' then system_code end asc,case when v_sort='system' and v_dir='desc' then system_code end desc,system_code,edition_year desc,coalesce(rank_exact,rank_low,999999),publisher_institution_name,id limit v_limit offset v_offset) select jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,'items',coalesce((select jsonb_agg(to_jsonb(x)) from ordered x),'[]'::jsonb)));
  elsif p_operation='ranking_imports' then if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if; return (select jsonb_build_object('total',(select count(*) from ranking.manual_imports),'limit',v_limit,'offset',v_offset,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.uploaded_at desc) from (select mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,mi.uploaded_at from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id order by mi.uploaded_at desc limit v_limit offset v_offset) x),'[]'::jsonb)));
  else raise exception 'unsupported ranking read operation: %',p_operation using errcode='22023'; end if;
end
$function$;
