-- CF-247 Decision 253 (4 Oct 2026). The Flinders better-page run found study pages for 71 courses. Read so far, 23 of
-- 26 did not print the course's own CRICOS code: double degrees, combined and discontinued courses have no study page
-- of their own, and search returned a related one (Bachelor of Laws for a Laws and Finance double degree). The identity
-- check refused them correctly, but each had replaced a confirmed handbook page. From now on a better page refused by
-- the identity check is undone: the earlier page is bound again and read again (schedule better-page-revert, every 5
-- minutes). Values already admitted from the earlier page were never removed. Logged in pipeline.page_link_repairs.
-- No text value in this file contains a semicolon.

create or replace function security.better_page_revert_v1() returns int
language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0;
begin
  for r in
    select pg.course_id, pg.provider_id, pg.url,
           (select x.old_url from pipeline.page_link_repairs x where x.course_id = pg.course_id and x.reason = 'firecrawl search: page with the fields the adapter reads' order by x.id desc limit 1) old_url
      from pipeline.coverage_course_pages pg
     where pg.basis = 'firecrawl_upgrade' and pg.read_status = 'identity_mismatch'
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = pg.course_id and k.field = 'official_url')
  loop
    continue when r.old_url is null or r.old_url = r.url;
    insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
      values (r.course_id, r.provider_id, r.url, r.old_url, 'better page refused by the identity check: earlier page bound again');
    update pipeline.coverage_course_pages set url = r.old_url, basis = 'better_page_reverted', status = 'bound', bound_at = now(), read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now() where course_id = r.course_id and basis = 'firecrawl_upgrade';
    n := n + 1;
  end loop;
  return n;
end $f$;
revoke all on function security.better_page_revert_v1() from public, anon, authenticated;

select security.better_page_revert_v1();
select cron.schedule('better-page-revert', '*/5 * * * *', $c$select security.better_page_revert_v1()$c$);
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values ('better-page-revert', 2, now()) on conflict (jobname) do nothing;
