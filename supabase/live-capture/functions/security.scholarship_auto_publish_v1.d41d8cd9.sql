CREATE OR REPLACE FUNCTION security.scholarship_auto_publish_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '300s'
AS $function$
declare v_ids uuid[]; v_ref text;
begin
  if security.scholarship_setting('auto_publish', 0) < 1 then return jsonb_build_object('skipped', 'auto_publish is off'); end if;
  select coalesce(array_agg(p.scholarship_id), '{}') into v_ids
    from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id
   where p.publishable and coalesce(s.publication_status, 'unpublished') <> 'published'
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id);
  if cardinality(v_ids) = 0 then return jsonb_build_object('published', 0); end if;
  v_ref := 'auto-publish ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI');
  update scholarship.scholarships set publication_status = 'published', updated_at = now() where id = any(v_ids);
  insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('publish', v_ref, v_ids);
  insert into search.refresh_requests(requested_by) values (v_ref || ': ' || cardinality(v_ids) || ' scholarships');
  return jsonb_build_object('published', cardinality(v_ids), 'batch', v_ref);
end $function$
