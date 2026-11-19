CREATE OR REPLACE FUNCTION security.provider_description_publication_check_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_body jsonb; v_zoho jsonb; v_n int:=0;
begin
 for r in select d.id,d.provider_id,d.proposal,p.stable_key,p.description from pipeline.provider_description_reads d join catalogue.providers p on p.id=d.provider_id where d.state in ('admitted','verified') and p.description=d.proposal->>'description' and security.provider_description_approved_lineage_v1(p.id,p.description) is not null order by d.consumer_checked_at nulls first,d.id limit security.pipeline_num_v1('pdesc.queue_per_run',10)::int for update of d skip locked loop
  begin v_body:=public.website_v2_provider(r.stable_key); exception when others then v_body:=null; end;
  v_zoho:=security.provider_description_consumer_read_v1('zoho',r.stable_key);
  update pipeline.provider_description_reads set consumer_checked_at=now(),consumer_checks=jsonb_build_object('website_verified',coalesce(v_body->'item'->>'provider_id'=r.stable_key and v_body->'item'->>'description'=r.description and r.description=r.proposal->>'description',false),'zoho_verified',coalesce(v_zoho->'item'->>'provider_id'=r.stable_key and v_zoho->'item'->>'description'=r.description and r.description=r.proposal->>'description',false),'website_error',v_body->'error','zoho_error',v_zoho->'error','checked_at',now()),zoho_published_at=case when v_zoho->'item'->>'provider_id'=r.stable_key and v_zoho->'item'->>'description'=r.description and r.description=r.proposal->>'description' then coalesce(zoho_published_at,now()) else zoho_published_at end,published_at=case when v_body->'item'->>'description'=r.description and v_body->'item'->>'provider_id'=r.stable_key and r.description=r.proposal->>'description' then coalesce(published_at,now()) else published_at end,updated_at=now() where id=r.id;
  if v_body->'item'->>'description'=r.description and v_body->'item'->>'provider_id'=r.stable_key and r.description=r.proposal->>'description' then v_n:=v_n+1; end if;
 end loop;
 return v_n;
end $function$
