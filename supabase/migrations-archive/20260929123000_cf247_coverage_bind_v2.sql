-- CF-247 complete coverage, pilot findings (29 Sep 2026, Monash, UNSW, Sydney, UTS):
--  * recording a large provider's pages and binding in one call hit the statement timeout; binding is now a
--    separate step (cron 'coverage-bind', every 5 minutes, for providers mapped since their last binding);
--  * one page was bound to several courses (a "Master of Business" page to seven Master of Business ... courses):
--    binding is now one-to-one - a page is bound only when the course and the page are each other's clear best
--    match (lead >= 0.1 on both sides) or the page carries the course's CRICOS code; everything else is ambiguous;
--  * scoring is a word-level join (hash join on words) instead of array comparisons per pair.
alter table pipeline.coverage_provider_discovery add column if not exists bound_at timestamptz;

create or replace function security.coverage_bind_v2(p_provider_id uuid)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','security' as $f$
declare v_bound int; v_amb int;
begin
  drop table if exists _cb_c, _cb_u, _cb_s, _cb_best;
  create temp table _cb_c on commit drop as
    select co.id course_id, lower(co.course_code) code, security.coverage_text_tokens(co.canonical_title) tok
      from catalogue.courses co where co.provider_id=p_provider_id and co.lifecycle_status='active';
  create temp table _cb_u on commit drop as
    select url, title, tokens, title_tokens, cardinality(tokens) ns, cardinality(title_tokens) nt
      from pipeline.coverage_provider_urls where provider_id=p_provider_id;
  create temp table _cb_s on commit drop as
    with ct as (select course_id, cardinality(tok) nc, t from _cb_c, unnest(tok) t),
         ut as (select url, 's' k, ns n, t from _cb_u, unnest(tokens) t union all select url, 't', nt, t from _cb_u, unnest(title_tokens) t),
         m as (select ct.course_id, ut.url, ut.k, max(ct.nc) nc, max(ut.n) nu, count(*) hits from ct join ut using (t) group by 1,2,3)
    select course_id, url, max(2.0*hits/nullif(nc+nu,0)) sc, false by_code from m group by 1,2
    union all
    select c.course_id, u.url, 1.0, true from _cb_c c join _cb_u u
      on c.code is not null and length(c.code)>=6 and (position(c.code in lower(u.url))>0 or position(c.code in lower(coalesce(u.title,'')))>0);
  create temp table _cb_best on commit drop as
    with s as (select course_id, url, max(sc) sc, bool_or(by_code) by_code from _cb_s group by 1,2),
         rc as (select *, row_number() over (partition by course_id order by sc desc, length(url)) rk_c,
                          lead(sc) over (partition by course_id order by sc desc, length(url)) nxt_c,
                          row_number() over (partition by url order by sc desc) rk_u,
                          lead(sc) over (partition by url order by sc desc) nxt_u from s)
    select course_id, url, sc, coalesce(nxt_c,0) nxt, by_code,
           by_code or (sc>=0.8 and sc-coalesce(nxt_c,0)>=0.1 and rk_u=1 and sc-coalesce(nxt_u,0)>=0.1) mutual
      from rc where rk_c=1 and sc>=0.6;
  insert into pipeline.coverage_course_pages(course_id,provider_id,url,score,runner_up,basis,status,bound_at,next_read_at)
  select course_id, p_provider_id, url, round(sc,3), round(nxt,3), case when by_code then 'cricos_code' else 'title_match' end,
         case when mutual then 'bound' else 'ambiguous' end, now(), now()
    from _cb_best
  on conflict (course_id) do update set url=excluded.url, score=excluded.score, runner_up=excluded.runner_up, basis=excluded.basis,
         status=excluded.status, bound_at=now(),
         read_status=case when pipeline.coverage_course_pages.url is distinct from excluded.url then null else pipeline.coverage_course_pages.read_status end,
         next_read_at=case when pipeline.coverage_course_pages.url is distinct from excluded.url then now() else pipeline.coverage_course_pages.next_read_at end
   where pipeline.coverage_course_pages.status not in ('mismatch') or pipeline.coverage_course_pages.url is distinct from excluded.url;
  -- courses whose earlier binding no longer holds (page gone or no longer a mutual best) are released
  update pipeline.coverage_course_pages p set status='ambiguous'
   where p.provider_id=p_provider_id and p.status='bound'
     and not exists(select 1 from _cb_best b where b.course_id=p.course_id and b.url=p.url and b.mutual);
  update pipeline.coverage_provider_discovery set bound_at=now() where provider_id=p_provider_id;
  select count(*) filter (where status='bound'), count(*) filter (where status='ambiguous') into v_bound, v_amb from pipeline.coverage_course_pages where provider_id=p_provider_id;
  return jsonb_build_object('bound',v_bound,'ambiguous',v_amb);
end $f$;
revoke all on function security.coverage_bind_v2(uuid) from public, anon, authenticated;

create or replace function security.coverage_bind_tick_v1(p_limit int default 10)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare r record; v jsonb:='[]'::jsonb;
begin
  for r in select provider_id from pipeline.coverage_provider_discovery
            where mapped_at is not null and (bound_at is null or bound_at<mapped_at) order by mapped_at limit greatest(1,least(p_limit,50)) loop
    v:=v||jsonb_build_object('provider_id',r.provider_id,'result',security.coverage_bind_v2(r.provider_id));
  end loop;
  return v;
end $f$;
revoke all on function security.coverage_bind_tick_v1(int) from public, anon, authenticated;

-- Recording no longer binds in the same statement (checksum-guarded).
do $patch$
declare v_def text; v_old text:='  if p_status=''mapped'' then perform security.coverage_bind_v1(p_provider_id); end if;'||E'\n';
begin
  if (select md5(prosrc) from pg_proc where oid='public.svc_coverage_discovery_record(uuid,text,text,int,jsonb,text)'::regprocedure)<>'6fb567d6ab7163eb2d8015615a08a599' then
    raise exception 'svc_coverage_discovery_record changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('public.svc_coverage_discovery_record(uuid,text,text,int,jsonb,text)'::regprocedure);
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'bind anchor not found exactly once'; end if;
  execute replace(v_def,v_old,'');
end $patch$;

-- Queue also passes the provider's course count (used to decide on a second, course-focused map).
create or replace function public.svc_coverage_discovery_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.coverage_provider_discovery d
     where (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
     order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,
           'courses',(select count(*) from catalogue.courses c where c.provider_id=u.provider_id and c.lifecycle_status='active'))),'[]'::jsonb) into v from upd u;
  return v;
end $f$;
revoke all on function public.svc_coverage_discovery_next(int) from public, anon, authenticated;
grant execute on function public.svc_coverage_discovery_next(int) to service_role;

-- Pilot providers whose record timed out go back to the queue; Monash is re-bound under the new rule.
update pipeline.coverage_provider_discovery set status='pending', attempts=0, last_error=null where status='failed' and last_error like '%statement timeout%';
delete from pipeline.coverage_course_pages where provider_id in (select provider_id from pipeline.coverage_provider_discovery where status='mapped');
update pipeline.coverage_provider_discovery set status='pending', attempts=0, next_due_at=null where status='mapped';

select cron.schedule('coverage-bind','*/5 * * * *',$$select security.coverage_bind_tick_v1(10)$$);
