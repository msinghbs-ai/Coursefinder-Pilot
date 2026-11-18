-- CF-247 (21 Oct 2026). Platform Admin 20:02: "Build fee reader for nz unis and make sure its compatible to ca and upcoming countries. The
-- logic has to be built by using ai model in the platform and collect and feed error to build and evolve data reader and help in
-- enrichment. ... think along the lines if the reader built for existing uni and country changes in coming month what will be required to
-- fix it align to new design or feature." Choices: "Automatic above confidence", "As published + yearly estimate", "NZ universities, then
-- NZ rest, then CA".
-- Why: the fee-schedule reader finds rows by CRICOS code, which only Australian courses have; New Zealand and Canadian fee tables list
-- qualifications by name (Otago: one table per division). 1,080 NZ courses hold a fee, from course pages only.
-- The fee reader:
--   1 Pages: each provider's fee pages are central pages (pipeline.provider_fact_sources, kind fee_schedule), read and stored by job
--     provider-facts. The reader adds suggestions from the central-page search (score at least fees.min_suggest_score) and the further fee
--     pages the AI finds linked from a fee page (fees.max_pages_per_provider). Job provider-facts is woken when pages wait.
--   2 AI reading (worker mode fee_ai, the platform's pinned central-page model in pipeline.central_ai_settings): every row as published
--     (qualification, subject, level, amount or range, currency, unit, domestic or international, fee year, a quote that must be on the
--     page) and the matching course from the provider's own list, with a confidence.
--   3 Country rules: pipeline.fee_country_profiles (currency, usual unit, full-time load a year, terms a year). A new country is a row
--     there, not new code. A fee per credit, point or term keeps the published amount and gets a yearly estimate from the full-time load.
--   4 Admission ("Automatic above confidence"): a row is admitted when the AI's match confidence is at least fees.auto_admit_confidence,
--     the title agrees (security.fee_title_similarity_v1 at least fees.min_title_similarity), the amount is within fees.outlier_ratio of
--     the country's held fees and the course holds no different fee from another source. Otherwise it goes to Layer 4 for a person.
--   5 Learning: pipeline.fee_reader_findings keeps every miss (no rows, rows matched to no course, currency, unit not understood, outliers,
--     quotes not on the page, conflicts, rows a person rejected, a page that changed or now gives far fewer rows). The latest open
--     findings and the provider's reading notes (pipeline.fee_reader_recipes, versioned, written by the AI from what it saw) go into the
--     next read of that provider, so the reader corrects itself.
--   6 A page that changes is read again (new content hash); a big drop in rows is a finding, and the provider's notes are rewritten.
--   7 Rollout from settings: fees.countries (["NZ"]) and fees.provider_types (["university"]); then NZ polytechnics and private providers,
--     then Canada, by changing the settings.
-- Replaces: security.ai_spend_today_v1 (fee_ai spend); security.worker_mode_waiting_v1 (provider_facts and fee_ai wake). Both md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): fees are written by security.coverage_apply_course_v1 into
-- catalogue.course_fees as provider_current_tuition, as the course-page reader does.

do $guard$
declare v_expected jsonb := '{"security.ai_spend_today_v1()": "12943a97ec013cc0f38ec655cfba832d",
                              "security.worker_mode_waiting_v1(text)": "57699fcfcde9eee300aef28a8a34cfef",
                              "security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)": "0f3beaac5ed5d4f2ded8a125f569cdfc"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change relies on', v_sig;
    end if;
  end loop;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- Settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'fees.countries', 'Fee reader: countries', 'Countries whose providers'' fee pages the AI fee reader reads.', 'list', '["NZ"]'::jsonb, null, null, 'countries', 340,
  'CF-247, Platform Admin 21 Oct 2026 20:02 "NZ universities, then NZ rest, then CA"', 'Enrichment', 'job fee-reader'),
 ('pipeline', 'fees.provider_types', 'Fee reader: provider types', 'Provider types read (university, tafe_polytechnic, wananga, private_vet, other). Widen to roll out.', 'list', '["university"]'::jsonb, null, null, 'types', 341,
  'CF-247, Platform Admin 21 Oct 2026 20:02 "NZ universities, then NZ rest, then CA"', 'Enrichment', 'job fee-reader'),
 ('pipeline', 'fees.auto_admit_confidence', 'Fee reader: admit automatically at match confidence', 'A fee row is admitted without a person when the AI''s match to the course is at least this sure (0 to 1) and the other checks pass; otherwise it goes to Layer 4.', 'number', to_jsonb(0.85), 0.5, 1, 'confidence', 342,
  'CF-247, Platform Admin 21 Oct 2026 20:02 "Automatic above confidence"', 'Enrichment', 'security.fee_reader_record_v1'),
 ('pipeline', 'fees.min_title_similarity', 'Fee reader: title agreement needed', 'Share of words the fee row''s qualification and the course title must share (0 to 1) for an automatic admission.', 'number', to_jsonb(0.6), 0, 1, 'share', 343,
  'CF-247, Platform Admin 21 Oct 2026 20:02', 'Enrichment', 'security.fee_reader_record_v1'),
 ('pipeline', 'fees.outlier_ratio', 'Fee reader: outside the usual range by', 'A yearly fee more than this many times above or below the median of the country''s held yearly fees is not admitted automatically.', 'number', to_jsonb(4), 1.5, 20, 'times', 344,
  'CF-247, Platform Admin 21 Oct 2026 20:02', 'Enrichment', 'security.fee_reader_record_v1'),
 ('pipeline', 'fees.min_suggest_score', 'Fee reader: take central-search suggestions from score', 'Fee pages suggested by the central-page search at or above this score are added for reading.', 'number', to_jsonb(4), 0, 10, 'score', 345,
  'CF-247, Platform Admin 21 Oct 2026 20:02', 'Enrichment', 'security.fee_reader_tick_v1'),
 ('pipeline', 'fees.max_pages_per_provider', 'Fee reader: fee pages a provider', 'The most fee pages kept for one provider (suggested and found by the AI).', 'number', to_jsonb(12), 1, 60, 'pages', 346,
  'CF-247, Platform Admin 21 Oct 2026 20:02', 'Enrichment', 'security.fee_reader_record_v1'),
 ('pipeline', 'fees.pages_per_run', 'Fee reader: pages a run', 'Fee pages one worker call reads with AI.', 'number', to_jsonb(3), 1, 10, 'pages', 347,
  'CF-247, Platform Admin 21 Oct 2026 20:02', 'Job sizes', 'job fee-reader'),
 ('pipeline', 'fees.page_chars', 'Fee reader: page text sent to the AI', 'Characters of a stored fee page sent in one AI call.', 'number', to_jsonb(40000), 5000, 120000, 'characters', 348,
  'CF-247, Platform Admin 21 Oct 2026 20:02', 'Enrichment', 'worker mode fee_ai'),
 ('pipeline', 'fees.findings_in_prompt', 'Fee reader: past problems given to the AI', 'Open findings of the provider given to the AI with each read, newest first.', 'number', to_jsonb(10), 0, 50, 'findings', 349,
  'CF-247, Platform Admin 21 Oct 2026 20:02 "collect and feed error to build and evolve data reader"', 'Enrichment', 'security.fee_reader_next_v1'),
 ('openrouter', 'guard_fee_ai', 'Fee reader with AI', 'AI US$ a day for the fee reader.', 'number', to_jsonb(5), 0, 100, 'US$ a day', 60,
  'CF-247, Platform Admin 21 Oct 2026 20:02', 'Daily guards', 'job fee-reader')
on conflict (toolset_key, key) do nothing;

-- Country rules ----------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.fee_country_profiles (
  country_code text primary key,
  currency_code text not null,
  usual_unit text not null check (usual_unit in ('per_year', 'per_credit', 'per_point', 'per_term', 'per_course')),
  full_time_units_a_year numeric,
  unit_name text,
  terms_a_year numeric,
  notes text,
  reason text not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
comment on table pipeline.fee_country_profiles is 'CF-247 21 Oct 2026: how a country publishes tuition, for the AI fee reader: currency, usual unit, full-time load a year (credits or points) and terms a year, used to work out a yearly estimate from a fee per credit, point or term. A new country is a row here. Changed on Layer 2/3 › Enrich fields › Fee reader (Platform Admin, with a reason).';
alter table pipeline.fee_country_profiles enable row level security;
insert into pipeline.fee_country_profiles(country_code, currency_code, usual_unit, full_time_units_a_year, unit_name, terms_a_year, notes, reason) values
 ('NZ', 'NZD', 'per_year', 120, 'points (credits)', 2, 'Universities publish a yearly fee per qualification; a full-time year is 120 points (1 EFTS); some list a fee per paper or point.', 'CF-247 21 Oct 2026'),
 ('CA', 'CAD', 'per_credit', 30, 'credits', 2, 'Universities often publish per credit or per term; a full-time year is about 30 credits (two terms of 15).', 'CF-247 21 Oct 2026'),
 ('AU', 'AUD', 'per_year', 8, 'units (subjects)', 2, 'Universities publish a yearly or per-unit fee; a full-time year is about 8 units (48 credit points).', 'CF-247 21 Oct 2026')
on conflict (country_code) do nothing;

-- Reader tables ----------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.fee_reader_queue (
  id uuid primary key default gen_random_uuid(),
  fact_source_id uuid not null,
  provider_id uuid not null,
  content_hash text not null,
  state text not null default 'queued' check (state in ('queued', 'leased', 'done', 'failed')),
  leased_until timestamptz,
  attempts int not null default 0,
  rows_found int,
  cost_usd numeric,
  model text,
  error text,
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  unique (fact_source_id, content_hash)
);
comment on table pipeline.fee_reader_queue is 'CF-247 21 Oct 2026: one AI fee read per fee page and page version (content hash); a changed page is read again. Filled by job fee-reader, worked by worker mode fee_ai.';
alter table pipeline.fee_reader_queue enable row level security;

create table if not exists pipeline.fee_reader_rows (
  id uuid primary key default gen_random_uuid(),
  queue_id uuid not null,
  fact_source_id uuid not null,
  provider_id uuid not null,
  qualification text,
  subject text,
  level text,
  amount_min numeric,
  amount_max numeric,
  currency_code text,
  unit text,
  audience text,
  fee_year int,
  quote text,
  yearly numeric,
  yearly_basis text,
  course_id uuid,
  match_confidence numeric,
  title_similarity numeric,
  outcome text not null,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists fee_reader_rows_provider on pipeline.fee_reader_rows(provider_id, created_at desc);
create index if not exists fee_reader_rows_queue on pipeline.fee_reader_rows(queue_id);
comment on table pipeline.fee_reader_rows is 'CF-247 21 Oct 2026: every fee row the AI fee reader read, as published (amount or range, unit, audience, fee year, quote), its yearly figure (published or estimated), the course it was matched to and what happened (admitted, review, same, conflict, no_course, domestic, not_yearly, skipped).';
alter table pipeline.fee_reader_rows enable row level security;

create table if not exists pipeline.fee_reader_findings (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null,
  fact_source_id uuid,
  kind text not null check (kind in ('no_rows', 'unmatched_row', 'currency', 'unit_unknown', 'outlier', 'quote_missing', 'conflict', 'rejected', 'page_changed', 'rows_dropped', 'read_failed')),
  key text not null default '',
  detail jsonb not null default '{}'::jsonb,
  times int not null default 1,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  resolved_at timestamptz,
  unique (provider_id, kind, key)
);
comment on table pipeline.fee_reader_findings is 'CF-247 21 Oct 2026 ("collect and feed error to build and evolve data reader"): what the fee reader got wrong or could not do, per provider; the newest open ones are given to the AI on the next read and shown on the Fee reader card. Resolved when the next read no longer has them.';
alter table pipeline.fee_reader_findings enable row level security;

create table if not exists pipeline.fee_reader_recipes (
  provider_id uuid primary key,
  version int not null default 1,
  notes text not null,
  history jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by text not null default 'fee_ai'
);
comment on table pipeline.fee_reader_recipes is 'CF-247 21 Oct 2026: how a provider''s fee pages are laid out, in the AI''s words or a person''s (versioned, the last five kept in history); given to the AI with every read of that provider, so a site that changes gets new notes on the next read.';
alter table pipeline.fee_reader_recipes enable row level security;

-- Helpers ----------------------------------------------------------------------------------------------------------------------------
create or replace function security.fee_title_words_v1(p text)
 returns text[]
 language sql
 immutable
 set search_path to ''
as $function$
  select coalesce(array(select distinct w from regexp_split_to_table(lower(regexp_replace(coalesce(p, ''), '\(level [0-9]+\)|&#[0-9]+;|[^a-zA-Z0-9 ]', ' ', 'g')), '\s+') w
                  where length(w) > 1 and w not in ('of', 'in', 'and', 'the', 'with', 'for', 'level', 'honours', 'hons')), '{}')
$function$;

create or replace function security.fee_title_similarity_v1(a text, b text)
 returns numeric
 language sql
 immutable
 set search_path to ''
as $function$
  -- share of the course title's words found in the fee row's words (qualification and subject together)
  select case when cardinality(security.fee_title_words_v1(b)) = 0 then 0
              else round(cardinality(array(select unnest(security.fee_title_words_v1(b)) intersect select unnest(security.fee_title_words_v1(a))))::numeric
                         / cardinality(security.fee_title_words_v1(b)), 3) end
$function$;

create or replace function security.fee_reader_in_scope_v1(p_provider uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
     where p.id = p_provider
       and k.iso_alpha2 in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.countries')
       and coalesce(t.code, 'other') in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.provider_types')
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id))
$function$;

create or replace function security.fee_reader_finding_v1(p_provider uuid, p_source uuid, p_kind text, p_key text, p_detail jsonb)
 returns void
 language sql
 security definer
 set search_path to ''
as $function$
  insert into pipeline.fee_reader_findings(provider_id, fact_source_id, kind, key, detail)
  values (p_provider, p_source, p_kind, left(coalesce(p_key, ''), 200), coalesce(p_detail, '{}'::jsonb))
  on conflict (provider_id, kind, key) do update set times = pipeline.fee_reader_findings.times + 1, last_seen = now(), detail = excluded.detail,
         fact_source_id = coalesce(excluded.fact_source_id, pipeline.fee_reader_findings.fact_source_id), resolved_at = null
$function$;
revoke execute on function security.fee_reader_finding_v1(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
revoke execute on function security.fee_reader_in_scope_v1(uuid) from public, anon, authenticated;

-- The tick: pages, queue, learning, worker ---------------------------------------------------------------------------------------------
create or replace function security.fee_reader_tick_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_added int := 0; v_queued int := 0; v_rejected int := 0; v_fired int := 0;
        v_max int := security.pipeline_num_v1('fees.max_pages_per_provider', 12)::int;
begin
  -- 1 fee pages suggested by the central-page search, for providers in scope
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
  select x.provider_id, 'fee_schedule', x.url, left(x.title, 200), 5, 'search', 'found'
    from (select s.provider_id, e->>'url' url, e->>'title' title, row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc) rn
            from pipeline.provider_central_search s cross join lateral jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
           where e->>'kind' = 'fee_schedule' and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('fees.min_suggest_score', 4)
             and security.fee_reader_in_scope_v1(s.provider_id)) x
   where x.rn <= v_max and x.url ~ '^https?://'
     and (select count(*) from pipeline.provider_fact_sources f where f.provider_id = x.provider_id and f.kind = 'fee_schedule') < v_max
  on conflict (provider_id, kind, url) do nothing;
  get diagnostics v_added = row_count;

  -- 2 queue every stored fee page version not read yet; a new version of a page read before is a finding
  insert into pipeline.fee_reader_queue(fact_source_id, provider_id, content_hash)
  select f.id, f.provider_id, f.content_hash
    from pipeline.provider_fact_sources f join pipeline.evidence_artifacts e on e.id = f.evidence_id
   where f.kind = 'fee_schedule' and f.content_hash is not null and e.storage_path is not null and f.status in ('read', 'no_values', 'parsed')
     and security.fee_reader_in_scope_v1(f.provider_id)
  on conflict (fact_source_id, content_hash) do nothing;
  get diagnostics v_queued = row_count;
  perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'page_changed', q.fact_source_id::text, jsonb_build_object('url', f.url))
     from pipeline.fee_reader_queue q join pipeline.provider_fact_sources f on f.id = q.fact_source_id
    where q.state = 'queued' and q.created_at > now() - interval '15 minutes'  -- fixed: the tick runs every 10 minutes
      and exists (select 1 from pipeline.fee_reader_queue o where o.fact_source_id = q.fact_source_id and o.content_hash <> q.content_hash and o.state = 'done');

  -- 3 rows a person rejected or corrected in Layer 4 are findings the reader learns from
  with r as (
    select l.entity_id course_id, fr.provider_id, fr.qualification, l.status decision
      from pipeline.layer4_review_items l
      join pipeline.fee_reader_rows fr on fr.course_id = l.entity_id and fr.outcome = 'review'
     where l.field_code = 'provider_current_tuition_validation' and l.status in ('rejected', 'edited_approved') and l.layer2_state->>'source' = 'fee reader'
       and l.decided_at > now() - interval '1 day')  -- fixed: look-back longer than the 10-minute tick
  select count(*) into v_rejected from (
    select security.fee_reader_finding_v1(r.provider_id, null, 'rejected', r.course_id::text,
             jsonb_build_object('qualification', r.qualification, 'decision', r.decision)) from r) z;

  -- 4 the worker, while there is work and AI budget
  if exists (select 1 from pipeline.fee_reader_queue q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now()))
     and not exists (select 1 from pipeline.fee_reader_queue q where q.state = 'leased' and q.leased_until > now())
     and security.ai_use_allowed_v1('fee_ai') then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fee_ai', 'limit', security.pipeline_num_v1('fees.pages_per_run', 3)::int));
    v_fired := 1;
  end if;
  return jsonb_build_object('pages_added', v_added, 'queued', v_queued, 'rejected_seen', v_rejected, 'worker', v_fired);
end $function$;
revoke execute on function security.fee_reader_tick_v1() from public, anon, authenticated;

-- What the worker reads ---------------------------------------------------------------------------------------------------------------
create or replace function public.svc_fee_ai_next(p_limit int)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v jsonb := '[]'::jsonb; q record;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  for q in
    update pipeline.fee_reader_queue x set state = 'leased', leased_until = now() + interval '4 minutes', attempts = attempts + 1  -- fixed: lease longer than one worker call
     where x.id in (select y.id from pipeline.fee_reader_queue y
                     where (y.state = 'queued' or (y.state = 'leased' and y.leased_until < now())) and y.attempts < 3  -- fixed: three tries
                     order by y.created_at limit greatest(1, least(coalesce(p_limit, 3), 10)) for update skip locked)
    returning x.*
  loop
    v := v || (
      select jsonb_build_object(
        'queue_id', q.id, 'source_id', f.id, 'url', f.url, 'storage_path', e.storage_path,
        'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2,
        'profile', (select to_jsonb(cp) - 'reason' - 'updated_by' - 'updated_at' from pipeline.fee_country_profiles cp where cp.country_code = k.iso_alpha2),
        'model', (select s.model_identifier from pipeline.central_ai_settings s where s.id = 1),
        'model_code', (select s.model_code from pipeline.central_ai_settings s where s.id = 1),
        'page_chars', security.pipeline_num_v1('fees.page_chars', 40000)::int,
        'notes', (select r.notes from pipeline.fee_reader_recipes r where r.provider_id = q.provider_id),
        'findings', coalesce((select jsonb_agg(jsonb_build_object('kind', z.kind, 'detail', z.detail, 'times', z.times) order by z.last_seen desc)
                                from (select * from pipeline.fee_reader_findings x where x.provider_id = q.provider_id and x.resolved_at is null
                                      order by x.last_seen desc limit security.pipeline_num_v1('fees.findings_in_prompt', 10)::int) z), '[]'::jsonb),
        'courses', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'title', c.canonical_title, 'level', sl.code) order by c.canonical_title)
                               from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id
                              where c.provider_id = q.provider_id and c.lifecycle_status = 'active'), '[]'::jsonb))
        from pipeline.provider_fact_sources f join pipeline.evidence_artifacts e on e.id = f.evidence_id
        join catalogue.providers p on p.id = f.provider_id join ref.countries k on k.id = p.country_id
       where f.id = q.fact_source_id);
  end loop;
  return v;
end $function$;
revoke execute on function public.svc_fee_ai_next(int) from public, anon, authenticated;
grant execute on function public.svc_fee_ai_next(int) to service_role;

-- What the worker reports: rows, admission, review, findings, notes, more pages ------------------------------------------------------
create or replace function public.svc_fee_ai_record(p_queue_id uuid, p_result jsonb, p_cost numeric, p_error text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare q pipeline.fee_reader_queue%rowtype; f pipeline.provider_fact_sources%rowtype; v_cc text; v_cur text; pr pipeline.fee_country_profiles%rowtype;
        r jsonb; v_rows int := 0; v_out jsonb := '{}'::jsonb; v_min_conf numeric := security.pipeline_num_v1('fees.auto_admit_confidence', 0.85);
        v_min_sim numeric := security.pipeline_num_v1('fees.min_title_similarity', 0.6); v_ratio numeric := security.pipeline_num_v1('fees.outlier_ratio', 4);
        v_median numeric; v_src uuid; v_hash text; v_url text; v_prev int; c record; v_year int := extract(year from now() at time zone 'Pacific/Auckland')::int;
        v_max int := security.pipeline_num_v1('fees.max_pages_per_provider', 12)::int; v_notes text; v_x record;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  select * into q from pipeline.fee_reader_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('error', 'unknown queue item'); end if;
  select * into f from pipeline.provider_fact_sources where id = q.fact_source_id;
  select k.iso_alpha2 into v_cc from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = q.provider_id;
  select * into pr from pipeline.fee_country_profiles where country_code = v_cc;
  v_cur := coalesce(pr.currency_code, (select a.currency_code from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = v_cc));
  if p_error is not null then
    update pipeline.fee_reader_queue set state = case when attempts >= 3 then 'failed' else 'queued' end, error = left(p_error, 500), cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0), leased_until = null where id = q.id;
    if q.attempts >= 3 then perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'read_failed', q.fact_source_id::text, jsonb_build_object('error', left(p_error, 300), 'url', f.url)); end if;
    return jsonb_build_object('error', p_error);
  end if;
  v_src := security.coverage_sweep_source(q.provider_id);
  v_median := (select percentile_cont(0.5) within group (order by cf.amount) from catalogue.course_fees cf join catalogue.courses c2 on c2.id = cf.course_id
                 join catalogue.providers p2 on p2.id = c2.provider_id join ref.countries k2 on k2.id = p2.country_id
                where k2.iso_alpha2 = v_cc and cf.fee_type = 'provider_current_tuition' and cf.status = 'active' and cf.basis in ('annual', 'indicative_annual'));

  -- 1 each row as published, its yearly figure and its course
  for r in select * from jsonb_array_elements(coalesce(p_result->'rows', '[]'::jsonb)) loop
    v_rows := v_rows + 1;
    insert into pipeline.fee_reader_rows(queue_id, fact_source_id, provider_id, qualification, subject, level, amount_min, amount_max, currency_code, unit, audience, fee_year, quote,
                                         yearly, yearly_basis, course_id, match_confidence, title_similarity, outcome)
    select q.id, q.fact_source_id, q.provider_id, left(r->>'qualification', 300), left(r->>'subject', 300), left(r->>'level', 60),
           nullif(r->>'amount_min', '')::numeric, nullif(r->>'amount_max', '')::numeric, upper(coalesce(r->>'currency', v_cur)), coalesce(r->>'unit', 'unknown'),
           coalesce(r->>'audience', 'international'), nullif(r->>'fee_year', '')::int, left(r->>'quote', 500),
           case coalesce(r->>'unit', 'unknown')
             when 'per_year' then nullif(r->>'amount_min', '')::numeric
             when 'per_credit' then nullif(r->>'amount_min', '')::numeric * pr.full_time_units_a_year
             when 'per_point' then nullif(r->>'amount_min', '')::numeric * pr.full_time_units_a_year
             when 'per_term' then nullif(r->>'amount_min', '')::numeric * pr.terms_a_year end,
           case coalesce(r->>'unit', 'unknown') when 'per_year' then 'annual' when 'per_credit' then 'indicative_annual' when 'per_point' then 'indicative_annual'
                when 'per_term' then 'indicative_annual' end,
           (select c2.id from catalogue.courses c2 where c2.id = nullif(r->>'course_id', '')::uuid and c2.provider_id = q.provider_id),
           least(greatest(coalesce(nullif(r->>'match_confidence', '')::numeric, 0), 0), 1),
           (select security.fee_title_similarity_v1(coalesce(r->>'qualification', '') || ' ' || coalesce(r->>'subject', ''), c2.canonical_title)
              from catalogue.courses c2 where c2.id = nullif(r->>'course_id', '')::uuid and c2.provider_id = q.provider_id),
           'pending';
  end loop;

  -- 2 outcome of each row
  update pipeline.fee_reader_rows x set outcome = case
      when x.currency_code is distinct from v_cur then 'skipped'
      when x.audience <> 'international' then 'domestic'
      when x.yearly is null then 'not_yearly'
      when x.course_id is null then 'no_course'
      else 'matched' end,
      note = case when x.currency_code is distinct from v_cur then 'currency ' || coalesce(x.currency_code, '?') || ' is not ' || v_cur
                  when x.unit not in ('per_year', 'per_credit', 'per_point', 'per_term', 'per_course') then 'unit not understood' end
   where x.queue_id = q.id;
  for v_x in select * from pipeline.fee_reader_rows where queue_id = q.id
             and (outcome in ('skipped', 'no_course') or (outcome = 'not_yearly' and unit <> 'per_course')) loop
    perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id,
      case when v_x.outcome = 'skipped' then 'currency' when v_x.outcome = 'not_yearly' then 'unit_unknown' else 'unmatched_row' end,
      coalesce(v_x.qualification, '') || ' ' || coalesce(v_x.subject, ''),
      jsonb_build_object('qualification', v_x.qualification, 'subject', v_x.subject, 'unit', v_x.unit, 'currency', v_x.currency_code, 'url', f.url));
  end loop;

  -- 3 one fee per course: the lowest yearly figure of its rows (a range is kept in the note), then admit, review, same or conflict
  for c in
    select x.course_id, min(x.yearly) yearly, max(x.yearly) high, max(x.fee_year) fee_year, min(x.match_confidence) conf, min(x.title_similarity) sim,
           (array_agg(x.yearly_basis order by x.yearly))[1] basis, (array_agg(x.quote order by x.yearly))[1] quote, count(*) n,
           (array_agg(x.unit order by x.yearly))[1] unit, (array_agg(x.amount_min order by x.yearly))[1] published
      from pipeline.fee_reader_rows x where x.queue_id = q.id and x.outcome = 'matched' group by x.course_id
  loop
    declare v_held record; v_outcome text; v_note text;
    begin
      select cf.amount, cf.source_id into v_held from catalogue.course_fees cf
       where cf.course_id = c.course_id and cf.fee_type = 'provider_current_tuition' and cf.status = 'active' order by cf.updated_at desc limit 1;
      v_note := case when c.high > c.yearly then 'from ' || c.yearly || ' to ' || c.high || ' by subject; ' else '' end
             || case when c.basis = 'indicative_annual' then 'yearly estimate from ' || c.published || ' ' || replace(c.unit, '_', ' ') || ' x full-time load; ' else '' end
             || 'AI fee reader (' || f.url || ')';
      v_outcome := case
        when v_held.amount is not null and abs(v_held.amount - c.yearly) <= greatest(1, v_held.amount * 0.01) then 'same'  -- fixed: rounding
        when v_held.amount is not null and v_held.source_id is distinct from v_src then 'conflict'
        when c.conf >= v_min_conf and coalesce(c.sim, 0) >= v_min_sim and (v_median is null or c.yearly between v_median / v_ratio and v_median * v_ratio)
             and coalesce(c.fee_year, v_year) >= v_year - 1 then 'admitted'
        else 'review' end;
      if v_outcome = 'admitted' then
        begin
          perform security.coverage_apply_course_v1(c.course_id, v_src, f.evidence_id, f.url, f.content_hash,
            jsonb_build_object('fee_amount', round(c.yearly, 2), 'currency_code', v_cur, 'fee_year', c.fee_year, 'fee_basis', c.basis, 'fee_notes', left(v_note, 500)));
        exception when others then
          v_outcome := 'review'; v_note := v_note || '; not admitted: ' || left(sqlerrm, 200);
        end;
      end if;
      if v_outcome in ('review', 'conflict') and not exists (select 1 from pipeline.layer4_review_items l where l.entity_id = c.course_id
                                                                and l.field_code = 'provider_current_tuition_validation' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', c.course_id, 'provider_current_tuition_validation', f.evidence_id,
                case when v_held.amount is not null then jsonb_build_object('amount', v_held.amount) else '{}'::jsonb end,
                jsonb_build_object('amount', round(c.yearly, 2), 'currency_code', v_cur, 'basis', case when c.basis = 'annual' then 'annual' else 'indicative_annual' end,
                                   'audience', 'international', 'fee_year', c.fee_year),
                jsonb_build_object('page', f.url, 'source', 'fee reader', 'quote', c.quote, 'match_confidence', c.conf, 'title_similarity', c.sim, 'note', v_note),
                '{}'::jsonb, 'pending',
                case when v_outcome = 'conflict' then 'Fee reader: a different fee is held from another source'
                     when c.conf < v_min_conf then 'Fee reader: course match not sure enough'
                     when coalesce(c.sim, 0) < v_min_sim then 'Fee reader: qualification and course title differ'
                     else 'Fee reader: outside the usual range or an old fee year' end,
                'CF-CHG-20260915-247');
      end if;
      if v_outcome = 'conflict' then
        perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'conflict', c.course_id::text, jsonb_build_object('held', v_held.amount, 'read', c.yearly));
      elsif v_outcome = 'review' and v_median is not null and c.yearly not between v_median / v_ratio and v_median * v_ratio then
        perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'outlier', c.course_id::text, jsonb_build_object('read', c.yearly, 'median', round(v_median)));
      end if;
      update pipeline.fee_reader_rows set outcome = v_outcome, note = left(v_note, 500) where queue_id = q.id and course_id = c.course_id and outcome = 'matched';
      v_out := jsonb_set(v_out, array[v_outcome], to_jsonb(coalesce((v_out->>v_outcome)::int, 0) + 1));
    end;
  end loop;

  -- 4 the AI's quotes that were not on the page (counted by the worker) and the size of the read
  if coalesce((p_result->>'quotes_missing')::int, 0) > 0 then
    perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'quote_missing', q.fact_source_id::text, jsonb_build_object('rows', (p_result->>'quotes_missing')::int, 'url', f.url));
  end if;
  if v_rows = 0 then
    perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'no_rows', q.fact_source_id::text, jsonb_build_object('url', f.url));
  else
    update pipeline.fee_reader_findings set resolved_at = now() where provider_id = q.provider_id and fact_source_id = q.fact_source_id and kind in ('no_rows', 'read_failed') and resolved_at is null;
  end if;
  select o.rows_found into v_prev from pipeline.fee_reader_queue o where o.fact_source_id = q.fact_source_id and o.state = 'done' and o.id <> q.id order by o.finished_at desc limit 1;
  if v_prev is not null and v_rows < v_prev / 2 then
    perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'rows_dropped', q.fact_source_id::text, jsonb_build_object('before', v_prev, 'now', v_rows, 'url', f.url));
  end if;

  -- 5 the AI's notes on how this provider's fee pages are laid out (versioned)
  v_notes := nullif(btrim(left(p_result->>'page_notes', 1500)), '');
  if v_notes is not null then
    insert into pipeline.fee_reader_recipes(provider_id, notes) values (q.provider_id, v_notes)
    on conflict (provider_id) do update set history = (jsonb_build_array(jsonb_build_object('version', pipeline.fee_reader_recipes.version, 'notes', pipeline.fee_reader_recipes.notes,
                                                         'at', pipeline.fee_reader_recipes.updated_at, 'by', pipeline.fee_reader_recipes.updated_by)) || pipeline.fee_reader_recipes.history) - 5,
           version = pipeline.fee_reader_recipes.version + 1, notes = excluded.notes, updated_at = now(), updated_by = 'fee_ai'
     where pipeline.fee_reader_recipes.notes is distinct from excluded.notes and pipeline.fee_reader_recipes.updated_by = 'fee_ai';
  end if;

  -- 6 further fee pages the AI saw linked from this one, on the provider's own site
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status, linked_from)
  select q.provider_id, 'fee_schedule', u, 'linked from a fee page (AI fee reader)', 6, 'search', 'found', q.fact_source_id
    from (select distinct left(jsonb_array_elements_text(coalesce(p_result->'more_fee_pages', '[]'::jsonb)), 500) u) m
   where u ~ '^https?://' and lower(substring(u from '^https?://([^/]+)')) like '%' || lower(regexp_replace(substring(coalesce(f.url, '') from '^https?://([^/]+)'), '^www\.', ''))
     and (select count(*) from pipeline.provider_fact_sources s where s.provider_id = q.provider_id and s.kind = 'fee_schedule') < v_max
  on conflict (provider_id, kind, url) do nothing;

  update pipeline.fee_reader_queue set state = 'done', finished_at = now(), rows_found = v_rows, cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0),
         model = left(p_result->>'model', 120), leased_until = null, error = null where id = q.id;
  if (v_out->>'admitted') is not null then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'provider_current_tuition', v_src, 'approved', 'CF-CHG-20260915-247, Platform Admin 21 Oct 2026 20:02 (AI fee reader, "Automatic above confidence")', now(), now(), now()
     where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = v_src);
    insert into search.refresh_requests(requested_by) values ('fee reader ' || left(q.id::text, 8));
  end if;
  return jsonb_build_object('rows', v_rows) || v_out;
end $function$;
revoke execute on function public.svc_fee_ai_record(uuid, jsonb, numeric, text) from public, anon, authenticated;
grant execute on function public.svc_fee_ai_record(uuid, jsonb, numeric, text) to service_role;

-- Screen: Layer 2/3 › Enrich fields › Fee reader ------------------------------------------------------------------------------------
create or replace function public.admin_fee_reader(p_action text, p_args jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', '')); v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'overview' then
    return jsonb_build_object(
      'scope', jsonb_build_object('countries', (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.countries'),
                                  'types', (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.provider_types'),
                                  'auto_confidence', security.pipeline_num_v1('fees.auto_admit_confidence', 0.85)),
      'profiles', (select coalesce(jsonb_agg(to_jsonb(cp) order by cp.country_code), '[]'::jsonb) from pipeline.fee_country_profiles cp),
      'spend_today', (select x.spent from security.ai_spend_today_v1() x where x.use = 'fee_ai'),
      'providers', (select coalesce(jsonb_agg(z order by z.name), '[]'::jsonb) from (
         select p.id provider_id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 country,
                (select count(*) from pipeline.provider_fact_sources f where f.provider_id = p.id and f.kind = 'fee_schedule') pages,
                (select count(*) from pipeline.provider_fact_sources f where f.provider_id = p.id and f.kind = 'fee_schedule' and f.content_hash is not null) pages_read,
                (select max(q.finished_at) from pipeline.fee_reader_queue q where q.provider_id = p.id) last_read,
                (select jsonb_object_agg(o, n) from (select r.outcome o, count(*) n from pipeline.fee_reader_rows r
                   where r.provider_id = p.id and r.queue_id in (select distinct on (q.fact_source_id) q.id from pipeline.fee_reader_queue q where q.provider_id = p.id and q.state = 'done' order by q.fact_source_id, q.finished_at desc)
                   group by 1) o) outcomes,
                (select count(*) from pipeline.fee_reader_findings x where x.provider_id = p.id and x.resolved_at is null) open_findings,
                (select count(distinct cf.course_id) from catalogue.course_fees cf join catalogue.courses c on c.id = cf.course_id
                  where c.provider_id = p.id and cf.fee_type = 'provider_current_tuition' and cf.status = 'active') courses_with_fee,
                (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') courses
           from catalogue.providers p join ref.countries k on k.id = p.country_id
          where security.fee_reader_in_scope_v1(p.id) or exists (select 1 from pipeline.fee_reader_queue q where q.provider_id = p.id)) z));
  elsif p_action = 'provider' then
    return jsonb_build_object(
      'pages', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'url', f.url, 'status', f.status, 'found_via', f.found_via, 'read_at', f.read_at,
                  'last', (select jsonb_build_object('state', q.state, 'rows', q.rows_found, 'cost', q.cost_usd, 'at', coalesce(q.finished_at, q.created_at), 'error', q.error)
                             from pipeline.fee_reader_queue q where q.fact_source_id = f.id order by q.created_at desc limit 1)) order by f.rank desc, f.url), '[]'::jsonb)
                  from pipeline.provider_fact_sources f where f.provider_id = v_pid and f.kind = 'fee_schedule'),
      'rows', (select coalesce(jsonb_agg(to_jsonb(r) - 'provider_id' - 'queue_id' || jsonb_build_object('course', (select c.canonical_title from catalogue.courses c where c.id = r.course_id))
                                         order by r.outcome, r.qualification), '[]'::jsonb)
                 from (select * from pipeline.fee_reader_rows r where r.provider_id = v_pid
                         and r.queue_id in (select distinct on (q.fact_source_id) q.id from pipeline.fee_reader_queue q where q.provider_id = v_pid and q.state = 'done' order by q.fact_source_id, q.finished_at desc)
                       limit 500) r),
      'findings', (select coalesce(jsonb_agg(to_jsonb(x) order by x.resolved_at nulls first, x.last_seen desc), '[]'::jsonb) from (select * from pipeline.fee_reader_findings x where x.provider_id = v_pid order by x.last_seen desc limit 100) x),
      'notes', (select to_jsonb(r) from pipeline.fee_reader_recipes r where r.provider_id = v_pid),
      'can_run', v_rank >= 4, 'can_manage', v_rank >= 6);
  elsif p_action = 'read_again' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    update pipeline.fee_reader_queue set state = 'queued', attempts = 0, leased_until = null, error = null
     where id in (select distinct on (q.fact_source_id) q.id from pipeline.fee_reader_queue q where q.provider_id = v_pid order by q.fact_source_id, q.created_at desc);
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('fees', 'read_again', v_pid::text, jsonb_build_object('pages', v_n, 'reason', v_reason), auth.uid());
    return jsonb_build_object('queued', v_n);
  elsif p_action = 'notes_set' then
    if v_rank < 5 then raise exception 'PIM Admin role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    insert into pipeline.fee_reader_recipes(provider_id, notes, updated_by) values (v_pid, left(btrim(p_args->>'notes'), 1500), 'person')
    on conflict (provider_id) do update set history = (jsonb_build_array(jsonb_build_object('version', pipeline.fee_reader_recipes.version, 'notes', pipeline.fee_reader_recipes.notes,
                                                         'at', pipeline.fee_reader_recipes.updated_at, 'by', pipeline.fee_reader_recipes.updated_by)) || pipeline.fee_reader_recipes.history) - 5,
           version = pipeline.fee_reader_recipes.version + 1, notes = excluded.notes, updated_at = now(), updated_by = 'person';
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('fees', 'notes_set', v_pid::text, jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  elsif p_action = 'profile_set' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    insert into pipeline.fee_country_profiles(country_code, currency_code, usual_unit, full_time_units_a_year, unit_name, terms_a_year, notes, reason, updated_by)
    values (upper(p_args->>'country'), upper(p_args->>'currency'), p_args->>'usual_unit', nullif(p_args->>'full_time_units_a_year', '')::numeric, p_args->>'unit_name',
            nullif(p_args->>'terms_a_year', '')::numeric, p_args->>'notes', v_reason, auth.uid())
    on conflict (country_code) do update set currency_code = excluded.currency_code, usual_unit = excluded.usual_unit, full_time_units_a_year = excluded.full_time_units_a_year,
           unit_name = excluded.unit_name, terms_a_year = excluded.terms_a_year, notes = excluded.notes, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now();
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('fees', 'profile_set', upper(p_args->>'country'), p_args, auth.uid());
    return public.admin_fee_reader('overview', '{}'::jsonb);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;
revoke execute on function public.admin_fee_reader(text, jsonb) from public, anon;
grant execute on function public.admin_fee_reader(text, jsonb) to authenticated;

-- Spend and wake --------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.ai_spend_today_v1()', '12943a97ec013cc0f38ec655cfba832d', array[
  [$o$    union all select 'enrich_fields', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.field_enrich_items x, d where x.updated_at >= d.t and coalesce(x.cost_usd, 0) > 0)$o$,
   $n$    union all select 'enrich_fields', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.field_enrich_items x, d where x.updated_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'fee_ai', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.fee_reader_queue x, d where coalesce(x.finished_at, x.created_at) >= d.t and coalesce(x.cost_usd, 0) > 0)$n$],
  [$o$('course_match', 'AI course-page matching', 4), ('enrich_fields', 'Enrich fields with AI', 5))$o$,
   $n$('course_match', 'AI course-page matching', 4), ('enrich_fields', 'Enrich fields with AI', 5), ('fee_ai', 'Fee reader with AI', 6))$n$]]);

select pg_temp.edit_once('security.worker_mode_waiting_v1(text)', '57699fcfcde9eee300aef28a8a34cfef', array[
  [$o$    else false end$o$,
   $n$    -- 21 Oct 2026 (fee reader): pages waiting to be read wake the provider-facts job
    when 'provider_facts' then exists (select 1 from pipeline.provider_fact_sources f where f.status = 'found' and coalesce(f.attempts, 0) < 3)
    else false end$n$]]);

-- Job, catalogue, register -----------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('fee-reader', 'Course pages', 33, 'Fee reader (AI)', 'Every 10 minutes: adds suggested fee pages for providers in scope (Settings › Pipeline settings › Enrichment, Fee reader), queues every stored fee page version not read yet, learns from rows a person rejected, and asks the worker to read fee pages with AI. Rows are admitted automatically above the confidence setting, otherwise sent to Layer 4. Layer 2/3 › Enrich fields › Fee reader.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('fee-reader', '7-59/10 * * * *', $$select security.fee_reader_tick_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.fee_country_profiles', 'Layer 2', 'How each country publishes tuition (fee reader)', 'active', '20261022001000'),
 ('table', 'pipeline.fee_reader_queue', 'Layer 2', 'AI fee reads per page version', 'active', '20261022001000'),
 ('table', 'pipeline.fee_reader_rows', 'Layer 2', 'Fee rows read by AI and their outcome', 'active', '20261022001000'),
 ('table', 'pipeline.fee_reader_findings', 'Layer 2', 'What the fee reader got wrong, fed back to the AI', 'active', '20261022001000'),
 ('table', 'pipeline.fee_reader_recipes', 'Layer 2', 'How a provider''s fee pages are laid out (versioned)', 'active', '20261022001000'),
 ('function', 'security.fee_reader_tick_v1', 'Layer 2', 'Fee reader: pages, queue, learning, worker', 'active', '20261022001000'),
 ('function', 'public.svc_fee_ai_next', 'Layer 2', 'Fee reader: work for the worker', 'active', '20261022001000'),
 ('function', 'public.svc_fee_ai_record', 'Layer 2', 'Fee reader: rows, admission, review, findings', 'active', '20261022001000'),
 ('function', 'public.admin_fee_reader', 'Layer 2', 'Layer 2/3 › Enrich fields › Fee reader', 'active', '20261022001000'),
 ('function', 'security.fee_title_similarity_v1', 'Layer 2', 'Fee row and course title agreement', 'active', '20261022001000'),
 ('function', 'security.fee_reader_in_scope_v1', 'Layer 2', 'Fee reader rollout scope from settings', 'active', '20261022001000'),
 ('job', 'fee-reader', 'Layer 2', 'Fee reader (AI)', 'active', '20261022001000')
on conflict (kind, name) do nothing;
