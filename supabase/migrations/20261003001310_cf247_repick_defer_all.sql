-- CF-247 (3 Oct 2026, 09:55 AEST). Second correction to 20261003001100. Even candidates sharing two or more title
-- words were mostly not the course's page (305 of 408 read in 15 minutes rejected), and the reader rendered them
-- through Firecrawl at about 6,700 credits an hour, which would empty the month's remaining 16,500 credits before
-- noon. All re-picked search candidates not yet read now wait 7 days; they are read again only once the reader
-- can read a search candidate directly without a rendered fallback (a worker change after the meeting). Pages bound
-- by the AI matcher are not touched. Nothing is rejected unread.
update pipeline.coverage_course_pages p
   set next_read_at = now() + interval '7 days'
 where p.status = 'bound' and p.read_status is null and p.basis = 'title_search' and p.bound_at >= '2026-10-02 23:00+00' and p.next_read_at <= now();
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('requeue', 'defer', 'All unread re-picked search candidates wait 7 days (Firecrawl burn about 6,700 credits an hour)',
        jsonb_build_object('why', '305 of 408 read in 15 minutes rejected, rendered through Firecrawl', 'next', 'read search candidates directly only, then release'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
