-- CF-247 (11 Oct 2026, bugs 11/10-2 follow-up, found in the live check of 20261011009400):
--  1. Humber College was matched to www.guelphhumber.ca (the University of Guelph-Humber, a different institution) by the rule
--     "name on the page and the address fits the name". Worker v0.19.0 now refuses an address that carries another distinctive
--     name. Humber's website, the course-page search recipe built from it and its 276 queued course searches are switched off,
--     and its website is searched again. Nothing is deleted.
--  2. A website found later replaces a switched-off generic search recipe (one recipe per provider).
--  3. "Find course pages with Firecrawl" uses the provider as its task scope, so its button finds the running task again.
-- md5-checked before and after.
do $guard$
declare v_expected jsonb := '{"security.provider_website_adopt_v1(uuid,text)": "38a5576fc70d48dabd4b2359a33e58e3", "security.provider_task_prepare_v1(text,jsonb)": "8584664912801ef17e7fbdecf6f11d48"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION security.provider_website_adopt_v1(p_provider_id uuid, p_url text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    on conflict (provider_id) do update set search_domain = excluded.search_domain, patterns = excluded.patterns, active = true, notes = excluded.notes, updated_at = now()
     where not pipeline.course_link_recipes.active and pipeline.course_link_recipes.notes like 'Generic recipe%';
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
end $function$;

CREATE OR REPLACE FUNCTION security.provider_task_prepare_v1(p_kind text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
                              'scope', v_pid::text);
  end if;
  raise exception 'unknown provider task';
end $function$;

-- Humber College: the wrong website off the record, its recipe switched off (its queued searches wait), searched again first
update pipeline.course_link_recipes r set active = false, notes = 'Switched off 11 Oct 2026: built from www.guelphhumber.ca, which is not Humber College''s site. ' || r.notes, updated_at = now()
 where r.provider_id = '570ddbbd-f07e-4060-b52d-c5322dcdaa00' and r.search_domain = 'guelphhumber.ca' and r.active;
update catalogue.providers set website = null, updated_at = now()
 where id = '570ddbbd-f07e-4060-b52d-c5322dcdaa00' and website = 'https://www.guelphhumber.ca';
update pipeline.coverage_provider_discovery
   set website = null, site_source = null, status = 'no_website', site_searched_at = null, leased_until = null, requested_at = now(), updated_at = now(),
       site_evidence = coalesce(site_evidence, '{}'::jsonb) || jsonb_build_object('refused', 'https://www.guelphhumber.ca', 'refused_why', 'the University of Guelph-Humber''s site, not Humber College''s (11 Oct 2026)')
 where provider_id = '570ddbbd-f07e-4060-b52d-c5322dcdaa00' and website = 'https://www.guelphhumber.ca';

do $post$
declare v_expected jsonb := '{"security.provider_website_adopt_v1(uuid,text)": "74186619b63278589d5b276482521086", "security.provider_task_prepare_v1(text,jsonb)": "77d029207a8737f9e17adcc6670f1c6a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $chk$
begin
  if exists (select 1 from catalogue.providers where website ilike '%guelphhumber%' and id = '570ddbbd-f07e-4060-b52d-c5322dcdaa00')
     or exists (select 1 from pipeline.course_link_recipes where provider_id = '570ddbbd-f07e-4060-b52d-c5322dcdaa00' and active and search_domain = 'guelphhumber.ca') then
    raise exception 'CF-247 post-check: Humber College still points at guelphhumber.ca';
  end if;
end $chk$;
