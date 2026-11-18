-- CF-247 F-AER.04 AER source discovery campaign: a recorded discovery outcome for every eligible provider (Platform Admin 11 Nov 2026 16:24 AEDT and the four AER decisions
-- answered the same afternoon: "Full provider source discovery — 10,000-credit ceiling ... across all 1,416 currently missing eligible AER providers, including universities,
-- TAFEs and private providers ... This decision does not override other platform budgets ... Continue automatically until every eligible provider has a recorded discovery
-- outcome, not necessarily a successful source").
-- Guards: G1 (no job added: the existing hourly aer-source-discover runs the campaign), G2 (every value is a setting with label, range, unit and used_by), G3 (no consumer API
--   object read or changed), Decision 260 (housekeeping), "a passing qualification never switches anything on by itself" (the campaign switch is the Platform Admin's decision).
-- Evidence (production, read only, 11 Nov 2026 16:30-17:10 AEDT, project fxcwkweaxjtknorudmwp):
--   * 1,476 eligible providers (AU 1,279, NZ 197); 63 have an entry-requirements source (60 read); 1,413 have none (nothing stored 372, course pages waiting 951,
--     course pages matched by title only 81, stored link 5, weak page 3, shared host 1).
--   * job aer-source-discover asks only about the 372 "nothing stored" providers, at most aer.source_discover_credits_per_day (200) a day, and asks a refused provider again
--     only after 24 hours. The last requests were made at 20:19Z on 10 Nov, BEFORE the targeted entry search was released (21:15Z): all 123 settled 'refused' an hour later
--     from evidence recorded on 22 Oct ("Firecrawl refused: credits_refused", searched_at 2026-10-22), because the settle rule did not check when the refusal was recorded.
--     Since then no provider has been asked and the entry search has spent 0 credits.
--   * Firecrawl plan: 94,715 of 100,000 credits left in the billing period to 8 Dec; central daily share 1,000 (about 680 used a day by other central work).
-- What:
--   1. pipeline.aer_discovery_campaigns NEW: one row per campaign (start, credit ceiling, state, decision). pipeline.aer_source_discover_requests.campaign_id NEW column.
--   2. Settings: aer.discovery_campaign_on (1), aer.discovery_campaign_credit_cap (10000), aer.discovery_campaign_batch (60 providers a run), aer.discovery_campaign_retry_hours (3).
--   3. security.aer_discovery_campaign_ask_v1 NEW, called at the end of each aer-source-discover run: asks the central-page search (the worker's targeted entry search when the
--      whole-site map is not due) about every eligible provider with no entry source and a usable website, largest first, until each has an outcome; a refusal is asked again
--      after the retry hours; it stops at the ceiling. security.aer_discovery_campaign_used_v1 / _over_v1 / _v1 NEW (credits used, ceiling check, status).
--   4. public.svc_fc_spend (md5-guarded edit): a central spend for a provider with an open campaign request is refused 'campaign_cap' once the campaign would pass its ceiling.
--      Every other rule still applies first: the monthly plan limit, the cost breakers, the daily total and the central share. Nothing here raises or bypasses a budget.
--   5. security.aer_source_discover_v1 (md5-guarded edit): a request is settled 'refused' or 'failed' only from evidence recorded after the request (the 22 Oct evidence defect);
--      the run result carries the campaign's result.
--   6. security.aer_discovery_outcomes_v1 NEW and public.admin_aer_discovery NEW (rank 4, read only): for each of the eligible providers, the source (address, document type,
--      status), the discovery outcome, when it was last checked, the evidence and the next action.
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 17:05 AEDT by Database function snapshot run 42974996927), before -> after:
--   public.svc_fc_spend(numeric,text,uuid,text) 39075b66a1d8ff15246b8c82ffa0c590 -> c9d616fa35a278103121416ce73e0295
--   security.aer_source_discover_v1(boolean) f818e6bb2500c5cc63c361970c73d1e3 -> 16e04c3ffe38a38f3b6f23df7bd0e0a1
-- Replaces: public.svc_fc_spend, security.aer_source_discover_v1 (same names; md5-guarded text edits, resulting md5 checked); taken back by
--   supabase/held/aer_discovery_campaign_forward_recovery.sql
-- Retires: nothing.
-- Reversal without code: aer.discovery_campaign_on 0 (no campaign request is made; spends are refused by nothing new).

do $g$
declare r record;
begin
  for r in select * from (values ('public.svc_fc_spend(numeric,text,uuid,text)'), ('security.aer_source_discover_v1(boolean)'), ('security.aer_eligible_v1()'),
                                 ('security.third_party_host_v1(text)'), ('security.fc_purpose_group_v1(text)'), ('security.pipeline_num_v1(text,numeric)'),
                                 ('security.current_role_rank()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.aer_source_discover_requests') is null or to_regclass('pipeline.provider_central_search') is null or to_regclass('pipeline.entry_matrix_sources') is null
     or to_regclass('pipeline.coverage_vendor_usage') is null then raise exception 'a table this change reads is missing'; end if;
end $g$;

-- 1. campaign record ------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_discovery_campaigns (
  id bigserial primary key,
  started_at timestamptz not null default now(),
  credit_cap numeric not null,
  state text not null default 'running' check (state in ('running', 'complete', 'cap_reached', 'stopped')),
  decision text not null,
  completed_at timestamptz,
  detail jsonb not null default '{}'::jsonb
);
comment on table pipeline.aer_discovery_campaigns is 'CF-247 F-AER.04: AER source discovery campaigns (one-off passes over every eligible provider with no entry-requirements source, each with a Firecrawl credit ceiling). Written by security.aer_discovery_campaign_ask_v1; read by the AER discovery screen.';
alter table pipeline.aer_source_discover_requests add column if not exists campaign_id bigint references pipeline.aer_discovery_campaigns(id);
create index if not exists aer_source_discover_requests_campaign_idx on pipeline.aer_source_discover_requests (campaign_id, provider_id) where campaign_id is not null;
create index if not exists aer_source_discover_requests_provider_idx on pipeline.aer_source_discover_requests (provider_id, requested_at desc);

-- 2. settings ------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.discovery_campaign_on', 'Entry requirements: discovery campaign on',
  '1 runs the current AER source discovery campaign: every eligible provider with no entry-requirements source is searched on its own website until each has a recorded outcome, within the credit ceiling below and every other Firecrawl limit. 0 stops asking.',
  'number', to_jsonb(1), 0, 1, 'switch', 1503, 'Entry requirements', 'security.aer_discovery_campaign_ask_v1; job aer-source-discover',
  'Platform Admin decision 11 Nov 2026 16:24 AEDT: full provider source discovery, 10,000-credit ceiling'),
 ('pipeline', 'aer.discovery_campaign_credit_cap', 'Entry requirements: discovery campaign credit ceiling',
  'Firecrawl credits the current discovery campaign may use in all (central-page maps and entry searches of the providers it asked about). It does not raise any other limit: the monthly plan, the daily total and the central share still apply.',
  'number', to_jsonb(10000), 0, 50000, 'credits', 1504, 'Entry requirements', 'security.aer_discovery_campaign_ask_v1; public.svc_fc_spend',
  'Platform Admin decision 11 Nov 2026 16:24 AEDT: hard 10,000-credit ceiling'),
 ('pipeline', 'aer.discovery_campaign_batch', 'Entry requirements: discovery campaign providers asked a run',
  'Most providers the campaign asks the central-page search about in one hourly run of aer-source-discover.',
  'number', to_jsonb(60), 0, 500, 'providers', 1505, 'Entry requirements', 'security.aer_discovery_campaign_ask_v1',
  'CF-247 F-AER.04: about the central-page search''s hourly capacity (batch.central_find every 5 minutes)'),
 ('pipeline', 'aer.discovery_campaign_retry_hours', 'Entry requirements: discovery campaign retry after a refusal',
  'Hours before a provider whose search was refused (a budget or share was used up) is asked again by the campaign.',
  'number', to_jsonb(3), 1, 168, 'hours', 1506, 'Entry requirements', 'security.aer_discovery_campaign_ask_v1',
  'CF-247 F-AER.04: refusals are budget waits, not outcomes')
on conflict (toolset_key, key) do nothing;

insert into pipeline.aer_discovery_campaigns(started_at, credit_cap, decision)
select now(), 10000, 'Platform Admin decision 11 Nov 2026 16:24 AEDT: one-off discovery pass across every eligible AER provider without a source (universities, TAFEs and private providers), hard 10,000-credit ceiling, inside every other platform budget; continue until every eligible provider has a recorded discovery outcome'
 where not exists (select 1 from pipeline.aer_discovery_campaigns);

-- 3. campaign functions --------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_discovery_campaign_used_v1(p_campaign bigint) returns numeric
language sql stable security definer set search_path = '' as $f$
  -- credits the campaign used: central-page spends (maps and entry searches) of the providers it asked about, from each request on
  select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u
   where security.fc_purpose_group_v1(u.purpose) = 'central'
     and exists (select 1 from pipeline.aer_source_discover_requests q where q.campaign_id = p_campaign and q.provider_id = u.provider_id and u.at >= q.requested_at)
$f$;
comment on function security.aer_discovery_campaign_used_v1(bigint) is 'CF-247 F-AER.04: Firecrawl credits used by an AER discovery campaign (central-page spends of the providers it asked about, from each request on).';

create or replace function security.aer_discovery_campaign_over_v1(p_provider uuid, p_units numeric) returns boolean
language sql stable security definer set search_path = '' as $f$
  -- true when this provider has an open request of the running campaign and the spend would take the campaign past its ceiling
  select exists (select 1 from pipeline.aer_discovery_campaigns c join pipeline.aer_source_discover_requests q on q.campaign_id = c.id
                  where c.state = 'running' and q.provider_id = p_provider and q.outcome is null
                    and security.aer_discovery_campaign_used_v1(c.id) + coalesce(p_units, 0) > security.pipeline_num_v1('aer.discovery_campaign_credit_cap', c.credit_cap))
$f$;
comment on function security.aer_discovery_campaign_over_v1(uuid, numeric) is 'CF-247 F-AER.04: whether a central-page spend for a provider asked by the running discovery campaign would pass the campaign ceiling (public.svc_fc_spend refuses it as campaign_cap).';

create or replace function security.aer_discovery_outcomes_v1() returns table(provider_id uuid, provider text, country text, website text, courses int,
  outcome text, source_url text, source_type text, source_status text, last_checked timestamptz, evidence jsonb, next_action text)
language sql stable security definer set search_path = '' as $f$
  with e as (select e.provider_id, e.country from security.aer_eligible_v1() e),
  src as (select distinct on (s.provider_id) s.provider_id, s.url, s.status, coalesce(s.read_at, s.updated_at) at from pipeline.entry_matrix_sources s
           order by s.provider_id, (s.status = 'read') desc, s.updated_at desc),
  req as (select distinct on (q.provider_id) q.provider_id, q.outcome, q.requested_at, q.outcome_at, q.detail, q.campaign_id from pipeline.aer_source_discover_requests q
           order by q.provider_id, q.requested_at desc),
  fails as (select q.provider_id, count(*) n from pipeline.aer_source_discover_requests q where q.outcome = 'failed' group by 1)
  select e.provider_id, coalesce(p.display_name, p.canonical_name), e.country, p.website,
         (select count(*)::int from catalogue.courses c where c.provider_id = e.provider_id and c.lifecycle_status = 'active'),
         case when src.provider_id is not null then 'source_' || src.status
              when coalesce(p.website, '') !~* '^https?://' then 'no_website'
              when security.third_party_host_v1(p.website) then 'website_is_directory'
              when req.provider_id is null then 'not_asked'
              when req.outcome is null then 'searching'
              when req.outcome = 'failed' and coalesce(fails.n, 0) >= security.pipeline_num_v1('aer.source_discover_max_tries', 3) then 'search_failed'
              else req.outcome end,
         src.url,
         case when src.url is null then null when src.url ~* '\.pdf($|[?#])' then 'pdf' else 'web page' end,
         src.status,
         greatest(src.at, req.outcome_at, req.requested_at),
         coalesce(req.detail, '{}'::jsonb) || jsonb_build_object('campaign_id', req.campaign_id),
         case when src.provider_id is not null and src.status = 'read' then 'read on its refresh schedule (entry.matrix_refresh_days)'
              when src.provider_id is not null then 'read by entry-matrix-read; failures retried within entry.matrix_attempts'
              when coalesce(p.website, '') !~* '^https?://' or security.third_party_host_v1(p.website) then 'set the provider''s own website (Provider catalogue), or attach an entry source by hand'
              when req.outcome is null and req.provider_id is not null then 'central-page search in progress'
              when req.outcome = 'refused' then 'asked again after aer.discovery_campaign_retry_hours (a budget was used up)'
              when req.outcome in ('no_entry_page', 'course_pages_found') then 'no entry page on the website: course-level reading from course pages; attach an entry source by hand if one exists'
              when req.outcome = 'failed' then 'search failed: retried up to aer.source_discover_max_tries, then attach by hand'
              else 'asked by the discovery campaign' end
    from e join catalogue.providers p on p.id = e.provider_id
    left join src on src.provider_id = e.provider_id
    left join req on req.provider_id = e.provider_id
    left join fails on fails.provider_id = e.provider_id
$f$;
comment on function security.aer_discovery_outcomes_v1() is 'CF-247 F-AER.04: for every AER-eligible provider, the entry-requirements source (address, document type, status), the discovery outcome, when it was last checked, the evidence and the next action. Read only, counted live.';

create or replace function security.aer_discovery_campaign_ask_v1(p_preview boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare c pipeline.aer_discovery_campaigns%rowtype; v_cap numeric; v_batch int := security.pipeline_num_v1('aer.discovery_campaign_batch', 60)::int;
        v_retry int := security.pipeline_num_v1('aer.discovery_campaign_retry_hours', 3)::int; v_tries int := security.pipeline_num_v1('aer.source_discover_max_tries', 3)::int;
        v_used numeric; v_per numeric; v_open int; v_room int; v_asked int := 0; v_cand int := 0; v_left int; r record;
begin
  select * into c from pipeline.aer_discovery_campaigns x where x.state = 'running' order by x.id desc limit 1;
  if c.id is null then return jsonb_build_object('on', false, 'why', 'no running campaign'); end if;
  if security.pipeline_num_v1('aer.discovery_campaign_on', 0) < 1 then return jsonb_build_object('on', false, 'campaign', c.id, 'why', 'aer.discovery_campaign_on is 0'); end if;
  v_cap := security.pipeline_num_v1('aer.discovery_campaign_credit_cap', c.credit_cap);
  v_used := security.aer_discovery_campaign_used_v1(c.id);
  select coalesce(round(sum(units) / nullif(count(distinct provider_id), 0), 1), 4) into v_per from pipeline.coverage_vendor_usage where purpose in ('central_map', 'central_entry_search');
  v_per := greatest(v_per, 1);
  select count(*) into v_open from pipeline.aer_source_discover_requests q where q.campaign_id = c.id and q.outcome is null;
  v_room := greatest(0, least(v_batch - v_open, floor((v_cap - v_used - v_per * v_open) / v_per)))::int;
  -- providers still without an outcome: eligible, no entry source, a usable website, not asked by this campaign to an outcome
  for r in
    with cand as (
      select e.provider_id, (select count(*) from catalogue.courses k where k.provider_id = e.provider_id and k.lifecycle_status = 'active') n
        from security.aer_eligible_v1() e join catalogue.providers p on p.id = e.provider_id
       where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)
         and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)
         and not exists (select 1 from pipeline.aer_source_discover_requests q where q.provider_id = e.provider_id and q.outcome is null)
         and not exists (select 1 from pipeline.aer_source_discover_requests q where q.campaign_id = c.id and q.provider_id = e.provider_id
                           and q.outcome in ('entry_source_found', 'course_pages_found', 'no_entry_page', 'superseded'))
         and (select count(*) from pipeline.aer_source_discover_requests q where q.campaign_id = c.id and q.provider_id = e.provider_id and q.outcome = 'failed') < v_tries
         and not exists (select 1 from pipeline.aer_source_discover_requests q where q.campaign_id = c.id and q.provider_id = e.provider_id
                           and q.outcome = 'refused' and q.outcome_at > now() - make_interval(hours => v_retry)))
    select * from cand order by n desc, provider_id
  loop
    v_cand := v_cand + 1;
    continue when v_asked >= v_room;  -- counted, asked in a later run
    if not p_preview then
      insert into pipeline.provider_central_search(provider_id, state, requested_at, attempts, updated_at) values (r.provider_id, 'queued', now(), 0, now())
      on conflict (provider_id) do update set state = case when pipeline.provider_central_search.state = 'leased' and pipeline.provider_central_search.leased_until > now() then pipeline.provider_central_search.state else 'queued' end,
             requested_at = now(), attempts = 0, updated_at = now();
      insert into pipeline.aer_source_discover_requests(provider_id, campaign_id, detail) values (r.provider_id, c.id, jsonb_build_object('planned_credits', v_per, 'route', 'campaign'));
    end if;
    v_asked := v_asked + 1;
  end loop;
  -- what is left: providers this campaign has not yet taken to an outcome (candidates, asked now or later) and its open requests
  v_left := v_cand + v_open;
  if not p_preview then
    if v_left = 0 then
      update pipeline.aer_discovery_campaigns set state = 'complete', completed_at = now(), detail = detail || jsonb_build_object('credits_used', v_used) where id = c.id;
    elsif v_used >= v_cap then
      update pipeline.aer_discovery_campaigns set state = 'cap_reached', completed_at = now(), detail = detail || jsonb_build_object('credits_used', v_used, 'left_without_outcome', v_left) where id = c.id;
    end if;
  end if;
  return jsonb_build_object('on', true, 'campaign', c.id, 'preview', p_preview, 'asked', v_asked, 'open', v_open, 'room', v_room, 'credits_used', v_used, 'credit_cap', v_cap,
                            'credits_per_provider', v_per, 'left_without_outcome', v_left);
end $f$;
comment on function security.aer_discovery_campaign_ask_v1(boolean) is 'CF-247 F-AER.04: one step of the running AER discovery campaign (called by security.aer_source_discover_v1, job aer-source-discover): asks the central-page search about eligible providers with no entry source until each has a recorded outcome, within aer.discovery_campaign_batch a run and the campaign credit ceiling; marks the campaign complete or cap_reached. With true: what it would ask, nothing written.';

create or replace function security.aer_discovery_campaign_v1() returns jsonb
language sql stable security definer set search_path = '' as $f$
  -- one pass over the outcomes (the read is used by a screen)
  with o as materialized (select x.outcome from security.aer_discovery_outcomes_v1() x),
  c as (select * from pipeline.aer_discovery_campaigns order by id desc limit 1)
  select jsonb_build_object(
    'campaign', (select to_jsonb(c) || jsonb_build_object('credits_used', security.aer_discovery_campaign_used_v1(c.id),
                                                           'credit_cap_now', security.pipeline_num_v1('aer.discovery_campaign_credit_cap', c.credit_cap),
                                                           'asked', (select count(distinct q.provider_id) from pipeline.aer_source_discover_requests q where q.campaign_id = c.id)) from c),
    'providers', (select count(*) from o),
    'by_outcome', (select coalesce(jsonb_object_agg(z.outcome, z.n), '{}'::jsonb) from (select o.outcome, count(*) n from o group by 1) z),
    'with_outcome', (select count(*) from o where o.outcome not in ('not_asked', 'searching', 'refused', 'failed')))
$f$;
comment on function security.aer_discovery_campaign_v1() is 'CF-247 F-AER.04: status of the latest AER discovery campaign: credits used against the ceiling, providers asked, providers by outcome and how many have a recorded outcome. Read only.';

create or replace function public.admin_aer_discovery(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_out text := nullif(p_args->>'outcome', ''); v_q text := nullif(p_args->>'q', '');
        v_lim int := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 500); v_off int := greatest(coalesce((p_args->>'offset')::int, 0), 0);  -- fixed: page size bounds of a screen list
begin
  if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or v_rank < 4) then
    raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;
  -- one pass over the outcomes (materialised once), then the counts and the page
  return (
    with o as materialized (select * from security.aer_discovery_outcomes_v1()),
    c as (select * from pipeline.aer_discovery_campaigns order by id desc limit 1),
    pg as (select * from o where (v_out is null or o.outcome = v_out) and (v_q is null or o.provider ilike '%' || v_q || '%')
            order by o.courses desc, o.provider limit v_lim offset v_off)
    select jsonb_build_object(
      'campaign', (select to_jsonb(c) || jsonb_build_object('credits_used', security.aer_discovery_campaign_used_v1(c.id),
                                                             'credit_cap_now', security.pipeline_num_v1('aer.discovery_campaign_credit_cap', c.credit_cap),
                                                             'asked', (select count(distinct q.provider_id) from pipeline.aer_source_discover_requests q where q.campaign_id = c.id)) from c),
      'providers', (select count(*) from o),
      'with_outcome', (select count(*) from o where o.outcome not in ('not_asked', 'searching', 'refused', 'failed')),
      'by_outcome', (select coalesce(jsonb_object_agg(z.outcome, z.n), '{}'::jsonb) from (select o.outcome, count(*) n from o group by 1) z),
      'rows', (select coalesce(jsonb_agg(to_jsonb(pg) order by pg.courses desc, pg.provider), '[]'::jsonb) from pg)));
end $f$;
revoke all on function public.admin_aer_discovery(jsonb) from public, anon;
grant execute on function public.admin_aer_discovery(jsonb) to authenticated;
comment on function public.admin_aer_discovery(jsonb) is 'CF-247 F-AER.04: Catalogue › Entry requirements, AER source discovery: the campaign status and, per eligible provider, source, outcome, last checked, evidence and next action (filter by outcome or name, paged). Rank 4 and above; read only; never part of the consumer API.';

revoke all on function security.aer_discovery_campaign_used_v1(bigint), security.aer_discovery_campaign_over_v1(uuid, numeric), security.aer_discovery_outcomes_v1(),
                       security.aer_discovery_campaign_ask_v1(boolean), security.aer_discovery_campaign_v1() from public, anon, authenticated;

-- 4-5. the guarded edits -------------------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('public.svc_fc_spend(numeric,text,uuid,text)', '39075b66a1d8ff15246b8c82ffa0c590', 'c9d616fa35a278103121416ce73e0295',
     array[$o$    elsif p_provider_id is not null and p_purpose = 'central_entry_search' then$o$],
     array[$n$    -- 12 Nov 2026 (F-AER.04 discovery campaign): a central spend for a provider the running campaign asked about stops at the campaign ceiling
    -- (aer.discovery_campaign_credit_cap); it is checked after the monthly limit, the cost breakers, the daily total and the central share above
    elsif p_provider_id is not null and v_grp = 'central' and security.aer_discovery_campaign_over_v1(p_provider_id, p_units) then
      v_why := 'campaign_cap';
    elsif p_provider_id is not null and p_purpose = 'central_entry_search' then$n$]),
    ('security.aer_source_discover_v1(boolean)', 'f818e6bb2500c5cc63c361970c73d1e3', '16e04c3ffe38a38f3b6f23df7bd0e0a1',
     array[$o$  for r in select q.id, q.provider_id, q.requested_at, s.state, s.searched_at, s.requested_at s_req, s.evidence, s.found$o$,
           $o$                  when r.s_req is null and r.evidence ? 'refusal' then 'refused'
                  when r.state = 'failed' or (r.evidence ? 'error' and r.s_req is null) then 'failed'$o$,
           $o$  return jsonb_build_object('on', true, 'preview', p_preview, 'settled', v_settled, 'asked', v_asked, 'credits_used_24h_or_planned', v_used, 'credits_per_provider', v_per, 'cap', v_cap);$o$],
     array[$n$  for r in select q.id, q.provider_id, q.requested_at, s.state, s.searched_at, s.requested_at s_req, s.evidence, s.found, s.updated_at s_upd$n$,
           $n$                  -- 12 Nov 2026 (F-AER.04): a refusal or an error settles the request only when it was recorded after the request (never the 22 Oct evidence)
                  when r.s_req is null and r.evidence ? 'refusal' and r.s_upd >= r.requested_at then 'refused'
                  when (r.state = 'failed' or (r.evidence ? 'error' and r.s_req is null)) and r.s_upd >= r.requested_at then 'failed'$n$,
           $n$  return jsonb_build_object('on', true, 'preview', p_preview, 'settled', v_settled, 'asked', v_asked, 'credits_used_24h_or_planned', v_used, 'credits_per_provider', v_per, 'cap', v_cap)
         || jsonb_build_object('campaign', security.aer_discovery_campaign_ask_v1(p_preview));$n$])
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
 ('table', 'pipeline.aer_discovery_campaigns', 'Layer 2', 'AER source discovery campaigns: start, credit ceiling, state, decision', 'active', '{}', '20261112040000'),
 ('function', 'security.aer_discovery_campaign_ask_v1', 'Layer 2', 'One step of the AER discovery campaign: ask the central-page search about providers without an outcome, within the ceiling', 'active', '{}', '20261112040000'),
 ('function', 'security.aer_discovery_outcomes_v1', 'Layer 2', 'Per eligible provider: AER source, discovery outcome, last checked, evidence, next action (read only)', 'active', '{}', '20261112040000'),
 ('function', 'public.admin_aer_discovery', 'Platform', 'AER source discovery screen read: campaign status and per-provider outcomes', 'active', '{}', '20261112040000')
on conflict do nothing;

do $post$ begin
  if position('aer_discovery_campaign_over_v1' in (select p.prosrc from pg_proc p where p.oid = 'public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) = 0 then raise exception 'post-check: the campaign ceiling is not checked'; end if;
  if position('fc_month_refusal_v1' in (select p.prosrc from pg_proc p where p.oid = 'public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) = 0 then raise exception 'post-check: the monthly limit was lost'; end if;
  if position('aer_discovery_campaign_ask_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_source_discover_v1(boolean)'::regprocedure)) = 0 then raise exception 'post-check: the campaign is not run'; end if;
  if not exists (select 1 from pipeline.aer_discovery_campaigns where state = 'running') then raise exception 'post-check: no running campaign'; end if;
end $post$;
