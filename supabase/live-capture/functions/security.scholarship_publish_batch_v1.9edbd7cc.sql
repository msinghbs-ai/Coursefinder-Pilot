CREATE OR REPLACE FUNCTION security.scholarship_publish_batch_v1(p_approval_ref text, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_ids uuid[]; v_before jsonb; v_after jsonb;
begin
  if coalesce(btrim(p_approval_ref),'')='' then raise exception 'approval reference required'; end if;
  select coalesce(array_agg(p.scholarship_id),'{}') into v_ids
    from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id=p.scholarship_id
   where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id);
  if not p_apply or cardinality(v_ids)=0 then return jsonb_build_object('apply',p_apply,'eligible',cardinality(v_ids),'ids',to_jsonb(v_ids)); end if;
  v_before:=security.consumer_api_snapshot_v1();
  update scholarship.scholarships set publication_status='published', updated_at=now() where id=any(v_ids);
  insert into pipeline.scholarship_publication_batches(kind,approval_ref,scholarship_ids) values ('publish',p_approval_ref,v_ids);
  v_after:=security.consumer_api_snapshot_v1();
  insert into pipeline.consumer_api_baselines(label,snapshot) values
    ('before scholarship publication batch ('||cardinality(v_ids)||', Decision 139)',v_before),
    ('after scholarship publication batch ('||cardinality(v_ids)||', Decision 139)',v_after);
  return jsonb_build_object('apply',true,'published',cardinality(v_ids),'ids',to_jsonb(v_ids));
end $function$
