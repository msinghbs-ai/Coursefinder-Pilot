-- CF-247 F-PDESC (Platform Admin decision 9 Nov 2026, "All-Provider Autonomous Description Delivery": approved source-verified machine admission, Tiers 1 to 4; data population mandate 9 Nov 2026).
--
-- What this adds (everything is OFF until the Platform Admin sets pdesc.machine_admit_on to 1 through Settings, with a reason):
--   1. A scoped, audited machine admission path for a provider's FIRST description: security.provider_description_machine_admit_v1(item). It does not call the human Layer 4
--      decision procedure (security.layer4_review_decide_impl, security.layer4_provider_description_apply_impl) and does not run a bulk UPDATE: one provider, one item, one
--      transaction. The item is settled under the system automation account (Decision 263) with the machine rule recorded in the decision, the control event and
--      pipeline.provider_description_machine_admissions (before and after text, evidence, tier, rule). It is never recorded as a human decision.
--   2. The objective rule (pdesc-machine-v1): provider live, in scope and not locked; no description yet; no earlier human rejection; no open identity finding; identity, evidence
--      lineage and per-sentence quote support proved again at admission (tiers 1 to 3, the same checks the human path makes); no claim, ranking, accreditation, outcome, campus,
--      scholarship, visa or promotional word (English and French lists), no page markup (&#039;), no figure, a usable provider name (not N/A, NA ...) (settings pdesc.machine_*). A proposal that
--      fails waits for a person in Layer 4 while there is room (pdesc.machine_pending_max) or is HELD with the whole proposal and the exact reason; it is never dropped.
--   3. Tier 4, registry_factual: a deterministic profile built only from the provider record, its active register listing (stored evidence) and its active catalogue offerings, with
--      every sentence tied to its facts; too thin a record leaves an explicit insufficient_verified_facts hold. No AI call and no page read.
--   4. Auto-settlement of the existing waiting Layer 4 provider-description items under the same rule (the rest stay waiting for a person, with the reason written on the item).
--   5. Withdrawal: security.provider_description_machine_withdraw_v1(provider, reason, person) restores the earlier text of one provider (refused if a person changed it since or a hand lock was added;
--      the row is read back after the update) and keeps the audit; it names the person, and re-queues the search refresh on the admission's own decision (production allows one signal for each
--      decision). The Platform Admin (rank 6) calls it through public.admin_provider_description_machine_withdraw_v1.
--   6. A read-only parity and scoreboard report (Website and Zoho read-back) and a throughput function (remaining, observed rate, share per country) used by the reader.
--   7. pdesc.provider_types: an EMPTY list now means every type, including providers with no type (all 1,130 Canadian providers have none); the token 'unclassified' selects them
--      alone. A list setting may carry a minimum number of values (min_value); pdesc.provider_keys and pdesc.provider_types carry 0, so they can be saved empty as their help says.
--   8. QA B2 (performance at 3,103 providers): an index beside catalogue.providers on the website host (the identity check compared every provider, 130 ms a call), a table of when each provider
--      was last looked at (rotation), two cheap helpers (About-page patterns, stored-copy candidate), and a funnel that counts identity and the stored page in one pass above pdesc.funnel_detail_max.
--   9. QA N-items: a provider the rule must not describe (lock, earlier rejection, withdrawn, cleared by hand, open finding, placeholder or marked-up name) is found by one function, security.provider_description_machine_blocked_v1.
-- Nothing is switched on here: pdesc.machine_admit_on, pdesc.registry_factual_on stay 0; no job, schedule, ceiling or existing setting value changes (pdesc.ai_usd_max, pdesc.firecrawl_reads_max,
-- pdesc.pending_max are untouched). The consumer API (G3) is not read for shape or changed: parity only calls the existing website_v2_provider and zoho_v2_provider.
--
-- Live definitions this change edits (read 9 Nov 2026, project fxcwkweaxjtknorudmwp), md5 of the function body (pg_proc.prosrc) before -> after. The body md5 is the same on PostgreSQL 16 (the test database) and 17 (live); the live bodies were compared to the test database's:
--   security.provider_description_scope_v1(uuid) 71075d22096ac3f28306aa7544a04ad0 -> 1c645431787b5b96ea13d2c06ed7234e
--   public.admin_provider_description_funnel_v1() 0db4ef39b72f23454a668b6c9a2d37d9 -> bb1ef5da87aabd6578de903f5eadcb56
--   public.admin_toolsets_write(text,jsonb) 50aaa7aeb76353c3f8d02cef552462ed -> 3254892aa756c95385187bb75adba5cf
-- Replaces: the type test in security.provider_description_scope_v1 and in the funnel (an empty list = every type; 'unclassified' = no type), and the list branch of public.admin_toolsets_write (honours min_value)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_scope_v1(uuid)'), ('security.provider_description_identity_v1(uuid,text)'), ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'),
                                 ('security.provider_description_approved_lineage_v1(uuid,text)'), ('security.provider_description_identity_snapshot_v1(uuid)'), ('security.pipeline_num_v1(text,numeric)'),
                                 ('security.toolset_setting(text,text)'), ('security.pdesc_has_term_v1(text,text)'), ('public.website_v2_provider(text)'), ('public.zoho_v2_provider(text)'),
                                 ('security.provider_description_publication_check_v1()'), ('security.provider_lifecycle_held_v1(uuid)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.layer4_decisions') is null or to_regclass('pipeline.search_refresh_signals') is null or to_regclass('catalogue.provider_registrations') is null
     or to_regclass('pipeline.admin_control_events') is null or to_regclass('pipeline.provider_identity_findings') is null then raise exception 'a table this change relies on is missing'; end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- guarded editing of live definitions
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17; the header lines pg_get_functiondef prints can differ between versions
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then
    raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- tables
create table if not exists pipeline.provider_description_machine_admissions (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  review_item_id uuid references pipeline.layer4_review_items(id),
  read_id uuid references pipeline.provider_description_reads(id),
  tier text not null check (tier in ('stored', 'direct', 'firecrawl', 'registry_factual')),
  rule text not null,
  outcome text not null check (outcome in ('admitted', 'declined', 'withdrawn')),
  reason text,
  before_description text,
  after_description text,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  source_url text,
  source_hash text,
  facts jsonb not null default '[]'::jsonb,
  checks jsonb not null default '{}'::jsonb,
  actor uuid not null,
  created_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  withdrawn_by uuid,
  withdrawn_reason text
);
comment on table pipeline.provider_description_machine_admissions is 'CF-247 F-PDESC (Platform Admin decision 9 Nov 2026): one row for each provider description the machine rule admitted (before and after text, tier, evidence, source hash, facts, actor, rule, withdrawal) and each Layer 4 provider-description item it declined (the exact reason). Written only by security.provider_description_machine_admit_v1, _withdraw_v1 and _settle_pending_v1; read by the scoreboard. The record of what the platform admitted without a person.';
create unique index if not exists provider_description_machine_admissions_live_uq on pipeline.provider_description_machine_admissions (provider_id) where outcome = 'admitted' and withdrawn_at is null;
create unique index if not exists provider_description_machine_admissions_declined_uq on pipeline.provider_description_machine_admissions (review_item_id) where outcome = 'declined';
create index if not exists provider_description_machine_admissions_provider_idx on pipeline.provider_description_machine_admissions (provider_id, created_at desc);
alter table pipeline.provider_description_machine_admissions enable row level security;
revoke all on pipeline.provider_description_machine_admissions from public, anon, authenticated;

create table if not exists pipeline.provider_description_registry_templates (
  scheme text primary key,
  register_sentence text not null,
  active boolean not null default true,
  note text
);
comment on table pipeline.provider_description_registry_templates is 'CF-247 F-PDESC Tier 4 (registry_factual): the one sentence that states a provider''s listing on a register, by registration scheme ({name} and {code} are filled from the verified register row). No wording for a scheme means no registry profile for it. Reviewed with the PR that adds a scheme; read only by security.provider_description_registry_profile_v1.';
alter table pipeline.provider_description_registry_templates enable row level security;
revoke all on pipeline.provider_description_registry_templates from public, anon, authenticated;

-- QA B2: the reader looks at a bounded slice of providers a run and remembers which it looked at, so every provider is looked at in turn and no run scans the whole catalogue
create table if not exists pipeline.provider_description_scan_marks (
  provider_id uuid primary key references catalogue.providers(id),
  scanned_at timestamptz not null default now(),
  last_reason text
);
comment on table pipeline.provider_description_scan_marks is 'CF-247 F-PDESC QA B2: when the description reader last looked at a provider as a candidate (one row each). The reader looks at the providers looked at least recently first, a bounded number a run (pdesc.scan_factor, pdesc.scan_max), so a provider that cannot be read yet rotates to the back and the rest are reached. Written only by security.provider_description_enqueue_v1.';
alter table pipeline.provider_description_scan_marks enable row level security;
revoke all on pipeline.provider_description_scan_marks from public, anon, authenticated;

-- QA B2: the other-provider host test in security.provider_description_identity_v1 compared every active provider's host (about 130 ms a call at 3,103 providers, a quarter of a second in the funnel for each); this index answers it from the host. An index beside the table: no column, row or function the consumer API reads changes (G3).
create index if not exists providers_site_host_active_idx on catalogue.providers ((security.site_host_v1(website))) where lifecycle_status = 'active';
comment on index catalogue.providers_site_host_active_idx is 'CF-247 F-PDESC QA B2: lookup of active providers by website host (security.site_host_v1), used by the provider identity check. Added beside the table; nothing the consumer API reads changes.';
insert into pipeline.provider_description_registry_templates (scheme, register_sentence, note) values
  ('cricos', '{name} is listed on the Commonwealth Register of Institutions and Courses for Overseas Students (CRICOS) with provider code {code}.', 'Australia: CRICOS provider code'),
  ('nzqa', '{name} appears in the New Zealand Qualifications Authority (NZQA) provider listing with provider number {code}.', 'New Zealand: NZQA provider number'),
  ('ircc_dli', '{name} appears on the Immigration, Refugees and Citizenship Canada list of designated learning institutions with DLI number {code}.', 'Canada: IRCC designated learning institution number')
on conflict (scheme) do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- settings (G2; defaults are the safe state: machine admission off)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pdesc.machine_admit_on', 'Provider descriptions: automatic admission (source-verified)',
  '1: a provider''s FIRST description that passes the objective rule (identity, per-sentence quote support, no promotional, ranking, accreditation, outcome, campus, scholarship or visa claim, no figure, no lock, no earlier human rejection) is admitted by the machine rule pdesc-machine-v1 and recorded as a machine decision, not a person''s. Anything else is held with its exact reason. 0: every description waits for a person in Layer 4. Off until the Platform Admin switches it on.',
  'number', '0'::jsonb, 0, 1, 'on/off', 994, 'Provider descriptions', 'security.provider_description_machine_admit_v1, public.svc_provider_description_record, security.provider_description_fire_v1', 'CF-247 F-PDESC (Platform Admin decision 9 Nov 2026): constrained machine admission, default off'),
 ('pipeline', 'pdesc.registry_factual_on', 'Provider descriptions: register-fact profile (tier 4)',
  '1: a provider whose official page cannot be read (no website, no About page, robots.txt, page not read) gets a short profile built only from its verified register listing, provider record and active catalogue courses, tagged registry_factual. 0: never. Needs automatic admission to be on as well.',
  'number', '0'::jsonb, 0, 1, 'on/off', 995, 'Provider descriptions', 'security.provider_description_registry_tier_v1', 'CF-247 F-PDESC (Platform Admin decision 9 Nov 2026): tier 4 default off'),
 ('pipeline', 'pdesc.registry_after_rules', 'Provider descriptions: reads that move on to the register-fact profile',
  'A provider whose latest read was held with one of these rules (or went to the dead letter list) has no readable official page and may get the register-fact profile. A provider with no website and no stored page also qualifies.',
  'list', '["no_website", "no_about_page", "home_not_read", "about_not_read", "robots_disallowed", "wrong_host"]'::jsonb, 0, null, 'rules', 996, 'Provider descriptions', 'security.provider_description_registry_tier_v1', 'CF-247 F-PDESC: which source outcomes are final enough for tier 4'),
 ('pipeline', 'pdesc.registry_min_facts', 'Provider descriptions: register-fact profile needs at least',
  'Verified facts a register-fact profile needs (type, location, register listing, course levels, course fields). Fewer: the provider is held with insufficient_verified_facts instead of a thin description.',
  'number', '3'::jsonb, 2, 8, 'facts', 997, 'Provider descriptions', 'security.provider_description_registry_profile_v1', 'CF-247 F-PDESC: no meaningless profile to meet a count'),
 ('pipeline', 'pdesc.registry_offerings_max', 'Provider descriptions: register-fact profile names at most',
  'Course levels and fields of study named in a register-fact profile (each at most this many).',
  'number', '3'::jsonb, 1, 6, 'names', 998, 'Provider descriptions', 'security.provider_description_registry_profile_v1', 'CF-247 F-PDESC: short, neutral profiles'),
 ('pipeline', 'pdesc.registry_per_run', 'Provider descriptions: register-fact profiles a run',
  'At most this many providers get a register-fact profile in one run of the reader.',
  'number', '25'::jsonb, 1, 500, 'providers', 999, 'Provider descriptions', 'security.provider_description_registry_tier_v1', 'CF-247 F-PDESC: bounded work a run'),
 ('pipeline', 'pdesc.machine_settle_per_run', 'Provider descriptions: waiting items settled a run',
  'At most this many description items already waiting in Layer 4 are checked against the automatic rule each run (those that pass are admitted as machine decisions; the rest stay for a person).',
  'number', '10'::jsonb, 1, 200, 'items', 1000, 'Provider descriptions', 'security.provider_description_machine_settle_pending_v1', 'CF-247 F-PDESC: auto-settlement of existing items, bounded'),
 ('pipeline', 'pdesc.machine_refused_words', 'Provider descriptions: extra words that stop automatic admission',
  'On top of the claim, marketing and campus/scholarship/guarantee word lists, a description with one of these words is never admitted by the machine rule (finance, visa and availability claims need their own verified source). A person can still decide it in Layer 4.',
  'list', '["visa", "visas", "migration", "immigration", "fee", "fees", "tuition", "funding", "loan", "loans", "bursary", "bursaries", "scholarships", "pathway", "pathways", "guaranteed", "accredited", "partner", "partners", "partnership", "campuses"]'::jsonb, 0, null, 'words', 1001, 'Provider descriptions', 'security.pdesc_machine_text_check_v1', 'CF-247 F-PDESC: finance, visa and availability claims are not machine-admitted'),
 ('pipeline', 'pdesc.machine_numbers_allowed', 'Provider descriptions: figures allowed in an automatic description',
  '0: a description with a number other than a four-digit year (a count, a percentage, an amount) is never admitted by the machine rule. 1: figures that the quote supports are allowed.',
  'number', '0'::jsonb, 0, 1, 'on/off', 1002, 'Provider descriptions', 'security.pdesc_machine_text_check_v1', 'CF-247 F-PDESC: no unverified figure'),
 ('pipeline', 'pdesc.target_hours', 'Provider descriptions: aim to clear the remaining providers within',
  'Sizes the queue from the providers still to do: remaining / (hours / minutes between runs). Used only with automatic admission on.',
  'number', '12'::jsonb, 1, 168, 'hours', 1003, 'Provider descriptions', 'security.provider_description_throughput_v1', 'CF-247 F-PDESC: throughput from remaining and observed rate, not a fixed batch'),
 ('pipeline', 'pdesc.queue_cap', 'Provider descriptions: most queued a run (automatic mode)',
  'The most providers added to the read list in one run when automatic admission is on (the older cap, providers queued a run, still applies when it is off).',
  'number', '60'::jsonb, 1, 500, 'providers', 1004, 'Provider descriptions', 'security.provider_description_throughput_v1, security.provider_description_selection_v1', 'CF-247 F-PDESC: bounded queue growth'),
 ('pipeline', 'pdesc.dispatch_max', 'Provider descriptions: worker calls at once',
  'The most worker calls sent in one run (each reads up to the providers-a-run setting). Concurrency is also bounded by the AI spend still available.',
  'number', '3'::jsonb, 1, 10, 'calls', 1005, 'Provider descriptions', 'security.provider_description_fire_v1', 'CF-247 F-PDESC: bounded parallel dispatch'),
 ('pipeline', 'pdesc.backlog_hours', 'Provider descriptions: keep queued ahead for',
  'The queue is kept to about this many hours of the observed reading rate (and never below two full worker rounds), so it does not grow faster than it can be read.',
  'number', '2'::jsonb, 1, 24, 'hours', 1006, 'Provider descriptions', 'security.provider_description_throughput_v1', 'CF-247 F-PDESC: queue sized from the observed rate'),
 ('pipeline', 'pdesc.rate_window_hours', 'Provider descriptions: observed rate over',
  'The reading rate is measured over this many past hours.',
  'number', '3'::jsonb, 1, 48, 'hours', 1007, 'Provider descriptions', 'security.provider_description_throughput_v1, public.svc_provider_description_next', 'CF-247 F-PDESC: observed rate window'),
 ('pipeline', 'pdesc.concurrency_max', 'Provider descriptions: reads in progress at most (automatic mode)',
  'Providers leased to a worker and not yet recorded, at most. With automatic admission on, this replaces the Layer 4 waiting cap as the limit on work in progress.',
  'number', '12'::jsonb, 1, 100, 'reads', 1008, 'Provider descriptions', 'public.svc_provider_description_next', 'CF-247 F-PDESC: concurrency bounded'),
 ('pipeline', 'pdesc.read_cost_floor_usd', 'Provider descriptions: cost allowed for a read before it starts',
  'No more reads are leased than the AI spend still available divides into at this cost (or the observed average cost of a read, if higher). Used only with automatic admission on.',
  'number', '0.003'::jsonb, 0.0001, 1, 'US$', 1009, 'Provider descriptions', 'public.svc_provider_description_next', 'CF-247 F-PDESC: concurrency bounded by spend'),
 ('pipeline', 'pdesc.machine_pending_max', 'Provider descriptions: declined descriptions waiting for a person at most (automatic mode)',
  'With automatic admission on, the old waiting cap (providers waiting in Layer 4) no longer stops the reader. A description that fails the automatic rule is kept as a waiting Layer 4 item for a person only while fewer than this many such items wait; beyond that it is HELD with the full proposal and the exact reason, never dropped, and is not counted as waiting. A description that passes is admitted at once and never waits.',
  'number', '200'::jsonb, 0, 5000, 'items', 1010, 'Provider descriptions', 'public.svc_provider_description_record, public.svc_provider_description_next', 'CF-247 F-PDESC QA N3: the waiting cap is replaced by a bounded one for declined items'),
 ('pipeline', 'pdesc.founded_year_min', 'Provider descriptions: earliest year allowed in an automatic description',
  'A four-digit year earlier than this (or later than the current year) counts as a figure and stops automatic admission; a year in range is allowed.',
  'number', '1800'::jsonb, 1000, 2000, 'year', 1011, 'Provider descriptions', 'security.pdesc_machine_text_check_v1', 'CF-247 F-PDESC QA N1: no value in code'),
 ('pipeline', 'pdesc.queue_floor_runs', 'Provider descriptions: queue kept for at least this many worker rounds',
  'The queue is never kept below this many full rounds of worker calls (providers a call x worker calls at once x this number), however low the observed rate.',
  'number', '2'::jsonb, 1, 10, 'rounds', 1012, 'Provider descriptions', 'security.provider_description_throughput_v1', 'CF-247 F-PDESC QA N1: no value in code'),
 ('pipeline', 'pdesc.report_detail', 'Provider descriptions: rows listed in the scoreboard',
  'The most mismatched providers the acceptance scoreboard lists.',
  'number', '20'::jsonb, 1, 200, 'rows', 1013, 'Provider descriptions', 'security.provider_description_machine_report_v1', 'CF-247 F-PDESC QA N1: no value in code'),
 ('pipeline', 'pdesc.city_min_chars', 'Provider descriptions: shortest city name rewritten from capitals',
  'A register-fact profile writes an all-capitals city name in normal capitals when the name has at least this many letters (shorter names such as NSW or ACT stay as they are).',
  'number', '4'::jsonb, 2, 10, 'letters', 1014, 'Provider descriptions', 'security.provider_description_registry_profile_v1', 'CF-247 F-PDESC QA N1: no value in code'),
 ('pipeline', 'pdesc.name_min_chars', 'Provider descriptions: shortest provider name an automatic description may use',
  'A provider whose name (canonical or display) is shorter than this, is a placeholder, or still holds web-page markup (for example &#039;) is never described automatically: its identity proof is not reliable. A person can still decide it.',
  'number', '3'::jsonb, 1, 20, 'letters', 1015, 'Provider descriptions', 'security.pdesc_clean_name_v1', 'CF-247 F-PDESC QA N8: name sanity'),
 ('pipeline', 'pdesc.placeholder_names', 'Provider descriptions: names that are placeholders',
  'A provider name equal to one of these (letters and numbers only, any case) is a placeholder, not a name. Matching ignores punctuation, so N/A and NA are the same entry.',
  'list', '["na", "n a", "none", "null", "nil", "tbc", "tbd", "unknown", "test", "testing", "sample", "undefined", "not available", "not applicable", "no name", "unnamed", "xx", "xxx"]'::jsonb, 0, null, 'names', 1016, 'Provider descriptions', 'security.pdesc_clean_name_v1', 'CF-247 F-PDESC QA N8: placeholder names'),
 ('pipeline', 'pdesc.machine_refused_words_fr', 'Provider descriptions: French words that stop automatic admission',
  'The claim, ranking, outcome, accreditation, scholarship, visa, fee and promotional words for French pages (Canadian providers). Each is listed with and without accents because the check reads letters and numbers only. English pages use the other lists.',
  'list', '["classement", "classements", "meilleur", "meilleure", "meilleurs", "meilleures", "chef de file", "excellence", "prestigieux", "prestigieuse", "reconnu", "reconnue", "renommé", "renomme", "réputé", "repute", "réputée", "reputee", "innovant", "innovante", "unique", "de calibre mondial", "calibre mondial", "classe mondiale", "premier choix", "numéro un", "numero un", "primé", "primée", "récompensé", "recompense", "accrédité", "accredite", "accréditée", "accreditee", "accréditation", "accreditation", "agrément", "agrement", "emploi", "emplois", "employabilité", "employabilite", "diplômés", "diplomes", "salaire", "salaires", "étudiants", "etudiants", "étudiant", "etudiant", "personnel", "bourse", "bourses", "visa", "visas", "immigration", "résidence permanente", "residence permanente", "frais", "scolarité", "scolarite", "financement", "prêt", "prets", "campus", "garanti", "garantie", "garantis", "partenaire", "partenaires", "partenariat", "partenariats"]'::jsonb, 0, null, 'words', 1017, 'Provider descriptions', 'security.pdesc_machine_text_check_v1', 'CF-247 F-PDESC QA N8: French pages'),
 ('pipeline', 'pdesc.scan_factor', 'Provider descriptions: providers looked at for each one queued',
  'When automatic admission is on, the reader looks at this many candidate providers (least recently looked at first) for each provider it needs to queue, instead of every provider. Providers that cannot be read yet rotate to the back, so every provider is looked at in turn.',
  'number', '3'::jsonb, 1, 20, 'x', 1018, 'Provider descriptions', 'security.provider_description_selection_v1, security.provider_description_enqueue_v1', 'CF-247 F-PDESC QA B2: bounded work a run'),
 ('pipeline', 'pdesc.scan_max', 'Provider descriptions: most providers looked at in one country in a run',
  'The most candidate providers looked at for one country in one run of the reader (the scan factor is limited by this).',
  'number', '150'::jsonb, 5, 2000, 'providers', 1019, 'Provider descriptions', 'security.provider_description_selection_v1', 'CF-247 F-PDESC QA B2: bounded work a run'),
 ('pipeline', 'pdesc.funnel_detail_max', 'Provider descriptions: funnel checks each provider up to',
  'The funnel on Settings checks identity and the stored page provider by provider while the providers in the set countries and types number no more than this. Above it the funnel counts them from the register in one pass (the same answer except for the page rule) so the screen stays quick.',
  'number', '400'::jsonb, 10, 20000, 'providers', 1020, 'Provider descriptions', 'public.admin_provider_description_funnel_v1', 'CF-247 F-PDESC QA B2: the screen stays inside its time-out'),
 ('pipeline', 'pdesc.firecrawl_per_call', 'Provider descriptions: Firecrawl reads one worker call may start (automatic mode)',
  'With automatic admission on, each worker call is granted at most this many Firecrawl reads, taken from what the ceiling still allows after the reads other calls hold in flight, so parallel calls can never go past pdesc.firecrawl_reads_max.',
  'number', '5'::jsonb, 0, 50, 'reads', 1021, 'Provider descriptions', 'public.svc_provider_description_next', 'CF-247 F-PDESC QA N4: the Firecrawl ceiling holds under parallel dispatch')
on conflict (toolset_key, key) do nothing;

-- list settings may carry a minimum number of values; the two scope lists that the help says may be empty carry 0
update pipeline.platform_toolset_settings set min_value = 1 where toolset_key = 'pipeline' and key = 'pdesc.countries' and min_value is null;
update pipeline.platform_toolset_settings set min_value = 0,
  help = 'Provider stable keys (for example provider:cricos:00008c). Empty: every provider of the countries and types above. Used for a supervised pilot.'
 where toolset_key = 'pipeline' and key = 'pdesc.provider_keys' and min_value is null;
update pipeline.platform_toolset_settings set min_value = 0,
  help = 'Institution types (ref.provider_types codes) whose providers are read. Empty: every type, including providers with no type yet. The word unclassified selects providers with no type.'
 where toolset_key = 'pipeline' and key = 'pdesc.provider_types' and min_value is null;

-- ----------------------------------------------------------------------------------------------------------------------------------------- scope: type list
create or replace function security.pdesc_type_in_scope_v1(p_code text) returns boolean language sql stable security definer set search_path to '' as $f$
  select jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb)) = 0
      or coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb) ? coalesce(nullif(btrim(p_code), ''), 'unclassified')
$f$;
comment on function security.pdesc_type_in_scope_v1(text) is 'CF-247 F-PDESC: a provider type is in the description reader scope. An empty pdesc.provider_types list is every type; a provider with no type is the token unclassified.';
revoke all on function security.pdesc_type_in_scope_v1(text) from public, anon, authenticated;

select pg_temp.edit_all('security.provider_description_scope_v1(uuid)', '71075d22096ac3f28306aa7544a04ad0', '1c645431787b5b96ea13d2c06ed7234e',
array[
$old$       and coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb) ? coalesce(t.code, '')
$old$],
array[
$new$       and security.pdesc_type_in_scope_v1(t.code)
$new$]);

select pg_temp.edit_all('public.admin_provider_description_funnel_v1()', '0db4ef39b72f23454a668b6c9a2d37d9', 'bb1ef5da87aabd6578de903f5eadcb56',
array[
$old$             and coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb) ? coalesce(t.code, '') policy_scope
$old$,
$old$        v_stall text; v_policy int; v_run int; v_spent numeric; v_fc numeric;
$old$,
$old$  with base as (
$old$,
$old$    select b.*, case when b.live and b.policy_scope then security.provider_description_scope_v1(b.id) end run_scope,
$old$,
$old$           case when b.live and b.policy_scope then coalesce((security.provider_description_identity_v1(b.id, b.website)->>'ok')::boolean, false) end identity_ok,
$old$,
$old$           case when b.live and b.policy_scope then security.provider_description_stored_v1(b.id) is not null end stored_page,
$old$,
$old$  v_sel := security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', v_size, 'mode', case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then 'approved' else 'stored' end));
$old$,
$old$                  when v_pending >= v_pmax then 'review_full'
$old$],
array[
$new$             and security.pdesc_type_in_scope_v1(t.code) policy_scope
$new$,
$new$        v_stall text; v_policy int; v_run int; v_spent numeric; v_fc numeric; v_big boolean; v_pat text[];
$new$,
$new$  -- many providers in scope (QA B2): identity and the stored page are counted from the register in one pass instead of provider by provider, so the screen stays inside its time-out
  select count(*) > security.pipeline_num_v1('pdesc.funnel_detail_max', 400) into v_big from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
   where p.lifecycle_status = 'active' and coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb) ? k.iso_alpha2::text and security.pdesc_type_in_scope_v1(t.code);
  v_pat := security.pdesc_about_like_patterns_v1();
  with base as (
$new$,
$new$    select b.*, case when b.live and b.policy_scope then case when v_big and jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb)) = 0 then true else security.provider_description_scope_v1(b.id) end end run_scope,
$new$,
$new$           case when b.live and b.policy_scope then case when v_big then b.has_site and not exists (select 1 from pipeline.provider_identity_findings f where f.provider_id = b.id and f.state = 'open')
                                                                           and not exists (select 1 from catalogue.providers o where o.id <> b.id and o.lifecycle_status = 'active' and security.site_host_v1(o.website) = security.site_host_v1(b.website))
                                                 else coalesce((security.provider_description_identity_v1(b.id, b.website)->>'ok')::boolean, false) end end identity_ok,
$new$,
$new$           case when b.live and b.policy_scope then case when v_big then security.provider_description_stored_candidate_v1(b.id, v_pat) else security.provider_description_stored_v1(b.id) is not null end end stored_page,
$new$,
$new$  v_sel := security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'prefilter', v_big, 'size', v_size, 'mode', case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then 'approved' else 'stored' end));
$new$,
$new$                  when v_pending >= v_pmax and security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then 'review_full'
$new$]);

-- the list branch of the governed settings write honours a minimum number of values (min_value); a list with no minimum is unchanged
select pg_temp.edit_all('public.admin_toolsets_write(text,jsonb)', '50aaa7aeb76353c3f8d02cef552462ed', '3254892aa756c95385187bb75adba5cf',
array[
$old$      if jsonb_typeof(v_val) <> 'array' then raise exception 'a list is needed'; end if;
$old$],
array[
$new$      if jsonb_typeof(v_val) <> 'array' then raise exception 'a list is needed'; end if;
      if v_set.min_value is not null and jsonb_array_length(v_val) < v_set.min_value then raise exception 'give at least % value(s)', v_set.min_value; end if;
$new$]);

-- ----------------------------------------------------------------------------------------------------------------------------------------- helpers: names, About-page patterns, blocked providers
create or replace function security.pdesc_clean_name_v1(p_name text) returns text language sql stable security definer set search_path to '' as $f$
  -- a usable provider name, or null: not empty, no web-page markup (&#039; &amp;), not a placeholder (N/A, NA, TBC ...), at least pdesc.name_min_chars letters or digits
  select case when nullif(btrim(p_name), '') is null then null
              when btrim(p_name) ~* '&#?[a-z0-9]{1,8};' then null
              when length(regexp_replace(btrim(p_name), '[^[:alnum:]]+', '', 'g')) < security.pipeline_num_v1('pdesc.name_min_chars', 3) then null
              when exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.placeholder_names'), '[]'::jsonb)) w
                            where regexp_replace(lower(w), '[^a-z0-9]+', '', 'g') <> '' and regexp_replace(lower(w), '[^a-z0-9]+', '', 'g') = regexp_replace(lower(btrim(p_name)), '[^a-z0-9]+', '', 'g')) then null
              else btrim(p_name) end
$f$;
comment on function security.pdesc_clean_name_v1(text) is 'CF-247 F-PDESC QA N8: a provider name the automatic rule can rely on (not empty, not a placeholder such as N/A or NA, no web-page markup such as &#039;, long enough), or null. The placeholder list and the length are settings.';
revoke all on function security.pdesc_clean_name_v1(text) from public, anon, authenticated;

create or replace function security.pdesc_about_like_patterns_v1() returns text[] language sql stable security definer set search_path to '' as $f$
  -- the same address patterns security.provider_description_stored_v1 starts from (an About page name or prefix as a path part), escaped for LIKE
  select array(select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) t
               union all
               select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) t where t <> '')
$f$;
comment on function security.pdesc_about_like_patterns_v1() is 'CF-247 F-PDESC QA B2: the LIKE patterns of the About-page address rule (pdesc.about_patterns and pdesc.about_prefixes), the first step of security.provider_description_stored_v1, as one list.';
revoke all on function security.pdesc_about_like_patterns_v1() from public, anon, authenticated;

create or replace function security.provider_description_stored_candidate_v1(p_provider uuid, p_patterns text[]) returns boolean language sql stable cost 10 security definer set search_path to '' as $f$
  -- a necessary condition of security.provider_description_stored_v1, in one index probe: a stored, recent copy whose address looks like an About page. The page rule and host proof still run later, on the few providers that pass.
  select exists (select 1 from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id = s.id
                  where s.provider_id = p_provider and a.storage_path is not null and a.source_url ~* '^https?://'
                    and lower(a.source_url) like any (p_patterns)
                    and coalesce(a.captured_at, a.created_at) > now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int))
$f$;
comment on function security.provider_description_stored_candidate_v1(uuid, text[]) is 'CF-247 F-PDESC QA B2: true when the provider has a stored, recent page copy whose address matches the given About-page patterns (security.pdesc_about_like_patterns_v1, passed in so they are read once; the cheap first half of security.provider_description_stored_v1; it never says yes to a provider the full rule would refuse for the address, and the page rule runs afterwards).';
revoke all on function security.provider_description_stored_candidate_v1(uuid, text[]) from public, anon, authenticated;

create or replace function security.provider_description_machine_blocked_v1(p_provider uuid) returns jsonb language plpgsql stable cost 500 security definer set search_path to '' as $f$
declare p catalogue.providers%rowtype; v_find text;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null then return jsonb_build_object('rule', 'provider_not_live', 'reason', 'There is no such provider.'); end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')) then
    return jsonb_build_object('rule', 'manual_lock', 'reason', 'The description is locked by hand.'); end if;
  if nullif(btrim(p.description), '') is not null then
    return jsonb_build_object('rule', 'description_already_held', 'reason', 'The provider already holds a description; the machine rule admits a first description only.'); end if;
  if exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null) then
    return jsonb_build_object('rule', 'description_cleared_after_admission', 'reason', 'A machine description was admitted for this provider and the description has since been cleared by hand; a person decides the next one.'); end if;
  if exists (select 1 from pipeline.layer4_review_items li where li.entity_type = 'provider' and li.entity_id = p.id and li.field_code = 'provider_description' and li.status = 'rejected') then
    return jsonb_build_object('rule', 'prior_human_rejection', 'reason', 'A person rejected an earlier description for this provider.'); end if;
  if exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is not null
               and not exists (select 1 from pipeline.provider_description_machine_admissions b where b.provider_id = p.id and b.outcome = 'admitted' and b.created_at > a.withdrawn_at)) then
    return jsonb_build_object('rule', 'withdrawn_awaiting_review', 'reason', 'A machine description for this provider was withdrawn; a person decides the next one.'); end if;
  select f.check_code into v_find from pipeline.provider_identity_findings f where f.provider_id = p.id and f.state = 'open' order by f.check_code limit 1;
  if v_find is not null then return jsonb_build_object('rule', 'identity_' || v_find, 'reason', 'An open provider identity finding needs a person: ' || v_find); end if;
  if (nullif(btrim(p.canonical_name), '') is not null and security.pdesc_clean_name_v1(p.canonical_name) is null)
     or (nullif(btrim(p.display_name), '') is not null and security.pdesc_clean_name_v1(p.display_name) is null)
     or (security.pdesc_clean_name_v1(p.canonical_name) is null and security.pdesc_clean_name_v1(p.display_name) is null) then
    return jsonb_build_object('rule', 'name_not_clean', 'reason', 'A provider name is a placeholder, too short or still holds web-page markup, so the identity proof is not reliable; a person decides.'); end if;
  return null;
end $f$;
comment on function security.provider_description_machine_blocked_v1(uuid) is 'CF-247 F-PDESC QA N6/N7/N8/N11: why the automatic rule must not read or describe this provider now, or null: locked by hand, already described, a machine description admitted and since cleared by hand, an earlier human rejection, a withdrawn machine description awaiting review, an open identity finding, or a placeholder or marked-up name. Read only; the reader holds such a provider before any AI call.';
revoke all on function security.provider_description_machine_blocked_v1(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- objective text rule
create or replace function security.pdesc_machine_text_check_v1(p_provider uuid, p_text text, p_codes text[] default '{}') returns text
language plpgsql stable security definer set search_path to '' as $f$
declare v_t text := lower(coalesce(p_text, '')); n text; w text; m text[]; v_year int := extract(year from now())::int; v_ymin int := security.pipeline_num_v1('pdesc.founded_year_min', 1800)::int;
        v_lists text[] := array['pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr']; l text;
begin
  -- web-page markup left in the text (&#039; &amp; &nbsp;) is never admitted: the wording was not read cleanly
  if coalesce(p_text, '') ~* '&#?[a-z0-9]{1,8};' then return 'entity_encoded:page markup'; end if;
  -- the provider's own names, the verified register codes and the register's own fixed wording (which names the register, e.g. "... for Overseas Students") are not claims ("Premier Institute", "provider code 00002J")
  for n in select nm from (select p.canonical_name nm from catalogue.providers p where p.id = p_provider union all select p.display_name from catalogue.providers p where p.id = p_provider
                           union all select p.short_name from catalogue.providers p where p.id = p_provider) z where nullif(btrim(nm), '') is not null order by length(nm) desc loop
    v_t := replace(v_t, lower(n), ' ');
  end loop;
  foreach n in array coalesce(p_codes, '{}') loop
    if nullif(btrim(n), '') is not null then v_t := replace(v_t, lower(n), ' '); end if;
  end loop;
  foreach l in array v_lists loop
    for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', l), '[]'::jsonb)) loop
      if security.pdesc_has_term_v1(v_t, w) then return 'refused_word:' || w; end if;
    end loop;
  end loop;
  if security.pipeline_num_v1('pdesc.machine_numbers_allowed', 0) < 1 then
    for m in select regexp_matches(v_t, '[0-9][0-9,.]*[0-9]|[0-9]', 'g') loop
      if not (m[1] ~ '^[0-9]{4}$' and m[1]::int between v_ymin and v_year) then return 'figure:' || m[1]; end if;
    end loop;
    if v_t ~ '[0-9]\s*(%|per\s*cent|percent)' then return 'figure:percentage'; end if;
  end if;
  return null;
end $f$;
comment on function security.pdesc_machine_text_check_v1(uuid, text, text[]) is 'CF-247 F-PDESC machine rule pdesc-machine-v1: null when the description is free of page markup, claim, marketing, campus/scholarship/guarantee and the extra machine words (English and French lists) and (unless allowed) of figures other than a four-digit year in range; otherwise the first refusal. The provider''s own names and listed register codes are ignored.';
revoke all on function security.pdesc_machine_text_check_v1(uuid, text, text[]) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the gate every tier passes
create or replace function security.provider_description_machine_gate_v1(p_provider uuid, p_text text, p_ctx jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare p catalogue.providers%rowtype; v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account (Decision 263)
        v_bad text; v_blk jsonb; v_codes text[] := coalesce(array(select jsonb_array_elements_text(coalesce(p_ctx->'codes', '[]'::jsonb))), '{}');
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off', 'reason', 'Automatic admission is off; a person decides in Layer 4.'); end if;
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null or p.lifecycle_status <> 'active' or p.publication_status <> 'published' or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) or security.provider_lifecycle_held_v1(p.id) then
    return jsonb_build_object('ok', false, 'rule', 'provider_not_live', 'reason', 'The provider is not active and published, or its lifecycle is held.');
  end if;
  if not security.provider_description_scope_v1(p.id) then return jsonb_build_object('ok', false, 'rule', 'out_of_scope', 'reason', 'The provider is outside the description reader scope.'); end if;
  -- lock, description already held, cleared after a machine admission, earlier human rejection, withdrawn awaiting review, open identity finding, unusable name
  v_blk := security.provider_description_machine_blocked_v1(p.id);
  if v_blk is not null then return jsonb_build_object('ok', false, 'rule', v_blk->>'rule', 'reason', v_blk->>'reason'); end if;
  if nullif(btrim(p_text), '') is null then return jsonb_build_object('ok', false, 'rule', 'no_description', 'reason', 'There is no description text.'); end if;
  v_bad := security.pdesc_machine_text_check_v1(p.id, p_text, v_codes);
  if v_bad is not null then return jsonb_build_object('ok', false, 'rule', 'machine_text_' || split_part(v_bad, ':', 1), 'reason', 'The description has a word, figure or markup the automatic rule does not admit (' || v_bad || '); it is not published automatically.'); end if;
  return jsonb_build_object('ok', true, 'rule', 'pdesc-machine-v1', 'actor', v_sys);
end $f$;
comment on function security.provider_description_machine_gate_v1(uuid, text, jsonb) is 'CF-247 F-PDESC machine rule pdesc-machine-v1, the conditions common to every tier: switch on, provider live and in scope, then security.provider_description_machine_blocked_v1 (lock, description held, cleared after a machine admission, earlier human rejection, withdrawn awaiting review, open identity finding, unusable name) and the objective text rule. Read only.';
revoke all on function security.provider_description_machine_gate_v1(uuid, text, jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- tier 4 profile
create or replace function security.provider_description_registry_profile_v1(p_provider uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare p catalogue.providers%rowtype; reg record; tpl text; v_country text; v_type text; v_tcode text; v_region text; v_city text; v_loc text; v_name text; v_art text;
        v_levels text[]; v_fields text[]; v_max int := security.pipeline_num_v1('pdesc.registry_offerings_max', 3)::int; v_min int := security.pipeline_num_v1('pdesc.registry_min_facts', 3)::int;
        v_facts jsonb := '[]'::jsonb; v_sent jsonb := '[]'::jsonb; s1 text; s2 text; s3 text; v_text text; v_ev record; v_have text[] := '{}'; v_asof timestamptz;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'No such provider.'); end if;
  select k.name into v_country from ref.countries k where k.id = p.country_id;
  select t.code, t.name into v_tcode, v_type from ref.provider_types t where t.id = p.provider_type_id;
  select s.name into v_region from ref.subdivisions s where s.id = p.subdivision_id;
  select r.* into reg from catalogue.provider_registrations r where r.provider_id = p.id and r.status = 'active' and r.evidence_id is not null order by r.checked_at desc nulls last, r.id limit 1;
  if reg.id is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The provider has no active register listing with stored evidence.'); end if;
  select a.id, a.source_url, a.content_hash, coalesce(a.captured_at, a.created_at) captured_at into v_ev from pipeline.evidence_artifacts a where a.id = reg.evidence_id;
  if v_ev.id is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The register listing''s evidence is not stored.'); end if;
  select t.register_sentence into tpl from pipeline.provider_description_registry_templates t where t.scheme = reg.registration_scheme and t.active;
  if tpl is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'There is no profile wording for register scheme ' || reg.registration_scheme || '.'); end if;
  v_name := coalesce(security.pdesc_clean_name_v1(p.display_name), security.pdesc_clean_name_v1(p.canonical_name));
  if v_name is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The provider has no usable name (a placeholder or page markup).'); end if;
  v_asof := coalesce(reg.checked_at, v_ev.captured_at);
  -- facts: each is a field of the verified record, with where it came from
  v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'register', 'field', 'catalogue.provider_registrations', 'value', reg.registration_scheme || ' ' || reg.registration_code || ' ' || reg.status,
      'source', 'register', 'registration_id', reg.id, 'evidence_id', reg.evidence_id, 'source_url', v_ev.source_url, 'source_hash', coalesce(v_ev.content_hash, v_ev.id::text), 'as_at', v_asof));
  v_have := v_have || 'register'::text;
  if v_tcode is not null and v_tcode <> 'other' and nullif(btrim(v_type), '') is not null then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'type', 'field', 'ref.provider_types.name', 'value', v_type, 'source', 'provider_record', 'provider_id', p.id, 'as_at', coalesce(p.provider_type_set_at, p.updated_at)));
    v_have := v_have || 'type'::text;
  end if;
  v_city := nullif(btrim(p.primary_city), '');
  if v_city is not null and v_city = upper(v_city) and length(v_city) >= security.pipeline_num_v1('pdesc.city_min_chars', 4)::int then v_city := initcap(lower(v_city)); end if;
  if v_city is not null and security.pdesc_machine_text_check_v1(p.id, v_city) is not null then v_city := null; end if; -- a "campus" or other refused word is not a city
  v_loc := nullif(concat_ws(', ', v_city, nullif(btrim(v_region), ''), nullif(btrim(v_country), '')), '');
  if (v_city is not null or nullif(btrim(v_region), '') is not null) and v_loc is not null then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'location', 'field', 'catalogue.providers.primary_city, subdivision, country', 'value', v_loc, 'source', 'provider_record', 'provider_id', p.id, 'as_at', p.updated_at));
    v_have := v_have || 'location'::text;
  end if;
  select coalesce(array_agg(x.name order by x.name), '{}') into v_levels from (select distinct sl.name from catalogue.courses c join ref.study_levels sl on sl.id = c.study_level_id
     where c.provider_id = p.id and c.lifecycle_status = 'active' and nullif(btrim(sl.name), '') is not null order by sl.name limit v_max) x;
  select coalesce(array_agg(x.name order by x.name), '{}') into v_fields from (select distinct f.name from catalogue.courses c join ref.fields_of_study f on f.id = c.primary_field_id
     where c.provider_id = p.id and c.lifecycle_status = 'active' and nullif(btrim(f.name), '') is not null order by f.name limit v_max) x;
  if coalesce(array_length(v_levels, 1), 0) > 0 then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'levels', 'field', 'catalogue.courses.study_level_id (active courses)', 'value', to_jsonb(v_levels), 'source', 'catalogue', 'provider_id', p.id, 'as_at', now()));
    v_have := v_have || 'levels'::text;
  end if;
  if coalesce(array_length(v_fields, 1), 0) > 0 then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'fields', 'field', 'catalogue.courses.primary_field_id (active courses)', 'value', to_jsonb(v_fields), 'source', 'catalogue', 'provider_id', p.id, 'as_at', now()));
    v_have := v_have || 'fields'::text;
  end if;
  if coalesce(array_length(v_have, 1), 0) < v_min then
    return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'facts_held', to_jsonb(v_have), 'facts_needed', v_min,
      'reason', format('%s verified fact(s) held (%s); %s needed for a useful, truthful profile.', coalesce(array_length(v_have, 1), 0), array_to_string(v_have, ', '), v_min));
  end if;
  -- sentences: wording only joins the verified facts
  v_art := case when v_type is null or lower(v_type) ~ '^(uni|use|eu|one|ubi)' then 'a' when lower(left(v_type, 1)) in ('a', 'e', 'i', 'o', 'u') then 'an' else 'a' end; -- "a university", "an agricultural college"
  s1 := case when 'type' = any (v_have) then v_name || ' is ' || v_art || ' ' || case when v_type ~ '^[A-Z][a-z]' then lower(left(v_type, 1)) || substr(v_type, 2) else v_type end || coalesce(' in ' || v_loc, '') || '.'
             else v_name || coalesce(' is located in ' || v_loc, ' is listed in this catalogue') || '.' end;
  s2 := replace(replace(tpl, '{name}', 'It'), '{code}', reg.registration_code);
  -- the second sentence reads "It is listed ..." / "It appears ..."; the template starts with the name, so the pronoun replaces it
  s3 := case when 'levels' = any (v_have) and 'fields' = any (v_have) then 'Its listed courses are at ' || regexp_replace(array_to_string(v_levels, ', '), ', ([^,]*)$', ' and \1') || ' levels, in fields including ' || regexp_replace(array_to_string(v_fields, ', '), ', ([^,]*)$', ' and \1') || '.'
             when 'levels' = any (v_have) then 'Its listed courses are at ' || regexp_replace(array_to_string(v_levels, ', '), ', ([^,]*)$', ' and \1') || ' levels.'
             when 'fields' = any (v_have) then 'Its listed courses are in fields including ' || regexp_replace(array_to_string(v_fields, ', '), ', ([^,]*)$', ' and \1') || '.' end;
  v_sent := jsonb_build_array(jsonb_build_object('text', s1, 'facts', (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array['type', 'location']) k where k = any (v_have))),
                              jsonb_build_object('text', s2, 'facts', jsonb_build_array('register')));
  if s3 is not null then v_sent := v_sent || jsonb_build_array(jsonb_build_object('text', s3, 'facts', (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array['levels', 'fields']) k where k = any (v_have)))); end if;
  v_text := concat_ws(' ', s1, s2, s3);
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or jsonb_array_length(v_sent) < security.pipeline_num_v1('pdesc.min_sentences', 2) or jsonb_array_length(v_sent) > security.pipeline_num_v1('pdesc.max_sentences', 5) then
    return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The profile (' || length(v_text) || ' characters, ' || jsonb_array_length(v_sent) || ' sentences) is outside the description limits (pdesc.min_chars, min_sentences, max_sentences).'); end if;
  if length(v_text) > security.pipeline_num_v1('pdesc.max_chars', 900) then
    return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The profile is longer than the description limit (' || length(v_text) || ' characters).'); end if;
  return jsonb_build_object('ok', true, 'rule', 'registry_factual', 'tier', 'registry_factual', 'text', v_text, 'sentences', v_sent, 'facts', v_facts, 'evidence_id', reg.evidence_id, 'registration_id', reg.id,
    'source_url', v_ev.source_url, 'source_hash', coalesce(v_ev.content_hash, v_ev.id::text), 'captured_at', v_ev.captured_at, 'codes', jsonb_build_array(s2, reg.registration_code), 'profile_version', 'registry-profile-v1');
end $f$;
comment on function security.provider_description_registry_profile_v1(uuid) is 'CF-247 F-PDESC tier 4 (registry_factual): a short factual profile built only from the provider record, its active register listing (stored evidence) and its active catalogue courses, each sentence tied to its facts; or insufficient_verified_facts. Deterministic, read only, no AI and no page read.';
revoke all on function security.provider_description_registry_profile_v1(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the admission
create or replace function security.provider_description_machine_admit_v1(p_item_id uuid) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; v_read pipeline.provider_description_reads%rowtype; v_tier text; v_text text; v_gate jsonb; v_check jsonb; v_prof jsonb; v_now text; v_pub jsonb; v_shown text; v_key text;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account that records Decision 263 rule decisions
        v_rule constant text := 'pdesc-machine-v1'; v_ref text := 'CF-247 F-PDESC; Platform Admin decision 9 Nov 2026 (source-verified machine admission, tiers 1 to 4)'; v_dec uuid; v_facts jsonb := '[]'::jsonb; v_codes jsonb := '[]'::jsonb;
        v_url text; v_hash text; v_reason text; v_decline text;
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off'); end if;
  select * into i from pipeline.layer4_review_items where id = p_item_id for update;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' or i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'not_a_waiting_provider_description'); end if;
  select * into v_read from pipeline.provider_description_reads r where r.review_item_id = i.id and r.state = 'proposed' for update;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  v_tier := coalesce(nullif(v_read.checks->>'tier', ''), v_read.read_via, i.proposed_value->>'tier');
  v_decline := null;
  if v_read.id is null then v_decline := 'no_proposed_read';
  elsif v_tier not in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_decline := 'unknown_tier';
  end if;
  if v_decline is null then
    if v_tier = 'registry_factual' then
      -- rebuilt from the verified record now: the text, the register evidence and the facts must be exactly what was proposed
      v_prof := security.provider_description_registry_profile_v1(i.entity_id);
      if not coalesce((v_prof->>'ok')::boolean, false) then v_decline := 'profile_' || coalesce(v_prof->>'rule', 'not_ok');
      elsif v_prof->>'text' is distinct from v_text or (v_prof->>'evidence_id')::uuid is distinct from i.evidence_id then v_decline := 'profile_changed_since_proposed';
      elsif not exists (select 1 from catalogue.provider_registrations rr where rr.id = (v_prof->>'registration_id')::uuid and rr.provider_id = i.entity_id and rr.status = 'active' and rr.evidence_id = i.evidence_id) then v_decline := 'register_listing_changed';
      end if;
      v_facts := coalesce(v_prof->'facts', '[]'::jsonb); v_codes := coalesce(v_prof->'codes', '[]'::jsonb); v_url := v_prof->>'source_url'; v_hash := v_prof->>'source_hash';
    else
      -- the same lineage, identity and quote checks the human path makes, proved again now
      if v_read.evidence_id is distinct from i.evidence_id or not exists (select 1 from pipeline.evidence_artifacts a join pipeline.sources s on s.id = a.source_id
           where a.id = i.evidence_id and s.provider_id = i.entity_id and a.source_url = v_read.source_url and coalesce(a.content_hash, a.id::text) = v_read.content_hash) then v_decline := 'evidence_lineage_changed';
      elsif not (security.provider_description_identity_v1(i.entity_id, v_read.source_url)->>'ok')::boolean then v_decline := 'identity_' || coalesce(security.provider_description_identity_v1(i.entity_id, v_read.source_url)->>'rule', 'not_clear');
      elsif v_read.checks->'identity_snapshot' is not null and v_read.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(i.entity_id) then v_decline := 'identity_changed_since_read';
      elsif v_read.checks->'identity_snapshot' is null and not exists (select 1 from catalogue.providers p cross join lateral jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) sentence
           where p.id = i.entity_id and exists (select 1 from unnest(array[p.canonical_name, p.display_name]) nm where nullif(btrim(nm), '') is not null
             and position(regexp_replace(lower(nm), '[^a-z0-9]+', '', 'g') in regexp_replace(lower(sentence->>'quote'), '[^a-z0-9]+', '', 'g')) > 0)) then v_decline := 'legacy_proposal_name_not_in_quote';
      else
        v_check := security.provider_description_validate_v1(i.entity_id, v_read.source_url, v_read.source_captured_at, jsonb_build_object('about_page', true, 'sentences', i.proposed_value->'sentences'));
        if v_check->>'outcome' not in ('propose', 'verified') or v_check->>'text' is distinct from v_text then v_decline := 'validation_' || coalesce(v_check->>'rule', 'changed'); end if;
      end if;
      v_url := v_read.source_url; v_hash := v_read.content_hash;
      v_facts := coalesce((select jsonb_agg(jsonb_build_object('sentence', s->>'text', 'quote', s->>'quote', 'source_url', v_read.source_url, 'source_hash', v_read.content_hash, 'evidence_id', v_read.evidence_id,
                    'captured_at', v_read.source_captured_at, 'model', v_read.model, 'prompt_version', v_read.prompt_version, 'worker', v_read.worker)) from jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s), '[]'::jsonb);
    end if;
  end if;
  if v_decline is null then
    v_gate := security.provider_description_machine_gate_v1(i.entity_id, v_text, jsonb_build_object('tier', v_tier, 'codes', v_codes));
    if not (v_gate->>'ok')::boolean then v_decline := v_gate->>'rule'; v_reason := v_gate->>'reason'; end if;
  end if;
  if v_decline is null and i.before_value->>'description' is not null and nullif(btrim(i.before_value->>'description'), '') is not null then v_decline := 'before_value_not_empty'; end if;
  if v_decline is null then
    select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
    if v_now is not null then v_decline := 'description_already_held'; end if;
  end if;
  if v_decline is not null then
    v_reason := coalesce(v_reason, 'The automatic rule did not admit this description (' || v_decline || '); a person decides in Layer 4.');
    insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, evidence_id, source_url, source_hash, facts, actor)
    values (i.entity_id, i.id, v_read.id, case when v_tier in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_tier else 'stored' end, v_rule, 'declined', v_reason, i.evidence_id, v_read.source_url, v_read.content_hash, v_facts, v_sys)
    on conflict (review_item_id) where outcome = 'declined' do update set reason = excluded.reason, tier = excluded.tier, facts = excluded.facts, created_at = now();
    update pipeline.layer4_review_items set escalation_reason = left('Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule [^.]*\. ', ''), 1000) -- fixed: the item's reason column shows its first 1000 characters
     where id = i.id and coalesce(escalation_reason, '') not like 'Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '.%';
    return jsonb_build_object('ok', false, 'rule', v_decline, 'reason', v_reason);
  end if;
  -- write the one description, settle the item as a machine decision, record everything
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- proved on the row: a guard that put the old text back must stop the admission, not leave an audit that says it was published
  if (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = i.entity_id) is distinct from v_text then raise exception 'description_not_written: the catalogue kept the earlier text'; end if;
  update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = i.id and status = 'pending';
  v_reason := format('Auto (%s, tier %s): %s. Not a person''s decision.', v_rule, v_tier,
                     case when v_tier = 'registry_factual' then 'built only from the verified register listing, provider record and active catalogue courses; every sentence tied to its facts'
                          else 'official page ' || coalesce(v_url, '') || ' (hash ' || left(coalesce(v_hash, ''), 12) || '); identity, evidence lineage and every sentence''s quote proved again at admission' end); -- fixed: a short hash prefix is shown for reading, the full hash is stored
  insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine'), coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', i.id::text, jsonb_build_object('kind', 'provider_description', 'ref', i.id::text, 'choice', 'approve', 'reason', v_reason, 'provider_id', i.entity_id, 'auto', true,
          'machine_rule', v_rule, 'tier', v_tier, 'decision_id', v_dec, 'field_code', i.field_code), v_sys);
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin v_pub := public.website_v2_provider(v_key); v_shown := v_pub->'item'->>'description'; exception when others then v_shown := null; end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(), published_at = case when v_shown = v_text then now() end, updated_at = now(),
         checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') where id = v_read.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now() where provider_id = i.entity_id and state = 'admitted' and id <> v_read.id;
  insert into pipeline.search_refresh_signals (entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', i.entity_id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
  insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, before_description, after_description, evidence_id, source_url, source_hash, facts, checks, actor)
  values (i.entity_id, i.id, v_read.id, v_tier, v_rule, 'admitted', v_reason, null, v_text, i.evidence_id, v_url, v_hash, v_facts,
          jsonb_build_object('decision_id', v_dec, 'published', v_shown = v_text, 'validation', coalesce(v_check->'checks', v_prof->'facts')), v_sys);
  return jsonb_build_object('ok', true, 'provider_id', i.entity_id, 'tier', v_tier, 'rule', v_rule, 'decision_id', v_dec, 'description_chars', length(v_text), 'published', v_shown = v_text);
end $f$;
comment on function security.provider_description_machine_admit_v1(uuid) is 'CF-247 F-PDESC machine admission of one provider''s FIRST description (tiers stored, direct, firecrawl, registry_factual): re-proves identity, lineage and quotes, applies the objective rule, writes the one description, settles the item under the system automation account with the machine rule and records the audit row. Never calls the human Layer 4 decision procedure. Declines (with the reason on the item and in the audit) rather than guess.';
revoke all on function security.provider_description_machine_admit_v1(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- withdrawal and rollback
create or replace function security.provider_description_machine_withdraw_v1(p_provider uuid, p_reason text, p_actor uuid) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare a pipeline.provider_description_machine_admissions%rowtype; v_now text; v_after text; v_dec uuid;
begin
  -- the caller is the person who asked (public.admin_provider_description_machine_withdraw_v1 passes auth.uid()); the system account is never recorded as the one who withdrew
  if p_actor is null or p_actor = 'c0ffee00-0000-4000-8000-000000000150'::uuid then raise exception 'the person who withdraws must be named'; end if; -- fixed: the system automation account (Decision 263) is not a person
  if nullif(btrim(p_reason), '') is null then raise exception 'give a reason (kept in the log)'; end if;
  select * into a from pipeline.provider_description_machine_admissions where provider_id = p_provider and outcome = 'admitted' and withdrawn_at is null for update;
  if a.id is null then return jsonb_build_object('ok', false, 'rule', 'no_live_machine_admission'); end if;
  select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = p_provider for update;
  if v_now is distinct from a.after_description then return jsonb_build_object('ok', false, 'rule', 'description_changed_since_admission', 'reason', 'A person changed the description since the machine admitted it; it is kept.'); end if;
  -- a hand lock added since the admission keeps the text (the catalogue guard would put it back silently): refuse, and change nothing
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p_provider and l.field in ('description', 'p_description', 'all')) then
    return jsonb_build_object('ok', false, 'rule', 'manual_lock', 'reason', 'The description has been locked by hand since the machine admitted it; it is kept. Release the lock first.'); end if;
  v_dec := nullif(a.checks->>'decision_id', '')::uuid;
  if v_dec is null then raise exception 'the admission has no decision to point the search refresh at'; end if;
  update catalogue.providers set description = a.before_description, updated_at = now() where id = p_provider;
  -- proved on the row, not assumed: a guard that put the old text back would leave the audit saying "restored"
  select nullif(btrim(p.description), '') into v_after from catalogue.providers p where p.id = p_provider;
  if v_after is distinct from nullif(btrim(a.before_description), '') then raise exception 'withdraw_not_applied: the catalogue kept the description; nothing was changed'; end if;
  update pipeline.provider_description_machine_admissions set withdrawn_at = now(), withdrawn_by = p_actor, withdrawn_reason = btrim(p_reason) where id = a.id;
  update pipeline.provider_description_reads set state = 'superseded', rule = 'machine_withdrawn', updated_at = now() where id = a.read_id and state in ('admitted', 'verified');
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('layer4', 'pdesc_machine_withdraw', p_provider::text, jsonb_build_object('admission_id', a.id, 'review_item_id', a.review_item_id, 'tier', a.tier, 'rule', a.rule, 'before', a.before_description, 'after', a.after_description, 'reason', btrim(p_reason), 'withdrawn_by', p_actor), p_actor);
  -- production keeps ONE search refresh signal for each decision (UNIQUE review_decision_id): the signal the admission queued is queued again for the same decision, not a second row
  insert into pipeline.search_refresh_signals as s (entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', p_provider, v_dec, 'Machine description withdrawn: ' || btrim(p_reason), 'CF-247 F-PDESC withdrawal')
  on conflict (review_decision_id) do update set status = case when s.status = 'processing' then s.status else 'queued' end, completed_at = null, reason = excluded.reason, change_control_ref = excluded.change_control_ref;
  return jsonb_build_object('ok', true, 'provider_id', p_provider, 'admission_id', a.id, 'restored', a.before_description, 'withdrawn_by', p_actor);
end $f$;
comment on function security.provider_description_machine_withdraw_v1(uuid, text, uuid) is 'CF-247 F-PDESC rollback of one machine-admitted description: restores the earlier text if no person changed it since and no hand lock was added, proves the row changed, records the named person and why, queues the search refresh again on the admission''s own decision (one signal for each decision), and holds the provider out of further automatic admission until a person decides. One provider at a time. Not callable from the app; use public.admin_provider_description_machine_withdraw_v1.';
revoke all on function security.provider_description_machine_withdraw_v1(uuid, text, uuid) from public, anon, authenticated;

create or replace function public.admin_provider_description_machine_withdraw_v1(p_provider uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $f$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to withdraw a machine description' using errcode = '42501'; end if; -- fixed: rank 6 is the Platform Admin role
  return security.provider_description_machine_withdraw_v1(p_provider, p_reason, auth.uid());
end $f$;
comment on function public.admin_provider_description_machine_withdraw_v1(uuid, text) is 'CF-247 F-PDESC: withdraw one machine-admitted provider description (restore the earlier text, keep the audit, record who and why). Platform Admin (rank 6) only; the person is recorded, not the system account.';
revoke all on function public.admin_provider_description_machine_withdraw_v1(uuid, text) from public, anon;
grant execute on function public.admin_provider_description_machine_withdraw_v1(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- auto-settlement of the items already waiting
create or replace function security.provider_description_machine_settle_pending_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare r record; v_res jsonb; v_ok int := 0; v_no int := 0; v_err int := 0;
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in select li.id from pipeline.layer4_review_items li where li.field_code = 'provider_description' and li.entity_type = 'provider' and li.status = 'pending'
            and not exists (select 1 from pipeline.provider_description_machine_admissions a where a.review_item_id = li.id and a.outcome = 'declined' and a.created_at > now() - make_interval(hours => 1)) -- fixed: a declined item is checked again at most hourly
            order by li.created_at limit security.pipeline_num_v1('pdesc.machine_settle_per_run', 10)::int loop
    begin
      v_res := security.provider_description_machine_admit_v1(r.id);
      if (v_res->>'ok')::boolean then v_ok := v_ok + 1; else v_no := v_no + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('on', true, 'admitted', v_ok, 'left_for_a_person', v_no, 'errors', v_err);
end $f$;
comment on function security.provider_description_machine_settle_pending_v1() is 'CF-247 F-PDESC: checks the provider-description items already waiting in Layer 4 against the machine rule, a bounded number a run (pdesc.machine_settle_per_run). Those that pass are admitted and settled as machine decisions; the rest stay for a person with the reason on the item.';
revoke all on function security.provider_description_machine_settle_pending_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- tier 4 run
create or replace function security.provider_description_registry_tier_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare r record; v_prof jsonb; v_gate jsonb; v_read uuid; v_item uuid; v_res jsonb; v_ok int := 0; v_held int := 0; v_err int := 0; v_msg text; v_rule text;
        v_rules jsonb := coalesce(security.toolset_setting('pipeline', 'pdesc.registry_after_rules'), '[]'::jsonb); v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account (Decision 263)
begin
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 or security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 or security.pipeline_num_v1('pdesc.registry_factual_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in
    with act as (select pz.country_id, count(*) n from pipeline.provider_description_machine_admissions z join catalogue.providers pz on pz.id = z.provider_id
                  where z.created_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id)
    select p.id from catalogue.providers p left join act on act.country_id = p.country_id
      left join lateral (select x.state, x.rule, x.updated_at from pipeline.provider_description_reads x where x.provider_id = p.id order by x.created_at desc, x.id desc limit 1) lr on true
     where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null and security.provider_description_scope_v1(p.id)
       and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = p.id and o.state in ('queued', 'reading', 'proposed'))
       and not exists (select 1 from pipeline.provider_description_reads h where h.provider_id = p.id and h.state = 'held' and h.checks->>'tier' = 'registry_factual' and h.updated_at > now() - make_interval(days => security.pipeline_num_v1('pdesc.recheck_days', 180)::int))
       and ((lr.state = 'held' and v_rules ? lr.rule) or lr.state = 'dead_letter'
            or (lr.state is null and nullif(btrim(p.website), '') is null and security.provider_description_stored_v1(p.id) is null))
       and security.provider_description_machine_blocked_v1(p.id) is null
     order by coalesce(act.n, 0), p.id
     limit security.pipeline_num_v1('pdesc.registry_per_run', 25)::int loop
    begin
      v_prof := security.provider_description_registry_profile_v1(r.id);
      if not coalesce((v_prof->>'ok')::boolean, false) then
        insert into pipeline.provider_description_reads (provider_id, state, rule, reason, worker, prompt_version, checks, tries)
        values (r.id, 'held', 'insufficient_verified_facts', left(v_prof->>'reason', 400), 'registry-factual-v1', 'registry-profile-v1', jsonb_build_object('tier', 'registry_factual', 'facts_held', v_prof->'facts_held', 'facts_needed', v_prof->'facts_needed', 'tier_hold', true), 0); -- fixed: display width of the stored reason text
        v_held := v_held + 1; continue;
      end if;
      v_gate := security.provider_description_machine_gate_v1(r.id, v_prof->>'text', jsonb_build_object('tier', 'registry_factual', 'codes', v_prof->'codes'));
      if not (v_gate->>'ok')::boolean then
        insert into pipeline.provider_description_reads (provider_id, state, rule, reason, worker, prompt_version, checks, tries)
        values (r.id, 'held', 'machine_declined_' || (v_gate->>'rule'), left(v_gate->>'reason', 400), 'registry-factual-v1', 'registry-profile-v1', jsonb_build_object('tier', 'registry_factual', 'tier_hold', true), 0); -- fixed: display width of the stored reason text
        v_held := v_held + 1; continue;
      end if;
      insert into pipeline.provider_description_reads (provider_id, state, rule, source_url, evidence_id, content_hash, source_captured_at, worker, prompt_version, proposal, checks, tries, last_verified_at)
      values (r.id, 'proposed', 'registry_factual', v_prof->>'source_url', (v_prof->>'evidence_id')::uuid, v_prof->>'source_hash', (v_prof->>'captured_at')::timestamptz, 'registry-factual-v1', 'registry-profile-v1',
              jsonb_build_object('description', v_prof->>'text', 'facts', v_prof->'facts', 'tier', 'registry_factual'),
              jsonb_build_object('tier', 'registry_factual', 'facts', v_prof->'facts', 'profile_version', 'registry-profile-v1', 'identity_snapshot', security.provider_description_identity_snapshot_v1(r.id)), 0, now())
      returning id into v_read;
      insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
      values ('provider', r.id, 'provider_description', (v_prof->>'evidence_id')::uuid, jsonb_build_object('description', null),
              jsonb_build_object('description', v_prof->>'text', 'tier', 'registry_factual', 'facts', v_prof->'facts', 'sentences_facts', v_prof->'sentences', 'source_url', v_prof->>'source_url', 'evidence_id', v_prof->>'evidence_id', 'captured_at', v_prof->>'captured_at', 'read_id', v_read),
              jsonb_build_object('read_via', null, 'content_hash', v_prof->>'source_hash', 'source_url', v_prof->>'source_url', 'tier', 'registry_factual'),
              jsonb_build_object('worker', 'registry-factual-v1', 'prompt_version', 'registry-profile-v1', 'rule', 'registry_factual'), 'pending',
              'Register-fact profile (tier 4): built only from the verified register listing, the provider record and the active catalogue courses, no page read and no AI. Admitted by the machine rule, not by a person.',
              'CF-247 F-PDESC (Platform Admin decision 9 Nov 2026)')
      returning id into v_item;
      update pipeline.provider_description_reads set review_item_id = v_item where id = v_read;
      v_res := security.provider_description_machine_admit_v1(v_item);
      if not (v_res->>'ok')::boolean then raise exception 'machine_declined:%', v_res->>'rule'; end if;
      v_ok := v_ok + 1;
    exception when others then
      get stacked diagnostics v_msg = message_text;
      begin
        insert into pipeline.provider_description_reads (provider_id, state, rule, reason, worker, prompt_version, checks, tries)
        values (r.id, 'held', case when v_msg like 'machine_declined:%' then 'machine_declined_' || substr(v_msg, 17) else 'registry_tier_error' end, left(v_msg, 400), 'registry-factual-v1', 'registry-profile-v1', -- fixed: display width of the stored reason text
                jsonb_build_object('tier', 'registry_factual', 'tier_hold', true), 0);
      exception when others then null;
      end;
      v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('on', true, 'admitted', v_ok, 'held', v_held, 'errors', v_err);
end $f$;
comment on function security.provider_description_registry_tier_v1() is 'CF-247 F-PDESC tier 4: for providers whose official page cannot be read (the latest read held with a rule in pdesc.registry_after_rules, dead letter, or no website and no stored page), builds the register-fact profile and passes it through the same machine admission as the other tiers; a provider with too few verified facts is held with insufficient_verified_facts. Bounded by pdesc.registry_per_run.';
revoke all on function security.provider_description_registry_tier_v1() from public, anon, authenticated;

create or replace function security.provider_description_machine_step_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_a jsonb; v_b jsonb;
begin
  -- one failure never stops the reader: each part reports its own error
  begin v_a := security.provider_description_machine_settle_pending_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.provider_description_registry_tier_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('settle', v_a, 'registry', v_b);
end $f$;
comment on function security.provider_description_machine_step_v1() is 'CF-247 F-PDESC: the machine part of one run of the existing provider-description-read job (settle waiting items, tier 4). Called by security.provider_description_fire_v1 only when pdesc.machine_admit_on is 1.';
revoke all on function security.provider_description_machine_step_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- throughput and the scoreboard (read only)
create or replace function security.provider_description_throughput_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_every numeric := security.pipeline_num_v1('pdesc.every_minutes', 60); v_target numeric := security.pipeline_num_v1('pdesc.target_hours', 12); v_batch int := security.pipeline_num_v1('batch.provider_description', 3)::int;
        v_disp int := security.pipeline_num_v1('pdesc.dispatch_max', 3)::int; v_cap int := security.pipeline_num_v1('pdesc.queue_cap', 60)::int; v_win numeric := security.pipeline_num_v1('pdesc.rate_window_hours', 3);
        v_back numeric := security.pipeline_num_v1('pdesc.backlog_hours', 2); v_by jsonb; v_total int; v_obs numeric; v_queued int; v_runs numeric; v_size int; v_room int; v_target_q int; v_share jsonb := '{}'::jsonb; c record;
begin
  select coalesce(jsonb_object_agg(z.cc, z.n), '{}'::jsonb), coalesce(sum(z.n), 0)::int into v_by, v_total from (
    select k.iso_alpha2::text cc, count(*) filter (where lr.state is null or lr.state in ('queued', 'reading')) n
      from catalogue.providers p join ref.countries k on k.id = p.country_id
      left join lateral (select x.state from pipeline.provider_description_reads x where x.provider_id = p.id order by x.created_at desc, x.id desc limit 1) lr on true
     where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null and security.provider_description_scope_v1(p.id)
     group by k.iso_alpha2) z;
  select count(*)::numeric / v_win into v_obs from pipeline.provider_description_reads x where x.updated_at > now() - make_interval(hours => v_win::int) and x.state in ('proposed', 'admitted', 'verified', 'held', 'dead_letter', 'rejected');
  select count(*) into v_queued from pipeline.provider_description_reads x where x.state = 'queued';
  v_runs := greatest(1, floor(v_target * 60 / greatest(v_every, 1)));
  v_size := least(v_cap, greatest(1, ceil(v_total / v_runs)::int));
  v_target_q := greatest(v_batch * v_disp * security.pipeline_num_v1('pdesc.queue_floor_runs', 2)::int, ceil(v_obs * v_back)::int);
  v_room := greatest(0, v_target_q - v_queued);
  v_size := least(v_size, v_room);
  if v_total > 0 and v_size > 0 then
    for c in select key cc, value::int n from jsonb_each_text(v_by) where value::int > 0 loop
      v_share := v_share || jsonb_build_object(c.cc, least(c.n, greatest(1, ceil(v_size::numeric * c.n / v_total)::int)));
    end loop;
  end if;
  return jsonb_build_object('remaining_total', v_total, 'remaining_by_country', v_by, 'observed_per_hour', round(v_obs, 2), 'queued_now', v_queued, 'runs_in_target', v_runs,
    'enqueue_size', v_size, 'queue_target', v_target_q, 'share', v_share, 'eta_hours', case when v_obs > 0 then round(v_total / v_obs, 1) end, 'target_hours', v_target);
end $f$;
comment on function security.provider_description_throughput_v1() is 'CF-247 F-PDESC: the providers still to do (never read, queued or reading) in scope by country, the observed reading rate, and the queue size and share per country the reader should add this run (remaining / runs in the target window, limited by what the observed rate can drain). Read only; every number comes from a pdesc.* setting.';
revoke all on function security.provider_description_throughput_v1() from public, anon, authenticated;

create or replace function security.provider_description_machine_report_v1(p_detail int default null) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_out jsonb;
begin
  select jsonb_build_object(
    'contract', 'provider-description-machine-report-v1', 'as_at', now(),
    'providers', (select jsonb_object_agg(z.cc, jsonb_build_object('providers', z.n, 'live', z.live, 'described', z.described, 'machine_admitted', z.machine, 'website_verified', z.web, 'zoho_verified', z.zoho))
                    from (select k.iso_alpha2::text cc, count(*) n, count(*) filter (where p.lifecycle_status = 'active' and p.publication_status = 'published') live,
                                 count(*) filter (where nullif(btrim(p.description), '') is not null) described,
                                 count(a.id) machine,
                                 count(*) filter (where (rd.consumer_checks->>'website_verified')::boolean) web, count(*) filter (where (rd.consumer_checks->>'zoho_verified')::boolean) zoho
                            from catalogue.providers p join ref.countries k on k.id = p.country_id
                            left join pipeline.provider_description_machine_admissions a on a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null
                            left join pipeline.provider_description_reads rd on rd.id = a.read_id
                           group by k.iso_alpha2) z),
    'tiers', (select coalesce(jsonb_object_agg(t.tier, t.n), '{}'::jsonb) from (select tier, count(*) n from pipeline.provider_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null group by tier) t),
    'declined', (select coalesce(jsonb_object_agg(d.reason_key, d.n), '{}'::jsonb) from (select split_part(reason, ' (', 1) reason_key, count(*) n from pipeline.provider_description_machine_admissions where outcome = 'declined' group by 1) d),
    'holds', (select coalesce(jsonb_object_agg(h.rule, h.n), '{}'::jsonb) from (select x.rule, count(*) n from pipeline.provider_description_reads x where x.state = 'held' and (x.rule like 'machine_declined%' or x.rule = 'insufficient_verified_facts') group by x.rule) h),
    'parity', (select jsonb_build_object('admitted', count(*), 'website_verified', count(*) filter (where (rd.consumer_checks->>'website_verified')::boolean), 'zoho_verified', count(*) filter (where (rd.consumer_checks->>'zoho_verified')::boolean),
                 'not_yet_checked', count(*) filter (where rd.consumer_checked_at is null),
                 'mismatched', coalesce((select jsonb_agg(jsonb_build_object('provider_id', m.provider_id, 'website', (m.consumer_checks->>'website_verified'), 'zoho', (m.consumer_checks->>'zoho_verified')) )
                                           from (select a2.provider_id, rd2.consumer_checks from pipeline.provider_description_machine_admissions a2 join pipeline.provider_description_reads rd2 on rd2.id = a2.read_id
                                                  where a2.outcome = 'admitted' and a2.withdrawn_at is null and rd2.consumer_checked_at is not null
                                                    and not (coalesce((rd2.consumer_checks->>'website_verified')::boolean, false) and coalesce((rd2.consumer_checks->>'zoho_verified')::boolean, false)) limit greatest(coalesce(p_detail, security.pipeline_num_v1('pdesc.report_detail', 20)::int), 0)) m), '[]'::jsonb))
                 from pipeline.provider_description_machine_admissions a join pipeline.provider_description_reads rd on rd.id = a.read_id where a.outcome = 'admitted' and a.withdrawn_at is null),
    'throughput', security.provider_description_throughput_v1()) into v_out;
  return v_out;
end $f$;
comment on function security.provider_description_machine_report_v1(int) is 'CF-247 F-PDESC acceptance scoreboard (read only): providers by country (live, described, machine-admitted, Website and Zoho read-back), admissions by tier, the exact holds and declines, the consumer parity mismatches and the throughput. The Website and Zoho read-back is recorded by the existing publication check on the admitted read; nothing here calls or changes a consumer API.';
revoke all on function security.provider_description_machine_report_v1(int) from public, anon, authenticated;
