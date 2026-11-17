-- CF-247 defect E15 (Platform Admin overnight mandate 1 Nov 2026 22:01; record §36.1): "Use the new page" makes the reviewer's page THE course page.
-- Why: security.layer4_course_link_apply_impl (Layer 4 course link, field official_course_url; "Use the new page" = approve, "Enter another
--   address" = edit_and_approve) inserted the approved page as one more active, non-primary official link and never retired the course's
--   previous official page. 30 Oct 2026: 17 approved course-link decisions; 15 courses now hold two active official pages (the old sweep page
--   and the reviewer's), and the website shows the reviewer's page only because its last_verified_at is newer (any re-read of the old page
--   would flip it back). For Waikato WI0194 and MITO 4226 the course page had been set by hand on the course record at 08:50 (manual locks
--   official_url and course_url); the manual-lock guard (security.manual_fact_guard, BEFORE trigger returning null) skipped the insert
--   without an error at 12:43, so both decisions were recorded "approved" and nothing changed.
-- What (one function, md5-guarded):
--   * A course whose page was set by hand (pipeline.manual_locks official_url or course_url) is refused with a plain message; the decision is
--     not recorded. The existing lock rule stands: a hand-set value is changed on the course record (public.admin_course_edit set_official_url),
--     which already supersedes pending Layer 4 link items (security.manual_close_layer4). Same wording as the fee-check guard in
--     public.admin_layer4_inbox: "a different course page is set on the course record".
--   * The course's other active official links become 'inactive' and not primary (allowed by course_links_status_check; nothing deleted,
--     the rows stay for history), the approved page is active and primary (the website's choice orders by is_primary first), and
--     catalogue.courses.course_url follows the approved page, as a page set on the course record does.
--   * If a guard still skips the row (no link id returned) the decision is refused instead of being recorded as applied.
--   * "Keep the page we hold" (reject) is unchanged: nothing is written. Fee items (provider_current_tuition, ..._validation) do not reach this
--     function, so the fee-check guards in public.admin_layer4_inbox are unchanged.
-- Before: e97b56cc87d02c4886df39918027eecc. After: 75a53dbbcd5e20e1018a05b61f6763aa (dry run in a rolled-back transaction, 1 Nov 2026 11:17 UTC; live unchanged afterwards).
-- Rollback: re-apply the before definition (the same edits reversed). Links already made inactive by a decision stay inactive; reactivating
--   one is a data change for the Platform Admin.
-- The six courses decided on 30 Oct are repaired separately by a count-guarded paste file (Platform Admin), not by this migration.
-- Replaces: security.layer4_course_link_apply_impl (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3): the website keeps reading search.course_documents.official_course_url, which is
--   built from the active links. No setting (G2): a rule, not a value.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)', 'e97b56cc87d02c4886df39918027eecc', '75a53dbbcd5e20e1018a05b61f6763aa', array[
 array[$o$declare v_item pipeline.layer4_review_items%rowtype; v_url text; v_host text; v_link uuid;$o$,
       $n$declare v_item pipeline.layer4_review_items%rowtype; v_url text; v_host text; v_link uuid; v_retired int := 0;$n$],
 array[$o$  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values (v_item.entity_id,'official_course',v_url,'international','Official provider course page (confirmed by reviewer)',false,'active',$o$,
       $n$  -- E15 (Platform Admin 1 Nov 2026 22:01): a page set by hand is changed on the course record; the lock guard skipped this row silently
  if exists (select 1 from pipeline.manual_locks l where l.entity='course' and l.entity_id=v_item.entity_id and l.field in ('official_url','course_url')) then
    raise exception 'this course''s page was set by hand on the course record: change it there (course detail, official page), or keep the page we hold';
  end if;
  -- E15: the approved page replaces the course's other official pages (inactive, kept for history), so the course has one course page
  update catalogue.course_links set status='inactive',is_primary=false,updated_at=now()
   where course_id=v_item.entity_id and link_type='official_course' and status='active' and url<>v_url;
  get diagnostics v_retired = row_count;
  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values (v_item.entity_id,'official_course',v_url,'international','Official provider course page (confirmed by reviewer)',true,'active',$n$],
 array[$o$  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',source_id=excluded.source_id,confidence=1,last_verified_at=now(),updated_at=now()
  returning id into v_link;$o$,
       $n$  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',is_primary=true,source_id=excluded.source_id,confidence=1,last_verified_at=now(),updated_at=now()
  returning id into v_link;
  -- E15: a guard that skips the row leaves no link; the decision is refused rather than recorded as applied
  if v_link is null then raise exception 'the course page was not saved (a guard on the course''s links refused it); nothing was changed'; end if;
  -- E15: the course record follows the approved page, as a page set on the course record does
  update catalogue.courses set course_url=v_url,updated_at=now() where id=v_item.entity_id and course_url is distinct from v_url;$n$],
 array[$o$  return jsonb_build_object('course_link_id',v_link,'url',v_url,'search_refreshed',true);$o$,
       $n$  return jsonb_build_object('course_link_id',v_link,'url',v_url,'search_refreshed',true,'superseded_links',v_retired);$n$]],
 array[1,1,1,1]);
