-- CF-247 (20 Oct 2026). Platform Admin 09:41 (capture of Layer 4 › Inbox, Adelaide course links): "on right of the Course name display the
-- Cricos code, otherwise what are we confirming and comparing, also the course name is align to course url, there should be no confusion.
-- What we hold is correct."
-- Found: the 5 Adelaide items propose a page for one major of the course (bachelor-of-journalism-creative-writing for Bachelor of
-- Journalism; bachelor-of-commerce-business-analytics while the page held is bachelor-of-commerce-property). The major pages print the
-- course's CRICOS code too, so the code alone cannot tell them apart.
-- Rule added to security.course_page_rule_v1 (Decision 263 page rules, md5-guarded): on the same site and folder, when the proposed page's
-- address is the held page's address with words added (a major or specialisation of it), the page held stays. The coverage sweep applies
-- it when it proposes a page, so these are no longer sent to a person. (Two different majors, as for Commerce, still go to a person.)
-- The 5 waiting Adelaide items are closed in Layer 4 › Inbox with the Platform Admin's decision ("What we hold is correct").
-- Replaces: security.course_page_rule_v1(text,text) (one case added; nothing else changes)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $chk$ begin
  if md5(pg_get_functiondef('security.course_page_rule_v1(text,text)'::regprocedure)) <> '53e4bcf49c72e0e29936f3c61f6045c4' then
    raise exception 'live security.course_page_rule_v1 differs from the definition this change replaces';
  end if;
end $chk$;

CREATE OR REPLACE FUNCTION security.course_page_rule_v1(p_held text, p_prop text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- Decision 263: which page wins when the coverage sweep proposes a different official course page; null = a person decides
  select case
    when p_prop is null or p_held is null then null
    when security.reference_url_has_use(p_prop, 'not_course_page') then 'keep:the proposed page is a course directory or search site, not the provider''s own site'
    when p_prop ~* '(^https?://handbook\.|programs-courses\.uq\.edu\.au)' and p_held !~* '(^https?://handbook\.|programs-courses\.uq\.edu\.au)'
      then 'keep:the provider''s course page stays official; the handbook page is a reference page'
    when p_prop ~* '(course-not-found|/index\.html$|find-a-study-option\.html$|/areas-of-study/|/postgraduate\.html$|/scholarships/|-minor/?$|/dom/?$)'
      then 'keep:the proposed page is a listing, not-found, scholarship, minor or domestic-only page'
    -- CF-247 20 Oct 2026 (Platform Admin "What we hold is correct"): a major or specialisation page of the course held
    when regexp_replace(rtrim(p_held, '/'), '/[^/]*$', '') = regexp_replace(rtrim(p_prop, '/'), '/[^/]*$', '')
         and lower(regexp_replace(rtrim(p_prop, '/'), '^.*/', '')) like lower(regexp_replace(rtrim(p_held, '/'), '^.*/', '')) || '-%'
      then 'keep:the proposed page is a major or specialisation of the course page held'
    when p_held ~* '^https?://handbook\.' and p_prop !~* '^https?://handbook\.'
         and substring(p_held from '^https?://handbook\.([^/]+)') = regexp_replace(substring(p_prop from '^https?://([^/]+)'), '^www\.', '')
      then 'take:the held page is the handbook; the provider''s course page showing the CRICOS code becomes official'
    when p_prop like rtrim(p_held, '/') || '/%' then 'take:the held page is a listing; the course''s own page under it becomes official'
    when substring(p_held from '^https?://([^/]+)') = substring(p_prop from '^https?://([^/]+)')
         and (regexp_match(p_held, '/(20[0-9]{2})/'))[1] < (regexp_match(p_prop, '/(20[0-9]{2})/'))[1]
         and lower(regexp_replace(rtrim(p_held, '/'), '^.*/', '')) = lower(regexp_replace(rtrim(p_prop, '/'), '^.*/', ''))
      then 'take:the same program code in a newer handbook year'
    else null end
$function$;
