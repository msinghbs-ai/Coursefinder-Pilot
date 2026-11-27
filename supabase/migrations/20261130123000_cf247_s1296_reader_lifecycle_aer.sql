-- CF-247 s1296 (S2-Build; SS-Programme-Control 27 Nov 2026 11:27 AEDT, "Complete Autonomous PIM: Institute Reader Creation, Qualification and Execution";
-- PIM acceptance gap coursefinder-admin #1207 comment 7206040106; Master Plan §6.3 steps 4a and 6, §6.8; F-OPS.14, F-OPS.16, F-OPS.19).
-- Academic entry first; scholarships follow on the same lifecycle (s1297).
--
-- Read live 27 Nov 2026 (rolled back, read only): 452 entry-matrix sources at 259 providers. Of each source's latest read, 313 are done (19 by a
-- deterministic reader), 36 failed for time or no reply, and 50 are held_unparsed (terminal: never read again) at 15 providers:
--   * RMIT, 36 HTML country pages (…/entry-requirements/country-equivalency/<country>): the site now prints the generic heading "Country or region
--     equivalency" on every country page, so the completeness guard holds every page as "not a country table" before any reader. In October the
--     same pages named the country in their heading and were read (29 runs admitted rows).
--   * 14 PDFs at 14 providers that no proven-structure reader proves (cells across column edges, a first row that is not a header, no ruled table).
-- Nothing detected such a template change, proposed a configuration for it, qualified it or resumed processing: a held page stayed held.
--
-- What it adds (the smallest extension, on what exists):
--   1. Reader configurations are versioned Layer 2 source profiles (pipeline.layer2_source_profiles and _versions, which already hold versioned
--      configuration, validation status and result): one profile per provider, domain and template (profile_key reader:academic_entry:<provider>:
--      <template>:<scope>), created disabled and paused. Configuration is data from a closed list: country_from ('url_slug') and overrides of
--      registered reader settings (reading.entry_*); no code, SQL, selector script or prompt. Active = enabled, not paused, current version valid.
--   2. security.reader_lifecycle_tick_v1 (run from the existing entry-matrix read, no new job): detects held pages by template class; reuses an
--      active configuration that covers the page; otherwise copies a configuration qualified at another provider for the same class, or proposes
--      the class's configuration; a class with no configuration in the existing readers' capability (the PDF layouts) is held with its exact reason.
--   3. Qualification on stored evidence only: the worker reads each sample's stored copy through the same entry-matrix reader with the candidate
--      configuration, deterministic readers only (no model, no fetch, no write, $0; svc_reader_qualify_next / svc_reader_qualify_record). Positive
--      samples are pages whose address names a country; negative samples are pages of the same template that name none and must stay held.
--   4. Activation is its own step: a pass switches nothing on (CLAUDE.md). security.reader_activate_v1 switches a qualified version on only under
--      the standing authority its knowledge pattern records (the Standing Authority Charter 23 Nov 2026 item 1 pre-authorises AER v2 proven-structure
--      readers), else HELD:ACTIVATION_AUTHORITY; it then reads the held pages again through the existing re-read (admin_entry_matrix_reread), then
--      the existing entry-matrix route, completeness guard, matrix machine rule (aer-matrix-machine-v1) and Layer 4 decide. A pass with no
--      deterministic proof activates only while the entry_matrices route has a usable model (existing caps); otherwise it is held.
--   5. svc_entry_matrix_next hands the active configuration with each leased read (one key added, md5 guarded).
--   6. Knowledge (s1292, no new store): patterns reader_config:aer_matrix:<class> in pipeline.ops_remedy_knowledge; every qualification, held
--      class and post-activation result is an outcome (security.ops_learning_record_v1) with its evidence signature; the same template class on the
--      same stored copies is never proposed again after a failure (security.ops_learning_retry_check_v1), and a configuration whose re-reads yield
--      nothing is paused and blocked (pipeline.ops_remedy_blocks).
-- G1: no job (the existing coverage-sweep entry_ai call runs the tick and the qualification). G2: four settings. G3: 75/48 checked. Locks and cron
-- checked. No spend. Nothing dropped or deleted.
-- Replaces: public.svc_entry_matrix_next (md5 42c269c8; one key added).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

create temp table s1296_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from catalogue.provider_entry_matrix where status = 'active') as aer_active_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure)) <> '42c269c847c07aec5505abdcfe931d83' then
    raise exception 'pre-check: svc_entry_matrix_next is not the definition this change was written against';
  end if;
  if to_regprocedure('security.ops_learning_record_v1(jsonb)') is null or to_regprocedure('security.ops_learning_retry_check_v1(text,text,text)') is null
     or to_regprocedure('public.admin_entry_matrix_reread(uuid[],text)') is null then
    raise exception 'pre-check: the recovery knowledge or the entry-matrix re-read is missing';
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'reader.lifecycle_on', 'Reader lifecycle: detect, propose, qualify and activate reader configurations',
   'When on, the entry-matrix read detects held pages by template, reuses or proposes a provider reader configuration, qualifies it on stored copies (no model, no fetch, no spend) and switches a passing configuration on within the Standing Authority Charter. Off stops new proposals and qualifications; active configurations keep working.',
   'switch', to_jsonb(1), 0, 1, 'switch', 1561, 'Entry requirements', 'security.reader_lifecycle_tick_v1; public.svc_reader_qualify_next', 'CF-247 s1296 (SS-Programme-Control 27 Nov 2026 11:27)'),
  ('pipeline', 'reader.qualify_min_positive', 'Reader lifecycle: pages a configuration must read before it is switched on',
   'The least number of positive sample pages (stored copies of the provider''s own template) a proposed reader configuration must pass. Every negative sample must still be held.',
   'number', to_jsonb(2), 1, 20, 'pages', 1562, 'Entry requirements', 'security.reader_qualify_decide_v1', 'CF-247 s1296'),
  ('pipeline', 'reader.qualify_samples_max', 'Reader lifecycle: sample pages per qualification',
   'At most this many stored pages are read to qualify one proposed configuration (at most two of them negative).',
   'number', to_jsonb(8), 2, 40, 'pages', 1563, 'Entry requirements', 'security.reader_propose_v1', 'CF-247 s1296'),
  ('pipeline', 'reader.proposals_per_tick', 'Reader lifecycle: proposals per run',
   'At most this many provider templates get a new reader configuration proposal in one run of the lifecycle step.',
   'number', to_jsonb(2), 1, 20, 'proposals', 1564, 'Entry requirements', 'security.reader_lifecycle_tick_v1', 'CF-247 s1296')
on conflict do nothing;

-- knowledge patterns (s1292 store): what the platform learns about entry-matrix templates
insert into pipeline.ops_remedy_knowledge (code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
  no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
values
  ('reader_config:aer_matrix:country_page_generic_heading', 'aer', 'Entry-matrix country pages whose heading names no country: the country is taken from the page address',
   array['reader:academic_entry:%:country_page_generic_heading:%'], 'country_page_generic_heading', null,
   '{"signal": "held_unparsed: not a country table: no country named in the page heading", "configuration": {"country_from": "url_slug", "settings": {"reading.entry_html_table_min_rows": 1}}}'::jsonb,
   'auto', 'platform', 'the pages whose address names one country pass the completeness guard and are read by the proven HTML table reader (or the routed model); pages naming no country stay held',
   'the same template class on the same stored copies already failed qualification or yielded nothing after activation: wait for a changed copy',
   'a provider''s country pages under one address folder with a generic heading; qualified on that provider''s stored copies with negative samples',
   true, 'Standing Authority Charter 23 Nov 2026 item 1: AER v2 proven-structure readers are pre-authorised', now(), 'S2-Build s1296', 'CF-247 s1296'),
  ('reader_config:aer_matrix:pdf_layout_unproven', 'aer', 'Entry-matrix PDFs no proven-structure reader proves (cells across column edges, no header row, no ruled table)',
   array['reader:academic_entry:%:pdf_layout_unproven:%'], 'pdf_layout_unproven', null,
   '{"signal": "held_unparsed: PDF …; grid no aligned grid"}'::jsonb,
   'release', 'claude_engineering', 'a new or extended AER v2 PDF reader (governed release) proves the layout; no configuration of the existing readers can',
   'held with the reader''s exact reason; not proposed again until the stored copy changes or a reader release changes the class',
   'never automatic: a reader change is engineering (AER v2) or the routed model under its own qualification',
   false, 'no configuration of the existing deterministic readers proves these layouts', now(), 'S2-Build s1296', 'CF-247 s1296')
on conflict (code) do nothing;

-- 1. the country an address names (last path segment, against the country reference), or null
create or replace function security.reader_country_from_slug_v1(p_url text)
returns text language sql stable security definer set search_path = '' as $function$
  with s as (select btrim(regexp_replace(lower(regexp_replace(regexp_replace(coalesce(p_url, ''), '[?#].*$', ''), '^.*/([^/]+)/?$', '\1')), '[^a-z]+', ' ', 'g')) slug),
  k as (select k.name, btrim(regexp_replace(lower(k.name), '[^a-z]+', ' ', 'g')) n, btrim(regexp_replace(lower(coalesce(k.official_name, '')), '[^a-z]+', ' ', 'g')) o from ref.countries k)
  select k.name from s, k
   where s.slug <> '' and k.n <> '' and (s.slug = k.n or (k.o <> '' and s.slug = k.o) or s.slug like k.n || ' %')
   order by (s.slug = k.n or s.slug = k.o) desc, length(k.n) desc limit 1
$function$;
comment on function security.reader_country_from_slug_v1(text) is 'CF-247 s1296: the country a page address names in its last path segment (exact name, official name, or the name followed by more words), from ref.countries; null when it names none.';
revoke all on function security.reader_country_from_slug_v1(text) from public, anon, authenticated;

-- 2. the template class of a held entry-matrix read
create or replace function security.reader_aer_template_v1(p_error text)
returns text language sql immutable set search_path = '' as $function$
  select case when p_error like 'held_unparsed: not a country table: no country named in the page heading%' then 'country_page_generic_heading'
              when p_error like 'held_unparsed: PDF %' or p_error like 'held_unparsed: no deterministic reader proved%' then 'pdf_layout_unproven' end
$function$;
comment on function security.reader_aer_template_v1(text) is 'CF-247 s1296: the reader template class of a held entry-matrix read (null when the hold is not a reader template matter).';

-- 3. the active configuration for one page (handed out with each leased read)
create or replace function security.reader_config_for_v1(p_domain text, p_provider uuid, p_url text)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select v.configuration || jsonb_build_object('profile_version_id', v.id,
           'country_hint', case when v.configuration->>'country_from' = 'url_slug' then security.reader_country_from_slug_v1(p_url) end)
    from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id = p.current_version_id
   where p.profile_key like 'reader:' || p_domain || ':' || p_provider::text || ':%' and p.enabled and not p.paused and v.validation_status = 'valid'
     and p_url like v.configuration->>'url_like'
   order by length(v.configuration->>'url_like') desc, v.created_at desc limit 1
$function$;
comment on function security.reader_config_for_v1(text, uuid, text) is 'CF-247 s1296: the active reader configuration (enabled, not paused, valid current version) that covers this page of this provider, with the country its address names; null when none.';
revoke all on function security.reader_config_for_v1(text, uuid, text) from public, anon, authenticated;

-- 4. propose (or reuse) a configuration for one provider template, with its samples
create or replace function security.reader_propose_v1(p_provider uuid, p_template text, p_url_like text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_code text := 'reader_config:aer_matrix:' || p_template; v_key text := 'reader:academic_entry:' || p_provider::text || ':' || p_template || ':' || left(md5(p_url_like), 8);
        v_src uuid; v_prof uuid; v_ver uuid; v_cfg jsonb; v_from uuid; v_samples jsonb; v_sig text; v_chk jsonb; v_next int;
        v_max int := greatest(security.pipeline_num_v1('reader.qualify_samples_max', 8)::int, 2);
begin
  -- the held pages of this template, newest stored copy of each source
  with h as (select distinct on (s.id) s.id, s.url, s.content_hash, r.error from pipeline.entry_matrix_sources s
               join pipeline.entry_matrix_runs r on r.source_id = s.id and r.content_hash is not distinct from coalesce(s.content_hash, s.evidence_id::text)
              where s.provider_id = p_provider and s.status = 'read' and s.evidence_id is not null and s.url like p_url_like
              order by s.id, r.created_at desc),
  c as (select h.*, security.reader_country_from_slug_v1(h.url) country from h where security.reader_aer_template_v1(h.error) = p_template)
  select md5(string_agg(c.id::text || ':' || coalesce(c.content_hash, ''), ',' order by c.id)),
         (select jsonb_agg(x) from (select jsonb_build_object('source_id', c2.id, 'content_hash', c2.content_hash, 'role', case when c2.country is null then 'negative' else 'positive' end, 'country', c2.country) x
                                      from (select * from c where country is not null order by url limit v_max - 2) c2
                                    union all
                                    select jsonb_build_object('source_id', c3.id, 'content_hash', c3.content_hash, 'role', 'negative', 'country', null)
                                      from (select * from c where country is null order by url limit 2) c3) q)
    into v_sig, v_samples from c;
  if v_samples is null then return jsonb_build_object('proposed', false, 'why', 'no held page of this template'); end if;
  -- prevention: the same template on the same stored copies already failed
  v_chk := security.ops_learning_retry_check_v1(v_code, 'provider:' || p_provider::text, v_sig);
  if not coalesce((v_chk->>'allowed')::boolean, true) then return jsonb_build_object('proposed', false, 'why', v_chk->>'reason', 'prevented', true); end if;
  if p_template = 'pdf_layout_unproven' then
    -- no configuration of the existing readers proves these layouts: an exact hold, recorded once per stored copy set
    perform security.ops_learning_record_v1(jsonb_build_object('code', v_code, 'entity', 'provider:' || p_provider::text, 'evidence_signature', v_sig, 'performed_by', 'platform',
      'success', false, 'stage_advanced', false, 'expected', 'a governed AER v2 reader release', 'observed', jsonb_build_object('held_pages', jsonb_array_length(v_samples), 'disposition', 'HELD:READER_RELEASE_REQUIRED'),
      'evidence', jsonb_build_object('source', 'security.reader_propose_v1', 'samples', v_samples)));
    return jsonb_build_object('proposed', false, 'why', 'HELD:READER_RELEASE_REQUIRED', 'held_pages', jsonb_array_length(v_samples));
  end if;
  if not exists (select 1 from jsonb_array_elements(v_samples) e where e->>'role' = 'positive') then
    return jsonb_build_object('proposed', false, 'why', 'no held page of this template names a country in its address');
  end if;
  -- reuse: a configuration of the same class qualified at another provider, else the class's own
  select v.id, v.configuration into v_from, v_cfg from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id = p.current_version_id
   where p.profile_key like 'reader:academic_entry:%:' || p_template || ':%' and v.validation_status = 'valid' and p.enabled and not p.paused
   order by v.created_at desc limit 1;
  v_cfg := jsonb_build_object('reader_config', 'reader-config-v1', 'domain', 'academic_entry', 'template', p_template, 'provider_id', p_provider, 'url_like', p_url_like,
             'country_from', coalesce(v_cfg->>'country_from', (select k.trigger_conditions#>>'{configuration,country_from}' from pipeline.ops_remedy_knowledge k where k.code = v_code)),
             'settings', coalesce(v_cfg->'settings', (select k.trigger_conditions#>'{configuration,settings}' from pipeline.ops_remedy_knowledge k where k.code = v_code), '{}'::jsonb),
             'reused_from', v_from, 'samples', v_samples, 'evidence_signature', v_sig, 'proposed_at', now(), 'proposed_by', 'security.reader_propose_v1');
  -- the store: the provider's source record, a profile per template, a version per proposal
  select s.id into v_src from pipeline.sources s where s.provider_id = p_provider order by (s.status = 'active') desc, s.trust_rank desc nulls last, s.created_at limit 1;
  if v_src is null then return jsonb_build_object('proposed', false, 'why', 'the provider has no source record to hold a profile'); end if;
  insert into pipeline.layer2_source_profiles (source_id, profile_key, domain, acquisition_method, target_entity_type, authority_class, enabled, paused, operational_owner)
  values (v_src, v_key, 'academic_entry', 'other_deterministic', 'entry_matrix', 'first_party', false, true, 'S2-Build reader lifecycle (s1296)')
  on conflict (profile_key) do update set updated_at = now() returning id into v_prof;
  if exists (select 1 from pipeline.layer2_source_profile_versions v where v.profile_id = v_prof and v.validation_status = 'pending') then
    return jsonb_build_object('proposed', false, 'why', 'a proposal of this template is already being qualified');
  end if;
  if exists (select 1 from pipeline.layer2_source_profile_versions v where v.profile_id = v_prof and v.validation_status = 'valid'
              and v.configuration->>'evidence_signature' = v_sig and not (v.validation_result ? 'activated_at')) then
    return jsonb_build_object('proposed', false, 'why', 'qualified on these stored copies; waiting for its activation step');
  end if;
  select coalesce(max(version_no), 0) + 1 into v_next from pipeline.layer2_source_profile_versions where profile_id = v_prof;
  insert into pipeline.layer2_source_profile_versions (profile_id, version_no, configuration, configuration_hash, validation_status, validation_result, change_control_ref)
  values (v_prof, v_next, v_cfg, md5(v_cfg::text), 'pending',
          jsonb_build_object('samples', (select jsonb_object_agg(e->>'source_id', jsonb_build_object('state', 'queued', 'role', e->>'role', 'country', e->>'country', 'content_hash', e->>'content_hash')) from jsonb_array_elements(v_samples) e)),
          'CF-247 s1296')
  returning id into v_ver;
  -- the profile points at its newest version; it stays switched off until the version passes
  update pipeline.layer2_source_profiles set current_version_id = case when enabled then current_version_id else v_ver end, updated_at = now() where id = v_prof;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reader_lifecycle', 'proposed', 'pipeline.layer2_source_profile_versions',
          jsonb_build_object('version', v_ver, 'profile_key', v_key, 'template', p_template, 'reused_from', v_from, 'samples', jsonb_array_length(v_samples)), null);
  return jsonb_build_object('proposed', true, 'version', v_ver, 'reused_from', v_from, 'samples', jsonb_array_length(v_samples));
end $function$;
comment on function security.reader_propose_v1(uuid, text, text) is 'CF-247 s1296: one provider template''s reader configuration proposal (reusing a configuration of the same class qualified elsewhere), with positive and negative samples; a class no configuration can prove is held with its reason; never proposed again on the same stored copies after a failure.';
revoke all on function security.reader_propose_v1(uuid, text, text) from public, anon, authenticated;

-- 5. a re-read through the existing function, from the service path (its API check refuses a JWT without a Platform Admin; this path is the platform itself)
create or replace function security.reader_reread_v1(p_source_ids uuid[], p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_claims text := current_setting('request.jwt.claims', true); v_role text := current_setting('request.jwt.claim.role', true); v jsonb;
begin
  if coalesce(array_length(p_source_ids, 1), 0) = 0 then return jsonb_build_object('runs', 0); end if;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.role', '', true);
  v := public.admin_entry_matrix_reread(p_source_ids, p_reason);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true), set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $function$;
comment on function security.reader_reread_v1(uuid[], text) is 'CF-247 s1296: the reader lifecycle''s re-read of held pages through public.admin_entry_matrix_reread (history kept, only proposed rows and pending items superseded), called by the platform itself.';
revoke all on function security.reader_reread_v1(uuid[], text) from public, anon, authenticated;

-- 6. decide a version once every sample is read
create or replace function security.reader_qualify_decide_v1(p_version uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v pipeline.layer2_source_profile_versions%rowtype; s jsonb := '{}'; v_min int := greatest(security.pipeline_num_v1('reader.qualify_min_positive', 2)::int, 1);
        v_det int; v_guard int; v_neg_bad int; v_pos int; v_neg int; v_route jsonb := security.ai_route_v1('entry_matrices'); v_model boolean; v_pass boolean; v_mode text;
        v_code text;
begin
  select * into v from pipeline.layer2_source_profile_versions where id = p_version for update;
  if v.id is null or v.validation_status <> 'pending' then return jsonb_build_object('decided', false, 'why', 'not pending'); end if;
  s := v.validation_result->'samples';
  if exists (select 1 from jsonb_each(s) e where e.value->>'state' <> 'done') then return jsonb_build_object('decided', false, 'why', 'samples still being read'); end if;
  select count(*) filter (where e.value->>'role' = 'positive'), count(*) filter (where e.value->>'role' = 'negative'),
         count(*) filter (where e.value->>'role' = 'positive' and e.value->>'outcome' = 'deterministic_read'),
         count(*) filter (where e.value->>'role' = 'positive' and e.value->>'outcome' in ('deterministic_read', 'guard_passed')),
         count(*) filter (where e.value->>'role' = 'negative' and e.value->>'outcome' <> 'guard_held')
    into v_pos, v_neg, v_det, v_guard, v_neg_bad from jsonb_each(s) e;
  v_model := v_route->>'model' is not null and not coalesce((v_route->>'held')::boolean, true);
  v_mode := case when v_det >= v_min then 'deterministic' when v_guard >= v_min and v_model then 'guard_then_routed_model' end;
  v_pass := v_mode is not null and v_neg_bad = 0;
  v_code := 'reader_config:aer_matrix:' || (v.configuration->>'template');
  update pipeline.layer2_source_profile_versions
     set validation_status = case when v_pass then 'valid' else 'invalid' end,
         validation_result = v.validation_result || jsonb_build_object('decided_at', now(), 'passed', v_pass, 'mode', v_mode, 'positive', v_pos, 'negative', v_neg,
           'deterministic', v_det, 'guard_passed', v_guard, 'negative_not_held', v_neg_bad, 'min_positive', v_min, 'routed_model', v_model,
           'rule', 'pass when deterministic reads >= min_positive, or guard passes >= min_positive while the entry_matrices route has a usable model; every negative sample still held')
   where id = v.id;
  perform security.ops_learning_record_v1(jsonb_build_object('code', v_code, 'entity', 'provider:' || (v.configuration->>'provider_id'), 'evidence_signature', v.configuration->>'evidence_signature',
    'performed_by', 'platform', 'success', v_pass, 'stage_advanced', v_pass, 'expected', 'qualified on stored copies',
    'observed', jsonb_build_object('mode', v_mode, 'positive', v_pos, 'deterministic', v_det, 'guard_passed', v_guard, 'negative', v_neg, 'negative_not_held', v_neg_bad),
    'evidence', jsonb_build_object('source', 'security.reader_qualify_decide_v1', 'version', v.id, 'reused_from', v.configuration->'reused_from')));
  if not v_pass then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', 'qualification_failed', 'pipeline.layer2_source_profile_versions', jsonb_build_object('version', v.id, 'mode', v_mode, 'deterministic', v_det, 'guard_passed', v_guard, 'negative_not_held', v_neg_bad), null);
    return jsonb_build_object('decided', true, 'passed', false, 'deterministic', v_det, 'guard_passed', v_guard, 'negative_not_held', v_neg_bad);
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reader_lifecycle', 'qualified', 'pipeline.layer2_source_profile_versions', jsonb_build_object('version', v.id, 'mode', v_mode, 'deterministic', v_det, 'guard_passed', v_guard), null);
  -- a pass switches nothing on: activation is its own step (security.reader_activate_v1), taken only under a recorded standing authority
  return jsonb_build_object('decided', true, 'passed', true, 'mode', v_mode, 'activation', 'separate step');
end $function$;
comment on function security.reader_qualify_decide_v1(uuid) is 'CF-247 s1296: decides a proposed reader configuration from its sample reads (valid or invalid); a pass switches nothing on; every decision is a recorded outcome.';
revoke all on function security.reader_qualify_decide_v1(uuid) from public, anon, authenticated;

-- 6b. activation: a separate, audited step, taken only under the standing authority the pattern records
create or replace function security.reader_activate_v1(p_version uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v pipeline.layer2_source_profile_versions%rowtype; k pipeline.ops_remedy_knowledge%rowtype; v_ids uuid[]; v_rr jsonb; v_route jsonb := security.ai_route_v1('entry_matrices');
begin
  select * into v from pipeline.layer2_source_profile_versions where id = p_version for update;
  if v.id is null or v.validation_status <> 'valid' or v.validation_result ? 'activated_at' then return jsonb_build_object('activated', false, 'why', 'not a qualified version awaiting activation'); end if;
  select * into k from pipeline.ops_remedy_knowledge where code = 'reader_config:aer_matrix:' || (v.configuration->>'template');
  -- authority: only a pattern held as automatic under a recorded standing decision (Standing Authority Charter 23 Nov 2026 item 1); anything else is a protected hold
  if k.code is null or k.authority <> 'auto' or not k.auto_eligible then
    update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('held', 'HELD:ACTIVATION_AUTHORITY', 'held_at', now()) where id = v.id;
    return jsonb_build_object('activated', false, 'why', 'HELD:ACTIVATION_AUTHORITY');
  end if;
  -- a qualification that relied on the routed model activates only while that route still has a usable model
  if v.validation_result->>'mode' = 'guard_then_routed_model' and (v_route->>'model' is null or coalesce((v_route->>'held')::boolean, true)) then
    return jsonb_build_object('activated', false, 'why', 'HELD:ROUTE_UNAVAILABLE');
  end if;
  update pipeline.layer2_source_profile_versions set validation_status = 'superseded' where profile_id = v.profile_id and id <> v.id and validation_status = 'valid';
  update pipeline.layer2_source_profiles set current_version_id = v.id, enabled = true, paused = false, updated_at = now() where id = v.profile_id;
  update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('activated_at', now(), 'authority', k.eligibility_reason) where id = v.id;
  -- the held pages of the template are read again through the existing pipeline (route, completeness guard, matrix machine rule and Layer 4 decide)
  select array_agg(s0.id) into v_ids from pipeline.entry_matrix_sources s0
    join lateral (select r.error from pipeline.entry_matrix_runs r where r.source_id = s0.id order by r.created_at desc limit 1) r on true
   where s0.provider_id = (v.configuration->>'provider_id')::uuid and s0.url like v.configuration->>'url_like' and s0.status = 'read'
     and security.reader_aer_template_v1(r.error) = v.configuration->>'template';
  v_rr := security.reader_reread_v1(v_ids, 'CF-247 s1296 reader lifecycle: configuration ' || v.id || ' activated; held pages of its template read again');
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reader_lifecycle', 'activated', 'pipeline.layer2_source_profiles', jsonb_build_object('profile', v.profile_id, 'version', v.id, 'mode', v.validation_result->>'mode',
          'reread_runs', v_rr->'runs', 'authority', k.eligibility_reason), null);
  return jsonb_build_object('activated', true, 'reread_runs', v_rr->'runs');
end $function$;
comment on function security.reader_activate_v1(uuid) is 'CF-247 s1296: switches a qualified reader configuration on as its own audited step, only under the standing authority its knowledge pattern records (otherwise HELD:ACTIVATION_AUTHORITY), and reads the held pages of its template again.';
revoke all on function security.reader_activate_v1(uuid) from public, anon, authenticated;

-- 7. the lifecycle step: reuse, detection and proposals, and the results of active configurations
create or replace function security.reader_lifecycle_tick_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_max int := greatest(security.pipeline_num_v1('reader.proposals_per_tick', 2)::int, 1); r record; v_p jsonb; v_out jsonb := '[]'; v_n int := 0;
        v_reuse uuid[]; v_rr jsonb; v_res int := 0; v_act jsonb := '[]';
begin
  if security.pipeline_num_v1('reader.lifecycle_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- (a) reuse: a held page an active configuration covers, held before that configuration existed, is read again with it
  select array_agg(x.id) into v_reuse from (
    select s.id from pipeline.entry_matrix_sources s
      join lateral (select r.error, r.result, r.updated_at from pipeline.entry_matrix_runs r where r.source_id = s.id order by r.created_at desc limit 1) lr on true
      join lateral (select security.reader_config_for_v1('academic_entry', s.provider_id, s.url) cfg) c on true
     where s.status = 'read' and c.cfg is not null and lr.error like 'held_unparsed%'
       and security.reader_aer_template_v1(lr.error) = c.cfg->>'template' and coalesce(lr.result#>>'{reader_config,profile_version_id}', '') = ''
       and (c.cfg->>'country_from' is distinct from 'url_slug' or c.cfg->>'country_hint' is not null)
     limit 20) x;  -- fixed: a bounded re-read per run
  if v_reuse is not null then
    v_rr := security.reader_reread_v1(v_reuse, 'CF-247 s1296 reader lifecycle: an active reader configuration covers these held pages');
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', 'reused', 'pipeline.entry_matrix_sources', jsonb_build_object('sources', to_jsonb(v_reuse), 'runs', v_rr->'runs'), null);
  end if;
  -- (b) results of reads made with an active configuration: one outcome per run; a configuration whose reads yield nothing is paused and blocked
  for r in select lr.id run_id, lr.state, lr.error, lr.rows_admitted, lr.content_hash, lr.result#>>'{reader_config,profile_version_id}' ver, s.provider_id
             from pipeline.entry_matrix_runs lr join pipeline.entry_matrix_sources s on s.id = lr.source_id
            where lr.result#>>'{reader_config,profile_version_id}' is not null and lr.state in ('done', 'failed') and lr.updated_at > now() - interval '30 days'  -- fixed: outcome window
              and not exists (select 1 from pipeline.ops_remedy_outcomes o where o.evidence_signature = 'run:' || lr.id::text || ':' || coalesce(lr.content_hash, ''))
            limit 50 loop  -- fixed: outcomes recorded per run
    perform security.ops_learning_record_v1(jsonb_build_object('code', 'reader_config:aer_matrix:' || coalesce((select v.configuration->>'template' from pipeline.layer2_source_profile_versions v where v.id = r.ver::uuid), 'country_page_generic_heading'),
      'entity', 'provider:' || r.provider_id::text, 'evidence_signature', 'run:' || r.run_id::text || ':' || coalesce(r.content_hash, ''), 'performed_by', 'platform',
      'success', r.state = 'done', 'stage_advanced', r.state = 'done' and coalesce(r.rows_admitted, 0) > 0, 'expected', 'rows proposed or admitted from a page read with the configuration',
      'observed', jsonb_build_object('state', r.state, 'error', left(r.error, 200), 'rows_admitted', r.rows_admitted, 'version', r.ver),
      'evidence', jsonb_build_object('source', 'security.reader_lifecycle_tick_v1', 'run', r.run_id)));
    v_res := v_res + 1;
  end loop;
  for r in select v.id ver, v.profile_id, v.configuration from pipeline.layer2_source_profile_versions v join pipeline.layer2_source_profiles p on p.current_version_id = v.id
            where p.enabled and not p.paused and v.validation_status = 'valid' and p.profile_key like 'reader:academic_entry:%' loop
    if (select count(*) filter (where lr.state = 'failed' and lr.error like 'held_%') >= greatest(security.pipeline_num_v1('reader.qualify_min_positive', 2)::int, 1)
                and count(*) filter (where lr.state = 'done') = 0
          from pipeline.entry_matrix_runs lr where lr.result#>>'{reader_config,profile_version_id}' = r.ver::text) then
      update pipeline.layer2_source_profiles set paused = true, updated_at = now() where id = r.profile_id;
      update pipeline.layer2_source_profile_versions set validation_status = 'invalid',
             validation_result = validation_result || jsonb_build_object('paused_at', now(), 'paused_why', 'no_yield_after_activation') where id = r.ver;
      insert into pipeline.ops_remedy_blocks (knowledge_code, fingerprint, reason, signature)
      values ('reader_config:aer_matrix:' || (r.configuration->>'template'), 'provider:' || (r.configuration->>'provider_id'), 'reads with the active configuration yielded nothing; paused',
              coalesce(r.configuration->>'evidence_signature', r.ver::text))
      on conflict do nothing;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('reader_lifecycle', 'paused_no_yield', 'pipeline.layer2_source_profiles', jsonb_build_object('profile', r.profile_id, 'version', r.ver), null);
    end if;
  end loop;
  -- (c) activation of qualified versions, as its own step
  for r in select v.id ver from pipeline.layer2_source_profile_versions v join pipeline.layer2_source_profiles p on p.id = v.profile_id
            where p.profile_key like 'reader:academic_entry:%' and v.validation_status = 'valid' and not (v.validation_result ? 'activated_at') and not (v.validation_result ? 'held')
            limit 5 loop  -- fixed: activations per run
    v_act := v_act || jsonb_build_array(security.reader_activate_v1(r.ver) || jsonb_build_object('version', r.ver));
  end loop;
  -- (d) detection and proposals: provider templates of held pages that no active configuration covers and no proposal is qualifying
  for r in select s.provider_id, security.reader_aer_template_v1(lr.error) template, regexp_replace(s.url, '[^/]+/?$', '') || '%' url_like, count(*) n
             from pipeline.entry_matrix_sources s
             join lateral (select r0.error from pipeline.entry_matrix_runs r0 where r0.source_id = s.id order by r0.created_at desc limit 1) lr on true
            where s.status = 'read' and s.evidence_id is not null and security.reader_aer_template_v1(lr.error) is not null
              and security.reader_config_for_v1('academic_entry', s.provider_id, s.url) is null
              and not exists (select 1 from pipeline.ops_remedy_blocks b where b.knowledge_code = 'reader_config:aer_matrix:' || security.reader_aer_template_v1(lr.error)
                                and b.fingerprint = 'provider:' || s.provider_id::text and b.lifted_at is null)
            group by 1, 2, 3 order by count(*) desc limit 50 loop  -- fixed: candidate templates considered per run
    exit when v_n >= v_max;
    v_p := security.reader_propose_v1(r.provider_id, r.template, r.url_like);
    if coalesce((v_p->>'proposed')::boolean, false) or v_p->>'why' = 'HELD:READER_RELEASE_REQUIRED' then v_n := v_n + 1; end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('provider', r.provider_id, 'template', r.template, 'pages', r.n) || v_p);
  end loop;
  return jsonb_build_object('on', true, 'reused_sources', coalesce(cardinality(v_reuse), 0), 'outcomes_recorded', v_res, 'activations', v_act, 'proposals', v_out);
end $function$;
comment on function security.reader_lifecycle_tick_v1() is 'CF-247 s1296: the reader lifecycle step, run from the existing entry-matrix read: reuse of active configurations on held pages, outcomes of reads made with them (no yield pauses and blocks), detection of held templates and bounded proposals.';
revoke all on function security.reader_lifecycle_tick_v1() from public, anon, authenticated;

-- 8. the worker's qualification lease and record (service role)
create or replace function public.svc_reader_qualify_next(p_limit integer default 2)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tick jsonb; v jsonb := '[]'; r record; v_n int := 0; v_lim int := greatest(1, least(coalesce(p_limit, 2), 10));  -- fixed: upper bound of one call
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('reader.lifecycle_on', 0) < 1 then return '[]'::jsonb; end if;
  v_tick := security.reader_lifecycle_tick_v1();
  for r in select v.id ver, v.configuration cfg, e.key source_id from pipeline.layer2_source_profile_versions v
             join pipeline.layer2_source_profiles p on p.id = v.profile_id, jsonb_each(v.validation_result->'samples') e
            where v.validation_status = 'pending' and p.profile_key like 'reader:academic_entry:%'
              and (e.value->>'state' = 'queued' or (e.value->>'state' = 'leased' and (e.value->>'leased_until')::timestamptz < now()))
            order by v.created_at, e.key limit v_lim for update of v skip locked loop
    update pipeline.layer2_source_profile_versions
       set validation_result = jsonb_set(validation_result, array['samples', r.source_id], (validation_result->'samples'->r.source_id) || jsonb_build_object('state', 'leased', 'leased_until', now() + interval '5 minutes'))  -- fixed: lease timer
     where id = r.ver;
    v := v || (select jsonb_build_array(jsonb_build_object('run_id', r.ver::text || ':' || r.source_id, 'qualify_version_id', r.ver, 'source_id', s.id, 'provider_id', s.provider_id,
               'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'url', s.url, 'storage_path', e.storage_path, 'mime', e.mime_type,
               'model', null, 'model_code', null, 'models', '[]'::jsonb, 'det_only', true,
               'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int, 'max_tokens', security.pipeline_num_v1('entry.matrix_max_tokens', 8000)::int,
               'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int, 'slice_concurrency', 1, 'pdf_max_pages', security.pipeline_num_v1('entry.pdf_max_pages', 40)::int,
               'completeness_required', security.entry_completeness_required_v1(s.provider_id),
               'reader_config', r.cfg - 'samples' || jsonb_build_object('profile_version_id', r.ver, 'country_hint', case when r.cfg->>'country_from' = 'url_slug' then security.reader_country_from_slug_v1(s.url) end)))
                 from pipeline.entry_matrix_sources s join pipeline.evidence_artifacts e on e.id = s.evidence_id join catalogue.providers p on p.id = s.provider_id
                 left join ref.countries k on k.id = p.country_id where s.id = r.source_id::uuid);
    v_n := v_n + 1;
  end loop;
  return v;
end $function$;
comment on function public.svc_reader_qualify_next(integer) is 'CF-247 s1296: runs the reader lifecycle step, then leases sample pages of proposed reader configurations for the worker (deterministic readers only, stored copies only).';
revoke all on function public.svc_reader_qualify_next(integer) from public, anon, authenticated;
grant execute on function public.svc_reader_qualify_next(integer) to service_role;

create or replace function public.svc_reader_qualify_record(p_version uuid, p_source uuid, p_result jsonb, p_error text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_out text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_error = 'time budget' then  -- not an outcome: the sample waits for the next call
    update pipeline.layer2_source_profile_versions set validation_result = jsonb_set(validation_result, array['samples', p_source::text], (validation_result->'samples'->p_source::text) || '{"state": "queued"}'::jsonb)
     where id = p_version and validation_status = 'pending' and validation_result->'samples' ? p_source::text;
    return jsonb_build_object('status', 'requeued');
  end if;
  v_out := case when p_error is null and coalesce(p_result->>'reader', '') <> '' and jsonb_array_length(coalesce(p_result->'rows', '[]'::jsonb)) + jsonb_array_length(coalesce(p_result->'qualification_rows', '[]'::jsonb)) > 0
                  then 'deterministic_read'
                when p_error like 'held_unparsed: no deterministic reader proved%' then 'guard_passed'
                when p_error like 'held_unparsed: not a country table%' then 'guard_held'
                when p_error like 'held_incomplete%' then 'read_incomplete'
                else 'not_read' end;
  update pipeline.layer2_source_profile_versions
     set validation_result = jsonb_set(validation_result, array['samples', p_source::text], (validation_result->'samples'->p_source::text)
           || jsonb_build_object('state', 'done', 'outcome', v_out, 'error', left(p_error, 300), 'reader', p_result->>'reader',
                                 'rows', jsonb_array_length(coalesce(p_result->'rows', '[]'::jsonb)), 'qualification_rows', jsonb_array_length(coalesce(p_result->'qualification_rows', '[]'::jsonb)),
                                 'completeness', p_result#>>'{completeness,status}', 'read_at', now()))
   where id = p_version and validation_status = 'pending' and validation_result->'samples' ? p_source::text;
  return jsonb_build_object('status', v_out, 'decision', security.reader_qualify_decide_v1(p_version));
end $function$;
comment on function public.svc_reader_qualify_record(uuid, uuid, jsonb, text) is 'CF-247 s1296: records one sample read of a proposed reader configuration (deterministic read, guard passed, guard held, incomplete, not read) and decides the version when every sample is read.';
revoke all on function public.svc_reader_qualify_record(uuid, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_reader_qualify_record(uuid, uuid, jsonb, text) to service_role;

-- 9. the active configuration goes with each leased entry-matrix read (one key added)
do $edit$
declare d text := pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure);
        a text := '''completeness_required'', security.entry_completeness_required_v1(u.provider_id))), ''[]''::jsonb) into v';
begin
  if position(a in d) = 0 then raise exception 'anchor not found in svc_entry_matrix_next'; end if;
  d := replace(d, a, '''completeness_required'', security.entry_completeness_required_v1(u.provider_id),
           ''reader_config'', security.reader_config_for_v1(''academic_entry'', u.provider_id, s.url))), ''[]''::jsonb) into v  -- s1296: the active reader configuration');
  execute d;
end $edit$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); t jsonb;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1296_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1296_guard) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from catalogue.provider_entry_matrix where status = 'active') <> (select aer_active_before from s1296_guard) then raise exception 'post-check: an active entry row changed'; end if;
  if pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure) !~ 'reader_config_for_v1' then raise exception 'post-check: svc_entry_matrix_next does not hand out the configuration'; end if;
  if has_function_privilege('authenticated', 'public.svc_reader_qualify_next(integer)', 'execute') or has_function_privilege('anon', 'public.svc_reader_qualify_record(uuid,uuid,jsonb,text)', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  if security.reader_country_from_slug_v1('https://x.example/country-equivalency/india') is distinct from (select name from ref.countries where iso_alpha2 = 'IN')
     or security.reader_country_from_slug_v1('https://x.example/country-equivalency/foundation-equivalencies') is not null then
    raise exception 'post-check: the address country is not read as designed';
  end if;
end $post$;
