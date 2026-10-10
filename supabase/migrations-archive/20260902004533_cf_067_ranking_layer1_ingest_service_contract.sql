CREATE OR REPLACE FUNCTION public.svc_ranking_ingest_apply(p_system_code text, p_edition_year integer, p_source_url text, p_methodology_url text, p_source_artifact_id uuid, p_source_fingerprint text, p_source_revision text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking', 'catalogue', 'ref', 'pipeline'
AS $function$
declare
  v_system_id uuid;
  v_edition_id uuid;
  v_created integer:=0;
  v_updated integer:=0;
  v_mapped integer:=0;
  v_unmapped integer:=0;
  v_row jsonb;
  v_pub_id uuid;
  v_provider_id uuid;
  v_country text;
  v_name text;
  v_rank_display text;
  v_rank_exact integer;
  v_rank_low integer;
  v_rank_high integer;
  v_score numeric;
  v_status text;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  if jsonb_typeof(coalesce(p_rows,'[]'::jsonb))<>'array' then
    raise exception 'rows must be array' using errcode='22023';
  end if;
  select id into v_system_id from ranking.systems where code=p_system_code and active;
  if v_system_id is null then raise exception 'unsupported ranking system' using errcode='22023'; end if;

  insert into ranking.editions(system_id,edition_year,methodology_url,source_url,source_artifact_id,retrieved_at,source_fingerprint,source_revision,access_status,licensing_note,status)
  values(v_system_id,p_edition_year,nullif(p_methodology_url,''),p_source_url,p_source_artifact_id,now(),p_source_fingerprint,coalesce(nullif(p_source_revision,''),'initial'),'licensed_upload','Publisher artifact registered through governed Layer 1 evidence flow','accepted')
  on conflict(system_id,edition_year,source_revision) do update set
    methodology_url=excluded.methodology_url,
    source_url=excluded.source_url,
    source_artifact_id=excluded.source_artifact_id,
    retrieved_at=excluded.retrieved_at,
    source_fingerprint=excluded.source_fingerprint,
    access_status='licensed_upload',
    status='accepted',
    updated_at=now()
  returning id into v_edition_id;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_name:=nullif(btrim(v_row->>'institution_name'),'');
    if v_name is null then continue; end if;
    v_country:=nullif(btrim(v_row->>'country_text'),'');
    v_rank_display:=nullif(btrim(v_row->>'rank_display'),'');
    v_rank_exact:=nullif(v_row->>'rank_exact','')::integer;
    v_rank_low:=nullif(v_row->>'rank_low','')::integer;
    v_rank_high:=nullif(v_row->>'rank_high','')::integer;
    v_score:=nullif(v_row->>'overall_score','')::numeric;
    v_status:=coalesce(nullif(v_row->>'rank_status',''),'unknown');

    select id into v_pub_id
    from ranking.publisher_institutions
    where system_id=v_system_id
      and lower(institution_name)=lower(v_name)
      and lower(coalesce(country_text,''))=lower(coalesce(v_country,''))
    limit 1;

    if v_pub_id is null then
      insert into ranking.publisher_institutions(system_id,publisher_institution_id,profile_url,institution_name,country_text,location_text,first_seen_edition,last_seen_edition)
      values(v_system_id,nullif(v_row->>'publisher_institution_id',''),nullif(v_row->>'profile_url',''),v_name,v_country,nullif(v_row->>'location_text',''),p_edition_year,p_edition_year)
      returning id into v_pub_id;
    else
      update ranking.publisher_institutions set
        publisher_institution_id=coalesce(publisher_institution_id,nullif(v_row->>'publisher_institution_id','')),
        profile_url=coalesce(profile_url,nullif(v_row->>'profile_url','')),
        first_seen_edition=least(coalesce(first_seen_edition,p_edition_year),p_edition_year),
        last_seen_edition=greatest(coalesce(last_seen_edition,p_edition_year),p_edition_year),
        updated_at=now()
      where id=v_pub_id;
    end if;

    select pm.provider_id into v_provider_id
    from ranking.provider_mappings pm
    where pm.publisher_institution_id=v_pub_id and pm.status='accepted' and pm.valid_to is null
    limit 1;

    if v_provider_id is null then
      select p.id into v_provider_id
      from catalogue.providers p
      left join ref.countries c on c.id=p.country_id
      where lower(coalesce(p.display_name,p.canonical_name))=lower(v_name)
        and (
          v_country is null
          or lower(c.name)=lower(v_country)
          or lower(c.iso_alpha2::text)=lower(v_country)
          or lower(c.iso_alpha3::text)=lower(v_country)
        )
      order by p.id
      limit 1;
      if v_provider_id is not null then
        insert into ranking.provider_mappings(publisher_institution_id,provider_id,mapping_method,confidence,status,evidence_artifact_id,reviewed_at,note)
        values(v_pub_id,v_provider_id,'exact_canonical_name_country',1.0,'accepted',p_source_artifact_id,now(),'Deterministic exact canonical/display name + country match during Layer 1 ranking ingestion')
        on conflict do nothing;
      end if;
    end if;

    insert into ranking.observations(
      edition_id,publisher_institution_id,provider_id,rank_display,rank_exact,rank_low,rank_high,is_tied,rank_status,overall_score,source_row_ordinal,source_row_payload,evidence_artifact_id
    ) values(
      v_edition_id,v_pub_id,v_provider_id,v_rank_display,v_rank_exact,v_rank_low,v_rank_high,
      coalesce((v_row->>'is_tied')::boolean,false),v_status,v_score,nullif(v_row->>'source_row_ordinal','')::integer,v_row,p_source_artifact_id
    )
    on conflict(edition_id,publisher_institution_id) do update set
      provider_id=excluded.provider_id,
      rank_display=excluded.rank_display,
      rank_exact=excluded.rank_exact,
      rank_low=excluded.rank_low,
      rank_high=excluded.rank_high,
      is_tied=excluded.is_tied,
      rank_status=excluded.rank_status,
      overall_score=excluded.overall_score,
      source_row_ordinal=excluded.source_row_ordinal,
      source_row_payload=excluded.source_row_payload,
      evidence_artifact_id=excluded.evidence_artifact_id;

    get diagnostics v_updated = row_count;
    if v_provider_id is null then v_unmapped:=v_unmapped+1; else v_mapped:=v_mapped+1; end if;
  end loop;

  update ranking.manual_imports
  set status=case when v_unmapped>0 then 'needs_review' else 'applied' end,
      parse_summary=jsonb_build_object('rows',jsonb_array_length(p_rows),'mapped',v_mapped,'unmapped',v_unmapped),
      updated_at=now()
  where evidence_artifact_id=p_source_artifact_id;

  return jsonb_build_object(
    'edition_id',v_edition_id,
    'rows',jsonb_array_length(p_rows),
    'mapped',v_mapped,
    'unmapped',v_unmapped,
    'status',case when v_unmapped>0 then 'needs_review' else 'applied' end
  );
end
$function$
;

revoke all on function public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb) from public,anon,authenticated;

grant execute on function public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.svc_ranking_latest_import(p_system_code text, p_edition_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
declare v jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
 select jsonb_build_object(
   'id',mi.id,'edition_year',mi.edition_year,'source_url',mi.source_url,'methodology_url',mi.methodology_url,
   'revision_note',mi.revision_note,'original_filename',mi.original_filename,'mime_type',mi.mime_type,'byte_size',mi.byte_size,
   'content_hash',mi.content_hash,'storage_path',mi.storage_path,'evidence_artifact_id',mi.evidence_artifact_id,'status',mi.status
 ) into v
 from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id
 where s.code=p_system_code and mi.edition_year=p_edition_year and mi.status in ('uploaded','validated','parsed','needs_review','reconciled','applied')
 order by mi.uploaded_at desc limit 1;
 return coalesce(v,'{}'::jsonb);
end
$function$
;

revoke all on function public.svc_ranking_latest_import(text,integer) from public,anon,authenticated;

grant execute on function public.svc_ranking_latest_import(text,integer) to service_role;