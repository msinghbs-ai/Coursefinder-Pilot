-- CF-247 (11 Oct 2026, Platform Admin bugs 11/10-2): provider websites, central pages and two new tasks.
--  Fix 3: a website found and verified by search (register code, or the provider's name on its home page) now goes on the provider
--         record (41 were held only in the discovery table, e.g. Britts College). Never over a website entered by hand.
--  Feature 2/3: every active provider without a website is searched for one, for every provider (not only Firecrawl targets; 189
--         had been skipped as "budget") and every country (the worker searches by name where there is no register code). New
--         providers are queued as they are added. A website arriving starts its course page search, contact read and central
--         page search.
--  Feature 4: central pages (key dates, international fees, English requirements) suggested from a Firecrawl map of the site
--         (pipeline.provider_central_search, scheduled job central-find). Suggestions only: a person attaches one.
--  Feature 1/2 tasks (standing rule G1): "Fill in a provider from its website" and "Find course pages with Firecrawl" are task
--         types shown in Task manager; the Adapter builder lists every course with its page state.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"public.svc_coverage_site_next(integer)": "3858a8abeb37fc807c1a3c44880aa659", "public.svc_coverage_site_record(uuid,text,jsonb)": "db8dd06546847801b76434e02a483cc4", "security.course_link_search_tick_v1(integer)": "9d53e2995f2fb1c80fd2296b8f86c608", "public.admin_adapter_builder_basics(text,jsonb)": "a631288734bd8b37700b379b53c5a52f", "security.admin_job_slice_v1(uuid,integer)": "577823ad1c4c8d9fbccc64ea9fee295f", "security.admin_job_watch_v1(uuid)": "10dd1edb4da67f91480afa4d0adaccde", "public.admin_jobs(text,jsonb)": "b259a26fadfa83605bb9494900a062d9"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1. Queue columns: a task's items go first in line
alter table pipeline.coverage_provider_discovery add column if not exists requested_at timestamptz;
alter table pipeline.course_link_search add column if not exists requested_at timestamptz;

-- 2. Central pages found by Firecrawl (Feature 4): one row per provider, its latest search and the pages suggested
create table if not exists pipeline.provider_central_search (
  provider_id uuid primary key references catalogue.providers(id),
  state text not null default 'queued' check (state in ('queued', 'leased', 'done', 'failed')),
  requested_at timestamptz,
  leased_until timestamptz,
  searched_at timestamptz,
  attempts int not null default 0,
  found jsonb,
  evidence jsonb,
  updated_at timestamptz not null default now()
);
alter table pipeline.provider_central_search enable row level security;
revoke all on pipeline.provider_central_search from public, anon, authenticated;
comment on table pipeline.provider_central_search is 'CF-247 Feature 4 (11 Oct 2026): central pages (key dates, international fees, English requirements) suggested from a Firecrawl map of the provider''s own site. Suggestions only: a person attaches one.';

-- 3. A provider's website, found and verified by search, goes on its record (Platform Admin, 11 Oct 2026: "yes when verified").
--    Never over a website entered by hand (manual lock) or an existing one, never a directory or register. Then the follow-on
--    work starts: course pages searched on that site, contacts read (their picker needs the website) and central pages found.
create or replace function security.provider_website_adopt_v1(p_provider_id uuid, p_url text)
returns boolean language plpgsql security definer set search_path to '' as $f$
declare v_url text := btrim(coalesce(p_url, '')); v_dom text;
begin
  if v_url !~* '^https?://[^\s/]+\.[^\s]+$' or security.third_party_host_v1(v_url) then return false; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p_provider_id and l.field = 'website') then return false; end if;
  update catalogue.providers set website = v_url, updated_at = now() where id = p_provider_id and nullif(btrim(website), '') is null;
  if not found then return false; end if;
  v_dom := lower(regexp_replace(substring(v_url from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
  if v_dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$' then
    insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
    select p_provider_id, v_dom,
           jsonb_build_array(jsonb_build_object(
             're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                   || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
             'rep', '\&')),
           true, 'Generic recipe: any page on the provider''s own site, from a website found and verified by search; used only when the reader proves the page is the course''s (CF-247, 11 Oct 2026)', now()
     where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
    insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
    select c.id, c.provider_id, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now()
      from catalogue.courses c
     where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
       and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
       and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
    on conflict (course_id) do nothing;
  end if;
  insert into pipeline.provider_central_search(provider_id, state, requested_at) values (p_provider_id, 'queued', now())
  on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, updated_at = now() where pipeline.provider_central_search.state <> 'leased';
  return true;
end $f$;
revoke all on function security.provider_website_adopt_v1(uuid, text) from public, anon, authenticated;

-- 4. Central page search: worker picker and recorder
create or replace function public.svc_central_find_next(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id from pipeline.provider_central_search s join catalogue.providers p on p.id = s.provider_id
     where (s.state = 'queued' or (s.state = 'leased' and s.leased_until < now())) and s.attempts < 3
       and p.lifecycle_status = 'active' and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)
     order by (s.requested_at is null), s.requested_at, (select count(*) from catalogue.courses c where c.provider_id = s.provider_id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 4), 10)) for update of s skip locked),
  upd as (update pipeline.provider_central_search s set state = 'leased', leased_until = now() + interval '10 minutes', attempts = s.attempts + 1, updated_at = now()
            from pick where s.provider_id = pick.provider_id returning s.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', u.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website)), '[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id = u.provider_id;
  return v;
end $f$;
revoke all on function public.svc_central_find_next(integer) from public, anon, authenticated;
grant execute on function public.svc_central_find_next(integer) to service_role;

create or replace function public.svc_central_find_record(p_provider_id uuid, p_found jsonb, p_evidence jsonb)
returns void language plpgsql security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_found is null then  -- no credit to spend: back in the queue, unchanged
    update pipeline.provider_central_search set state = 'queued', leased_until = null, attempts = greatest(attempts - 1, 0), evidence = p_evidence, updated_at = now() where provider_id = p_provider_id;
    return;
  end if;
  update pipeline.provider_central_search
     set state = case when p_evidence ? 'error' then (case when attempts >= 3 then 'failed' else 'queued' end) else 'done' end,
         found = case when p_evidence ? 'error' then found else p_found end, evidence = p_evidence, leased_until = null,
         searched_at = case when p_evidence ? 'error' then searched_at else now() end,
         requested_at = case when p_evidence ? 'error' then requested_at end, updated_at = now()
   where provider_id = p_provider_id;
end $f$;
revoke all on function public.svc_central_find_record(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.svc_central_find_record(uuid, jsonb, jsonb) to service_role;

-- 5. New and edited providers: a provider with no website is searched for one; a website arriving starts the central page search
create or replace function security.provider_site_followups_tg()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if nullif(btrim(NEW.website), '') is null then
    if TG_OP = 'INSERT' then
      insert into pipeline.coverage_provider_discovery(provider_id, status, requested_at, updated_at) values (NEW.id, 'no_website', now(), now())
      on conflict (provider_id) do nothing;
    end if;
  elsif TG_OP = 'INSERT' or nullif(btrim(OLD.website), '') is distinct from nullif(btrim(NEW.website), '') then
    insert into pipeline.provider_central_search(provider_id, state, requested_at) values (NEW.id, 'queued', now())
    on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, updated_at = now() where pipeline.provider_central_search.state <> 'leased';
  end if;
  return null;
end $f$;
revoke all on function security.provider_site_followups_tg() from public, anon, authenticated;
create or replace trigger provider_site_followups after insert or update of website on catalogue.providers for each row execute function security.provider_site_followups_tg();

-- 6. Task types (standing rule G1: every background feature is a task type or a scheduled job, shown in Task manager)
insert into pipeline.admin_job_kinds(kind, label, what, can_pause, added_in) values
  ('provider_fill', 'Fill in a provider from its website', 'Finds the provider''s own website by search (verified by its register code or its name on the home page) when none is recorded, then reads its public contacts and finds its central pages (key dates, international fees, English requirements) with Firecrawl.', false, 'v2.15.245'),
  ('course_page_find', 'Find course pages with Firecrawl', 'Searches the provider''s own site for the official page of each chosen course (by CRICOS code, or by title), first in line.', false, 'v2.15.245')
on conflict (kind) do nothing;

create or replace function security.provider_task_fire_v1(p_mode text)
returns int language plpgsql security definer set search_path to '' as $f$
declare v_body jsonb;
begin
  v_body := case p_mode when 'find_site' then '{"mode":"find_site","limit":5}'::jsonb when 'contact_page' then '{"mode":"contact_page","limit":8}'::jsonb
                         when 'central_find' then '{"mode":"central_find","limit":4}'::jsonb end;
  if v_body is null then return 0; end if;
  if exists (select 1 from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = p_mode and l.created_at > now() - interval '45 seconds'
              and not exists (select 1 from net._http_response r where r.id = l.request_id)) then return 0; end if;
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', v_body);
  return 1;
end $f$;
revoke all on function security.provider_task_fire_v1(text) from public, anon, authenticated;

create or replace function security.provider_task_prepare_v1(p_kind text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_name text; v_site text; v_ids uuid[]; v_n int := 0;
begin
  select coalesce(p.display_name, p.canonical_name), nullif(btrim(p.website), '') into v_name, v_site from catalogue.providers p where p.id = v_pid and p.lifecycle_status = 'active';
  if v_name is null then raise exception 'choose an active provider'; end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = v_pid) then raise exception 'this provider is unpublished or archived; publish or restore it first'; end if;
  if p_kind = 'provider_fill' then
    if v_site is null then
      insert into pipeline.coverage_provider_discovery(provider_id, status, requested_at, updated_at) values (v_pid, 'no_website', now(), now())
      on conflict (provider_id) do update set status = case when pipeline.coverage_provider_discovery.website is null then 'no_website' else pipeline.coverage_provider_discovery.status end,
             site_searched_at = null, leased_until = null, requested_at = now(), updated_at = now();
      -- a website already found and verified earlier is adopted straight away
      perform security.provider_website_adopt_v1(v_pid, d.website) from pipeline.coverage_provider_discovery d where d.provider_id = v_pid and d.site_source like 'search_verified_%' and d.website is not null;
      select nullif(btrim(p.website), '') into v_site from catalogue.providers p where p.id = v_pid;
    end if;
    if v_site is not null then
      insert into pipeline.provider_central_search(provider_id, state, requested_at) values (v_pid, 'queued', now())
      on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, attempts = 0, updated_at = now();
    end if;
    update pipeline.provider_contact_checks set checked_at = now() - interval '91 days', outcome = 'requested' where provider_id = v_pid and kind = 'public_general';
    return jsonb_build_object('provider_id', v_pid, 'had_website', v_site is not null, 'title', 'Fill in from website: ' || v_name, 'scope', v_pid::text);
  elsif p_kind = 'course_page_find' then
    if not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = v_pid and x.active) then
      raise exception 'no website is recorded for this provider yet, so there is nowhere to search; use Fill in from website first';
    end if;
    v_ids := array(select c.id from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active'
                     and (case when jsonb_typeof(p_args->'course_ids') = 'array' and jsonb_array_length(p_args->'course_ids') > 0
                               then c.id = any (array(select x::uuid from jsonb_array_elements_text(p_args->'course_ids') x))
                               else not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.read_status = 'read') end));
    if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'every course of this provider already has a read page'; end if;
    if cardinality(v_ids) > 300 then raise exception 'at most 300 courses in one task'; end if;
    insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at, requested_at)
    select c.id, c.provider_id, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now(), now()
      from catalogue.courses c where c.id = any (v_ids)
    on conflict (course_id) do update set state = 'queued', stage = excluded.stage, attempts = 0, cand_idx = 0, queued_at = now(), requested_at = now(), sent_at = null
     where pipeline.course_link_search.state not in ('sent');
    get diagnostics v_n = row_count;
    return jsonb_build_object('provider_id', v_pid, 'course_ids', to_jsonb(v_ids), 'queued', v_n,
                              'title', 'Find course pages: ' || v_name || ' (' || cardinality(v_ids) || ' course' || case when cardinality(v_ids) = 1 then '' else 's' end || ')',
                              'scope', v_pid::text || ':' || md5(array_to_string(array(select x::text from unnest(v_ids) x order by 1), ',')));
  end if;
  raise exception 'unknown provider task';
end $f$;
revoke all on function security.provider_task_prepare_v1(text, jsonb) from public, anon, authenticated;

-- 7. Scheduled job for the central page search, with its Task manager label (standing rule G1)
select cron.schedule('central-find', '2-59/5 * * * *', $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"central_find","limit":4}'::jsonb)$$)
 where not exists (select 1 from cron.job where jobname = 'central-find');
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank) values
  ('central-find', 'Layer 2 reading', 135, 'Find central pages', 'Maps each provider''s own site with Firecrawl and suggests its key dates, international fee and English requirements pages, for a person to attach.', 5)
on conflict (jobname) do nothing;

CREATE OR REPLACE FUNCTION public.svc_coverage_site_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.coverage_provider_discovery d
     where d.status='no_website' and coalesce(d.site_searched_at,'-infinity')<now()-interval '30 days' and coalesce(d.leased_until,'-infinity')<now()
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (d.requested_at is null), d.requested_at, (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes' from pick where d.provider_id=pick.provider_id returning d.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'name',coalesce(p.display_name,p.canonical_name),'trading',p.short_name,
           'cricos',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='cricos'),'country',security.coverage_country(u.provider_id),
           'dli',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='ircc_dli'))),'[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id=u.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_site_record(p_provider_id uuid, p_website text, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_dom text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.245: no credit to spend: searched again in a day; nothing else is recorded
  if coalesce(p_evidence->>'note', '') ilike '%budget%' then
    update pipeline.coverage_provider_discovery set leased_until=null, site_searched_at=now()-interval '29 days', site_evidence=p_evidence, updated_at=now() where provider_id=p_provider_id;
    return;
  end if;
  -- v2.15.232 (Fix 3): a course finder address entered by hand is kept; the search result is stored as evidence only
  if exists (select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p_provider_id and l.field='course_finder')
     or exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id=p_provider_id and d.site_source='manual') then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence, updated_at=now() where provider_id=p_provider_id;
    return;
  end if;
  -- v2.15.233 (Feature 1): a course directory or other third-party site is never recorded as the provider's site
  if nullif(p_website,'') is not null and security.third_party_host_v1(p_website) then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, updated_at=now(),
           site_evidence=coalesce(p_evidence,'{}'::jsonb)||jsonb_build_object('refused', p_website, 'refused_why', 'third-party site, not the provider''s own')
     where provider_id=p_provider_id;
    return;
  end if;
  update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence,
         website=coalesce(nullif(p_website,''),website), site_source=case when nullif(p_website,'') is not null then coalesce('search_verified_'||nullif(p_evidence->>'basis',''),'search_verified_cricos_code') else site_source end,
         status=case when nullif(p_website,'') is not null then 'pending' else status end, attempts=case when nullif(p_website,'') is not null then 0 else attempts end,
         requested_at=null, updated_at=now()
   where provider_id=p_provider_id;
  -- v2.15.245 (Platform Admin, 11 Oct 2026): a website found and verified goes on the provider's record, with its follow-on work
  if nullif(p_website,'') is not null then perform security.provider_website_adopt_v1(p_provider_id, p_website); end if;
  -- Decision 220: a Canadian site gets the generic recipe for its own .ca domain, and its active courses with no
  -- candidate page are queued for the course-page search by title.
  if nullif(p_website,'') is not null and security.coverage_country(p_provider_id) = 'CA' then
    v_dom := lower(regexp_replace(substring(btrim(p_website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
    if v_dom ~ '^[a-z0-9.-]+\.ca$' then
      insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
      select p_provider_id, v_dom,
             jsonb_build_array(jsonb_build_object(
               're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                     || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
               'rep', '\&')),
             true, 'Generic recipe: any page on the provider''s own site; used only when the reader proves the page is the course''s (CA, Decision 220, 2 Oct 2026)', now()
       where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      select c.id, c.provider_id, 'title', 'queued', now()
        from catalogue.courses c
       where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
         and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
      on conflict (course_id) do nothing;
    end if;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION security.course_link_search_tick_v1(p_batch integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_urls text[]; v_c text[]; v_cap numeric; v_on boolean; v_used numeric; v_key text; v_dom text;
        n_harvest int := 0; n_found int := 0; n_moved int := 0; n_sent int := 0; v_next text;
begin
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;

  -- 1. Collect finished searches.
  for r in select s.*, h.status_code, h.content from pipeline.course_link_search s join net._http_response h on h.id = s.req_id
            where s.state = 'sent' loop
    n_harvest := n_harvest + 1;
    if r.status_code = 200 and left(r.content, 1) = '{' then
      perform public.svc_coverage_usage(2, 'course_link_search', r.provider_id, r.query);
      v_urls := array(select e->>'url' from jsonb_array_elements(coalesce((r.content::jsonb)->'data', '[]'::jsonb)) e);
      v_c := security.course_link_pick_v1(r.provider_id, v_urls);
      if cardinality(v_c) > 0 then
        update pipeline.course_link_search set state = 'found', results = to_jsonb(v_urls), candidates = to_jsonb(v_c), cand_idx = 1,
               bound_url = v_c[1], done_at = now() where course_id = r.course_id;
        perform security.course_link_bind_v1(r.course_id, r.provider_id, v_c[1], case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
        n_found := n_found + 1;
      elsif r.stage = 'cricos' then
        update pipeline.course_link_search set stage = 'title', state = 'queued', results = to_jsonb(v_urls), attempts = 0 where course_id = r.course_id;
      else
        update pipeline.course_link_search set state = 'none', results = to_jsonb(v_urls), done_at = now() where course_id = r.course_id;
      end if;
    else
      update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= 3 then 'error' else 'queued' end,
             results = jsonb_build_object('http_status', r.status_code, 'body', left(r.content, 300)) where course_id = r.course_id;
    end if;
  end loop;
  -- searches with no response after 20 minutes are sent again
  update pipeline.course_link_search set state = 'queued', attempts = attempts + 1
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);

  -- 2. Pages the reader could not confirm move to the next candidate, then to the title search.
  for r in select s.*, p.status pstatus, p.read_status, p.read_attempts from pipeline.course_link_search s
             join pipeline.coverage_course_pages p on p.course_id = s.course_id and p.url = s.bound_url
            where s.state = 'found' and (p.status = 'mismatch' or (p.read_status in ('fetch_failed','blocked','robots_disallowed') and (p.read_attempts >= 2 or p.http_status in (404, 410)))) loop
    if r.cand_idx < jsonb_array_length(r.candidates) then
      v_next := r.candidates->>r.cand_idx;
      update pipeline.course_link_search set cand_idx = cand_idx + 1, bound_url = v_next where course_id = r.course_id;
      perform security.course_link_bind_v1(r.course_id, r.provider_id, v_next, case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
    elsif r.stage = 'cricos' then
      update pipeline.course_link_search set stage = 'title', state = 'queued', attempts = 0, done_at = null where course_id = r.course_id;
    else
      update pipeline.course_link_search set state = 'none', done_at = now() where course_id = r.course_id;
    end if;
    n_moved := n_moved + 1;
  end loop;
  update pipeline.course_link_search s set state = 'verified' from pipeline.coverage_course_pages p
   where s.state = 'found' and p.course_id = s.course_id and p.url = s.bound_url and p.status = 'bound' and p.identity_basis is not null;

  -- 2b. Decision 217: courses without a CRICOS code whose earlier page was read again and is not theirs are searched by title.
  insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
  select p.course_id, p.provider_id, 'title', 'queued', now()
    from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
   where p.status = 'mismatch' and p.basis not in ('cricos_search', 'title_search')
     and coalesce(c.course_code, '') !~ '^[0-9]{6}[0-9A-Z]$'
     and exists (select 1 from pipeline.course_link_recipes rc where rc.provider_id = p.provider_id and rc.active)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     and not exists (select 1 from pipeline.course_link_search s where s.course_id = p.course_id)
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p.course_id and k.field = 'official_url')
   limit 200
  on conflict (course_id) do nothing;

  -- 2c. Decision 252: pages from the Serper search pass, after the reader.
  perform security.search_pass_advance_v1();

  -- 3. Send the next batch, inside the monthly credit cap.
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if v_on and coalesce((select x.send_via from pipeline.course_link_search_settings x where x.id = 1), 'pg_net') = 'pg_net' and v_used + 2 * p_batch <= v_cap then
    v_key := public.svc_coverage_firecrawl()->>'secret';
    if v_key is not null then
      for r in select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
                 from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
                 join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
                 left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
                where s.state = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
                order by (s.requested_at is null), (s.stage <> 'cricos'), row_number() over (partition by s.provider_id order by md5(s.course_id::text)), coalesce(pp.rank, 100000)
                limit greatest(1, least(coalesce(p_batch, 40), 100)) loop
        v_dom := case r.stage when 'cricos' then '"' || r.course_code || '" site:' || r.search_domain
                                         else '"' || replace(regexp_replace(r.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || r.search_domain end;
        update pipeline.course_link_search set state = 'sent', sent_at = now(), query = v_dom,
               req_id = net.http_post(url := 'https://api.firecrawl.dev/v1/search',
                          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
                          body := jsonb_build_object('query', v_dom, 'limit', 5), timeout_milliseconds := 60000)
         where course_id = r.course_id;
        n_sent := n_sent + 1;
      end loop;
    end if;
  end if;
  return jsonb_build_object('collected', n_harvest, 'found', n_found, 'moved_on', n_moved, 'sent', n_sent, 'credits_this_month', v_used, 'cap', v_cap);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_adapter_builder_basics(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid; v_q text; v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'search' then
    v_q := btrim(coalesce(p_args->>'q', ''));
    if length(v_q) < 2 then return jsonb_build_object('providers', '[]'::jsonb); end if;
    select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) into v from (
      select jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
               'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id),
               'courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'),
               'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = p.id)) x
        from catalogue.providers p
       where p.lifecycle_status = 'active' and (coalesce(p.display_name, p.canonical_name) ilike '%' || v_q || '%' or p.website ilike '%' || v_q || '%')
       order by (exists (select 1 from pipeline.uni_adapters u where u.provider_id = p.id)) desc, coalesce(p.display_name, p.canonical_name) limit 20) s;
    return jsonb_build_object('providers', v);
  end if;
  if p_action <> 'basics' then raise exception 'unknown action'; end if;
  v_pid := nullif(p_args->>'provider_id', '')::uuid;
  if not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'unknown provider'; end if;
  select jsonb_build_object(
    'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
    'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id),
    'courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'),
    'pages', (select jsonb_build_object('stored', count(*), 'read', count(*) filter (where pg.read_status = 'read'),
                                        'needs_render', count(*) filter (where pg.read_status in ('needs_render', 'blocked')))
                from pipeline.coverage_course_pages pg where pg.provider_id = p.id),
    'adapter', (select jsonb_build_object('enabled', u.enabled, 'admit', u.admit, 'admit_fields', u.admit_fields, 'notes', left(coalesce(u.notes, ''), 600),
                                          'updated_at', u.updated_at, 'patterns', (select count(*) from jsonb_object_keys(coalesce(u.patterns, '{}'::jsonb))),
                                          'json_paths', (select count(*) from jsonb_object_keys(coalesce(u.json_paths, '{}'::jsonb))))
                  from pipeline.uni_adapters u where u.provider_id = p.id),
    'qualify', case when exists (select 1 from pipeline.uni_adapters u where u.provider_id = p.id) then security.adapter_qualify_one_v1(p.id, 0.5, 0.9) end,
    'central', (select coalesce(jsonb_agg(jsonb_build_object('kind', f.kind, 'url', f.url, 'status', f.status, 'found_via', f.found_via,
                         'decision', f.decision) order by f.kind, f.rank, f.updated_at desc), '[]'::jsonb)
                  from pipeline.provider_fact_sources f where f.provider_id = p.id and f.status not in ('failed', 'no_values')),
    'suggested', (select coalesce(jsonb_agg(jsonb_build_object('kind', s.kind, 'url', s.url, 'title', s.title, 'source', s.source) order by s.kind, s.source, s.rn), '[]'::jsonb) from (select distinct on (q.kind, q.url) q.* from (
                    -- v2.15.245 (Feature 4): pages found by the Firecrawl map of the site, then those among its stored links
                    select m.kind, m.url, m.title, 'map'::text source, m.rn from (select e->>'kind' kind, e->>'url' url, e->>'title' title, row_number() over (partition by e->>'kind' order by (e->>'score')::numeric desc) rn
                      from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e where cs.provider_id = p.id) m
                     where m.rn <= 3 and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = p.id and f.kind = m.kind and f.url = m.url)
                    union all
                    select * from (select k.kind, u.url, u.title, 'links'::text source, row_number() over (partition by k.kind order by length(u.url)) rn
                      from pipeline.coverage_provider_urls u
                      cross join lateral (select case
                               when u.url ~* '(key-?dates|academic-?calendar|semester-?dates|term-?dates|important-?dates|principal-?dates)' then 'intake_calendar'
                               when u.url ~* '(international.*(fee|tuition)|(fee|tuition).*international|fee-?schedule|tuition-?fees)' then 'fee_schedule'
                               when u.url ~* '(english-?language-?requirement|english-?requirement|english-?proficiency)' then 'english_policy' end kind) k
                     where u.provider_id = p.id and k.kind is not null
                       and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = p.id and f.kind = k.kind and f.url = u.url)) l where l.rn <= 3) q order by q.kind, q.url, (q.source <> 'map')) s),
    -- v2.15.245 (Fix 3, Features 1-4): where the website came from, the central page search, contacts and every course's page
    'website_found', (select jsonb_build_object('website', d.website, 'source', d.site_source, 'status', d.status, 'searched_at', d.site_searched_at, 'requested', d.requested_at is not null,
                        'basis', d.site_evidence->>'basis', 'note', d.site_evidence->>'note', 'refused', d.site_evidence->>'refused') from pipeline.coverage_provider_discovery d where d.provider_id = p.id),
    'central_search', (select jsonb_build_object('state', s.state, 'searched_at', s.searched_at, 'requested', s.requested_at is not null, 'found', coalesce(jsonb_array_length(s.found), 0),
                        'error', s.evidence->>'error', 'addresses', (s.evidence->>'addresses')::int) from pipeline.provider_central_search s where s.provider_id = p.id),
    'contacts', jsonb_build_object('phone', p.phone, 'email', p.email,
                        'checked_at', (select k.checked_at from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'public_general'),
                        'outcome', (select k.outcome from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'public_general')),
    'course_list', (select coalesce(jsonb_agg(z.x order by z.rk, z.x->>'title'), '[]'::jsonb) from (
                      select jsonb_build_object('course_id', c.id, 'title', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'url', g.url, 'read_status', g.read_status,
                               'state', st.state, 'search', ls.state, 'searched_at', ls.sent_at) x,
                             case st.state when 'no_page' then 1 when 'not_found' then 2 when 'searching' then 3 when 'stored' then 4 else 5 end rk
                        from catalogue.courses c
                        left join pipeline.coverage_course_pages g on g.course_id = c.id
                        left join pipeline.course_link_search ls on ls.course_id = c.id
                        cross join lateral (select case when g.read_status = 'read' then 'read' when g.url is not null then 'stored'
                                                        when ls.state in ('queued', 'sent') then 'searching' when ls.state = 'none' then 'not_found' else 'no_page' end state) st
                       where c.provider_id = p.id and c.lifecycle_status = 'active' limit 500) z),
    'can_manage', v_rank >= 6)
    into v from catalogue.providers p where p.id = v_pid;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_job_slice_v1(p_id uuid, p_items integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_next int; v_total int; v_ids uuid[]; v_pid uuid; v_r jsonb; v_min_read numeric; v_min_agree numeric;
        v_done int := 0; v_errs int; v_pass int; v_fields text[]; v_have text[]; v_want text[]; v_claims text; v_res jsonb; v_added text[];
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  if v_j.kind in ('reread_pages', 'firecrawl_run', 'adapter_apply', 'central_page_read', 'scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread', 'provider_fill', 'course_page_find') then return security.admin_job_watch_v1(p_id); end if;
  v_ids := array(select (x)::uuid from jsonb_array_elements_text(v_j.args->'providers') x);
  v_total := coalesce(array_length(v_ids, 1), 0);
  v_next := coalesce((v_j.cursor->>'next')::int, 1);
  v_errs := coalesce((v_j.result->>'errors')::int, 0);
  v_pass := coalesce((v_j.result->>'passing')::int, 0);
  v_min_read := coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5);
  v_min_agree := coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9);
  while v_next <= v_total and v_done < p_items loop
    v_pid := v_ids[v_next];
    begin
      if v_j.kind = 'qualify_adapters' then
        v_r := security.adapter_qualify_one_v1(v_pid, v_min_read, v_min_agree);
        insert into pipeline.adapter_qualifications(job_id, provider_id, pages_read, fields, passing)
          values (p_id, v_pid, (v_r->>'pages_read')::int, v_r->'fields', array(select x from jsonb_array_elements_text(v_r->'passing') x))
          on conflict (job_id, provider_id) do update set measured_at = now(), pages_read = excluded.pages_read, fields = excluded.fields, passing = excluded.passing where pipeline.adapter_qualifications.job_id = excluded.job_id and pipeline.adapter_qualifications.provider_id = excluded.provider_id;
        if jsonb_array_length(v_r->'passing') > 0 then v_pass := v_pass + 1; end if;
      elsif v_j.kind = 'admit_qualified' then
        v_want := array(select x from jsonb_array_elements_text(v_j.args->'fields') x);
        select q.passing into v_fields from pipeline.adapter_qualifications q where q.job_id = coalesce((v_j.args->'qual_jobs'->>v_pid::text)::uuid, (v_j.args->>'qualification_job_id')::uuid) and q.provider_id = v_pid;
        select coalesce(u.admit_fields, '{}') into v_have from pipeline.uni_adapters u where u.provider_id = v_pid;
        v_added := array(select f from unnest(v_fields) f where f = any (v_want) and f <> all (v_have));
        if coalesce(array_length(v_added, 1), 0) > 0 then
          -- as the person who started the job, through the ordinary admission control (its checks and its log entry)
          v_claims := jsonb_build_object('sub', v_j.requested_by::text, 'role', 'authenticated')::text;
          perform set_config('request.jwt.claims', v_claims, true);
          v_res := public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', v_pid, 'admit', true,
                     'fields', to_jsonb(array(select distinct f from unnest(v_have || v_added) f order by f)),
                     'reason', left('Admitted by job ' || p_id::text || ' (' || v_j.title || '): ' || v_j.reason, 400)));
          perform set_config('request.jwt.claims', '', true);
          v_pass := v_pass + 1;
          insert into pipeline.admin_job_events(job_id, note, detail) values (p_id, 'admitted ' || array_to_string(v_added, ', ') || ' for ' || (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_pid), jsonb_build_object('provider_id', v_pid, 'fields', v_res->'fields'));
        end if;
      end if;
    exception when others then
      perform set_config('request.jwt.claims', '', true);
      v_errs := v_errs + 1;
      insert into pipeline.admin_job_events(job_id, note, detail) values (p_id, 'error for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_pid), v_pid::text) || ': ' || left(sqlerrm, 300), jsonb_build_object('provider_id', v_pid));
    end;
    v_next := v_next + 1; v_done := v_done + 1;
  end loop;
  update pipeline.admin_jobs set cursor = jsonb_build_object('next', v_next), progress = jsonb_build_object('done', v_next - 1, 'total', v_total), result = jsonb_build_object('passing', v_pass, 'errors', v_errs), updated_at = now() where id = p_id;
  return v_next > v_total;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_job_watch_v1(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_done int := 0; v_total int := 0; v_fin boolean := false; v_note text := null; v_phase text := null;
        v_n_map int := 0; v_n_cand int := 0; v_extra jsonb; v_sch uuid[]; v_before uuid[]; v_since timestamptz;
        v_last_done int; v_last_at timestamptz; v_stall interval; v_ids uuid[]; r record;
        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  v_last_done := coalesce((v_j.cursor->>'last_done')::int, -1);
  v_last_at := coalesce((v_j.cursor->>'last_change_at')::timestamptz, v_j.started_at, v_j.created_at);
  if v_j.kind = 'reread_pages' then
    v_stall := interval '30 minutes';
    select * into r from pipeline.university_reread_requests q where q.id = (v_j.args->>'request_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the re-read request is gone';
    elsif r.status = 'cancelled' then v_fin := true; v_note := 'cancelled before every university was sent (' || cardinality(r.done_ids) || ' of ' || cardinality(r.provider_ids) || ' sent)';
    elsif r.status = 'failed' then v_fin := true; v_note := 'the request failed: ' || coalesce(r.last_error, 'no detail');
    elsif r.status in ('waiting', 'sending') then
      v_phase := 'sending'; v_done := cardinality(r.done_ids); v_total := cardinality(r.provider_ids);
    else
      v_phase := 'reading'; v_total := coalesce(r.pages, 0);
      v_ids := r.provider_ids;
      select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = any (v_ids) and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
      if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) sent back and read again'; end if;
    end if;
  elsif v_j.kind = 'firecrawl_run' then
    select * into r from pipeline.firecrawl_runs x where x.id = (v_j.args->>'run_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the run is gone';
    else
      v_done := coalesce(r.done, 0); v_total := coalesce(r.items, 0);
      if r.status <> 'running' then v_fin := true; v_note := 'run ' || r.status || ': ' || v_done || ' of ' || v_total || ' done, ' || coalesce(r.credits_used, 0) || ' credits'; end if;
    end if;
  elsif v_j.kind = 'adapter_apply' then
    v_stall := interval '20 minutes';
    v_total := coalesce((v_j.args->>'pages')::int, 0);
    select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = (v_j.args->>'provider_id')::uuid and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
    if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) read again with the adapter'; end if;
  elsif v_j.kind = 'central_page_read' then
    v_stall := interval '30 minutes'; v_total := 1;
    select * into r from pipeline.provider_fact_sources s where s.id = (v_j.args->>'source_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the central page record is gone';
    elsif r.status in ('read', 'parsed', 'no_values', 'failed') and r.updated_at >= coalesce(v_j.started_at, v_j.created_at) - interval '1 minute' then
      v_done := 1; v_fin := true; v_note := 'page ' || r.status || coalesce(': ' || (r.parse_summary->>'error'), '');
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks. The pages in scope were queued first in line when the task
  -- started; each minute this checks progress, sends the scraper worker the next step (map the site, screen candidate pages, read
  -- scholarship pages) when none is already on its way, and finishes when nothing in scope is left to do.
  elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
    v_stall := interval '30 minutes'; v_since := v_j.created_at;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x);
    v_sch := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x);
    select count(*) filter (where p.requested_at is null and p.read_at >= v_since), count(*) into v_done, v_total
      from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id
     where s.lifecycle_status = 'active'
       and (case when v_j.kind = 'scholarship_reread' then s.id = any (v_sch) else s.provider_id = any (v_ids) end)
       and (p.requested_at is not null or p.read_at >= v_since or s.created_at >= v_since);
    if v_j.kind = 'scholarship_provider_scan' then
      select count(*) into v_n_map from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and d.status = 'pending' and d.attempts < 3;
      select count(*) into v_n_cand from pipeline.scholarship_page_candidates c
       where c.provider_id = any (v_ids) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register' and c.next_read_at <= now() and c.attempts < 3;
    end if;
    v_phase := case when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
    v_extra := jsonb_build_object('phase_detail', v_phase, 'providers_mapping', v_n_map, 'candidates_waiting', v_n_cand,
      'new_scholarships', (select count(*) from scholarship.scholarships s where s.provider_id = any (v_ids) and s.created_at >= v_since),
      'links_changed', (select count(*) from pipeline.scholarship_sweep_changes c join scholarship.scholarships s on s.id = c.scholarship_id
                         where s.provider_id = any (v_ids) and c.field = 'course_links' and c.changed_at >= v_since),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = any (v_ids) and u.purpose like 'sch\_%' and u.at >= v_since));
    if v_j.kind = 'scholarship_course_check' then
      v_before := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'before', '[]'::jsonb)) x);
      v_extra := v_extra || jsonb_build_object('course_id', v_j.args->>'course_id',
        'linked_now', (select count(*) from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped'),
        'added', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id
                   where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped' and not (m.scholarship_id = any (v_before))),
        'removed', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.scholarships s
                     where s.id = any (v_before) and not exists (select 1 from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.scholarship_id = s.id and m.mapping_state = 'mapped')));
    end if;
    if v_n_map = 0 and v_n_cand = 0 and v_done >= v_total then
      v_fin := true;
      v_note := v_done || ' scholarship page(s) read through the scraper' || coalesce(', ' || nullif((v_extra->>'new_scholarships')::int, 0) || ' new scholarship(s) found', '')
             || ', course links changed on ' || (v_extra->>'links_changed') || ', ' || (v_extra->>'credits') || ' scholarship scraper credit(s) used for ' || case when cardinality(v_ids) = 1 then 'this provider' else 'these providers' end || ' while the task ran'
             || case when v_j.kind = 'scholarship_course_check' then '; this course now has ' || (v_extra->>'linked_now') || ' scholarship(s) (' || jsonb_array_length(v_extra->'added') || ' added, ' || jsonb_array_length(v_extra->'removed') || ' removed)' else '' end;
    else
      perform security.scholarship_task_fire_v1(case when v_n_map > 0 then array['discover'] when v_n_cand > 0 then array['candidates'] else array['read'] end);
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin bugs 11/10-2): Fill in a provider from its website (website, then contacts, then central
  -- pages; each step sent to the worker when none is on its way) and Find course pages with Firecrawl (the chosen courses first in
  -- the course page search, finished when each has been searched).
  elsif v_j.kind = 'provider_fill' then
    v_stall := interval '30 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid; v_total := 3;
    select nullif(btrim(p.website), ''), (p.phone is not null and p.email is not null) into v_site, v_cok from catalogue.providers p where p.id = v_pid;
    select * into r from pipeline.coverage_provider_discovery d where d.provider_id = v_pid;
    if v_site is null and r.provider_id is not null and r.status = 'no_website' and (r.site_searched_at is null or r.site_searched_at < v_since) then
      v_phase := 'finding the website'; v_done := 0;
      perform security.provider_task_fire_v1('find_site');
    elsif v_site is null then
      v_fin := true; v_done := 3;
      v_note := 'no website could be verified by search' || coalesce(' (' || (r.site_evidence->>'note') || ')', '') || '; enter it by hand in the Adapter builder, step 1.1';
    else
      v_done := 1;
      if not coalesce(v_cok, false) and exists (select 1 from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active')
         and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = v_pid and k.kind = 'public_general' and k.checked_at >= v_since and k.outcome not in ('leased', 'requested')) then
        v_phase := 'reading contacts';
        perform security.provider_task_fire_v1('contact_page');
      else
        v_done := 2;
        if exists (select 1 from pipeline.provider_central_search s where s.provider_id = v_pid and s.state in ('queued', 'leased')) then
          v_phase := 'finding central pages';
          perform security.provider_task_fire_v1('central_find');
        else
          v_done := 3; v_fin := true;
        end if;
      end if;
    end if;
    v_extra := jsonb_build_object('phase_detail', coalesce(v_phase, 'finishing'), 'website', v_site, 'website_basis', r.site_evidence->>'basis',
      'phone', (select p.phone from catalogue.providers p where p.id = v_pid), 'email', (select p.email from catalogue.providers p where p.id = v_pid),
      'central_found', (select coalesce(jsonb_array_length(s.found), 0) from pipeline.provider_central_search s where s.provider_id = v_pid),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.at >= v_since));
    if v_fin and v_note is null then
      v_note := 'website ' || coalesce(v_site, 'not found') || '; phone ' || coalesce(v_extra->>'phone', 'not found') || ', email ' || coalesce(v_extra->>'email', 'not found')
             || '; ' || coalesce(v_extra->>'central_found', '0') || ' central page suggestion(s) to attach in the Adapter builder, step 1.3; ' || (v_extra->>'credits') || ' Firecrawl credit(s)';
    end if;
  elsif v_j.kind = 'course_page_find' then
    v_stall := interval '45 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'course_ids', '[]'::jsonb)) x);
    v_total := coalesce(cardinality(v_ids), 0);
    select count(*) filter (where s.state not in ('queued', 'sent') and s.queued_at >= v_since),
           count(*) filter (where s.state in ('verified', 'found') and s.queued_at >= v_since),
           count(*) filter (where s.state = 'none' and s.queued_at >= v_since)
      into v_done, v_c, v_c2 from pipeline.course_link_search s where s.course_id = any (v_ids);
    v_phase := 'searching course pages';
    v_extra := jsonb_build_object('phase_detail', v_phase, 'found', v_c, 'not_found', v_c2,
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.purpose = 'course_link_search' and u.at >= v_since));
    if v_done >= v_total then
      v_fin := true;
      v_note := v_c || ' of ' || v_total || ' course page(s) found on the provider''s site; ' || v_c2 || ' not found (enter those by hand in the Adapter builder, step 2.1)';
    end if;
  end if;
  if v_done <> v_last_done then v_last_done := v_done; v_last_at := now(); end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then
    v_fin := true; v_note := coalesce(v_note, v_done || ' of ' || v_total || ' done, nothing more for ' || extract(epoch from v_stall)::int / 60 || ' minutes: the rest wait their turn in the reader');
  end if;
  update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', v_last_done, 'last_change_at', v_last_at), progress = jsonb_build_object('done', v_done, 'total', v_total) || coalesce(jsonb_build_object('phase', v_phase), '{}'::jsonb), result = jsonb_build_object('done', v_done, 'total', v_total, 'errors', case when v_note like 'the request failed%' then 1 else 0 end) || coalesce(jsonb_build_object('note', v_note), '{}'::jsonb) || coalesce(v_extra, '{}'::jsonb), updated_at = now() where id = p_id;
  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_jobs(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_id uuid; v_kind text; v_ids uuid[]; v_j pipeline.admin_jobs%rowtype;
        v_q pipeline.admin_jobs%rowtype; v_fields text[]; v_title text; v_n int; v_res jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'jobs', coalesce((select jsonb_agg(to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0), 'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by)) order by j.created_at desc)
                         from (select * from pipeline.admin_jobs where state in ('queued', 'running', 'paused') or (p_args->>'all')::boolean order by created_at desc limit greatest(1, least(coalesce((p_args->>'limit')::int, 50), 200))) j), '[]'::jsonb),
      'match', case when p_args ? 'kind' then (select to_jsonb(j) - 'args' || jsonb_build_object('providers', coalesce(jsonb_array_length(j.args->'providers'), 0)) from pipeline.admin_jobs j
                      where j.kind = p_args->>'kind' and j.scope is not distinct from nullif(p_args->>'scope', '') and j.state in ('queued', 'running', 'paused') order by j.created_at desc limit 1) end,
      'job', case when p_args ? 'id' then (select to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0),
                    'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by),
                    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc) from (select * from pipeline.admin_job_events e where e.job_id = j.id order by e.id desc limit 200) e), '[]'::jsonb),
                    'qualifications', coalesce((select jsonb_agg(jsonb_build_object('provider_id', q.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(p.id), 'pages_read', q.pages_read, 'fields', q.fields, 'passing', q.passing, 'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = q.provider_id), 'admitted', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.admit)) order by coalesce(p.display_name, p.canonical_name))
                                       from pipeline.adapter_qualifications q join catalogue.providers p on p.id = q.provider_id where (q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid or q.job_id::text = j.args->'qual_jobs'->>q.provider_id::text)), '[]'::jsonb))
                  from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid) end,
      'settings', jsonb_build_object('min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb), 'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)),
      'countries', coalesce((select jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'adapters', n.n) order by k.name) from ref.countries k join (select p.country_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.country_id) n on n.country_id = k.id), '[]'::jsonb),
      'states', coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'country', k.iso_alpha2, 'adapters', n.n) order by s.code) from ref.subdivisions s join ref.countries k on k.id = s.country_id join (select p.subdivision_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.subdivision_id) n on n.subdivision_id = s.id), '[]'::jsonb),
      'can_admit', v_rank >= 6,
      -- 11 Oct 2026: job kinds from the registry, and (Task manager) everything using resources right now
      'kinds', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object('label', k.label, 'can_pause', k.can_pause)), '{}'::jsonb) from pipeline.admin_job_kinds k),
      'running_now', case when coalesce((p_args->>'running')::boolean, false) then security.admin_running_now_v1() end);
  end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    v_kind := p_args->>'kind';
    if v_kind = 'qualify_adapters' then
      if v_rank < 5 then raise exception 'Operator (adapters) or above required' using errcode = '42501'; end if;
      v_ids := security.admin_jobs_resolve_adapters_v1(coalesce(p_args->'args', '{}'::jsonb));
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapters match that choice'; end if;
      v_title := 'Qualify ' || array_length(v_ids, 1) || ' adapter(s)' || coalesce(' in ' || nullif(btrim(coalesce(p_args->'args'->>'state', p_args->'args'->>'country', '')), ''), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), nullif(p_args->'args'->>'state', ''), nullif(p_args->'args'->>'country', '')))
        returning * into v_j;
    elsif v_kind = 'admit_qualified' and not (coalesce(p_args->'args', '{}'::jsonb) ? 'qualification_job_id') then
      -- 6 Oct (Layer 2 › Adapters): admit the ticked adapters, each from its own latest finished Qualify
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      select coalesce(jsonb_object_agg(z.provider_id, z.job_id), '{}'::jsonb), coalesce(array_agg(z.provider_id order by z.provider_id), '{}') into v_res, v_ids
        from (select distinct on (x.provider_id) x.provider_id, x.job_id, x.passing from pipeline.adapter_qualifications x join pipeline.admin_jobs qj on qj.id = x.job_id and qj.kind = 'qualify_adapters' and qj.state = 'done'
               where x.provider_id = any (array(select (y)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) y))
               order by x.provider_id, x.measured_at desc) z
       where z.passing && v_fields and exists (select 1 from pipeline.uni_adapters u where u.provider_id = z.provider_id and u.enabled);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no ticked adapter passed for those fields in its latest Qualify (or it is switched off)'; end if;
      v_title := 'Admit the passing fields of ' || case when array_length(v_ids, 1) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 adapter') else array_length(v_ids, 1) || ' adapters' end || ' (latest Qualify of each)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qual_jobs', v_res, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), case when array_length(v_ids, 1) = 1 then v_ids[1]::text else 'adapters' end))
        returning * into v_j;
      v_res := null;
    elsif v_kind = 'admit_qualified' then
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      select * into v_q from pipeline.admin_jobs q where q.id = (p_args->'args'->>'qualification_job_id')::uuid;
      if v_q.id is null or v_q.kind <> 'qualify_adapters' or v_q.state <> 'done' then raise exception 'choose a finished Qualify job'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      v_ids := array(select q.provider_id from pipeline.adapter_qualifications q where q.job_id = v_q.id and q.passing && v_fields
                      and exists (select 1 from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.enabled)
                      order by q.provider_id);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapter passed for those fields'; end if;
      v_title := 'Admit the passing fields of ' || array_length(v_ids, 1) || ' adapter(s) (from ' || v_q.title || ')';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qualification_job_id', v_q.id, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason, v_q.id::text)
        returning * into v_j;
    elsif v_kind = 'reread_pages' then
      v_res := public.admin_university_reread('queue', coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('reason', v_reason));
      v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) x);
      v_title := 'Read pages again: ' || case when cardinality(v_ids) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 university') else cardinality(v_ids) || ' universities' end
                 || case when coalesce(p_args->'args'->>'which', 'all') = 'not_confirmed' then ' (pages not confirmed)' else '' end || case when coalesce((p_args->'args'->>'central')::boolean, false) then ' with central pages' else '' end;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('request_id', v_res->>'request_id', 'provider_ids', to_jsonb(v_ids), 'which', coalesce(p_args->'args'->>'which', 'all'), 'central', coalesce((p_args->'args'->>'central')::boolean, false)),
                jsonb_build_object('done', 0, 'total', cardinality(v_ids), 'phase', 'sending'), auth.uid(), v_reason, case when cardinality(v_ids) = 1 then v_ids[1]::text else coalesce(nullif(p_args->'args'->>'scope', ''), 'universities') end)
        returning * into v_j;
    elsif v_kind = 'firecrawl_run' then
      v_res := public.admin_firecrawl_write('start', jsonb_build_object('use_case', p_args->'args'->>'use_case', 'reason', v_reason));
      v_title := 'Firecrawl run: ' || replace(coalesce(p_args->'args'->>'use_case', ''), '_', ' ') || ' (' || coalesce(v_res->>'items', '0') || ' pages, cap ' || coalesce(v_res->>'credits_cap', '-') || ' credits)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'firecrawl', v_title, jsonb_build_object('run_id', v_res->>'run_id', 'use_case', p_args->'args'->>'use_case', 'items', (v_res->>'items')::int), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'items')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'use_case')
        returning * into v_j;
      v_ids := '{}';
    elsif v_kind = 'adapter_apply' then
      v_res := public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'reason', v_reason));
      v_title := 'Apply the adapter: ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '') || ' (' || coalesce(v_res->>'pages_read_again', '0') || ' pages)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'pages', coalesce((v_res->>'pages_read_again')::int, 0), 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages_read_again')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    elsif v_kind = 'central_page_read' then
      v_res := public.admin_provider_central_page(coalesce(nullif(p_args->'args'->>'action', ''), 'add'), jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'title', p_args->'args'->>'title', 'reason', v_reason));
      v_title := 'Read a central page: ' || replace(coalesce(p_args->'args'->>'kind', ''), '_', ' ') || ' for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('source_id', v_res->>'source_id', 'provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', 1), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks (provider, several providers, course, scholarship)
    elsif v_kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      v_res := security.scholarship_task_prepare_v1(v_kind, coalesce(p_args->'args', '{}'::jsonb));
      if exists (select 1 from pipeline.admin_jobs j where j.kind = v_kind and j.scope is not distinct from (v_res->>'scope') and j.state in ('queued', 'running', 'paused')) then
        raise exception 'this check is already running; see Scheduled jobs › Task manager';
      end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'scholarships:' || v_kind || ':' || coalesce(v_res->>'scope', ''), v_res->>'title', v_res - 'title' - 'scope', jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages')::int, 0)), auth.uid(), v_reason, v_res->>'scope')
        returning * into v_j;
      v_ids := array(select x::uuid from jsonb_array_elements_text(v_res->'providers') x);
      perform security.scholarship_task_fire_v1(case when v_kind = 'scholarship_provider_scan' then array['discover', 'read'] else array['read'] end);
    -- 11 Oct 2026 (CF-247, Platform Admin bugs 11/10-2): Fill in a provider from its website; Find course pages with Firecrawl
    elsif v_kind in ('provider_fill', 'course_page_find') then
      v_res := security.provider_task_prepare_v1(v_kind, coalesce(p_args->'args', '{}'::jsonb));
      if exists (select 1 from pipeline.admin_jobs j where j.kind = v_kind and j.scope is not distinct from (v_res->>'scope') and j.state in ('queued', 'running', 'paused')) then
        raise exception 'this task is already running; see Scheduled jobs › Task manager';
      end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'providers:' || v_kind || ':' || coalesce(v_res->>'scope', ''), v_res->>'title', v_res - 'title' - 'scope',
                jsonb_build_object('done', 0, 'total', case when v_kind = 'provider_fill' then 3 else jsonb_array_length(v_res->'course_ids') end), auth.uid(), v_reason, v_res->>'scope')
        returning * into v_j;
      v_ids := array[(v_res->>'provider_id')::uuid];
      if v_kind = 'provider_fill' then
        perform security.provider_task_fire_v1(case when coalesce((v_res->>'had_website')::boolean, false) then 'contact_page' else 'find_site' end);
      end if;
    else
      raise exception 'unknown job kind';
    end if;
    insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_start', v_j.id::text, jsonb_build_object('kind', v_kind, 'title', v_j.title, 'providers', array_length(v_ids, 1), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_j.id, 'title', v_j.title, 'providers', array_length(v_ids, 1));
  end if;
  v_id := (p_args->>'id')::uuid;
  select * into v_j from pipeline.admin_jobs j where j.id = v_id;
  if v_j.id is null then raise exception 'unknown job'; end if;
  if v_rank < 5 and v_j.requested_by <> auth.uid() then raise exception 'only the person who started it, or an Operator, may change this job' using errcode = '42501'; end if;
  if p_action = 'cancel' then
    if v_j.state in ('done', 'failed', 'cancelled') then raise exception 'the job has already finished'; end if;
    if v_j.kind = 'reread_pages' then
      update pipeline.university_reread_requests set status = 'cancelled', finished_at = now() where id = (v_j.args->>'request_id')::uuid and status in ('waiting', 'sending');
    elsif v_j.kind = 'firecrawl_run' then
      perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason));
    elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      -- the pages lose their place at the front of the queue; they are read again in their normal turn
      update pipeline.scholarship_pages p set requested_at = null from scholarship.scholarships s
       where s.id = p.scholarship_id and p.requested_at is not null
         and (s.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x))
              or s.id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x)));
      update pipeline.scholarship_page_candidates c set requested_at = null
       where c.requested_at is not null and c.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x));
    elsif v_j.kind = 'course_page_find' then
      -- the courses lose their place at the front of the course page search; they are searched in their normal turn
      update pipeline.course_link_search set requested_at = null
       where requested_at is not null and course_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'course_ids', '[]'::jsonb)) x));
    elsif v_j.kind = 'provider_fill' then
      update pipeline.coverage_provider_discovery set requested_at = null where provider_id = (v_j.args->>'provider_id')::uuid and requested_at is not null;
      update pipeline.provider_central_search set requested_at = null where provider_id = (v_j.args->>'provider_id')::uuid and requested_at is not null;
    end if;
    if v_j.state in ('queued', 'paused') then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now(), cancel_requested = true where id = v_id;
      perform security.admin_job_close_v1(v_id);
    else
      update pipeline.admin_jobs set cancel_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'pause' then
    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'; end if;
    if not coalesce((select k.can_pause from pipeline.admin_job_kinds k where k.kind = v_j.kind), false) then raise exception 'this task cannot be paused, only cancelled'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'paused', updated_at = now() where id = v_id;
    else
      update pipeline.admin_jobs set pause_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'resume' then
    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('continue', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    update pipeline.admin_jobs set state = 'queued', pause_requested = false, updated_at = now() where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_id, p_action || ' requested by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_' || p_action, v_id::text, jsonb_build_object('title', v_j.title, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$;

-- 8. Once: websites already found and verified go on the provider record (41 at the time of writing)
select count(*) filter (where security.provider_website_adopt_v1(d.provider_id, d.website)) as websites_adopted
  from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id
 where d.site_source like 'search_verified_%' and nullif(btrim(d.website), '') is not null and nullif(btrim(p.website), '') is null and p.lifecycle_status = 'active';

-- 9. Once: every active provider without a website is queued for the search (Platform Admin: all of them, Canada included);
--    those skipped as "budget" (not Firecrawl targets) are searched again now
insert into pipeline.coverage_provider_discovery(provider_id, status, updated_at)
select p.id, 'no_website', now() from catalogue.providers p
 where p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is null
   and not exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = p.id)
on conflict (provider_id) do nothing;
update pipeline.coverage_provider_discovery set site_searched_at = null, leased_until = null, updated_at = now()
 where status = 'no_website' and coalesce(site_evidence->>'note', '') ilike '%budget%';

-- 10. Once: providers with a website and active courses are queued for the central page search (largest first)
insert into pipeline.provider_central_search(provider_id, state)
select p.id, 'queued' from catalogue.providers p
 where p.lifecycle_status = 'active' and p.website ~* '^https?://'
   and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
on conflict (provider_id) do nothing;

do $post$
declare v_expected jsonb := '{"public.svc_coverage_site_next(integer)": "a9b60629be9529185cb767d0f641493d", "public.svc_coverage_site_record(uuid,text,jsonb)": "1720c7382c1374d85c59b01f80cfffaf", "security.course_link_search_tick_v1(integer)": "13b0771da8ae1831ff1291bfac82faa6", "public.admin_adapter_builder_basics(text,jsonb)": "4ae55199dfa8d7dbfa74c7d65067c200", "security.admin_job_slice_v1(uuid,integer)": "6ced8179e6c4279008fd53d1b73beaec", "security.admin_job_watch_v1(uuid)": "90a14cb34e5383cdb265e7ec4c46a56e", "public.admin_jobs(text,jsonb)": "43e1caadcc5c59ac0fd1a369006aed3b"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $chk$
declare v_left int; v_unq int; v_cs int;
begin
  select count(*) into v_left from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id
   where d.site_source like 'search_verified_%' and nullif(btrim(d.website), '') is not null and nullif(btrim(p.website), '') is null and p.lifecycle_status = 'active'
     and not security.third_party_host_v1(d.website) and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field = 'website');
  if v_left > 0 then raise exception 'CF-247 post-check: % verified website(s) still not on the provider record', v_left; end if;
  select count(*) into v_unq from catalogue.providers p where p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is null
     and not exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = p.id);
  if v_unq > 0 then raise exception 'CF-247 post-check: % provider(s) without a website are not queued for the search', v_unq; end if;
  select count(*) into v_cs from pipeline.admin_job_kinds where kind in ('provider_fill', 'course_page_find');
  if v_cs <> 2 or not exists (select 1 from cron.job where jobname = 'central-find') or not exists (select 1 from pipeline.automation_catalogue where jobname = 'central-find') then
    raise exception 'CF-247 post-check: task types or the central-find job are missing';
  end if;
end $chk$;
