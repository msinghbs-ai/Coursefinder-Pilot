-- CF-247 (3 Oct 2026, 09:50 AEST). Correction to 20261003001100 (stored search results picked again). The generic
-- recipes keep any page on the university's site, so most of the 8,789 re-picked candidates are not course pages
-- (a login page, a graduation page): in the first hour 194 of 222 read were rejected by the identity rule, and most
-- were read through Firecrawl (the direct fetch was thin), at about 2,700 credits an hour against 17,000 left for
-- the month. Rapid admission plan, step 3: a course that fails a step is retried on a timetable, not dropped.
-- What this does, for re-picked pages not yet read: a candidate whose address shares no word of the course title
-- waits 30 days (by then the AI matcher has usually bound a better page, which replaces a search binding); one that
-- shares one word waits 7 days; two or more words are read now. Nothing is rejected without being read, nothing is
-- written to the catalogue, and no page bound by another method is touched.
with w as (
  select p.course_id, p.url,
         (select array_agg(w) from regexp_split_to_table(lower(regexp_replace(c.canonical_title, '[^A-Za-z0-9 ]', ' ', 'g')), '\s+') w
           where length(w) >= 4 and w not in ('bachelor','master','diploma','certificate','graduate','degree','advanced','associate','doctor','postgraduate','undergraduate','honours','level','program','programme','course','with','studies','major','science','arts','business','management')) words
    from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id
   where p.status = 'bound' and p.read_status is null and p.basis = 'title_search' and p.bound_at >= '2026-10-02 23:00+00'),
 scored as (select course_id, (select count(*) from unnest(words) x where lower(url) like '%' || x || '%') hits from w)
update pipeline.coverage_course_pages p
   set next_read_at = case when s.hits = 0 then now() + interval '30 days' else now() + interval '7 days' end
  from scored s where s.course_id = p.course_id and s.hits < 2 and p.status = 'bound' and p.read_status is null;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('requeue', 'defer', 'Re-picked search candidates whose address shares fewer than two title words wait 7 or 30 days',
        jsonb_build_object('why', 'first hour: 194 of 222 rejected, read through Firecrawl at about 2,700 credits an hour', 'rule', '0 title words in the address: 30 days; 1 word: 7 days; 2 or more: read now'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
