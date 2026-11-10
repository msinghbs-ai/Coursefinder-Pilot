-- CF-247 F-AER.01 governed source discovery for eligible providers with nothing stored (Platform Admin decision 10 Nov 2026 ~23:45 AEDT, AER recovery pack decision 3:
-- "Approve 200 Firecrawl credits/day" for the 373 eligible providers without stored entry-requirement or course-page evidence).
-- The decision's controls: official provider websites first and existing stored evidence reused; the 200-credit daily limit plus the existing platform-wide budget and provider
-- controls; no repeated crawling of the same failed addresses; transient failures retried automatically; unresolved providers to a structured exception queue; continue across
-- the providers without individual manual decisions; outcomes recorded against the 1,476-provider AER scope; a discovered page does not authorise admission of its contents.
-- Evidence (production, read only, 11 Nov 2026 00:2x AEDT): of the 373 (security.aer_no_source_route_v1 route nothing_stored), 370 have a central-page search row; their last
--   searches ran 12-22 Oct, BEFORE the entry-requirements page kind was added to central_find (Track C step A, 26 Oct 2026): across ALL providers the stored searches hold
--   1 entry_requirements suggestion against 1,441 fee and 1,400 calendar suggestions. The searches simply never looked for the page. central_find (Firecrawl map of the
--   provider's own website, then one targeted map per page kind not found) costs 3.8 credits a provider on average (pipeline.coverage_vendor_usage, purpose central_map,
--   8,774 credits / 2,314 providers). Its suggestions become entry reader sources through the existing security.entry_matrix_attach_v1 (job entry-matrix-read), within
--   entry.attach_per_provider, and are read by the existing entry matrix reader; every first read still passes Layer 4 (a person, or for course reads rule aer-machine-v1).
-- What:
--   1. Settings: aer.source_discover_on 1, aer.source_discover_credits_per_day 200, aer.source_discover_recheck_days 30, aer.source_discover_max_tries 3.
--   2. pipeline.aer_source_discover_requests: one row per request (provider, when, outcome, credits measured, evidence) - the dedupe record and the exception queue.
--   3. security.aer_source_discover_v1(preview): (a) settles open requests from what the existing search recorded (entry_source_found / course_pages_found /
--      no_entry_page / refused (Firecrawl share or not due: retried when due, not counted as a try) / failed (site error: retried, counted)); (b) measures the credits the
--      requested providers actually used in the last 24 hours (coverage_vendor_usage, central purposes) and plans the rest of the 200 at 3.8 a provider (measured average);
--      (c) asks the existing central-page search to run for that many more nothing_stored providers (own website set, not third-party host, not asked within the recheck
--      period, fewer than the maximum tries; largest course count first) by setting provider_central_search.requested_at (the search's own priority field).
--      No Firecrawl call is made here; the search's own spend guard (svc_fc_spend, central share, central refresh days) still decides each spend.
--   4. security.aer_source_discover_report_v1(): requests by outcome, providers still to ask, credits used in 24 hours, and the exception queue (providers whose tries are used up,
--      with the last outcome and the next action).
--   5. Job aer-source-discover (catalogued, G1) at :19, command free of numbers (G2).
-- Replaces: nothing. Retires: nothing. Reversal: aer.source_discover_on = 0 (the job does nothing; asked searches already queued run once).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.source_discover_on', 'Entry requirements: find entry pages for providers with nothing stored',
  '1 asks the central-page search (Firecrawl map of the provider''s own website) to look again for providers with no stored entry or course page, within the daily credit limit below. Found pages become entry reader sources; every first read still goes through Layer 4. 0 stops asking.',
  'number', to_jsonb(1), 0, 1, 'switch', 1501, 'Entry requirements', 'security.aer_source_discover_v1; job aer-source-discover',
  'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 3): approve 200 Firecrawl credits/day'),
 ('pipeline', 'aer.source_discover_credits_per_day', 'Entry requirements: Firecrawl credits a day for finding entry pages', 'Credits the providers asked by job aer-source-discover may use in any 24 hours (measured from the vendor usage ledger).',
  'number', to_jsonb(200), 0, 5000, 'credits', 1502, 'Entry requirements', 'security.aer_source_discover_v1', 'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 3): 200 credits a day'),
 ('pipeline', 'aer.source_discover_recheck_days', 'Entry requirements: days before a provider is asked again', 'A provider whose search found no entry page is not asked again for this many days.',
  'number', to_jsonb(30), 1, 365, 'days', 1503, 'Entry requirements', 'security.aer_source_discover_v1', 'Platform Admin decision 10 Nov 2026: avoid crawling the same failed addresses repeatedly'),
 ('pipeline', 'aer.source_discover_max_tries', 'Entry requirements: tries before a provider goes to the exception queue', 'Completed searches (not refusals) after which a provider with no entry page is listed for a person.',
  'number', to_jsonb(3), 1, 10, 'tries', 1504, 'Entry requirements', 'security.aer_source_discover_v1', 'Platform Admin decision 10 Nov 2026: structured exception queue')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.aer_source_discover_requests (
  id bigint generated always as identity primary key,
  provider_id uuid not null,
  requested_at timestamptz not null default now(),
  outcome text check (outcome in ('entry_source_found', 'course_pages_found', 'no_entry_page', 'refused', 'failed', 'superseded')),
  outcome_at timestamptz,
  credits numeric,
  detail jsonb not null default '{}'::jsonb
);
create index if not exists aer_source_discover_requests_provider_idx on pipeline.aer_source_discover_requests(provider_id, requested_at desc);
create unique index if not exists aer_source_discover_requests_open_uq on pipeline.aer_source_discover_requests(provider_id) where outcome is null;
comment on table pipeline.aer_source_discover_requests is 'CF-247 F-AER.01: each request job aer-source-discover made to the central-page search for a provider with nothing stored, and what came of it. The exception queue is read from it.';
alter table pipeline.aer_source_discover_requests enable row level security;
revoke all on pipeline.aer_source_discover_requests from public, anon, authenticated;

create or replace function security.aer_source_discover_v1(p_preview boolean default false) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_cap numeric := security.pipeline_num_v1('aer.source_discover_credits_per_day', 200); v_recheck int := security.pipeline_num_v1('aer.source_discover_recheck_days', 30)::int;
        v_tries int := security.pipeline_num_v1('aer.source_discover_max_tries', 3)::int; v_per numeric; v_used numeric; v_room int; v_settled int := 0; v_asked int := 0; r record; v_out text; v_cr numeric;
begin
  if security.pipeline_num_v1('aer.source_discover_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- (a) settle open requests from what the search recorded
  for r in select q.id, q.provider_id, q.requested_at, s.state, s.searched_at, s.requested_at s_req, s.evidence, s.found
             from pipeline.aer_source_discover_requests q left join pipeline.provider_central_search s on s.provider_id = q.provider_id
            where q.outcome is null loop
    v_out := case when exists (select 1 from pipeline.entry_matrix_sources m where m.provider_id = r.provider_id) then 'entry_source_found'
                  when r.searched_at is not null and r.searched_at >= r.requested_at then
                       case when exists (select 1 from pipeline.coverage_course_pages g where g.provider_id = r.provider_id and g.status = 'bound') then 'course_pages_found' else 'no_entry_page' end
                  when r.s_req is null and r.evidence ? 'refusal' then 'refused'
                  when r.state = 'failed' or (r.evidence ? 'error' and r.s_req is null) then 'failed'
                  else null end;
    if v_out is not null and not p_preview then
      select coalesce(sum(u.units), 0) into v_cr from pipeline.coverage_vendor_usage u
       where u.provider_id = r.provider_id and u.at >= r.requested_at and security.fc_purpose_group_v1(u.purpose) = 'central';
      update pipeline.aer_source_discover_requests set outcome = v_out, outcome_at = now(), credits = v_cr,
             detail = detail || jsonb_build_object('search_state', r.state, 'searched_at', r.searched_at, 'evidence', r.evidence,
                                                   'entry_suggestions', (select count(*) from jsonb_array_elements(coalesce(r.found, '[]'::jsonb)) e where e->>'kind' = 'entry_requirements'))
       where id = r.id;
      v_settled := v_settled + 1;
    end if;
  end loop;
  -- (b) credits the asked providers used in the last 24 hours, and the measured average a provider
  select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u
   where u.at > now() - make_interval(hours => 24) and security.fc_purpose_group_v1(u.purpose) = 'central' -- fixed: the daily limit counts the last 24 hours
     and exists (select 1 from pipeline.aer_source_discover_requests q where q.provider_id = u.provider_id and u.at >= q.requested_at);
  select coalesce(round(sum(units) / nullif(count(distinct provider_id), 0), 1), 4) into v_per from pipeline.coverage_vendor_usage where purpose = 'central_map';
  v_per := greatest(v_per, 1);
  -- requests still open are planned at the average too
  v_used := v_used + v_per * (select count(*) from pipeline.aer_source_discover_requests q where q.outcome is null
                                and not exists (select 1 from pipeline.coverage_vendor_usage u where u.provider_id = q.provider_id and u.at >= q.requested_at));
  v_room := greatest(0, floor((v_cap - v_used) / v_per))::int;
  -- (c) ask the central-page search for that many more providers with nothing stored
  for r in select n.provider_id from security.aer_no_source_route_v1() n
             join catalogue.providers p on p.id = n.provider_id
            where n.route = 'nothing_stored' and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)
              and not exists (select 1 from pipeline.aer_source_discover_requests q where q.provider_id = n.provider_id
                                and (q.outcome is null or (q.outcome in ('no_entry_page', 'course_pages_found', 'failed') and q.outcome_at > now() - make_interval(days => v_recheck))
                                     or (q.outcome = 'refused' and q.outcome_at > now() - make_interval(hours => 24)))) -- fixed: a refusal is asked again after a day
              and (select count(*) from pipeline.aer_source_discover_requests q where q.provider_id = n.provider_id and q.outcome in ('no_entry_page', 'course_pages_found', 'failed')) < v_tries
            order by (select count(*) from catalogue.courses c where c.provider_id = n.provider_id and c.lifecycle_status = 'active') desc, n.provider_id
            limit v_room loop
    if not p_preview then
      insert into pipeline.provider_central_search(provider_id, state, requested_at, attempts, updated_at) values (r.provider_id, 'queued', now(), 0, now())
      on conflict (provider_id) do update set state = case when pipeline.provider_central_search.state = 'leased' and pipeline.provider_central_search.leased_until > now() then pipeline.provider_central_search.state else 'queued' end,
             requested_at = now(), attempts = 0, updated_at = now();
      insert into pipeline.aer_source_discover_requests(provider_id, detail) values (r.provider_id, jsonb_build_object('planned_credits', v_per, 'route', 'nothing_stored'));
    end if;
    v_asked := v_asked + 1;
  end loop;
  return jsonb_build_object('on', true, 'preview', p_preview, 'settled', v_settled, 'asked', v_asked, 'credits_used_24h_or_planned', v_used, 'credits_per_provider', v_per, 'cap', v_cap);
end $f$;
comment on function security.aer_source_discover_v1(boolean) is 'CF-247 F-AER.01: one run of job aer-source-discover: settles earlier requests from what the central-page search recorded, then asks the search to look for entry pages for more providers with nothing stored, within aer.source_discover_credits_per_day (measured). Makes no Firecrawl call itself; preview = true changes nothing.';
revoke all on function security.aer_source_discover_v1(boolean) from public, anon, authenticated;

create or replace function security.aer_source_discover_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  with last as (select distinct on (provider_id) * from pipeline.aer_source_discover_requests order by provider_id, requested_at desc),
  tries as (select provider_id, count(*) filter (where outcome in ('no_entry_page', 'course_pages_found', 'failed')) n from pipeline.aer_source_discover_requests group by 1)
  select jsonb_build_object('contract', 'aer-source-discover-report-v1', 'as_at', now(), 'on', security.pipeline_num_v1('aer.source_discover_on', 0) >= 1,
    'requests_by_outcome', (select coalesce(jsonb_object_agg(coalesce(outcome, 'open'), n), '{}'::jsonb) from (select outcome, count(*) n from pipeline.aer_source_discover_requests group by 1) z),
    'providers_asked', (select count(distinct provider_id) from pipeline.aer_source_discover_requests),
    'providers_with_entry_source_now', (select count(distinct q.provider_id) from pipeline.aer_source_discover_requests q where exists (select 1 from pipeline.entry_matrix_sources m where m.provider_id = q.provider_id)),
    'credits_24h', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.at > now() - make_interval(hours => 24) and security.fc_purpose_group_v1(u.purpose) = 'central'
                      and exists (select 1 from pipeline.aer_source_discover_requests q where q.provider_id = u.provider_id and u.at >= q.requested_at)), -- fixed: report window
    'exceptions', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', l.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'website', p.website, 'tries', t.n,
                                   'last_outcome', l.outcome, 'last_at', l.outcome_at,
                                   'next_action', 'A person adds the entry-requirements page (public.admin_entry_matrix_seed) or confirms the provider has none.') order by p.canonical_name), '[]'::jsonb)
                     from last l join tries t on t.provider_id = l.provider_id join catalogue.providers p on p.id = l.provider_id
                    where t.n >= security.pipeline_num_v1('aer.source_discover_max_tries', 3) and not exists (select 1 from pipeline.entry_matrix_sources m where m.provider_id = l.provider_id)))
$f$;
comment on function security.aer_source_discover_report_v1() is 'CF-247 F-AER.01 (read only): requests job aer-source-discover made and their outcomes, credits used in 24 hours, providers that now have an entry source, and the exception queue (tries used up, no entry page).';
revoke all on function security.aer_source_discover_report_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-source-discover', 'Enrichment', 32, 'Entry requirements: find entry pages for providers with nothing stored',
  'At :19 every hour: settles earlier requests, then asks the central-page search (Firecrawl map of the provider''s own website) to look for the entry-requirements page of more eligible providers that have no stored entry or course page, within Settings > Pipeline settings > Entry requirements: Firecrawl credits a day for finding entry pages (200). Found pages become entry reader sources; a provider with no page after the set tries goes to the exception list.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'aer-source-discover') then
    perform cron.schedule('aer-source-discover', '19 * * * *', $j$select security.aer_source_discover_v1()$j$);
  end if;
end $c$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_source_discover_v1', 'Layer 1', 'Asks the central-page search to find entry pages for providers with nothing stored (credit-capped)', 'active', '{}', '20261111070000'),
 ('function', 'security.aer_source_discover_report_v1', 'Layer 1', 'Outcomes and exception queue of AER source discovery', 'active', '{}', '20261111070000'),
 ('table', 'pipeline.aer_source_discover_requests', 'Layer 1', 'Requests and outcomes of AER source discovery', 'active', '{}', '20261111070000'),
 ('job', 'aer-source-discover', 'Layer 1', 'Runs AER source discovery', 'active', '{}', '20261111070000')
on conflict do nothing;
