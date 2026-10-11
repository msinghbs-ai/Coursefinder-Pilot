CREATE OR REPLACE FUNCTION security.scholarship_publication_review_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_ids uuid[];
begin
  select coalesce(array_agg(s.id),'{}') into v_ids
    from scholarship.scholarships s join security.scholarship_publishability_v1() p on p.scholarship_id=s.id
   where s.publication_status='published' and not p.publishable;
  if cardinality(v_ids)>0 then
    update scholarship.scholarships set publication_status='withdrawn', updated_at=now() where id=any(v_ids);
    insert into pipeline.scholarship_publication_batches(kind,approval_ref,scholarship_ids) values ('withdraw','Decision 139 automatic withdrawal',v_ids);
  end if;
  return jsonb_build_object('withdrawn',cardinality(v_ids));
end $function$
