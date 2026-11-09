-- CF-247 F-CDESC (Platform Admin decision 10 Nov 2026, "Course descriptions: autonomous AI admission from stored course pages"; operating rule 10 Nov 2026 05:40: only class-A settings, everything else derived).
--
-- Slice 1 of 2: the machine rule for FIRST course descriptions, read only. Nothing is admitted by this migration and nothing switches on.
--   1. pipeline.course_description_machine_admissions: the ledger of every course description the machine rule admitted or declined (before and after text, page evidence id and content hash, source URL,
--      model, prompt version, rule version, actor, outcome, exact reason and next action, withdrawal, recovery, Website read-back).
--   2. pipeline.course_description_source_checks: an OPTIONAL place for a later, independent re-read of the stored page (nothing writes to it yet: no worker mode or RPC for it exists in this change). The evaluator
--      reads it only if a row exists: a failed result declines; a confirmed result counts only if it is recent (gaps.recheck_days) and the hash it read equals the evidence content hash; no row never blocks.
--      WHAT IS RE-VALIDATED at admission is therefore NOT a fresh read of the page. It is: the on_page result the worker stored for each quote when it read the page (re-run through the live
--      course_description_check_v1), the sentence, length, support and in-provider duplicate checks, the wording policy, the identity binding (bound, not ambiguous, identity proof allowed for the country, enough margin
--      over the runner-up, not an AI match), the evidence not stale (gaps.recheck_days), the content hash carried in the stored object's address and the object present in storage, and no catalogue-wide duplicate.
--   3. ONE new setting, enrich.course_description_machine_on (ships 0). The text policy is the EXISTING admission policy, not a parallel set: the refused-word lists (pdesc.claim_words, pdesc.superlatives,
--      pdesc.evidence_claim_words, pdesc.machine_refused_words, pdesc.machine_refused_words_fr, pdesc.machine_neutral_words) and the figures policy (pdesc.machine_numbers_allowed, pdesc.founded_year_min) are read
--      through the live security.pdesc_machine_text_check_ctx_v1; the sentence, length, support and in-provider duplicate checks are the live security.course_description_check_v1 (pdesc.support_min_share,
--      pdesc.duplicate_share, enrich.course_description_*). Derived by code, not settings: the evidence age limit is gaps.recheck_days; the catalogue-wide duplicate share is pdesc.duplicate_share; its comparison
--      window is enrich.course_description_duplicate_window; items settled a run are bounded by a time box and enrich.course_text_items_per_day; a held reading is looked at again when the policy changed or after gaps.recheck_days.
--   4. security.course_description_machine_check_v1(item): the read-only evaluator of the safe class, one precise reason code and next action for every decline; and security.course_description_machine_shadow_v1():
--      a read-only report over the waiting Layer 4 items and the held readings (what would be admitted, what stays for a person and why). Both can be run on live before the switch is ever turned on.
--   5. An index beside catalogue.courses (courses_description_norm_md5_idx) for the catalogue-wide exact-duplicate test. No column, row or function the consumer API reads changes (G3).
-- The consumer API is not changed (G3). enrich.course_description_review_first stays 100000 and is not read here. No Layer 4 item, description, setting value or job changes.
-- Replaces: nothing (adds a separate machine route beside the human Layer 4 route; the old route is unchanged)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.course_description_check_v1(uuid,jsonb)'), ('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'), ('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'),
                                 ('security.coverage_identity_allowed(uuid,text,text)'), ('security.pdesc_words_v1(text)'), ('security.pipeline_num_v1(text,numeric)'), ('security.toolset_setting(text,text)'),
                                 ('security.course_description_trusted_v1(uuid)'), ('security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)'), ('security.course_description_review_trg_v1()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.layer4_decisions') is null or to_regclass('pipeline.search_refresh_signals') is null or to_regclass('pipeline.admin_control_events') is null
     or to_regclass('pipeline.field_enrich_items') is null or to_regclass('pipeline.coverage_course_pages') is null or to_regclass('pipeline.manual_locks') is null
     or to_regclass('pipeline.enrichment_flags') is null or to_regclass('storage.objects') is null then raise exception 'a table this change relies on is missing'; end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- tables
create table if not exists pipeline.course_description_machine_admissions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  review_item_id uuid references pipeline.layer4_review_items(id),
  reading_item_id bigint,
  rule text not null,
  outcome text not null check (outcome in ('admitted', 'declined')),
  reason_code text,
  reason text,
  next_action text,
  transient boolean not null default false,
  retry_after timestamptz,
  policy_stamp text,
  before_description text,
  after_description text,
  text_md5 text,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  content_hash text,
  source_url text,
  storage_path text,
  model text,
  prompt_version text,
  worker text,
  checks jsonb not null default '{}'::jsonb,
  recovery text,
  consumer_check text,
  consumer_checked_at timestamptz,
  actor uuid not null,
  created_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  withdrawn_by uuid,
  withdrawn_reason text
);
comment on table pipeline.course_description_machine_admissions is 'CF-247 F-CDESC (Platform Admin decision 10 Nov 2026): one row for each first course description the machine rule cdesc-machine-v1 admitted (before and after text, page evidence id and content hash, source URL, model, prompt version, actor, recovery, Website read-back, withdrawal) and each waiting Layer 4 course description it declined (exact reason code and next action). Written only by security.course_description_machine_admit_v1, _withdraw_v1, _settle_v1 and _consumer_recheck_v1; read by the shadow and scoreboard reports. The record of what the platform admitted without a person.';
create unique index if not exists course_description_machine_admissions_live_uq on pipeline.course_description_machine_admissions (course_id) where outcome = 'admitted' and withdrawn_at is null;
create unique index if not exists course_description_machine_admissions_declined_uq on pipeline.course_description_machine_admissions (review_item_id) where outcome = 'declined';
create index if not exists course_description_machine_admissions_course_idx on pipeline.course_description_machine_admissions (course_id, created_at desc);
create index if not exists course_description_machine_admissions_consumer_idx on pipeline.course_description_machine_admissions (consumer_checked_at nulls first) where outcome = 'admitted' and withdrawn_at is null and consumer_check is distinct from 'matched';
alter table pipeline.course_description_machine_admissions enable row level security;
revoke all on pipeline.course_description_machine_admissions from public, anon, authenticated;

create table if not exists pipeline.course_description_source_checks (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  review_item_id uuid references pipeline.layer4_review_items(id),
  result text not null check (result in ('confirmed', 'quote_missing', 'hash_mismatch', 'object_missing', 'error')),
  content_hash_read text,
  quotes_total integer,
  quotes_found integer,
  detail jsonb not null default '{}'::jsonb,
  worker text,
  checked_at timestamptz not null default now()
);
comment on table pipeline.course_description_source_checks is 'CF-247 F-CDESC optional independent re-read of a stored course page: the hash of the object read and how many of the waiting description''s quotes were found on it. Nothing writes to it yet (no worker mode or RPC exists for it); it is empty until a later change adds one. security.course_description_machine_check_v1 reads the latest row for the evidence: a failed result declines; a confirmed result counts only if it is no older than gaps.recheck_days and its content_hash_read equals the evidence content hash, otherwise the admission is declined as unusable; no row never blocks.';
create index if not exists course_description_source_checks_evidence_idx on pipeline.course_description_source_checks (evidence_id, checked_at desc);
alter table pipeline.course_description_source_checks enable row level security;
revoke all on pipeline.course_description_source_checks from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the one setting (G2; ships off)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.course_description_machine_on', 'Course descriptions: automatic admission (source-verified)',
  '1: a course''s FIRST description read from its own stored official page that passes the objective rule cdesc-machine-v1 is admitted by the machine and recorded as a machine decision in the ledger and in Layer 4, never as a person''s. At the moment it writes, the rule checks again (it does not read the page again): the quote results the worker stored for each sentence (on the page), the sentence, length, support and in-provider duplicate checks, the words and figures policy shared with provider descriptions (no claim, ranking, accreditation, outcome, campus or figure), the page binding (bound, not ambiguous, proof allowed, clear margin over the runner-up, not an AI match, evidence unchanged), the stored page recent and present with its content hash in its address, no duplicate of any other course''s text within the comparison window, and no hand lock, hold or earlier rejection. Anything else stays for a person with its exact reason. 0: every first description waits for a person in Layer 4. Machine approvals are not counted as a person''s trust: security.course_description_trusted_v1 (the count behind enrich.course_description_review_first) leaves out items whose decision is marked as a machine decision. enrich.course_description_review_first stays 100000.',
  'number', '0'::jsonb, 0, 1, 'on/off', 1122, 'Course description and deadline',
  'security.course_description_machine_admit_v1, security.course_description_machine_run_v1 (job course-description-machine), security.course_description_machine_trg_v1',
  'CF-247 F-CDESC (Platform Admin decision 10 Nov 2026): source-verified machine admission, default off')
on conflict (toolset_key, key) do nothing;
-- the switch is a person's decision (control class 'human', Platform Admin 10 Nov 2026, F-OPS.05). The column is added by 20261110080000; where it is not there yet this does nothing, and that migration leaves a
-- classified row alone. Only the row this change inserts is set, and only while it is still unclassified.
do $cc$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'pipeline' and table_name = 'platform_toolset_settings' and column_name = 'control_class') then
    execute $q$update pipeline.platform_toolset_settings set control_class = 'human' where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on' and control_class is null$q$;
  end if;
end $cc$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- helpers
create or replace function security.cdesc_norm_v1(p_text text) returns text language sql immutable set search_path to '' as $f$
  select btrim(regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', ' ', 'g'))
$f$;
comment on function security.cdesc_norm_v1(text) is 'CF-247 F-CDESC: a description with case, punctuation and spacing removed, for the exact-duplicate test across the catalogue (md5 of this is indexed beside catalogue.courses).';
revoke all on function security.cdesc_norm_v1(text) from public, anon, authenticated;

create index if not exists courses_description_norm_md5_idx on catalogue.courses (md5(security.cdesc_norm_v1(description))) where nullif(btrim(description), '') is not null;
comment on index catalogue.courses_description_norm_md5_idx is 'CF-247 F-CDESC: lookup of described courses by the normalised text of the description, used by the machine rule''s catalogue-wide exact-duplicate test. An index beside the table: no column, row or function the consumer API reads changes (G3).';

create or replace function security.cdesc_machine_fail_v1(p_rule text, p_reason text, p_next text, p_transient boolean default false) returns jsonb language sql immutable set search_path to '' as $f$
  select jsonb_build_object('ok', false, 'rule', p_rule, 'reason', p_reason, 'next_action', p_next, 'transient', p_transient)
$f$;
comment on function security.cdesc_machine_fail_v1(text, text, text, boolean) is 'CF-247 F-CDESC: the shape of a decline by the machine rule (reason code, reason, exact next action, whether it is worth looking at again soon).';
revoke all on function security.cdesc_machine_fail_v1(text, text, text, boolean) from public, anon, authenticated;

create or replace function security.course_description_machine_policy_stamp_v1() returns text language sql stable security definer set search_path to '' as $f$
  -- a fingerprint of every setting the rule reads, so a declined item is looked at again when (and only when) the policy changes
  select md5('cdesc-machine-v1|' || coalesce(string_agg(s.key || '=' || s.value::text, '|' order by s.key), ''))
    from pipeline.platform_toolset_settings s
   where s.toolset_key = 'pipeline' and (s.key like 'enrich.course_description\_%' escape '\' and s.key <> 'enrich.course_description_machine_on'
         or s.key in ('pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr', 'pdesc.machine_neutral_words',
                      'pdesc.machine_numbers_allowed', 'pdesc.founded_year_min', 'pdesc.support_min_share', 'pdesc.duplicate_share', 'gaps.recheck_days'))
$f$;
comment on function security.course_description_machine_policy_stamp_v1() is 'CF-247 F-CDESC: md5 of every setting the machine rule reads (not its own switch). A declined item is evaluated again when the stamp changed, when the decline is transient, or after gaps.recheck_days.';
revoke all on function security.course_description_machine_policy_stamp_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the safe-class evaluator (read only)
create or replace function security.course_description_machine_check_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; p catalogue.providers%rowtype; g pipeline.coverage_course_pages%rowtype; e pipeline.evidence_artifacts%rowtype; f pipeline.field_enrich_items%rowtype;
        sc pipeline.course_description_source_checks%rowtype;
        v_rule constant text := 'cdesc-machine-v1'; v_fid bigint; v_text text; v_md5 text; v_chk jsonb; v_pol text; v_sents jsonb; v_share numeric; v_win int; v_words text[]; v_dup record; v_other uuid; v_recheck text := 'not_run';
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; -- derived: a stored page older than the days after which the queue reads the course again is not trusted
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_description_first_read' then
    return security.cdesc_machine_fail_v1('not_a_course_description_item', 'This is not a waiting first course description.', 'Nothing to do.'); end if;
  if i.status <> 'pending' then return security.cdesc_machine_fail_v1('item_not_pending', 'The item is already decided (' || i.status || ').', 'Nothing to do.'); end if;
  select * into c from catalogue.courses where id = i.entity_id;
  if c.id is null or c.lifecycle_status <> 'active' then
    return security.cdesc_machine_fail_v1('course_not_active', 'The course is not active.', 'Leave it; the retire job settles proposals for courses that are no longer active.'); end if;
  select * into p from catalogue.providers where id = c.provider_id;
  if p.id is null or p.lifecycle_status <> 'active' or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) or security.provider_lifecycle_held_v1(p.id) then
    return security.cdesc_machine_fail_v1('provider_not_live', 'The provider is hidden, held or not active.', 'A person decides in Layer 4 once the provider is live again.'); end if;
  if nullif(btrim(c.description), '') is not null then
    return security.cdesc_machine_fail_v1('description_already_held', 'The course already has a description.', 'The machine rule admits a first description only; the proposal is superseded by the retire job or rejected by a person.'); end if;
  if nullif(btrim(i.before_value->>'description'), '') is not null then
    return security.cdesc_machine_fail_v1('before_value_not_empty', 'The proposal was made over an earlier description.', 'A person decides in Layer 4.'); end if;
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_type = 'course' and o.entity_id = c.id and o.field_code = i.field_code and o.status = 'pending' and o.id <> i.id) then
    return security.cdesc_machine_fail_v1('another_pending_item', 'The course has another waiting description.', 'A person decides which one in Layer 4.'); end if;
  -- hand lock and hold
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('description', 'course_description', 'all')) then
    return security.cdesc_machine_fail_v1('manual_lock', 'The description is locked by hand.', 'Release the lock first; a person decides.'); end if;
  if exists (select 1 from pipeline.enrichment_flags fl where fl.reason_code = 'manual_hold' and fl.state <> 'released'
              and ((fl.entity = 'course' and fl.entity_key = c.id::text) or (fl.entity = 'provider' and fl.entity_key = p.id::text))) then
    return security.cdesc_machine_fail_v1('manual_hold', 'A person put a hold on the course or its provider.', 'Release the hold first; a person decides.'); end if;
  -- rejection memory: by course, by page, by text, and a withdrawn machine admission
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_type = 'course' and o.entity_id = c.id and o.field_code = i.field_code and o.status not in ('pending', 'approved', 'edited_approved')) then
    return security.cdesc_machine_fail_v1('rejected_before_course', 'A person decided against an earlier description for this course.', 'A person decides in Layer 4.'); end if;
  if exists (select 1 from pipeline.course_description_machine_admissions a where a.course_id = c.id and a.outcome = 'admitted' and a.withdrawn_at is not null) then
    return security.cdesc_machine_fail_v1('withdrawn_awaiting_person', 'A machine description for this course was withdrawn.', 'A person decides in Layer 4.'); end if;
  if i.evidence_id is not null and exists (select 1 from pipeline.layer4_review_items o where o.field_code = i.field_code and o.evidence_id = i.evidence_id and o.id <> i.id and o.status not in ('pending', 'approved', 'edited_approved')) then
    return security.cdesc_machine_fail_v1('rejected_before_page', 'A person decided against a description read from this same stored page.', 'A person decides in Layer 4.'); end if;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  if v_text is null then return security.cdesc_machine_fail_v1('no_description', 'The proposal has no description.', 'A person decides in Layer 4.'); end if;
  v_md5 := md5(security.cdesc_norm_v1(v_text));
  if exists (select 1 from pipeline.layer4_review_items o where o.field_code = i.field_code and o.id <> i.id and o.status not in ('pending', 'approved', 'edited_approved')
               and md5(security.cdesc_norm_v1(o.proposed_value->>'description')) = v_md5) then
    return security.cdesc_machine_fail_v1('rejected_before_text', 'A person decided against this same wording for another course.', 'A person decides in Layer 4.'); end if;
  -- the right course and the right page
  select * into g from pipeline.coverage_course_pages where course_id = c.id;
  if g.course_id is null then return security.cdesc_machine_fail_v1('binding_missing', 'The course has no bound page.', 'The queue binds the page again.', true); end if;
  if g.status = 'ambiguous' then return security.cdesc_machine_fail_v1('binding_ambiguous', 'The page is bound to the course only ambiguously (more than one candidate).', 'A person decides in Layer 4, or the binding is settled first.'); end if;
  if g.status <> 'bound' then return security.cdesc_machine_fail_v1('binding_' || g.status, 'The course page is ' || g.status || ', not bound.', 'The queue binds the page again.', true); end if;
  if g.provider_id is distinct from c.provider_id then return security.cdesc_machine_fail_v1('binding_other_provider', 'The bound page belongs to another provider.', 'A person decides in Layer 4.'); end if;
  if g.read_status is distinct from 'read' then return security.cdesc_machine_fail_v1('page_not_read', 'The bound page is not marked read.', 'The queue reads the page again.', true); end if;
  if not security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'description') then
    return security.cdesc_machine_fail_v1('identity_not_allowed', 'The page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit a description for this country.', 'A person decides in Layer 4.'); end if;
  -- how firmly the page was matched to this course: an AI match, or a runner-up page scoring close to the chosen one, is not a clear identity
  if g.basis = 'ai_match' or (g.score is not null and g.runner_up is not null and g.score - g.runner_up < 0.1) then -- fixed: a margin under 0.1 between the chosen page and the runner-up is not a clear match; no setting exists for it and none is added (10 Nov 2026 05:40 rule)
    return security.cdesc_machine_fail_v1('identity_margin_thin', 'The page was matched by an AI match or by a score only just above the next candidate (' || coalesce(g.basis, 'no basis') || ', score ' || coalesce(g.score::text, 'none') || ', runner-up ' || coalesce(g.runner_up::text, 'none') || ').', 'A person decides in Layer 4.'); end if;
  if g.evidence_id is distinct from i.evidence_id then
    return security.cdesc_machine_fail_v1('evidence_moved', 'The course''s bound page copy changed after this description was read.', 'The queue reads the new copy; the old proposal is superseded or decided by a person.', true); end if;
  if i.proposed_value->>'source_url' is distinct from g.url then
    return security.cdesc_machine_fail_v1('page_url_changed', 'The page address the description was read from is no longer the bound address.', 'A person decides in Layer 4.'); end if;
  v_fid := case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end;
  select * into f from pipeline.field_enrich_items where id = v_fid;
  if f.id is null or f.field <> 'description' then return security.cdesc_machine_fail_v1('reading_missing', 'The reading behind the proposal is not available.', 'A person decides in Layer 4.'); end if;
  if f.course_id is distinct from c.id then return security.cdesc_machine_fail_v1('reading_other_course', 'The reading belongs to another course.', 'A person decides in Layer 4.'); end if;
  if f.state <> 'review' then return security.cdesc_machine_fail_v1('reading_not_current', 'The reading is in state ' || f.state || ', not waiting.', 'A person decides in Layer 4.'); end if;
  if f.evidence_id is distinct from i.evidence_id then return security.cdesc_machine_fail_v1('reading_other_evidence', 'The reading was made on a different page copy than the proposal names.', 'A person decides in Layer 4.'); end if;
  if nullif(btrim(f.value->>'text'), '') is distinct from v_text then return security.cdesc_machine_fail_v1('text_changed', 'The proposal text differs from the reading it came from.', 'A person decides in Layer 4.'); end if;
  if nullif(btrim(i.layer3_state->>'model'), '') is null or nullif(btrim(i.layer3_state->>'prompt'), '') is null then
    return security.cdesc_machine_fail_v1('reader_unrecorded', 'The reader''s model or prompt version is not recorded.', 'A person decides in Layer 4.'); end if;
  -- the stored page: immutable lineage, present, recent
  select * into e from pipeline.evidence_artifacts where id = i.evidence_id;
  if e.id is null or nullif(btrim(e.storage_path), '') is null or nullif(btrim(e.content_hash), '') is null then
    return security.cdesc_machine_fail_v1('page_not_stored', 'The stored page copy has no object or content hash.', 'The queue reads the course page again.', true); end if;
  if position(e.content_hash in e.storage_path) = 0 then
    return security.cdesc_machine_fail_v1('lineage_hash_mismatch', 'The stored object''s address does not carry the evidence content hash.', 'A person decides in Layer 4.'); end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'evidence' and o.name = e.storage_path) then
    return security.cdesc_machine_fail_v1('object_missing', 'The stored page object is not in storage.', 'The queue reads the course page again.', true); end if;
  if coalesce(e.captured_at, e.created_at) < now() - make_interval(days => v_days) then
    return security.cdesc_machine_fail_v1('evidence_stale', 'The stored page was captured more than ' || v_days || ' days ago.', 'The queue reads the page again; the description is checked on the new copy.', true); end if;
  -- optional independent re-read of the page (nothing writes this table yet): the latest row for this evidence, if there is one
  select * into sc from pipeline.course_description_source_checks s where s.evidence_id = e.id and s.course_id = c.id order by s.checked_at desc limit 1;
  if sc.id is not null then
    if sc.result <> 'confirmed' then return security.cdesc_machine_fail_v1('source_recheck_failed', 'A re-read of the stored page did not confirm the quotes (' || sc.result || ').', 'The queue reads the course page again; a person decides if it persists.', true); end if;
    -- a confirmation counts only if it is recent and it read the very object the evidence names
    if sc.checked_at < now() - make_interval(days => v_days) or sc.content_hash_read is distinct from e.content_hash then
      return security.cdesc_machine_fail_v1('source_recheck_unusable', 'The recorded re-read of the page is older than ' || v_days || ' days or read a different copy (hash read ' || coalesce(left(sc.content_hash_read, 12), 'none') || ', evidence hash ' || left(e.content_hash, 12) || ').', 'Read the page again; a person decides meanwhile.', true); end if;
    v_recheck := 'confirmed';
  end if;
  -- every sentence: the on_page result the worker stored for each quote, supported, complete, in range (the live check, run again now on the stored reading; the page is not read again here)
  v_chk := security.course_description_check_v1(c.id, f.value);
  if not coalesce((v_chk->>'ok')::boolean, false) then
    return security.cdesc_machine_fail_v1('check_' || coalesce(v_chk->>'rule', 'failed'), coalesce(v_chk->>'reason', 'The text check refused it.'), 'A person decides in Layer 4.'); end if;
  if v_chk->>'text' is distinct from v_text then return security.cdesc_machine_fail_v1('text_changed', 'The checked text differs from the proposal.', 'A person decides in Layer 4.'); end if;
  -- the admission policy: claims, ranking, accreditation, outcomes, campus words, markup and figures
  v_sents := coalesce(f.value->'sentences', '[]'::jsonb);
  v_pol := security.pdesc_machine_text_check_ctx_v1(p.id, v_text, '{}', v_sents);
  if v_pol is not null then
    return security.cdesc_machine_fail_v1('policy_' || split_part(v_pol, ':', 1), 'The wording has a word, figure or markup the admission policy does not admit (' || v_pol || ').', 'A person decides in Layer 4.'); end if;
  -- catalogue-wide duplicates: exact (any course, described or waiting) and near (other providers; this provider is covered by the live check above)
  select d.id into v_other from catalogue.courses d where d.id <> c.id and nullif(btrim(d.description), '') is not null and md5(security.cdesc_norm_v1(d.description)) = v_md5 limit 1;
  if v_other is not null then
    return security.cdesc_machine_fail_v1('duplicate_exact_described', 'Another course already holds exactly this wording (shared qualification wording).', 'A person decides in Layer 4.'); end if;
  select o.entity_id into v_other from pipeline.layer4_review_items o where o.field_code = i.field_code and o.status = 'pending' and o.entity_id <> c.id and md5(security.cdesc_norm_v1(o.proposed_value->>'description')) = v_md5 limit 1;
  if v_other is not null then
    return security.cdesc_machine_fail_v1('duplicate_exact_waiting', 'Another waiting description has exactly this wording (shared qualification wording).', 'A person decides in Layer 4.'); end if;
  v_share := security.pipeline_num_v1('pdesc.duplicate_share', 0.8); v_win := security.pipeline_num_v1('enrich.course_description_duplicate_window', 500)::int; v_words := security.pdesc_words_v1(v_text);
  select z.course_id, z.sim into v_dup from (
    select x.course_id, round(k.n::numeric / (cardinality(v_words) + cardinality(x.wb) - k.n), 4) sim
      from (select x0.course_id, array(select distinct w from regexp_split_to_table(lower(coalesce(x0.d, '')), '[^a-z0-9]+') w where length(w) >= 3) wb
              from (select * from (select r.entity_id course_id, r.proposed_value->>'description' d from pipeline.layer4_review_items r join catalogue.courses c2 on c2.id = r.entity_id
                                    where r.field_code = i.field_code and r.status in ('pending', 'approved', 'edited_approved') and r.entity_id <> c.id and c2.provider_id <> c.provider_id
                                    order by r.created_at desc limit v_win) w1
                    union all -- and the descriptions the catalogue holds for other providers (however they arrived), newest first, within the same window
                    select * from (select d2.id course_id, d2.description d from catalogue.courses d2
                                    where nullif(btrim(d2.description), '') is not null and d2.id <> c.id and d2.provider_id <> c.provider_id
                                    order by d2.updated_at desc limit v_win) w2) x0) x
      cross join lateral (select count(*) n from unnest(v_words) w where w = any (x.wb)) k
     where cardinality(v_words) > 0 and cardinality(x.wb) > 0) z
   where z.sim >= v_share order by z.sim desc limit 1;
  if v_dup.course_id is not null then
    return security.cdesc_machine_fail_v1('duplicate_near_other_provider', 'The wording is almost the same as another provider''s course description (' || v_dup.sim || ').', 'A person decides in Layer 4.'); end if;
  return jsonb_build_object('ok', true, 'rule', v_rule, 'course_id', c.id, 'provider_id', p.id, 'review_item_id', i.id, 'reading_item_id', f.id, 'text', v_text, 'text_md5', md5(v_text),
    'evidence_id', e.id, 'content_hash', e.content_hash, 'storage_path', e.storage_path, 'source_url', g.url, 'captured_at', coalesce(e.captured_at, e.created_at),
    'model', i.layer3_state->>'model', 'prompt_version', i.layer3_state->>'prompt', 'worker', i.layer3_state->>'worker', 'source_recheck', v_recheck,
    'checks', coalesce(v_chk->'checks', '{}'::jsonb) || jsonb_build_object('identity_basis', g.identity_basis, 'binding', g.status, 'policy', 'ok'));
end $f$;
comment on function security.course_description_machine_check_v1(uuid) is 'CF-247 F-CDESC machine rule cdesc-machine-v1, the safe class (read only): for one waiting first course description, ok with the evidence it rests on, or the exact reason code and next action: course and provider live, description still empty, no hand lock, hold or earlier rejection (by course, page or wording), the page bound (not ambiguous), read, identity allowed, matched with a clear margin and not by AI match, unchanged, stored with its content hash in the object address, present in storage and recent (gaps.recheck_days), the quote results the worker stored for each sentence and the support, length and in-provider duplicate checks (the live text check, run again on the stored reading; the page itself is not read again), the admission policy for claims and figures, no exact duplicate anywhere in the catalogue, no near duplicate (word overlap at pdesc.duplicate_share) among other providers'' waiting or approved proposals and described courses within the comparison window enrich.course_description_duplicate_window (older text or a paraphrase is not caught), and an optional recorded re-read of the page (a failed one declines; a confirmed one counts only if recent and for the same content hash). Changes nothing.';
revoke all on function security.course_description_machine_check_v1(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- shadow report (read only)
create or replace function security.course_description_machine_shadow_v1(p_limit integer default null, p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare r record; v jsonb; v_lim int := coalesce(p_limit, 200); -- fixed: a report page, the evaluation is the bounded cost
        v_by jsonb := '{}'::jsonb; v_ok int := 0; v_n int := 0; v_sample jsonb := '[]'::jsonb; v_total int; v_prov jsonb := '{}'::jsonb; v_held int; v_held_policy int; hr record;
begin
  select count(*) into v_total from pipeline.layer4_review_items li where li.field_code = 'course_description_first_read' and li.entity_type = 'course' and li.status = 'pending';
  for r in select li.id, li.entity_id from pipeline.layer4_review_items li where li.field_code = 'course_description_first_read' and li.entity_type = 'course' and li.status = 'pending'
            order by li.created_at, li.id limit v_lim offset greatest(coalesce(p_offset, 0), 0) loop
    v := security.course_description_machine_check_v1(r.id);
    v_n := v_n + 1;
    if (v->>'ok')::boolean then
      v_ok := v_ok + 1;
      if jsonb_array_length(v_sample) < 5 then v_sample := v_sample || jsonb_build_array(jsonb_build_object('review_item_id', r.id, 'course_id', r.entity_id, 'chars', length(v->>'text'))); end if;
    else
      v_by := jsonb_set(v_by, array[v->>'rule'], to_jsonb(coalesce((v_by->>(v->>'rule'))::int, 0) + 1));
    end if;
  end loop;
  -- readings held at the provider's waiting cap: not yet items; counted, and how many pass the wording policy alone
  select count(*) into v_held from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%' and nullif(btrim(e.value->>'text'), '') is not null;
  select count(*) into v_held_policy from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%' and nullif(btrim(e.value->>'text'), '') is not null
     and security.pdesc_machine_text_check_ctx_v1(e.provider_id, e.value->>'text', '{}', coalesce(e.value->'sentences', '[]'::jsonb)) is null;
  return jsonb_build_object('contract', 'course-description-machine-shadow-v1', 'rule', 'cdesc-machine-v1', 'as_at', now(), 'switch_on', security.pipeline_num_v1('enrich.course_description_machine_on', 0) >= 1,
    'waiting_items', v_total, 'examined', v_n, 'offset', greatest(coalesce(p_offset, 0), 0), 'would_admit', v_ok, 'stay_for_a_person', v_n - v_ok, 'by_reason', v_by, 'sample_would_admit', v_sample,
    'held_readings', jsonb_build_object('count', v_held, 'pass_wording_policy', v_held_policy, 'note', 'held at the provider''s waiting cap; promoted to items by the existing promote-held step as room appears, then evaluated like any waiting item'),
    'next_offset', case when greatest(coalesce(p_offset, 0), 0) + v_n < v_total then greatest(coalesce(p_offset, 0), 0) + v_n end);
end $f$;
comment on function security.course_description_machine_shadow_v1(integer, integer) is 'CF-247 F-CDESC shadow report (read only, changes nothing, works with the switch off): runs the safe-class evaluator over the waiting first course descriptions (a page of p_limit from p_offset, 200 by default) and returns how many would be admitted, why the rest stay for a person (reason codes), a sample, and the held readings. Page through with next_offset.';
revoke all on function security.course_description_machine_shadow_v1(integer, integer) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.course_description_machine_admissions', 'Layer 4', 'Ledger of first course descriptions admitted or declined by the machine rule cdesc-machine-v1', 'active', '{}', '20261110060000'),
 ('table', 'pipeline.course_description_source_checks', 'Layer 4', 'Optional record of an independent re-read of a stored course page (quotes found, hash read); empty until a later change writes to it', 'active', '{}', '20261110060000'),
 ('function', 'security.course_description_machine_check_v1', 'Layer 4', 'Safe-class evaluator for one waiting first course description (read only)', 'active', '{}', '20261110060000'),
 ('function', 'security.course_description_machine_shadow_v1', 'Layer 4', 'Shadow report over the waiting first course descriptions (read only)', 'active', '{}', '20261110060000')
on conflict do nothing;

do $post$ begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', -1) <> 0 then raise exception 'post-check: the machine switch must exist and be 0'; end if;
  if security.pipeline_num_v1('enrich.course_description_review_first', 0) < 1 then raise exception 'post-check: review_first must be untouched'; end if;
end $post$;
