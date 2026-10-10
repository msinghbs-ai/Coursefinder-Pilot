CREATE OR REPLACE FUNCTION public.svc_coverage_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
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
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'provider_id',u.provider_id,'url',u.url,'title',c.canonical_title,'code',c.course_code,'country',security.coverage_country(u.provider_id),'status',u.status,'basis',u.basis,'manual',coalesce(u.basis='manual',false),'rendered_before',(exists (select 1 from pipeline.coverage_course_pages q where q.course_id=u.course_id and q.fetched_via='firecrawl') or exists (select 1 from pipeline.page_link_repairs x where x.course_id=u.course_id and x.reason like 'university adapter: international view read%')),'priority',coalesce((select pp.rank<=100 from pipeline.provider_priority pp where pp.provider_id=u.provider_id),false) or exists (select 1 from pipeline.course_priority cp where cp.course_id=u.course_id))),'[]'::jsonb)
    into v from upd u join catalogue.courses c on c.id=u.course_id;
  return v;
end $function$
