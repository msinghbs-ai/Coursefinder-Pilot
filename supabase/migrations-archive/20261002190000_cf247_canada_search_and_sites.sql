-- CF-247 (2 Oct 2026, 23:10 AEST). Platform Admin, 22:50: "once uni website is acquired, finding sitemap and courses
-- page should be smooth". Canada had 163 verified course pages of 2,382 because:
--  * the course search used our catalogue title as an exact phrase ("Medical Genetics: Doctor of Philosophy (PhD) -
--    UBCV"), which never appears on the university's site: 2,003 Canadian searches found nothing;
--  * 8 Canadian universities had no website: the rule needed the full name in the home page title or heading.
-- 1. Canadian course searches use the title's words without quotes, brackets, colons or campus suffixes
--    ("Medical Genetics Doctor of Philosophy site:ubc.ca"). Other countries are unchanged. md5 guard.
-- 2. Canadian searches that found nothing are queued again (courses open to international students first through the
--    usual order). The monthly search credit cap (50,000) is unchanged; the queue stops when it is reached.
-- 3. Website hints rejected by worker v0.10.2 and v0.10.3 are offered again for the new website rule (Decision 235:
--    the full name anywhere on the home page when the address fits the name). md5 guard.
-- Nothing is admitted by this migration; pages found are read and checked by the identity rule as before.
do $p$
declare s text; d text;
  o1 text := $o$else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end$o$;
  n1 text := $n$else case when security.coverage_country(p.provider_id) = 'CA'
                                     then trim(regexp_replace(regexp_replace(regexp_replace(p.canonical_title, '\s*\([^)]*\)', ' ', 'g'), '\s+-\s+(UBCV|UBCO|Major|Honours|Open Learning)\M.*$', '', 'i'), '[:"]+', ' ', 'g')) || ' site:' || p.search_domain
                                     else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end end$n$;
  o2 text := $o$not in ('coverage-sweep-worker-v0.10.0', 'coverage-sweep-worker-v0.10.1')$o$;
  n2 text := $n$not in ('coverage-sweep-worker-v0.10.0', 'coverage-sweep-worker-v0.10.1', 'coverage-sweep-worker-v0.10.2', 'coverage-sweep-worker-v0.10.3')$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p where p.proname = 'svc_course_link_search_next';
  if md5(s) is distinct from '4165a4e5553a729301ff6fac7cdef0c2' then raise exception 'svc_course_link_search_next changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'search piece not found once'; end if;
  execute replace(d, o1, n1);
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p where p.proname = 'svc_site_hint_next';
  if md5(s) is distinct from 'c710bab9dc476c1674ab29f1bfed9eae' then raise exception 'svc_site_hint_next changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'hint piece not found once'; end if;
  execute replace(d, o2, n2);
end $p$;

update pipeline.course_link_search s
   set state = 'queued', attempts = 0, results = null
 where s.state = 'none' and s.stage = 'title' and security.coverage_country(s.provider_id) = 'CA'
   and not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = s.course_id and p.read_status = 'read');
