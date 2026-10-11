CREATE OR REPLACE FUNCTION security.admin_scholarship_publishing_v1(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'security'
AS $function$
declare v_id uuid:=nullif(p_args->>'id','')::uuid; v_res jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action='publish_batch' then
    if coalesce(btrim(p_args->>'approval'),'')='' then raise exception 'an approval note is required'; end if;
    if (security.scholarship_publish_batch_v1('dry run',false)->>'eligible')::int<>(p_args->>'expected')::int then raise exception 'the eligible list changed; refresh and check again'; end if;
    v_res:=security.scholarship_publish_batch_v1('CF-CHG-20260915-247; Decision 139; '||btrim(p_args->>'approval'),true);
  elsif p_action='hold' then
    if coalesce(btrim(p_args->>'reason'),'')='' then raise exception 'a reason is required'; end if;
    insert into pipeline.scholarship_publication_holds(scholarship_id,reason,held_by) values (v_id,btrim(p_args->>'reason'),'admin')
    on conflict (scholarship_id) do update set reason=excluded.reason, held_by='admin', held_at=now(), released_at=null, release_note=null;
    update scholarship.scholarships set publication_status='withdrawn', updated_at=now() where id=v_id and publication_status='published';
  elsif p_action='release' then
    update pipeline.scholarship_publication_holds set released_at=now(), release_note=coalesce(p_args->>'note','released by an admin') where scholarship_id=v_id and released_at is null;
  elsif p_action='withdraw' then
    update scholarship.scholarships set publication_status='withdrawn', updated_at=now() where id=v_id and publication_status='published';
    insert into pipeline.scholarship_publication_batches(kind,approval_ref,scholarship_ids) values ('withdraw','Admin control: '||coalesce(p_args->>'reason','withdrawn'),array[v_id]);
  elsif p_action='confirm_international' then
    if coalesce(btrim(p_args->>'note'),'')='' then raise exception 'a note is required'; end if;
    insert into scholarship.criteria(scholarship_id,criterion_type,operator,value_codes,value_json,human_text,is_mandatory,machine_evaluable,status,confidence)
    values (v_id,'student_type','in',array['international'],jsonb_build_object('by','person','actor',auth.uid(),'decision','Decision 212'),left(btrim(p_args->>'note'),300),true,true,'active',1);
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('scholarships',p_action,v_id::text,p_args||coalesce(jsonb_build_object('result',v_res),'{}'::jsonb),auth.uid());
  return security.admin_scholarship_publishing_read_v1();
end $function$
