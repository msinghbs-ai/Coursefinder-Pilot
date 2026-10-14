-- CF-247 (14 Oct 2026) Website API v2: course display code (Decision 255) for the website.
-- Canadian courses hold source IDs (portal GUIDs, page IDs, slugs) in course_code. The website needs the code a person reads:
-- the printed code where one exists, else the StudySearch code. Additive only: course items gain display_code,
-- display_code_kind (own or studysearch) and display_code_label. course_code is unchanged. The course action also finds a
-- course by its StudySearch code. md5-checked before. nothing is dropped or deleted.
do $d$
declare v text; n text;
begin
  v := pg_get_functiondef('api.website_v2_course_item(uuid,text[],text[])'::regprocedure);
  if md5(v) <> '3b9f4f5ddcb2413a13f38ac57418ace1' then raise exception 'website_v2_course_item changed since the check'; end if;
  n := replace(v, $o$'course_code', d.course_code,$o$,
                  $o$'course_code', d.course_code,
    'display_code', security.course_display_code_v1(d.course_id)->>'code',
    'display_code_kind', security.course_display_code_v1(d.course_id)->>'kind',
    'display_code_label', security.course_display_code_v1(d.course_id)->>'label',$o$);
  if n = v then raise exception 'course_item anchor not found'; end if;
  execute n;

  v := pg_get_functiondef('public.website_v2_course(text)'::regprocedure);
  if md5(v) <> 'a22d40c8274d118c6d67a8df91a2a81a' then raise exception 'website_v2_course changed since the check'; end if;
  n := replace(v, $o$from search.course_documents d where lower(d.course_stable_key)=lower(btrim(p_identifier)) or lower(d.course_code)=lower(btrim(p_identifier))$o$,
                  $o$from search.course_documents d where lower(d.course_stable_key)=lower(btrim(p_identifier)) or lower(d.course_code)=lower(btrim(p_identifier))
    or d.course_id in (select i.course_id from catalogue.course_identifiers i where i.scheme = 'studysearch' and upper(i.identifier) = upper(btrim(p_identifier)))$o$);
  n := replace(n, $o$   where lower(d.course_stable_key)=lower(btrim(p_identifier)) or lower(d.course_code)=lower(btrim(p_identifier))
   order by$o$,
                  $o$   where lower(d.course_stable_key)=lower(btrim(p_identifier)) or lower(d.course_code)=lower(btrim(p_identifier))
      or d.course_id in (select i.course_id from catalogue.course_identifiers i where i.scheme = 'studysearch' and upper(i.identifier) = upper(btrim(p_identifier)))
   order by$o$);
  if (length(n) - length(v)) < 200 then raise exception 'course anchors not found'; end if;
  execute n;
end $d$
