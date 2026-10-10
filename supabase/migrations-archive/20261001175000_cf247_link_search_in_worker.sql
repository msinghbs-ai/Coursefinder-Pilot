-- CF-247 (Decision 204): course-link search runs in the coverage-sweep worker (mode "link_search"), not through the
-- database's outbound queue. Measured on 1 Oct 2026: pg_net sends requests in rounds of 200 and each round waits for
-- its slowest call; at 80 Firecrawl searches a minute the queue stalled for about 4 minutes and the coverage workers,
-- which are called through the same queue, waited behind it. The worker runs a bounded number of searches in parallel
-- (6 by default) and records each result through the same rules as before:
--   public.svc_course_link_search_next(limit)  picks queued searches (inside the monthly allowance) and marks them sent;
--   public.svc_course_link_search_record(...)  applies one result: pick candidates with the provider's recipe, bind the
--                                               first for the reader, move to the title search, or mark not found.
-- pipeline.course_link_search_settings.send_via says who sends: 'pg_net' (the old tick) or 'worker'. It stays 'pg_net'
-- in this migration; it is switched once the worker is verified live. A search lost by the worker is sent again after
-- 20 minutes by the existing tick rule. Usage is recorded per search (2 credits) under 'course_link_search' as before.

alter table pipeline.course_link_search_settings add column if not exists send_via text not null default 'pg_net';
do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'course_link_search_settings_send_via_check') then
    alter table pipeline.course_link_search_settings add constraint course_link_search_settings_send_via_check check (send_via in ('pg_net','worker'));
  end if;
end $c$;

create or replace function public.svc_course_link_search_next(p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_on boolean; v_cap numeric; v_used numeric; v_lim int := greatest(1, least(coalesce(p_limit, 40), 200)); v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if not coalesce(v_on, false) or v_used + 2 * v_lim > v_cap then return '[]'::jsonb; end if;
  with pick as (
    select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
      from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
      join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
      left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
     where s.state = 'queued'
     order by (s.stage <> 'cricos'), coalesce(pp.rank, 100000), md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
     limit v_lim
     for update of s skip locked),
  upd as (
    update pipeline.course_link_search s set state = 'sent', sent_at = now(), req_id = null,
           query = case p.stage when 'cricos' then '"' || p.course_code || '" site:' || p.search_domain
                                else '"' || replace(p.canonical_title, '"', '') || '" site:' || p.search_domain end
      from pick p where s.course_id = p.course_id
    returning s.course_id, s.provider_id, s.stage, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'provider_id', provider_id, 'stage', stage, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $fn$;
revoke all on function public.svc_course_link_search_next(int) from public, anon, authenticated;
grant execute on function public.svc_course_link_search_next(int) to service_role;

create or replace function public.svc_course_link_search_record(p_course_id uuid, p_http int, p_urls text[], p_error text default null) returns text
language plpgsql security definer set search_path = '' as $fn$
declare r pipeline.course_link_search%rowtype; v_c text[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.course_link_search where course_id = p_course_id and state = 'sent' for update;
  if r.course_id is null then return 'not_sent'; end if;
  -- the worker ran out of time or credits before searching: back in the queue, no attempt counted
  if p_error in ('time budget', 'credit budget') then
    update pipeline.course_link_search set state = 'queued' where course_id = p_course_id;
    return 'requeued';
  end if;
  if p_http = 200 then
    v_c := security.course_link_pick_v1(r.provider_id, coalesce(p_urls, '{}'));
    if cardinality(v_c) > 0 then
      update pipeline.course_link_search set state = 'found', results = to_jsonb(p_urls), candidates = to_jsonb(v_c), cand_idx = 1,
             bound_url = v_c[1], done_at = now() where course_id = p_course_id;
      perform security.course_link_bind_v1(p_course_id, r.provider_id, v_c[1], case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
      return 'found';
    elsif r.stage = 'cricos' then
      update pipeline.course_link_search set stage = 'title', state = 'queued', results = to_jsonb(p_urls), attempts = 0 where course_id = p_course_id;
      return 'title_next';
    else
      update pipeline.course_link_search set state = 'none', results = to_jsonb(p_urls), done_at = now() where course_id = p_course_id;
      return 'none';
    end if;
  end if;
  update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= 3 then 'error' else 'queued' end,
         results = jsonb_build_object('http_status', p_http, 'body', left(coalesce(p_error, ''), 300))
   where course_id = p_course_id;
  return 'failed';
end $fn$;
revoke all on function public.svc_course_link_search_record(uuid, int, text[], text) from public, anon, authenticated;
grant execute on function public.svc_course_link_search_record(uuid, int, text[], text) to service_role;

-- The old tick stops sending when the worker sends (collection of in-flight pg_net searches and candidate moves continue).
do $tick$
declare s text; d text; v text;
  o text := '  if v_on and v_used + 2 * p_batch <= v_cap then';
  n text := '  if v_on and coalesce((select x.send_via from pipeline.course_link_search_settings x where x.id = 1), ''pg_net'') = ''pg_net'' and v_used + 2 * p_batch <= v_cap then';
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'course_link_search_tick_v1';
  v := md5(s);
  if v is distinct from 'ab94cc87e67ecf30cb35fac0c977161f' then raise exception 'course_link_search_tick_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'course_link_search_tick_v1: send condition not found once'; end if;
  execute replace(d, o, n);
end $tick$;
