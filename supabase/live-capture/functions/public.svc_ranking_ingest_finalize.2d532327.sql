CREATE OR REPLACE FUNCTION public.svc_ranking_ingest_finalize(p_system_code text, p_edition_year integer, p_source_artifact_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking', 'catalogue', 'ref'
AS $function$
declare
  v_system_id uuid;
  v_edition_id uuid;
  v_rows bigint:=0;
  v_mapped bigint:=0;
  v_global_unmapped bigint:=0;
  v_supported_scope_unmapped bigint:=0;
  v_equivalent_links bigint:=0;
  v_status text;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;

  select id into v_system_id from ranking.systems where code=p_system_code and active;
  if v_system_id is null then raise exception 'unsupported ranking system' using errcode='22023'; end if;

  select e.id into v_edition_id
  from ranking.editions e
  where e.system_id=v_system_id
    and e.edition_year=p_edition_year
    and e.source_artifact_id=p_source_artifact_id
  order by e.updated_at desc
  limit 1;
  if v_edition_id is null then raise exception 'ranking edition not found for source artifact' using errcode='22023'; end if;

  select count(*),
         count(*) filter(where o.provider_id is not null or exists(
           select 1 from ranking.observation_provider_links opl
           where opl.observation_id=o.id
         )),
         count(*) filter(where o.provider_id is null and not exists(
           select 1 from ranking.observation_provider_links opl
           where opl.observation_id=o.id
         ))
  into v_rows,v_mapped,v_global_unmapped
  from ranking.observations o
  where o.edition_id=v_edition_id;

  select count(*) into v_supported_scope_unmapped
  from ranking.observations o
  join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id
  where o.edition_id=v_edition_id
    and o.provider_id is null
    and not exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id)
    and exists(
      select 1
      from ref.countries c
      where (lower(c.name)=lower(coalesce(pi.country_text,''))
          or lower(c.iso_alpha2::text)=lower(coalesce(pi.country_text,''))
          or lower(c.iso_alpha3::text)=lower(coalesce(pi.country_text,'')))
        and exists(select 1 from catalogue.providers p where p.country_id=c.id)
    );

  select count(*) into v_equivalent_links
  from ranking.observation_provider_links opl
  join ranking.observations o on o.id=opl.observation_id
  where o.edition_id=v_edition_id and opl.is_primary=false;

  v_status:=case when v_supported_scope_unmapped>0 then 'needs_review' else 'applied' end;

  update ranking.manual_imports
  set status=v_status,
      parse_summary=jsonb_build_object(
        'rows',v_rows,
        'mapped',v_mapped,
        'global_unmapped',v_global_unmapped,
        'supported_scope_unmapped',v_supported_scope_unmapped,
        'equivalent_provider_fanout_links',v_equivalent_links,
        'finalized_at',now()
      ),
      updated_at=now()
  where evidence_artifact_id=p_source_artifact_id;

  return jsonb_build_object(
    'edition_id',v_edition_id,
    'rows',v_rows,
    'mapped',v_mapped,
    'global_unmapped',v_global_unmapped,
    'supported_scope_unmapped',v_supported_scope_unmapped,
    'equivalent_provider_fanout_links',v_equivalent_links,
    'status',v_status
  );
end
$function$
