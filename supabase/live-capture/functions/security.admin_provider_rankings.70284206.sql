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
  v_obs uuid[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  -- Find this provider's observations once (direct and linked), each via an index.
  v_obs := array(select o.id from ranking.observations o where o.provider_id=p_provider_id union select opl.observation_id from ranking.observation_provider_links opl where opl.provider_id=p_provider_id);

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
          where o.id = any(v_obs) and e.system_id=s.id and e.status='accepted'
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
            where o.id = any(v_obs) and e.system_id=s.id and e.status='accepted'
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
