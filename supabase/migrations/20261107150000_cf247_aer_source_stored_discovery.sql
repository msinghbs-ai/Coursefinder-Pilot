-- CF-247 AER source discovery from stored evidence (Platform Admin mandate 7 Nov 2026 21:57: find what can be discovered and validated WITHOUT paid acquisition).
-- Guards: G1 (the job is catalogued), G2 (every size, switch and wait is a setting), G3 (no consumer API object is touched), Decision 260 (housekeeping),
--   "A passing qualification never switches anything on by itself" (the new step ships OFF and its job ships paused),
--   "Do not spend Firecrawl credits": nothing here fetches a page; it reads links the platform already stored.
-- Replaces: security.entry_matrix_attach_v1 (same name; md5-guarded: a provider with no entry page yet can now be given its first one)
-- Retires: nothing
--
-- Why (production, read only, 7 Nov 2026 AEDT):
--   * 1,424 of 1,476 AER-eligible providers have no row in pipeline.entry_matrix_sources, so no AER source attempt (disposition not_discovered).
--   * Cause 1, a circular gate. security.entry_matrix_attach_v1 attaches a suggested entry page only where security.entry_matrix_enabled_v1(provider) is
--     true. Since the scheduled reading went live (3 Nov 2026) that function, while job aer-scheduled-read is on, also requires that the provider "has an entry
--     page recorded" (an existing pipeline.entry_matrix_sources row). A provider with no entry page can therefore never be given its first one: live, 0 of the
--     1,424 providers pass the gate although all 1,424 are AER-eligible, in a country switched on, and not hidden.
--   * Cause 2, no supply. Entry-page suggestions come only from job central-find (a Firecrawl map of the provider's site; page type entry_requirements was added
--     to the worker on 26 Oct 2026). All 1,679 finished central searches ran from 11 to 22 Oct 2026, before that page type existed, so
--     pipeline.provider_central_search.found holds no entry_requirements suggestion for any provider; 637 more wait for credits (credits_refused 163,
--     credits_reserve 4). Re-mapping costs Firecrawl credits, which are not available.
--   * What is free: the platform already stores the links it read. pipeline.provider_discovery_links (links seen on stored pages, with their link text) and
--     pipeline.coverage_provider_urls (the provider's own site-map addresses it kept) hold, for the providers without a source, a few addresses that the worker's own
--     page rules (coverage-sweep central.ts, kind entry_requirements) score as an international entry-requirements page. This migration applies those same rules to
--     the stored links, on the provider's own website host only, and attaches the best ones through the existing path (found_via search); the existing reader then fetches
--     them directly (robots.txt respected; Firecrawl only where the existing render hosts allow it), reads them, and sends every first read to a person in Layer 4.
-- What this changes:
--   1. security.entry_matrix_attach_allowed_v1(provider): the eligibility of entry_matrix_enabled_v1 without the "entry page already recorded" clause. Everything else
--      (reader on, country, not hidden, AER-eligible and country switched on while the scheduled reading runs, entry.providers otherwise) is the same.
--   2. security.entry_matrix_attach_v1 (md5-guarded edit): uses that rule, so a central-find suggestion can become a provider's first entry page.
--   3. security.entry_source_score_v1(url, title): the worker's entry_requirements page rules as a pure function (same patterns, noise list and score).
--   4. security.entry_source_stored_find_v1(limit, apply): the stored-link step. Own host only; a host shared by another active provider is not attached (identity needs
--      a person); every provider looked at is recorded with the reason in pipeline.aer_source_stored_find. apply false measures and writes nothing.
--   5. Job aer-source-stored-find (catalogued, created PAUSED) and setting aer.source_stored_find_on (0). Nothing is switched on here.
-- Nothing is fetched, read by AI, attached, admitted or published by this migration. Nothing is dropped or deleted. No consumer API object is touched (G3).

do $guard$
declare v_def text;
begin
  select pg_get_functiondef('security.entry_matrix_attach_v1()'::regprocedure) into v_def;
  if md5(v_def) not in ('b34e95379b61ef98a65837686825857f') and v_def not like '%entry_matrix_attach_allowed_v1%' then
    raise exception 'security.entry_matrix_attach_v1 is not the definition this migration replaces (md5 %)', md5(v_def);
  end if;
end $guard$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
('pipeline', 'aer.source_stored_find_on', 'Entry pages from stored links: on',
 'When 1, job aer-source-stored-find looks at the links the platform has already stored for each AER-eligible provider that has no entry-requirements page, and attaches the best page on the provider''s own website (best three at most: Entry matrices: pages tried a provider) for the entry matrix reader. Nothing is fetched or paid for by this step; the reader then fetches the page directly and every first read goes to a person in Layer 4. 0 = off.',
 'number', '0'::jsonb, 0, 1, 'on/off', 953, 'Entry requirements', 'security.entry_source_stored_find_v1 (job aer-source-stored-find)',
 'CF-247 AER source discovery without paid acquisition (Platform Admin mandate 7 Nov 2026 21:57): ships off'),
('pipeline', 'batch.aer_source_stored_find', 'Entry pages from stored links: providers looked at a run',
 'How many providers with no entry-requirements page the job looks at in one run (the ones with most courses first). A provider found to have no candidate is looked at again after the days below.',
 'number', '200'::jsonb, 1, 1500, 'providers', 994, 'Job sizes', 'security.entry_source_stored_find_v1 (job aer-source-stored-find)',
 'CF-247 AER source discovery without paid acquisition (7 Nov 2026): one run covers the 1,424 providers in a few hours'),
('pipeline', 'aer.source_stored_find_recheck_days', 'Entry pages from stored links: look again after',
 'A provider the step looked at without attaching a page (no link material, no candidate, or a website shared with another provider) is looked at again after this many days, because newly stored links can change the answer.',
 'number', '14'::jsonb, 1, 90, 'days', 954, 'Entry requirements', 'security.entry_source_stored_find_v1 (job aer-source-stored-find)',
 'CF-247 AER source discovery without paid acquisition (7 Nov 2026)')
on conflict (toolset_key, key) do nothing;

-- 2. the record of what the step found for each provider, and why not ---------------------------------------------------------------------
create table if not exists pipeline.aer_source_stored_find (
  provider_id uuid primary key references catalogue.providers(id),
  checked_at timestamptz not null default now(),
  outcome text not null check (outcome in ('attached', 'no_link_material', 'no_entry_candidate', 'host_shared')),
  links int not null default 0,
  candidates int not null default 0,
  best_url text,
  best_score numeric,
  attached int not null default 0,
  detail jsonb not null default '{}'::jsonb
);
comment on table pipeline.aer_source_stored_find is 'CF-247 (7 Nov 2026): for each AER-eligible provider without an entry-requirements page, what security.entry_source_stored_find_v1 found in the links the platform already stored (provider_discovery_links, coverage_provider_urls): attached, no_link_material, no_entry_candidate or host_shared, with the best address and score. Nothing here is a source; attached addresses are in pipeline.entry_matrix_sources.';
alter table pipeline.aer_source_stored_find enable row level security;
revoke all on table pipeline.aer_source_stored_find from public, anon, authenticated;

-- 3. the page rules (the worker's coverage-sweep central.ts, kind entry_requirements) as a pure function ------------------------------------
create or replace function security.entry_source_score_v1(p_url text, p_title text) returns numeric language sql immutable set search_path = '' as $function$
  -- fixed: the same page-type rules and score as the worker's central.ts (strong 6 in the address, 4 in the link text, weak 1.5; +2 international; -0.5 PDF; +0.2 a level for a short address)
  with x as (
    select lower(replace(coalesce(substring(p_url from '^https?://[^/?#]+(/[^?#]*)'), '/'), '%20', ' ')) path,
           lower(coalesce(substring(p_url from '(\?[^#]*)'), '')) qs, lower(coalesce(p_title, '')) title),
  y as (
    select x.*, cardinality(array_remove(string_to_array(x.path, '/'), '')) depth,
           (x.path ~ 'country[-_ ]?equivalen|academic[-_ ]?(equivalen|entry[-_ ]?requirements?|requirements)|international[-_ ]?(and[-_ ]?overseas[-_ ]?)?qualifications|overseas[-_ ]?qualifications|qualifications?[-_ ]?(by[-_ ]?country|equivalen)|admission[-_ ]?by[-_ ]?country|entry[-_ ]?requirements?[-_ ]?(by[-_ ]?country|for[-_ ]?international)|international[-_ ]?(academic[-_ ]?)?entry[-_ ]?requirements?|minimum[-_ ]?entry[-_ ]?score') strong_path,
           (x.title ~ 'country[-_ ]?equivalen|academic[-_ ]?(equivalen|entry[-_ ]?requirements?|requirements)|international[-_ ]?(and[-_ ]?overseas[-_ ]?)?qualifications|overseas[-_ ]?qualifications|qualifications?[-_ ]?(by[-_ ]?country|equivalen)|admission[-_ ]?by[-_ ]?country|entry[-_ ]?requirements?[-_ ]?(by[-_ ]?country|for[-_ ]?international)|international[-_ ]?(academic[-_ ]?)?entry[-_ ]?requirements?|minimum[-_ ]?entry[-_ ]?score') strong_title,
           (x.path ~ 'entry[-_ ]?requirements?' or x.title ~ 'entry[-_ ]?requirements?') weak,
           -- an English-language requirements page is the English rule, not the academic entry matrix
           ((x.path || ' ' || x.title) ~ 'english|ielts|language[-_ ]?requirements?') english,
           ((x.path || x.qs) ~ '/(news|events?|blog|stories|media|staff|people|profiles?|search|login|signin|tags?|category|careers?|jobs|research|alumni|giving|donate|library|shop|cart|wp-admin|feed|residence|housing|accommodation|insurance|medical|parking|workshops?|pubs|publications)(/|$)|refund|extension|request[-_ ]?form|meals?|events[-_ ]?calendar|\.(jpe?g|png|gif|svg|zip|docx?|xlsx?|pptx?)$|[?&](page|s|q)=') noise,
           ((x.path || ' ' || x.title) ~ 'international|overseas|\yintl\y') intl,
           (x.path ~ '\.pdf$') pdf
      from x)
  select case when english or noise or not (strong_path or strong_title or weak) then null
              else round((case when strong_path then 6 when strong_title then 4 else 1.5 end) + (case when intl then 2 else 0 end) - (case when pdf then 0.5 else 0 end) + greatest(0, 5 - depth) * 0.2, 1) end
    from y
$function$;
comment on function security.entry_source_score_v1(text, text) is 'CF-247 (7 Nov 2026): the score the worker (coverage-sweep central.ts, kind entry_requirements) gives a link as a provider''s international entry-requirements page, from its address and link text; null when it is not a candidate (English page, noise, no entry-requirements wording). 3 and above is a suggestion; central.min_suggest_score decides what is attached.';
revoke all on function security.entry_source_score_v1(text, text) from public, anon, authenticated;

-- 4. the eligibility to be given a first entry page ---------------------------------------------------------------------------------------
create or replace function security.entry_matrix_attach_allowed_v1(p_provider uuid) returns boolean language sql stable security definer set search_path = '' as $function$
  -- security.entry_matrix_enabled_v1 without its "an entry page is already recorded" clause: that clause made the first page of a provider impossible to attach
  select security.pipeline_num_v1('entry.matrix_enabled', 0) >= 1
     and exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id
                  where p.id = p_provider
                    and coalesce(security.toolset_setting('pipeline', 'entry.countries'), '["AU","NZ"]'::jsonb) ? k.iso_alpha2::text)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)
     and (case when security.aer_schedule_active_v1()
               then exists (select 1 from security.aer_eligible_v1() e where e.provider_id = p_provider and (security.aer_schedule_country_v1(e.country)->>'on')::boolean)
               else jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb)) = 0
                    or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text end)
$function$;
comment on function security.entry_matrix_attach_allowed_v1(uuid) is 'CF-247 (7 Nov 2026): whether a provider may be given an entry-requirements page: the rule of security.entry_matrix_enabled_v1 without the clause that an entry page is already recorded. Used by security.entry_matrix_attach_v1 and security.entry_source_stored_find_v1.';
revoke all on function security.entry_matrix_attach_allowed_v1(uuid) from public, anon, authenticated;

-- md5-guarded edit of security.entry_matrix_attach_v1: the attach uses that rule
do $edit$
declare v_def text := pg_get_functiondef('security.entry_matrix_attach_v1()'::regprocedure); v_old text := 'security.entry_matrix_enabled_v1(s.provider_id)'; v_c int;
begin
  if v_def like '%entry_matrix_attach_allowed_v1%' then raise notice 'security.entry_matrix_attach_v1: already applied'; return; end if;
  if md5(v_def) <> 'b34e95379b61ef98a65837686825857f' then raise exception 'security.entry_matrix_attach_v1 differs from the definition this change edits (md5 %)', md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'security.entry_matrix_attach_v1: the edit must apply exactly once (found %)', v_c; end if;
  execute replace(v_def, v_old, 'security.entry_matrix_attach_allowed_v1(s.provider_id)');
  raise notice 'security.entry_matrix_attach_v1: applied';
end $edit$;

-- 5. the stored-link step -------------------------------------------------------------------------------------------------------------------
create or replace function security.entry_source_stored_find_v1(p_limit integer default null, p_apply boolean default true) returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.aer_source_stored_find', 200)::int);
  v_max int := security.pipeline_num_v1('entry.attach_per_provider', 3)::int;
  v_min numeric := greatest(security.pipeline_num_v1('central.min_suggest_score', 4), 3);  -- fixed: the worker never suggests a page that scores under 3
  v_days int := security.pipeline_num_v1('aer.source_stored_find_recheck_days', 14)::int;
  r record; v_c jsonb; v_links int; v_cands int; v_weak int; v_best_url text; v_best_score numeric; v_shared boolean; v_pick jsonb; v_att int; v_out text;
  v_tally jsonb := '{}'::jsonb; v_looked int := 0; v_sources int := 0; v_preview jsonb := '[]'::jsonb;
begin
  if p_apply and security.pipeline_num_v1('aer.source_stored_find_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return jsonb_build_object('on', false, 'reason', 'the entry matrix reader is off (entry.matrix_enabled)'); end if;
  for r in
    select p.id provider_id, security.site_host_v1(p.website) ph
      from security.aer_eligible_v1() e join catalogue.providers p on p.id = e.provider_id
     where security.entry_matrix_attach_allowed_v1(p.id)
       and not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = p.id)
       and coalesce(btrim(p.website), '') ~* '^https?://' and not security.third_party_host_v1(p.website)
       and not exists (select 1 from pipeline.aer_source_stored_find f where f.provider_id = p.id and (f.outcome = 'attached' or f.checked_at > now() - make_interval(days => v_days)))
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc, p.id
     limit v_limit
  loop
    v_looked := v_looked + 1;
    -- every stored link of the provider, scored by the worker's rules; own website host (or a sub-domain of it) only; one row an address (www and a closing slash ignored)
    select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) into v_c from (
      select distinct on (kk.k) u.url, u.title, u.src, u.pages, security.entry_source_score_v1(u.url, u.title) score,
             coalesce(security.site_host_v1(u.url) = r.ph or right(security.site_host_v1(u.url), length(r.ph) + 1) = '.' || r.ph, false) ownhost
        from (select l.url, l.title, 'coverage_provider_urls' src, 1 pages from pipeline.coverage_provider_urls l where l.provider_id = r.provider_id
              union all select l.url, l.anchor_text, 'provider_discovery_links', coalesce(l.pages, 1) from pipeline.provider_discovery_links l where l.provider_id = r.provider_id) u,
             lateral (select lower(regexp_replace(regexp_replace(u.url, '^https?://(www\.)?', ''), '/+$', '')) k) kk
       order by kk.k, security.entry_source_score_v1(u.url, u.title) desc nulls last, u.pages desc, length(u.url), u.url) q;
    v_links := jsonb_array_length(v_c);
    select count(*) filter (where x.score >= v_min and x.ownhost), count(*) filter (where x.score is not null and x.ownhost and x.score < v_min)
      into v_cands, v_weak from jsonb_to_recordset(v_c) as x(url text, title text, src text, pages int, score numeric, ownhost boolean);
    select x.url, x.score into v_best_url, v_best_score from jsonb_to_recordset(v_c) as x(url text, title text, src text, pages int, score numeric, ownhost boolean)
     where x.score is not null and x.ownhost order by x.score desc, length(x.url), x.url limit 1;
    v_shared := exists (select 1 from catalogue.providers o where o.id <> r.provider_id and o.lifecycle_status = 'active' and security.site_host_v1(o.website) = r.ph);
    v_att := 0; v_pick := '[]'::jsonb;
    v_out := case when v_links = 0 then 'no_link_material' when v_cands = 0 then 'no_entry_candidate' when v_shared then 'host_shared' else 'attached' end;
    if v_out = 'attached' then
      select coalesce(jsonb_agg(jsonb_build_object('url', t.url, 'title', t.title, 'score', t.score, 'source', t.src, 'pages', t.pages, 'rank', t.rn) order by t.rn), '[]'::jsonb) into v_pick
        from (select x.*, row_number() over (order by x.score desc, length(x.url), x.url) rn from jsonb_to_recordset(v_c) as x(url text, title text, src text, pages int, score numeric, ownhost boolean)
               where x.score >= v_min and x.ownhost) t where t.rn <= v_max;
      if p_apply then
        insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
        select r.provider_id, e->>'url', left(e->>'title', 200), (e->>'rank')::int, 'search' from jsonb_array_elements(v_pick) e
        on conflict (provider_id, url) do nothing;
        get diagnostics v_att = row_count;
        v_sources := v_sources + v_att;
      end if;
    end if;
    v_tally := jsonb_set(v_tally, array[v_out], to_jsonb(coalesce((v_tally->>v_out)::int, 0) + 1));
    if not p_apply and v_out = 'attached' then v_preview := v_preview || jsonb_build_object('provider_id', r.provider_id, 'pick', v_pick); end if;
    if p_apply then
      insert into pipeline.aer_source_stored_find(provider_id, checked_at, outcome, links, candidates, best_url, best_score, attached, detail)
      values (r.provider_id, now(), v_out, v_links, v_cands, v_best_url, v_best_score, v_att,
              jsonb_build_object('below_threshold', v_weak, 'host_shared', v_shared, 'min_score', v_min, 'picked', v_pick))
      on conflict (provider_id) do update set checked_at = excluded.checked_at, outcome = excluded.outcome, links = excluded.links, candidates = excluded.candidates,
        best_url = excluded.best_url, best_score = excluded.best_score, attached = excluded.attached, detail = excluded.detail;
    end if;
  end loop;
  return jsonb_build_object('on', true, 'apply', p_apply, 'looked_at', v_looked, 'sources_attached', v_sources, 'outcomes', v_tally) || case when p_apply then '{}'::jsonb else jsonb_build_object('would_attach', v_preview) end;
end $function$;
comment on function security.entry_source_stored_find_v1(integer, boolean) is 'CF-247 (7 Nov 2026): job aer-source-stored-find. For AER-eligible providers with no entry-requirements page, scores the links the platform already stored (provider_discovery_links, coverage_provider_urls) with the worker''s entry_requirements page rules, keeps those on the provider''s own website host (not a host another active provider also uses), and attaches the best (entry.attach_per_provider) as found_via search for the existing reader. Records every provider looked at, with the reason (pipeline.aer_source_stored_find). Fetches nothing, spends nothing. apply false measures without writing. Off until aer.source_stored_find_on is 1.';
revoke all on function security.entry_source_stored_find_v1(integer, boolean) from public, anon, authenticated;

-- 6. the job (G1): catalogued, created PAUSED -----------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-source-stored-find', 'Course pages', 39, 'Entry pages from stored links',
  'Hourly at :37 when switched on (setting Entry pages from stored links: on): for AER-eligible providers that have no entry-requirements page, scores the links the platform has already stored (links seen on stored pages and the provider''s own site-map addresses) with the same page rules as Find central pages, and attaches the best page on the provider''s own website for the entry matrix reader. Fetches nothing and spends no Firecrawl credit; the reader fetches the page directly and every first read waits for a person in Layer 4. A provider with no usable link is recorded with the reason and looked at again after the days in Entry pages from stored links: look again after.',
  6, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'aer-source-stored-find') then
    perform cron.schedule('aer-source-stored-find', '37 * * * *', 'select security.entry_source_stored_find_v1(security.pipeline_num_v1(''batch.aer_source_stored_find'', 200)::int)');
    perform cron.alter_job((select jobid from cron.job where jobname = 'aer-source-stored-find'), active := false);
  end if;
end $j$;

-- 7. housekeeping: the register ---------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'aer-source-stored-find', 'Layer 2', 'Entry requirements', 'First entry-requirements page of an AER-eligible provider from links already stored (paused until activated)', 'active', '{}', '20261107150000'),
 ('table', 'pipeline.aer_source_stored_find', 'Layer 2', 'Entry requirements', 'What the stored-link step found for each provider without an entry page, and why not', 'active', '{}', '20261107150000'),
 ('function', 'security.entry_source_stored_find_v1', 'Layer 2', 'Entry requirements', 'Job aer-source-stored-find: attaches the best stored entry-requirements link on the provider''s own host', 'active', '{}', '20261107150000'),
 ('function', 'security.entry_source_score_v1', 'Layer 2', 'Entry requirements', 'The worker''s entry_requirements page rules as a pure function', 'active', '{}', '20261107150000'),
 ('function', 'security.entry_matrix_attach_allowed_v1', 'Layer 2', 'Entry requirements', 'Eligibility to be given a first entry page (entry_matrix_enabled_v1 without the page-already-recorded clause)', 'active', '{}', '20261107150000')
on conflict do nothing;
update pipeline.component_register set note = coalesce(note || '. ', '') || '7 Nov 2026 (20261107150000): attaches with security.entry_matrix_attach_allowed_v1, so a provider with no entry page can be given its first', updated_at = now()
 where kind = 'function' and name = 'security.entry_matrix_attach_v1' and coalesce(note, '') not like '%20261107150000%';

-- 8. post-check: ships off and paused; the attach rule is the new one; the enabled rule is untouched ----------------------------------------------------
do $post$ begin
  if security.pipeline_num_v1('aer.source_stored_find_on', 99) <> 0 then raise exception 'post-check: the step must ship off'; end if;
  if exists (select 1 from cron.job where jobname = 'aer-source-stored-find' and active) then raise exception 'post-check: the job must ship paused'; end if;
  if pg_get_functiondef('security.entry_matrix_attach_v1()'::regprocedure) not like '%entry_matrix_attach_allowed_v1(s.provider_id)%' then raise exception 'post-check: the attach does not use the new rule'; end if;
  if pg_get_functiondef('security.entry_matrix_enabled_v1(uuid)'::regprocedure) not like '%pipeline.entry_matrix_sources s where s.provider_id = p_provider%' then raise exception 'post-check: entry_matrix_enabled_v1 must be untouched'; end if;
end $post$;
