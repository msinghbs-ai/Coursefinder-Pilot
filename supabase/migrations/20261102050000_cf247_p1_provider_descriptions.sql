-- CF-247 missing-field enrichment, Priority 1: university (provider) descriptions.
-- Authority: Platform Admin 2 Nov 2026 10:28 (admin docs/platform/nz-enrichment-brief/2026-11-02-missing-field-enrichment-mandate.md §2, §5A,
--   §6-§8), with the Wix developer hand-off of 2 Nov 2026 (45 Australian universities assessed, 0 descriptions, 45 missing).
-- What exists and is reused:
--   * catalogue.providers.description is already projected by the consumer API (public.website_v2_provider: 'description'). Filling it is a
--     value change, not a shape change: no consumer API function, table or column is altered (G3).
--   * The governed provider reader pattern of Track C (entry matrices): the reader's own read list, stored copy first, the worker reads a page
--     directly (robots.txt respected) and uses Firecrawl only when the site refuses (existing Firecrawl budget, svc_fc_spend), copies are
--     registered as evidence (public.svc_coursefacts_register_evidence under the provider's coverage-sweep source), the AI spend line and
--     daily guard (security.ai_spend_today_v1 / ai_use_allowed_v1), the fire guard and pipeline.svc_pilot_submit_nonce.
--   * The AI path: worker coverage-sweep with the pinned Enrich fields model (pipeline.central_ai_settings, the qualified model the Enrich
--     fields reader already uses; never a router), its answer limits (reading.answer_tokens.*) and cost recording.
--   * Layer 4: pipeline.layer4_review_items with a new field code provider_description (entity provider). Checked against the Platform
--     Admin direction of 2 Nov 2026 11:10 ("Do not introduce a new Layer 4 review type if an existing kind safely supports the same evidence
--     and decision rules"); no existing kind does:
--       - the default course scalar path (layer4_course_scalar_resolve_impl) refuses any entity but a course;
--       - official_course_url / Inbox kind course_link, course_english, provider_current_tuition(_validation): course entities, writing
--         course links, English rows or fees; their choices (keep / use / enter an address) would let an unquoted value be entered;
--       - no_page_first_run / conjoint_rule_first_run: provider entities, but approval records course samples as having no page and they are
--         under the SP-2a auto-admission job (layer4-auto-admit), which descriptions must never be;
--       - entry_matrix_first_run / entry_matrix_change: provider entities with quoted evidence, but approval admits rows into
--         catalogue.provider_entry_matrix, the AER rules apply (Platform Admin only, Approve-except shape, skipped by bulk decide), and a
--         changed matrix may be admitted without a person (entry.matrix_first_run_review 0);
--       - Layer 4 › Attributes (pipeline.provider_policy_proposals, central pages): not a Layer 4 item; its kinds are english_policy and
--         intake_calendar only (table check), it needs a provider-facts source (kinds fee, English, calendar only) and approval applies rules to
--         courses; using it means changing two table checks and the policy apply functions;
--       - scope_resolution, held scholarships, provider departures and counsellor reports: other entities or decisions.
--     The new kind is isolated (its own apply function and Inbox entry; sections 6, 9a and 9c) and needs the Platform Admin's approval
--     before release. The closest governed pattern, the entry matrix first run, is followed: a provider-entity item, its own apply function,
--     and a status trigger for the outcomes that do not admit. A correction is made in the provider record (a person's value, locked by hand,
--     which this reader never overwrites); the Inbox offers approve as read and reject.
--     Auto-admission: no approved policy covers descriptions (the only auto-admit policy, SP-2a, covers no-page and conjoint first runs);
--     every description waits for a person.
-- Lifecycle (mandate §7): Discover (worker: stored About / Overview copy, else the home page's About link on the provider's own hosts) ->
--   Verify identity (the page host is one of the provider's own hosts: its website, binding.provider_host_aliases, approved extra domains;
--   another active provider's host is refused) -> Reuse / acquire -> Extract (pinned model; every sentence with the page's exact words) ->
--   Validate (security.provider_description_validate_v1: host, about page, sentence count, every quote on the page, every sentence supported
--   by its quote, no superlatives or ranking / facility / outcome / accreditation claims unless quoted, length, source age, duplicate of
--   another provider's description, same as the description held) -> Propose (Layer 4, at most pdesc.pending_max waiting) -> Review / admit
--   (a person; security.layer4_provider_description_apply_impl writes catalogue.providers.description only on approval, never over a value
--   locked by hand or changed since the proposal) -> Verify publication (the Website API v2 payload is read back after admission).
-- Acquisition is off (pdesc.acquire_direct 0, pdesc.acquire_firecrawl 0; decision pack 2 Nov 2026 10:56 Decision 7): only stored About copies
--   are read until the Platform Admin approves the pilot cost. The integrator's reconciliation (2 Nov 2026) found no stored About page for any
--   provider, so the page type about_page is added to the existing central page finder (worker central.ts, whole-site map only, no extra
--   credits); its suggestions are this reader's first candidates, then the About link of the home page.
-- Layer 4 kind provider_description is a NEW kind (sections 6 and 9a/9c, isolated): it needs the Platform Admin's approval before release.
-- Job provider-description-read (catalogued; cron INACTIVE and pdesc.enabled 0): frequency, batch, countries, provider types, provider list,
--   tries, retry wait, dead letter, pause and resume are settings (G2). Activation is a separate, deliberate step; a passing test switches
--   nothing on.
-- Metrics (§8): public.admin_provider_descriptions('metrics') for Coverage › Every field (eligible, present, missing, proposed, held,
--   admitted, dead letter, stored pages, pages acquired, AI reads, cost, cost per admitted description, rejections by reason, Layer 4 queue,
--   last run, remaining backlog), by country and provider.
-- Replaces: security.layer4_review_decide_impl, security.layer4_inbox_kinds_v1, security.layer4_inbox_items_v1, public.admin_layer4_inbox, security.ai_spend_today_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No consumer API function, table or column is altered (G3). Nothing is switched on.

-- ---------------------------------------------------------------- 1 the reader's own read list
create table if not exists pipeline.provider_description_reads (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  state text not null default 'queued' check (state in ('queued', 'reading', 'proposed', 'held', 'dead_letter', 'admitted', 'rejected', 'verified', 'superseded')),
  tries int not null default 0,
  next_try_at timestamptz not null default now(),
  leased_until timestamptz,
  source_url text,
  read_via text check (read_via in ('stored', 'direct', 'firecrawl')),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  content_hash text,
  source_captured_at timestamptz,
  model text,
  prompt_version text,
  worker text,
  cost_usd numeric not null default 0,
  firecrawl_reads int not null default 0,
  proposal jsonb,
  checks jsonb,
  rule text,
  reason text,
  review_item_id uuid references pipeline.layer4_review_items(id),
  last_verified_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.provider_description_reads is 'CF-247 P1 provider descriptions (Platform Admin 2 Nov 2026 10:28): one read of one provider''s official About / Overview page for its description, with source URL, evidence, capture time, the pinned model, prompt version, cost, the validation checks, the Layer 4 item and the verification and publication dates. One open read (queued, reading, proposed) a provider. catalogue.providers.description is written only when a person approves the Layer 4 item.';
create unique index if not exists provider_description_reads_open_uq on pipeline.provider_description_reads (provider_id) where state in ('queued', 'reading', 'proposed');
create index if not exists provider_description_reads_state_idx on pipeline.provider_description_reads (state, next_try_at);
create index if not exists provider_description_reads_provider_idx on pipeline.provider_description_reads (provider_id, created_at desc);
create index if not exists provider_description_reads_review_idx on pipeline.provider_description_reads (review_item_id);
create index if not exists provider_description_reads_evidence_idx on pipeline.provider_description_reads (evidence_id);
alter table pipeline.provider_description_reads enable row level security;

-- ---------------------------------------------------------------- 2 settings (G2: every tunable; the reader is off)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pdesc.enabled', 'Provider descriptions: reader on',
  '1: job provider-description-read queues providers without a description and reads their official About page (stored copy first). 0: paused; nothing is queued, read or proposed, and the reads waiting resume where they stopped when it is set to 1 again. Off until the Platform Admin activates it.',
  'number', '0'::jsonb, 0, 1, 'on/off', 960, 'Provider descriptions', 'security.provider_description_fire_v1, public.svc_provider_description_next', 'CF-247 P1 provider descriptions (Platform Admin 2 Nov 2026 10:28): off by default'),
 ('pipeline', 'pdesc.acquire_direct', 'Provider descriptions: read pages not held',
  '1: when no stored About copy is held, the worker reads the provider''s home page and its About page directly (robots.txt respected; no Firecrawl credits). 0: only stored copies are read. Off until the Platform Admin approves the supervised pilot.',
  'number', '0'::jsonb, 0, 1, 'on/off', 959, 'Provider descriptions', 'public.svc_provider_description_next, worker provider_description', 'CF-247 P1 provider descriptions; decision pack 2 Nov 2026 10:56 Decision 7: acquisition off until the pilot cost is approved'),
 ('pipeline', 'pdesc.acquire_firecrawl', 'Provider descriptions: Firecrawl when a site refuses',
  '1: a page the site refuses to a direct read may be read through Firecrawl, within the existing Firecrawl budget (svc_fc_spend). 0: never. Off until the Platform Admin approves the pilot cost.',
  'number', '0'::jsonb, 0, 1, 'on/off', 958, 'Provider descriptions', 'public.svc_provider_description_next, worker provider_description', 'CF-247 P1 provider descriptions; decision pack 2 Nov 2026 10:56 Decision 7: no paid Firecrawl without the pilot''s cost approval'),
 ('pipeline', 'pdesc.ai_usd_max', 'Provider descriptions: AI spend ceiling (all reads)',
  'Total AI spend of every description read so far (pipeline.provider_description_reads.cost_usd). At or above it no read starts: the hard ceiling of a pilot approved by the Platform Admin. Raise it with a reason to continue.',
  'number', '1'::jsonb, 0, 100, 'US$', 957, 'Provider descriptions', 'public.svc_provider_description_next, security.provider_description_fire_v1', 'CF-247 P1 provider descriptions: cost-capped pilot (Platform Admin direction 2 Nov 2026 11:10)'),
 ('pipeline', 'pdesc.firecrawl_reads_max', 'Provider descriptions: Firecrawl reads ceiling (all reads)',
  'Total Firecrawl page reads the description reader may make (home and About pages a site refused to a direct read). 0: none. The hard Firecrawl ceiling of a pilot approved by the Platform Admin; each read also passes the existing Firecrawl budget.',
  'number', '0'::jsonb, 0, 2000, 'reads', 956, 'Provider descriptions', 'public.svc_provider_description_next, worker provider_description', 'CF-247 P1 provider descriptions: cost-capped pilot (Platform Admin direction 2 Nov 2026 11:10)'),
 ('pipeline', 'pdesc.every_minutes', 'Provider descriptions: run every',
  'The job wakes every 10 minutes and sends the worker only when this long has passed since its last call.', 'number', '60'::jsonb, 10, 1440, 'minutes', 961, 'Provider descriptions', 'security.provider_description_fire_v1', 'CF-247 P1 provider descriptions: frequency is a setting'),
 ('pipeline', 'batch.provider_description', 'Provider descriptions: providers a run',
  'Providers one worker call reads (each is one page and one AI call).', 'number', '3'::jsonb, 1, 10, 'providers', 962, 'Provider descriptions', 'job provider-description-read, public.svc_provider_description_next', 'CF-247 P1 provider descriptions: bounded batches'),
 ('pipeline', 'pdesc.queue_per_run', 'Provider descriptions: providers queued a run',
  'At most this many providers without a description (or with a stale one) are added to the read list each run.', 'number', '10'::jsonb, 1, 100, 'providers', 963, 'Provider descriptions', 'security.provider_description_enqueue_v1', 'CF-247 P1 provider descriptions: no uncontrolled queue growth'),
 ('pipeline', 'pdesc.countries', 'Provider descriptions: countries',
  'Countries whose providers are read (ISO codes).', 'list', '["AU"]'::jsonb, null, null, 'countries', 964, 'Provider descriptions', 'security.provider_description_scope_v1', 'CF-247 P1 provider descriptions: initial priority the 45 Australian universities'),
 ('pipeline', 'pdesc.provider_types', 'Provider descriptions: institution types',
  'Institution types (ref.provider_types codes) whose providers are read.', 'list', '["university"]'::jsonb, null, null, 'types', 965, 'Provider descriptions', 'security.provider_description_scope_v1', 'CF-247 P1 provider descriptions: universities first'),
 ('pipeline', 'pdesc.provider_keys', 'Provider descriptions: only these providers',
  'Provider stable keys (for example provider:cricos:00008c). Empty: every provider of the countries and types above. Used for a supervised pilot.', 'list', '[]'::jsonb, null, null, 'providers', 966, 'Provider descriptions', 'security.provider_description_scope_v1', 'CF-247 P1 provider descriptions: per-provider scope'),
 ('pipeline', 'pdesc.tries', 'Provider descriptions: tries a read',
  'A read that fails (page not reached, AI error, cut answer) is tried again up to this many times; then it goes to the dead letter list on Coverage, where a PIM Admin can retry it.', 'number', '3'::jsonb, 1, 10, 'tries', 967, 'Provider descriptions', 'public.svc_provider_description_next, public.svc_provider_description_record', 'CF-247 P1 provider descriptions: bounded retries, dead letter'),
 ('pipeline', 'pdesc.retry_minutes', 'Provider descriptions: wait before a retry',
  'A failed read waits this long before it is tried again.', 'number', '360'::jsonb, 30, 10080, 'minutes', 968, 'Provider descriptions', 'public.svc_provider_description_record', 'CF-247 P1 provider descriptions: retries'),
 ('pipeline', 'pdesc.recheck_days', 'Provider descriptions: check again after',
  'A provider whose read was held (no About page, not supported) or whose admitted description was last verified this long ago is queued again.', 'number', '180'::jsonb, 30, 730, 'days', 969, 'Provider descriptions', 'security.provider_description_enqueue_v1', 'CF-247 P1 provider descriptions: stale and outdated descriptions'),
 ('pipeline', 'pdesc.pending_max', 'Provider descriptions: waiting in Layer 4 at most',
  'No new read starts while this many description proposals wait for a person in Layer 4.', 'number', '10'::jsonb, 1, 100, 'items', 970, 'Provider descriptions', 'security.provider_description_fire_v1, public.svc_provider_description_next', 'CF-247 P1 provider descriptions: no uncontrolled Layer 4 queue growth'),
 ('pipeline', 'pdesc.page_chars', 'Provider descriptions: page text read',
  'Characters of the About page''s main text the model reads.', 'number', '16000'::jsonb, 2000, 60000, 'characters', 971, 'Provider descriptions', 'public.svc_provider_description_next, worker provider_description', 'CF-247 P1 provider descriptions'),
 ('pipeline', 'pdesc.min_quote_chars', 'Provider descriptions: shortest quote',
  'A quote must have at least this many letters and digits and be found on the page.', 'number', '20'::jsonb, 8, 200, 'characters', 972, 'Provider descriptions', 'public.svc_provider_description_next, worker provider_description', 'CF-247 P1 provider descriptions: every sentence supported by a quoted span'),
 ('pipeline', 'pdesc.min_sentences', 'Provider descriptions: fewest sentences', 'A description has at least this many sentences.', 'number', '2'::jsonb, 1, 5, 'sentences', 973, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: suitable length'),
 ('pipeline', 'pdesc.max_sentences', 'Provider descriptions: most sentences', 'A description has at most this many sentences.', 'number', '5'::jsonb, 2, 12, 'sentences', 974, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: suitable length'),
 ('pipeline', 'pdesc.min_chars', 'Provider descriptions: shortest description', 'A description shorter than this is held.', 'number', '150'::jsonb, 50, 1000, 'characters', 975, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: suitable length'),
 ('pipeline', 'pdesc.max_chars', 'Provider descriptions: longest description', 'A description longer than this is held.', 'number', '900'::jsonb, 200, 4000, 'characters', 976, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: suitable length'),
 ('pipeline', 'pdesc.support_min_share', 'Provider descriptions: sentence supported from',
  'Share of a sentence''s content words (four letters or more) that must appear in its quote (the first five letters, so plurals and tenses count). Below it the sentence is not supported and the description is held.', 'number', '0.6'::jsonb, 0.3, 1, 'share', 977, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: every sentence supported by a quoted span'),
 ('pipeline', 'pdesc.duplicate_share', 'Provider descriptions: duplicate from',
  'Word overlap (Jaccard) at or above which a description is the same as another provider''s (held as a duplicate) or as the one already held (verified, not proposed again).', 'number', '0.8'::jsonb, 0.5, 1, 'share', 978, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: duplicate detection'),
 ('pipeline', 'pdesc.source_max_age_days', 'Provider descriptions: stored copy at most',
  'A stored About page older than this is not reused (the page is read again), and a description from an older copy is held as outdated.', 'number', '365'::jsonb, 30, 1095, 'days', 979, 'Provider descriptions', 'security.provider_description_stored_v1, security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: outdated detection'),
 ('pipeline', 'pdesc.about_patterns', 'Provider descriptions: About page names',
  'Address path parts or link texts that name a provider''s About, Overview or institutional profile page.', 'list',
  '["about", "about-us", "about-the-university", "about-uni", "overview", "our-university", "the-university", "who-we-are", "university-profile", "institutional-profile", "our-story", "at-a-glance", "facts-and-figures", "discover"]'::jsonb,
  null, null, 'names', 980, 'Provider descriptions', 'security.provider_description_stored_v1, worker provider_description', 'CF-247 P1 provider descriptions: discover the About, Overview or institutional profile page'),
 ('pipeline', 'pdesc.superlatives', 'Provider descriptions: marketing words',
  'Words and phrases that may appear in a description only inside the sentence''s quote.', 'list',
  '["best", "leading", "world-class", "world class", "world-leading", "top", "premier", "renowned", "prestigious", "excellent", "excellence", "outstanding", "unrivalled", "unparalleled", "finest", "elite", "cutting-edge", "award-winning", "number one", "#1", "first-class", "exceptional", "innovative", "vibrant"]'::jsonb,
  null, null, 'words', 981, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: no marketing superlatives unless quoted'),
 ('pipeline', 'pdesc.claim_words', 'Provider descriptions: claim words',
  'Words that make a ranking, facility, outcome or accreditation claim; they may appear in a description only inside the sentence''s quote.', 'list',
  '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "students", "staff", "alumni", "award", "awards"]'::jsonb,
  null, null, 'words', 982, 'Provider descriptions', 'security.provider_description_validate_v1', 'CF-247 P1 provider descriptions: no rankings, facilities, outcomes or accreditation claims unless quoted'),
 ('pipeline', 'reading.answer_tokens.provider_description', 'AI answer length: provider description',
  'The longest answer the provider description reader may give for one About page. A cut answer fails the read, named.', 'number',
  to_jsonb(1500), 500, 8000, 'tokens', 940, 'AI answer limits', 'worker coverage-sweep provider_description', 'CF-247 P1 provider descriptions'),
 ('openrouter', 'guard_provider_description', 'Daily guard: provider descriptions with AI',
  'The provider description reader stops for the day when its AI spend reaches this (UTC day), inside the overall credit floor.', 'number', '1'::jsonb, 0, 100, 'US$ a day', 50, 'Daily guards', 'security.ai_use_allowed_v1(''provider_description'')', 'CF-247 P1 provider descriptions: existing AI spending limits')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- 3 scope, hosts, stored copy
create or replace function security.provider_description_scope_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path to '' as $function$
  select exists (
    select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
     where p.id = p_provider and p.lifecycle_status = 'active'
       and coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb) ? k.iso_alpha2::text
       and coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb) ? coalesce(t.code, '')
       and (jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb)) = 0
            or coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb) ? lower(p.stable_key)
            or coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb) ? p.stable_key))
$function$;
comment on function security.provider_description_scope_v1(uuid) is 'CF-247 P1 provider descriptions: the provider is in the reader''s scope (active; country in pdesc.countries; type in pdesc.provider_types; in pdesc.provider_keys when that list is not empty).';

-- the provider's own hosts: its website, its approved other websites (binding.provider_host_aliases) and its approved extra domains
create or replace function security.provider_hosts_v1(p_provider uuid) returns text[]
language sql stable security definer set search_path to '' as $function$
  select coalesce(array_agg(distinct h) filter (where h <> ''), '{}'::text[]) from (
    select regexp_replace(lower(coalesce(substring(p.website from '^(?:https?://)?([^/?#:]+)'), '')), '^www\.', '') h
      from catalogue.providers p where p.id = p_provider
    union all
    select regexp_replace(x, '^www\.', '')
      from catalogue.providers p, jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'binding.provider_host_aliases'), '[]'::jsonb)) e,
           regexp_split_to_table(lower(btrim(substr(e, strpos(e, '=') + 1))), '\s+') x
     where p.id = p_provider and lower(split_part(e, '=', 1)) = lower(p.stable_key)
    union all
    select regexp_replace(lower(d.domain), '^(https?://)?(www\.)?', '') from pipeline.provider_extra_domains d where d.provider_id = p_provider and d.state = 'approved') z
$function$;
comment on function security.provider_hosts_v1(uuid) is 'CF-247 P1 provider descriptions: the provider''s own hosts (website, binding.provider_host_aliases, approved pipeline.provider_extra_domains), the same sources as security.course_page_check_v1.';

-- own (a page on one of the provider's hosts), other_provider (another active provider's website), unknown_host, no_url
create or replace function security.provider_page_host_v1(p_provider uuid, p_url text) returns text
language sql stable security definer set search_path to '' as $function$
  with u as (select regexp_replace(lower(coalesce(substring(p_url from '^https?://([^/?#:]+)'), '')), '^www\.', '') host)
  select case when u.host = '' then 'no_url'
              when exists (select 1 from unnest(security.provider_hosts_v1(p_provider)) h where h <> '' and (u.host = h or u.host like '%.' || h)) then 'own'
              when exists (select 1 from catalogue.providers o, lateral (select regexp_replace(lower(coalesce(substring(o.website from '^(?:https?://)?([^/?#:]+)'), '')), '^www\.', '') b) ob
                            where o.id <> p_provider and o.lifecycle_status = 'active' and ob.b <> '' and (u.host = ob.b or u.host like '%.' || ob.b)) then 'other_provider'
              else 'unknown_host' end
    from u
$function$;
comment on function security.provider_page_host_v1(uuid, text) is 'CF-247 P1 provider descriptions: whose website a page is on (own, other_provider, unknown_host, no_url). Only an own page is read for a description.';

-- the newest stored About / Overview copy of the provider: on its own host, an About page name in the address, younger than pdesc.source_max_age_days
create or replace function security.provider_description_stored_v1(p_provider uuid) returns uuid
language sql stable security definer set search_path to '' as $function$
  select a.id
    from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id = s.id
   where s.provider_id = p_provider and a.storage_path is not null and a.source_url ~* '^https?://'
     and coalesce(a.mime_type, 'text/html') ~* 'html|markdown|text'
     and coalesce(a.captured_at, a.created_at) > now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int)
     and security.provider_page_host_v1(p_provider, a.source_url) = 'own'
     and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) pat,
                      regexp_split_to_table(lower(coalesce(substring(a.source_url from '^https?://[^/]+(/[^?#]*)'), '')), '/') seg
                  where seg <> '' and seg = lower(pat))
   order by coalesce(a.captured_at, a.created_at) desc, a.id
   limit 1
$function$;
comment on function security.provider_description_stored_v1(uuid) is 'CF-247 P1 provider descriptions: stored copy first. The newest stored copy of the provider''s own About / Overview page (an About page name, pdesc.about_patterns, as a whole part of the address path), younger than pdesc.source_max_age_days.';

-- ---------------------------------------------------------------- 4 validation (every rule is a setting; nothing written)
-- distinct words of three letters or more
create or replace function security.pdesc_words_v1(p text) returns text[]
language sql immutable set search_path to '' as $function$
  select coalesce(array_agg(distinct w), '{}'::text[]) from regexp_split_to_table(lower(coalesce(p, '')), '[^a-z0-9]+') w where length(w) >= 3
$function$;

-- word overlap (Jaccard) of two texts
create or replace function security.pdesc_similarity_v1(a text, b text) returns numeric
language sql immutable set search_path to '' as $function$
  with x as (select security.pdesc_words_v1(a) wa, security.pdesc_words_v1(b) wb)
  select case when cardinality(x.wa) = 0 or cardinality(x.wb) = 0 then 0
              else round((select count(*) from unnest(x.wa) w where w = any (x.wb))::numeric
                         / (select count(*) from (select unnest(x.wa) union select unnest(x.wb)) u), 4) end
    from x
$function$;

-- a word or phrase of the list is in the text (whole words; '#' kept)
create or replace function security.pdesc_has_term_v1(p_text text, p_term text) returns boolean
language sql immutable set search_path to '' as $function$
  select nullif(btrim(regexp_replace(lower(coalesce(p_term, '')), '[^a-z0-9#%]+', ' ', 'g')), '') is not null
     and position(' ' || btrim(regexp_replace(lower(coalesce(p_term, '')), '[^a-z0-9#%]+', ' ', 'g')) || ' '
                  in ' ' || regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9#%]+', ' ', 'g') || ' ') > 0
$function$;

-- share of a sentence's content words (four letters or more) whose first five letters are in the quote
create or replace function security.pdesc_support_v1(p_sentence text, p_quote text) returns numeric
language sql immutable set search_path to '' as $function$
  with s as (select distinct left(w, 5) w from regexp_split_to_table(lower(coalesce(p_sentence, '')), '[^a-z0-9]+') w
              where length(w) >= 4 and w not in ('that', 'this', 'with', 'from', 'into', 'their', 'there', 'which', 'where', 'what', 'have', 'also', 'such', 'they', 'them', 'than', 'more', 'most', 'other', 'offers', 'offer', 'provides', 'provide')),
       q as (select distinct left(w, 5) w from regexp_split_to_table(lower(coalesce(p_quote, '')), '[^a-z0-9]+') w where length(w) >= 4)
  select case when (select count(*) from s) = 0 then 1 else round((select count(*) from s where s.w in (select w from q))::numeric / (select count(*) from s), 4) end
$function$;

-- p_result: {"about_page": bool, "sentences": [{"text", "quote", "on_page"}]} as the worker recorded it.
-- Returns {ok, rule, reason, outcome (propose | verified | held | refused), text, checks}.
create or replace function security.provider_description_validate_v1(p_provider uuid, p_url text, p_captured_at timestamptz, p_result jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_host text := security.provider_page_host_v1(p_provider, p_url);
        v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text;
        v_sup numeric; v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);
        v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_current text; v_other record; v_checks jsonb := '{}'::jsonb;
begin
  v_n := jsonb_array_length(v_s);
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_s) with ordinality e(x, o));
  v_checks := jsonb_build_object('host', v_host, 'sentences', v_n, 'chars', length(coalesce(v_text, '')));
  if v_host <> 'own' then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', 'wrong_host', 'checks', v_checks,
      'reason', case v_host when 'other_provider' then 'the page is on another provider''s website' when 'no_url' then 'no page address' else 'the page is not on the provider''s own website' end);
  end if;
  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;
  if v_n < security.pipeline_num_v1('pdesc.min_sentences', 2) or v_n > security.pipeline_num_v1('pdesc.max_sentences', 5) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'sentence_count', 'checks', v_checks, 'reason', v_n || ' sentence(s), outside the set range');
  end if;
  for s in select x from jsonb_array_elements(v_s) x loop
    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s quote is not on the page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, facility, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
    end if;
    v_sup := security.pdesc_support_v1(t, s->>'quote');
    if v_sup < v_min_sup then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
        'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
    end if;
  end loop;
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or length(v_text) > security.pipeline_num_v1('pdesc.max_chars', 900) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range');
  end if;
  if p_captured_at is not null and p_captured_at < now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'source_outdated', 'checks', v_checks, 'reason', 'the stored page is older than the set age');
  end if;
  -- duplicate: another provider's description held, or another provider's proposal waiting
  select z.provider_id, z.sim into v_other from (
    select p.id provider_id, security.pdesc_similarity_v1(v_text, p.description) sim from catalogue.providers p
     where p.id <> p_provider and nullif(btrim(p.description), '') is not null
    union all
    select r.provider_id, security.pdesc_similarity_v1(v_text, r.proposal->>'description') from pipeline.provider_description_reads r
     where r.provider_id <> p_provider and r.state = 'proposed') z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.provider_id is not null then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'duplicate_other_provider', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.provider_id, 'similarity', v_other.sim),
      'reason', 'the same as another provider''s description (' || v_other.sim || ')');
  end if;
  select nullif(btrim(p.description), '') into v_current from catalogue.providers p where p.id = p_provider;
  if v_current is not null and security.pdesc_similarity_v1(v_text, v_current) >= v_dup then
    return jsonb_build_object('ok', true, 'outcome', 'verified', 'rule', 'same_as_current', 'text', v_text,
      'checks', v_checks || jsonb_build_object('similarity_current', security.pdesc_similarity_v1(v_text, v_current)), 'reason', 'the page still supports the description held');
  end if;
  return jsonb_build_object('ok', true, 'outcome', 'propose', 'rule', case when v_current is null then 'missing' else 'changed' end, 'text', v_text, 'checks', v_checks, 'reason', null);
end $function$;
comment on function security.provider_description_validate_v1(uuid, text, timestamptz, jsonb) is 'CF-247 P1 provider descriptions: the validation of one read (mandate §7): own host, about page, sentence count, every quote on the page, every sentence supported by its quote, no marketing words or claims unless quoted, length, source age, duplicate of another provider, same as the description held. Writes nothing.';

-- ---------------------------------------------------------------- 5 queue, worker next / record
create or replace function security.provider_description_enqueue_v1() returns int
language plpgsql security definer set search_path to '' as $function$
declare v_n int;
begin
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return 0; end if;
  insert into pipeline.provider_description_reads(provider_id)
  select p.id from catalogue.providers p
   where security.provider_description_scope_v1(p.id)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
     and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id
                      and (r.state in ('queued', 'reading', 'proposed', 'dead_letter')
                           or (r.state in ('held', 'rejected') and r.updated_at > now() - make_interval(days => security.pipeline_num_v1('pdesc.recheck_days', 180)::int))
                           or (r.state in ('admitted', 'verified') and coalesce(r.last_verified_at, r.updated_at) > now() - make_interval(days => security.pipeline_num_v1('pdesc.recheck_days', 180)::int))))
     and (nullif(btrim(p.description), '') is null
          or exists (select 1 from pipeline.provider_description_reads r2 where r2.provider_id = p.id and r2.state in ('admitted', 'verified')))
   order by (nullif(btrim(p.description), '') is not null), coalesce(p.display_name, p.canonical_name)
   limit greatest(1, security.pipeline_num_v1('pdesc.queue_per_run', 10)::int)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;
comment on function security.provider_description_enqueue_v1() is 'CF-247 P1 provider descriptions: queues at most pdesc.queue_per_run providers in scope with no description, or whose description this reader admitted and last verified more than pdesc.recheck_days ago. A description entered elsewhere is never re-read; a value locked by hand is never queued; held and rejected reads wait pdesc.recheck_days; dead letters wait for a person.';

create or replace function public.svc_provider_description_next(p_limit integer) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('idle', true, 'reason', 'off', 'items', '[]'::jsonb); end if;
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
  select c.model_identifier into v_model from pipeline.central_ai_settings c where c.id = 1;
  if nullif(btrim(v_model), '') is null then return jsonb_build_object('idle', true, 'reason', 'no_model', 'items', '[]'::jsonb); end if;
  -- the pilot's hard ceilings: total AI spend and total Firecrawl reads of this reader
  select coalesce(sum(r.cost_usd), 0), coalesce(sum(r.firecrawl_reads), 0) into v_spent, v_fc_used from pipeline.provider_description_reads r;
  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  with pick as (select r.id from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
                   and security.provider_description_scope_v1(r.provider_id)
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   and (security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 or security.provider_description_stored_v1(r.provider_id) is not null)
                 order by r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3), (security.pipeline_num_v1('pdesc.pending_max', 10) - v_pending)::int))
                 for update skip locked),
  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1,
                 leased_until = now() + interval '20 minutes',  -- fixed: claim timer (a lost worker call is taken again)
                 updated_at = now()
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
           'website', p.website, 'country', k.iso_alpha2, 'hosts', to_jsonb(security.provider_hosts_v1(u.provider_id)),
           'stored', (select jsonb_build_object('evidence_id', a.id, 'storage_path', a.storage_path, 'url', a.source_url, 'captured_at', coalesce(a.captured_at, a.created_at))
                        from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(u.provider_id)),
           -- About pages the central page finder suggested (page type about_page, central.ts), on the provider's own hosts, best first
           'candidates', (select coalesce(jsonb_agg(z.url order by z.score desc, length(z.url)), '[]'::jsonb) from (
                            select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                              from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                             where cs.provider_id = u.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                               and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
                               and security.provider_page_host_v1(u.provider_id, e->>'url') = 'own') z))), '[]'::jsonb)
    into v
    from upd u join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;
  return jsonb_build_object('model', v_model,
    'acquire_direct', security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1, 'acquire_firecrawl', security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1,
    'firecrawl_left', greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used),
    'page_chars', security.pipeline_num_v1('pdesc.page_chars', 16000)::int,
    'min_quote_chars', security.pipeline_num_v1('pdesc.min_quote_chars', 20)::int,
    'about_patterns', coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb), 'items', v);
end $function$;
revoke all on function public.svc_provider_description_next(integer) from public, anon, authenticated;
grant execute on function public.svc_provider_description_next(integer) to service_role;
comment on function public.svc_provider_description_next(integer) is 'CF-247 P1 provider descriptions: worker lease (mode provider_description). Nothing while pdesc.enabled is 0 or pdesc.pending_max proposals wait in Layer 4. Gives each provider''s own hosts, its stored About copy when held, the pinned Enrich fields model and the limits.';

-- p_results: [{item_id, fetch?: {status, via, url, http, storage_path, sha256, mime}, stored_evidence_id?, answer?: {about_page, sentences: [{text, quote, on_page}]},
--              model, prompt_version, worker, cost, error?, retry?}]
create or replace function public.svc_provider_description_record(p_results jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare x jsonb; r pipeline.provider_description_reads%rowtype; v_ev uuid; v_url text; v_cap timestamptz; v_via text; v_hash text;
        v_chk jsonb; v_item uuid; v_tally jsonb := '{}'::jsonb; v_out text; v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    select * into r from pipeline.provider_description_reads where id = (x->>'item_id')::uuid for update;
    if r.id is null or r.state <> 'reading' then v_tally := v_tally || jsonb_build_object('stale', coalesce((v_tally->>'stale')::int, 0) + 1); continue; end if;
    update pipeline.provider_description_reads set cost_usd = cost_usd + greatest(coalesce((x->>'cost')::numeric, 0), 0),
           firecrawl_reads = firecrawl_reads + greatest(coalesce((x->>'fc_reads')::int, 0), 0),
           model = coalesce(nullif(x->>'model', ''), model), prompt_version = coalesce(nullif(x->>'prompt_version', ''), prompt_version),
           worker = coalesce(left(nullif(x->>'worker', ''), 60), worker), updated_at = now()
     where id = r.id;
    v_ev := null; v_url := null; v_cap := null; v_via := null; v_hash := null;
    -- the page: a stored copy, or a page the worker read and stored now (registered as evidence under the provider's coverage-sweep source)
    if (x->>'stored_evidence_id') is not null then
      select a.id, a.source_url, coalesce(a.captured_at, a.created_at), coalesce(a.content_hash, a.id::text) into v_ev, v_url, v_cap, v_hash
        from pipeline.evidence_artifacts a join pipeline.sources s on s.id = a.source_id
       where a.id = (x->>'stored_evidence_id')::uuid and s.provider_id = r.provider_id;
      v_via := case when v_ev is not null then 'stored' end;
    elsif x->'fetch'->>'status' = 'read' and x->'fetch'->>'storage_path' is not null and x->'fetch'->>'sha256' ~ '^[0-9a-f]{64}$' then
      v_url := x->'fetch'->>'url'; v_hash := x->'fetch'->>'sha256'; v_via := x->'fetch'->>'via'; v_cap := now();
      if security.provider_page_host_v1(r.provider_id, v_url) = 'own' then
        select a.id into v_ev from pipeline.evidence_artifacts a where a.source_id = security.coverage_sweep_source(r.provider_id) and a.content_hash = v_hash and a.source_url = v_url limit 1;
        if v_ev is null then
          v_ev := public.svc_coursefacts_register_evidence(security.coverage_sweep_source(r.provider_id), v_url, x->'fetch'->>'storage_path', v_hash,
                    coalesce(x->'fetch'->>'mime', 'text/html'),
                    jsonb_build_object('layer', 2, 'kind', 'provider_about_page', 'worker', 'coverage-sweep', 'provider_description_read_id', r.id, 'read_via', v_via));
        end if;
      end if;
    end if;
    update pipeline.provider_description_reads set evidence_id = coalesce(v_ev, evidence_id), source_url = coalesce(v_url, x->'fetch'->>'url', source_url),
           read_via = coalesce(v_via, read_via), content_hash = coalesce(v_hash, content_hash), source_captured_at = coalesce(v_cap, source_captured_at)
     where id = r.id;
    v_err := nullif(x->>'error', '');
    if v_err is not null or coalesce((x->>'retry')::boolean, false) then
      -- a failed read is tried again after pdesc.retry_minutes, at most pdesc.tries times; then the dead letter list
      update pipeline.provider_description_reads set state = case when tries >= v_max then 'dead_letter' else 'queued' end,
             next_try_at = now() + make_interval(mins => security.pipeline_num_v1('pdesc.retry_minutes', 360)::int), leased_until = null,
             rule = case when tries >= v_max then 'dead_letter' else 'retry' end, reason = left(coalesce(v_err, x->>'reason', 'retry'), 400), updated_at = now()
       where id = r.id returning state into v_out;
      v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1); continue;
    end if;
    if x->'answer' is null then
      -- no page to read: no About page on the provider's own hosts, robots.txt, another provider's host
      update pipeline.provider_description_reads set state = 'held', leased_until = null, rule = coalesce(nullif(x->>'rule', ''), 'no_about_page'),
             reason = left(coalesce(x->>'reason', 'no About page found on the provider''s own website'), 400), updated_at = now()
       where id = r.id;
      v_tally := v_tally || jsonb_build_object('held', coalesce((v_tally->>'held')::int, 0) + 1); continue;
    end if;
    select * into r from pipeline.provider_description_reads where id = r.id;
    v_chk := security.provider_description_validate_v1(r.provider_id, r.source_url, r.source_captured_at, x->'answer');
    if v_chk->>'outcome' = 'propose' and r.evidence_id is null then
      v_chk := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'no_evidence', 'reason', 'the page copy is not stored as evidence', 'checks', v_chk->'checks');
    end if;
    if v_chk->>'outcome' = 'propose' then
      insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
      values ('provider', r.provider_id, 'provider_description', r.evidence_id,
              jsonb_build_object('description', (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = r.provider_id)),
              jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences', 'source_url', r.source_url, 'evidence_id', r.evidence_id,
                                 'captured_at', r.source_captured_at, 'read_id', r.id),
              jsonb_build_object('read_via', r.read_via, 'content_hash', r.content_hash, 'source_url', r.source_url),
              jsonb_build_object('model', r.model, 'prompt_version', r.prompt_version, 'worker', r.worker, 'cost_usd', r.cost_usd, 'checks', v_chk->'checks', 'rule', v_chk->>'rule'),
              'pending', 'Provider description read from the official page: every sentence quotes the page. A person approves or rejects it; nothing is published before.',
              'CF-247 P1 provider descriptions (Platform Admin 2 Nov 2026 10:28)')
      returning id into v_item;
      update pipeline.provider_description_reads set state = 'proposed', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = null, review_item_id = v_item, last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'proposed';
    elsif v_chk->>'outcome' = 'verified' then
      update pipeline.provider_description_reads set state = 'verified', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = v_chk->>'reason', last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'verified';
    else
      update pipeline.provider_description_reads set state = 'held', leased_until = null, proposal = jsonb_build_object('sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = left(v_chk->>'reason', 400), updated_at = now()
       where id = r.id;
      v_out := 'held';
    end if;
    v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1);
  end loop;
  return v_tally;
end $function$;
revoke all on function public.svc_provider_description_record(jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_description_record(jsonb) to service_role;
comment on function public.svc_provider_description_record(jsonb) is 'CF-247 P1 provider descriptions: records the worker''s reads. A stored or newly stored own-host page is the evidence; a failed read is retried (pdesc.tries, pdesc.retry_minutes) then dead-lettered; a read that passes security.provider_description_validate_v1 becomes one Layer 4 item (provider_description); one that matches the description held is verified; anything else is held with its rule. Never writes catalogue.providers.';

-- ---------------------------------------------------------------- 6 admission (a person, Layer 4) and publication check
create or replace function security.layer4_provider_description_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare i pipeline.layer4_review_items%rowtype; v_text text; v_now text; v_pub jsonb; v_shown text; v_key text;
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' then raise exception 'not a provider description item' using errcode = '22023'; end if;
  -- approved as read: an edited description has no quote for its new words, so it is not admitted (reject, and the page is read again later)
  if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read, with every sentence quoted from the page; reject it instead of editing' using errcode = '22023'; end if;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  if v_text is null then raise exception 'the proposal has no description' using errcode = '22023'; end if;
  if i.evidence_id is null then raise exception 'the proposal has no stored page' using errcode = '22023'; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = i.entity_id and l.field in ('description', 'p_description', 'all')) then
    raise exception 'the description is locked by hand' using errcode = '22023';
  end if;
  select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
  if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then raise exception 'the description changed since this was proposed; reject this item' using errcode = '22023'; end if;
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- verify publication: the Website API v2 provider payload is read back (a provider not published returns nothing yet)
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin
    v_pub := public.website_v2_provider(v_key);
    v_shown := v_pub->'item'->>'description';
  exception when others then v_shown := null;
  end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(),
         published_at = case when v_shown = v_text then now() end, updated_at = now()
   where review_item_id = i.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now()
   where provider_id = i.entity_id and state = 'admitted' and review_item_id is distinct from i.id;
  return jsonb_build_object('provider_id', i.entity_id, 'description_chars', length(v_text), 'published', v_shown = v_text, 'evidence_id', i.evidence_id);
end $function$;
revoke all on function security.layer4_provider_description_apply_impl(uuid, uuid, jsonb, text) from public, anon, authenticated;
comment on function security.layer4_provider_description_apply_impl(uuid, uuid, jsonb, text) is 'CF-247 P1 provider descriptions: Layer 4 approval of a provider_description item writes catalogue.providers.description (as read, never edited; never over a value locked by hand or changed since the proposal), marks the read admitted and checks the Website API v2 payload shows it (published_at).';

-- outcomes that do not admit: the read is rejected (reject) or queued again (more evidence, returns)
create or replace function security.provider_description_review_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $function$
begin
  update pipeline.provider_description_reads set
         state = case when new.status = 'rejected' then 'rejected' when new.status in ('more_evidence', 'returned_layer2', 'returned_layer3') then 'held' when new.status = 'superseded' then 'superseded' else state end,
         rule = case when new.status in ('approved', 'edited_approved') then rule else 'layer4_' || new.status end,
         updated_at = now()
   where review_item_id = new.id and state = 'proposed' and new.status not in ('approved', 'edited_approved');
  return new;
end $function$;
create or replace trigger layer4_review_items_provider_description after update of status on pipeline.layer4_review_items
  for each row when (old.status = 'pending' and new.status <> 'pending' and new.field_code = 'provider_description')
  execute function security.provider_description_review_trg_v1();

-- ---------------------------------------------------------------- 7 job provider-description-read (catalogued; inactive)
create or replace function security.provider_description_fire_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int;
begin
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  v_q := security.provider_description_enqueue_v1();
  select count(*) into v_dead from pipeline.provider_description_reads r where r.state = 'dead_letter';
  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('queued', v_q, 'ai', 'stopped', 'dead_letter', v_dead); end if;
  if (select coalesce(sum(r.cost_usd), 0) from pipeline.provider_description_reads r) >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then
    return jsonb_build_object('queued', v_q, 'ai', 'ceiling', 'dead_letter', v_dead);
  end if;
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
  select count(*) into v_due from pipeline.provider_description_reads r
   where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now())) and r.tries < security.pipeline_num_v1('pdesc.tries', 3);
  select max(l.created_at) into v_last from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description'
     and l.created_at > now() - make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int);
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if v_due > 0 and v_open = 0 and v_last is null then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int));
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 1, 'dead_letter', v_dead);
  end if;
  return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 0, 'dead_letter', v_dead);
end $function$;
comment on function security.provider_description_fire_v1() is 'CF-247 P1 provider descriptions: job provider-description-read. While pdesc.enabled is 1: queues providers (bounded), and at most once every pdesc.every_minutes sends the worker batch.provider_description providers, inside the AI daily guard (guard_provider_description) and while fewer than pdesc.pending_max proposals wait in Layer 4.';

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('provider-description-read', 'Course pages', 38, 'Provider descriptions: find, read and propose',
  'Every 10 minutes while Provider descriptions: reader on is 1 (off until the Platform Admin activates it), at most once every Provider descriptions: run every: queues providers in scope with no description (bounded), takes the stored copy of the provider''s own About page where one is held, otherwise has the worker find the About link on the provider''s home page and read it (direct first with robots.txt respected; Firecrawl only when the site refuses, within the Firecrawl budget), and sends it to the pinned Enrich fields model. Every sentence must quote the page; a description that passes every check goes to Layer 4, where a person approves or rejects it. Failed reads are retried, then listed as dead letters on Coverage.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'provider-description-read') then
    perform cron.schedule('provider-description-read', '6,16,26,46,56 * * * *', $j$select security.provider_description_fire_v1()$j$);
  end if;
  perform cron.alter_job((select jobid from cron.job where jobname = 'provider-description-read'), active := false);
end $c$;

-- ---------------------------------------------------------------- 8 metrics and dead-letter recovery (Coverage › Every field)
create or replace function public.admin_provider_descriptions(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_rank int := security.current_role_rank(); v_ids uuid[]; v_n int; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'curator role required' using errcode = '42501'; end if;
  if p_action = 'metrics' then
    return (with el as (
              select p.id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 cc, nullif(btrim(p.description), '') is not null present,
                     (select r.state from pipeline.provider_description_reads r where r.provider_id = p.id order by r.created_at desc limit 1) state,
                     (select r.rule from pipeline.provider_description_reads r where r.provider_id = p.id order by r.created_at desc limit 1) rule,
                     security.provider_description_stored_v1(p.id) is not null stored
                from catalogue.providers p join ref.countries k on k.id = p.country_id
               where security.provider_description_scope_v1(p.id) and (v_cc is null or k.iso_alpha2 = v_cc)
                 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)),
            rd as (select r.* from pipeline.provider_description_reads r join el on el.id = r.provider_id)
      select jsonb_build_object(
        'enabled', security.pipeline_num_v1('pdesc.enabled', 0) >= 1,
        'job_active', coalesce((select j.active from cron.job j where j.jobname = 'provider-description-read'), false),
        'by_country', coalesce((select jsonb_agg(jsonb_build_object('country', cc, 'eligible', n, 'present', pr, 'missing', n - pr, 'stored_pages', st) order by cc)
                                  from (select cc, count(*) n, count(*) filter (where present) pr, count(*) filter (where stored) st from el group by cc) c), '[]'::jsonb),
        'eligible', (select count(*) from el), 'present', (select count(*) from el where present), 'missing', (select count(*) from el where not present),
        'stored_pages_available', (select count(*) from el where stored),
        'queued', (select count(*) from el where state = 'queued'), 'reading', (select count(*) from el where state = 'reading'),
        'proposed', (select count(*) from el where state = 'proposed'), 'held', (select count(*) from el where state = 'held'),
        'dead_letter', (select count(*) from el where state = 'dead_letter'), 'admitted', (select count(*) from el where state = 'admitted'),
        'verified', (select count(*) from el where state = 'verified'), 'rejected', (select count(*) from el where state = 'rejected'),
        'published', (select count(*) from rd where rd.state = 'admitted' and rd.published_at is not null),
        'pages_acquired', (select count(*) from rd where rd.read_via in ('direct', 'firecrawl')),
        'pages_reused', (select count(*) from rd where rd.read_via = 'stored'),
        'ai_reads', (select count(*) from rd where rd.model is not null),
        'retried', (select count(*) from rd where rd.tries > 1),
        'cost_usd', (select round(coalesce(sum(rd.cost_usd), 0), 4) from rd),
        'firecrawl_reads', (select coalesce(sum(rd.firecrawl_reads), 0) from rd),
        'ai_usd_max', security.pipeline_num_v1('pdesc.ai_usd_max', 1), 'firecrawl_reads_max', security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0),
        'cost_per_admitted_usd', (select case when count(*) filter (where rd.state = 'admitted') = 0 then null
                                              else round(sum(rd.cost_usd) / count(*) filter (where rd.state = 'admitted'), 4) end from rd),
        'reads_last_7_days', (select count(*) from rd where rd.updated_at > now() - make_interval(days => 7) and rd.model is not null),
        'last_run', (select max(l.created_at) from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description'),
        'layer4_pending', (select count(*) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending'),
        'layer4_decided', (select count(*) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status <> 'pending'),
        'rejections', coalesce((select jsonb_agg(jsonb_build_object('rule', rule, 'n', n) order by n desc)
                                  from (select rd.rule, count(*) n from rd where rd.state in ('held', 'rejected', 'dead_letter') group by rd.rule) z), '[]'::jsonb),
        'backlog', (select count(*) from el where not present and coalesce(state, 'none') not in ('proposed', 'held', 'dead_letter', 'rejected')),
        'providers', coalesce((select jsonb_agg(jsonb_build_object('provider_id', el.id, 'provider', el.name, 'country', el.cc, 'present', el.present, 'state', el.state,
                                                                  'rule', el.rule, 'stored_page', el.stored) order by el.cc, el.name) from el), '[]'::jsonb)));
  elsif p_action = 'retry' then
    -- dead letters and held reads go back to the queue (PIM Admin and above, with a reason)
    if v_rank < 5 then raise exception 'PIM Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 5 then raise exception 'reason required'; end if;
    v_ids := array(select jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb))::uuid);
    update pipeline.provider_description_reads r set state = 'queued', tries = 0, next_try_at = now(), leased_until = null, rule = 'retried', reason = v_reason, updated_at = now()
     where r.state in ('dead_letter', 'held') and r.provider_id = any (v_ids)
       and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = r.provider_id and o.state in ('queued', 'reading', 'proposed'))
       and r.id = (select r2.id from pipeline.provider_description_reads r2 where r2.provider_id = r.provider_id order by r2.created_at desc limit 1);
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('provider_descriptions', 'retry', 'pipeline.provider_description_reads', jsonb_build_object('providers', to_jsonb(v_ids), 'requeued', v_n, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'requeued', v_n);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;
revoke all on function public.admin_provider_descriptions(text, jsonb) from public, anon;
grant execute on function public.admin_provider_descriptions(text, jsonb) to authenticated;
comment on function public.admin_provider_descriptions(text, jsonb) is 'CF-247 P1 provider descriptions (mandate §8): metrics for Coverage › Every field (eligible, present, missing, proposed, held, admitted, dead letter, stored pages, pages acquired and reused, AI reads, cost and cost per admitted description, rejections by rule, Layer 4 queue, last run, backlog, by country and provider) and retry of dead letters (PIM Admin, with a reason).';

revoke all on function security.provider_description_scope_v1(uuid) from public, anon, authenticated;
revoke all on function security.provider_hosts_v1(uuid) from public, anon, authenticated;
revoke all on function security.provider_page_host_v1(uuid, text) from public, anon, authenticated;
revoke all on function security.provider_description_stored_v1(uuid) from public, anon, authenticated;
revoke all on function security.provider_description_validate_v1(uuid, text, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function security.provider_description_enqueue_v1() from public, anon, authenticated;
revoke all on function security.provider_description_fire_v1() from public, anon, authenticated;
revoke all on function security.provider_description_review_trg_v1() from public, anon, authenticated;

-- ---------------------------------------------------------------- 9 md5-guarded edits of live functions
-- md5 (before = live, read 2 Nov 2026 10:45 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/p1-provider-descriptions/run.sh):
--   security.layer4_review_decide_impl(uuid,text,text,jsonb)  67966cebe3184b9acad1a3451fd0021b -> 073889b7c5319019b25212ce08705a37
--   security.ai_spend_today_v1()                               f18af72fe3d406341931a5daaa93f987 -> cb68e7677710b14c3c219048de34c406
--   security.layer4_inbox_kinds_v1()                           629fcbda204cd79fdba97a096a6dc26b -> f5fc812e0971a415b664926ec5dbdf8c
--   security.layer4_inbox_items_v1()                           c1a133c3260c3c160397151bd0664957 -> c31b009df674a4a6ff531f00b99a9a45
--   public.admin_layer4_inbox(text,jsonb)                      417f181d12155f79f68c1e70c27a1892 -> f1f0d760b682d6d132af0e8b55151292
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 9a Layer 4 decide: a provider description is admitted only through its own apply function (approved as read)
select pg_temp.edit_once('security.layer4_review_decide_impl(uuid,text,text,jsonb)', '67966cebe3184b9acad1a3451fd0021b', '073889b7c5319019b25212ce08705a37', array[
  array[$o$    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$o$,
        $n$    elsif v_item.entity_type='provider' and v_item.field_code='provider_description' then
      -- CF-247 P1 (Platform Admin 2 Nov 2026 10:28): a provider description is admitted as read, never edited; reject etc. by trigger
      v_scalar:=security.layer4_provider_description_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$n$]], array[1]);

-- 9b AI spend: the description reader has its own line and daily guard (guard_provider_description), inside the AI stop
select pg_temp.edit_once('security.ai_spend_today_v1()', 'f18af72fe3d406341931a5daaa93f987', 'cb68e7677710b14c3c219048de34c406', array[
  array[$o$from pipeline.entry_matrix_runs x, d where x.updated_at >= d.t and coalesce(x.cost_usd, 0) > 0)$o$,
        $n$from pipeline.entry_matrix_runs x, d where x.updated_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'provider_description', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.provider_description_reads x, d where x.updated_at >= d.t and coalesce(x.cost_usd, 0) > 0)$n$],
  array[$o$('entry_matrix', 'Entry matrices with AI', 7))$o$, $n$('entry_matrix', 'Entry matrices with AI', 7), ('provider_description', 'Provider descriptions with AI', 8))$n$]], array[1, 1]);

-- 9c Layer 4 › Inbox: university descriptions are their own kind (they would otherwise show as course links), approved as read or rejected
select pg_temp.edit_once('security.layer4_inbox_kinds_v1()', '629fcbda204cd79fdba97a096a6dc26b', 'f5fc812e0971a415b664926ec5dbdf8c', array[
  array[$o$   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [$o$,
        $n$   "provider_description": {"label": "University description", "order": 18, "choices": [
     {"key": "approve", "label": "Approve as read", "returns": "The description is published as read from the official page (every sentence quoted from it); the website shows it from its next read"},
     {"key": "reject", "label": "Reject", "returns": "Nothing is published; the university is read again after the set wait"}]},
   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [$n$]], array[1]);

select pg_temp.edit_once('security.layer4_inbox_items_v1()', 'c1a133c3260c3c160397151bd0664957', 'c31b009df674a4a6ff531f00b99a9a45', array[
  array[$o$              when r.field_code = any (security.aer_review_kinds_v1()) then 'aer_review'  -- CF-247 A1-A3 (30 Oct 2026): the AER review path
$o$,
        $n$              when r.field_code = any (security.aer_review_kinds_v1()) then 'aer_review'  -- CF-247 A1-A3 (30 Oct 2026): the AER review path
              when r.entity_type = 'provider' and r.field_code = 'provider_description' then 'provider_description'  -- CF-247 P1 (2 Nov 2026): university descriptions
$n$],
  array[$o$                                       when 'entry_matrix_change' then 'Entry requirements: the provider table changed' end,$o$,
        $n$                                       when 'entry_matrix_change' then 'Entry requirements: the provider table changed'
                                       when 'provider_description' then 'University description from the official page' end,$n$]], array[1, 1]);

select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', '417f181d12155f79f68c1e70c27a1892', 'f1f0d760b682d6d132af0e8b55151292', array[
  array[$o$  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'keep' then 'reject' when 'use' then 'approve' else 'edit_and_approve' end, v_reason,$o$,
        $n$  elsif v_kind = 'provider_description' then
    -- CF-247 P1 (Platform Admin 2 Nov 2026 10:28): a university description is approved as read or rejected, never edited
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'approve' then 'approve' else 'reject' end, v_reason, null);
  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'keep' then 'reject' when 'use' then 'approve' else 'edit_and_approve' end, v_reason,$n$]], array[1]);

-- ---------------------------------------------------------------- 10 register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.provider_description_reads', 'Layer 2', 'P1 provider descriptions: the reader''s read list with provenance, checks and Layer 4 item', 'active', '{}', '20261102050000'),
 ('function', 'security.provider_description_validate_v1', 'Layer 3', 'P1 provider descriptions: evidence-grounded validation', 'active', '{}', '20261102050000'),
 ('function', 'public.svc_provider_description_next', 'Layer 2', 'P1 provider descriptions: worker lease', 'active', '{}', '20261102050000'),
 ('function', 'public.svc_provider_description_record', 'Layer 3', 'P1 provider descriptions: worker record, validation and Layer 4 proposal', 'active', '{}', '20261102050000'),
 ('function', 'security.layer4_provider_description_apply_impl', 'Layer 4', 'P1 provider descriptions: admission by a person and publication check', 'active', '{}', '20261102050000'),
 ('function', 'security.provider_description_fire_v1', 'Layer 2', 'P1 provider descriptions: job provider-description-read', 'active', '{}', '20261102050000'),
 ('function', 'public.admin_provider_descriptions', 'Operations', 'P1 provider descriptions: metrics and dead-letter retry', 'active', '{}', '20261102050000')
on conflict do nothing;
