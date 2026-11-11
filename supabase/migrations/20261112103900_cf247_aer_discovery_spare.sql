-- CF-247 F-AER.04 AER discovery campaign: verified spare central capacity and the credit-count fix (Platform Admin decision D2, 11 Nov 2026, SS-017 / Operating Model v1.12:
-- "reallocate up to 1,000 credits a day of verified unused central Firecrawl capacity to the discovery campaign ... No increase to the overall approved daily Firecrawl budget.
-- No increase beyond the approved 10,000-credit AER campaign ceiling ... preserve the vendor reserve and other allocations ... reduce automatically when no spare capacity
-- exists ... no repeat searches against unchanged evidence ... track providers attempted, new sources, not-found outcomes, credits and cost per usable source").
-- Guards: G1 (no job added: the campaign still runs from aer-source-discover and the central-page search), G2 (every value is a setting with label, range, unit and used_by),
--   G3 (no consumer API object read or changed), Decision 260 (housekeeping), "a passing qualification never switches anything on by itself".
-- Evidence (production, read only, 11 Nov 2026 20:20-20:40 AEDT, project fxcwkweaxjtknorudmwp):
--   * campaign 1: 105 providers asked in 13 hours, 161 credits used, 60 requests open. Three requests failed and 31 settled from evidence "svc_fc_spend: canceling statement
--     due to statement timeout": security.aer_discovery_campaign_used_v1 scans all 203,525 Firecrawl usage rows calling a function on each (5.9-14.8 s against an 8 s
--     statement limit), and svc_fc_spend calls it for every central spend of a campaign provider. The same total from each provider's first request, through the existing
--     (provider_id, at) index: 161 credits in 92 ms.
--   * Firecrawl day (Melbourne): total 4,000; 2,623 billed by 20:35. Central share 1,000 with 117 left (central maps 778). Reads share 1,200 with 1,097 left and 22 credits
--     in the last 3 hours; scholarships 255 left, 1 credit in 3 hours; description 128 left. Vendor balance estimate 94,486; floor (priority_floor_course_search) 1,500.
-- What:
--   1. security.aer_discovery_campaign_used_v1: same result, from each provider's first campaign request (no full scan).
--   2. Settings: aer.discovery_spare_daily_max (1000, at most 1000), aer.discovery_spare_window_hours (3), aer.discovery_spare_margin_pct (50).
--   3. security.aer_discovery_spare_room_v1 NEW: the credits the campaign may take today beyond the central share. It is the least of: the daily maximum less spare already
--      taken; the day total less the automatic credits billed, less what every other group is projected to still need (its recent rate or the same hours of the previous
--      day, whichever is higher, plus the margin, never more than its unused share) and less the central share still unused; and the vendor balance above the floor
--      (none when no balance was read in the last 2 hours). It is 0 when the campaign or the daily budget is off.
--   4. pipeline.aer_discovery_spare_spends NEW: each spare credit spend (campaign, provider, purpose, credits, room at the time).
--   5. public.svc_fc_spend (md5-guarded edit): a central spend for a provider with an open campaign request that the central share would refuse is allowed only when the spare
--      room covers it; every other rule still applies before and after (monthly limit, cost breakers, the campaign ceiling, not_due for unchanged evidence).
--   6. security.aer_discovery_metrics_v1 NEW and public.admin_aer_discovery (md5-guarded edit, adds 'metrics'): providers attempted, new sources, usable (read) sources,
--      not-found outcomes, credits, spare credits today and in all, cost per usable source, the spare room now.
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 20:40 AEDT), before -> after:
--   security.aer_discovery_campaign_used_v1(bigint) 2b1e2ec802e29f873fe0a77c85fe7150 -> a1635da2b5eb53b4539518cb65ba7198
--   public.svc_fc_spend(numeric,text,uuid,text) c9d616fa35a278103121416ce73e0295 -> 07972f712be389e84d49f33a0852f534
--   public.admin_aer_discovery(jsonb) 2f26aa2679d98904bb310bc97857857c -> 8a84d58d70e1c7f31606af2b4199363b
-- Replaces: security.aer_discovery_campaign_used_v1, public.svc_fc_spend, public.admin_aer_discovery (same names; md5-guarded, resulting md5 checked); taken back by
--   supabase/held/aer_discovery_spare_forward_recovery.sql
-- Retires: nothing.
-- Reversal without code: aer.discovery_spare_daily_max 0 (no spare room; the central share decides as before).

do $g$
declare r record;
begin
  for r in select * from (values ('public.svc_fc_spend(numeric,text,uuid,text)'), ('security.aer_discovery_campaign_used_v1(bigint)'), ('public.admin_aer_discovery(jsonb)'),
                                 ('security.fc_purpose_group_v1(text)'), ('security.pipeline_num_v1(text,numeric)'), ('security.fc_setting_num_v1(text,numeric)'),
                                 ('security.fc_day_start_v1()'), ('security.fc_billed_today_v1()'), ('security.fc_on_demand_today_v1()'), ('security.fc_priority_room_v1()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.aer_discovery_campaigns') is null or to_regclass('pipeline.aer_source_discover_requests') is null or to_regclass('pipeline.coverage_vendor_usage') is null
     or to_regclass('pipeline.entry_matrix_sources') is null then raise exception 'a table this change reads is missing'; end if;
end $g$;

-- 2. settings ------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.discovery_spare_daily_max', 'Entry requirements: discovery campaign spare credits a day',
  'Most Firecrawl credits a day the discovery campaign may take beyond the central share, and only from verified unused capacity: inside the daily total, after every other group''s projected need and above the vendor floor. 0 switches it off. Never more than 1,000 (Platform Admin decision D2).',
  'number', to_jsonb(1000), 0, 1000, 'credits', 1507, 'Entry requirements', 'security.aer_discovery_spare_room_v1; public.svc_fc_spend',
  'Platform Admin decision D2, 11 Nov 2026: up to 1,000 credits a day of verified unused central capacity'),
 ('pipeline', 'aer.discovery_spare_window_hours', 'Entry requirements: spare capacity measured over',
  'Hours of recent spend used to project what each other Firecrawl group still needs today (the higher of that rate and the same hours of the previous day).',
  'number', to_jsonb(3), 1, 24, 'hours', 1508, 'Entry requirements', 'security.aer_discovery_spare_room_v1',
  'CF-247 F-AER.04 D2: spare capacity is verified against recent and previous-day use'),
 ('pipeline', 'aer.discovery_spare_margin_pct', 'Entry requirements: spare capacity safety margin',
  'Added to each other group''s projected need before anything is counted as spare.',
  'number', to_jsonb(50), 0, 300, 'percent', 1509, 'Entry requirements', 'security.aer_discovery_spare_room_v1',
  'CF-247 F-AER.04 D2: other allocations are preserved')
on conflict (toolset_key, key) do nothing;

-- 4. spare spend record --------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_discovery_spare_spends (
  id bigserial primary key,
  campaign_id bigint not null references pipeline.aer_discovery_campaigns(id),
  provider_id uuid not null,
  purpose text not null,
  units numeric not null,
  room numeric not null,
  at timestamptz not null default now()
);
create index if not exists aer_discovery_spare_spends_at_idx on pipeline.aer_discovery_spare_spends (at);
comment on table pipeline.aer_discovery_spare_spends is 'CF-247 F-AER.04 D2: Firecrawl credits the AER discovery campaign took beyond the central share from verified unused capacity (security.aer_discovery_spare_room_v1). Written by public.svc_fc_spend; read by security.aer_discovery_metrics_v1.';

-- 3. spare room ----------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_discovery_spare_room_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_max numeric; v_win numeric; v_margin numeric; v_start timestamptz := security.fc_day_start_v1();
        v_end timestamptz; v_left_h numeric; v_total numeric; v_auto numeric; v_taken numeric; v_vendor numeric;
        v_reserved numeric := 0; v_central_left numeric := 0; v_share numeric; v_used numeric; v_recent numeric; v_prev numeric; v_need numeric;
        v_groups jsonb := '{}'::jsonb; v_room numeric; g record;
begin
  v_max := least(security.pipeline_num_v1('aer.discovery_spare_daily_max', 0), 1000);  -- fixed: Platform Admin decision D2 sets 1,000 credits a day as the most
  if v_max <= 0 then return jsonb_build_object('room', 0, 'why', 'aer.discovery_spare_daily_max is 0'); end if;
  if security.pipeline_num_v1('aer.discovery_campaign_on', 0) < 1 or not exists (select 1 from pipeline.aer_discovery_campaigns c where c.state = 'running') then
    return jsonb_build_object('room', 0, 'why', 'no running campaign'); end if;
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then
    return jsonb_build_object('room', 0, 'why', 'daily budget off'); end if;
  v_win := greatest(security.pipeline_num_v1('aer.discovery_spare_window_hours', 3), 1);
  v_margin := greatest(security.pipeline_num_v1('aer.discovery_spare_margin_pct', 50), 0);
  v_end := (((v_start at time zone 'Australia/Melbourne') + interval '1 day') at time zone 'Australia/Melbourne');  -- fixed: the Firecrawl budget day (fc_day_start_v1)
  v_left_h := greatest(0, extract(epoch from (v_end - now())) / 3600);
  v_total := security.fc_setting_num_v1('daily_budget_total', 15000);
  v_auto := security.fc_billed_today_v1() - security.fc_on_demand_today_v1();
  select coalesce(sum(x.units), 0) into v_taken from pipeline.aer_discovery_spare_spends x where x.at >= v_start;
  -- every other group keeps what it is projected to still need today; central keeps its own unused share (the campaign uses that first)
  for g in with u as (select security.fc_purpose_group_v1(x.purpose) grp,
                             coalesce(sum(x.units) filter (where x.at >= v_start), 0) used,
                             coalesce(sum(x.units) filter (where x.at >= now() - make_interval(secs => v_win * 3600)), 0) recent,
                             coalesce(sum(x.units) filter (where x.at >= now() - interval '1 day' and x.at < v_end - interval '1 day'), 0) prev
                        from pipeline.coverage_vendor_usage x
                       where x.at >= least(v_start, now() - make_interval(secs => v_win * 3600), now() - interval '1 day') and x.on_demand_run is null
                       group by 1)
            select substr(s.key, 13) grp, (s.value #>> '{}')::numeric share, coalesce(u.used, 0) used, coalesce(u.recent, 0) recent, coalesce(u.prev, 0) prev
              from pipeline.platform_toolset_settings s left join u on u.grp = substr(s.key, 13)
             where s.toolset_key = 'firecrawl' and s.key like 'daily\_share\_%' loop
    v_used := g.used; v_recent := g.recent; v_prev := g.prev;
    if g.grp = 'central' then
      v_central_left := greatest(0, g.share - v_used);
      v_groups := v_groups || jsonb_build_object(g.grp, jsonb_build_object('share', g.share, 'used', v_used, 'kept', v_central_left));
    else
      v_need := least(greatest(0, g.share - v_used), ceil(greatest(v_recent / v_win * v_left_h, v_prev) * (1 + v_margin / 100)));
      v_reserved := v_reserved + v_need;
      v_groups := v_groups || jsonb_build_object(g.grp, jsonb_build_object('share', g.share, 'used', v_used, 'recent', v_recent, 'previous_day_same_hours', v_prev, 'kept', v_need));
    end if;
  end loop;
  v_vendor := security.fc_priority_room_v1();
  if v_vendor is null then
    return jsonb_build_object('room', 0, 'why', 'no vendor balance read in the last 2 hours', 'groups', v_groups); end if;
  v_room := greatest(0, floor(least(v_max - v_taken, v_total - v_auto - v_reserved - v_central_left, v_vendor)));
  return jsonb_build_object('room', v_room, 'daily_max', v_max, 'taken_today', v_taken, 'day_total', v_total, 'billed_automatic', v_auto, 'kept_for_others', v_reserved,
                            'central_unused', v_central_left, 'vendor_above_floor', v_vendor, 'hours_left', round(v_left_h, 1), 'groups', v_groups,
                            'why', case when v_room > 0 then 'spare capacity' when v_max - v_taken <= 0 then 'daily maximum taken' when v_vendor <= 0 then 'vendor floor'
                                        else 'no spare capacity' end);
end $f$;
comment on function security.aer_discovery_spare_room_v1() is 'CF-247 F-AER.04 D2: Firecrawl credits the AER discovery campaign may still take today beyond the central share, from verified unused capacity only, with the breakdown.';

create or replace function security.aer_discovery_spare_ok_v1(p_provider uuid, p_units numeric)
returns boolean language sql stable security definer set search_path = '' as $f$
  -- a provider with an open request of the running campaign, and spare room for this spend
  select exists (select 1 from pipeline.aer_discovery_campaigns c join pipeline.aer_source_discover_requests q on q.campaign_id = c.id
                  where c.state = 'running' and q.provider_id = p_provider and q.outcome is null)
     and coalesce((security.aer_discovery_spare_room_v1()->>'room')::numeric, 0) >= coalesce(p_units, 0)
$f$;

-- 6. metrics -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_discovery_metrics_v1()
returns jsonb language sql stable security definer set search_path = '' as $f$
  with c as (select * from pipeline.aer_discovery_campaigns order by id desc limit 1),
  f as (select q.provider_id, min(q.requested_at) first_at from pipeline.aer_source_discover_requests q join c on q.campaign_id = c.id group by 1),
  last as (select distinct on (q.provider_id) q.provider_id, q.outcome from pipeline.aer_source_discover_requests q join c on q.campaign_id = c.id
            order by q.provider_id, q.requested_at desc),
  src as (select s.provider_id, s.status from pipeline.entry_matrix_sources s join f on f.provider_id = s.provider_id and s.created_at >= f.first_at),
  m as (select (select count(*) from f) attempted,
               (select count(*) from src) new_sources,
               (select count(distinct provider_id) from src where status = 'read') usable,
               (select count(*) from last where outcome in ('no_entry_page', 'course_pages_found')) not_found,
               (select count(*) from last where outcome is null) open,
               (select security.aer_discovery_campaign_used_v1(c.id) from c) credits,
               (select coalesce(sum(x.units), 0) from pipeline.aer_discovery_spare_spends x join c on x.campaign_id = c.id) spare_all,
               (select coalesce(sum(x.units), 0) from pipeline.aer_discovery_spare_spends x where x.at >= security.fc_day_start_v1()) spare_today)
  select jsonb_build_object('providers_attempted', m.attempted, 'new_sources', m.new_sources, 'usable_sources', m.usable, 'not_found', m.not_found, 'open', m.open,
                            'credits', m.credits, 'spare_credits_total', m.spare_all, 'spare_credits_today', m.spare_today,
                            'cost_per_usable_source', case when m.usable > 0 then round(m.credits / m.usable, 1) end,
                            'by_outcome', (select coalesce(jsonb_object_agg(coalesce(z.outcome, 'searching'), z.n), '{}'::jsonb) from (select outcome, count(*) n from last group by 1) z),
                            'spare', security.aer_discovery_spare_room_v1())
    from m
$f$;
comment on function security.aer_discovery_metrics_v1() is 'CF-247 F-AER.04 D2: AER discovery campaign metrics (providers attempted, new and usable sources, not found, credits, spare credits, cost per usable source, spare room now).';

revoke all on function security.aer_discovery_spare_room_v1(), security.aer_discovery_spare_ok_v1(uuid, numeric), security.aer_discovery_metrics_v1() from public, anon, authenticated;

-- 1, 5, 6. the guarded edits ---------------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_discovery_campaign_used_v1(bigint)', '2b1e2ec802e29f873fe0a77c85fe7150', 'a1635da2b5eb53b4539518cb65ba7198',
     array[$o$  select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u
   where security.fc_purpose_group_v1(u.purpose) = 'central'
     and exists (select 1 from pipeline.aer_source_discover_requests q where q.campaign_id = p_campaign and q.provider_id = u.provider_id and u.at >= q.requested_at)$o$],
     array[$n$  -- 12 Nov 2026 (D2): from each provider's first request of the campaign, through the (provider_id, at) index; the same total as any request before the spend
  with f as (select q.provider_id, min(q.requested_at) t from pipeline.aer_source_discover_requests q where q.campaign_id = p_campaign group by 1)
  select coalesce(sum(u.units), 0) from f join pipeline.coverage_vendor_usage u on u.provider_id = f.provider_id and u.at >= f.t
   where security.fc_purpose_group_v1(u.purpose) = 'central'$n$]),
    ('public.svc_fc_spend(numeric,text,uuid,text)', 'c9d616fa35a278103121416ce73e0295', '07972f712be389e84d49f33a0852f534',
     array[$o$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url);$o$,
           $o$    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    if security.fc_budget_left_v1(p_purpose) < p_units then$o$,
           $o$  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return true;$o$],
     array[$n$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url); v_spare boolean := false;$n$,
           $n$    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    -- 12 Nov 2026 (Platform Admin decision D2): a central spend for a provider with an open discovery campaign request that the central share would refuse may use
    -- verified unused capacity (security.aer_discovery_spare_room_v1: inside the daily total, after every other group's projected need, above the vendor floor, at most
    -- aer.discovery_spare_daily_max a day); the campaign ceiling and not_due below still apply
    v_spare := v_grp = 'central' and p_provider_id is not null and security.fc_budget_left_v1(p_purpose) < p_units
               and security.aer_discovery_spare_ok_v1(p_provider_id, p_units);
    if security.fc_budget_left_v1(p_purpose) < p_units and not v_spare then$n$,
           $n$  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  if v_spare then
    insert into pipeline.aer_discovery_spare_spends(campaign_id, provider_id, purpose, units, room)
    select c.id, p_provider_id, p_purpose, p_units, coalesce((security.aer_discovery_spare_room_v1()->>'room')::numeric, 0) + p_units
      from pipeline.aer_discovery_campaigns c where c.state = 'running' order by c.id desc limit 1;
  end if;
  return true;$n$]),
    ('public.admin_aer_discovery(jsonb)', '2f26aa2679d98904bb310bc97857857c', '8a84d58d70e1c7f31606af2b4199363b',
     array[$o$      'rows', (select coalesce(jsonb_agg(to_jsonb(pg) order by pg.courses desc, pg.provider), '[]'::jsonb) from pg)));$o$],
     array[$n$      'metrics', security.aer_discovery_metrics_v1(),  -- 12 Nov 2026 (D2)
      'rows', (select coalesce(jsonb_agg(to_jsonb(pg) order by pg.courses desc, pg.provider), '[]'::jsonb) from pg)));$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

-- register, post-check ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.aer_discovery_spare_spends', 'Layer 2', 'AER discovery campaign credits taken from verified unused capacity beyond the central share', 'active', '{}', '20261112103900'),
 ('function', 'security.aer_discovery_spare_room_v1', 'Layer 2', 'Credits the AER discovery campaign may still take today from verified unused capacity, with the breakdown', 'active', '{}', '20261112103900'),
 ('function', 'security.aer_discovery_metrics_v1', 'Layer 2', 'AER discovery campaign metrics: attempted, new and usable sources, not found, credits, cost per usable source', 'active', '{}', '20261112103900')
on conflict do nothing;

do $post$ begin
  if position('aer_discovery_spare_ok_v1' in (select p.prosrc from pg_proc p where p.oid = 'public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) = 0 then raise exception 'post-check: the spare room is not used'; end if;
  if position('aer_discovery_campaign_over_v1' in (select p.prosrc from pg_proc p where p.oid = 'public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) = 0 then raise exception 'post-check: the campaign ceiling was lost'; end if;
  if position('fc_month_refusal_v1' in (select p.prosrc from pg_proc p where p.oid = 'public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) = 0 then raise exception 'post-check: the monthly limit was lost'; end if;
  if security.pipeline_num_v1('aer.discovery_spare_daily_max', 0) > 1000 then raise exception 'post-check: the spare maximum passes the decision'; end if;
end $post$;
