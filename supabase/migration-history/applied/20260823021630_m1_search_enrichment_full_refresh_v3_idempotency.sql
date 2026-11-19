do $do$
declare v_def text;
begin
  select pg_get_functiondef('search.refresh_course_base_v3(boolean)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    'description=excluded.description,\n      subdivision_codes=excluded.subdivision_codes',
    'description=excluded.description,\n      search_text=concat_ws('' '',excluded.search_text,search.course_documents.enrichment_semantic_text),\n      search_tsv=excluded.search_tsv || setweight(to_tsvector(''english'',coalesce(search.course_documents.enrichment_semantic_text,'''')),''C''),\n      subdivision_codes=excluded.subdivision_codes');
  v_def:=replace(v_def,
    'content_hash=excluded.content_hash,semantic_content_hash=excluded.semantic_content_hash,updated_at=now()',
    'content_hash=excluded.content_hash,semantic_content_hash=case when nullif(trim(search.course_documents.enrichment_semantic_text),'''') is null then excluded.semantic_content_hash else encode(extensions.digest(jsonb_build_object(''base'',excluded.course_stable_key,''provider'',excluded.provider_name,''title'',excluded.course_title,''code'',excluded.course_code,''level'',excluded.study_level_code,''field'',excluded.primary_field_code,''collections'',excluded.collection_names,''academic_options'',excluded.academic_option_names,''description'',excluded.description,''enrichment'',nullif(trim(search.course_documents.enrichment_semantic_text),''''))::text,''sha256''),''hex'') end,updated_at=now()');
  execute v_def;
end
$do$;

create or replace function search.refresh_course_documents_v3(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=search,extensions,pg_temp
as $function$
declare
  v_base jsonb;
  v_enrichment_dry jsonb;
  v_enrichment jsonb;
  v_full_hash text;
  v_coverage jsonb;
  v_generation bigint;
  v_enrichment_changed bigint;
  v_base_new bigint;
begin
  v_base:=search.refresh_course_base_v3(p_apply);
  v_enrichment_dry:=search.refresh_course_enrichment_v1(false);
  v_enrichment_changed:=coalesce((v_enrichment_dry->>'changed')::bigint,0);
  v_base_new:=coalesce((v_base->>'new')::bigint,0);

  if p_apply and (v_enrichment_changed>0 or v_base_new>0) then
    v_enrichment:=search.refresh_course_enrichment_v1(true);
  else
    v_enrichment:=v_enrichment_dry;
  end if;

  if p_apply then
    select encode(extensions.digest(coalesce(string_agg(course_id::text||':'||coalesce(content_hash,'')||':'||coalesce(enrichment_content_hash,''),'|' order by course_id::text),''),'sha256'),'hex')
      into v_full_hash from search.course_documents;
    select jsonb_build_object(
      'with_field',count(*) filter(where primary_field_id is not null),
      'with_state',count(*) filter(where has_state),
      'with_delivery',count(*) filter(where cardinality(delivery_modes)>0),
      'with_regulatory_tuition',count(*) filter(where has_regulatory_tuition),
      'with_provider_current_tuition',count(*) filter(where has_provider_current_tuition),
      'with_official_url',count(*) filter(where official_course_url is not null),
      'with_intake',count(*) filter(where has_intake),
      'with_english',count(*) filter(where has_english),
      'with_scholarship',count(*) filter(where has_scholarship)
    ) into v_coverage from search.course_documents;
    update search.projection_state
      set generation=generation+1,rebuilt_at=now(),row_count=(select count(*) from search.course_documents),content_hash=v_full_hash,
          metadata=jsonb_build_object(
            'projection_version','course-v3','countries',v_base->'countries','coverage',v_coverage,
            'country_gate','explicit','enrichment_gate','domain_and_source_explicit',
            'base_content_hash',v_base->>'base_content_hash','enrichment_stage_hash',v_enrichment->>'stage_hash',
            'refresh_function','search.refresh_course_documents_v3'
          )
      where projection_code='courses'
      returning generation into v_generation;
  else
    select generation into v_generation from search.projection_state where projection_code='courses';
  end if;

  return jsonb_build_object('apply',p_apply,'projection','courses','projection_version','course-v3','generation',v_generation,
    'base',v_base,'enrichment',v_enrichment,'full_content_hash',v_full_hash);
end
$function$;
revoke all on function search.refresh_course_documents_v3(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_documents_v3(boolean) to service_role;
