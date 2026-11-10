-- CF-247 F-AER.01 AER source discovery: targeted entry-requirements search for providers whose whole-site map is not due (Platform Admin 11 Nov 2026 05:42 AEDT:
-- "Find the issue with AER not admitting fast enough and missing providers ... build readers where required. Make sure platform is autonomous").
-- Evidence (production, read only, 11 Nov 2026 05:45-06:10 AEDT): job aer-source-discover (20261111070000) asked the central-page search about 294 of the 370 eligible
--   providers with nothing stored; 242 requests settled 'refused', 52 open, 0 credits spent, 0 entry sources found. Every refusal was svc_fc_spend 'not_due' (275 on
--   11 Nov, Melbourne day): each of the 370 had a central-page spend within firecrawl central_refresh_days (30), so the whole-site map was refused, the request settled
--   'refused', and the job asked again a day later. 357 of the 370 were last searched before the entry page kind existed (26 Oct), so their stored searches never looked
--   for the page; 310 become due over the next 7 days at about 3.8 credits each. The decision's 200 credits a day (AER recovery pack decision 3) could not be used.
-- What (no new spend authority; the requests are still planned inside aer.source_discover_credits_per_day and every svc_fc_spend rule still applies):
--   1. security.fc_purpose_group_v1: purpose central_entry_search belongs to group central (same daily share; counted by aer_source_discover_v1's credit measure).
--   2. public.svc_fc_spend: a central_entry_search spend is held by its own interval (aer.source_discover_recheck_days), not by the whole-site map's refresh interval.
--   3. public.svc_aer_entry_search_wanted(provider): true while AER source discovery has an open request for the provider, aer.entry_search_on is 1 and no targeted
--      entry search ran for it within the recheck days. The worker (coverage-sweep v0.64.0, central_find) asks it when the whole-site map is refused or found no entry page.
--   4. public.svc_central_entry_record(provider, found, evidence): records the targeted search: replaces only the entry_requirements suggestions in
--      provider_central_search.found (fee, calendar, English and About suggestions kept), sets searched_at so aer_source_discover_v1 settles the request; an error is
--      recorded as a failed try (the request settles 'failed', retried within aer.source_discover_max_tries). Suggestions scoring central.min_suggest_score (4) or more become
--      entry reader sources through the existing security.entry_matrix_attach_v1; every first read still goes through Layer 4.
--   5. Setting aer.entry_search_on (1).
--   6. security.entry_source_score_v1 (stored-link scorer, md5-guarded full definition): the same weak pattern and small-provider top-level rule as the worker, so the
--      free stored-link route (job aer-source-stored-find) finds the same pages from links already stored.
-- Replaces: security.fc_purpose_group_v1, public.svc_fc_spend, security.entry_source_score_v1 (same names; md5-guarded text edits, resulting md5 checked)
-- Retires: nothing.
-- Reversal: aer.entry_search_on = 0 (the worker never asks for a targeted search; behaviour equals 20261111070000).

do $g$
begin
  if md5(pg_get_functiondef('security.fc_purpose_group_v1(text)'::regprocedure)) <> '94950903b554779e4d0793620b3ccad3' then
    raise exception 'security.fc_purpose_group_v1 differs from the live version this migration was written against';
  end if;
  if md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) <> 'a0f43e737574f504de4aad17daf792bb' then
    raise exception 'public.svc_fc_spend differs from the live version this migration was written against';
  end if;
end $g$;

-- 1 and 2: exact text edits of the live definitions (one occurrence each), then the result is checked
do $e$
declare v_d text;
begin
  v_d := pg_get_functiondef('security.fc_purpose_group_v1(text)'::regprocedure);
  execute replace(v_d, $q$when p in ('central_map', 'central_scrape') or p like$q$, $q$when p in ('central_map', 'central_scrape', 'central_entry_search') or p like$q$);
  v_d := pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure);
  execute replace(v_d, $q$    elsif p_provider_id is not null and v_grp = 'central'
          and exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and security.fc_purpose_group_v1(x.purpose) = 'central'
$q$, $q$    -- CF-247 F-AER.01 (20261111090000): a targeted entry-requirements search for a provider that AER source discovery asked about is not held by the
    -- central refresh interval (that interval belongs to the whole-site map, which for 357 of these providers ran before the entry page kind existed).
    -- It is held only by its own interval, aer.source_discover_recheck_days, and still by every rule above (month limit, cost breakers, the central share).
    elsif p_provider_id is not null and p_purpose = 'central_entry_search' then
      if exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose = 'central_entry_search'
                  and x.at > now() - make_interval(days => security.pipeline_num_v1('aer.source_discover_recheck_days', 30)::int)
                  and x.at < now() - interval '6 hours') then  -- fixed: spends within the same search run
        v_why := 'not_due';
      end if;
    elsif p_provider_id is not null and v_grp = 'central'
          and exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and security.fc_purpose_group_v1(x.purpose) = 'central'
$q$);
  if md5(pg_get_functiondef('security.fc_purpose_group_v1(text)'::regprocedure)) <> '8041bf166d40460f8b255ed0bcbc8312' then
    raise exception 'security.fc_purpose_group_v1: the edit did not give the expected definition';
  end if;
  if md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) <> '9dea6e647cce8ab0e08e22e1bc4bf444' then
    raise exception 'public.svc_fc_spend: the edit did not give the expected definition';
  end if;
end $e$;

-- 6: the stored-link scorer keeps the worker's page rules (s371 parity): the weak pattern and the small-provider top-level rule of central.ts v0.64.0,
--    so job aer-source-stored-find finds the same pages free of charge from links already stored
do $g$
begin
  if md5(pg_get_functiondef('security.entry_source_score_v1(text,text)'::regprocedure)) <> '3419ec17dcf4745645660348c7188e72' then
    raise exception 'security.entry_source_score_v1 differs from the live version this migration was written against';
  end if;
end $g$;

CREATE OR REPLACE FUNCTION security.entry_source_score_v1(p_url text, p_title text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- fixed: the same page-type rules and score as the worker's central.ts (strong 6 in the address, 4 in the link text, weak 1.5; a small provider's top-level entry page 4.5; +2 international; -0.5 PDF; +0.2 a level for a short address)
  with x as (
    select lower(replace(coalesce(substring(p_url from '^https?://[^/?#]+(/[^?#]*)'), '/'), '%20', ' ')) path,
           lower(coalesce(substring(p_url from '(\?[^#]*)'), '')) qs, lower(coalesce(p_title, '')) title),
  y as (
    select x.*, cardinality(array_remove(string_to_array(x.path, '/'), '')) depth,
           (x.path ~ 'country[-_ ]?equivalen|academic[-_ ]?(equivalen|entry[-_ ]?requirements?|requirements)|international[-_ ]?(and[-_ ]?overseas[-_ ]?)?qualifications|overseas[-_ ]?qualifications|qualifications?[-_ ]?(by[-_ ]?country|equivalen)|admission[-_ ]?by[-_ ]?country|entry[-_ ]?requirements?[-_ ]?(by[-_ ]?country|for[-_ ]?international)|international[-_ ]?(academic[-_ ]?)?entry[-_ ]?requirements?|minimum[-_ ]?entry[-_ ]?score') strong_path,
           (x.title ~ 'country[-_ ]?equivalen|academic[-_ ]?(equivalen|entry[-_ ]?requirements?|requirements)|international[-_ ]?(and[-_ ]?overseas[-_ ]?)?qualifications|overseas[-_ ]?qualifications|qualifications?[-_ ]?(by[-_ ]?country|equivalen)|admission[-_ ]?by[-_ ]?country|entry[-_ ]?requirements?[-_ ]?(by[-_ ]?country|for[-_ ]?international)|international[-_ ]?(academic[-_ ]?)?entry[-_ ]?requirements?|minimum[-_ ]?entry[-_ ]?score') strong_title,
           (x.path ~ '(entry|admission)[-_ ]?requirements?' or x.title ~ '(entry|admission)[-_ ]?requirements?') weak,
           -- an English-language requirements page is the English rule, not the academic entry matrix
           ((x.path || ' ' || x.title) ~ 'english|ielts|language[-_ ]?requirements?') english,
           ((x.path || x.qs) ~ '/(news|events?|blog|stories|media|staff|people|profiles?|search|login|signin|tags?|category|careers?|jobs|research|alumni|giving|donate|library|shop|cart|wp-admin|feed|residence|housing|accommodation|insurance|medical|parking|workshops?|pubs|publications)(/|$)|refund|extension|request[-_ ]?form|meals?|events[-_ ]?calendar|\.(jpe?g|png|gif|svg|zip|docx?|xlsx?|pptx?)$|[?&](page|s|q)=') noise,
           ((x.path || ' ' || x.title) ~ 'international|overseas|\yintl\y') intl,
           (x.path ~ '\.pdf$') pdf
      from x)
  select case when english or noise or not (strong_path or strong_title or weak) then null
              else round(greatest(case when strong_path then 6 when strong_title then 4 else 1.5 end,
                                  case when depth <= 2 and path ~ '^/((international|study|apply|admissions?|students?)/)?(entry|admissions?)[-_]?requirements?(/|$)' then 4.5 else 0 end)
                         + (case when intl then 2 else 0 end) - (case when pdf then 0.5 else 0 end) + greatest(0, 5 - depth) * 0.2, 1) end
    from y
$function$;

-- 5: the switch
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.entry_search_on', 'Entry requirements: targeted entry-page search for providers asked about',
  '1 lets the central-page search run one targeted search of the provider''s own website for its entry requirements page (about 1 Firecrawl credit) when job aer-source-discover asked about the provider and its whole-site map is not due or found no entry page. It spends inside the daily credits for finding entry pages above and the central share. 0 never asks for it.',
  'number', to_jsonb(1), 0, 1, 'switch', 1505, 'Entry requirements',
  'public.svc_aer_entry_search_wanted; public.svc_fc_spend (purpose central_entry_search); worker coverage-sweep central_find',
  'Platform Admin 11 Nov 2026 05:42 AEDT: build readers where required; spends inside AER recovery pack decision 3 (200 credits a day)')
on conflict (toolset_key, key) do nothing;

-- 3: whether the worker should run the targeted search for a provider
create or replace function public.svc_aer_entry_search_wanted(p_provider_id uuid) returns boolean
language plpgsql stable security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.pipeline_num_v1('aer.entry_search_on', 0) >= 1
     and security.pipeline_num_v1('aer.source_discover_on', 0) >= 1
     and exists (select 1 from pipeline.aer_source_discover_requests q where q.provider_id = p_provider_id and q.outcome is null)
     and not exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose = 'central_entry_search'
                       and x.at > now() - make_interval(days => security.pipeline_num_v1('aer.source_discover_recheck_days', 30)::int));
end $f$;
comment on function public.svc_aer_entry_search_wanted(uuid) is 'CF-247 F-AER.01 (20261111090000): true while AER source discovery has an open request for the provider, aer.entry_search_on is 1 and no targeted entry-requirements search ran for it within aer.source_discover_recheck_days. Asked by worker coverage-sweep central_find.';
revoke all on function public.svc_aer_entry_search_wanted(uuid) from public, anon, authenticated;
grant execute on function public.svc_aer_entry_search_wanted(uuid) to service_role;

-- 4: record the targeted search without losing the other page kinds
create or replace function public.svc_central_entry_record(p_provider_id uuid, p_found jsonb, p_evidence jsonb) returns void
language plpgsql security definer set search_path to '' as $f$
declare v_entry jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_entry
    from jsonb_array_elements(case when jsonb_typeof(p_found) = 'array' then p_found else '[]'::jsonb end) e
   where e->>'kind' = 'entry_requirements' and e->>'url' ~* '^https?://';
  if coalesce(p_evidence, '{}'::jsonb) ? 'error' then
    -- a failed try: the request settles 'failed' (security.aer_source_discover_v1) and is asked again within the maximum tries
    update pipeline.provider_central_search s
       set state = 'queued', leased_until = null, requested_at = null, updated_at = now(),
           evidence = coalesce(s.evidence, '{}'::jsonb) || jsonb_build_object('error', p_evidence->>'error', 'entry_search', p_evidence)
     where s.provider_id = p_provider_id;
    return;
  end if;
  update pipeline.provider_central_search s
     set found = coalesce((select jsonb_agg(e) from jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e where e->>'kind' is distinct from 'entry_requirements'), '[]'::jsonb) || v_entry,
         evidence = (coalesce(s.evidence, '{}'::jsonb) - 'error' - 'refusal' - 'note') || jsonb_build_object('entry_search', p_evidence || jsonb_build_object('suggested', jsonb_array_length(v_entry))),
         state = 'done', searched_at = now(), requested_at = null, leased_until = null, updated_at = now()
   where s.provider_id = p_provider_id;
end $f$;
comment on function public.svc_central_entry_record(uuid, jsonb, jsonb) is 'CF-247 F-AER.01 (20261111090000): records a targeted entry-requirements search of a provider''s own website: replaces only the entry_requirements suggestions in provider_central_search.found and sets searched_at; an error is a failed try. Called by worker coverage-sweep central_find.';
revoke all on function public.svc_central_entry_record(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.svc_central_entry_record(uuid, jsonb, jsonb) to service_role;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.svc_aer_entry_search_wanted', 'Layer 1', 'Whether the central-page search should run a targeted entry-requirements search for a provider AER discovery asked about', 'active', '{}', '20261111090000'),
 ('function', 'public.svc_central_entry_record', 'Layer 1', 'Records a targeted entry-requirements search without losing the other central page suggestions', 'active', '{}', '20261111090000')
on conflict do nothing;
