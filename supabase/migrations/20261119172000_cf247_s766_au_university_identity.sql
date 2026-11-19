-- CF-247 S1-RM-Design (Platform Admin 19 Nov 2026 16:18, s766): the identity holds on Australian university descriptions that the catalogue can settle.
-- What was read live (19 Nov 2026, by the rolled-back dry run only, no interactive query), head 20261119160000:
--   Victoria University: two active records, CRICOS 00124K (bac82321, 279 active courses, vu.edu.au) and CRICOS 02475D (0f5373c8, 35 active courses, vu.edu.au/international).
--     They are two registrations, not one record twice: 120 tables reference a provider, 34 of the 35 courses share a title with the other record and none shares a code.
--     No merge function exists and nothing is deleted by a migration, so neither record is merged or retired here (see the hand-over in the admin CURRENT-STATE).
--   RMIT University (8e1adb6c, 00122A) and "RMIT University Pathways, RMIT UP" (30b81368) hold the host rmit.edu.au; Western Sydney University (1719c3ba, 00917K) and
--     "UWS College ... The College" (bd473ff9) hold westernsydney.edu.au. Each pair blocks the other (provider_host_conflict).
--   Torrens University Australia (fec52f92) and Moore College (a2a42020) have a stored About page; the page names "Torrens University" and "Moore Theological College",
--     the catalogue names do not, so the proof held both on provider_name_conflict.
--   The record named "NA" (84289838, CRICOS 03811G) is a private VET provider (Myotherapy, Real Estate, Beauty Therapy) with 7 active courses and a manually locked website
--     of aucd.edu.au. It is not the Australian University College of Divinity and it holds active courses, so it is not retired or unlinked here.
-- What this change does:
--   1 records which provider owns a host (pipeline.provider_host_owners) and makes the identity proof honour it: the owner is clear on its host, another provider that
--     holds the same host stays held with the same rule, a host with no recorded owner is decided exactly as before. Owners: Victoria University (bac82321), RMIT University
--     and Western Sydney University.
--   2 records "Torrens University" and "Moore Theological College" as trading names (catalogue.provider_aliases, alias type trading_name), each taken from the provider's own
--     stored About page title, and lets the description reader use trading names as identity names (public.svc_provider_description_next).
--   3 queues one stored-page read for each provider of the two that has a stored page, no description and no manual lock. The scheduled worker runs it under its own limits.
-- Not changed: the consumer API (G3 stays 75 functions and 48 tables; a table in schema pipeline, no public table or function), the proof's word rules, the manual locks,
-- any description a person wrote. pdesc.acquire_firecrawl stays 0 (guarded). GPT-4.1 mini at about US$0.0015 a read inside the service cap of US$0.50 a day.
-- Replaces: the host-conflict test inside security.provider_description_identity_v1 (identical when no owner is recorded) and the identity names list inside public.svc_provider_description_next (the catalogue names first, then trading names)
-- Retires: nothing
set local lock_timeout = '5s';
do $g$
begin
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'guard: Firecrawl is on for provider descriptions; nothing changed'; end if;
  if (security.ai_route_v1('provider_description')->>'model') is distinct from 'openai/gpt-4.1-mini'
     or (security.ai_route_v1('provider_description')->'cap'->>'usd')::numeric > 0.5 then
    raise exception 'guard: the provider_description route is not GPT-4.1 mini with a cap of at most US$0.50; nothing changed';
  end if;
  -- the live definitions are the ones read on 19 Nov 2026 (a changed definition means another change landed first)
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'provider_description_identity_v1')
       is distinct from '8c1399260b3c7da5e427452f22ba3c6f' then raise exception 'guard: security.provider_description_identity_v1 is not the definition this change was written against'; end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'svc_provider_description_next')
       is distinct from 'f7b463e1df56305e32404c73493781b6' then raise exception 'guard: public.svc_provider_description_next is not the definition this change was written against'; end if;
end $g$;

-- 1 host owners
create table if not exists pipeline.provider_host_owners (
  host              text primary key,
  owner_provider_id uuid not null references catalogue.providers(id),
  reason            text not null,
  recorded_by       text not null,
  recorded_at       timestamptz not null default now()
);
comment on table pipeline.provider_host_owners is 'CF-247 s766 (Platform Admin 19 Nov 2026 16:18): which provider owns a website host when more than one active provider records it (a university and its pathway college, or two registrations of one university). The provider description identity proof treats the owner as clear on the host and every other provider that holds it as in conflict; a host with no row is decided as before. Written by a migration or the Platform Admin with a reason; read by security.provider_description_identity_v1.';
alter table pipeline.provider_host_owners enable row level security;
revoke all on pipeline.provider_host_owners from public, anon, authenticated;

insert into pipeline.provider_host_owners(host, owner_provider_id, reason, recorded_by)
select security.site_host_v1(p.website), p.id,
       case p.stable_key
         when 'provider:cricos:00124k' then 'Victoria University (CRICOS 00124K) is the university; the second record (CRICOS 02475D, vu.edu.au/international) is a separate registration on the same host'
         when 'provider:cricos:00122a' then 'RMIT University is the parent; RMIT University Pathways (RMIT UP) is a unit on rmit.edu.au/up'
         else 'Western Sydney University is the parent; UWS College (The College) is a unit on westernsydney.edu.au/thecollege' end,
       's766 Platform Admin 19 Nov 2026 16:18'
  from catalogue.providers p
 where p.stable_key in ('provider:cricos:00124k', 'provider:cricos:00122a', 'provider:cricos:00917k')
   and p.lifecycle_status = 'active' and p.publication_status = 'published' and security.site_host_v1(p.website) is not null
on conflict (host) do nothing;

create or replace function security.provider_description_identity_v1(p_provider uuid, p_url text) returns jsonb
language plpgsql stable security definer set search_path to ''
as $f$
declare p catalogue.providers%rowtype; v_finding text; v_other uuid; v_host text; v_owner uuid;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null or p.lifecycle_status <> 'active' or p.publication_status <> 'published'
     or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)
     or security.provider_lifecycle_held_v1(p_provider) then
    return jsonb_build_object('ok', false, 'rule', 'provider_inactive', 'reason', 'The provider is not active and published, or its lifecycle is held.');
  end if;
  select f.check_code into v_finding from pipeline.provider_identity_findings f
   where f.provider_id = p_provider and f.state = 'open'
   order by f.check_code limit 1;
  if v_finding is not null then
    return jsonb_build_object('ok', false, 'rule', 'identity_' || v_finding,
      'reason', 'An existing provider identity finding requires resolution: ' || v_finding);
  end if;
  if security.provider_page_host_v1(p_provider, p_url) <> 'own' then
    return jsonb_build_object('ok', false, 'rule', 'wrong_host', 'reason', 'The source is not on an approved provider host.');
  end if;
  -- s766: a host with a recorded owner is decided by the record. The owner is clear; any other provider that holds the host stays in conflict.
  v_host := security.site_host_v1(p_url);
  select o.owner_provider_id into v_owner from pipeline.provider_host_owners o
   where v_host is not null and o.host = v_host
     and exists (select 1 from catalogue.providers w where w.id = o.owner_provider_id and w.lifecycle_status = 'active');
  if v_owner = p_provider then
    return jsonb_build_object('ok', true, 'rule', 'identity_clear', 'via', 'recorded_host_owner');
  end if;
  if v_owner is not null then
    return jsonb_build_object('ok', false, 'rule', 'provider_host_conflict', 'conflicting_provider_id', v_owner,
      'reason', 'Another active provider is the recorded owner of the source host; exact provider identity requires resolution.');
  end if;
  -- Even an own host is ambiguous when it is another current provider's primary host.
  -- Never infer that a university and similarly named college are interchangeable.
  select o.id into v_other from catalogue.providers o
   where o.id <> p_provider and o.lifecycle_status = 'active'
     and security.site_host_v1(o.website) = security.site_host_v1(p_url)
     and security.site_host_v1(p_url) is not null
   order by o.id limit 1;
  if v_other is not null then
    return jsonb_build_object('ok', false, 'rule', 'provider_host_conflict', 'conflicting_provider_id', v_other,
      'reason', 'Another active provider holds the source host; exact provider identity requires resolution.');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'identity_clear');
end $f$;
comment on function security.provider_description_identity_v1(uuid, text) is 'Provider descriptions: existing active/published, hidden and lifecycle controls; unresolved identity findings; the source host must be the provider''s own; a host with a recorded owner (pipeline.provider_host_owners, s766) is clear for the owner and in conflict for every other provider; a host with no owner is in conflict when another current provider holds it as its primary host.';

-- 2 trading names, and the reader's identity names
insert into catalogue.provider_aliases(provider_id, alias, alias_type)
select p.id, v.alias, 'trading_name'
  from (values ('provider:cricos:03389e', 'Torrens University'), ('provider:cricos:00682b', 'Moore Theological College')) v(k, alias)
  join catalogue.providers p on p.stable_key = v.k and p.lifecycle_status = 'active' and p.publication_status = 'published'
on conflict (provider_id, alias, coalesce(locale, '')) do nothing;

do $r$
declare v_def text; v_new text; v_old constant text := 'jsonb_build_array(p.canonical_name,p.display_name)';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'svc_provider_description_next';
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'guard: the identity names expression is not found exactly once'; end if;
  v_new := replace(v_def, v_old, v_old || ' || coalesce((select jsonb_agg(a.alias order by a.alias) from catalogue.provider_aliases a where a.provider_id = p.id and a.alias_type = ''trading_name'' and a.valid_to is null), ''[]''::jsonb)');
  execute v_new;
end $r$;

-- 3 one stored-page read for each of the two that has a page
create temp table cf_s766 on commit drop as
  select p.id as provider_id from catalogue.providers p
   where p.stable_key in ('provider:cricos:03389e', 'provider:cricos:00682b')
     and p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
     and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state in ('queued', 'reading', 'proposed'))
     and security.provider_description_stored_v1(p.id) is not null;
insert into pipeline.provider_description_reads(provider_id, state, next_try_at, reason, checks)
select c.provider_id, 'queued', now(), 'Read from the stored page with the trading name recorded (s766, Platform Admin 19 Nov 2026 16:18)',
       jsonb_build_object('drain', jsonb_build_object('rule', 's766-au-university-identity', 'basis', 'provider_name_conflict', 'at', now()))
  from cf_s766 c;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'layer4', 'rule_execute', 's766-au-university-identity',
       jsonb_build_object('host_owners', (select count(*) from pipeline.provider_host_owners), 'trading_names', 2, 'queued', (select count(*) from cf_s766), 'route', 'gpt-4.1-mini', 'firecrawl', 0),
       'c0ffee00-0000-4000-8000-000000000150'::uuid;

do $c$
declare v_n int := (select count(*) from cf_s766);
begin
  if (select count(*) from pipeline.provider_host_owners) < 3 then raise exception 'post-check: fewer than 3 host owners recorded'; end if;
  if (select string_agg(o.host, ',' order by o.host) from pipeline.provider_host_owners o) is distinct from 'rmit.edu.au,vu.edu.au,westernsydney.edu.au' then raise exception 'post-check: the recorded hosts are not the three expected'; end if;
  -- the owners are clear on their own host; the units are still in conflict; Victoria's second registration stays in conflict
  if (security.provider_description_identity_v1((select id from catalogue.providers where stable_key = 'provider:cricos:00122a'), 'https://www.rmit.edu.au/about')->>'rule') is distinct from 'identity_clear' then raise exception 'post-check: RMIT University is not clear on its host'; end if;
  if (security.provider_description_identity_v1((select id from catalogue.providers where stable_key = 'provider:cricos:00917k'), 'https://www.westernsydney.edu.au/about')->>'rule') is distinct from 'identity_clear' then raise exception 'post-check: Western Sydney University is not clear on its host'; end if;
  if (security.provider_description_identity_v1((select id from catalogue.providers where stable_key = 'provider:cricos:00124k'), 'https://www.vu.edu.au/about-vu')->>'rule') is distinct from 'identity_clear' then raise exception 'post-check: Victoria University is not clear on its host'; end if;
  if (security.provider_description_identity_v1((select id from catalogue.providers where stable_key = 'provider:cricos:01912g'), 'https://www.rmit.edu.au/up/about')->>'rule') is distinct from 'provider_host_conflict' then raise exception 'post-check: RMIT UP is not in conflict on the RMIT host'; end if;
  if (security.provider_description_identity_v1((select id from catalogue.providers where stable_key = 'provider:cricos:02475d'), 'https://www.vu.edu.au/about-vu')->>'rule') is distinct from 'provider_host_conflict' then raise exception 'post-check: the second Victoria University record is not in conflict'; end if;
  if (select count(*) from catalogue.provider_aliases where alias_type = 'trading_name' and alias in ('Torrens University', 'Moore Theological College')) <> 2 then raise exception 'post-check: the two trading names are not recorded'; end if;
  if pg_get_functiondef('public.svc_provider_description_next'::regproc) not like '%a.alias_type = ''trading_name''%' then raise exception 'post-check: the reader does not carry trading names'; end if;
  if v_n > 2 then raise exception 'post-check: % reads queued, more than the 2 providers', v_n; end if;
  if exists (select 1 from pipeline.provider_description_reads r where r.state in ('queued', 'reading', 'proposed') group by r.provider_id having count(*) > 1) then raise exception 'post-check: a provider has two open reads'; end if;
  if exists (select 1 from cf_s766 c join catalogue.providers p on p.id = c.provider_id where nullif(btrim(p.description), '') is not null) then raise exception 'post-check: a provider with a description was queued'; end if;
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'post-check: Firecrawl is on for provider descriptions'; end if;
  raise notice 's766-au-university-identity: % reads queued', v_n;
end $c$;
