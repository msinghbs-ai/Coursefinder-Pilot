-- CF-247 s1313 (S1-Build; SS-Programme-Control 27 Nov 2026 16:07 AEDT, "P0 Scholarship Production Picker Recovery", decision D12; SCH-FU-10,
-- coursefinder-admin #1305): the scholarship listing picker no longer leaves out a provider only because it has used its paid scholarship
-- Firecrawl cap, so its due listing pages get their free direct read again (robots.txt respected, no credit).
-- Found live (rolled back, read only): public.svc_scholarship_listing_next drops every provider where security.fc_sch_held_v1(provider, true) is
-- true. That function joins two rules: (a) the per-university paid cap (scholarship_cap_per_uni) and (b) discovery eligibility (fc_sch_eligible_v1,
-- the Canadian opening scholarship.listing_open_ca), both only while the Firecrawl budget switch is on. The listing read is direct first
-- (worker v1.0.35, s992); a paid scrape is asked only when the direct copy gives no item, and every paid scrape passes the worker's reserve and
-- scholarship share checks and public.svc_fc_spend, which enforces the daily budget, the per-university cap (scholarship group), the DR-15
-- eligibility rule for new pages and the account reserve. Rule (a) in the picker therefore only blocks free reads.
-- The change (smallest): security.fc_sch_listing_held_v1 is rule (b) exactly as fc_sch_held_v1 states it (same budget switch, same eligibility,
-- same Canadian opening), and the picker uses it in place of fc_sch_held_v1. Provider visibility (provider_hidden_v1), third-party hosts,
-- the lease, order and limit are unchanged. fc_sch_held_v1 itself and every other caller are unchanged; no cap, reserve, share, on-demand
-- control, hold, lock, job or setting changes. Spend: none added (a paid fallback is still refused by the same gates).
-- G1: no job. G2: no new value. G3: 75/48 checked. Nothing dropped or deleted.
-- Replaces: public.svc_scholarship_listing_next (md5 dc3b6885; one anchored predicate).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the replaced function

create temp table s1313_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) <> 'dc3b688512a12d5bbf3ed16eecdbd796' then
    raise exception 'pre-check: public.svc_scholarship_listing_next is not the definition this change was written against';
  end if;
  if md5(pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure)) <> '7c74b911a6b30e148e28bebc1ea29765' then
    raise exception 'pre-check: security.fc_sch_held_v1 is not the definition this change mirrors';
  end if;
  if position('scholarship_cap_per_uni' in (select string_agg(pg_get_functiondef(p.oid), ' ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'svc_fc_spend')) = 0 then
    raise exception 'pre-check: svc_fc_spend no longer enforces the per-university scholarship cap';
  end if;
end $pre$;

-- rule (b) of fc_sch_held_v1, word for word: discovery eligibility while the Firecrawl budget switch is on, with the Canadian opening
create or replace function security.fc_sch_listing_held_v1(p_provider_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $function$
begin
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then
    return false;
  end if;
  return not security.fc_sch_eligible_v1(p_provider_id)
    and not (coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'scholarship.listing_open_ca'), 0) > 0
             and exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id where p.id = p_provider_id and c.iso_alpha2 = 'CA'));
end $function$;
comment on function security.fc_sch_listing_held_v1(uuid) is 'CF-247 s1313: the listing picker''s provider hold: the discovery eligibility rule of security.fc_sch_held_v1 (same budget switch, same Canadian opening) without its paid cap, which public.svc_fc_spend enforces on every paid scrape.';
revoke all on function security.fc_sch_listing_held_v1(uuid) from public, anon, authenticated;

do $edit$
declare d text := pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure);
        a text := 'and not security.fc_sch_held_v1(d.provider_id, true)),';
begin
  if position(a in d) = 0 then raise exception 'anchor not found in svc_scholarship_listing_next'; end if;
  d := replace(d, a, 'and not security.fc_sch_listing_held_v1(d.provider_id)),  -- s1313: eligibility only; the paid cap is enforced on each paid scrape (svc_fc_spend)');
  execute d;
end $edit$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); r record; n_diff int := 0;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1313_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1313_guard) then raise exception 'post-check: manual locks changed'; end if;
  if pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure) !~ 'fc_sch_listing_held_v1' then raise exception 'post-check: the picker does not use the listing hold'; end if;
  if md5(pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure)) <> '7c74b911a6b30e148e28bebc1ea29765' then raise exception 'post-check: fc_sch_held_v1 changed'; end if;
  if has_function_privilege('authenticated', 'security.fc_sch_listing_held_v1(uuid)', 'execute') then raise exception 'post-check: execute privileges are not as released'; end if;
  -- the listing hold never releases a provider the original rule holds for eligibility: held by (b) in one means held in the other
  for r in select distinct l.provider_id from pipeline.scholarship_listing_pages l where l.active loop
    if security.fc_sch_listing_held_v1(r.provider_id) and not security.fc_sch_held_v1(r.provider_id, true) then n_diff := n_diff + 1; end if;
  end loop;
  if n_diff > 0 then raise exception 'post-check: % providers are held by the listing hold but not by fc_sch_held_v1', n_diff; end if;
end $post$;
