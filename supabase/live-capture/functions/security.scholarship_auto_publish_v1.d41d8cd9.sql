CREATE OR REPLACE FUNCTION security.scholarship_auto_publish_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '300s'
AS $function$
declare v_ids uuid[]; v_ref text; v_hold uuid[] := '{}';
begin
  -- v1.0.2 (Platform Admin 15 Nov 2026 11:22): a closed scholarship is not served, whether or not automatic publishing is on
  perform security.scholarship_expire_v1();
  if security.scholarship_setting('auto_publish', 0) < 1 then return jsonb_build_object('skipped', 'auto_publish is off'); end if;
  select coalesce(array_agg(p.scholarship_id), '{}') into v_ids
    from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id
   where p.publishable and coalesce(s.publication_status, 'unpublished') <> 'published'
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id);
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 5): a scholarship published automatically that now fails a check is held with the
  -- reason and taken off search; it is listed in Layer 4 to release or fix. One a person published is shown as failing, not held.
  select coalesce(array_agg(p.scholarship_id), '{}') into v_hold
    from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id
   where not p.publishable and s.publication_status = 'published'
     and not exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null)
     and coalesce((select b.approval_ref from pipeline.scholarship_publication_batches b where s.id = any (b.scholarship_ids) and b.kind = 'publish' order by b.created_at desc limit 1), '') like 'auto-publish%';
  v_ref := to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI');
  if cardinality(v_hold) > 0 then
    insert into pipeline.scholarship_publication_holds(scholarship_id, reason, held_by)
    select p.scholarship_id, 'Failed a check after publishing: ' || array_to_string(p.missing, '; '), 'auto' from security.scholarship_publishability_for_v1(v_hold) p
    on conflict (scholarship_id) do update set reason = excluded.reason, held_by = 'auto', held_at = now(), released_at = null, release_note = null;
    update scholarship.scholarships set publication_status = 'withdrawn', updated_at = now() where id = any (v_hold);
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('withdraw', 'auto-hold ' || v_ref, v_hold);
  end if;
  if cardinality(v_ids) > 0 then
    update scholarship.scholarships set publication_status = 'published', updated_at = now() where id = any (v_ids);
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('publish', 'auto-publish ' || v_ref, v_ids);
  end if;
  if cardinality(v_ids) + cardinality(v_hold) > 0 then
    insert into search.refresh_requests(requested_by) values ('auto-publish ' || v_ref || ': ' || cardinality(v_ids) || ' published, ' || cardinality(v_hold) || ' held');
  end if;
  return jsonb_build_object('published', cardinality(v_ids), 'held', cardinality(v_hold), 'batch', case when cardinality(v_ids) > 0 then 'auto-publish ' || v_ref end);
end $function$
