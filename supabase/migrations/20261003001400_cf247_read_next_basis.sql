-- CF-247 (3 Oct 2026, 10:10 AEST). Rapid admission plan, step 3, after the two corrections of 20261003001300/001310:
-- the reader is told how a page was bound ('basis') so that a search candidate — picked by a URL recipe, often not the
-- course's page — is read directly only and never rendered through Firecrawl. The matcher's pages and pages entered
-- by hand keep the rendered fallback. The md5 guard confirms the live function is the one this replaces.
do $g$ begin
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'svc_coverage_read_next') is distinct from '25caf5f62fe8e6975730dbc42ad63e97'
  then raise exception 'svc_coverage_read_next changed; not replacing'; end if;
end $g$;
create or replace function public.svc_coverage_read_next(p_limit integer)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline' as $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with due as (
    select p.course_id, p.provider_id, p.status st, coalesce(pp.rank,100000) prank, coalesce(cp.sort,1000000) csort, row_number() over (partition by p.provider_id order by (p.status<>'bound'), p.next_read_at) rk
      from pipeline.coverage_course_pages p left join pipeline.provider_priority pp on pp.provider_id=p.provider_id left join pipeline.course_priority cp on cp.course_id=p.course_id
     where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3),
  pick as (select course_id from due where rk<=8 order by csort, least(prank,101), (st<>'bound'), rk, random() limit greatest(1,least(coalesce(p_limit,20),60))),
  upd as (update pipeline.coverage_course_pages p set leased_until=now()+interval '10 minutes', read_attempts=p.read_attempts+1
            from pick where p.course_id=pick.course_id returning p.course_id, p.provider_id, p.url, p.status, p.basis)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'provider_id',u.provider_id,'url',u.url,'title',c.canonical_title,'code',c.course_code,'country',security.coverage_country(u.provider_id),'status',u.status,'basis',u.basis,'manual',coalesce(u.basis='manual',false),'priority',coalesce((select pp.rank<=100 from pipeline.provider_priority pp where pp.provider_id=u.provider_id),false) or exists (select 1 from pipeline.course_priority cp where cp.course_id=u.course_id))),'[]'::jsonb)
    into v from upd u join catalogue.courses c on c.id=u.course_id;
  return v;
end $function$;
-- the search candidates deferred at 09:50 and 09:55 are read now, directly only
update pipeline.coverage_course_pages p
   set next_read_at = now()
 where p.status = 'bound' and p.read_status is null and p.basis = 'title_search' and p.bound_at >= '2026-10-02 23:00+00' and p.next_read_at > now();
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('requeue', 'release', 'Re-picked search candidates read now, directly only (no rendered fallback for a search candidate)',
        jsonb_build_object('worker', 'coverage-sweep-worker-v0.13.4', 'direction', 'Platform Admin 3 Oct 2026 08:17 (rapid admission plan, step 3)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
