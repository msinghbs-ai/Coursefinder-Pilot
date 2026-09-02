begin;
CREATE OR REPLACE FUNCTION security.admin_provider_rankings(p_provider_id uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'ranking', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),10);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select coalesce(jsonb_object_agg(code,payload),'{}'::jsonb)
  into v_result
  from (
    select s.code,
      jsonb_build_object(
        'system_code',s.code,
        'publisher_name',s.publisher_name,
        'ranking_name',s.ranking_name,
        'latest',(
          select jsonb_strip_nulls(jsonb_build_object(
            'edition_year',e.edition_year,
            'rank_display',o.rank_display,
            'rank_exact',o.rank_exact,
            'rank_low',o.rank_low,
            'rank_high',o.rank_high,
            'rank_status',o.rank_status,
            'is_tied',o.is_tied,
            'overall_score',o.overall_score,
            'source_url',e.source_url,
            'methodology_url',e.methodology_url,
            'evidence_artifact_id',o.evidence_artifact_id
          ))
          from ranking.observations o
          join ranking.editions e on e.id=o.edition_id
          where (o.provider_id=p_provider_id or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id and opl.provider_id=p_provider_id)) and e.system_id=s.id and e.status='accepted'
          order by e.edition_year desc,e.updated_at desc
          limit 1
        ),
        'history',coalesce((
          select jsonb_agg(x order by (x->>'edition_year')::integer desc)
          from (
            select jsonb_strip_nulls(jsonb_build_object(
              'edition_year',e.edition_year,
              'rank_display',o.rank_display,
              'rank_exact',o.rank_exact,
              'rank_low',o.rank_low,
              'rank_high',o.rank_high,
              'rank_status',o.rank_status,
              'is_tied',o.is_tied,
              'overall_score',o.overall_score,
              'methodology_version',e.methodology_version
            )) x
            from ranking.observations o
            join ranking.editions e on e.id=o.edition_id
            where (o.provider_id=p_provider_id or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id and opl.provider_id=p_provider_id)) and e.system_id=s.id and e.status='accepted'
            order by e.edition_year desc,e.updated_at desc
            limit v_limit
          ) h
        ),'[]'::jsonb)
      ) payload
    from ranking.systems s
    where s.active
  ) z;

  return coalesce(v_result,'{}'::jsonb);
end
$function$
;
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
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if p_operation='ranking_summary' then
    return jsonb_build_object(
      'systems',coalesce((
        select jsonb_agg(jsonb_build_object(
          'code',s.code,
          'publisher_name',s.publisher_name,
          'ranking_name',s.ranking_name,
          'official_url',s.official_url,
          'latest_edition',(select max(e.edition_year) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
          'accepted_editions',(select count(*) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
          'observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted'),
          'mapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and o.provider_id is not null),
          'unmapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and o.provider_id is null)
        ) order by s.code)
        from ranking.systems s where s.active
      ),'[]'::jsonb),
      'manual_imports',case when v_rank>=4 then (
        select jsonb_build_object(
          'total',count(*),
          'uploaded',count(*) filter(where status='uploaded'),
          'needs_review',count(*) filter(where status='needs_review'),
          'applied',count(*) filter(where status='applied')
        ) from ranking.manual_imports
      ) else null end
    );
  elsif p_operation='ranking_filters' then
    return jsonb_build_object(
      'systems',coalesce((select jsonb_agg(jsonb_build_object('code',code,'label',ranking_name) order by code) from ranking.systems where active),'[]'::jsonb),
      'years',coalesce((select jsonb_agg(y order by y desc) from (select distinct edition_year y from ranking.editions) q),'[]'::jsonb),
      'statuses',jsonb_build_array('ranked_exact','ranked_band','reporter','unranked','not_eligible','unknown')
    );
  elsif p_operation='ranking_observations' then
    return (
      with filtered as (
        select
          o.id,s.code system_code,s.publisher_name,s.ranking_name,e.edition_year,e.methodology_version,e.methodology_url,e.source_url,
          pi.institution_name publisher_institution_name,pi.country_text,
          o.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,
          o.rank_display,o.rank_exact,o.rank_low,o.rank_high,o.is_tied,o.rank_status,o.overall_score,o.evidence_artifact_id
        from ranking.observations o
        join ranking.editions e on e.id=o.edition_id
        join ranking.systems s on s.id=e.system_id
        join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id
        left join catalogue.providers p on p.id=o.provider_id
        where e.status='accepted'
          and (v_system is null or s.code=v_system)
          and (v_year is null or e.edition_year=v_year)
          and (v_provider is null or o.provider_id=v_provider or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id and opl.provider_id=v_provider))
          and (v_query is null or pi.institution_name ilike '%'||v_query||'%' or coalesce(p.display_name,p.canonical_name) ilike '%'||v_query||'%')
      )
      select jsonb_build_object(
        'total',(select count(*) from filtered),
        'limit',v_limit,
        'offset',v_offset,
        'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.system_code,x.edition_year desc,coalesce(x.rank_exact,x.rank_low,999999),x.publisher_institution_name)
          from (select * from filtered order by system_code,edition_year desc,coalesce(rank_exact,rank_low,999999),publisher_institution_name limit v_limit offset v_offset) x),'[]'::jsonb)
      )
    );
  elsif p_operation='ranking_imports' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    return (
      select jsonb_build_object(
        'total',(select count(*) from ranking.manual_imports),
        'limit',v_limit,'offset',v_offset,
        'items',coalesce((
          select jsonb_agg(to_jsonb(x) order by x.uploaded_at desc)
          from (
            select mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,
              mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,
              mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,mi.uploaded_at
            from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id
            order by mi.uploaded_at desc limit v_limit offset v_offset
          ) x
        ),'[]'::jsonb)
      )
    );
  else
    raise exception 'unsupported ranking read operation: %',p_operation using errcode='22023';
  end if;
end
$function$
;
commit;