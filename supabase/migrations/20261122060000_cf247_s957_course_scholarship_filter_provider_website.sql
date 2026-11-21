-- CF-247 s957 (session S1-API-Frontend-Delivery, Lane 1 item 2, second part; India team review of 20 Nov 2026): two admin reads.
--
-- REQ-96 (defect): Courses › Has scholarship = Yes returned courses whose detail shows no scholarship. Read live 21 Nov 2026 23:15 AEDT: 3 of the
--   first 100 such courses (for example Edith Cowan, La Trobe College, Bond) show none, because the filter (public.ui_courses_decision_page)
--   counted any scholarship scope of the course or of its provider, published or not (the same rule in security.admin_course_page_fast_base,
--   security.admin_course_page_unfiltered_fast and public.ui_courses_decision_page); the course detail and the website show only the
--   published scholarships linked to the course. 13,571 courses passed the filter; the website's search record says 12,759 have one.
--   The filter and the Scholarships column now read the course's search record (search.course_documents.has_scholarship): the same
--   answer the website gives, so the filter, the column and the detail agree.
-- REQ-98: the course detail (public.admin_read 'course_detail') adds provider_website, the provider's website (read through the new
--   security definer helper security.course_provider_website_v1, as admin_read never reads schema catalogue itself), so the screen can
--   link to the institution and to the course page at the top of the detail.
-- Admin reads only: neither function is part of the consumer API (G3, checked before and after). Live on deploy. $0. G1: no job. G2: no value.
-- Parity: live head 20261122040000 read 21 Nov 2026 23:20 AEDT; this file is numbered strictly above it and above s956 (20261122050000).
-- Replaces: the scope-based has_scholarship of the Course catalogue.
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the post-check reads a page of courses

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s957_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s957_cron on commit drop as select count(*) n from cron.job where active;

-- regex edits of the live definition, guarded by its md5 before (and after, when known); each edit must apply exactly once
create or replace function pg_temp.edit_re(p_sig text, p_before text, p_after text, p_edits text[][]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_new text;
begin
  if p_after is not null and md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g')) <> 1 then
      raise exception '%: edit % must apply exactly once (found %)', p_sig, i, (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g'));
    end if;
    v_def := regexp_replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if p_after is not null and md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $f$;

-- REQ-96: has_scholarship from the course's search record
select pg_temp.edit_re('public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean,text)',
  '5e8e9f86c3e590f30fddb6b4ef118635', null, array[
  array[$o$select exists\(\s+select 1 from scholarship\.scopes ss\s+where coalesce\(ss\.include_exclude,'include'\)='include'\s+and \(ss\.course_id=c\.id or \(ss\.scope_type='provider' and ss\.provider_id=c\.provider_id\)\)\s+\) has_scholarship$o$,
        $n$select coalesce((select sd.has_scholarship from search.course_documents sd where sd.course_id=c.id), false) has_scholarship$n$]]);

-- REQ-96: the Course catalogue's own page reads (the filter and the Scholarships column), the same rule
select pg_temp.edit_re('security.admin_course_page_fast_base(jsonb)', 'aa88cb2bc090a1670cd7fd423e8cf0ca', null, array[
  array[$o$exists\(\s+select 1 from scholarship\.scopes ss\s+where coalesce\(ss\.include_exclude,'include'\)='include'\s+and \(ss\.course_id=c\.id or \(ss\.scope_type='provider' and ss\.provider_id=c\.provider_id\)\)\)=v_has_scholarship$o$,
        $n$coalesce((select sd.has_scholarship from search.course_documents sd where sd.course_id=c.id), false)=v_has_scholarship$n$],
  array[$o$select exists\(\s*select 1 from scholarship\.scopes ss\s+where coalesce\(ss\.include_exclude,'include'\)='include'\s+and \(ss\.course_id=pg\.id or \(ss\.scope_type='provider' and ss\.provider_id=pg\.provider_id\)\)\s*\) has_scholarship$o$,
        $n$select coalesce((select sd.has_scholarship from search.course_documents sd where sd.course_id=pg.id), false) has_scholarship$n$]]);
select pg_temp.edit_re('security.admin_course_page_unfiltered_fast(jsonb)', '5db669272a3fa612b1268ef8502a9b7c', null, array[
  array[$o$select exists\(\s*select 1 from scholarship\.scopes ss\s+where coalesce\(ss\.include_exclude,'include'\)='include'\s+and \(ss\.course_id=pg\.id or \(ss\.scope_type='provider' and ss\.provider_id=pg\.provider_id\)\)\s*\) has_scholarship$o$,
        $n$select coalesce((select sd.has_scholarship from search.course_documents sd where sd.course_id=pg.id), false) has_scholarship$n$]]);

-- REQ-98: the provider's website on the course detail. public.admin_read runs as the caller and never reads schema catalogue itself (s780),
-- so the website comes through a security definer helper, readable by every StudySearch role (the course detail already shows the provider).
create or replace function security.course_provider_website_v1(p_provider_id uuid) returns text
language sql stable security definer set search_path = '' as $f$
  select p.website from catalogue.providers p where p.id = p_provider_id and coalesce(security.current_role_rank(), 0) >= 1
$f$;
comment on function security.course_provider_website_v1(uuid) is 'CF-247 s957 (REQ-98): the website of a course''s provider for the course detail (public.admin_read course_detail); null for a caller with no StudySearch role.';
revoke all on function security.course_provider_website_v1(uuid) from public, anon;
grant execute on function security.course_provider_website_v1(uuid) to authenticated, service_role;
select pg_temp.edit_re('public.admin_read(text,jsonb)', '82cff726382fa3c80e627ceebd3523f3', null, array[
  array[$o$return v_result\|\|jsonb_build_object\('fee_summary',security\.admin_course_fee_summary\(v_id\)\)$o$,
        $n$return v_result||jsonb_build_object('provider_website',security.course_provider_website_v1(nullif(v_result->>'provider_id','')::uuid))||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))$n$]]);

do $c$
declare v_api jsonb := security.consumer_api_check_v1(); v_def text;
begin
  v_def := pg_get_functiondef('public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean,text)'::regprocedure);
  if position('from search.course_documents sd where sd.course_id=c.id), false) has_scholarship' in v_def) = 0 then raise exception 'post-check: the scholarship filter is not the search record'; end if;
  if (select count(*) from regexp_matches(pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure) || pg_get_functiondef('security.admin_course_page_unfiltered_fast(jsonb)'::regprocedure), 'scholarship\.scopes', 'g')) <> 0 then raise exception 'post-check: a catalogue page still counts scholarship scopes'; end if;
  if position('''provider_website''' in pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: course_detail has no provider_website'; end if;
  if (select count(*) from cron.job where active) <> (select n from s957_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s957_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
