-- CF-247 S1-RM-Design (Platform Admin 19 Nov 2026 16:18, s766 follow-up): the two stored-page reads queued by 20261119172000 (Torrens University Australia and Moore College)
-- were taken by the scheduled worker and held by its recovery memory (recovery_knowledge_unchanged_failure: the same stored page already failed, so no model call was made;
-- nothing was spent). What changed since that failure is the identity: the page heading names a trading name that is now recorded. The Platform Admin's directive names these
-- two reads, so they are asked for the way an operator's Fill description click asks for one (public.admin_provider_description_fill_v1): a new queued read marked on demand,
-- with the worker started at once, after an on-demand request is opened with its estimate (security.on_demand_open_v1, Pilot CLAUDE.md on-demand rule).
-- Scope: openrouter only (GPT-4.1 mini, about US$0.0015 a read, estimate US$0.003). Firecrawl is not asked for and stays off (pdesc.acquire_firecrawl 0, guarded): both providers
-- are read from the stored copy. The reader, its identity proof (the page heading must name the provider), its grounding checks and the unchanged machine admission decide each one;
-- a description is never overwritten (neither provider has one) and the manual locks are honoured. Nothing is admitted by this change.
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
create temp table cf_s766b on commit drop as
  select p.id as provider_id, coalesce(p.display_name, p.canonical_name) as name from catalogue.providers p
   where p.stable_key in ('provider:cricos:03389e', 'provider:cricos:00682b')
     and p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
     and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state in ('queued', 'reading', 'proposed'))
     and security.provider_description_stored_v1(p.id) is not null
     and coalesce((security.provider_description_identity_v1(p.id, (select a.source_url from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(p.id)))->>'ok')::boolean, false);
create temp table cf_s766b_od on commit drop as
  select security.on_demand_open_v1('claude_session', 'S1-RM-Design s766: read the stored About page of Torrens University Australia and Moore College now the trading names Torrens University and Moore Theological College are recorded',
           (select coalesce(array_agg(provider_id), '{}') from cf_s766b), jsonb_build_object('reads', (select count(*) from cf_s766b), 'ai_usd', 0.003, 'firecrawl_credits', 0),
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
  if v_n > 2 then raise exception 'post-check: % reads queued, more than the 2 providers', v_n; end if;
  if exists (select 1 from pipeline.provider_description_reads r where r.state in ('queued', 'reading', 'proposed') group by r.provider_id having count(*) > 1) then raise exception 'post-check: a provider has two open reads'; end if;
  if exists (select 1 from cf_s766b c join catalogue.providers p on p.id = c.provider_id where nullif(btrim(p.description), '') is not null) then raise exception 'post-check: a provider with a description was queued'; end if;
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'post-check: Firecrawl is on for provider descriptions'; end if;
  raise notice 's766 on-demand read: % reads queued', v_n;
end $c$;
