CREATE OR REPLACE FUNCTION public.svc_layer1_stage_course_scope_keys(p_source_id uuid, p_scope_tag text, p_course_scheme text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'catalogue', 'pipeline', 'ref'
AS $function$
declare r jsonb; v_provider uuid; v_dli text; v_id text; v_level text; v_n int:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if nullif(trim(p_scope_tag),'') is null or nullif(trim(p_course_scheme),'') is null then raise exception 'scope tag and scheme required'; end if;
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    v_dli:=upper(nullif(trim(r->>'provider_code'),'')); v_id:=nullif(trim(r->>'local_program_id'),''); v_level:=nullif(trim(r->>'study_level_code'),'');
    if v_dli is null or v_id is null then raise exception 'scope row missing provider_code/local_program_id'; end if;
    select pi.provider_id into v_provider from catalogue.provider_identifiers pi join ref.countries c on c.id=pi.country_id where upper(c.iso_alpha2::text)='CA' and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)=v_dli order by pi.is_primary desc,pi.verified_at desc nulls last limit 1;
    if v_provider is null then raise exception 'scope Provider DLI not resolved: %',v_dli; end if;
    insert into pipeline.ca_course_scope_keys(source_id,scope_tag,provider_id,course_scheme,identifier,study_level_code,metadata,verified_at)
    values(p_source_id,trim(p_scope_tag),v_provider,lower(trim(p_course_scheme)),v_id,v_level,coalesce(r->'metadata','{}'::jsonb),now())
    on conflict (source_id,scope_tag,provider_id,course_scheme,identifier) do update set study_level_code=excluded.study_level_code,metadata=excluded.metadata,verified_at=excluded.verified_at;
    v_n:=v_n+1;
  end loop;
  return jsonb_build_object('staged',v_n,'scope_tag',p_scope_tag);
end $function$
