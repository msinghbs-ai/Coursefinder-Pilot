CREATE OR REPLACE FUNCTION public.svc_scholarship_prepare_source(p_source_key text, p_label text, p_url text, p_source_type text DEFAULT 'scholarship_catalogue'::text, p_trust_rank smallint DEFAULT 95, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_country uuid;
  v_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if nullif(btrim(p_source_key),'') is null or nullif(btrim(p_url),'') is null then
    raise exception 'source key and url required';
  end if;

  select id into v_country from ref.countries where iso_alpha2='AU';
  if v_country is null then raise exception 'AU country missing'; end if;

  select id into v_id
  from pipeline.sources
  where metadata->>'scholarship_source_key'=p_source_key
  limit 1;

  if v_id is null then
    insert into pipeline.sources(source_type,country_id,url,label,trust_rank,status,metadata)
    values (
      p_source_type,v_country,p_url,p_label,p_trust_rank,'active',
      coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
        'layer','2A',
        'domain','scholarship',
        'scholarship_source_key',p_source_key,
        'identity_authority',false
      )
    )
    returning id into v_id;
  else
    update pipeline.sources
       set source_type=p_source_type,
           url=p_url,
           label=p_label,
           trust_rank=p_trust_rank,
           status='active',
           metadata=metadata || coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
             'layer','2A','domain','scholarship','scholarship_source_key',p_source_key,'identity_authority',false
           ),
           updated_at=now()
     where id=v_id;
  end if;
  return v_id;
end
$function$
