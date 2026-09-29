-- CF-247 top universities first, page reading (Platform Admin, 30 Sep 2026 03:05 IST). The 10 largest providers had
-- about 730 course pages that could not be read: sites that block plain fetches or render with script, on pages the
-- matcher marked "ambiguous" (more than one course could fit), which never used the Firecrawl fallback.
-- 1. svc_coverage_read_next marks pages of the 100 largest providers (pipeline.provider_priority) as priority and
--    picks them first; coverage-sweep v0.6.1 uses Firecrawl for priority pages too. Identity is unchanged: a page is
--    only accepted with the course's CRICOS code on it.
-- 2. Their blocked, needs-render and fetch-failed pages are queued again (attempts reset).
-- Edited in place from the live definition, only if unchanged (md5).
do $g$
declare d text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.svc_coverage_read_next(integer)'::regprocedure)<>'1d3496b1f17bb9fcdfa031485a3caa3d' then
    raise exception 'cf247_top_providers_read_priority: svc_coverage_read_next changed; review first';
  end if;
  d:=pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure);
  n:=replace(d,$s$select p.course_id, p.provider_id, p.status st, row_number() over (partition by p.provider_id order by (p.status<>'bound'), p.next_read_at) rk
      from pipeline.coverage_course_pages p$s$,$s$select p.course_id, p.provider_id, p.status st, coalesce(pp.rank,100000) prank, row_number() over (partition by p.provider_id order by (p.status<>'bound'), p.next_read_at) rk
      from pipeline.coverage_course_pages p left join pipeline.provider_priority pp on pp.provider_id=p.provider_id$s$);
  n:=replace(n,$s$pick as (select course_id from due where rk<=8 order by (st<>'bound'), rk, random()$s$,$s$pick as (select course_id from due where rk<=8 order by (prank>100), (st<>'bound'), rk, random()$s$);
  n:=replace(n,$s$'status',u.status)$s$,$s$'status',u.status,'priority',coalesce((select pp.rank<=100 from pipeline.provider_priority pp where pp.provider_id=u.provider_id),false))$s$);
  if position('prank' in n)=0 or position('''priority''' in n)=0 or position('order by (prank>100)' in n)=0 then raise exception 'read_next edit did not apply'; end if;
  execute n;
end $g$;

update pipeline.coverage_course_pages p set read_attempts=0, next_read_at=now(), leased_until=null
  from pipeline.provider_priority pp
 where pp.provider_id=p.provider_id and pp.rank<=100 and p.status in ('bound','ambiguous')
   and p.read_status in ('blocked','needs_render','fetch_failed');
