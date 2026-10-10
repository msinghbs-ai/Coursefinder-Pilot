CREATE OR REPLACE FUNCTION security.admin_ranking_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'ranking', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_system text:=nullif(p_args->>'system_code','');
  v_year integer:=nullif(p_args->>'edition_year','')::integer;
  v_provider uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_query text:=nullif(btrim(p_args->>'query'),'');
  v_country text:=nullif(p_args->>'country','');
  v_state text:=nullif(p_args->>'state','');
  v_link text:=nullif(p_args->>'link','');
  v_sort text:=case when lower(coalesce(nullif(p_args->>'sort',''),'rank')) in ('institution','provider','rank','score','country','status','edition','system') then lower(coalesce(nullif(p_args->>'sort',''),'rank')) else 'rank' end;
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if p_operation='ranking_summary' then
    return jsonb_build_object('systems',coalesce((select jsonb_agg(jsonb_build_object('code',s.code,'publisher_name',s.publisher_name,'ranking_name',s.ranking_name,'official_url',s.official_url,'latest_edition',(select max(e.edition_year) from ranking.editions e where e.system_id=s.id and e.status='accepted'),'accepted_editions',(select count(*) from ranking.editions e where e.system_id=s.id and e.status='accepted'),'observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted')),'mapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') and o.provider_id is not null),'unmapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') and o.provider_id is null),'total_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted')) order by s.code) from ranking.systems s where s.active),'[]'::jsonb),'manual_imports',case when v_rank>=4 then (select jsonb_build_object('total',count(*),'uploaded',count(*) filter(where status='uploaded'),'needs_review',count(*) filter(where status='needs_review'),'applied',count(*) filter(where status='applied')) from ranking.manual_imports) else null end);
  elsif p_operation='ranking_filters' then
    return jsonb_build_object('systems',coalesce((select jsonb_agg(jsonb_build_object('code',code,'label',ranking_name) order by code) from ranking.systems where active and (v_system is null or code=v_system)),'[]'::jsonb),'years',coalesce((select jsonb_agg(y order by y desc) from (select distinct e.edition_year y from ranking.editions e join ranking.systems s on s.id=e.system_id where e.status='accepted' and (v_system is null or s.code=v_system)) q),'[]'::jsonb),'editions',coalesce((select jsonb_agg(jsonb_build_object('year',q.edition_year,'observations',q.observations,'mapped_observations',q.mapped_observations) order by q.edition_year desc) from (select e.edition_year,count(o.id)::integer observations,count(o.id) filter(where o.provider_id is not null)::integer mapped_observations from ranking.editions e join ranking.systems s on s.id=e.system_id left join ranking.observations o on o.edition_id=e.id where e.status='accepted' and (v_system is null or s.code=v_system) group by e.id,e.edition_year) q),'[]'::jsonb),'statuses',jsonb_build_array('ranked_exact','ranked_band','reporter','unranked','not_eligible','unknown'));
  elsif p_operation='ranking_observations' then
    return (
      with filtered as (
        select o.id,s.code system_code,s.publisher_name,s.ranking_name,e.edition_year,e.methodology_version,e.methodology_url,e.source_url,pi.institution_name publisher_institution_name,pi.country_text,o.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,o.rank_display,o.rank_exact,o.rank_low,o.rank_high,o.is_tied,o.rank_status,o.overall_score,o.evidence_artifact_id,o.publisher_institution_id,sd.code state_code,sd.name state_name
        from ranking.observations o
        join ranking.editions e on e.id=o.edition_id
        join ranking.systems s on s.id=e.system_id
        join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id
        left join catalogue.providers p on p.id=o.provider_id
        left join ref.subdivisions sd on sd.id=p.subdivision_id
        where e.status='accepted'
          and (v_system is null or s.code=v_system)
          and (v_year is null or e.edition_year=v_year)
          and (v_provider is null or o.provider_id=v_provider or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id and opl.provider_id=v_provider))
          and (v_query is null or pi.institution_name ilike '%'||v_query||'%' or coalesce(p.display_name,p.canonical_name) ilike '%'||v_query||'%')
          and (v_country is null or pi.country_text=v_country)
          and (v_state is null or sd.code=v_state)
          and (v_link is null or (v_link='linked' and o.provider_id is not null) or (v_link='not_linked' and o.provider_id is null))
      ), ordered as (
        select * from filtered order by
          case when v_sort='institution' and v_dir='asc' then lower(publisher_institution_name) end asc,
          case when v_sort='institution' and v_dir='desc' then lower(publisher_institution_name) end desc,
          case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,
          case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,
          case when v_sort='rank' and v_dir='asc' then coalesce(rank_exact,rank_low,999999) end asc,
          case when v_sort='rank' and v_dir='desc' then coalesce(rank_exact,rank_low,-1) end desc,
          case when v_sort='score' and v_dir='asc' then overall_score end asc nulls last,
          case when v_sort='score' and v_dir='desc' then overall_score end desc nulls last,
          case when v_sort='country' and v_dir='asc' then lower(coalesce(country_text,'')) end asc,
          case when v_sort='country' and v_dir='desc' then lower(coalesce(country_text,'')) end desc,
          case when v_sort='status' and v_dir='asc' then lower(coalesce(rank_status,'')) end asc,
          case when v_sort='status' and v_dir='desc' then lower(coalesce(rank_status,'')) end desc,
          case when v_sort='edition' and v_dir='asc' then edition_year end asc,
          case when v_sort='edition' and v_dir='desc' then edition_year end desc,
          case when v_sort='system' and v_dir='asc' then system_code end asc,
          case when v_sort='system' and v_dir='desc' then system_code end desc,
          system_code,edition_year desc,coalesce(rank_exact,rank_low,999999),publisher_institution_name,id
        limit v_limit offset v_offset
      )
      select jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,'items',coalesce((select jsonb_agg(to_jsonb(x)) from ordered x),'[]'::jsonb))
    );
  elsif p_operation='ranking_imports' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    return (select jsonb_build_object('total',(select count(*) from ranking.manual_imports),'limit',v_limit,'offset',v_offset,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.uploaded_at desc) from (select mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,mi.uploaded_at from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id order by mi.uploaded_at desc limit v_limit offset v_offset) x),'[]'::jsonb)));
  else
    raise exception 'unsupported ranking read operation: %',p_operation using errcode='22023';
  end if;
end
$function$
