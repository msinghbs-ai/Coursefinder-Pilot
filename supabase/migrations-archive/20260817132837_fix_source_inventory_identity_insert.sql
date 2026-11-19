create or replace function public.svc_layer1_replace_source_inventory(
  p_country_code text,
  p_source_id uuid,
  p_provider_id uuid,
  p_inventory_hash text,
  p_records jsonb
) returns jsonb
language plpgsql security definer
set search_path='public','pipeline','ref'
as $$
declare v_country uuid; v_count int:=0; r jsonb;
begin
  select id into v_country from ref.countries where upper(iso_alpha2::text)=upper(p_country_code);
  if v_country is null then raise exception 'country missing'; end if;
  if nullif(trim(p_inventory_hash),'') is null then raise exception 'inventory hash required'; end if;
  delete from pipeline.source_record_staging where source_id=p_source_id and provider_id=p_provider_id;
  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    insert into pipeline.source_record_staging(country_id,source_id,provider_id,source_record_id,raw_payload,content_hash,status,ingested_at)
    values(v_country,p_source_id,p_provider_id,lower(trim(r->>'guid')),r,p_inventory_hash,'pending',now());
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('staged',v_count,'inventory_hash',p_inventory_hash);
end $$;
revoke all on function public.svc_layer1_replace_source_inventory(text,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_layer1_replace_source_inventory(text,uuid,uuid,text,jsonb) to service_role;
