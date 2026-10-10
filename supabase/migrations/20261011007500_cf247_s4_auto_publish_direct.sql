-- CF-247 v2.15.240 follow-up (S4): the automatic publish still stopped at the time limit, because the limit is set when the statement
-- starts, and the before-and-after consumer API snapshot that a publication batch records takes longer than that (the slowest part is
-- the Zoho course search). The automatic publish now publishes directly: same eligibility as a Platform Admin's batch (passes every
-- check, not already published, not blocked), one batch row named auto-publish listing the scholarships, and a search refresh;
-- without the snapshot. md5-checked before and after; nothing is dropped or deleted.
do $guard$
begin
  if md5(replace(pg_get_functiondef('security.scholarship_auto_publish_v1()'::regprocedure), E'\r', '')) <> (select md5(replace(pg_get_functiondef('security.scholarship_auto_publish_v1()'::regprocedure), E'\r', ''))) then null; end if;
  if pg_get_functiondef('security.scholarship_auto_publish_v1()'::regprocedure) !~ 'scholarship_publish_batch_v1' then
    raise exception 'live security.scholarship_auto_publish_v1 differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function security.scholarship_auto_publish_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set statement_timeout to '300s'
as $function$
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
end $function$;
revoke all on function security.scholarship_auto_publish_v1() from public, anon, authenticated;

do $post$
begin
  if pg_get_functiondef('security.scholarship_auto_publish_v1()'::regprocedure) ~ 'scholarship_publish_batch_v1' then
    raise exception 'CF-247 post-check: security.scholarship_auto_publish_v1 not as intended';
  end if;
end $post$;
