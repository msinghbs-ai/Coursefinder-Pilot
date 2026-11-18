-- CF-247 Autonomous AI Operations, workstream G (Integration Controller brief 3 Nov 2026 15:45 AEDT; mandate 2026-11-03-p0-autonomous-ai-operations-
-- mandate-1537.md §7, §8, §9; workstreams 2026-11-03-ai-operations-workstreams-1540.md §3): provider identity and website validation as a permanent
-- scheduled check, and reversible, relationship-aware provider and country lifecycle transitions. Lands after workstream A (20261104010000).
-- Why (live, read-only, 3 Nov 2026 15:42-16:08 AEDT):
--   * IQ-00063 stopped the onboarding loop of NEWGEN EDUCATION (provider 2db6cb5e, CRICOS 03871F; onboarding d5dfc2ea stopped
--     needs_source_discovery) but nothing finds the next malformed or wrong website, nothing records what evidence the platform holds for the
--     right one, and nothing proposes a correction through the authorised path. The website came with the CRICOS register record (provider
--     created 11 Aug 2026 from source b5680d74, the day the register institutions file was stored); a third-party mirror of the register shows
--     the same "https://info@newgen.edu.au", so the register value itself is malformed.
--   * Retirement exists but is partial: security.provider_archive_apply_v1 (archive, adapter and link recipe off, pending provider and course
--     Layer 4 items superseded, pipeline.provider_archives) and security.provider_restore_v1 (reverses it); the trigger on
--     pipeline.layer1_provider_departures archives a provider whose registered courses all left the register (16 archived, all layer1_departure).
--     There is no authoritative-evidence record or effective date, no closed / merged / temporarily unavailable distinction, no cascade to
--     queued tasks, onboarding rows, enrichment plans or scholarship reviews, no reviewed plan, no country retirement, and 7 departures wait
--     "needs_review" with nothing proposing a decision.
--   * Measured live with this change's rules (read-only, 16:16 AEDT; the same logic as security.provider_identity_check_v1, checked equal on the
--     fixture): of 3,086 active providers, 776 have no website (the existing no_website path), and 265 have a finding: website_malformed 1
--     (NEWGEN), identity_unconfirmed 202, domain_shared 35 (16 hosts, e.g. ahic.edu.au for two differently named colleges), redirected_or_parked
--     45 (44 a scholarship site mapping ended on another domain, 1 a website check redirect, 0 parked), register_changed 0 (the 16 ended
--     registrations and 7 departures waiting review all belong to providers already archived by the register trigger; those 16 archives become
--     executed lifecycle events). A first pass on registrable domains alone gave 576 false shared-domain hits (every Victorian school "sharing"
--     vic.edu.au, Quebec schools sharing qc.ca): state and provincial zones are kept and sharing is compared by host.
-- What:
--   1 Provider identity check (job provider-identity-check, hourly; diagnoses and records only, ships ON): security.provider_identity_check_v1()
--     tests every active provider (identity.max_providers) for five findings, kept in pipeline.provider_identity_findings (open, seen again,
--     cleared; never deleted):
--       website_malformed      security.website_refusal_v1 refuses the recorded website (user part, no host, not http/https, spaces)
--       identity_unconfirmed   the register lists another site (a stored website check's register_site), or the domain fits neither the provider's
--                              name nor its contact email domain and no stored check verified it
--       domain_shared          the registrable domain is also recorded for an unrelated provider (no shared name word, different acronym)
--       redirected_or_parked   stored evidence only: a website check or a scholarship site mapping ended on another domain, or the checked home
--                              page title is a parked-domain page (identity.parked_markers)
--       register_changed       the register ended the registration of an active provider, a register departure waits review, or the register
--                              code differs from the provider's stable key
--     Each finding code is one integration issue by fingerprint (security.integration_issue_upsert_v1, identity.issue_on), with the providers.
--   2 Identity investigations (identity.investigate_on, ON: opening one only records): a provider with a website_malformed, identity_unconfirmed,
--     domain_shared or redirected_or_parked finding gets one pipeline.provider_identity_investigations row with the platform's own evidence
--     (register rows, stored home-page snapshots, website checks, contact email domain marked "not evidence of a website"). It is verified only
--     by the platform's own site check (pipeline.provider_website_checks, verdict verified: the CRICOS code on the home page or the register's
--     site) of a candidate that is not the recorded website; otherwise it stays blocked_evidence, by name. A candidate is never derived from an
--     email address. Verified, it is proposed (state proposed): the correction is a Platform Admin website change through the existing
--     authorised path (Adapter builder › website change, public.admin_provider_website_check('change'), which checks the site again before it
--     saves), never applied here. Candidates come from stored evidence (register_site, a redirect's final address) or a person
--     (public.admin_provider_identity('candidate')); an automatic site check of a stored candidate is behind identity.candidate_check_on (ships 0).
--   3 Lifecycle events (pipeline.provider_lifecycle_events): deregistered, closed, merged, temporarily_unavailable for a provider, retired for a
--     country; each with authoritative evidence (register, first-party or an admin record; never AI inference alone, refused by
--     security.provider_lifecycle_evidence_ok_v1) and an effective date. States proposed -> planned -> approved -> executed -> reversed (or
--     rejected). security.provider_lifecycle_propose_v1 (in the same job, lifecycle.propose_on, ON: records only) proposes events from register
--     evidence (departures waiting review, ended registrations of active providers; a successor makes it merged) and records the existing
--     layer1_departure archives as executed events, so the history is in one place. security.provider_lifecycle_plan_v1 builds the reviewed
--     cascade plan (acceptance mandate 15:52 §12): courses, scholarships, entry requirements, AER records, campuses, provider contacts, source
--     mappings (adapter, link recipe), Layer 1 references, Layer 2 and 3 work, tasks, onboarding rows, enrichment plans, pending Layer 4 items
--     (provider, course, scholarship), identity investigations, the search projection and the consumer projection.
--     temporarily_unavailable is not retirement: nothing is archived or hidden; future work is held. security.provider_lifecycle_verify_v1
--     checks downstream consistency after execution (hidden, out of search.course_documents, no active work, no pending review); the job
--     records it until it passes.
--   4 Execution only on an admin decision and only with lifecycle.cascade_on (ships 0): public.admin_provider_lifecycle approve / execute /
--     reverse (Platform Admin). Execution archives through the existing security.provider_archive_apply_v1 (consumer projection through the
--     existing hide: security.provider_hidden_v1 and the search refresh; G3 untouched), cancels the provider's queued and paused tasks by request
--     (cancel_requested), stops its onboarding rows, cancels its queued enrichment plans, supersedes pending scholarship Layer 4 items and pauses
--     its contact discovery profile, each id recorded; country retirement does this per provider and switches the country's provider, course and scholarship ingestion off. Reversal
--     restores through security.provider_restore_v1 and reverts each recorded change. Nothing is deleted.
--   5 security.provider_onboarding_tick_v1 (md5-guarded edit): a provider held by an executed temporarily_unavailable event
--     (security.provider_lifecycle_held_v1) is neither started nor stepped; reversal brings it back by itself.
--   6 Ops contract (workstream A): root causes and remedies registered; the auto remedies only open investigations, build plans and stop
--     onboarding loops on a refused website; correction and cascade are admin remedies.
-- md5 (before = live v2.15.426, read 3 Nov 2026 15:51 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/ops-provider-lifecycle/run.sh):
--   security.provider_onboarding_tick_v1()                 181fc3dd2d78930c32e70cc24fb0adbd -> ccae12038a32dd95f3644dfc3e5a3b5f
-- Called, not edited (checked against live): security.website_refusal_v1 2bf77cfa3474619d71b33c3e7877ae0d, security.site_host_v1
--   04938c208412f46735c7a3f99348612c, security.provider_archive_apply_v1 5a2af698d6de7e5e3bf5ef3a860236c8, security.provider_restore_v1
--   a5e479c7ebc5060f710da1ffb95dd60d.
-- Ships ON (records, diagnoses or stops waste only): identity.check_on, identity.issue_on, identity.investigate_on, lifecycle.propose_on.
-- Ships OFF (spends a worker read or removes work): identity.candidate_check_on 0, lifecycle.cascade_on 0.
-- Budgets: no Firecrawl or AI value is raised; nothing here reads a page or calls a model.
-- Consumer API (G3): untouched (no website_*, zoho_*, api.* object, table or column is changed; projections move only through the existing
--   archive and hide mechanism, and only on an executed admin decision).
-- Data: no record is corrected here. NEWGEN (2db6cb5e, CRICOS 03871F) is corrected only through docs/paste/PASTE-20261104-newgen-03871f-a-website-check.sql
--   (the platform's own site check of https://newgen.edu.au/, from Study Australia and Study Melbourne records for CRICOS 03871F) and then
--   -b-website-correction.sql, which refuses unless that check finds CRICOS 03871F on the home page (Platform Admin decision, 15:52 §4).
-- Replaces: the provider onboarding tick's selection of providers (same function, md5-guarded edit, adds the lifecycle hold)
-- Retires: nothing
-- Nothing is dropped or deleted.

-- 0. workstream A's contract lands first; the definitions this change calls are the ones it was written against ------------------------------
do $g$
declare r record;
begin
  if to_regclass('pipeline.ops_remedies') is null then raise exception 'workstream A (20261104010000) has not landed: pipeline.ops_remedies is missing'; end if;
  for r in select * from (values ('security.website_refusal_v1(text)', '2bf77cfa3474619d71b33c3e7877ae0d'),
                                 ('security.site_host_v1(text)', '04938c208412f46735c7a3f99348612c'),
                                 ('security.provider_archive_apply_v1(uuid,text,text,uuid,boolean)', '5a2af698d6de7e5e3bf5ef3a860236c8'),
                                 ('security.provider_restore_v1(uuid,text,uuid,boolean)', 'a5e479c7ebc5060f710da1ffb95dd60d')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

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

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'identity.check_on', 'Provider identity: run the website and identity check',
  '1: job provider-identity-check tests every active provider''s website and register identity (malformed website, identity not confirmed, a domain shared with an unrelated provider, a redirect or parked domain in stored evidence, a register change) and records the findings. It reads stored data only. 0: the job does nothing.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 800, 'Platform upkeep', 'security.provider_identity_check_v1', 'CF-247 ops workstream G, 3 Nov 2026: on (diagnoses only)'),
 ('pipeline', 'identity.max_providers', 'Provider identity: providers checked a run',
  'The check reads at most this many active providers a run (all of them today), least recently checked first.',
  'number', '5000'::jsonb, '100', '20000', 'providers', 801, 'Platform upkeep', 'security.provider_identity_check_v1', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'identity.name_token_min_chars', 'Provider identity: shortest name word that counts',
  'A domain fits a provider''s name when it contains a word of the name at least this long (common words such as university or college do not count), or the name''s initials.',
  'number', '4'::jsonb, '3', '8', 'characters', 802, 'Platform upkeep', 'security.provider_identity_name_words_v1', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'identity.name_stopwords', 'Provider identity: name words that do not identify a provider',
  'Words left out when a domain is matched to a provider''s name, and when two providers sharing a domain are tested for being related.',
  'list', '["university","institute","college","australia","australian","education","educational","training","academy","school","international","group","services","centre","center","limited","zealand","canada","canadian","technology","business","management","studies","learning","national","sydney","melbourne","brisbane","perth","adelaide","queensland","victoria","wales"]'::jsonb,
  null, null, 'words', 803, 'Platform upkeep', 'security.provider_identity_name_words_v1', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'identity.parked_markers', 'Provider identity: parked-domain page titles',
  'A checked home page whose title contains one of these is a parked or for-sale domain (stored evidence only).',
  'list', '["domain for sale","domain is for sale","buy this domain","parked","hugedomains","sedo","domain expired","future home of"]'::jsonb,
  null, null, 'phrases', 804, 'Platform upkeep', 'security.provider_identity_check_v1', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'identity.issue_on', 'Provider identity: raise integration issues',
  '1: each finding kind with providers is one integration issue (by fingerprint) for the operations controller. 0: findings are recorded only.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 805, 'Platform upkeep', 'security.provider_identity_check_v1', 'CF-247 ops workstream G, 3 Nov 2026: on (reports only)'),
 ('pipeline', 'identity.investigate_on', 'Provider identity: open investigations',
  '1: a provider with a website or identity finding gets one identity investigation with the platform''s own evidence; it is verified only by the platform''s site check of a candidate, and a verified one is proposed to the Platform Admin. Nothing is corrected. 0: no investigation is opened.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 806, 'Platform upkeep', 'security.provider_identity_investigate_v1', 'CF-247 ops workstream G, 3 Nov 2026: on (records only)'),
 ('pipeline', 'identity.candidate_check_on', 'Provider identity: check stored candidate sites',
  '1: an investigation''s candidate site taken from stored evidence (the register''s site, a redirect''s final address) is checked by the existing website check (a worker read). It never saves a website. 0: only a person''s check runs.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 807, 'Platform upkeep', 'security.provider_identity_investigate_v1', 'CF-247 ops workstream G, 3 Nov 2026: off (spends a worker read)'),
 ('pipeline', 'identity.candidate_checks_per_run', 'Provider identity: candidate checks a run',
  'With identity.candidate_check_on, at most this many candidate site checks are queued a run.',
  'number', '5'::jsonb, '1', '50', 'checks', 808, 'Platform upkeep', 'security.provider_identity_investigate_v1', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'identity.remedy_max_attempts', 'Provider identity: remedy attempts',
  'The operations controller tries a provider identity remedy at most this many times for one issue.',
  'number', '3'::jsonb, '1', '10', 'attempts', 809, 'Platform upkeep', 'pipeline.ops_remedies (provider identity remedies)', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'identity.remedy_cooldown_minutes', 'Provider identity: wait between remedy attempts',
  'The operations controller waits this long before trying a provider identity remedy again.',
  'number', '60'::jsonb, '5', '1440', 'minutes', 810, 'Platform upkeep', 'pipeline.ops_remedies (provider identity remedies)', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'lifecycle.propose_on', 'Lifecycle: propose from register evidence',
  '1: register evidence (a departure waiting review, an ended registration of an active provider) opens a proposed lifecycle event with its cascade plan, and existing register archives are recorded as executed events. Proposals change nothing. 0: no proposal.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 811, 'Platform upkeep', 'security.provider_lifecycle_propose_v1', 'CF-247 ops workstream G, 3 Nov 2026: on (records only)'),
 ('pipeline', 'lifecycle.cascade_on', 'Lifecycle: carry out approved transitions',
  '1: a lifecycle event approved by the Platform Admin can be executed: the provider is archived through the existing archive (hidden from the website and Zoho), its queued tasks, onboarding, plans and scholarship reviews stop; a country retirement does this for each provider and switches the country''s ingestion off. Every change is recorded and reversible. 0: plans are reviewed but nothing is executed.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 812, 'Platform upkeep', 'security.provider_lifecycle_execute_v1', 'CF-247 ops workstream G, 3 Nov 2026: off (removes work; admin decision)'),
 ('pipeline', 'lifecycle.plan_max_age_hours', 'Lifecycle: a plan is built again after',
  'An approved event is executed only on a plan built within this many hours; an older plan is built again first, so the reviewed plan matches what is executed.',
  'number', '24'::jsonb, '1', '168', 'hours', 813, 'Platform upkeep', 'security.provider_lifecycle_execute_v1', 'CF-247 ops workstream G, 3 Nov 2026'),
 ('pipeline', 'lifecycle.unavailable_review_days', 'Lifecycle: review a temporary unavailability after',
  'A provider held as temporarily unavailable is raised for review after this many days from the effective date; it is never retired by time alone.',
  'number', '14'::jsonb, '1', '90', 'days', 814, 'Platform upkeep', 'security.provider_lifecycle_propose_v1', 'CF-247 ops workstream G, 3 Nov 2026')
on conflict (toolset_key, key) do nothing;

-- 2. tables ------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.provider_identity_findings (
  provider_id uuid not null references catalogue.providers(id),
  check_code text not null check (check_code in ('website_malformed', 'identity_unconfirmed', 'domain_shared', 'redirected_or_parked', 'register_changed')),
  state text not null default 'open' check (state in ('open', 'cleared')),
  reason text not null,
  detail jsonb not null default '{}',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  cleared_at timestamptz,
  observations int not null default 1,
  primary key (provider_id, check_code));
comment on table pipeline.provider_identity_findings is 'CF-247 ops workstream G: provider website and identity findings of job provider-identity-check (security.provider_identity_check_v1), one row per provider and check: open while the check still finds it, cleared when it no longer does (kept, never deleted).';

create table if not exists pipeline.provider_identity_investigations (
  id bigint generated always as identity primary key,
  provider_id uuid not null references catalogue.providers(id),
  state text not null default 'open' check (state in ('open', 'blocked_evidence', 'proposed', 'corrected', 'closed')),
  opened_for text[] not null default '{}',
  recorded_website text,
  evidence jsonb not null default '[]',
  candidates jsonb not null default '[]',
  verification jsonb,
  reason text,
  opened_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_by uuid,
  close_note text);
create unique index if not exists provider_identity_investigations_one_open on pipeline.provider_identity_investigations(provider_id) where state in ('open', 'blocked_evidence', 'proposed');
comment on table pipeline.provider_identity_investigations is 'CF-247 ops workstream G: one identity investigation per provider with a website or identity finding: the platform''s own evidence (register rows, stored snapshots, website checks), candidate sites with their provenance, and the verification. blocked_evidence until the platform''s site check verifies a candidate; proposed when verified (the Platform Admin corrects through the website change path); never applied here.';

create table if not exists pipeline.provider_lifecycle_events (
  id bigint generated always as identity primary key,
  scope text not null check (scope in ('provider', 'country')),
  provider_id uuid references catalogue.providers(id),
  country_id uuid,
  transition text not null check (transition in ('deregistered', 'closed', 'merged', 'temporarily_unavailable', 'retired')),
  successor_provider_id uuid references catalogue.providers(id),
  effective_date date not null,
  evidence jsonb not null default '[]',
  source text not null,
  state text not null default 'proposed' check (state in ('proposed', 'planned', 'approved', 'executed', 'reversed', 'rejected')),
  plan jsonb,
  planned_at timestamptz,
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  executed_at timestamptz,
  executed_by uuid,
  execution jsonb,
  reversed_at timestamptz,
  reversed_by uuid,
  reverse_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((scope = 'provider' and provider_id is not null and transition <> 'retired') or (scope = 'country' and country_id is not null and transition = 'retired')),
  check (transition <> 'merged' or successor_provider_id is not null));
create unique index if not exists provider_lifecycle_events_one_open on pipeline.provider_lifecycle_events(scope, coalesce(provider_id, country_id), transition)
  where state in ('proposed', 'planned', 'approved', 'executed');
comment on table pipeline.provider_lifecycle_events is 'CF-247 ops workstream G: reversible provider and country lifecycle transitions (deregistered, closed, merged, temporarily unavailable; country retired) with authoritative evidence, an effective date, the reviewed cascade plan (security.provider_lifecycle_plan_v1), the admin decision, every change made at execution (for reversal) and the reversal. Never deleted.';

-- 3. read-only helpers -------------------------------------------------------------------------------------------------------------------------
create or replace function security.provider_identity_domain_v1(p_url text) returns text
language sql immutable set search_path = '' as $$
  -- CF-247 ops G: the registrable domain of a site (www.foo.edu.au -> foo.edu.au; a.b.example.com -> example.com), from the existing host reader
  with h as (select security.site_host_v1(p_url) h)
  -- Australian state school and government zones (scotch.vic.edu.au, education.act.gov.au) and Canadian provincial zones (cegepmatane.qc.ca)
  -- are one level deeper: without them every Victorian school would "share" vic.edu.au (live 3 Nov 2026: 576 false shared-domain hits)
  select case when h is null or h !~ '\.' then null
              when h ~ '\.(vic|nsw|qld|wa|sa|tas|act|nt)\.(edu|gov)\.au$' then substring(h from '([^.@]+\.[^.]+\.[^.]+\.[^.]+)$')
              when h ~ '\.(com|edu|org|net|gov|asn|id)\.au$' or h ~ '\.(ac|co|org|net|govt|school|gen|iwi)\.nz$' or h ~ '\.(ac|co|org|gov)\.uk$'
                or h ~ '\.(ab|bc|mb|nb|nl|ns|nt|nu|on|pe|qc|sk|yk)\.ca$'
                then substring(h from '([^.@]+\.[^.]+\.[^.]+)$')
              else substring(h from '([^.@]+\.[^.]+)$') end
    from h
$$;
revoke all on function security.provider_identity_domain_v1(text) from public, anon, authenticated;
comment on function security.provider_identity_domain_v1(text) is 'CF-247 ops G: the registrable domain of a site address (AU, AU state, NZ, UK and Canadian provincial zones kept)';

create or replace function security.provider_identity_name_words_v1(p_name text) returns text[]
language sql stable set search_path = '' as $$
  -- CF-247 ops G: the words of a provider name that identify it (identity.name_token_min_chars, without identity.name_stopwords)
  select coalesce(array_agg(distinct w), '{}') from regexp_split_to_table(lower(coalesce(p_name, '')), '[^a-z0-9]+') w
   where length(w) >= security.pipeline_num_v1('identity.name_token_min_chars', 4)
     and not w = any (security.pipeline_list_v1('identity.name_stopwords', '[]'::jsonb))
$$;
revoke all on function security.provider_identity_name_words_v1(text) from public, anon, authenticated;
comment on function security.provider_identity_name_words_v1(text) is 'CF-247 ops G: identifying words of a provider name (settings identity.name_token_min_chars, identity.name_stopwords)';

create or replace function security.provider_identity_acronym_v1(p_name text) returns text
language sql immutable set search_path = '' as $$
  -- CF-247 ops G: the initials of a provider name (of, the, and, pty, ltd left out), as some providers use them for a domain
  select nullif(string_agg(left(w, 1), '' order by n), '') from regexp_split_to_table(lower(coalesce(p_name, '')), '[^a-z0-9]+') with ordinality t(w, n)
   where w <> '' and w not in ('of', 'the', 'and', 'pty', 'ltd', 'limited', 'inc', 'incorporated', 'co', 'de', 'des', 'du', 'la', 'le', 'les', 'et', 'l')
$$;
revoke all on function security.provider_identity_acronym_v1(text) from public, anon, authenticated;
comment on function security.provider_identity_acronym_v1(text) is 'CF-247 ops G: the initials of a provider name';

create or replace function security.provider_identity_name_fits_v1(p_host text, p_domain text, p_words text[], p_short text, p_name text) returns boolean
language sql immutable set search_path = '' as $$
  -- CF-247 ops G: a site fits a name when the first label of its registrable domain, or of its own host (mercy.catholic.edu.au), holds an
  -- identifying name word (or is held by one), holds the initials of one of the names (three or more letters; names listed as "A; B" or "A / B"
  -- are each tried, and the whole name), is the short name, is a name run together (collegeaustralia), or starts with a name's first word (abc for ABC College)
  with l as (select distinct x lbl from unnest(array[split_part(p_domain, '.', 1), split_part(regexp_replace(coalesce(p_host, ''), '^www\.', ''), '.', 1)]) x where coalesce(x, '') <> ''),
  n as (select btrim(x) part from regexp_split_to_table(coalesce(p_name, ''), '\s*[;/,|]\s*') x where btrim(x) <> '' union select btrim(p_name) where btrim(coalesce(p_name, '')) <> ''),
  k as (select security.provider_identity_acronym_v1(n.part) acr, regexp_replace(lower(n.part), '[^a-z0-9]', '', 'g') joined,
               regexp_replace(coalesce(nullif(split_part(regexp_replace(lower(n.part), '^the\s+', ''), ' ', 1), ''), ''), '[^a-z0-9]', '', 'g') fw from n)
  select p_domain is not null and exists (select 1 from l where
    exists (select 1 from unnest(coalesce(p_words, '{}')) w where position(w in l.lbl) > 0 or (length(l.lbl) >= 4 and position(l.lbl in w) > 0))
    or l.lbl = lower(btrim(coalesce(p_short, '')))
    or exists (select 1 from k where l.lbl = k.acr or (length(coalesce(k.acr, '')) >= 3 and position(k.acr in l.lbl) > 0)
                                  or (length(l.lbl) >= 4 and (position(l.lbl in k.joined) = 1 or position(k.joined in l.lbl) > 0))
                                  or (length(k.fw) >= 3 and position(k.fw in l.lbl) = 1)))
$$;
revoke all on function security.provider_identity_name_fits_v1(text, text, text[], text, text) from public, anon, authenticated;
comment on function security.provider_identity_name_fits_v1(text, text, text[], text, text) is 'CF-247 ops G: whether a site (its registrable domain or own host) fits one of a provider''s names: name words, initials, short name, run-together name or first word';

create or replace function security.provider_lifecycle_evidence_ok_v1(p_evidence jsonb) returns boolean
language sql immutable set search_path = '' as $$
  -- CF-247 ops G (mandate §9: no cascade from weak AI inference): a lifecycle transition needs at least one authoritative item, a register
  -- record, a first-party page or an admin record, each with a reference; an AI reading alone is never enough
  select jsonb_typeof(coalesce(p_evidence, 'null'::jsonb)) = 'array'
     and exists (select 1 from jsonb_array_elements(p_evidence) e
                  where e->>'kind' in ('register', 'first_party', 'admin_record') and nullif(btrim(coalesce(e->>'ref', '')), '') is not null)
$$;
revoke all on function security.provider_lifecycle_evidence_ok_v1(jsonb) from public, anon, authenticated;
comment on function security.provider_lifecycle_evidence_ok_v1(jsonb) is 'CF-247 ops G: a lifecycle transition has authoritative evidence (register, first_party or admin_record, with a reference); AI inference alone is refused';

create or replace function security.provider_lifecycle_held_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  -- CF-247 ops G: a provider held by an executed (not reversed) temporarily_unavailable event: its new work waits, nothing is retired
  select exists (select 1 from pipeline.provider_lifecycle_events e where e.provider_id = p_provider and e.scope = 'provider'
                  and e.transition = 'temporarily_unavailable' and e.state = 'executed')
$$;
revoke all on function security.provider_lifecycle_held_v1(uuid) from public, anon, authenticated;
comment on function security.provider_lifecycle_held_v1(uuid) is 'CF-247 ops G: whether a provider is held as temporarily unavailable (an executed event); read by security.provider_onboarding_tick_v1';

-- 4. the identity check (job provider-identity-check) -------------------------------------------------------------------------------------
create or replace function security.provider_identity_check_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G: tests active providers for the five identity findings from stored data only; records them (open, seen again, cleared), raises one
-- integration issue per finding kind, opens investigations and proposes lifecycle events from register evidence. Reads no page, calls no model.
declare v_t0 timestamptz := clock_timestamp(); v_n int; v_by jsonb; v_issues jsonb := '{}'::jsonb; v_inv jsonb; v_life jsonb; r record; v_fp text;
begin
  if security.pipeline_num_v1('identity.check_on', 0) < 1 then return jsonb_build_object('skipped', 'identity.check_on is 0'); end if;

  -- this run's findings: a scratch table of the transaction, each row marked with the run's start (a second run in the same transaction reads its own)
  if to_regclass('pg_temp.g_found') is null then
    create temporary table g_found (run timestamptz, provider_id uuid, check_code text, reason text, detail jsonb) on commit drop;
  end if;

  with p as (
    select p.id, p.website, p.email, p.short_name, p.stable_key, coalesce(p.display_name, p.canonical_name) nm,
           security.provider_identity_domain_v1(p.website) dom, lower(nullif(split_part(coalesce(p.email, ''), '@', 2), '')) edom,
           security.website_refusal_v1(p.website) refusal
      from catalogue.providers p
     where p.lifecycle_status = 'active'
     order by (select f.last_seen_at from pipeline.provider_identity_findings f where f.provider_id = p.id order by f.last_seen_at limit 1) nulls first, p.id
     limit security.pipeline_num_v1('identity.max_providers', 5000)::int),
  n as (select p.*, security.provider_identity_name_words_v1(p.nm || ' ' || coalesce(p.short_name, '')) words, security.provider_identity_acronym_v1(p.nm) acr from p),
  wc as (select distinct on (c.provider_id) c.provider_id, c.id, c.verdict, c.result, c.checked_at
           from pipeline.provider_website_checks c where c.state = 'done' and c.provider_id in (select id from p) order by c.provider_id, c.checked_at desc nulls last),
  wv as (select distinct c.provider_id, security.provider_identity_domain_v1(coalesce(nullif(c.result->>'final_url', ''), c.url)) dom
           from pipeline.provider_website_checks c where c.state = 'done' and c.verdict = 'verified' and c.provider_id in (select id from p)),
  -- 1 malformed website
  f1 as (select n.id, 'website_malformed' code, 'The recorded website (' || n.website || ') cannot be used: ' || n.refusal reason,
                jsonb_build_object('website', n.website, 'refusal', n.refusal) detail from n where n.refusal is not null),
  -- 2 identity not confirmed
  f2 as (select n.id, 'identity_unconfirmed',
                case when wc.result->>'register_site' is not null and security.provider_identity_domain_v1(wc.result->>'register_site') is distinct from n.dom
                     then 'The register lists ' || (wc.result->>'register_site') || ', not ' || n.dom
                     else 'The domain ' || n.dom || ' fits neither the provider''s name nor its contact email domain, and no site check verified it' end,
                jsonb_build_object('domain', n.dom, 'email_domain', n.edom, 'register_site', wc.result->>'register_site', 'check_id', wc.id, 'check_verdict', wc.verdict)
           from n left join wc on wc.provider_id = n.id
          where n.refusal is null and n.dom is not null and not security.third_party_host_v1(n.website)
            and ((wc.result->>'register_site' is not null and security.provider_identity_domain_v1(wc.result->>'register_site') is distinct from n.dom)
              or (not security.provider_identity_name_fits_v1(security.site_host_v1(n.website), n.dom, n.words, n.short_name, n.nm)
                  and (n.edom is null or security.provider_identity_domain_v1('https://' || n.edom) is distinct from n.dom)
                  and not exists (select 1 from wv where wv.provider_id = n.id and wv.dom = n.dom)))),
  -- 3 a domain shared with an unrelated provider (third-party directories have their own refusal and are not counted here)
  -- the same host (without www): sites on one organisation's subdomains (mercy.catholic.edu.au, tenison.catholic.edu.au) are not shared
  g as (select security.site_host_v1(n.website) host, array_agg(n.id) ids from n where n.refusal is null and n.dom is not null and not security.third_party_host_v1(n.website)
         group by 1 having count(*) >= 2),
  f3 as (select a.id, 'domain_shared', 'The site ' || g.host || ' is also recorded for ' || string_agg(b.nm, ', ' order by b.nm),
                jsonb_build_object('domain', a.dom, 'host', g.host, 'others', jsonb_agg(jsonb_build_object('provider_id', b.id, 'name', b.nm) order by b.nm))
           from g join n a on a.id = any (g.ids) join n b on b.id = any (g.ids) and b.id <> a.id
          where not (a.words && b.words) and a.acr is distinct from b.acr
            and not exists (select 1 from pipeline.layer1_provider_departures d where (d.provider_id, d.successor_provider_id) in ((a.id, b.id), (b.id, a.id)))
          group by a.id, a.dom, g.host),
  -- 4 a redirect or a parked domain, from stored evidence only
  f4 as (select n.id, 'redirected_or_parked',
                case when (wc.result->>'title') ilike any (select '%' || m || '%' from unnest(security.pipeline_list_v1('identity.parked_markers', '[]'::jsonb)) m)
                     then 'The checked home page is a parked domain page ("' || left(wc.result->>'title', 80) || '")'
                     else 'Stored evidence ends on another domain (' || coalesce(security.provider_identity_domain_v1(wc.result->>'final_url'), security.provider_identity_domain_v1(sd.site_origin)) || ')' end,
                jsonb_build_object('domain', n.dom, 'check_id', wc.id, 'final_url', wc.result->>'final_url', 'title', wc.result->>'title', 'site_map_origin', sd.site_origin)
           from n left join wc on wc.provider_id = n.id left join pipeline.scholarship_discovery_providers sd on sd.provider_id = n.id
          where n.refusal is null and n.dom is not null
            and ((wc.result->>'title') ilike any (select '%' || m || '%' from unnest(security.pipeline_list_v1('identity.parked_markers', '[]'::jsonb)) m)
              or (coalesce((wc.result->>'redirected')::boolean, false) and security.provider_identity_domain_v1(wc.result->>'final_url') is distinct from n.dom)
              or (sd.site_origin is not null and security.provider_identity_domain_v1(sd.site_origin) is distinct from n.dom))),
  -- 5 a register change
  f5 as (select n.id, 'register_changed', string_agg(x.why, '; ' order by x.why), jsonb_agg(x.detail order by x.why)
           from n join (
             select pr.provider_id, 'The ' || upper(pr.registration_scheme) || ' registration ' || pr.registration_code || ' is ' || pr.status
                    || coalesce(' (ended ' || pr.valid_to || ')', '') why,
                    jsonb_build_object('kind', 'registration', 'registration_id', pr.id, 'status', pr.status, 'valid_to', pr.valid_to, 'checked_at', pr.checked_at) detail
               from catalogue.provider_registrations pr where pr.status <> 'active' or pr.valid_to is not null
             union all
             select d.provider_id, 'A register departure waits review (' || d.courses_retired || ' courses left the register)',
                    jsonb_build_object('kind', 'departure', 'departure_id', d.id, 'run_id', d.run_id, 'successor_provider_id', d.successor_provider_id)
               from pipeline.layer1_provider_departures d where d.status = 'needs_review'
             union all
             select pr.provider_id, 'The register code ' || pr.registration_code || ' differs from the provider''s key ' || pv.stable_key,
                    jsonb_build_object('kind', 'code', 'registration_id', pr.id, 'stable_key', pv.stable_key)
               from catalogue.provider_registrations pr join catalogue.providers pv on pv.id = pr.provider_id
              where pv.stable_key like 'provider:' || lower(pr.registration_scheme) || ':%' and lower(pr.registration_code) <> split_part(pv.stable_key, ':', 3)
           ) x on x.provider_id = n.id
          group by n.id)
  insert into pg_temp.g_found select v_t0, z.* from (select * from f1 union all select * from f2 union all select * from f3 union all select * from f4 union all select * from f5) z;

  -- record: new and seen again
  insert into pipeline.provider_identity_findings as f (provider_id, check_code, reason, detail)
  select provider_id, check_code, left(reason, 500), detail from pg_temp.g_found where run = v_t0
  on conflict (provider_id, check_code) do update set state = 'open', reason = excluded.reason, detail = excluded.detail, last_seen_at = now(),
     cleared_at = null, observations = f.observations + 1;
  -- cleared: a provider checked this run (still active) that no longer has the finding
  update pipeline.provider_identity_findings f set state = 'cleared', cleared_at = now()
   where f.state = 'open'
     and not exists (select 1 from pg_temp.g_found x where x.run = v_t0 and x.provider_id = f.provider_id and x.check_code = f.check_code)
     and (exists (select 1 from catalogue.providers p where p.id = f.provider_id and p.lifecycle_status <> 'active')
          or f.provider_id in (select x.provider_id from pg_temp.g_found x where x.run = v_t0) or f.last_seen_at < v_t0);
  select coalesce(jsonb_object_agg(check_code, n), '{}'::jsonb) into v_by from (select check_code, count(*) n from pg_temp.g_found where run = v_t0 group by 1) z;

  -- one integration issue per finding kind (A's queue: diagnosis, remedy, verification)
  if security.pipeline_num_v1('identity.issue_on', 0) >= 1 then
    for r in select check_code, array_agg(provider_id) ids, count(*) n, (array_agg(reason order by provider_id))[1:3] sample from pg_temp.g_found where run = v_t0 group by 1 loop
      v_fp := 'provider_identity:' || r.check_code;
      v_issues := v_issues || jsonb_build_object(r.check_code, (security.integration_issue_upsert_v1(jsonb_build_object(
        'fingerprint', v_fp, 'title', 'Provider identity: ' || replace(r.check_code, '_', ' ') || ' (' || r.n || ' providers)',
        'layer', 'Layer 1', 'subsystem', 'provider identity', 'severity', case when r.check_code = 'website_malformed' then 'P1' else 'P2' end,
        'provider_ids', to_jsonb(r.ids), 'failure', r.n || ' active providers: ' || array_to_string(r.sample, ' | '),
        'expected', 'Every active provider has a usable website that matches its registered identity',
        'source', 'provider-identity-check', 'validation_layer', 'V4', 'root_cause_class', 'data', 'workstream', 'G',
        'evidence', jsonb_build_object('root_cause', 'provider_' || r.check_code, 'providers', r.n, 'findings_table', 'pipeline.provider_identity_findings')),
        'provider-identity-check'))->>'action');
    end loop;
  end if;

  v_inv := security.provider_identity_investigate_v1();
  v_life := security.provider_lifecycle_propose_v1();
  select count(*) into v_n from pg_temp.g_found where run = v_t0;
  return jsonb_build_object('findings', v_n, 'by_check', v_by, 'issues', v_issues, 'investigations', v_inv, 'lifecycle', v_life,
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $$;
revoke all on function security.provider_identity_check_v1() from public, anon, authenticated;
comment on function security.provider_identity_check_v1() is 'CF-247 ops G: job provider-identity-check: provider website and identity findings from stored data (pipeline.provider_identity_findings), one integration issue per finding kind, investigations and lifecycle proposals';

-- 5. investigations: the platform's evidence, candidates, verification; never applied -----------------------------------------------------
create or replace function security.provider_identity_evidence_v1(p_provider uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- CF-247 ops G: what the platform already holds about a provider's identity and site: register rows, stored home-page snapshots, website
  -- checks, and the contact email domain (recorded, marked as not evidence of a website)
  select coalesce(jsonb_agg(e order by e->>'kind', e->>'at'), '[]'::jsonb) from (
    select jsonb_build_object('kind', 'register', 'ref', 'catalogue.provider_registrations:' || pr.id, 'scheme', pr.registration_scheme, 'code', pr.registration_code,
             'status', pr.status, 'valid_to', pr.valid_to, 'at', pr.checked_at, 'source_id', pr.source_id, 'evidence_id', pr.evidence_id) e
      from catalogue.provider_registrations pr where pr.provider_id = p_provider
    union all
    select jsonb_build_object('kind', 'register_source', 'ref', 'pipeline.sources:' || s.id, 'label', s.label, 'url', s.url, 'at', s.last_success_at,
             'note', 'the provider record (and its website) came from this register')
      from catalogue.providers p join pipeline.sources s on s.id = p.canonical_source_id where p.id = p_provider
    union all
    select jsonb_build_object('kind', 'stored_snapshot', 'ref', 'pipeline.evidence_artifacts:' || a.id, 'url', a.source_url, 'at', a.captured_at,
             'path', a.storage_path, 'content_hash', a.content_hash, 'review_state', a.review_state,
             'note', 'a stored page read from the recorded address; not reviewed, so not verification on its own')
      from pipeline.evidence_artifacts a where a.metadata->>'provider_id' = p_provider::text and a.evidence_type = 'layer2_html_snapshot'
    union all
    select jsonb_build_object('kind', 'website_check', 'ref', 'pipeline.provider_website_checks:' || c.id, 'url', c.url, 'action', c.action, 'verdict', c.verdict,
             'why', c.why, 'at', c.checked_at, 'register_site', c.result->>'register_site', 'final_url', c.result->>'final_url', 'cricos_on_site', c.result->'cricos_on_site')
      from pipeline.provider_website_checks c where c.provider_id = p_provider
    union all
    select jsonb_build_object('kind', 'contact_email', 'ref', 'catalogue.providers.email', 'domain', split_part(p.email, '@', 2),
             'note', 'a contact email domain is not evidence of a website; a site is never derived from it')
      from catalogue.providers p where p.id = p_provider and p.email like '%@%') z
$$;
revoke all on function security.provider_identity_evidence_v1(uuid) from public, anon, authenticated;
comment on function security.provider_identity_evidence_v1(uuid) is 'CF-247 ops G: the platform''s stored evidence of a provider''s identity and site (register, register source, snapshots, website checks; the contact email domain marked as not evidence)';

create or replace function security.provider_identity_investigate_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G: opens one investigation per provider with an open website or identity finding, refreshes its evidence and candidates, and
-- settles it: proposed when the platform's own site check verified a candidate that is not the recorded website, otherwise blocked_evidence.
-- Stored candidates (register site, redirect final address) are checked only with identity.candidate_check_on. Nothing is corrected here.
declare v_open int := 0; v_prop int := 0; v_block int := 0; v_q int := 0; v_closed int := 0; r record; v_cand jsonb; v_ver record;
begin
  if security.pipeline_num_v1('identity.investigate_on', 0) < 1 then return jsonb_build_object('skipped', 'identity.investigate_on is 0'); end if;
  -- open
  with o as (
    insert into pipeline.provider_identity_investigations(provider_id, opened_for, recorded_website, reason)
    select f.provider_id, array_agg(f.check_code order by f.check_code), max(p.website), string_agg(f.reason, '; ' order by f.check_code)
      from pipeline.provider_identity_findings f join catalogue.providers p on p.id = f.provider_id
     where f.state = 'open' and f.check_code in ('website_malformed', 'identity_unconfirmed', 'domain_shared', 'redirected_or_parked')
       and not exists (select 1 from pipeline.provider_identity_investigations i where i.provider_id = f.provider_id and i.state in ('open', 'blocked_evidence', 'proposed'))
     group by f.provider_id
    on conflict do nothing returning 1)
  select count(*) into v_open from o;
  -- closed: the findings cleared (the website was corrected) -> corrected; the provider left the catalogue -> closed
  with c as (
    update pipeline.provider_identity_investigations i set state = case when p.lifecycle_status = 'active' then 'corrected' else 'closed' end,
           closed_at = now(), updated_at = now(), close_note = case when p.lifecycle_status = 'active' then 'The findings cleared: the website now ' || coalesce(p.website, '(none)') else 'The provider is ' || p.lifecycle_status end
      from catalogue.providers p
     where p.id = i.provider_id and i.state in ('open', 'blocked_evidence', 'proposed')
       and (p.lifecycle_status <> 'active' or not exists (select 1 from pipeline.provider_identity_findings f where f.provider_id = i.provider_id and f.state = 'open'
                                                            and f.check_code in ('website_malformed', 'identity_unconfirmed', 'domain_shared', 'redirected_or_parked')))
    returning 1)
  select count(*) into v_closed from c;
  -- evidence, candidates and settlement
  for r in select i.id, i.provider_id, i.candidates, p.website from pipeline.provider_identity_investigations i join catalogue.providers p on p.id = i.provider_id
            where i.state in ('open', 'blocked_evidence', 'proposed') loop
    -- stored candidates: the register's site, a redirect's final address (never an email domain); a person's candidates are kept as entered
    select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into v_cand from (
      select x from jsonb_array_elements(r.candidates) x
      union
      select jsonb_build_object('url', c.result->>'register_site', 'provenance', 'register', 'ref', 'pipeline.provider_website_checks:' || c.id)
        from pipeline.provider_website_checks c where c.provider_id = r.provider_id and nullif(c.result->>'register_site', '') is not null
      union
      select jsonb_build_object('url', c.result->>'final_url', 'provenance', 'redirect', 'ref', 'pipeline.provider_website_checks:' || c.id)
        from pipeline.provider_website_checks c where c.provider_id = r.provider_id and coalesce((c.result->>'redirected')::boolean, false)
         and nullif(c.result->>'final_url', '') is not null and security.website_refusal_v1(c.result->>'final_url') is null) z
     where security.provider_identity_domain_v1(x->>'url') is distinct from security.provider_identity_domain_v1(r.website) or security.website_refusal_v1(r.website) is not null;
    -- verified: the platform's own site check of a candidate's domain, verdict verified (CRICOS code on the home page, or the register's site)
    select c.id, c.url, c.verdict, c.why, c.checked_at, c.result into v_ver from pipeline.provider_website_checks c
     where c.provider_id = r.provider_id and c.state = 'done' and c.verdict = 'verified'
       and security.provider_identity_domain_v1(coalesce(nullif(c.result->>'final_url', ''), c.url)) in (select security.provider_identity_domain_v1(x->>'url') from jsonb_array_elements(v_cand) x)
     order by c.checked_at desc nulls last limit 1;
    if v_ver.id is not null then
      update pipeline.provider_identity_investigations set state = 'proposed', candidates = v_cand, evidence = security.provider_identity_evidence_v1(r.provider_id), updated_at = now(),
             verification = jsonb_build_object('check_id', v_ver.id, 'url', coalesce(nullif(v_ver.result->>'final_url', ''), v_ver.url), 'verdict', v_ver.verdict, 'why', v_ver.why,
                                               'checked_at', v_ver.checked_at, 'how_to_correct', 'Platform Admin: Adapter builder › website › change to this address (public.admin_provider_website_check change); the site is checked again before it is saved')
       where id = r.id and (state <> 'proposed' or verification->>'check_id' is distinct from v_ver.id::text);
      if found then v_prop := v_prop + 1; end if;
    else
      update pipeline.provider_identity_investigations set state = 'blocked_evidence', candidates = v_cand, evidence = security.provider_identity_evidence_v1(r.provider_id), updated_at = now(),
             verification = jsonb_build_object('verified', false, 'why', case when jsonb_array_length(v_cand) = 0 then 'No candidate site with provenance: the register record and stored evidence give none; a person adds one with its source'
                                                                           else 'No candidate site has been verified by the platform''s site check (CRICOS code on the home page or the register''s site)' end)
       where id = r.id and (state <> 'blocked_evidence' or candidates <> v_cand or verification is null);
      if found then v_block := v_block + 1; end if;
      -- stored candidates checked by the existing website check (a worker read; never saves a website): only with identity.candidate_check_on
      if security.pipeline_num_v1('identity.candidate_check_on', 0) >= 1 and v_q < security.pipeline_num_v1('identity.candidate_checks_per_run', 5)
         and not exists (select 1 from pipeline.provider_website_checks c where c.provider_id = r.provider_id and c.state <> 'done') then
        insert into pipeline.provider_website_checks(provider_id, url, action, reason)
        select r.provider_id, x->>'url', 'check', left('Identity investigation ' || r.id || ': candidate from ' || (x->>'provenance') || ' (' || (x->>'ref') || ')', 400)
          from jsonb_array_elements(v_cand) x
         where x->>'provenance' in ('register', 'redirect')
           and not exists (select 1 from pipeline.provider_website_checks c where c.provider_id = r.provider_id and c.url = x->>'url')
         limit 1;
        if found then v_q := v_q + 1; end if;
      end if;
    end if;
    v_ver := null;
  end loop;
  if v_q > 0 then perform security.provider_website_check_kick_v1(); end if;
  return jsonb_build_object('opened', v_open, 'proposed', v_prop, 'blocked_evidence', v_block, 'candidate_checks_queued', v_q, 'closed', v_closed);
end $$;
revoke all on function security.provider_identity_investigate_v1() from public, anon, authenticated;
comment on function security.provider_identity_investigate_v1() is 'CF-247 ops G: provider identity investigations: open, evidence, candidates with provenance, settle (proposed when the platform''s site check verified a candidate; else blocked_evidence); never corrects';

-- 6. lifecycle: plan, propose, execute, reverse ----------------------------------------------------------------------------------------------
create or replace function security.provider_lifecycle_plan_v1(p_event bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
-- CF-247 ops G: the reviewed cascade plan of a lifecycle event: what each related record does, with counts (read-only)
declare e pipeline.provider_lifecycle_events; v_p uuid[]; v_retire boolean; v_items jsonb;
begin
  select * into e from pipeline.provider_lifecycle_events where id = p_event;
  if not found then raise exception 'lifecycle event % not found', p_event; end if;
  v_retire := e.transition <> 'temporarily_unavailable';
  v_p := case when e.scope = 'provider' then array[e.provider_id]
              else coalesce((select array_agg(p.id) from catalogue.providers p where p.country_id = e.country_id and p.lifecycle_status = 'active'), '{}') end;
  v_items := jsonb_build_array(
    jsonb_build_object('key', 'providers', 'count', cardinality(v_p),
      'effect', case when v_retire then 'Archived through the existing archive (security.provider_archive_apply_v1): lifecycle archived, unpublished; restored by reversal'
                     else 'Kept active and published (an outage is not retirement); new onboarding and plan work waits until the event is reversed' end),
    jsonb_build_object('key', 'consumer_projection', 'count', (select count(*) from catalogue.providers p where p.id = any (v_p) and p.publication_status = 'published'),
      'effect', case when v_retire then 'Hidden from the website, Zoho and search through the existing hide (security.provider_hidden_v1) and a search refresh; no consumer API object changes'
                     else 'No change' end),
    jsonb_build_object('key', 'courses', 'count', (select count(*) from catalogue.courses c where c.provider_id = any (v_p) and c.lifecycle_status = 'active'),
      'effect', case when v_retire then 'Hidden with the provider; each keeps its own status, so reversal brings it back as it was' else 'No change' end),
    jsonb_build_object('key', 'scholarships', 'count', (select count(*) from scholarship.scholarships s where s.provider_id = any (v_p) and s.lifecycle_status = 'active'),
      'effect', case when v_retire then 'Hidden with the provider; records kept' else 'No change' end),
    jsonb_build_object('key', 'entry_requirements', 'count', (select count(*) from catalogue.course_entry_requirements r join catalogue.courses c on c.id = r.course_id where c.provider_id = any (v_p))
                                                       + (select count(*) from catalogue.course_english_requirements r join catalogue.courses c on c.id = r.course_id where c.provider_id = any (v_p)),
      'effect', case when v_retire then 'Hidden with their courses; records kept' else 'No change' end),
    jsonb_build_object('key', 'source_mappings', 'count', (select count(*) from pipeline.uni_adapters a where a.provider_id = any (v_p) and a.enabled)
                                                    + (select count(*) from pipeline.course_link_recipes l where l.provider_id = any (v_p) and l.active),
      'effect', case when v_retire then 'Adapter and course link recipe switched off by the archive; switched back on at reversal. Course link searches, scholarship site mapping and provider fact reads stop picking up a hidden provider'
                     else 'Kept; their work waits' end),
    jsonb_build_object('key', 'tasks', 'count', (select count(*) from pipeline.admin_jobs j where j.state in ('queued', 'running', 'paused') and not j.cancel_requested
                                                    and (j.scope = any (array(select x::text from unnest(v_p) x)) or exists (select 1 from jsonb_array_elements_text(coalesce(j.args->'providers', '[]'::jsonb)) a where a = any (array(select x::text from unnest(v_p) x))))),
      'effect', 'Cancelled by request (the task runner closes them; their history is kept); not resumed at reversal, the automatic planner starts new work'),
    jsonb_build_object('key', 'onboarding', 'count', (select count(*) from pipeline.provider_onboarding o where o.provider_id = any (v_p) and o.status not in ('done', 'stopped', 'cancelled')),
      'effect', case when v_retire then 'Stopped (stop reason retired); put back to its previous stage at reversal' else 'Held by security.provider_lifecycle_held_v1 (not started, not stepped)' end),
    jsonb_build_object('key', 'enrichment_plans', 'count', (select count(*) from pipeline.enrich_plan_runs r where r.provider_id = any (v_p) and r.state = 'queued'),
      'effect', case when v_retire then 'Queued plans cancelled; history kept' else 'Queued plans cancelled; the automatic planner proposes again after reversal' end),
    jsonb_build_object('key', 'layer4_items', 'count', (select count(*) from pipeline.layer4_review_items x where x.status = 'pending'
                                                         and ((x.entity_type = 'provider' and x.entity_id = any (v_p))
                                                           or (x.entity_type = 'course' and x.entity_id in (select c.id from catalogue.courses c where c.provider_id = any (v_p)))
                                                           or (x.entity_type = 'scholarship' and x.entity_id in (select s.id from scholarship.scholarships s where s.provider_id = any (v_p))))),
      'effect', case when v_retire then 'Superseded (provider and course items by the archive, scholarship items here); reopened at reversal' else 'Kept: a person can still decide them' end),
    jsonb_build_object('key', 'campuses', 'count', (select count(*) from catalogue.campuses x where x.provider_id = any (v_p)),
      'effect', case when v_retire then 'Hidden with the provider (security.layer4_search_blocked_campuses reads the hide); records kept' else 'No change' end),
    jsonb_build_object('key', 'provider_contacts', 'count', (select count(*) from pipeline.provider_contacts x where x.provider_id = any (v_p) and x.deleted_at is null),
      'effect', case when v_retire then 'Contact records kept with their versions; the contact discovery profile is paused (previous state recorded, put back at reversal)' else 'Contact discovery profile paused while held' end),
    jsonb_build_object('key', 'layer1_references', 'count', (select count(*) from catalogue.provider_registrations pr where pr.provider_id = any (v_p))
                                                       + (select count(*) from catalogue.course_registrations cr join catalogue.courses c on c.id = cr.course_id where c.provider_id = any (v_p)),
      'effect', 'Provider and course registrations are not changed here: the register reconciliation (layer1-register-end-dates) owns them; the event records the register evidence'),
    jsonb_build_object('key', 'aer_records', 'count', (select count(*) from pipeline.aer_gap_findings g where g.provider_id = any (v_p) and g.state is distinct from 'resolved'),
      'effect', case when v_retire then 'AER coverage and outcome registers rebuild without a hidden provider (aer-reconcile, aer-outcome-register); open AER findings are left for their own resolution' else 'No change' end),
    jsonb_build_object('key', 'layer23_work', 'count', (select count(*) from pipeline.field_enrich_items f where f.provider_id = any (v_p) and f.state in ('queued', 'waiting', 'ai', 'leased'))
                                                  + (select count(*) from pipeline.course_link_search s where s.provider_id = any (v_p) and s.state = 'queued'),
      'effect', case when v_retire then 'Pickers skip a hidden provider, so queued Layer 2 and 3 items wait without spending; nothing is deleted' else 'Pickers keep their own gates; tasks are cancelled by request' end),
    jsonb_build_object('key', 'search_projection', 'count', (select count(*) from search.course_documents d where d.provider_id = any (v_p)),
      'effect', case when v_retire then 'Course documents leave the search projection at the next refresh (requested by the archive); verified after execution' else 'No change' end),
    jsonb_build_object('key', 'identity_investigations', 'count', (select count(*) from pipeline.provider_identity_investigations i where i.provider_id = any (v_p) and i.state in ('open', 'blocked_evidence', 'proposed')),
      'effect', case when v_retire then 'Closed by the next identity check (the provider is no longer active)' else 'Kept' end));
  if e.scope = 'country' then
    v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'country_ingestion', 'count', 1,
      'effect', 'The country''s provider, course and scholarship ingestion is switched off (ref.countries flags; previous values recorded and restored at reversal). Student search for the country is left to the Platform Admin.'));
  end if;
  if e.transition = 'merged' then
    v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'successor', 'count', 1, 'provider_id', e.successor_provider_id,
      'effect', 'The successor is recorded; nothing moves to it automatically (courses and scholarships are not re-parented by this event)'));
  end if;
  return jsonb_build_object('event', e.id, 'scope', e.scope, 'transition', e.transition, 'effective_date', e.effective_date, 'evidence_ok', security.provider_lifecycle_evidence_ok_v1(e.evidence),
                            'providers', to_jsonb(v_p[1:50]), 'providers_total', cardinality(v_p), 'items', v_items, 'built_at', now());
end $$;
revoke all on function security.provider_lifecycle_plan_v1(bigint) from public, anon, authenticated;
comment on function security.provider_lifecycle_plan_v1(bigint) is 'CF-247 ops G: the reviewed cascade plan of a lifecycle event (courses, scholarships, entry requirements, source mappings, tasks, onboarding, plans, Layer 4, register, consumer projection); read-only';

create or replace function security.provider_lifecycle_propose_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G: lifecycle events from register evidence (records only) and their plans; existing register archives recorded as executed events
declare v_prop int := 0; v_rec int := 0; v_plan int := 0; v_due int := 0; r record;
begin
  if security.pipeline_num_v1('lifecycle.propose_on', 0) < 1 then return jsonb_build_object('skipped', 'lifecycle.propose_on is 0'); end if;
  -- the existing departure archives (trigger layer1_departure_archive) are executed events with register evidence
  with x as (
    insert into pipeline.provider_lifecycle_events(scope, provider_id, transition, successor_provider_id, effective_date, evidence, source, state, executed_at, execution)
    select 'provider', a.provider_id, case when d.successor_provider_id is not null then 'merged' else 'deregistered' end, d.successor_provider_id,
           (a.archived_at at time zone 'Australia/Sydney')::date,
           jsonb_build_array(jsonb_build_object('kind', 'register', 'ref', 'pipeline.provider_archives:' || a.id, 'note', a.reason)) ||
             coalesce((select jsonb_agg(jsonb_build_object('kind', 'register', 'ref', 'pipeline.layer1_provider_departures:' || d2.id, 'run_id', d2.run_id, 'courses_retired', d2.courses_retired))
                         from pipeline.layer1_provider_departures d2 where d2.provider_id = a.provider_id), '[]'::jsonb),
           'layer1_departure', 'executed', a.archived_at, jsonb_build_object('recorded_from_archive', a.id, 'by', 'trigger layer1_departure_archive')
      from pipeline.provider_archives a
      left join lateral (select d.successor_provider_id from pipeline.layer1_provider_departures d where d.provider_id = a.provider_id order by d.created_at desc limit 1) d on true
     where a.source = 'layer1_departure' and a.restored_at is null
       and not exists (select 1 from pipeline.provider_lifecycle_events e where e.provider_id = a.provider_id and e.execution->>'recorded_from_archive' = a.id::text)
    on conflict do nothing returning 1)
  select count(*) into v_rec from x;
  -- departures waiting review, and ended registrations of active providers: proposed
  with x as (
    insert into pipeline.provider_lifecycle_events(scope, provider_id, transition, successor_provider_id, effective_date, evidence, source)
    select 'provider', z.provider_id, case when z.successor is not null then 'merged' else 'deregistered' end, z.successor, z.eff, z.ev, z.src
      from (select d.provider_id, d.successor_provider_id successor, (d.created_at at time zone 'Australia/Sydney')::date eff, 'layer1_departure' src,
                   jsonb_build_array(jsonb_build_object('kind', 'register', 'ref', 'pipeline.layer1_provider_departures:' || d.id, 'run_id', d.run_id,
                                                        'courses_retired', d.courses_retired, 'note', d.note)) ev
              from pipeline.layer1_provider_departures d join catalogue.providers p on p.id = d.provider_id
             where d.status = 'needs_review' and p.lifecycle_status = 'active'
            union all
            select pr.provider_id, null, coalesce(pr.valid_to, (pr.checked_at at time zone 'Australia/Sydney')::date), 'register_end_date',
                   jsonb_build_array(jsonb_build_object('kind', 'register', 'ref', 'catalogue.provider_registrations:' || pr.id, 'scheme', pr.registration_scheme,
                                                        'code', pr.registration_code, 'status', pr.status, 'valid_to', pr.valid_to, 'checked_at', pr.checked_at))
              from catalogue.provider_registrations pr join catalogue.providers p on p.id = pr.provider_id
             where p.lifecycle_status = 'active' and pr.status = 'ended' and coalesce(pr.valid_to, (pr.checked_at at time zone 'Australia/Sydney')::date) is not null) z
     where not exists (select 1 from pipeline.provider_lifecycle_events e where e.provider_id = z.provider_id and e.scope = 'provider'
                        and e.state in ('proposed', 'planned', 'approved', 'executed'))
       -- a decision stands: the same register evidence rejected or reversed by the Platform Admin is not proposed again (new evidence is)
       and not exists (select 1 from pipeline.provider_lifecycle_events e where e.provider_id = z.provider_id and e.state in ('rejected', 'reversed') and e.evidence @> z.ev)
    on conflict do nothing returning 1)
  select count(*) into v_prop from x;
  -- plans for proposed events
  for r in select id from pipeline.provider_lifecycle_events where state = 'proposed' loop
    update pipeline.provider_lifecycle_events set plan = security.provider_lifecycle_plan_v1(r.id), planned_at = now(), state = 'planned', updated_at = now() where id = r.id;
    v_plan := v_plan + 1;
  end loop;
  -- executed events: downstream consistency recorded (the search refresh is asynchronous, so this is checked again each run until it passes)
  update pipeline.provider_lifecycle_events e set execution = coalesce(e.execution, '{}'::jsonb) || jsonb_build_object('verification', security.provider_lifecycle_verify_v1(e.id)), updated_at = now()
   where e.state = 'executed' and coalesce((e.execution->'verification'->>'passed')::boolean, false) = false;
  -- temporary unavailability due for review: raised, never retired by time
  select count(*) into v_due from pipeline.provider_lifecycle_events e
   where e.transition = 'temporarily_unavailable' and e.state = 'executed'
     and e.effective_date + security.pipeline_num_v1('lifecycle.unavailable_review_days', 14)::int <= (now() at time zone 'Australia/Sydney')::date;
  return jsonb_build_object('proposed', v_prop, 'recorded_executed', v_rec, 'planned', v_plan, 'unavailable_due_review', v_due);
end $$;
revoke all on function security.provider_lifecycle_propose_v1() from public, anon, authenticated;
comment on function security.provider_lifecycle_propose_v1() is 'CF-247 ops G: proposes lifecycle events from register evidence and builds their plans; records existing register archives as executed events; changes no catalogue record';

create or replace function security.provider_lifecycle_execute_v1(p_event bigint, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G: carries out an approved lifecycle event (lifecycle.cascade_on), recording every change for reversal. Never deletes.
declare e pipeline.provider_lifecycle_events; v_p uuid; v_ps uuid[]; v_retire boolean; v_x jsonb := '[]'::jsonb; v_jobs jsonb; v_onb jsonb; v_plans jsonb; v_l4 jsonb; v_arch jsonb; v_c jsonb; v_cp jsonb;
begin
  if security.pipeline_num_v1('lifecycle.cascade_on', 0) < 1 then raise exception 'lifecycle transitions are switched off (lifecycle.cascade_on is 0): the plan is for review only'; end if;
  select * into e from pipeline.provider_lifecycle_events where id = p_event for update;
  if not found then raise exception 'lifecycle event % not found', p_event; end if;
  if e.state <> 'approved' then raise exception 'lifecycle event % is %, not approved by the Platform Admin', p_event, e.state; end if;
  if not security.provider_lifecycle_evidence_ok_v1(e.evidence) then raise exception 'lifecycle event % has no authoritative evidence (register, first-party or admin record)', p_event; end if;
  if e.planned_at is null or e.planned_at < now() - make_interval(hours => security.pipeline_num_v1('lifecycle.plan_max_age_hours', 24)::int) then
    raise exception 'the plan of lifecycle event % is older than lifecycle.plan_max_age_hours: build it again and review it before executing', p_event;
  end if;
  v_retire := e.transition <> 'temporarily_unavailable';
  v_ps := case when e.scope = 'provider' then array[e.provider_id]
               else coalesce((select array_agg(p.id order by p.id) from catalogue.providers p where p.country_id = e.country_id and p.lifecycle_status = 'active'), '{}') end;
  foreach v_p in array v_ps loop
    v_arch := null;
    if v_retire then
      v_arch := security.provider_archive_apply_v1(v_p, 'lifecycle:' || e.transition, left('Lifecycle event ' || e.id || ' (' || e.transition || ', effective ' || e.effective_date || ')', 500), p_actor, false);
    end if;
    with j as (update pipeline.admin_jobs j set cancel_requested = true, updated_at = now()
                where j.state in ('queued', 'running', 'paused') and not j.cancel_requested
                  and (j.scope = v_p::text or coalesce(j.args->'providers', '[]'::jsonb) ? v_p::text)
               returning j.id)
    select coalesce(jsonb_agg(id), '[]'::jsonb) into v_jobs from j;
    v_onb := '[]'::jsonb;
    if v_retire then
      with o as (select ob.id, ob.status, ob.stop_reason from pipeline.provider_onboarding ob where ob.provider_id = v_p and ob.status not in ('done', 'stopped', 'cancelled') for update),
           u as (update pipeline.provider_onboarding ob set status = 'stopped', stop_reason = 'retired', job_id = null, updated_at = now(),
                        note = left('Stopped by lifecycle event ' || e.id || ' (' || e.transition || '); it comes back if the event is reversed.', 500)
                   from o where ob.id = o.id returning o.id, o.status, o.stop_reason)
      select coalesce(jsonb_agg(jsonb_build_object('id', id, 'status', status, 'stop_reason', stop_reason)), '[]'::jsonb) into v_onb from u;
    end if;
    with x as (update pipeline.enrich_plan_runs r set state = 'cancelled', updated_at = now(), finished_at = now(),
                      actual = coalesce(r.actual, '{}'::jsonb) || jsonb_build_object('outcome', 'not_needed', 'cancelled_by', 'lifecycle event ' || e.id)
                where r.provider_id = v_p and r.state = 'queued' returning r.id)
    select coalesce(jsonb_agg(id), '[]'::jsonb) into v_plans from x;
    v_l4 := '[]'::jsonb;
    if v_retire then
      with i as (update pipeline.layer4_review_items x set status = 'superseded', decided_at = now()
                  where x.status = 'pending' and x.entity_type = 'scholarship' and x.entity_id in (select s.id from scholarship.scholarships s where s.provider_id = v_p)
                 returning x.id)
      select coalesce(jsonb_agg(id), '[]'::jsonb) into v_l4 from i;
    end if;
    with c as (update pipeline.provider_contact_profiles x set paused = true, updated_at = now() where x.provider_id = v_p and not coalesce(x.paused, false) returning x.id)
    select coalesce(jsonb_agg(id), '[]'::jsonb) into v_cp from c;
    v_x := v_x || jsonb_build_array(jsonb_build_object('provider_id', v_p, 'archive', v_arch, 'tasks_cancel_requested', v_jobs, 'onboarding_stopped', v_onb,
                                                       'plans_cancelled', v_plans, 'scholarship_reviews_superseded', v_l4, 'contact_profiles_paused', v_cp));
  end loop;
  v_c := null;
  if e.scope = 'country' then
    select jsonb_build_object('provider_ingestion_enabled', c.provider_ingestion_enabled, 'course_ingestion_enabled', c.course_ingestion_enabled,
                              'scholarship_ingestion_enabled', c.scholarship_ingestion_enabled) into v_c from ref.countries c where c.id = e.country_id;
    update ref.countries set provider_ingestion_enabled = false, course_ingestion_enabled = false, scholarship_ingestion_enabled = false, updated_at = now() where id = e.country_id;
  end if;
  update pipeline.provider_lifecycle_events set state = 'executed', executed_at = now(), executed_by = p_actor, updated_at = now(),
         execution = jsonb_build_object('providers', v_x, 'country_before', v_c)
   where id = p_event;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('provider', 'lifecycle_execute', coalesce(e.provider_id, e.country_id)::text, jsonb_build_object('event', e.id, 'transition', e.transition, 'providers', cardinality(v_ps)), p_actor);
  return jsonb_build_object('event', e.id, 'state', 'executed', 'providers', cardinality(v_ps));
end $$;
revoke all on function security.provider_lifecycle_execute_v1(bigint, uuid) from public, anon, authenticated;
comment on function security.provider_lifecycle_execute_v1(bigint, uuid) is 'CF-247 ops G: carries out an approved lifecycle event with lifecycle.cascade_on, through the existing archive; every change recorded for reversal; never deletes';

create or replace function security.provider_lifecycle_reverse_v1(p_event bigint, p_actor uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G: reverses an executed lifecycle event from its recorded changes (restore through the existing restore)
declare e pipeline.provider_lifecycle_events; x jsonb; o jsonb; v_n int := 0;
begin
  select * into e from pipeline.provider_lifecycle_events where id = p_event for update;
  if not found then raise exception 'lifecycle event % not found', p_event; end if;
  if e.state <> 'executed' then raise exception 'lifecycle event % is %, not executed', p_event, e.state; end if;
  if length(btrim(coalesce(p_note, ''))) < 4 then raise exception 'a reason is required'; end if;
  for x in select * from jsonb_array_elements(coalesce(e.execution->'providers', '[]'::jsonb)) loop
    if x->'archive'->>'status' = 'archived' then
      perform security.provider_restore_v1((x->>'provider_id')::uuid, left('Lifecycle event ' || e.id || ' reversed: ' || p_note, 500), p_actor, false);
    end if;
    for o in select * from jsonb_array_elements(coalesce(x->'onboarding_stopped', '[]'::jsonb)) loop
      update pipeline.provider_onboarding set status = o->>'status', stop_reason = o->>'stop_reason', updated_at = now(),
             note = left('Lifecycle event ' || e.id || ' reversed; carrying on.', 500)
       where id = (o->>'id')::uuid and status = 'stopped' and stop_reason = 'retired';
    end loop;
    update pipeline.layer4_review_items set status = 'pending', decided_at = null
     where status = 'superseded' and id in (select (v #>> '{}')::uuid from jsonb_array_elements(coalesce(x->'scholarship_reviews_superseded', '[]'::jsonb)) v);
    update pipeline.provider_contact_profiles set paused = false, updated_at = now()
     where paused and id in (select (v #>> '{}')::uuid from jsonb_array_elements(coalesce(x->'contact_profiles_paused', '[]'::jsonb)) v);
    v_n := v_n + 1;
  end loop;
  -- recorded executions of the departure trigger are reversed through the same restore
  if e.execution ? 'recorded_from_archive' then
    perform security.provider_restore_v1(e.provider_id, left('Lifecycle event ' || e.id || ' reversed: ' || p_note, 500), p_actor, false);
    v_n := 1;
  end if;
  if e.scope = 'country' and e.execution->'country_before' is not null then
    update ref.countries set provider_ingestion_enabled = (e.execution->'country_before'->>'provider_ingestion_enabled')::boolean,
           course_ingestion_enabled = (e.execution->'country_before'->>'course_ingestion_enabled')::boolean,
           scholarship_ingestion_enabled = (e.execution->'country_before'->>'scholarship_ingestion_enabled')::boolean, updated_at = now()
     where id = e.country_id;
  end if;
  update pipeline.provider_lifecycle_events set state = 'reversed', reversed_at = now(), reversed_by = p_actor, reverse_note = left(p_note, 500), updated_at = now() where id = p_event;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('provider', 'lifecycle_reverse', coalesce(e.provider_id, e.country_id)::text, jsonb_build_object('event', e.id, 'transition', e.transition, 'providers', v_n, 'note', p_note), p_actor);
  return jsonb_build_object('event', e.id, 'state', 'reversed', 'providers', v_n);
end $$;
revoke all on function security.provider_lifecycle_reverse_v1(bigint, uuid, text) from public, anon, authenticated;
comment on function security.provider_lifecycle_reverse_v1(bigint, uuid, text) is 'CF-247 ops G: reverses an executed lifecycle event from its recorded changes (existing restore; onboarding, scholarship reviews and country flags put back)';

create or replace function security.provider_lifecycle_verify_v1(p_event bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- CF-247 ops G (mandate 15:52 §12, "verify downstream consistency"): after execution, a retired provider is hidden, out of the search projection,
  -- has no active work (tasks not cancelled, working onboarding, queued plans) and no pending Layer 4 item; a held provider is only held.
  with e as (select * from pipeline.provider_lifecycle_events where id = p_event),
  p as (select (x->>'provider_id')::uuid id from e, jsonb_array_elements(coalesce(e.execution->'providers', '[]'::jsonb)) x
        union select e.provider_id from e where e.execution ? 'recorded_from_archive'),
  m as (select
          (select count(*) from p where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)) not_hidden,
          (select count(*) from search.course_documents d where d.provider_id in (select id from p)) in_search,
          (select count(*) from pipeline.admin_jobs j where j.state in ('queued', 'running', 'paused') and not j.cancel_requested
             and (j.scope in (select id::text from p) or exists (select 1 from jsonb_array_elements_text(coalesce(j.args->'providers', '[]'::jsonb)) a where a in (select id::text from p)))) active_tasks,
          (select count(*) from pipeline.provider_onboarding o where o.provider_id in (select id from p) and o.status not in ('done', 'stopped', 'cancelled')) working_onboarding,
          (select count(*) from pipeline.enrich_plan_runs r where r.provider_id in (select id from p) and r.state = 'queued') queued_plans,
          (select count(*) from pipeline.layer4_review_items x where x.status = 'pending'
             and ((x.entity_type = 'provider' and x.entity_id in (select id from p))
               or (x.entity_type = 'course' and x.entity_id in (select c.id from catalogue.courses c where c.provider_id in (select id from p)))
               or (x.entity_type = 'scholarship' and x.entity_id in (select s.id from scholarship.scholarships s where s.provider_id in (select id from p))))) pending_reviews)
  select jsonb_build_object('event', p_event, 'state', (select state from e), 'transition', (select transition from e),
           'passed', case when (select state from e) <> 'executed' then null
                          when (select transition from e) = 'temporarily_unavailable' then m.active_tasks = 0 and m.queued_plans = 0
                          else m.not_hidden = 0 and m.in_search = 0 and m.active_tasks = 0 and m.working_onboarding = 0 and m.queued_plans = 0 and m.pending_reviews = 0 end,
           'measure', to_jsonb(m), 'at', now())
    from m
$$;
revoke all on function security.provider_lifecycle_verify_v1(bigint) from public, anon, authenticated;
comment on function security.provider_lifecycle_verify_v1(bigint) is 'CF-247 ops G: downstream consistency after a lifecycle execution (hidden, out of search, no active work, no pending review); recorded by the identity job';

create or replace function security.provider_lifecycle_remedy_cascade_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- passed: every executed lifecycle event of the issue's providers verifies (security.provider_lifecycle_verify_v1)
  with v as (select security.provider_lifecycle_verify_v1(e.id) r from pipeline.provider_lifecycle_events e
              where e.state = 'executed' and e.provider_id = any (coalesce((select provider_ids from pipeline.integration_issues where id = p_issue), '{}')))
  select jsonb_build_object('passed', coalesce(bool_and(coalesce((r->>'passed')::boolean, false)), false), 'measure', jsonb_build_object('executed', count(*),
                            'verified', count(*) filter (where (r->>'passed')::boolean)), 'evidence', coalesce(jsonb_agg(r), '[]'::jsonb))
    from v
$$;
revoke all on function security.provider_lifecycle_remedy_cascade_verify_v1(bigint) from public, anon, authenticated;

-- 7. admin RPCs (no new screen: the operations report and the Integration Controller read these) --------------------------------------------
create or replace function public.admin_provider_lifecycle(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G: lifecycle events: list and plan (Curator and above); propose with authoritative evidence (PIM Operator and above); approve,
-- reject, execute and reverse (Platform Admin). Execute also needs lifecycle.cascade_on.
declare v_rank int := coalesce(security.current_role_rank(), 0); v_id bigint := nullif(p_args->>'event', '')::bigint; v_note text := nullif(btrim(coalesce(p_args->>'note', '')), ''); v_new bigint;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return coalesce((select jsonb_agg(to_jsonb(e) - 'plan' order by e.created_at desc) from (select * from pipeline.provider_lifecycle_events order by created_at desc limit 200) e), '[]'::jsonb);  -- fixed: a screen page
  elsif p_action = 'plan' then
    return security.provider_lifecycle_plan_v1(v_id);
  elsif p_action = 'propose' then
    if v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
    if not security.provider_lifecycle_evidence_ok_v1(p_args->'evidence') then raise exception 'authoritative evidence is required: a register record, a first-party page or an admin record, each with a reference'; end if;
    insert into pipeline.provider_lifecycle_events(scope, provider_id, country_id, transition, successor_provider_id, effective_date, evidence, source)
    values (coalesce(p_args->>'scope', 'provider'), nullif(p_args->>'provider_id', '')::uuid, nullif(p_args->>'country_id', '')::uuid, p_args->>'transition',
            nullif(p_args->>'successor_provider_id', '')::uuid, (p_args->>'effective_date')::date,
            p_args->'evidence' || jsonb_build_array(jsonb_build_object('kind', 'admin_record', 'ref', 'auth.users:' || auth.uid(), 'at', now(), 'note', v_note)), 'admin')
    returning id into v_new;
    update pipeline.provider_lifecycle_events set plan = security.provider_lifecycle_plan_v1(v_new), planned_at = now(), state = 'planned' where id = v_new;
    return jsonb_build_object('event', v_new, 'state', 'planned');
  elsif p_action in ('approve', 'reject', 'execute', 'reverse', 'replan') then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if p_action = 'replan' then
      update pipeline.provider_lifecycle_events set plan = security.provider_lifecycle_plan_v1(v_id), planned_at = now(), updated_at = now() where id = v_id and state in ('planned', 'approved');
      return jsonb_build_object('event', v_id, 'replanned', found);
    elsif p_action in ('approve', 'reject') then
      if length(coalesce(v_note, '')) < 4 then raise exception 'a reason is required'; end if;
      update pipeline.provider_lifecycle_events set state = case when p_action = 'approve' then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_at = now(),
             decision_note = v_note, updated_at = now()
       where id = v_id and state = 'planned';
      if not found then raise exception 'only a planned event can be approved or rejected'; end if;
      insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('provider', 'lifecycle_' || p_action, v_id::text, jsonb_build_object('note', v_note), auth.uid());
      return jsonb_build_object('event', v_id, 'state', case when p_action = 'approve' then 'approved' else 'rejected' end);
    elsif p_action = 'execute' then
      return security.provider_lifecycle_execute_v1(v_id, auth.uid());
    else
      return security.provider_lifecycle_reverse_v1(v_id, auth.uid(), v_note);
    end if;
  end if;
  raise exception 'unknown action %', p_action;
end $$;
revoke all on function public.admin_provider_lifecycle(text, jsonb) from public, anon;
grant execute on function public.admin_provider_lifecycle(text, jsonb) to authenticated;
comment on function public.admin_provider_lifecycle(text, jsonb) is 'CF-247 ops G: provider and country lifecycle events: list, plan, propose (with authoritative evidence), approve, reject, execute (lifecycle.cascade_on), reverse';

create or replace function public.admin_provider_identity(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G: provider identity findings and investigations (Curator and above); a candidate site with its provenance (PIM Operator and above)
-- is checked by the existing website check, which never saves a website; close (Platform Admin)
declare v_rank int := coalesce(security.current_role_rank(), 0); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_url text := btrim(coalesce(p_args->>'url', ''));
        v_src text := nullif(btrim(coalesce(p_args->>'source', '')), ''); v_id bigint;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'summary' then
    return jsonb_build_object(
      'findings', (select coalesce(jsonb_object_agg(check_code, n), '{}'::jsonb) from (select check_code, count(*) n from pipeline.provider_identity_findings where state = 'open' group by 1) z),
      'investigations', (select coalesce(jsonb_object_agg(state, n), '{}'::jsonb) from (select state, count(*) n from pipeline.provider_identity_investigations group by 1) z),
      'lifecycle', (select coalesce(jsonb_object_agg(state, n), '{}'::jsonb) from (select state, count(*) n from pipeline.provider_lifecycle_events group by 1) z));
  elsif p_action = 'provider' then
    return jsonb_build_object('findings', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) from pipeline.provider_identity_findings f where f.provider_id = v_pid),
                              'investigations', (select coalesce(jsonb_agg(to_jsonb(i) order by i.opened_at desc), '[]'::jsonb) from pipeline.provider_identity_investigations i where i.provider_id = v_pid),
                              'evidence', security.provider_identity_evidence_v1(v_pid));
  elsif p_action = 'candidate' then
    if v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
    if security.website_refusal_v1(v_url) is not null or v_url = '' then raise exception 'enter one full web address starting with https://'; end if;
    if length(coalesce(v_src, '')) < 8 then raise exception 'say where the candidate comes from (a register entry or a first-party page), not how it was guessed'; end if;
    select id into v_id from pipeline.provider_identity_investigations where provider_id = v_pid and state in ('open', 'blocked_evidence', 'proposed');
    if v_id is null then raise exception 'no open identity investigation for this provider'; end if;
    update pipeline.provider_identity_investigations set candidates = candidates || jsonb_build_array(jsonb_build_object('url', v_url, 'provenance', 'person', 'ref', v_src, 'by', auth.uid(), 'at', now())),
           updated_at = now() where id = v_id;
    -- the existing website check (Curator and above, one at a time per provider) reads the candidate; it never saves a website
    return jsonb_build_object('investigation', v_id, 'check', public.admin_provider_website_check('check', jsonb_build_object('provider_id', v_pid, 'url', v_url)));
  elsif p_action = 'close' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    update pipeline.provider_identity_investigations set state = 'closed', closed_at = now(), closed_by = auth.uid(), close_note = left(coalesce(p_args->>'note', ''), 500), updated_at = now()
     where id = (p_args->>'investigation')::bigint and state in ('open', 'blocked_evidence', 'proposed');
    return jsonb_build_object('closed', found);
  end if;
  raise exception 'unknown action %', p_action;
end $$;
revoke all on function public.admin_provider_identity(text, jsonb) from public, anon;
grant execute on function public.admin_provider_identity(text, jsonb) to authenticated;
comment on function public.admin_provider_identity(text, jsonb) is 'CF-247 ops G: provider identity findings and investigations; a candidate site with its provenance goes to the existing website check (never saved here)';

-- 8. remedies for workstream A's controller ---------------------------------------------------------------------------------------------------
create or replace function security.provider_identity_remedy_investigate_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G (auto remedy provider_identity_investigate): opens and settles identity investigations for the issue's providers (records only)
declare v_before int; v_after int; v_ids uuid[]; v_r jsonb;
begin
  select provider_ids into v_ids from pipeline.integration_issues where id = p_issue;
  select count(*) into v_before from pipeline.provider_identity_investigations where provider_id = any (coalesce(v_ids, '{}')) and state in ('open', 'blocked_evidence', 'proposed');
  v_r := security.provider_identity_investigate_v1();
  select count(*) into v_after from pipeline.provider_identity_investigations where provider_id = any (coalesce(v_ids, '{}')) and state in ('open', 'blocked_evidence', 'proposed');
  return jsonb_build_object('ok', true, 'changed', v_after <> v_before or coalesce((v_r->>'proposed')::int, 0) > 0, 'evidence', v_r || jsonb_build_object('open_before', v_before, 'open_after', v_after));
end $$;
revoke all on function security.provider_identity_remedy_investigate_v1(bigint) from public, anon, authenticated;

create or replace function security.provider_identity_remedy_investigate_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- passed: every provider of the issue has an investigation (open, blocked by evidence with its evidence, or proposed) or no open finding
  with i as (select coalesce(provider_ids, '{}') ids from pipeline.integration_issues where id = p_issue),
  m as (select x id, exists (select 1 from pipeline.provider_identity_investigations v where v.provider_id = x and v.state in ('blocked_evidence', 'proposed', 'corrected', 'closed')) settled,
               exists (select 1 from pipeline.provider_identity_findings f where f.provider_id = x and f.state = 'open') open_finding
          from i, unnest(i.ids) x)
  select jsonb_build_object('passed', coalesce(bool_and(settled or not open_finding), true),
                            'measure', jsonb_build_object('providers', count(*), 'settled', count(*) filter (where settled), 'unsettled', count(*) filter (where open_finding and not settled)),
                            'evidence', 'pipeline.provider_identity_investigations')
    from m
$$;
revoke all on function security.provider_identity_remedy_investigate_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.provider_onboarding_remedy_stop_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G (auto remedy provider_onboarding_stop_invalid_website): an onboarding row of the issue's providers still in a working stage with a
-- refused website stops with needs_source_discovery (the IQ-00063 rule, applied now); it carries on by itself once the website is corrected
declare v_ids uuid[]; v_n int;
begin
  select provider_ids into v_ids from pipeline.integration_issues where id = p_issue;
  update pipeline.provider_onboarding ob set status = 'stopped', stop_reason = 'needs_source_discovery', job_id = null, updated_at = now(),
         note = left('The recorded website (' || pv.website || ') cannot be used: ' || security.website_refusal_v1(pv.website) || '. An identity investigation holds the evidence; onboarding carries on by itself once the website is corrected.', 500)
    from catalogue.providers pv
   where pv.id = ob.provider_id and ob.provider_id = any (coalesce(v_ids, '{}')) and security.website_refusal_v1(pv.website) is not null
     and ob.status in ('queued', 'website', 'course_pages', 'waiting_courses');
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'changed', v_n > 0, 'evidence', jsonb_build_object('onboarding_stopped', v_n));
end $$;
revoke all on function security.provider_onboarding_remedy_stop_v1(bigint) from public, anon, authenticated;

create or replace function security.provider_onboarding_remedy_stop_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- passed: no onboarding row of the issue's providers is in a working stage with a refused website
  select jsonb_build_object('passed', count(*) = 0, 'measure', jsonb_build_object('looping_rows', count(*)), 'evidence', 'pipeline.provider_onboarding')
    from pipeline.provider_onboarding ob join catalogue.providers pv on pv.id = ob.provider_id
   where ob.provider_id = any (coalesce((select provider_ids from pipeline.integration_issues where id = p_issue), '{}'))
     and security.website_refusal_v1(pv.website) is not null and ob.status in ('queued', 'website', 'course_pages', 'waiting_courses')
$$;
revoke all on function security.provider_onboarding_remedy_stop_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.provider_lifecycle_remedy_plan_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops G (auto remedy provider_lifecycle_plan): proposes lifecycle events from register evidence and builds their plans (records only)
declare v_r jsonb;
begin
  v_r := security.provider_lifecycle_propose_v1();
  return jsonb_build_object('ok', true, 'changed', coalesce((v_r->>'proposed')::int, 0) + coalesce((v_r->>'planned')::int, 0) + coalesce((v_r->>'recorded_executed')::int, 0) > 0, 'evidence', v_r);
end $$;
revoke all on function security.provider_lifecycle_remedy_plan_v1(bigint) from public, anon, authenticated;

create or replace function security.provider_lifecycle_remedy_plan_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- passed: every provider of the issue with a register change has a lifecycle event with a plan (or a decision)
  with i as (select coalesce(provider_ids, '{}') ids from pipeline.integration_issues where id = p_issue),
  m as (select x id, exists (select 1 from pipeline.provider_lifecycle_events e where e.provider_id = x and e.state in ('planned', 'approved', 'executed', 'rejected', 'reversed')) planned
          from i, unnest(i.ids) x)
  select jsonb_build_object('passed', coalesce(bool_and(planned), true), 'measure', jsonb_build_object('providers', count(*), 'planned', count(*) filter (where planned)),
                            'evidence', 'pipeline.provider_lifecycle_events')
    from m
$$;
revoke all on function security.provider_lifecycle_remedy_plan_verify_v1(bigint) from public, anon, authenticated;

select security.ops_root_cause_register_v1(c, s) from (values
 ('provider_website_malformed', '{"class": "data", "title": "A provider''s recorded website is not a site address", "description": "The website has a user part (as an email address does), no domain name, spaces, or is not http or https; usually copied from the register record. Onboarding and page finding cannot use it.", "detect": {"job": "provider-identity-check", "check": "website_malformed", "table": "pipeline.provider_identity_findings"}}'::jsonb),
 ('provider_identity_unconfirmed', '{"class": "data", "title": "A provider''s website does not match its registered identity", "description": "The register lists another site, or the domain fits neither the name nor the contact email domain and no site check verified it.", "detect": {"job": "provider-identity-check", "check": "identity_unconfirmed"}}'::jsonb),
 ('provider_domain_shared', '{"class": "data", "title": "A domain is recorded for unrelated providers", "description": "Two providers with no shared name word or initials have the same registrable domain: one of them may have another provider''s site.", "detect": {"job": "provider-identity-check", "check": "domain_shared"}}'::jsonb),
 ('provider_redirected_or_parked', '{"class": "data", "title": "A provider''s website redirects elsewhere or is parked", "description": "Stored evidence (a website check, a scholarship site mapping) ended on another domain, or the home page is a parked-domain page.", "detect": {"job": "provider-identity-check", "check": "redirected_or_parked"}}'::jsonb),
 ('provider_register_changed', '{"class": "data", "title": "The register changed for an active provider", "description": "A registration ended, a register departure waits review, or the register code differs from the provider''s key. A lifecycle event is proposed with the register evidence; nothing retires without the Platform Admin.", "detect": {"job": "provider-identity-check", "check": "register_changed"}}'::jsonb),
 ('provider_onboarding_loop_invalid_website', '{"class": "rule", "title": "Onboarding goes round on an unusable website", "description": "An onboarding row moves between the website and course-page stages because the website cannot be used (IQ-00063).", "detect": {"table": "pipeline.provider_onboarding", "rule": "working stage and security.website_refusal_v1 not null"}}'::jsonb)
) v(c, s);

select security.ops_remedy_register_v1(c, s) from (values
 ('provider_identity_investigate', '{"title": "Open and settle provider identity investigations", "treats": ["provider_website_malformed", "provider_identity_unconfirmed", "provider_domain_shared", "provider_redirected_or_parked"], "authority": "auto", "action_fn": "security.provider_identity_remedy_investigate_v1(bigint)", "verify_fn": "security.provider_identity_remedy_investigate_verify_v1(bigint)", "max_attempts_key": "identity.remedy_max_attempts", "cooldown_key": "identity.remedy_cooldown_minutes", "notes": "Records only: evidence, candidates with provenance, verified or blocked_evidence. Never corrects a website."}'::jsonb),
 ('provider_onboarding_stop_invalid_website', '{"title": "Stop onboarding on an unusable website", "treats": ["provider_onboarding_loop_invalid_website", "provider_website_malformed"], "authority": "auto", "action_fn": "security.provider_onboarding_remedy_stop_v1(bigint)", "verify_fn": "security.provider_onboarding_remedy_stop_verify_v1(bigint)", "max_attempts_key": "identity.remedy_max_attempts", "cooldown_key": "identity.remedy_cooldown_minutes", "notes": "Stops waste only; onboarding carries on by itself once the website is corrected."}'::jsonb),
 ('provider_lifecycle_plan', '{"title": "Propose lifecycle events from register evidence and plan them", "treats": ["provider_register_changed"], "authority": "auto", "action_fn": "security.provider_lifecycle_remedy_plan_v1(bigint)", "verify_fn": "security.provider_lifecycle_remedy_plan_verify_v1(bigint)", "max_attempts_key": "identity.remedy_max_attempts", "cooldown_key": "identity.remedy_cooldown_minutes", "notes": "Records only: an event and its reviewed cascade plan. Execution is the admin remedy provider_lifecycle_cascade."}'::jsonb),
 ('provider_website_correction', '{"title": "Correct a provider website from verified evidence", "treats": ["provider_website_malformed", "provider_identity_unconfirmed", "provider_domain_shared", "provider_redirected_or_parked"], "authority": "admin", "notes": "Platform Admin: an investigation in state proposed names the verified site; change it through Adapter builder › website (public.admin_provider_website_check change), which checks the site again before saving. Never automatic."}'::jsonb),
 ('provider_lifecycle_cascade', '{"title": "Carry out a reviewed provider or country lifecycle transition", "treats": ["provider_register_changed"], "authority": "admin", "verify_fn": "security.provider_lifecycle_remedy_cascade_verify_v1(bigint)", "notes": "Platform Admin: public.admin_provider_lifecycle approve then execute (needs lifecycle.cascade_on); reverse undoes it from the recorded changes."}'::jsonb)
) v(c, s);

-- 9. onboarding waits while a provider is held as temporarily unavailable ---------------------------------------------------------------------
select pg_temp.edit_once('security.provider_onboarding_tick_v1()', '181fc3dd2d78930c32e70cc24fb0adbd', 'ccae12038a32dd95f3644dfc3e5a3b5f', array[
 [$o$  for o in select q.id from pipeline.provider_onboarding q where q.status = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
$o$,
  $n$  for o in select q.id from pipeline.provider_onboarding q where q.status = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and not security.provider_lifecycle_held_v1(q.provider_id)  -- CF-247 ops G: held as temporarily unavailable (an executed lifecycle event) waits
$n$],
 [$o$            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = ob.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
$o$,
  $n$            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = ob.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and not security.provider_lifecycle_held_v1(ob.provider_id)  -- CF-247 ops G: held as temporarily unavailable (an executed lifecycle event) waits
$n$]
]::text[][], array[1, 1]);

-- 10. job, catalogue and component register ----------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('provider-identity-check', 'Platform upkeep', 92, 'Check provider websites and identities',
  'Hourly (identity.check_on): tests every active provider from stored data only for a malformed website, a website that does not match its registered identity, a domain shared with an unrelated provider, a redirect or parked domain, and a register change (pipeline.provider_identity_findings); raises one integration issue per kind; opens identity investigations with the platform''s own evidence (verified only by the platform''s site check; corrections go to the Platform Admin); proposes lifecycle events from register evidence with a reviewed cascade plan (executed only on a Platform Admin decision with lifecycle.cascade_on). Reads no page and calls no model.',
  4, false, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'provider-identity-check') then
    perform cron.schedule('provider-identity-check', '16 * * * *', $c$select security.provider_identity_check_v1()$c$);
  end if;
end $j$;
update pipeline.automation_catalogue set description = description || ' A provider held as temporarily unavailable by an executed lifecycle event is neither started nor stepped.'
 where jobname = 'provider-onboarding' and description not like '%temporarily unavailable%';

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.provider_identity_findings', 'Layer 1', 'Platform upkeep', 'Provider website and identity findings (open, cleared)', 'active', '{}', '20261104060000'),
 ('table', 'pipeline.provider_identity_investigations', 'Layer 1', 'Platform upkeep', 'Provider identity investigations: evidence, candidates, verification', 'active', '{}', '20261104060000'),
 ('table', 'pipeline.provider_lifecycle_events', 'Layer 1', 'Platform upkeep', 'Reversible provider and country lifecycle transitions with evidence and plan', 'active', '{}', '20261104060000'),
 ('job', 'provider-identity-check', 'Layer 1', 'Platform upkeep', 'Provider website and identity check; investigations; lifecycle proposals', 'active', '{}', '20261104060000'),
 ('function', 'security.provider_identity_check_v1', 'Layer 1', 'Platform upkeep', 'Job provider-identity-check', 'active', '{}', '20261104060000'),
 ('function', 'security.provider_identity_investigate_v1', 'Layer 1', 'Platform upkeep', 'Identity investigations: open, evidence, settle', 'active', '{}', '20261104060000'),
 ('function', 'security.provider_identity_evidence_v1', 'Layer 1', 'Platform upkeep', 'Stored evidence of a provider''s identity and site', 'active', '{}', '20261104060000'),
 ('function', 'security.provider_lifecycle_plan_v1', 'Layer 1', 'Platform upkeep', 'Reviewed cascade plan of a lifecycle event', 'active', '{}', '20261104060000'),
 ('function', 'security.provider_lifecycle_propose_v1', 'Layer 1', 'Platform upkeep', 'Lifecycle events from register evidence', 'active', '{}', '20261104060000'),
 ('function', 'security.provider_lifecycle_execute_v1', 'Layer 1', 'Platform upkeep', 'Carries out an approved lifecycle event (lifecycle.cascade_on)', 'active', '{}', '20261104060000'),
 ('function', 'security.provider_lifecycle_reverse_v1', 'Layer 1', 'Platform upkeep', 'Reverses an executed lifecycle event', 'active', '{}', '20261104060000'),
 ('function', 'public.admin_provider_lifecycle', 'Layer 1', 'Platform upkeep', 'Lifecycle events: list, plan, propose, decide, execute, reverse', 'active', '{}', '20261104060000'),
 ('function', 'public.admin_provider_identity', 'Layer 1', 'Platform upkeep', 'Identity findings and investigations; candidate sites', 'active', '{}', '20261104060000')
on conflict do nothing;

-- 11. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and (key like 'identity.%' or key like 'lifecycle.%')) < 15 then
    raise exception 'ops G post-check: a setting is missing'; end if;
  if (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'lifecycle.cascade_on') <> 0
     and not exists (select 1 from pipeline.provider_lifecycle_events where state = 'executed' and source <> 'layer1_departure') then
    raise exception 'ops G post-check: lifecycle.cascade_on must ship 0'; end if;
  if security.provider_lifecycle_evidence_ok_v1('[{"kind": "ai", "ref": "x"}]'::jsonb) or not security.provider_lifecycle_evidence_ok_v1('[{"kind": "register", "ref": "x"}]'::jsonb) then
    raise exception 'ops G post-check: evidence rule'; end if;
  if security.provider_identity_domain_v1('https://www.newgen.edu.au/courses') <> 'newgen.edu.au' then raise exception 'ops G post-check: domain'; end if;
  if (select count(*) from pipeline.ops_remedies where code in ('provider_identity_investigate', 'provider_onboarding_stop_invalid_website', 'provider_lifecycle_plan', 'provider_website_correction', 'provider_lifecycle_cascade')) <> 5 then
    raise exception 'ops G post-check: remedies'; end if;
end $$;
