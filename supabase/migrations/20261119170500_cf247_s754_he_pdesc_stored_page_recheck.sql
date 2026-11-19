-- CF-247 S2-BOOST (Platform Admin 19 Nov 2026 16:00, s754): triage of the university and higher-education provider descriptions, and one bounded
-- GPT-4.1 mini re-check of the holds a stored-page read can still settle. Data only: no table, column, function, job or setting (G3 75/48).
-- What was read live (19 Nov 2026 16:05 to 16:25 AEDT, by the rolled-back dry run only, no interactive query): 201 published, active providers
-- of the types university, university_college, higher_education_institute and wananga; 141 hold a description, 60 do not. By their latest read:
--   ready to admit 0 (no reading passes the machine rule); Layer 4 pending 8 (all declined by the machine rule, each needs a person);
--   identity holds 29 (another active provider holds the host 9, the page does not prove the full name 18, identity unconfirmed 1, sub-unit page 1);
--   grounding holds outside Layer 4 2 (read today with GPT-4.1 mini); other content holds 8; no stored page and never read 13.
-- The identity proof runs before any model call and takes its names from the catalogue and the register only, so a further read cannot pass
-- the 29 identity holds; reaching them needs a recorded trading name or a person, not a weaker proof. Holds read today with GPT-4.1 mini are not
-- read again (a second read of the same page by the same model is not new evidence).
-- This change queues one read for each provider of those types that: is published and active with no description and no manual lock, has a
-- stored official page, has no open read, and whose latest read was held by a content rule (not identity, host, sub-unit or a refused source
-- word) and was not made by GPT-4.1 mini in the last day. On the live read that is 2 providers (Kingsford Institute of Higher Education and
-- Australian Guild of Education, both held by the sentence count on 10 and 11 Nov). The reader, its identity proof, its grounding checks and the
-- unchanged machine admission decide each one; a description a person wrote is never overwritten (the claim takes only providers with none).
-- Spend: GPT-4.1 mini at about US$0.0015 a read, inside the service cap of US$0.50 a day; pdesc.acquire_firecrawl stays 0 (guarded below).
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $g$
begin
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'guard: Firecrawl is on for provider descriptions; nothing queued'; end if;
  if (security.ai_route_v1('provider_description')->>'model') is distinct from 'openai/gpt-4.1-mini'
     or (security.ai_route_v1('provider_description')->'cap'->>'usd')::numeric > 0.5 then
    raise exception 'guard: the provider_description route is not GPT-4.1 mini with a cap of at most US$0.50; nothing queued';
  end if;
end $g$;

create temp table cf_s754 on commit drop as
  with he as (
    select p.id from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id
     where coalesce(to_jsonb(t)->>'code', to_jsonb(t)->>'name') in ('university', 'university_college', 'higher_education_institute', 'wananga')
       and p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
       and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state in ('queued', 'reading', 'proposed'))),
  lr as (select distinct on (r.provider_id) r.provider_id, r.state, r.rule, r.model, r.created_at
           from pipeline.provider_description_reads r join he on he.id = r.provider_id order by r.provider_id, r.created_at desc)
  select lr.provider_id, lr.rule from lr
   where lr.state = 'held'
     and lr.rule not in ('provider_name_conflict', 'provider_name_not_proved', 'provider_host_conflict', 'provider_subunit_source', 'refused_word', 'refused_host')
     and lr.rule not like 'machine_declined_identity%'
     and not (coalesce(lr.model, '') ilike '%gpt-4.1-mini%' and lr.created_at > now() - interval '1 day')
     and security.provider_description_stored_v1(lr.provider_id) is not null;

insert into pipeline.provider_description_reads(provider_id, state, next_try_at, reason, checks)
select c.provider_id, 'queued', now(), 'Re-check with GPT-4.1 mini from the stored page (s754, Platform Admin 19 Nov 2026 16:00)',
       jsonb_build_object('drain', jsonb_build_object('rule', 's754-he-pdesc-recheck', 'basis', c.rule, 'at', now()))
  from cf_s754 c;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'layer4', 'rule_execute', 's754-he-pdesc-recheck',
       jsonb_build_object('queued', (select count(*) from cf_s754), 'by_rule', (select coalesce(jsonb_object_agg(rule, n), '{}'::jsonb) from (select rule, count(*) n from cf_s754 group by 1) z),
                          'route', 'gpt-4.1-mini', 'firecrawl', 0),
       'c0ffee00-0000-4000-8000-000000000150'::uuid;

do $c$
declare v_n int := (select count(*) from cf_s754);
begin
  if v_n > 10 then raise exception 'post-check: % reads queued, more than the 2 read live (at most 10)', v_n; end if;  -- fixed: the live read plus drift
  if exists (select 1 from pipeline.provider_description_reads r where r.state in ('queued', 'reading', 'proposed') group by r.provider_id having count(*) > 1) then raise exception 'post-check: a provider has two open reads'; end if;
  if exists (select 1 from cf_s754 c join catalogue.providers p on p.id = c.provider_id where nullif(btrim(p.description), '') is not null) then raise exception 'post-check: a provider with a description was queued'; end if;
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'post-check: Firecrawl is on for provider descriptions'; end if;
  raise notice 's754-he-pdesc-recheck: % reads queued', v_n;
end $c$;
