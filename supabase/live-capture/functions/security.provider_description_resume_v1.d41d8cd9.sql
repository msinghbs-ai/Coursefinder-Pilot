CREATE OR REPLACE FUNCTION security.provider_description_resume_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_n int:=0; v_free int;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return 0; end if;
 select greatest(0,security.pipeline_num_v1('pdesc.pending_max',10)::int-count(*)::int) into v_free from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending';
 for r in select * from pipeline.provider_description_reads x where ((x.state='held' and x.rule='review_full') or (x.state='queued' and x.rule='retried' and x.proposal->>'description' is not null)) and x.evidence_id is not null order by x.updated_at,x.id limit v_free for update skip locked loop
  update pipeline.provider_description_reads set state='reading' where id=r.id;
  perform public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id',r.id,'stored_evidence_id',r.evidence_id,'answer',jsonb_build_object('about_page',true,'sentences',r.proposal->'sentences'))));
  v_n:=v_n+1;
 end loop;
 return v_n;
end $function$
