-- CF-247 Firecrawl format profiles (Platform Admin 14 Nov 2026 19:19; answers 14 Nov 2026: screenshots off by default and kept as received,
-- crawl settings checked only with no crawl runs, the screen built after the mock-up is accepted). Numbered after R7 (20261114193000).
-- What a Firecrawl /v2/scrape asks for is set per profile in the existing Toolsets and limits › Firecrawl settings (no new dashboard or settings
-- editor, F-OPS.08): formats (markdown, rawHtml, html, links, screenshot only), onlyMainContent, includeTags, excludeTags, maxAge, waitFor,
-- timeout, optional actions, and crawl options (limit, maxDiscoveryDepth, includePaths, excludePaths, sitemap) checked for later use.
-- json, summary, question, highlights, every other format and onlyCleanContent are refused here (security.fc_scrape_profiles_check_v1) and
-- dropped again by the worker client (firecrawl.ts applyProfile): no surcharge format and no unpinned AI pass is ever sent.
-- Each worker lane is mapped to a profile; a provider can have its own profile for a lane. Lanes mapped to lane_own (AER v1 lanes, Decision 276;
-- adapter capture; the diagnostic probe) and lanes not in the map send their own request unchanged.
-- The seeds keep today's requests (each lane's formats and onlyMainContent, no waitFor or timeout so each lane keeps its own, Firecrawl's own
-- 2-day copy age) and add markdown to the page reads: rawHtml and markdown in one 1-credit call. Course pages keep onlyMainContent false
-- until a read shows rawHtml is unchanged by it (today's reader needs content outside <main>).
-- Worker coverage-sweep v0.99.0 keeps the markdown (and a screenshot only when a profile asks) beside the stored page and records them on the
-- same evidence row (public.svc_evidence_formats_attach_v1): files, profile, profile version, formats, copy age, cache state, page status, credits.
-- No route switch, ceiling, Observe/Stop mode, model route or paused queue changes; aer.v2_shadow_on is not read or written.
-- G2: the profiles and the screenshot size limit are settings; Firecrawl's own API bounds in the check are marked fixed.
-- G3: no consumer API object is read or changed (evidence metadata gains keys beside the existing ones; no column changes).
-- Replaces: public.svc_worker_settings_v1() and public.admin_toolsets_write(text,jsonb) (same names and signatures; md5-guarded edits of the live
--   text); the kind check of pipeline.platform_toolset_settings (same name, json added). The firecrawl setting read_formats stays: lanes mapped to
--   lane_own and the probe still read it.
-- Retires: nothing.

set local lock_timeout = '3s';

-- 1. A setting can hold a set of values (kind json). It is changed only on its own screen, never as text.
do $c$
declare v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'pipeline.platform_toolset_settings'::regclass and c.conname = 'platform_toolset_settings_kind_check';
  if position('json' in coalesce(v_def, '')) = 0 then
    execute format('alter table pipeline.platform_toolset_settings drop constraint %I, add constraint %I check (kind = any (array[%L::text, %L::text, %L::text, %L::text, %L::text]))',
                   'platform_toolset_settings_kind_check', 'platform_toolset_settings_kind_check', 'number', 'text', 'boolean', 'list', 'json');
  end if;
end $c$;

-- 2. The check every save and the worker make (the same rules as firecrawl.ts checkProfile / checkProfiles). Returns every problem in words.
-- Type tests first, in a case, so a wrong type is a problem in words and never a cast error.
create or replace function security.fc_int_in_v1(v jsonb, lo numeric, hi numeric) returns boolean
language sql immutable set search_path to '' as $function$
  select case when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric = trunc((v #>> '{}')::numeric) and (v #>> '{}')::numeric between lo and hi else false end
$function$;
create or replace function security.fc_str_list_ok_v1(v jsonb, n int, pattern text, max_len int) returns boolean
language sql immutable set search_path to '' as $function$
  select case when jsonb_typeof(v) = 'array' then jsonb_array_length(v) <= n
              and not exists (select 1 from jsonb_array_elements(v) x
                               where case when jsonb_typeof(x) = 'string' then length(x #>> '{}') not between 1 and max_len or (pattern is not null and (x #>> '{}') !~ pattern) else true end)
         else false end
$function$;
create or replace function security.fc_scrape_profile_check_v1(p jsonb, p_name text) returns text[]
language plpgsql immutable set search_path to '' as $function$
declare e text[] := '{}'; k text; f jsonb; a jsonb; c jsonb; v_formats text[] := array['markdown', 'rawHtml', 'html', 'links', 'screenshot'];
        v_keys text[] := array['name', 'about', 'formats', 'onlyMainContent', 'includeTags', 'excludeTags', 'maxAgeMs', 'waitFor', 'timeout', 'actions', 'screenshotFullPage', 'crawl'];
        v_actions text[] := array['click', 'wait', 'scroll', 'press', 'write'];
        v_tag text := '^[a-zA-Z][a-zA-Z0-9-]{0,40}$|^[.#][A-Za-z0-9_-]{1,60}$';
begin
  if p is null or jsonb_typeof(p) <> 'object' then return array[p_name || ': not a profile']; end if;
  for k in select jsonb_object_keys(p) loop
    if not k = any (v_keys) then
      e := e || case when k = 'onlyCleanContent' then p_name || ': onlyCleanContent is never sent (an AI pass over the page)' else p_name || ': ' || k || ' is not a profile setting' end;
    end if;
  end loop;
  if (case when jsonb_typeof(p->'formats') = 'array' then jsonb_array_length(p->'formats') = 0 else true end) then e := e || (p_name || ': choose at least one format');
  else
    for f in select jsonb_array_elements(p->'formats') loop
      if (case when jsonb_typeof(f) = 'string' then not (f #>> '{}') = any (v_formats) else true end) then
        e := e || (p_name || ': format ' || coalesce(f #>> '{}', f::text) || ' is never sent (only markdown, rawHtml, html, links, screenshot)');
      end if;
    end loop;
    if (select count(distinct x) from jsonb_array_elements(p->'formats') x) <> jsonb_array_length(p->'formats') then e := e || (p_name || ': a format is named twice'); end if;
    if not exists (select 1 from jsonb_array_elements_text(p->'formats') x where x in ('markdown', 'rawHtml', 'html', 'links')) then
      e := e || (p_name || ': a screenshot alone is not a page read; add markdown, rawHtml, html or links');
    end if;
  end if;
  if p ? 'onlyMainContent' and jsonb_typeof(p->'onlyMainContent') <> 'boolean' then e := e || (p_name || ': onlyMainContent is yes or no'); end if;
  foreach k in array array['includeTags', 'excludeTags'] loop
    if p ? k and not security.fc_str_list_ok_v1(p->k, 40, v_tag, 61) then
      e := e || (p_name || ': ' || k || ' is a list of tag names or .class/#id selectors');
    end if;
  end loop;
  -- fixed: Firecrawl API bounds (maxAge at most 30 days here, waitFor 0 to 60,000 ms, timeout 1,000 to 300,000 ms)
  if coalesce(jsonb_typeof(p->'maxAgeMs'), 'null') <> 'null' and not security.fc_int_in_v1(p->'maxAgeMs', 0, 2592000000) then
    e := e || (p_name || ': the Firecrawl copy age is 0 to 30 days'); end if;
  if coalesce(jsonb_typeof(p->'waitFor'), 'null') <> 'null' and not security.fc_int_in_v1(p->'waitFor', 0, 60000) then
    e := e || (p_name || ': wait after load is 0 to 60,000 ms'); end if;
  if coalesce(jsonb_typeof(p->'timeout'), 'null') <> 'null' and not security.fc_int_in_v1(p->'timeout', 1000, 300000) then
    e := e || (p_name || ': time allowed is 1,000 to 300,000 ms'); end if;
  if security.fc_int_in_v1(p->'waitFor', 0, 60000) and security.fc_int_in_v1(p->'timeout', 1000, 300000) and (p->>'waitFor')::numeric >= (p->>'timeout')::numeric then
    e := e || (p_name || ': wait after load must be shorter than the time allowed'); end if;
  if coalesce(jsonb_typeof(p->'actions'), 'null') <> 'null' then
    if (case when jsonb_typeof(p->'actions') = 'array' then jsonb_array_length(p->'actions') > 20 else true end) then e := e || (p_name || ': actions are a list of at most 20 steps');
    else
      for a in select jsonb_array_elements(p->'actions') loop
        if jsonb_typeof(a) <> 'object' or not coalesce(a->>'type', '') = any (v_actions) then
          e := e || (p_name || ': action ' || coalesce(a->>'type', a::text) || ' is not allowed (only click, wait, scroll, press, write)');
        end if;
      end loop;
    end if;
  end if;
  if p ? 'screenshotFullPage' and jsonb_typeof(p->'screenshotFullPage') <> 'boolean' then e := e || (p_name || ': full-page screenshot is yes or no'); end if;
  if p ? 'crawl' then
    c := p->'crawl';
    if jsonb_typeof(c) <> 'object' then e := e || (p_name || ': crawl options are a set of values');
    else
      for k in select jsonb_object_keys(c) loop
        if not k = any (array['limit', 'maxDiscoveryDepth', 'includePaths', 'excludePaths', 'sitemap']) then
          e := e || (p_name || ': crawl ' || k || ' is not a crawl option (maxDiscoveryDepth, not maxDepth)'); end if;
      end loop;
      if c ? 'limit' and not security.fc_int_in_v1(c->'limit', 1, 1000) then
        e := e || (p_name || ': crawl pages at most is 1 to 1,000'); end if;  -- fixed: a sanity bound on a checked-only option (no lane crawls)
      if c ? 'maxDiscoveryDepth' and not security.fc_int_in_v1(c->'maxDiscoveryDepth', 0, 10) then
        e := e || (p_name || ': crawl link depth is 0 to 10'); end if;
      foreach k in array array['includePaths', 'excludePaths'] loop
        if c ? k and not security.fc_str_list_ok_v1(c->k, 50, null, 200) then
          e := e || (p_name || ': crawl ' || k || ' is a list of path patterns'); end if;
      end loop;
      if c ? 'sitemap' and not coalesce(c->>'sitemap', '') = any (array['include', 'skip', 'only']) then e := e || (p_name || ': crawl site map is include, skip or only'); end if;
    end if;
  end if;
  return e;
end $function$;
comment on function security.fc_scrape_profile_check_v1(jsonb, text) is 'CF-247 Firecrawl format profiles: every problem with one scrape profile, in words (empty when it can be saved and sent). Formats only markdown, rawHtml, html, links, screenshot; onlyCleanContent and every other key refused. The same rules as checkProfile in coverage-sweep/firecrawl.ts.';

create or replace function security.fc_scrape_profiles_check_v1(p_profiles jsonb, p_lanes jsonb, p_overrides jsonb) returns text[]
language plpgsql immutable set search_path to '' as $function$
declare e text[] := '{}'; k text; v jsonb; o jsonb;
begin
  if p_profiles is null or jsonb_typeof(p_profiles) <> 'object' or p_profiles = '{}'::jsonb then e := e || 'profiles: at least one profile'::text;
  else
    for k, v in select * from jsonb_each(p_profiles) loop
      if k !~ '^[a-z][a-z0-9_]{0,40}$' or k = 'lane_own' then e := e || ('profile name ' || k || ' is not allowed'); end if;
      e := e || security.fc_scrape_profile_check_v1(v, k);
    end loop;
  end if;
  if p_lanes is not null and jsonb_typeof(p_lanes) <> 'object' then e := e || 'lanes: a set of lane and profile';
  else
    for k, v in select * from jsonb_each(coalesce(p_lanes, '{}'::jsonb)) loop
      if jsonb_typeof(v) <> 'string' or ((v #>> '{}') <> 'lane_own' and not coalesce(p_profiles ? (v #>> '{}'), false)) then
        e := e || ('lane ' || k || ': profile ' || coalesce(v #>> '{}', v::text) || ' does not exist'); end if;
    end loop;
  end if;
  if p_overrides is not null and jsonb_typeof(p_overrides) <> 'array' then e := e || 'overrides: a list';
  else
    for o in select jsonb_array_elements(coalesce(p_overrides, '[]'::jsonb)) loop
      if coalesce(o->>'provider_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or coalesce(o->>'lane', '') = ''
         or not (o->>'profile' = 'lane_own' or coalesce(p_profiles ? (o->>'profile'), false)) then
        e := e || ('override for ' || coalesce(o->>'provider_id', '?') || ': needs a university, a lane and an existing profile');
      end if;
    end loop;
  end if;
  return e;
end $function$;
comment on function security.fc_scrape_profiles_check_v1(jsonb, jsonb, jsonb) is 'CF-247 Firecrawl format profiles: every problem with the whole set (profiles, lane map, provider overrides), in words. The same rules as checkProfiles in coverage-sweep/firecrawl.ts; a set the worker finds wrong is not used (each lane then sends its own request).';

-- 3. The settings (seeded with today's requests plus markdown on page reads).
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by, control_class)
values
 ('firecrawl', 'scrape_profiles', 'Format profiles',
  'What a Firecrawl page read asks for, by profile: formats (markdown, rawHtml, html, links, screenshot), main content only, tags kept or left out, copy age, wait, time allowed, actions, crawl options. Changed on Format profiles with a reason.',
  'json', $j${
    "page_html":      {"name": "Page HTML and markdown", "about": "Course pages, lists, About pages and site checks: the raw page for the readers and markdown kept beside it, one credit.", "formats": ["rawHtml", "markdown"], "onlyMainContent": false, "maxAgeMs": 172800000},
    "aer_hub_page":   {"name": "AER hub page", "about": "Country and entry-band tables in side panels: the whole page, never main content only. Not mapped while AER v1 is frozen (Decision 276).", "formats": ["rawHtml", "markdown"], "onlyMainContent": false, "maxAgeMs": 172800000},
    "text_full":      {"name": "Whole page as text", "about": "Register and address pages read as text.", "formats": ["markdown"], "onlyMainContent": false, "maxAgeMs": 172800000},
    "text_main":      {"name": "Main content as text", "about": "Provider facts documents.", "formats": ["markdown"], "onlyMainContent": true, "maxAgeMs": 172800000},
    "register_links": {"name": "Register links and text", "about": "Register search pages: the links and the text.", "formats": ["links", "markdown"], "onlyMainContent": true, "maxAgeMs": 172800000}
  }$j$::jsonb, null, null, 'profiles', 200, 'Firecrawl format profiles, Platform Admin 14 Nov 2026 19:19: today''s requests plus markdown on page reads', 'Format profiles',
  'worker coverage-sweep v0.99.0: every scrape through fcClient (firecrawl.ts); public.admin_fc_profiles_set_v1', 'human'),
 ('firecrawl', 'scrape_profile_lanes', 'Profile each lane uses',
  'Which profile each worker lane sends. lane_own: the lane sends its own request unchanged (AER v1 lanes, adapter capture, the probe). A lane not listed sends its own request.',
  'json', $j${
    "course_read": "page_html", "course_read_view": "page_html", "course_read_priority": "page_html", "read_page": "page_html",
    "companion_read": "page_html", "course_list_read": "page_html", "source_find": "page_html", "programme_discover": "page_html", "programme_read": "page_html",
    "provider_description": "page_html", "site_check": "page_html", "find_site": "page_html", "scholarship_read": "page_html",
    "cricos_peo": "text_full", "enrich_address": "text_full", "provider_facts_read": "text_main", "find_site_register": "register_links",
    "entry_render": "lane_own", "entry_fallback": "lane_own", "entry_pdf_render": "lane_own", "adapter_builder": "lane_own", "probe": "lane_own"
  }$j$::jsonb, null, null, 'lanes', 201, 'Firecrawl format profiles, Platform Admin 14 Nov 2026 19:19', 'Format profiles',
  'worker coverage-sweep v0.99.0: resolveProfile (firecrawl.ts)', 'human'),
 ('firecrawl', 'scrape_profile_overrides', 'University overrides',
  'A university that needs another profile for one lane (for example a site that hides its entry bands outside the main content).',
  'json', '[]'::jsonb, null, null, 'overrides', 202, 'Firecrawl format profiles, Platform Admin 14 Nov 2026 19:19 (none yet)', 'Format profiles',
  'worker coverage-sweep v0.99.0: resolveProfile (firecrawl.ts)', 'human'),
 ('firecrawl', 'scrape_profiles_version', 'Format profiles version',
  'Goes up by one with every saved change; recorded on each evidence row the profiles produced.',
  'number', '1'::jsonb, 1, 1000000, 'version', 203, 'Firecrawl format profiles, first version', 'Format profiles',
  'worker coverage-sweep v0.99.0: evidence metadata firecrawl.profile_version; public.admin_fc_profiles_set_v1', 'automatic'),
 ('firecrawl', 'screenshot_max_mb', 'Largest screenshot kept',
  'A screenshot a profile asks for is kept as received up to this size; a larger one is noted on the evidence row and not kept. No profile asks for screenshots today.',
  'number', '15'::jsonb, 1, 50, 'MB', 204, 'Firecrawl format profiles: screenshots off by default (Platform Admin 14 Nov 2026)', 'Format profiles',
  'worker coverage-sweep v0.99.0: keepFormats', 'human')
on conflict (toolset_key, key) do nothing;

-- 4. Save and read the profiles (Toolsets and limits › Firecrawl › Format profiles).
create or replace function public.admin_fc_profiles_set_v1(p_profiles jsonb, p_lanes jsonb, p_overrides jsonb, p_reason text, p_expected_version int default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_reason, '')); v_errs text[]; v_ver int; v_before jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  v_errs := security.fc_scrape_profiles_check_v1(p_profiles, coalesce(p_lanes, '{}'::jsonb), coalesce(p_overrides, '[]'::jsonb));
  if cardinality(v_errs) > 0 then raise exception 'not saved: %', array_to_string(v_errs, '; ') using errcode = '22023'; end if;
  select (value #>> '{}')::int into v_ver from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'scrape_profiles_version' for update;
  if p_expected_version is not null and p_expected_version <> v_ver then
    raise exception 'someone saved version % since you opened this; reload and make the change again', v_ver using errcode = '40001';
  end if;
  select jsonb_object_agg(key, value) into v_before from pipeline.platform_toolset_settings
   where toolset_key = 'firecrawl' and key in ('scrape_profiles', 'scrape_profile_lanes', 'scrape_profile_overrides');
  update pipeline.platform_toolset_settings s set value = x.v, reason = v_reason, updated_by = auth.uid(), updated_at = now()
    from (values ('scrape_profiles', p_profiles), ('scrape_profile_lanes', coalesce(p_lanes, '{}'::jsonb)), ('scrape_profile_overrides', coalesce(p_overrides, '[]'::jsonb)),
                 ('scrape_profiles_version', to_jsonb(v_ver + 1))) x(k, v)
   where s.toolset_key = 'firecrawl' and s.key = x.k;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'fc_profiles', 'firecrawl.scrape_profiles',
          jsonb_build_object('version', v_ver + 1, 'before', v_before, 'after', jsonb_build_object('scrape_profiles', p_profiles, 'scrape_profile_lanes', p_lanes, 'scrape_profile_overrides', p_overrides), 'reason', v_reason),
          auth.uid());
  return jsonb_build_object('ok', true, 'version', v_ver + 1);
end $function$;
comment on function public.admin_fc_profiles_set_v1(jsonb, jsonb, jsonb, text, int) is 'CF-247 Firecrawl format profiles: Platform Admin saves the profiles, the lane map and the university overrides together with a reason; refused when security.fc_scrape_profiles_check_v1 finds a problem or someone saved since (p_expected_version); the version goes up by one; logged in admin_control_events.';
revoke all on function public.admin_fc_profiles_set_v1(jsonb, jsonb, jsonb, text, int) from public, anon;
grant execute on function public.admin_fc_profiles_set_v1(jsonb, jsonb, jsonb, text, int) to authenticated;

create or replace function public.admin_fc_profiles_read_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v jsonb;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select jsonb_build_object(
    'profiles', max(case when key = 'scrape_profiles' then value end), 'lanes', max(case when key = 'scrape_profile_lanes' then value end),
    'overrides', max(case when key = 'scrape_profile_overrides' then value end),
    'version', max(case when key = 'scrape_profiles_version' then (value #>> '{}')::int end),
    'screenshot_max_mb', max(case when key = 'screenshot_max_mb' then (value #>> '{}')::numeric end),
    'saved_at', max(updated_at) filter (where key = 'scrape_profiles_version'), 'reason', max(reason) filter (where key = 'scrape_profiles_version'),
    'formats', '["markdown","rawHtml","html","links","screenshot"]'::jsonb, 'never_sent', '["json","summary","question","highlights","onlyCleanContent"]'::jsonb,
    'can_edit', coalesce(security.current_role_rank(), 0) >= 6)
    into v from pipeline.platform_toolset_settings
   where toolset_key = 'firecrawl' and key in ('scrape_profiles', 'scrape_profile_lanes', 'scrape_profile_overrides', 'scrape_profiles_version', 'screenshot_max_mb');
  v := v || jsonb_build_object('problems', to_jsonb(security.fc_scrape_profiles_check_v1(v->'profiles', v->'lanes', v->'overrides')),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'version', e.detail->'version', 'reason', e.detail->>'reason') order by e.created_at desc)
                           from (select * from pipeline.admin_control_events where area = 'toolsets' and action = 'fc_profiles' order by created_at desc limit 10) e), '[]'::jsonb));
  return v;
end $function$;
comment on function public.admin_fc_profiles_read_v1() is 'CF-247 Firecrawl format profiles: the profiles, lane map, overrides, version, allowed and never-sent formats, any problem the check finds, and the last ten saves, for Toolsets and limits › Firecrawl › Format profiles.';
revoke all on function public.admin_fc_profiles_read_v1() from public, anon;
grant execute on function public.admin_fc_profiles_read_v1() to authenticated;

-- 5. The other formats of a read are recorded on the evidence row of its stored page (newest row with that storage path).
create or replace function public.svc_evidence_formats_attach_v1(p_rows jsonb) returns int
language plpgsql security definer set search_path to '' as $function$
declare x jsonb; v_base text; v_files jsonb; v_fc jsonb; v_n int := 0; v_id uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 50 then raise exception 'a list of at most 50 rows'; end if;  -- fixed: one call's size
  for x in select jsonb_array_elements(p_rows) loop
    if coalesce(x->>'storage_path', '') = '' then continue; end if;
    v_base := regexp_replace(x->>'storage_path', '(\.html\.gz|\.gz)$', '');
    -- only files stored beside the page itself are recorded
    select coalesce(jsonb_object_agg(k, val), '{}'::jsonb) into v_files from jsonb_each(coalesce(x->'files', '{}'::jsonb)) f(k, val)
     where k in ('stored', 'markdown', 'screenshot', 'screenshot_skipped') and jsonb_typeof(val) = 'string'
       and (k = 'screenshot_skipped' or (val #>> '{}') = x->>'storage_path' or starts_with(val #>> '{}', v_base || '.'));
    select coalesce(jsonb_object_agg(k, val), '{}'::jsonb) into v_fc from jsonb_each(coalesce(x->'firecrawl', '{}'::jsonb)) f(k, val)
     where k in ('profile', 'profile_version', 'formats', 'max_age_ms', 'fresh', 'cache_state', 'cached_at', 'page_status', 'credits_used', 'scrape_id');
    select id into v_id from pipeline.evidence_artifacts where storage_path = x->>'storage_path' order by created_at desc limit 1;
    if v_id is null then continue; end if;
    update pipeline.evidence_artifacts set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('formats', v_files, 'firecrawl', v_fc) where id = v_id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;
comment on function public.svc_evidence_formats_attach_v1(jsonb) is 'CF-247 Firecrawl format profiles (worker coverage-sweep v0.99.0): records on the newest evidence row of a stored page the other formats kept beside it (metadata.formats: stored, markdown, screenshot) and the request (metadata.firecrawl: profile, profile_version, formats, max_age_ms, fresh, cache_state, cached_at, page_status, credits_used, scrape_id). Only files stored beside that page are recorded.';
revoke all on function public.svc_evidence_formats_attach_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_evidence_formats_attach_v1(jsonb) to service_role;

-- 6. The worker reads the profiles; the generic setting editor never writes a set of values as text.
create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_old text, p_new text) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
end $f$;

select pg_temp.edit_once('public.svc_worker_settings_v1()', '5ef1c297c311ea346d95d04b2d430c34',
  $o$'search_results_scholarship_search', 'search_results_scholarship_discover'))$o$,
  $n$'search_results_scholarship_search', 'search_results_scholarship_discover',
                                                          -- CF-247 Firecrawl format profiles (worker v0.99.0)
                                                          'scrape_profiles', 'scrape_profile_lanes', 'scrape_profile_overrides', 'scrape_profiles_version', 'screenshot_max_mb'))$n$);

select pg_temp.edit_once('public.admin_toolsets_write(text,jsonb)', '531d48c1adce92dd78d44a4650d19061',
  $o$    if v_set.key is null then raise exception 'unknown setting'; end if;$o$,
  $n$    if v_set.key is null then raise exception 'unknown setting'; end if;
    -- CF-247 Firecrawl format profiles: a set of values, and the version it carries, change only on their own screen (checked, versioned)
    if v_set.kind = 'json' or (v_set.toolset_key = 'firecrawl' and v_set.key = 'scrape_profiles_version') then
      raise exception 'this setting is changed on Toolsets and limits › Firecrawl › Format profiles'; end if;$n$);

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.fc_scrape_profiles_check_v1', 'Layer 2', 'Firecrawl', 'Format profiles: the check every save and the worker make (surcharge formats and onlyCleanContent refused)', 'active', '{}', '20261114201500'),
 ('function', 'security.fc_scrape_profile_check_v1', 'Layer 2', 'Firecrawl', 'Format profiles: the check of one profile', 'active', '{}', '20261114201500'),
 ('function', 'security.fc_int_in_v1', 'Layer 2', 'Firecrawl', 'Format profiles check: a whole number in a range', 'active', '{}', '20261114201500'),
 ('function', 'security.fc_str_list_ok_v1', 'Layer 2', 'Firecrawl', 'Format profiles check: a short list of short strings', 'active', '{}', '20261114201500'),
 ('function', 'public.admin_fc_profiles_set_v1', 'Layer 2', 'Firecrawl', 'Format profiles: save with a reason (Platform Admin), versioned and logged', 'active', '{}', '20261114201500'),
 ('function', 'public.admin_fc_profiles_read_v1', 'Layer 2', 'Firecrawl', 'Format profiles: the screen''s read', 'active', '{}', '20261114201500'),
 ('function', 'public.svc_evidence_formats_attach_v1', 'Layer 2', 'Firecrawl', 'Records the markdown and screenshot kept beside a stored page, and the request, on its evidence row', 'active', '{}', '20261114201500')
on conflict do nothing;

-- 7. Post-checks: the seeds pass the check, no surcharge format is accepted, nothing else moved.
do $c$
declare v_p jsonb; v_l jsonb; v_o jsonb;
begin
  select max(case when key = 'scrape_profiles' then value end), max(case when key = 'scrape_profile_lanes' then value end), max(case when key = 'scrape_profile_overrides' then value end)
    into v_p, v_l, v_o from pipeline.platform_toolset_settings where toolset_key = 'firecrawl';
  if cardinality(security.fc_scrape_profiles_check_v1(v_p, v_l, v_o)) <> 0 then raise exception 'post-check: the seeded profiles pass the check: %', security.fc_scrape_profiles_check_v1(v_p, v_l, v_o); end if;
  if cardinality(security.fc_scrape_profile_check_v1('{"formats":["rawHtml","json"]}', 't')) = 0 or cardinality(security.fc_scrape_profile_check_v1('{"formats":["summary"]}', 't')) = 0
     or cardinality(security.fc_scrape_profile_check_v1('{"formats":["markdown","question"]}', 't')) = 0 or cardinality(security.fc_scrape_profile_check_v1('{"formats":["markdown","highlights"]}', 't')) = 0
     or cardinality(security.fc_scrape_profile_check_v1('{"formats":["markdown"],"onlyCleanContent":true}', 't')) = 0 then
    raise exception 'post-check: surcharge formats and onlyCleanContent are refused'; end if;
  if exists (select 1 from jsonb_each_text(v_l) where key in ('entry_render', 'entry_fallback', 'entry_pdf_render') and value <> 'lane_own') then
    raise exception 'post-check: AER v1 lanes keep their own request (Decision 276)'; end if;
  if not (public.svc_worker_settings_v1() ? 'scrape_profiles') then raise exception 'post-check: the worker reads the profiles'; end if;
end $c$;
