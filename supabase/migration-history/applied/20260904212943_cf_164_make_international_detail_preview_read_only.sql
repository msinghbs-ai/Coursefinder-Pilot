do $patch$
declare
  v_def text;
  v_marker text:='  -- Reclassify only active acquisition candidates in scope. An explicit international cue is required for automatic detail firing.';
  v_insert text:=$ins$
  if v_action='preview' then
    with scoped_providers as (
      select distinct p.id
      from catalogue.providers p join ref.countries c on c.id=p.country_id
      where upper(c.iso_alpha2::text)=upper(p_country_code)
        and (v_scope_type='country'
          or (v_scope_type='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id)))
          or (v_scope_type='university' and p.id=p_scope_id))
    ), x as (
      select c.classification,count(*) n
      from pipeline.layer2_scholarship_discovery_candidates c
      join pipeline.sources s on s.id=c.source_id
      join scoped_providers sp on sp.id=s.provider_id
      where coalesce(c.status,'') not in('rejected','duplicate','superseded')
      group by c.classification
    )
    select coalesce(sum(n),0),coalesce(sum(n) filter(where classification='detail_ready'),0),coalesce(sum(n) filter(where classification='needs_review'),0),coalesce(sum(n) filter(where classification='catalogue_or_filter'),0)
      into v_candidates,v_ready,v_review,v_catalogue from x;
    return jsonb_build_object('ok',true,'action','preview','scope_type',v_scope_type,'scope_id',p_scope_id,'scope_name',v_scope_name,'country_code',upper(p_country_code),'candidate_total',v_candidates,'detail_ready',v_ready,'needs_review',v_review,'catalogue_or_filter',v_catalogue,'max_jobs',v_limit,'publication_changed',false,'preview_mutated',false);
  end if;

  -- Reclassify only active acquisition candidates in scope. An explicit international cue is required for automatic detail firing.
$ins$;
begin
  select pg_get_functiondef('public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean)'::regprocedure) into v_def;
  if position(v_marker in v_def)=0 then raise exception 'CF-164 patch marker not found'; end if;
  v_def:=replace(v_def,v_marker,v_insert);
  execute v_def;
end
$patch$;
