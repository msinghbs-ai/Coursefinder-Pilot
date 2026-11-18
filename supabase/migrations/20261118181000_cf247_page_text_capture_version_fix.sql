-- CF-247 page-text (Pilot #1252): a newer stored copy of a course page gets the next capture version, not a duplicate key (S2-Build;
-- Platform Admin 18 Nov 2026 14:23, "the Pilot #1252 shared-page evidence key fix").
--
-- What was read live (18 Nov 2026 14:35 AEDT): pipeline.page_text_conversions holds 3,378 done, 2 too short and 179 failed with "duplicate key
-- value violates unique constraint layer2_evidence_group_capture_version_uq". public.svc_page_text_record_v1 wrote every text copy as capture
-- version 1 of group coverage:<course>; a course whose page was stored again (a newer source snapshot) already had version 1 from the earlier
-- copy, so the newer text could not be recorded. Each failed copy waits a day and fails the same way again.
--
-- What it changes: the text copy is recorded as the next capture version of its course's group (one writer per course at a time), so the
-- newer copy is kept beside the older one, with its own derived_from_evidence_id. The 179 failed copies are made due again now (their retry
-- clock is moved back past the one-day wait); nothing is deleted.
-- Nothing is dropped or deleted. G3 untouched.
-- Replaces: the fixed capture version 1 of page-text copies in public.svc_page_text_record_v1.
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

select pg_temp.cf_edit('public.svc_page_text_record_v1(uuid,text,text,text,integer,text)'::regprocedure, '53505fc60cca2fc38075ecdd74f60b38',
  $o$              1, 'coverage:' || x.course_id)$o$,
  $n$              (select coalesce(max(t2.capture_version), 0) + 1 from pipeline.evidence_artifacts t2 where t2.evidence_group_key = 'coverage:' || x.course_id), 'coverage:' || x.course_id)$n$,
  $m$select coalesce(max(t2.capture_version), 0) + 1$m$);

select pg_temp.cf_edit('public.svc_page_text_record_v1(uuid,text,text,text,integer,text)'::regprocedure,
  md5((select p.prosrc from pg_proc p where p.oid = 'public.svc_page_text_record_v1(uuid,text,text,text,integer,text)'::regprocedure)),
  $o$    if v_ev is null then
      insert into pipeline.evidence_artifacts$o$,
  $n$    if v_ev is null then
      perform pg_advisory_xact_lock(hashtext('coverage:' || x.course_id));  -- fixed: one capture version at a time for a course
      insert into pipeline.evidence_artifacts$n$,
  $m$perform pg_advisory_xact_lock(hashtext('coverage:' || x.course_id));$m$);

-- the copies that failed on the duplicate key are due again now (their next try waited a day from claimed_at)
update pipeline.page_text_conversions
   set claimed_at = now() - interval '1 day' - interval '1 minute'  -- fixed: just past the one-day retry wait of svc_page_text_next_v1
 where outcome = 'failed' and error like '%layer2_evidence_group_capture_version_uq%';

do $e$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
end $e$;
