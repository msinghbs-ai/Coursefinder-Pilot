-- CF-247 Decision 254 (5 Oct 2026, night run wave 4). Reading a page again (the Read pages again button, or an agent's
-- re-read) replaced a good earlier reading with nothing when the second read failed for a passing reason (the site
-- refused the reader, timed out, or the page was put off to the monthly rendered read). Vision College and Holmesglen
-- lost their readings that way tonight. Now a page that was read and confirmed keeps its reading, its identity and its
-- stored copy when a later read fails for such a reason, and the read is tried again later. A page that is gone (404)
-- or now names another course is still recorded as such.
-- The pages that lost their reading this way after a Platform Admin re-read are put back from their stored copy (the
-- identity recorded with that copy). Their fields are worked out again from the stored copy by the reader's
-- re-extract run and the university's adapter. Snippet patch, md5-guarded, found exactly once. No text value in this
-- file contains a semicolon.

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)'::regprocedure) is distinct from '441e99bb2ee9022273226a878a7af9c2' then
    raise exception 'svc_coverage_read_record changed, not patching'; end if;
  v_def := pg_get_functiondef('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$  if v_row.course_id is null then raise exception 'course page not bound'{sc} end if{sc}
$s$, $s$  if v_row.course_id is null then raise exception 'course page not bound'{sc} end if{sc}
  -- night run: a page read and confirmed before keeps its reading when a later read fails for a passing reason
  if p_read_status in ('fetch_failed', 'blocked', 'needs_render', 'too_thin', 'not_html') and v_row.read_status = 'read' and v_row.identity_basis is not null and v_row.evidence_id is not null then
    update pipeline.coverage_course_pages set http_status = p_http_status, leased_until = null, next_read_at = case when p_read_status = 'needs_render' then date_trunc('month', now()) + interval '1 month 1 hour' else now() + interval '7 days' end where course_id = p_course_id{sc}
    return jsonb_build_object('evidence_id', null, 'kept_previous_read', true, 'failed_as', p_read_status){sc}
  end if{sc}
$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59));
    v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

-- pages that lost their reading after a Platform Admin re-read tonight, put back from their stored copy
create table if not exists pipeline.reading_restores_20261005 as
  select pg.course_id, pg.provider_id, pg.read_status failed_as, e.id evidence_id, e.metadata->>'identity_basis' identity_basis, now() restored_at
    from pipeline.coverage_course_pages pg join pipeline.evidence_artifacts e on e.id = pg.evidence_id
   where pg.read_status in ('fetch_failed', 'blocked', 'needs_render', 'too_thin', 'not_html')
     and coalesce(e.metadata->>'identity_basis', '') <> '' and e.metadata->>'course_id' = pg.course_id::text and e.source_url = pg.url
     and exists (select 1 from pipeline.page_link_repairs r where r.course_id = pg.course_id and r.reason like 'read again by a Platform Admin%');
alter table pipeline.reading_restores_20261005 enable row level security;
revoke all on table pipeline.reading_restores_20261005 from anon, authenticated;

update pipeline.coverage_course_pages pg set read_status = 'read', identity_basis = x.identity_basis, candidates = jsonb_build_object('final_url', pg.url, 'restored_from_stored_copy', true), next_read_at = now() + interval '7 days', leased_until = null from pipeline.reading_restores_20261005 x where x.course_id = pg.course_id and pg.evidence_id = x.evidence_id and pg.read_status = x.failed_as;
