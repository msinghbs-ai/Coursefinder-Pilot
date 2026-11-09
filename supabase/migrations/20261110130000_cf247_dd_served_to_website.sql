-- CF-247 F-CDESC Data Delivery, root-cause fix (Platform Admin, 10 Nov 2026): the course description stage "Described courses published to the Website" counted search.course_documents.publication_status = 'published',
-- and "unpublished (not served to the Website)" counted the rest. That is not what the Website reads. The Website consumer API (public.website_v2_course and website_v2_course_search, through
-- api.website_v2_course_item) serves every course in search.course_documents unless its provider is hidden (security.provider_hidden_v1); the course's own publication_status flag does not decide it.
-- Layer 4 can also block a course (security.layer4_search_blocked_courses). Live proof, 10 Nov 2026: website_v2_course_search total = 34,041 while only 10 courses carry the flag 'published';
-- all 145 machine-admitted courses are served with matching text; all 308 described courses are in the served set.
-- The change: the one CTE `shown` in security.data_delivery_cdesc_stages_v1() now takes the course documents whose provider is not in provider_hidden_v1 (column provider_id) and whose course is not in
-- layer4_search_blocked_courses (column course_id). The JSON keys website_published and unpublished_course are kept (the screen and the tests read them); their meaning is now "served to the Website"
-- and "not served (provider hidden or blocked in Layer 4)". Nothing else in the function changes. The function is read only and Admin only (revoked from public, anon, authenticated).
-- Live definition (pg_proc.prosrc md5, read 10 Nov 2026, project fxcwkweaxjtknorudmwp), original -> edited:
--   security.data_delivery_cdesc_stages_v1()  eeb3d57c652c66d3f11f38c4de44068b -> d2a913a4d294f71fadf949bff6786f94
-- Forward recovery (the original body, byte for byte): supabase/held/dd_served_to_website_forward_recovery.sql.
-- The consumer API (G3) is not touched: no public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, api.* object, table column or edge function changes; they, the course
-- documents and the two views are only read. No setting value changes, nothing is switched on or off, nothing is dropped or deleted. No number is added to the code (G2).
-- Replaces: security.data_delivery_cdesc_stages_v1 is edited in place (md5-guarded, md5 eeb3d57c652c66d3f11f38c4de44068b -> d2a913a4d294f71fadf949bff6786f94, one CTE); otherwise nothing
-- Retires: nothing

do $g$ declare s text; begin
  foreach s in array array['security.data_delivery_cdesc_stages_v1()', 'security.provider_hidden_v1', 'security.layer4_search_blocked_courses'] loop
    if s like '%()' then
      if to_regprocedure(s) is null then raise exception 'required % is missing (apply 20261110100000 first)', s; end if;
    elsif to_regclass(s) is null then raise exception 'required % is missing', s; end if;
  end loop;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the md5-guarded edit
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.data_delivery_cdesc_stages_v1()', 'eeb3d57c652c66d3f11f38c4de44068b', 'd2a913a4d294f71fadf949bff6786f94',
     array[$o$shown as (select d.course_id from search.course_documents d where d.publication_status = 'published' and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id)),$o$],
     array[$n$shown as (select d.course_id from search.course_documents d where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id) and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id)), -- served to the Website: every course document whose provider is not hidden and that Layer 4 does not block; the course's own publication_status is not what the Website reads$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then continue; end if; -- already applied
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
  end loop;
end $m$;

do $post$ begin
  if position('provider_hidden_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_cdesc_stages_v1()'::regprocedure)) = 0 then raise exception 'post-check: the served set must read the hidden providers'; end if;
  if position('publication_status = ''published''' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_cdesc_stages_v1()'::regprocedure)) > 0 then raise exception 'post-check: the course flag must no longer decide what is served'; end if;
end $post$;
