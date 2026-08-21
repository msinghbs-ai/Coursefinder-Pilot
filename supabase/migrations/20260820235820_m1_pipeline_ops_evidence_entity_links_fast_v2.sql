-- M1-PIPELINE-OPS / CF-CHG-20260821-016
-- Final evidence entity-impact read path. Pages the maintained lineage index before
-- resolving canonical/Search/publication state, avoiding full-table lineage rebuilds.
-- Supersedes the intermediate live v1 optimisation from the same UAT session.

create or replace function security.admin_evidence_entities(p_evidence_id uuid,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','pipeline','catalogue','scholarship','search','publishing','auth'
as $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce((p_args->>'limit')::integer,50),1),200);
  v_offset integer:=greatest(coalesce((p_args->>'offset')::integer,0),0);
  v_type text:=lower(nullif(trim(coalesce(p_args->>'entity_type','')), ''));
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  with page_links as materialized (
    select el.entity_type,el.entity_id,el.provider_id,el.link_count
    from pipeline.evidence_entity_links el
    where el.evidence_id=p_evidence_id
      and (v_type is null or el.entity_type=v_type)
    order by el.entity_type,el.entity_id
    limit v_limit offset v_offset
  ),
  resolved as (
    select l.entity_type,l.entity_id,l.link_count,
      coalesce(c.canonical_title,p.canonical_name,ca.name,s.name) entity_label,
      coalesce(c.course_code,c.stable_key,p.stable_key,ca.stable_key,s.stable_key) entity_code,
      coalesce(l.provider_id,c.provider_id,ca.provider_id,s.provider_id,case when l.entity_type='provider' then p.id end) provider_id,
      coalesce(cp.canonical_name,cap.canonical_name,sp.canonical_name,p.canonical_name) provider_label,
      coalesce(c.publication_status,p.publication_status,ca.publication_status,s.publication_status) canonical_publication_status,
      d.course_id is not null search_projected,d.publication_status search_publication_status,
      d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      coalesce((select jsonb_agg(jsonb_build_object('channel_code',es.channel_code,'locale',es.locale,'publication_status',es.publication_status,'updated_at',es.updated_at) order by es.channel_code,es.locale) from publishing.entity_states es where es.entity_id=l.entity_id),'[]'::jsonb) consumer_publication
    from page_links l
    left join catalogue.courses c on l.entity_type='course' and c.id=l.entity_id
    left join catalogue.providers cp on cp.id=coalesce(l.provider_id,c.provider_id)
    left join catalogue.providers p on l.entity_type='provider' and p.id=l.entity_id
    left join catalogue.campuses ca on l.entity_type='campus' and ca.id=l.entity_id
    left join catalogue.providers cap on cap.id=ca.provider_id
    left join scholarship.scholarships s on l.entity_type='scholarship' and s.id=l.entity_id
    left join catalogue.providers sp on sp.id=s.provider_id
    left join search.course_documents d on l.entity_type='course' and d.course_id=l.entity_id
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.entity_type,x.entity_id) from resolved x),'[]'::jsonb),
    'total',(select count(*) from pipeline.evidence_entity_links el where el.evidence_id=p_evidence_id and (v_type is null or el.entity_type=v_type)),
    'limit',v_limit,
    'offset',v_offset,
    'sort_basis','stable_entity_id',
    'consequence_note','Downstream Search/publication fields show the current state of related canonical entities; they are not asserted as causal consequences of this evidence unless a separate governed admission record exists.'
  ) into v_result;
  return v_result;
end
$function$;
