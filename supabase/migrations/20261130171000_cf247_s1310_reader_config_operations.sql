-- CF-247 s1310 (S1-Build; SS-Programme-Control 27 Nov 2026 13:39 and 13:43 AEDT, "P0 — Australian University Reader Plugin Implementation";
-- Platform Admin direction 27 Nov 2026, coursefinder-admin #1293: reader configuration is data, shared engine code is governed; no per-institute CI).
-- What it adds, on the s1303 and s1304 reader lifecycle (no new table, job, queue, scheduler or reader):
--   1. One operational writer for reader configurations (security.reader_config_op_v1), reached by the Adapter builder screen
--      (public.admin_reader_configs_v1, signed-in, rank-checked) and by the operations workflow reader-config-ops (public.svc_reader_configs_v1,
--      service role): list, save a draft, update its sources, qualify it on stored copies, activate it under the existing authority, pause, resume,
--      roll back to an earlier version, and requalify. A configuration is a closed list: for academic entry the template (country_page_generic_heading
--      or provider_settings), the address pattern, country_from and overrides of registered reading.entry_* settings within their ranges; for
--      scholarships the hosts the listing links its awards to (hosts of the provider's own site). No code, SQL, selector script or prompt.
--   2. A draft is a version that is pending with its samples in state draft (never leased); Qualify queues them for the existing worker lease
--      (svc_reader_qualify_next, svc_reader_qualify_sch_next) on stored copies only, deterministic readers only, no fetch, no model, $0.
--   3. Negative samples by class: a provider_settings negative must not be read into rows (deterministic_read or guard_passed fails it); a
--      scholarship negative listing must not gain items. Two anchored, md5-guarded edits.
--   4. Activation stays the existing step and authority: academic entry under the knowledge pattern's recorded standing authority (Standing
--      Authority Charter 23 Nov 2026 item 1; a provider_settings pattern is added on the same footing); scholarships stay HELD:ACTIVATION_AUTHORITY
--      until the Platform Admin grants it (security.ops_learning_eligibility_set_v1). An activated provider_settings version has its covered pages
--      read again once through the existing re-read (security.reader_reread_v1).
--   5. Version history and annual source-change requalification (security.reader_config_maintain_v1, run from the existing lifecycle step): an
--      active version older than reader.requalify_days, or whose sample copies changed, gets a successor version qualified on the current copies;
--      a successor that fails pauses the configuration (outcome recorded, rollback available), one that passes is activated by the existing step.
-- G1: no job (the existing entry-matrix job 337 runs the lifecycle step). G2: reader.requalify_days is a setting. G3: 75/48 checked; nothing in the
-- consumer API changes. Locks and cron checked. No spend. Nothing dropped or deleted.
-- Replaces: security.reader_qualify_decide_v1 (md5 39a7b937; negatives by class), public.svc_reader_qualify_sch_record (md5 0e0ea7b8; negative
--   listings), security.reader_lifecycle_tick_v1 (md5 b42617c9; one anchored addition: the maintenance step).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

create temp table s1310_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from catalogue.provider_entry_matrix where status = 'active') as aer_active_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('security.reader_qualify_decide_v1(uuid)'::regprocedure)) <> '39a7b937df4feae498a3bee1793a3d7b' then
    raise exception 'pre-check: security.reader_qualify_decide_v1 is not the definition this change was written against';
  end if;
  if md5(pg_get_functiondef('public.svc_reader_qualify_sch_record(uuid,bigint,jsonb)'::regprocedure)) <> '0e0ea7b891eb4688f998ba991dce7e94' then
    raise exception 'pre-check: public.svc_reader_qualify_sch_record is not the definition this change was written against';
  end if;
  if md5(pg_get_functiondef('security.reader_lifecycle_tick_v1()'::regprocedure)) <> 'b42617c90c58499582670c4240bc075b' then
    raise exception 'pre-check: security.reader_lifecycle_tick_v1 is not the definition this change was written against';
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'reader.requalify_days', 'Reader configurations: requalify an active configuration after',
        'An active reader configuration is qualified again on the current stored copies after this many days, or sooner when one of its sample copies changes. A successor that passes replaces it; one that fails pauses it for a person (roll back or fix on the Adapter builder).',
        'number', to_jsonb(365), 30, 730, 'days', 1565, 'Entry requirements', 'security.reader_config_maintain_v1', 'CF-247 s1310 (SS-Programme-Control 27 Nov 2026 13:39)')
on conflict do nothing;

insert into pipeline.ops_remedy_knowledge (code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
  no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
values ('reader_config:aer_matrix:provider_settings', 'aer', 'Entry-matrix pages of one provider read with overrides of registered reader settings',
        array['reader:academic_entry:%:provider_settings:%'], 'provider_settings', null,
        '{"signal": "a provider''s entry pages are read with 0 rows or dropped rows that a registered reading.entry_* setting governs", "configuration": {"settings": "registered reading.entry_* keys within their ranges"}}'::jsonb,
        'auto', 'platform', 'the provider''s pages read with the configuration propose rows that the completeness guard, the matrix machine rule and Layer 4 then decide',
        'the same settings on the same stored copies already failed qualification or yielded nothing after activation: wait for a changed copy',
        'a provider template whose stored copies a registered reader setting governs; qualified on that provider''s stored copies, negatives not read into rows',
        true, 'Standing Authority Charter 23 Nov 2026 item 1 (AER v2 readers pre-authorised) and Platform Admin direction 27 Nov 2026 (coursefinder-admin #1293: data-only reader configuration); a pass relying on the routed model activates only while that route has a usable model',
        now(), 'S1-Build s1310', 'CF-247 s1310')
on conflict (code) do nothing;

-- 1. a configuration is a closed list: validate it and return the cleaned configuration, or raise with the reason
create or replace function security.reader_config_clean_v1(p_domain text, p_provider uuid, p_cfg jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_t text := p_cfg->>'template'; v_like text := btrim(coalesce(p_cfg->>'url_like', '')); v_set jsonb := '{}'; k text; x jsonb; s record; v_hosts jsonb := '[]';
        v_base text; h text; v_from text := nullif(btrim(coalesce(p_cfg->>'country_from', '')), '');
begin
  if p_domain = 'academic_entry' then
    if v_t not in ('country_page_generic_heading', 'provider_settings') then raise exception 'INVALID_INPUT: template must be country_page_generic_heading or provider_settings'; end if;
    if v_like !~ '^https?://[^/%]+/' or length(v_like) > 300 then  -- fixed: the address pattern's length bound
      raise exception 'INVALID_INPUT: url_like is an address pattern on the provider''s own site (SQL like, %% for any text)';
    end if;
    if not exists (select 1 from pipeline.entry_matrix_sources s0 where s0.provider_id = p_provider and s0.url like v_like) then
      raise exception 'INVALID_INPUT: no entry-matrix source of this provider matches url_like';
    end if;
    if v_from is not null and v_from <> 'url_slug' then raise exception 'INVALID_INPUT: country_from is url_slug or empty'; end if;
    if v_t = 'country_page_generic_heading' and v_from is null then raise exception 'INVALID_INPUT: a country page configuration takes country_from url_slug'; end if;
    for k, x in select * from jsonb_each(coalesce(p_cfg->'settings', '{}'::jsonb)) loop
      select * into s from pipeline.platform_toolset_settings t where t.toolset_key = 'pipeline' and t.key = k;
      if k !~ '^reading\.entry_[a-z0-9_]+$' or s.key is null then raise exception 'INVALID_INPUT: % is not a registered reading.entry_ setting', k; end if;
      if jsonb_typeof(s.value) = 'number' then
        if jsonb_typeof(x) <> 'number' or (s.min_value is not null and x::text::numeric < s.min_value) or (s.max_value is not null and x::text::numeric > s.max_value) then
          raise exception 'INVALID_INPUT: % takes a number from % to %', k, s.min_value, s.max_value;
        end if;
      elsif jsonb_typeof(s.value) = 'array' then
        if jsonb_typeof(x) <> 'array' or jsonb_array_length(x) > 200 or exists (select 1 from jsonb_array_elements(x) e where jsonb_typeof(e) <> 'string' or length(e #>> '{}') > 200) then  -- fixed: the list bounds the worker accepts (reader-config.ts)
          raise exception 'INVALID_INPUT: % takes a list of up to 200 short texts', k;
        end if;
      else raise exception 'INVALID_INPUT: % cannot be set by a configuration', k;
      end if;
      v_set := v_set || jsonb_build_object(k, x);
    end loop;
    if v_t = 'provider_settings' and v_set = '{}'::jsonb then raise exception 'INVALID_INPUT: a provider_settings configuration sets at least one reading.entry_ setting'; end if;
    return jsonb_build_object('reader_config', 'reader-config-v1', 'domain', 'academic_entry', 'template', v_t, 'provider_id', p_provider, 'url_like', v_like,
                              'country_from', v_from, 'settings', v_set);
  elsif p_domain = 'scholarship' then
    if coalesce(v_t, 'link_hosts') <> 'link_hosts' then raise exception 'INVALID_INPUT: the scholarship template is link_hosts'; end if;
    select regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '') into v_base
      from pipeline.scholarship_discovery_providers d where d.provider_id = p_provider;
    for h in select lower(btrim(e #>> '{}')) from jsonb_array_elements(coalesce(p_cfg->'hosts_add', '[]'::jsonb)) e loop
      if h !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' or v_base is null or not (h = v_base or h like '%.' || v_base) then
        raise exception 'INVALID_INPUT: % is not a host of the provider''s own site (%)', h, coalesce(v_base, 'no site recorded');
      end if;
      v_hosts := v_hosts || to_jsonb(h);
    end loop;
    if jsonb_array_length(v_hosts) > 10 then raise exception 'INVALID_INPUT: at most 10 hosts'; end if;  -- fixed: a configuration's host list bound
    return jsonb_build_object('reader_config', 'reader-config-v1', 'domain', 'scholarship', 'template', 'link_hosts', 'provider_id', p_provider, 'hosts_add', v_hosts);
  end if;
  raise exception 'INVALID_INPUT: domain is academic_entry or scholarship';
end $function$;
comment on function security.reader_config_clean_v1(text, uuid, jsonb) is 'CF-247 s1310: validates a reader configuration against its closed list (academic entry: template, address pattern, country_from, registered reading.entry_* settings within their ranges; scholarships: hosts of the provider''s own site) and returns it cleaned, or raises INVALID_INPUT.';
revoke all on function security.reader_config_clean_v1(text, uuid, jsonb) from public, anon, authenticated;

-- 2. the samples of a version, snapshotted from the current stored copies (academic entry: entry-matrix sources; scholarships: listing pages)
create or replace function security.reader_config_samples_v1(p_domain text, p_provider uuid, p_like text, p_samples jsonb, p_state text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v jsonb := '{}'; e jsonb; v_id text; v_role text; v_hash text; v_path text; v_url text; v_max int := greatest(security.pipeline_num_v1('reader.qualify_samples_max', 8)::int, 2);
begin
  if jsonb_typeof(p_samples) <> 'array' or jsonb_array_length(p_samples) = 0 then raise exception 'INVALID_INPUT: samples is a non-empty list of {id, role}'; end if;
  if jsonb_array_length(p_samples) > v_max then raise exception 'INVALID_INPUT: at most % samples (setting reader.qualify_samples_max)', v_max; end if;
  for e in select * from jsonb_array_elements(p_samples) loop
    v_id := coalesce(e->>'id', e->>'source_id', e->>'listing_id'); v_role := coalesce(e->>'role', 'positive');
    if v_role not in ('positive', 'negative') then raise exception 'INVALID_INPUT: a sample role is positive or negative'; end if;
    if p_domain = 'academic_entry' then
      select s.content_hash, s.url into v_hash, v_url from pipeline.entry_matrix_sources s
       where s.id::text = v_id and s.provider_id = p_provider and s.evidence_id is not null;
      if v_url is null then raise exception 'INVALID_INPUT: sample % is not a stored entry-matrix source of this provider', v_id; end if;
      if v_role = 'positive' and v_url not like p_like then raise exception 'INVALID_INPUT: positive sample % is outside the address pattern', v_id; end if;
      v := v || jsonb_build_object(v_id, jsonb_build_object('state', p_state, 'role', v_role, 'content_hash', v_hash, 'url', left(v_url, 300)));
    else
      select l.url, (select a.storage_path from pipeline.evidence_artifacts a where a.source_url = l.url and a.storage_path is not null order by a.created_at desc limit 1)
        into v_url, v_path from pipeline.scholarship_listing_pages l where l.id::text = v_id and l.provider_id = p_provider;
      if v_url is null or v_path is null then raise exception 'INVALID_INPUT: sample % is not a listing page of this provider with a stored copy', v_id; end if;
      v := v || jsonb_build_object(v_id, jsonb_build_object('state', p_state, 'role', v_role, 'path', v_path, 'url', left(v_url, 300)));
    end if;
  end loop;
  if not exists (select 1 from jsonb_each(v) x where x.value->>'role' = 'positive') then raise exception 'INVALID_INPUT: at least one positive sample'; end if;
  return v;
end $function$;
comment on function security.reader_config_samples_v1(text, uuid, text, jsonb, text) is 'CF-247 s1310: the sample pages of a reader configuration version with the stored copy each is read from (content hash or storage path), checked to be the provider''s own stored pages.';
revoke all on function security.reader_config_samples_v1(text, uuid, text, jsonb, text) from public, anon, authenticated;

-- 3. requalification: a successor version of the same configuration, qualified on the current stored copies
create or replace function security.reader_config_requalify_v1(p_version uuid, p_by text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v pipeline.layer2_source_profile_versions%rowtype; v_dom text; v_s jsonb; v_cfg jsonb; v_next int; v_new uuid;
begin
  select * into v from pipeline.layer2_source_profile_versions where id = p_version;
  if v.id is null then raise exception 'INVALID_INPUT: no such version'; end if;
  if exists (select 1 from pipeline.layer2_source_profile_versions x where x.profile_id = v.profile_id and x.validation_status = 'pending') then
    return jsonb_build_object('requalified', false, 'why', 'a version of this configuration is already a draft or being qualified');
  end if;
  v_dom := v.configuration->>'domain';
  v_s := security.reader_config_samples_v1(v_dom, (v.configuration->>'provider_id')::uuid, v.configuration->>'url_like',
           (select jsonb_agg(jsonb_build_object('id', e.key, 'role', coalesce(e.value->>'role', 'positive'))) from jsonb_each(v.validation_result->'samples') e), 'queued');
  v_cfg := (v.configuration - 'samples' - 'proposed_at' - 'proposed_by' - 'evidence_signature' - 'requalify_of')
           || jsonb_build_object('samples', (select jsonb_agg(jsonb_build_object('source_id', e.key, 'listing_id', e.key, 'role', e.value->>'role', 'content_hash', e.value->>'content_hash', 'path', e.value->>'path')) from jsonb_each(v_s) e),
                                 'evidence_signature', md5((select string_agg(e.key || ':' || coalesce(e.value->>'content_hash', e.value->>'path', ''), ',' order by e.key) from jsonb_each(v_s) e)),
                                 'requalify_of', v.id, 'proposed_at', now(), 'proposed_by', p_by);
  select coalesce(max(version_no), 0) + 1 into v_next from pipeline.layer2_source_profile_versions where profile_id = v.profile_id;
  insert into pipeline.layer2_source_profile_versions (profile_id, version_no, configuration, configuration_hash, validation_status, validation_result, change_control_ref, created_by)
  values (v.profile_id, v_next, v_cfg, md5(v_cfg::text), 'pending', jsonb_build_object('samples', v_s, 'requalify_of', v.id, 'requested_by', p_by, 'reason', left(p_reason, 300)), 'CF-247 s1310', null)
  returning id into v_new;
  update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('requalify_requested_at', now(), 'successor', v_new) where id = v.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reader_lifecycle', 'requalify_requested', 'pipeline.layer2_source_profile_versions', jsonb_build_object('version', v_new, 'of', v.id, 'by', p_by, 'reason', left(p_reason, 300)), null);
  return jsonb_build_object('requalified', true, 'version', v_new, 'version_no', v_next, 'samples', (select count(*) from jsonb_each(v_s)));
end $function$;
comment on function security.reader_config_requalify_v1(uuid, text, text) is 'CF-247 s1310: a successor version of a reader configuration with its samples snapshotted from the current stored copies, queued for qualification (the annual or source-change requalification, or a person''s Requalify).';
revoke all on function security.reader_config_requalify_v1(uuid, text, text) from public, anon, authenticated;

-- 4. maintenance, run from the lifecycle step: one re-read after a provider_settings activation, requalification when due, a failed successor pauses
create or replace function security.reader_config_maintain_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare r record; v_ids uuid[]; v_rr jsonb; n_rr int := 0; n_rq int := 0; n_pause int := 0; v_days int := greatest(security.pipeline_num_v1('reader.requalify_days', 365)::int, 30);
begin
  -- (a) an activated provider_settings version: its covered pages are read again once, through the existing re-read
  for r in select v.id, v.configuration cfg from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id = p.current_version_id
            where p.profile_key like 'reader:academic_entry:%:provider_settings:%' and p.enabled and not p.paused and v.validation_status = 'valid'
              and v.validation_result ? 'activated_at' and not (v.validation_result ? 'reread_at') limit 5 loop  -- fixed: re-reads started per run
    select array_agg(s.id) into v_ids from pipeline.entry_matrix_sources s
     where s.provider_id = (r.cfg->>'provider_id')::uuid and s.url like r.cfg->>'url_like' and s.status = 'read' and s.evidence_id is not null;
    v_rr := security.reader_reread_v1(coalesce(v_ids, '{}'::uuid[]), 'CF-247 s1310 reader configuration ' || r.id || ' active: its pages are read again with it');
    update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('reread_at', now(), 'reread_runs', v_rr->'runs', 'reread_sources', coalesce(cardinality(v_ids), 0)) where id = r.id;
    n_rr := n_rr + 1;
  end loop;
  -- (b) requalification: an active version past reader.requalify_days, or whose sample copies changed, gets a successor (at most once a day)
  for r in select v.id, v.validation_result vr, v.configuration cfg from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id = p.current_version_id
            where p.profile_key like 'reader:%' and p.enabled and not p.paused and v.validation_status = 'valid' and v.validation_result ? 'activated_at'
              and coalesce((v.validation_result->>'requalify_requested_at')::timestamptz, '-infinity') < now() - interval '1 day'  -- fixed: one successor a day at most
              and not exists (select 1 from pipeline.layer2_source_profile_versions x where x.profile_id = p.id and x.validation_status = 'pending')
              and ((v.validation_result->>'activated_at')::timestamptz < now() - make_interval(days => v_days)
                   or exists (select 1 from jsonb_each(v.validation_result->'samples') e join pipeline.entry_matrix_sources s on s.id::text = e.key
                               where v.configuration->>'domain' = 'academic_entry' and s.content_hash is distinct from e.value->>'content_hash')
                   or exists (select 1 from jsonb_each(v.validation_result->'samples') e join pipeline.scholarship_listing_pages l on l.id::text = e.key
                               where v.configuration->>'domain' = 'scholarship' and e.value ? 'path'
                                 and (select a.storage_path from pipeline.evidence_artifacts a where a.source_url = l.url and a.storage_path is not null order by a.created_at desc limit 1) is distinct from e.value->>'path'))
            limit 5 loop  -- fixed: requalifications started per run
    perform security.reader_config_requalify_v1(r.id, 'platform', case when (r.vr->>'activated_at')::timestamptz < now() - make_interval(days => v_days)
                                                                       then 'annual requalification (reader.requalify_days)' else 'a sample copy changed' end);
    n_rq := n_rq + 1;
  end loop;
  -- (c) a successor that failed: the active configuration is paused for a person (roll back, or fix and qualify a new draft)
  for r in select c.id cur, c.profile_id, s.id succ, c.configuration cfg from pipeline.layer2_source_profile_versions s
             join pipeline.layer2_source_profile_versions c on c.id = (s.validation_result->>'requalify_of')::uuid
             join pipeline.layer2_source_profiles p on p.id = c.profile_id and p.current_version_id = c.id and p.enabled and not p.paused
            where s.validation_status = 'invalid' and not (c.validation_result ? 'requalify_failed_at') loop
    update pipeline.layer2_source_profiles set paused = true, updated_at = now() where id = r.profile_id;
    update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('requalify_failed_at', now(), 'failed_successor', r.succ) where id = r.cur;
    perform security.ops_learning_record_v1(jsonb_build_object('code', case when r.cfg->>'domain' = 'scholarship' then 'reader_config:sch_listing:link_hosts' else 'reader_config:aer_matrix:' || (r.cfg->>'template') end,
      'entity', 'provider:' || (r.cfg->>'provider_id'), 'evidence_signature', 'requalify:' || r.succ::text, 'performed_by', 'platform', 'success', false, 'stage_advanced', false,
      'expected', 'the configuration qualifies again on the current stored copies', 'observed', jsonb_build_object('successor', r.succ, 'disposition', 'paused for a person'),
      'evidence', jsonb_build_object('source', 'security.reader_config_maintain_v1', 'version', r.cur)));
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', 'paused_requalification_failed', 'pipeline.layer2_source_profiles', jsonb_build_object('profile', r.profile_id, 'version', r.cur, 'successor', r.succ), null);
    n_pause := n_pause + 1;
  end loop;
  return jsonb_build_object('rereads', n_rr, 'requalifications', n_rq, 'paused', n_pause);
end $function$;
comment on function security.reader_config_maintain_v1() is 'CF-247 s1310: reader configuration maintenance in the lifecycle step: one re-read after a provider_settings activation, requalification when reader.requalify_days pass or a sample copy changes, and a failed successor pauses the configuration for a person.';
revoke all on function security.reader_config_maintain_v1() from public, anon, authenticated;

-- 5. the operational writer and the read (one function; the callers check who may do what)
create or replace function security.reader_config_op_v1(p_action text, p_args jsonb, p_by text, p_rank int)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_pid uuid; v_dom text; v_cfg jsonb; v_key text; v_src uuid; v_prof uuid; v_ver uuid; v_next int; v_s jsonb; v jsonb; x pipeline.layer2_source_profile_versions%rowtype;
        p pipeline.layer2_source_profiles%rowtype; v_reason text := left(btrim(coalesce(p_args->>'reason', '')), 300); v_r jsonb;
begin
  if p_action <> 'list' and v_reason = '' then raise exception 'INVALID_INPUT: a reason is required'; end if;
  if p_action in ('activate', 'pause', 'resume', 'rollback') and p_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action in ('save_draft', 'qualify', 'requalify', 'discard_draft') and p_rank < 5 then raise exception 'PIM Admin role required' using errcode = '42501'; end if;
  if p_action in ('discard_draft', 'qualify', 'requalify', 'activate', 'pause', 'resume', 'rollback') and not (p_args ? 'version_id') then raise exception 'INVALID_INPUT: version_id'; end if;
  if p_args ? 'version_id' then
    select * into x from pipeline.layer2_source_profile_versions where id = (p_args->>'version_id')::uuid;
    if x.id is null then raise exception 'INVALID_INPUT: no such version'; end if;
    select * into p from pipeline.layer2_source_profiles where id = x.profile_id;
    if p.profile_key not like 'reader:%' then raise exception 'INVALID_INPUT: not a reader configuration'; end if;
  end if;

  if p_action = 'list' then
    v_pid := (p_args->>'provider_id')::uuid;
    if v_pid is null or not exists (select 1 from catalogue.providers c where c.id = v_pid) then raise exception 'INVALID_INPUT: provider_id'; end if;
    return jsonb_build_object(
      'provider_id', v_pid, 'can_draft', p_rank >= 5, 'can_activate', p_rank >= 6,
      'requalify_days', security.pipeline_num_v1('reader.requalify_days', 365)::int, 'min_positive', security.pipeline_num_v1('reader.qualify_min_positive', 2)::int,
      'samples_max', security.pipeline_num_v1('reader.qualify_samples_max', 8)::int, 'lifecycle_on', security.pipeline_num_v1('reader.lifecycle_on', 0) >= 1,
      'configurations', coalesce((select jsonb_agg(jsonb_build_object('profile_id', pr.id, 'profile_key', pr.profile_key, 'domain', pr.domain, 'enabled', pr.enabled, 'paused', pr.paused,
          'current_version_id', pr.current_version_id, 'owner', pr.operational_owner, 'updated_at', pr.updated_at,
          'versions', (select jsonb_agg(jsonb_build_object('id', vv.id, 'version_no', vv.version_no, 'status', vv.validation_status,
                          'draft', coalesce((vv.validation_result->>'draft')::boolean, false), 'configuration', vv.configuration - 'samples',
                          'samples', vv.validation_result->'samples', 'decided_at', vv.validation_result->'decided_at', 'passed', vv.validation_result->'passed',
                          'mode', vv.validation_result->'mode', 'held', vv.validation_result->'held', 'activated_at', vv.validation_result->'activated_at',
                          'authority', vv.validation_result->'authority', 'reread_at', vv.validation_result->'reread_at', 'reread_runs', vv.validation_result->'reread_runs',
                          'requalify_of', vv.validation_result->'requalify_of', 'requalify_failed_at', vv.validation_result->'requalify_failed_at',
                          'paused_why', vv.validation_result->'paused_why', 'rule', vv.validation_result->'rule', 'hosts_add', vv.validation_result->'hosts_add',
                          'result', vv.validation_result - 'samples', 'created_at', vv.created_at, 'change_control_ref', vv.change_control_ref) order by vv.version_no desc)
                        from pipeline.layer2_source_profile_versions vv where vv.profile_id = pr.id),
          'runs', (select jsonb_build_object('reads', count(*), 'done', count(*) filter (where r.state = 'done'), 'rows_admitted', coalesce(sum(r.rows_admitted), 0),
                          'last', max(r.updated_at)) from pipeline.entry_matrix_runs r
                    where pr.domain = 'academic_entry' and r.result#>>'{reader_config,profile_version_id}' in (select vv.id::text from pipeline.layer2_source_profile_versions vv where vv.profile_id = pr.id)))
          order by pr.domain, pr.profile_key)
        from pipeline.layer2_source_profiles pr where pr.profile_key like 'reader:academic_entry:' || v_pid::text || ':%' or pr.profile_key like 'reader:scholarship:' || v_pid::text || ':%'), '[]'::jsonb),
      'entry_sources', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'url', s.url, 'status', s.status, 'stored', s.evidence_id is not null, 'content_hash', left(coalesce(s.content_hash, ''), 12),
          'read_at', s.read_at, 'last_state', lr.state, 'last_error', left(lr.error, 200), 'rows_admitted', lr.rows_admitted, 'rows_dropped', lr.rows_dropped, 'last_read', lr.created_at,
          'reader_config', lr.result#>>'{reader_config,profile_version_id}') order by s.status, s.url)
        from pipeline.entry_matrix_sources s left join lateral (select r0.* from pipeline.entry_matrix_runs r0 where r0.source_id = s.id order by r0.created_at desc limit 1) lr on true
        where s.provider_id = v_pid and s.status <> 'inactive'), '[]'::jsonb),
      'listing_pages', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'active', l.active, 'status', l.status, 'items', jsonb_array_length(coalesce(l.items, '[]'::jsonb)),
          'total_stated', l.total_stated, 'page_state', l.page_state, 'read_at', l.read_at,
          'stored', exists (select 1 from pipeline.evidence_artifacts a where a.source_url = l.url and a.storage_path is not null)) order by l.active desc, l.id)
        from pipeline.scholarship_listing_pages l where l.provider_id = v_pid), '[]'::jsonb),
      'entry_rows', jsonb_build_object('active', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.status = 'active'),
                                       'other', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.status <> 'active')),
      'settings', coalesce((select jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'value', t.value, 'min', t.min_value, 'max', t.max_value, 'unit', t.unit) order by t.key)
        from pipeline.platform_toolset_settings t where t.toolset_key = 'pipeline' and t.key ~ '^reading\.entry_[a-z0-9_]+$' and jsonb_typeof(t.value) in ('number', 'array')), '[]'::jsonb),
      'authority', coalesce((select jsonb_agg(jsonb_build_object('code', k.code, 'authority', k.authority, 'auto', k.auto_eligible, 'why', k.eligibility_reason) order by k.code)
        from pipeline.ops_remedy_knowledge k where k.code like 'reader_config:%'), '[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'detail', e.detail) order by e.created_at desc) from (
          select e0.* from pipeline.admin_control_events e0 where e0.area = 'reader_lifecycle'
             and (e0.detail->>'profile' in (select pr.id::text from pipeline.layer2_source_profiles pr where pr.profile_key like 'reader:%:' || v_pid::text || ':%')
               or e0.detail->>'version' in (select vv.id::text from pipeline.layer2_source_profile_versions vv join pipeline.layer2_source_profiles pr on pr.id = vv.profile_id where pr.profile_key like 'reader:%:' || v_pid::text || ':%'))
           order by e0.created_at desc limit 40) e), '[]'::jsonb));  -- fixed: events shown
  end if;

  if p_action = 'save_draft' then
    v_pid := (p_args->>'provider_id')::uuid; v_dom := p_args->>'domain';
    if v_pid is null or not exists (select 1 from catalogue.providers c where c.id = v_pid) then raise exception 'INVALID_INPUT: provider_id'; end if;
    v_cfg := security.reader_config_clean_v1(v_dom, v_pid, coalesce(p_args->'configuration', '{}'::jsonb));
    v_s := security.reader_config_samples_v1(v_dom, v_pid, v_cfg->>'url_like', p_args->'samples', 'draft');
    v_key := case when v_dom = 'academic_entry' then 'reader:academic_entry:' || v_pid::text || ':' || (v_cfg->>'template') || ':' || left(md5(v_cfg->>'url_like'), 8)
                  else 'reader:scholarship:' || v_pid::text || ':link_hosts:all' end;
    select s.id into v_src from pipeline.sources s where s.provider_id = v_pid order by (s.status = 'active') desc, s.trust_rank desc nulls last, s.created_at limit 1;
    if v_src is null then raise exception 'INVALID_INPUT: the provider has no source record to hold a configuration'; end if;
    insert into pipeline.layer2_source_profiles (source_id, profile_key, domain, acquisition_method, target_entity_type, authority_class, enabled, paused, operational_owner)
    values (v_src, v_key, v_dom, 'other_deterministic', case when v_dom = 'scholarship' then 'scholarship_listing' else 'entry_matrix' end, 'first_party', false, true, 'Reader configurations (s1310): ' || left(p_by, 80))
    on conflict (profile_key) do update set updated_at = now() returning id into v_prof;
    if exists (select 1 from pipeline.layer2_source_profile_versions q where q.profile_id = v_prof and q.validation_status = 'pending' and not coalesce((q.validation_result->>'draft')::boolean, false)) then
      raise exception 'INVALID_INPUT: a version of this configuration is being qualified; wait for its result';
    end if;
    v_cfg := v_cfg || jsonb_build_object('samples', (select jsonb_agg(jsonb_build_object('source_id', e.key, 'listing_id', e.key, 'role', e.value->>'role', 'content_hash', e.value->>'content_hash', 'path', e.value->>'path')) from jsonb_each(v_s) e),
                                         'evidence_signature', md5((select string_agg(e.key || ':' || coalesce(e.value->>'content_hash', e.value->>'path', ''), ',' order by e.key) from jsonb_each(v_s) e)),
                                         'source_note', left(coalesce(p_args->>'source_note', ''), 300), 'proposed_at', now(), 'proposed_by', left(p_by, 120));
    select q.id into v_ver from pipeline.layer2_source_profile_versions q where q.profile_id = v_prof and q.validation_status = 'pending' and coalesce((q.validation_result->>'draft')::boolean, false);
    if v_ver is not null then
      update pipeline.layer2_source_profile_versions set configuration = v_cfg, configuration_hash = md5(v_cfg::text),
             validation_result = jsonb_build_object('draft', true, 'samples', v_s, 'saved_by', left(p_by, 120), 'reason', v_reason, 'saved_at', now()) where id = v_ver;
    else
      select coalesce(max(version_no), 0) + 1 into v_next from pipeline.layer2_source_profile_versions where profile_id = v_prof;
      insert into pipeline.layer2_source_profile_versions (profile_id, version_no, configuration, configuration_hash, validation_status, validation_result, change_control_ref)
      values (v_prof, v_next, v_cfg, md5(v_cfg::text), 'pending', jsonb_build_object('draft', true, 'samples', v_s, 'saved_by', left(p_by, 120), 'reason', v_reason, 'saved_at', now()), 'CF-247 s1310')
      returning id into v_ver;
      -- a configuration that is not switched on points at its newest version
      update pipeline.layer2_source_profiles set current_version_id = case when enabled then current_version_id else v_ver end, updated_at = now() where id = v_prof;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', 'draft_saved', 'pipeline.layer2_source_profile_versions', jsonb_build_object('profile', v_prof, 'version', v_ver, 'profile_key', v_key, 'by', left(p_by, 120), 'reason', v_reason, 'samples', (select count(*) from jsonb_each(v_s))), null);
    return jsonb_build_object('saved', true, 'profile_id', v_prof, 'version_id', v_ver, 'profile_key', v_key);
  end if;

  if p_action = 'discard_draft' then
    if x.validation_status <> 'pending' or not coalesce((x.validation_result->>'draft')::boolean, false) then raise exception 'INVALID_INPUT: only a draft can be discarded'; end if;
    update pipeline.layer2_source_profile_versions set validation_status = 'invalid', validation_result = validation_result - 'draft' || jsonb_build_object('discarded_at', now(), 'discarded_by', left(p_by, 120), 'reason', v_reason) where id = x.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('reader_lifecycle', 'draft_discarded', 'pipeline.layer2_source_profile_versions', jsonb_build_object('profile', x.profile_id, 'version', x.id, 'by', left(p_by, 120), 'reason', v_reason), null);
    return jsonb_build_object('discarded', true);
  end if;

  if p_action = 'qualify' then
    if x.validation_status <> 'pending' or not coalesce((x.validation_result->>'draft')::boolean, false) then raise exception 'INVALID_INPUT: only a draft is sent to qualification (use requalify for a decided version)'; end if;
    v_s := security.reader_config_samples_v1(x.configuration->>'domain', (x.configuration->>'provider_id')::uuid, x.configuration->>'url_like',
             (select jsonb_agg(jsonb_build_object('id', e.key, 'role', coalesce(e.value->>'role', 'positive'))) from jsonb_each(x.validation_result->'samples') e), 'queued');
    update pipeline.layer2_source_profile_versions
       set configuration = configuration || jsonb_build_object('evidence_signature', md5((select string_agg(e.key || ':' || coalesce(e.value->>'content_hash', e.value->>'path', ''), ',' order by e.key) from jsonb_each(v_s) e))),
           validation_result = (validation_result - 'draft') || jsonb_build_object('samples', v_s, 'qualify_requested_at', now(), 'qualify_requested_by', left(p_by, 120), 'reason', v_reason)
     where id = x.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', 'qualify_requested', 'pipeline.layer2_source_profile_versions', jsonb_build_object('profile', x.profile_id, 'version', x.id, 'by', left(p_by, 120), 'reason', v_reason, 'samples', (select count(*) from jsonb_each(v_s))), null);
    return jsonb_build_object('queued', true, 'version_id', x.id, 'samples', (select count(*) from jsonb_each(v_s)));
  end if;

  if p_action = 'requalify' then
    return security.reader_config_requalify_v1(x.id, left(p_by, 120), v_reason);
  end if;

  if p_action = 'activate' then
    if x.validation_status <> 'valid' or x.validation_result ? 'activated_at' then raise exception 'INVALID_INPUT: only a qualified version that is not yet active is activated'; end if;
    v_r := case when x.configuration->>'domain' = 'scholarship' then security.reader_activate_sch_v1(x.id) else security.reader_activate_v1(x.id) end;
    if coalesce((v_r->>'activated')::boolean, false) then
      update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('activated_by', left(p_by, 120), 'activation_reason', v_reason) where id = x.id;
      v_r := v_r || jsonb_build_object('maintenance', security.reader_config_maintain_v1());
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', 'activation_requested', 'pipeline.layer2_source_profile_versions', jsonb_build_object('profile', x.profile_id, 'version', x.id, 'by', left(p_by, 120), 'reason', v_reason, 'result', v_r), null);
    return v_r;
  end if;

  if p_action in ('pause', 'resume') then
    update pipeline.layer2_source_profiles set paused = (p_action = 'pause'), updated_at = now() where id = p.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', case when p_action = 'pause' then 'paused_by_person' else 'resumed_by_person' end, 'pipeline.layer2_source_profiles', jsonb_build_object('profile', p.id, 'version', x.id, 'by', left(p_by, 120), 'reason', v_reason), null);
    return jsonb_build_object(p_action || 'd', true);
  end if;

  if p_action = 'rollback' then
    -- back to a version that was active before: it becomes current again, the current one is superseded, and its pages are read again
    if not (x.validation_result ? 'activated_at') or x.id = p.current_version_id or x.validation_status not in ('superseded', 'valid') then
      raise exception 'INVALID_INPUT: roll back to an earlier version that was active';
    end if;
    update pipeline.layer2_source_profile_versions set validation_status = 'superseded' where profile_id = p.id and validation_status = 'valid' and id <> x.id;
    update pipeline.layer2_source_profile_versions set validation_status = 'valid', validation_result = (validation_result - 'reread_at') || jsonb_build_object('rolled_back_at', now(), 'rolled_back_by', left(p_by, 120), 'rollback_reason', v_reason) where id = x.id;
    update pipeline.layer2_source_profiles set current_version_id = x.id, enabled = true, paused = false, updated_at = now() where id = p.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reader_lifecycle', 'rolled_back', 'pipeline.layer2_source_profiles', jsonb_build_object('profile', p.id, 'version', x.id, 'from', p.current_version_id, 'by', left(p_by, 120), 'reason', v_reason), null);
    if x.configuration->>'domain' = 'scholarship' then
      update pipeline.scholarship_listing_pages l set next_read_at = now() where l.provider_id = (x.configuration->>'provider_id')::uuid and l.active and l.status = 'read';
    end if;
    return jsonb_build_object('rolled_back', true, 'maintenance', security.reader_config_maintain_v1());
  end if;

  raise exception 'INVALID_INPUT: action is list, save_draft, discard_draft, qualify, requalify, activate, pause, resume or rollback';
end $function$;
comment on function security.reader_config_op_v1(text, jsonb, text, int) is 'CF-247 s1310: the reader configuration writer and read (list, save_draft, discard_draft, qualify, requalify, activate, pause, resume, rollback); every write needs a reason and is an admin_control_events line; activation stays the existing step and authority.';
revoke all on function security.reader_config_op_v1(text, jsonb, text, int) from public, anon, authenticated;

create or replace function public.admin_reader_configs_v1(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_rank int := coalesce(security.current_role_rank(), 0);
begin
  if auth.uid() is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if v_rank < 5 then raise exception 'PIM Admin role required' using errcode = '42501'; end if;  -- fixed: who reads (the Adapter builder tab's rank)
  return security.reader_config_op_v1(p_action, coalesce(p_args, '{}'::jsonb), 'user:' || auth.uid()::text, v_rank);
end $function$;
comment on function public.admin_reader_configs_v1(text, jsonb) is 'CF-247 s1310: Layer 2/3 › Adapter builder › Reader configurations: read and change a provider''s AER and scholarship reader configurations (PIM Admin drafts and qualifies; Platform Admin activates, pauses, resumes and rolls back).';
revoke all on function public.admin_reader_configs_v1(text, jsonb) from public, anon;
grant execute on function public.admin_reader_configs_v1(text, jsonb) to authenticated;

create or replace function public.svc_reader_configs_v1(p_action text, p_args jsonb, p_by text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(btrim(p_by), '') = '' then raise exception 'INVALID_INPUT: who is acting (p_by)'; end if;
  -- the operations path acts with Platform Admin standing for drafts, qualification and activation under the existing authority; it never grants authority
  return security.reader_config_op_v1(p_action, coalesce(p_args, '{}'::jsonb), 'ops:' || left(p_by, 100), 6);
end $function$;
comment on function public.svc_reader_configs_v1(text, jsonb, text) is 'CF-247 s1310: the reader configuration writer for the reader-config-ops operations workflow (service role); the same checks and log as the screen; activation authority is never granted here.';
revoke all on function public.svc_reader_configs_v1(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_reader_configs_v1(text, jsonb, text) to service_role;

-- 6. negatives by class (anchored edits)
do $edit$
declare d text := pg_get_functiondef('security.reader_qualify_decide_v1(uuid)'::regprocedure);
        a text := 'count(*) filter (where e.value->>''role'' = ''negative'' and e.value->>''outcome'' <> ''guard_held'')';
begin
  if position(a in d) = 0 then raise exception 'anchor not found in reader_qualify_decide_v1'; end if;
  d := replace(d, a, 'count(*) filter (where e.value->>''role'' = ''negative'' and case when v.configuration->>''template'' = ''provider_settings''
                                     then e.value->>''outcome'' in (''deterministic_read'', ''guard_passed'') else e.value->>''outcome'' <> ''guard_held'' end)  -- s1310: a provider_settings negative must not be read into rows');
  execute d;
end $edit$;

do $edit$
declare d text := pg_get_functiondef('public.svc_reader_qualify_sch_record(uuid,bigint,jsonb)'::regprocedure);
        a1 text := 'v_hosts jsonb; v_code text;';
        a2 text := 'select count(*), count(*) filter (where e.value->>''outcome'' = ''items_gained'') into v_pos, v_gain from jsonb_each(v.validation_result->''samples'') e;';
        a3 text := 'where e.value->>''outcome'' <> ''not_read'') and v_gain > 0;';
        a4 text := '''samples_read'', v_pos, ''gained'', v_gain,';
begin
  if position(a1 in d) = 0 or position(a2 in d) = 0 or position(a3 in d) = 0 or position(a4 in d) = 0 then raise exception 'anchor not found in svc_reader_qualify_sch_record'; end if;
  d := replace(d, a1, 'v_hosts jsonb; v_code text; v_neg_bad int := 0;');
  d := replace(d, a2, 'select count(*) filter (where coalesce(e.value->>''role'', ''positive'') = ''positive''), count(*) filter (where coalesce(e.value->>''role'', ''positive'') = ''positive'' and e.value->>''outcome'' = ''items_gained''),
         count(*) filter (where e.value->>''role'' = ''negative'' and e.value->>''outcome'' = ''items_gained'')
    into v_pos, v_gain, v_neg_bad from jsonb_each(v.validation_result->''samples'') e;  -- s1310: a negative listing must not gain items');
  d := replace(d, a3, 'where e.value->>''outcome'' <> ''not_read'' and coalesce(e.value->>''role'', ''positive'') = ''positive'') and v_gain > 0 and v_neg_bad = 0;');
  d := replace(d, a4, '''samples_read'', v_pos, ''gained'', v_gain, ''negative_gained'', v_neg_bad,');
  execute d;
end $edit$;

-- 7. the lifecycle step runs the maintenance (anchored addition)
do $edit$
declare d text := pg_get_functiondef('security.reader_lifecycle_tick_v1()'::regprocedure);
        a text := '  return jsonb_build_object(''on'', true, ''reused_sources''';
begin
  if position(a in d) = 0 then raise exception 'anchor not found in reader_lifecycle_tick_v1'; end if;
  d := replace(d, a, '  perform security.reader_config_maintain_v1();  -- s1310: re-read after a provider_settings activation, requalification when due, a failed successor pauses
' || a);
  execute d;
end $edit$;

do $post$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1310_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1310_guard) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from catalogue.provider_entry_matrix where status = 'active') <> (select aer_active_before from s1310_guard) then raise exception 'post-check: an active entry row changed'; end if;
  if pg_get_functiondef('security.reader_lifecycle_tick_v1()'::regprocedure) !~ 'reader_config_maintain_v1'
     or pg_get_functiondef('security.reader_qualify_decide_v1(uuid)'::regprocedure) !~ 'provider_settings'
     or pg_get_functiondef('public.svc_reader_qualify_sch_record(uuid,bigint,jsonb)'::regprocedure) !~ 'v_neg_bad' then
    raise exception 'post-check: an anchored edit is not in place';
  end if;
  if has_function_privilege('anon', 'public.admin_reader_configs_v1(text,jsonb)', 'execute') or has_function_privilege('authenticated', 'public.svc_reader_configs_v1(text,jsonb,text)', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  -- the closed list holds: an unregistered key and an out-of-range value are refused
  begin perform security.reader_config_clean_v1('academic_entry', gen_random_uuid(), '{"template":"code"}'::jsonb); raise exception 'post-check: a template outside the list was accepted';
  exception when others then if sqlerrm like 'post-check%' then raise; end if; end;
end $post$;
