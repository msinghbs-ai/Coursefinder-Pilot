-- CF-247 S2-BOOST-Providers (Platform Admin 19 Nov 2026 07:39, decisions 2 and 4: route provider descriptions back to GPT-4.1 mini with
-- prompt version 5 and run a bounded re-read, at most US$0.50 and no Firecrawl). Data only: no table, column, function or job.
-- What was read live (19 Nov 07:40 to 07:55 AEDT, SELECT only):
--   * Route provider_description: cascade [qwen3-30b], daily cap US$1, US$0.0424 spent today. GPT-4.1 mini is in the model catalogue as
--     not_allowed (Platform Admin 13 Nov 19:14, cost) and has no qualification row for this service. Its record on this service: 158 usable
--     readings of 392 with prompt version 4, US$0.00154 a reading on average (811 paid readings); Qwen3 30B: 8 of 39 with version 5.
--   * Published, active providers with no description, no manual lock and no open read: 598. Their latest read: 58 held by grounding (quote
--     not on the page, unsupported sentence or number), 196 held by the page identity proof (no AI call is made for those), 238 never read
--     of which 13 have a stored official page. The 54 readings restored to Layer 4 by 20261119080000 keep their open reading and are not queued.
-- 1 GPT-4.1 mini is allowed again, qualified for provider_description only (the Platform Admin's decision is the evidence), and is the
--   service's one model; the daily cap of the service is US$0.50, so today's spend cannot pass it. Activation is this step, by decision,
--   and is not a side effect of the qualification row.
-- 2 pdesc.acquire_firecrawl is 0: the reader takes a stored copy or reads the page directly, and makes no Firecrawl call.
-- 3 Drain pdesc-gpt41-drain: one read is queued for each of the 58 + 196 + 13 providers above. The reader, its identity proof (with the s762
--   rule), its grounding checks and the unchanged machine admission decide each one; a description a person wrote is never overwritten.
-- 4 (addendum 08:17, F-PDESC.01/.02) dates, calendar and timetable stay refused source words (block 2b).
-- G1: no job. G2: the cap and the switch are a route value and a setting. G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $g$
begin
  if (select cascade from pipeline.ai_service_routes where service_code = 'provider_description') is distinct from array['qwen3-30b']
     and (select cascade from pipeline.ai_service_routes where service_code = 'provider_description') is distinct from array['gpt-4.1-mini'] then
    raise exception 'the provider_description route is not the one read on 19 Nov 07:40 (the Platform Admin changed it); nothing applied';
  end if;
  if not exists (select 1 from pipeline.ai_model_catalogue where code = 'gpt-4.1-mini') then raise exception 'gpt-4.1-mini is not in the model catalogue'; end if;
  if (select version from pipeline.provider_description_prompts where status = 'active') is distinct from 5 then raise exception 'the active provider-description prompt is not version 5; nothing applied'; end if;
end $g$;

-- 1 ------------------------------------------------------------------------------------------------------------------------- the route
update pipeline.ai_model_catalogue
   set status = 'allowed', changed_at = now(), reason = 'Platform Admin 19 Nov 2026 07:39: allowed again for provider descriptions (bounded stored-page re-read)',
       note = 'Allowed for the provider description route only (Platform Admin 19 Nov 2026 07:39). 13 Nov 2026 19:14: too expensive for general use; no other service lists it.'
 where code = 'gpt-4.1-mini' and status <> 'allowed';

insert into pipeline.ai_route_qualifications (service_code, model_code, prompt_version, status, provisional, evidence, evidence_detail, qualified_at, changed_at)
select 'provider_description', 'gpt-4.1-mini', 'provider-description-p5', 'qualified', true,
       'Platform Admin decision 19 Nov 2026 07:39 (route provider descriptions back to GPT-4.1 mini with prompt version 5); live record with prompt version 4: 158 usable readings of 392; regression qualification with version 5 pending',
       jsonb_build_object('usable_p4', 158, 'readings_p4', 392, 'qwen3_30b_usable_p5', 8, 'qwen3_30b_readings_p5', 39, 'read_at', '2026-11-18T20:07:00Z'), now(), now()
 where not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'provider_description' and q.model_code = 'gpt-4.1-mini');

update pipeline.ai_service_routes
   set cascade = array['gpt-4.1-mini'], previous_model = 'qwen/qwen3-30b-a3b-instruct-2507', daily_usd_cap = 0.5, changed_at = now(),
       reason = 'Platform Admin 19 Nov 2026 07:39: GPT-4.1 mini with prompt version 5; daily cap US$0.50 for the bounded stored-page re-read'
 where service_code = 'provider_description' and cascade = array['qwen3-30b'];

-- 2 ------------------------------------------------------------------------------------------------------------------- no Firecrawl
update pipeline.platform_toolset_settings
   set value = '0'::jsonb, reason = 'Platform Admin 19 Nov 2026 07:39: no Firecrawl spend for the provider description re-read (stored copy or direct read only)', updated_at = now()
 where toolset_key = 'pipeline' and key = 'pdesc.acquire_firecrawl' and value <> '0'::jsonb;

-- 2b ------------------------------------------------------------------------------------- F-PDESC.01/.02 source words (addendum 08:17)
-- There is no allow list of source words: the one list is pdesc.refused_path_words, the words that make a page address unusable as a
-- description source. dates, calendar and timetable have been in it since 9 Nov 2026. This block keeps them there: a missing word is put back.
update pipeline.platform_toolset_settings s
   set value = s.value || (select coalesce(jsonb_agg(w), '[]'::jsonb) from unnest(array['dates', 'calendar', 'timetable']) w where not s.value ? w),
       reason = 'Platform Admin 19 Nov 2026 08:17 (F-PDESC.01/.02): dates, calendar and timetable pages are never a description source', updated_at = now()
 where s.toolset_key = 'pipeline' and s.key = 'pdesc.refused_path_words' and not s.value ?& array['dates', 'calendar', 'timetable'];

-- 3 ------------------------------------------------------------------------------------------------------------------------ the drain
create temp table cf_drain on commit drop as
  with miss as (
    select p.id from catalogue.providers p
     where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
       and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state in ('queued', 'reading', 'proposed'))),
  lr as (select distinct on (r.provider_id) r.provider_id, r.state, r.rule from pipeline.provider_description_reads r join miss m on m.id = r.provider_id
          order by r.provider_id, r.created_at desc)
  select lr.provider_id, case when lr.rule in ('provider_name_conflict', 'provider_name_not_proved') then 'identity' else 'grounding' end basis
    from lr where lr.state = 'held' and lr.rule in ('quote_not_on_page', 'unsupported_sentence', 'unsupported_numeric_claim', 'provider_name_conflict', 'provider_name_not_proved')
  union all
  select m.id, 'never_read_stored' from miss m
   where not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = m.id) and security.provider_description_stored_v1(m.id) is not null;

insert into pipeline.provider_description_reads(provider_id, state, next_try_at, reason, checks)
select c.provider_id, 'queued', now(), 'Re-read with GPT-4.1 mini and prompt version 5 (pdesc-gpt41-drain, Platform Admin 19 Nov 2026 07:39)',
       jsonb_build_object('drain', jsonb_build_object('rule', 'pdesc-gpt41-drain', 'basis', c.basis, 'at', now()))
  from cf_drain c;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'layer4', 'rule_execute', 'pdesc-gpt41-drain',
       jsonb_build_object('queued', (select count(*) from cf_drain), 'by_basis', (select jsonb_object_agg(basis, n) from (select basis, count(*) n from cf_drain group by 1) z),
                          'route', 'gpt-4.1-mini', 'daily_usd_cap', 0.5, 'firecrawl', 0),
       'c0ffee00-0000-4000-8000-000000000150'::uuid;

do $c$
declare v jsonb := security.ai_route_v1('provider_description');
begin
  if v->>'model' is distinct from 'openai/gpt-4.1-mini' or (v->'cap'->>'usd')::numeric <> 0.5 then raise exception 'post-check: the route does not answer GPT-4.1 mini with a US$0.50 cap: %', v - 'key'; end if;
  if exists (select 1 from pipeline.ai_service_routes r where r.service_code <> 'provider_description' and 'gpt-4.1-mini' = any (r.cascade)) then raise exception 'post-check: another service lists gpt-4.1-mini'; end if;
  if not (select value ?& array['dates', 'calendar', 'timetable'] from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.refused_path_words') then raise exception 'post-check: dates, calendar or timetable is not a refused source word'; end if;
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'post-check: Firecrawl is still on for provider descriptions'; end if;
  if exists (select 1 from pipeline.provider_description_reads r where r.state in ('queued', 'reading', 'proposed') group by r.provider_id having count(*) > 1) then raise exception 'post-check: a provider has two open reads'; end if;
  if exists (select 1 from cf_drain c join catalogue.providers p on p.id = c.provider_id where nullif(btrim(p.description), '') is not null) then raise exception 'post-check: a provider with a description was queued'; end if;
  raise notice 'pdesc-gpt41-drain: % reads queued', (select count(*) from cf_drain);
end $c$;
