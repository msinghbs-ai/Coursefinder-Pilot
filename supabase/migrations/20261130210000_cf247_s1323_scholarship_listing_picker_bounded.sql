-- CF-247 s1323 (S1-Build; SS-Programme-Control 27 Nov 2026 21:08 AEDT item 5, "Continue scholarship dispatcher recovery. The picker is
-- operating too close to its statement timeout"; decision D12 approved by the Platform Admin 27 Nov 2026: free listing reads for providers held
-- only by the paid cap).
-- Measured live 27 Nov 2026 22:10 AEDT (rolled back): 72 providers have due listing pages. public.svc_scholarship_listing_next took 6.7 s of
-- its 8 s call limit and returned no page: security.fc_sch_held_v1 (paid cap and discovery eligibility) held all 72 (3.6 s), so every
-- lane call since 17:09 spent its time and read nothing new from the due list. The discovery eligibility rule alone (security.fc_sch_listing_held_v1,
-- s1313, kept unused) releases 27 providers with 362 due pages and took 1.6 s for all 72; s1313 failed because that check ran for every
-- provider at once under load (12.9 s).
-- The change (bounded, D12): the picker checks providers one at a time in the order of their first due page and stops as soon as it holds
-- the call's pages or its time budget is used (a fixed fire guard), so its cost no longer grows with the number of providers or the load. A
-- provider is skipped when hidden or held by the discovery eligibility rule; a provider held only by the paid cap gets its free listing read.
-- Every paid scrape is still refused by public.svc_fc_spend (daily budget, per-university cap, DR-15 eligibility, reserve), which the worker
-- calls before any Firecrawl request. Third-party hosts, the lease (15 minutes), the page order within a provider, the limit and the output
-- are unchanged.
-- G1: no job. G2: scholarship.listing_max as before; the time budget is a fire guard. G3: 75/48 checked. Locks and cron checked. $0.
-- Replaces: public.svc_scholarship_listing_next (md5 dc3b6885; the whole body, same signature and output).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replacement

create temp table s1323_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) <> 'dc3b688512a12d5bbf3ed16eecdbd796' then
    raise exception 'pre-check: public.svc_scholarship_listing_next is not the definition this change replaces';
  end if;
  if to_regprocedure('security.fc_sch_listing_held_v1(uuid)') is null then raise exception 'pre-check: security.fc_sch_listing_held_v1 (s1313) is missing'; end if;
end $pre$;

create or replace function public.svc_scholarship_listing_next(p_limit integer) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v jsonb;
  v_lim int := greatest(1, least(coalesce(p_limit, 6), security.pipeline_num_v1('scholarship.listing_max', 20)::int));
  v_t0 timestamptz := clock_timestamp();
  v_prov uuid[] := '{}';
  v_pages int := 0;
  r record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- s1323 (27 Nov 2026, D12): providers one at a time, in the order of their first due page, until the released providers hold the call's pages
  -- or the time is used; then the same global order as before among the released providers' pages
  for r in select l.provider_id, min(coalesce(l.next_read_at, '-infinity'::timestamptz)) first_due, count(*) due_pages
             from pipeline.scholarship_listing_pages l
            where l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()
            group by l.provider_id order by 2, 1 loop
    exit when v_pages >= v_lim;
    exit when clock_timestamp() - v_t0 > interval '2500 milliseconds';  -- fixed: fire guard, the picker stays well inside the 8 s call limit
    continue when r.provider_id is null;
    continue when exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id);
    continue when security.fc_sch_listing_held_v1(r.provider_id);
    v_prov := v_prov || r.provider_id; v_pages := v_pages + r.due_pages;
  end loop;
  with pick as (
    select l.id from pipeline.scholarship_listing_pages l
     where l.provider_id = any (v_prov) and l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()
       and not security.third_party_host_v1(l.url)
     order by l.next_read_at nulls first, l.id limit v_lim for update skip locked),
  upd as (
    update pipeline.scholarship_listing_pages l set next_read_at = now() + interval '15 minutes' from pick where l.id = pick.id  -- fixed: claim lease
    returning l.id, l.provider_id, l.url, l.next_url, l.page_state)
  -- CF-247 scholarship recovery F6: a partly read catalogue continues from the address it stopped at
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url, 'next_url', case when u.page_state = 'partial' then u.next_url end,
           'hosts', (select to_jsonb(coalesce(d.allowed_hosts, '{}') || array[regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '')])
                       from pipeline.scholarship_discovery_providers d where d.provider_id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$;
comment on function public.svc_scholarship_listing_next(integer) is 'CF-247 s1323 (D12): leases the next due scholarship listing pages. Providers are checked one at a time in the order of their first due page (hidden, discovery eligibility; a provider held only by the paid cap gets its free read, every paid scrape is still refused by svc_fc_spend), stopping when the call''s pages are held or its 2.5 s budget is used. Third-party hosts, the 15-minute lease, the order and the output as before.';
revoke all on function public.svc_scholarship_listing_next(integer) from public, anon, authenticated;
grant execute on function public.svc_scholarship_listing_next(integer) to service_role;

do $post$
declare v jsonb := security.consumer_api_check_v1(); b record; t0 timestamptz; ms int; n int;
begin
  select * into b from pg_temp.s1323_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> b.cron_before then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  -- the picker, timed in a block that is rolled back, so its lease is never kept
  begin
    t0 := clock_timestamp(); n := jsonb_array_length(public.svc_scholarship_listing_next(6)); ms := extract(milliseconds from clock_timestamp() - t0)::int;
    raise exception 's1323 timing block';
  exception when raise_exception then null;
  end;
  raise notice 's1323 picker: % pages in % ms', n, ms;
  if ms > 4000 then raise exception 'post-check: the picker took % ms', ms; end if;  -- fixed: half the 8 s call limit
end $post$;
