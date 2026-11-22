-- CF-247 s982 (S2-Build; Platform Admin consolidated batch 23 Nov 2026 07:16 and 07:45 AEDT, Part 3: IQ-00555 and IQ-00029, coverage-sweep
-- HTTP 500): the scholarship listing claim checks hosts only on the pages of providers that passed.
-- Measured live after s981 (rolled-back read-backs, 23 Nov 2026 09:51 to 09:55 AEDT): the hold check for 34 providers takes 0.8 s at :52, but the
-- whole claim still took 5.5 to 7.6 s. EXPLAIN ANALYZE of the claim showed the planner evaluating security.third_party_host_v1 on all 348 due
-- pages inside the "ok" step (650 ms quiet; about 1.9 ms a call) before joining the 8 providers that passed. public.svc_scholarship_listing_next
-- (md5-guarded, in place) puts the due pages of passing providers in their own materialised step first (a planner fence), then the host check.
-- Same rule, same rows, same order, limit and lease. G1: no job. G2: no new value. G3: no consumer object (75/48 before and after). $0.
-- Replaces: the s978 "ok" step of public.svc_scholarship_listing_next (rewritten in place).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if position('s982 (23 Nov 2026, IQ-00555)' in pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) = 0
     and md5(pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) <> '0fd4943e0dce7769320fd51f375ab808' then
    raise exception 'guard: live public.svc_scholarship_listing_next differs from the definition this change replaces';
  end if;
end $g$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_listing_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- s978 (23 Nov 2026, IQ-00555): the provider checks (hidden, Firecrawl scholarship hold) run once per provider of the due pages, not once per
  -- due page, and the host check only on the pages of providers that passed (339 due pages of 29 providers took 2.1 s quiet and 10 s under
  -- load, past the 8 s limit); then the same order, limit and lease
  with due as materialized (
    select l.id, l.provider_id from pipeline.scholarship_listing_pages l
     where l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()),
  prov as materialized (
    select d.provider_id from (select distinct due.provider_id from due) d
     where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)
       and not security.fc_sch_held_v1(d.provider_id, true)),
  cand as materialized (
    select due.id from due join prov on prov.provider_id is not distinct from due.provider_id),
  -- s982 (23 Nov 2026, IQ-00555): cand is a fence, so the host check runs only on the pages of providers that passed (the planner had pushed it
  -- down to all 348 due pages: 650 ms quiet, past 8 s with the hold check under load)
  ok as materialized (
    select l.id from cand join pipeline.scholarship_listing_pages l on l.id = cand.id
     where not security.third_party_host_v1(l.url)),  -- v2.15.265
  pick as (
    select l.id from pipeline.scholarship_listing_pages l
     where l.id in (select ok.id from ok)
       and l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()
     order by l.next_read_at nulls first, l.id limit greatest(1, least(coalesce(p_limit, 6), security.pipeline_num_v1('scholarship.listing_max', 20)::int)) for update skip locked),
  upd as (update pipeline.scholarship_listing_pages l set next_read_at = now() + interval '15 minutes' from pick where l.id = pick.id returning l.id, l.provider_id, l.url, l.next_url, l.page_state)  -- fixed: claim lease
  -- CF-247 scholarship recovery F6: a partly read catalogue continues from the address it stopped at
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url, 'next_url', case when u.page_state = 'partial' then u.next_url end,
           'hosts', (select to_jsonb(coalesce(d.allowed_hosts, '{}') || array[regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '')])
                       from pipeline.scholarship_discovery_providers d where d.provider_id = u.provider_id))), '[]'::jsonb) into v from upd u;
  return v;
end $function$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if position('s982 (23 Nov 2026, IQ-00555)' in pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) = 0 then
    raise exception 'post-check: the listing claim was not replaced';
  end if;
end $c$;
