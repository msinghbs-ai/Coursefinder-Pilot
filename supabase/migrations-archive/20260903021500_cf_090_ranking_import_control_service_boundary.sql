begin;

create or replace function public.svc_ranking_import_control_context(p_import_id uuid)
returns jsonb
language sql
security definer
set search_path='pg_catalog','ranking','pipeline'
as $$
 with x as (
   select mi.*,rs.code system_code,
          case when rs.code='the_wur' then 'THE' else 'QS' end source_system
   from ranking.manual_imports mi
   join ranking.systems rs on rs.id=mi.system_id
   where mi.id=p_import_id
 )
 select jsonb_build_object(
   'id',x.id,
   'system_id',x.system_id,
   'system_code',x.system_code,
   'edition_year',x.edition_year,
   'original_filename',x.original_filename,
   'status',x.status,
   'evidence_artifact_id',x.evidence_artifact_id,
   'source_url',x.source_url,
   'methodology_url',x.methodology_url,
   'content_hash',x.content_hash,
   'source_id',(
     select s.id
     from pipeline.sources s
     where upper(coalesce(s.metadata->>'source_system',''))=x.source_system
     order by
       case when nullif(s.metadata->>'edition_year','')::integer=x.edition_year then 0
            when coalesce((s.metadata->>'multi_year_family')::boolean,false) then 1
            else 2 end,
       s.updated_at desc
     limit 1
   )
 )
 from x
$$;

revoke all on function public.svc_ranking_import_control_context(uuid) from public,anon,authenticated;
grant execute on function public.svc_ranking_import_control_context(uuid) to service_role;

create or replace function public.svc_ranking_import_validation_update(
 p_import_id uuid,
 p_status text,
 p_validation_summary jsonb,
 p_parse_summary jsonb
)
returns boolean
language plpgsql
security definer
set search_path='pg_catalog','ranking'
as $$
begin
 if current_user not in ('service_role','postgres') then
   raise exception 'service role required' using errcode='42501';
 end if;
 if p_status not in ('uploaded','validated','parsed','reconciled','needs_review','applied','rejected') then
   raise exception 'invalid ranking import status' using errcode='22023';
 end if;
 update ranking.manual_imports
 set status=p_status,
     validation_summary=coalesce(p_validation_summary,'{}'::jsonb),
     parse_summary=coalesce(p_parse_summary,'{}'::jsonb),
     updated_at=now()
 where id=p_import_id;
 return found;
end
$$;

revoke all on function public.svc_ranking_import_validation_update(uuid,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.svc_ranking_import_validation_update(uuid,text,jsonb,jsonb) to service_role;

create or replace function public.svc_ranking_ingest_finalize(
  p_system_code text,
  p_edition_year integer,
  p_source_artifact_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','ranking','catalogue','ref'
as $
declare
  v_system_id uuid; v_edition_id uuid; v_rows bigint:=0; v_mapped bigint:=0;
  v_global_unmapped bigint:=0; v_supported_scope_unmapped bigint:=0; v_equivalent_links bigint:=0; v_status text;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
  select id into v_system_id from ranking.systems where code=p_system_code and active;
  if v_system_id is null then raise exception 'unsupported ranking system' using errcode='22023'; end if;
  select e.id into v_edition_id from ranking.editions e
  where e.system_id=v_system_id and e.edition_year=p_edition_year and e.source_artifact_id=p_source_artifact_id
  order by e.updated_at desc limit 1;
  if v_edition_id is null then raise exception 'ranking edition not found for source artifact' using errcode='22023'; end if;

  select count(*),
         count(*) filter(where o.provider_id is not null or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id)),
         count(*) filter(where o.provider_id is null and not exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id))
  into v_rows,v_mapped,v_global_unmapped
  from ranking.observations o where o.edition_id=v_edition_id;

  select count(*) into v_supported_scope_unmapped
  from ranking.observations o join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id
  where o.edition_id=v_edition_id and o.provider_id is null
    and not exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id)
    and exists(
      select 1 from ref.countries c
      where (lower(c.name)=lower(coalesce(pi.country_text,'')) or lower(c.iso_alpha2::text)=lower(coalesce(pi.country_text,'')) or lower(c.iso_alpha3::text)=lower(coalesce(pi.country_text,'')))
        and exists(select 1 from catalogue.providers p where p.country_id=c.id)
    );

  select count(*) into v_equivalent_links
  from ranking.observation_provider_links opl join ranking.observations o on o.id=opl.observation_id
  where o.edition_id=v_edition_id and opl.is_primary=false;

  v_status:=case when v_supported_scope_unmapped>0 then 'needs_review' else 'applied' end;
  update ranking.manual_imports set status=v_status,
    parse_summary=jsonb_build_object('rows',v_rows,'mapped',v_mapped,'global_unmapped',v_global_unmapped,'supported_scope_unmapped',v_supported_scope_unmapped,'equivalent_provider_fanout_links',v_equivalent_links,'finalized_at',now()),
    updated_at=now()
  where evidence_artifact_id=p_source_artifact_id;

  return jsonb_build_object('edition_id',v_edition_id,'rows',v_rows,'mapped',v_mapped,'global_unmapped',v_global_unmapped,'supported_scope_unmapped',v_supported_scope_unmapped,'equivalent_provider_fanout_links',v_equivalent_links,'status',v_status);
end
$;
revoke all on function public.svc_ranking_ingest_finalize(text,integer,uuid) from public,anon,authenticated;
grant execute on function public.svc_ranking_ingest_finalize(text,integer,uuid) to service_role;


commit;
