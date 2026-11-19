-- CF-247 S1-RM-Design (Platform Admin 19 Nov 2026 16:18 and the addendum of 17:02, s766 follow-up): more trading names, one more host owner, and the reads asked for on demand.
-- 1 The two stored-page reads queued by 20261119172000 (Torrens University Australia and Moore College) were taken by the scheduled worker and held by its recovery memory
--   (recovery_knowledge_unchanged_failure: the same stored page already failed, so no model call was made; nothing was spent).
-- 2 S2-BOOST (admin #651) named 8 higher-education providers whose stored page is blocked only by the name. Read live today (rolled-back dry run, stored page headings from
--   each provider's last read), the page heading names the institution with these names, so they are recorded as trading names (catalogue.provider_aliases, type trading_name):
--     Auckland University of Technology (AUT): "About Auckland University of Technology in New Zealand - AUT"  -> Auckland University of Technology in New Zealand, AUT
--     CIHE Australia: "ABOUT | CIHE | Crown Institute of Higher Education | Australia"                          -> CIHE, Crown Institute of Higher Education
--     Murdoch College, The University of Adelaide College, Kaplan ...: "About Us | Kaplan Murdoch"            -> Kaplan Murdoch
--     Sydney Met (CRICOS 03906M): the page names Sydney Metropolitan Institute of Technology                  -> Sydney Metropolitan Institute of Technology
--   Torrens University and Moore Theological College were recorded by 20261119172000. Not recorded: Lyons College (the catalogue name already is "Lyons College"; the hold is the h1
--   "Why Choose Lyons College") and Te Whare Wananga o Awanuiarangi (the name is already the catalogue name; the hold is the title segment "... logo"). An alias cannot clear either,
--   and the proof is not weakened to reach them; each needs a person in Layer 4.
-- 3 Holmes Institute: three active registrations share www.holmesinstitute.edu.au (CRICOS 02639M, 02767C, 02727M; no stored page for any). The Melbourne registration 02639M is recorded as
--   the owner of the host (Melbourne is the primary city of all three records and the provider's head office); the other two stay held and a person may move the owner row.
-- 4 The reads are asked for the way an operator's Fill description click asks for one (public.admin_provider_description_fill_v1): an on-demand request opened with its estimate
--   (security.on_demand_open_v1, Pilot CLAUDE.md on-demand rule), new queued reads marked on demand, the worker started at once. Scope: openrouter only (GPT-4.1 mini, about US$0.0015 a read,
--   estimate US$0.01 for six reads, well inside the US$0.10 cap). Firecrawl is not asked for and stays off (pdesc.acquire_firecrawl 0, guarded); every provider read has a stored copy.
--   The reader, its identity proof (the page heading must name the provider), its grounding checks and the unchanged machine admission decide each one; a description is never
--   overwritten (none of the providers has one) and the manual locks are honoured. Nothing is admitted by this change. Consumer API untouched (G3 75/48).
-- Replaces: the two held reads of 20261119172000 (kept as they are; the admission ledger refers to them)
-- Retires: nothing
set local lock_timeout = '5s';
do $g$
begin
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'guard: Firecrawl is on for provider descriptions; nothing queued'; end if;
  if (security.ai_route_v1('provider_description')->>'model') is distinct from 'openai/gpt-4.1-mini'
     or (security.ai_route_v1('provider_description')->'cap'->>'usd')::numeric > 0.5 then
    raise exception 'guard: the provider_description route is not GPT-4.1 mini with a cap of at most US$0.50; nothing queued';
  end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then raise exception 'guard: the provider description reader is switched off'; end if;
end $g$;
insert into catalogue.provider_aliases(provider_id, alias, alias_type)
select p.id, v.alias, 'trading_name'
  from (values ('provider:nzqa:7008', 'Auckland University of Technology in New Zealand'), ('provider:nzqa:7008', 'AUT'),
               ('provider:cricos:03744b', 'CIHE'), ('provider:cricos:03744b', 'Crown Institute of Higher Education'),
               ('provider:cricos:03127e', 'Kaplan Murdoch'), ('provider:cricos:03906m', 'Sydney Metropolitan Institute of Technology')) v(k, alias)
  join catalogue.providers p on p.stable_key = v.k and p.lifecycle_status = 'active' and p.publication_status = 'published'
on conflict (provider_id, alias, coalesce(locale, '')) do nothing;
insert into pipeline.provider_host_owners(host, owner_provider_id, reason, recorded_by)
select security.site_host_v1(p.website), p.id, 'Holmes Institute: three registrations (02639M Melbourne, 02767C Sydney, 02727M Brisbane, Cairns and Surfers Paradise) share this host; the Melbourne registration is recorded as the owner (s766 addendum)', 's766 Platform Admin 19 Nov 2026 17:02'
  from catalogue.providers p where p.stable_key = 'provider:cricos:02639m' and p.lifecycle_status = 'active' and p.publication_status = 'published' and security.site_host_v1(p.website) is not null
on conflict (host) do nothing;
create temp table cf_s766b on commit drop as
  select p.id as provider_id, coalesce(p.display_name, p.canonical_name) as name from catalogue.providers p
   where exists (select 1 from catalogue.provider_aliases a where a.provider_id = p.id and a.alias_type = 'trading_name' and a.valid_to is null)
     and p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
     and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state in ('queued', 'reading', 'proposed'))
     and security.provider_description_stored_v1(p.id) is not null
     and coalesce((security.provider_description_identity_v1(p.id, (select a.source_url from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(p.id)))->>'ok')::boolean, false);
create temp table cf_s766b_od on commit drop as
  select security.on_demand_open_v1('claude_session', 'S1-RM-Design s766: read the stored About page of the six higher-education providers whose only block was a trading name, now the trading names are recorded',
           (select coalesce(array_agg(provider_id), '{}') from cf_s766b), jsonb_build_object('reads', (select count(*) from cf_s766b), 'ai_usd', 0.01, 'firecrawl_credits', 0),
           'c0ffee00-0000-4000-8000-000000000150'::uuid, array['openrouter']) as r
   where exists (select 1 from cf_s766b);
insert into pipeline.provider_description_reads(provider_id, state, next_try_at, reason, checks)
select c.provider_id, 'queued', now(), 'Read from the stored page with the trading name recorded, asked for on demand (s766, Platform Admin 19 Nov 2026 16:18)',
       jsonb_build_object('on_demand', jsonb_build_object('by', 'c0ffee00-0000-4000-8000-000000000150', 'at', now()),
                          'drain', jsonb_build_object('rule', 's766-au-university-identity', 'basis', 'recovery_knowledge_unchanged_failure', 'at', now()),
                          'on_demand_request', (select r->>'id' from cf_s766b_od))
  from cf_s766b c;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'layer4', 'rule_execute', 's766-au-university-identity-on-demand',
       jsonb_build_object('queued', (select count(*) from cf_s766b), 'route', 'gpt-4.1-mini', 'firecrawl', 0, 'on_demand_request', (select r->>'id' from cf_s766b_od)),
       'c0ffee00-0000-4000-8000-000000000150'::uuid;
do $s$
begin
  if exists (select 1 from cf_s766b) then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int));
  end if;
end $s$;
do $c$
declare v_n int := (select count(*) from cf_s766b);
begin
  if v_n > 6 then raise exception 'post-check: % reads queued, more than the 6 providers', v_n; end if;
  if (select count(*) from catalogue.provider_aliases where alias_type = 'trading_name') < 8 then raise exception 'post-check: fewer than 8 trading names recorded'; end if;
  if not exists (select 1 from pipeline.provider_host_owners where host = 'holmesinstitute.edu.au') then raise exception 'post-check: the Holmes Institute host owner is not recorded'; end if;
  if exists (select 1 from pipeline.provider_description_reads r where r.state in ('queued', 'reading', 'proposed') group by r.provider_id having count(*) > 1) then raise exception 'post-check: a provider has two open reads'; end if;
  if exists (select 1 from cf_s766b c join catalogue.providers p on p.id = c.provider_id where nullif(btrim(p.description), '') is not null) then raise exception 'post-check: a provider with a description was queued'; end if;
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'post-check: Firecrawl is on for provider descriptions'; end if;
  raise notice 's766 on-demand read: % reads queued', v_n;
end $c$;
