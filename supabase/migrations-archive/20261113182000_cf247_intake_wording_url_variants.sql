-- CF-247 F-INT: the intake planner finds the stored intake wording of a course page under its trailing-slash variant or another of the provider's
-- own hosts (follow-up to 20261113181000, Pilot #1086; Platform Admin 12 Nov 2026 20:57 "proceed with all steps").
-- Found: after #1086 the E16 check passed for Southern Cross and Wollongong pages, and the planner stopped at "no stored reading of the page's intake
--   wording (month only)": security.intake_page_wording_v1 looks the course's read page up by exact address, and the intake's evidence address has a
--   trailing slash the read page has not (93 of 97 re-planned intakes in a 60-course run).
-- What:
--   1. md5-guarded text edit of security.intake_page_wording_v1: the page lookup (same course only) also matches
--      security.course_page_url_variants_v1. Nothing else changes.
--   2. Speed fix of 20261113181000 (measured live after it deployed): security.course_page_check_v1 called the variants helper once per stored page
--      of the provider (it depended on a column of the row being scanned), about 265 ms a check instead of about 50 ms; Rule B qualification of
--      Griffith timed out in it. Both lookups now take the variants from the function's own arguments once per call (an uncorrelated sub-select),
--      the same addresses as before. md5-guarded edit 554d95af... -> 38c776ca... (150 Griffith checks: 7.5 s). Rolled-back live trial on 40 such courses: 15 intakes dated, the rest held with their
--   real reason (no single calendar start, several periods, month only).
-- Guards: G1 (no job), G2 (no operational value), G3 (no consumer API object), G4 (cf-247-s539).
-- Replaces: security.intake_page_wording_v1 and security.course_page_check_v1 (same names; md5-guarded text edits, resulting md5 checked).
-- Retires: nothing.
-- Reversal: reverse the edits (bodies daa96acbe87de1cf0a2bec523a911c7a and 554d95af03219a28a2b7274914a46af6).

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.intake_page_wording_v1(uuid,uuid,text)', 'daa96acbe87de1cf0a2bec523a911c7a', 'eb380f591dc17bf536c94d999f4f1b26',
  array[$o$where g.course_id = p_course and (g.url = p_url or g.candidates->>'final_url' = p_url)$o$],
  array[$n$where g.course_id = p_course and (g.url = p_url or g.candidates->>'final_url' = p_url
                                       -- 12 Nov 2026 (F-INT): the same page with or without its trailing slash, or on another of the provider's own hosts
                                       or g.url = any ((select security.course_page_url_variants_v1(co.provider_id, p_url) from catalogue.courses co where co.id = p_course)::text[]))$n$]);

select pg_temp.edit_all('security.course_page_check_v1(uuid,text,text,text)', '554d95af03219a28a2b7274914a46af6', '38c776ca90378d866167390f7d40d42b',
  array[$o$or g.url = any (security.course_page_url_variants_v1(c.provider_id, p_url))) and g.read_status = 'read'$o$,
        $o$or g.url = any (security.course_page_url_variants_v1(t.provider_id, p_url)))$o$],
  array[$n$or g.url = any ((select security.course_page_url_variants_v1(co.provider_id, p_url) from catalogue.courses co where co.id = p_course)::text[]))
                      and g.read_status = 'read'$n$,
        $n$or g.url = any ((select security.course_page_url_variants_v1(co.provider_id, p_url) from catalogue.courses co where co.id = p_course)::text[]))$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_page_wording_v1(uuid,uuid,text)'::regprocedure)) <> 'eb380f591dc17bf536c94d999f4f1b26' then
    raise exception 'post-check: security.intake_page_wording_v1 does not have the recorded body'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.course_page_check_v1(uuid,text,text,text)'::regprocedure)) <> '38c776ca90378d866167390f7d40d42b' then
    raise exception 'post-check: security.course_page_check_v1 does not have the recorded body'; end if;
end $post$;
