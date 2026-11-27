-- CF-247 s1304 (S2-Build; SS-Programme-Control 27 Nov 2026 11:27 AEDT, "Complete Autonomous PIM: Institute Reader Creation, Qualification and Execution"):
-- the s1303 reader lifecycle for scholarships, on the existing scholarship listing reader.
-- Read live 27 Nov 2026 (rolled back, read only): 1,712 active listing pages at 265 providers; 347 read with 0 items at 99 providers (33 of them with
-- no published scholarship); 310 of the 347 have a stored copy. Two kinds: pages that are not listings (FAQ, tips, application status, renewal, one
-- award's own page such as UPEI's display?awardid=…), and
-- listing pages whose awards the existing readers do not extract (for example a stated total of 278 with 0 items read).
-- What it adds (same store, knowledge and steps as s1303; no new table, job, queue or reader):
--   1. Detection of 0-item listing pages by class: not_a_listing (recorded once per page as HELD:NOT_A_LISTING for the scholarship owner) and
--      items_not_extracted.
--   2. A proposal per provider: a Layer 2 source profile (domain scholarship, reader:scholarship:<provider>:link_hosts:all), switched off, whose
--      configuration is data: hosts the listing links its awards to (a separate scholarships site or portal of the same provider).
--   3. Qualification on stored copies only: the worker runs the existing listing readers before and after adding the hosts the page links its awards
--      to (scholarship.ts listingCandidateHosts: at least two award links each); a pass needs more items on every positive sample.
--      A page that gains nothing is held as HELD:READER_RELEASE_REQUIRED (the awards are not where any existing reader looks).
--   4. Activation is its own step (security.reader_activate_sch_v1) and needs a standing authority the knowledge pattern records. Scholarship reader
--      configurations have none: the pattern ships with admin authority and not automatic, so a qualified configuration is HELD:ACTIVATION_AUTHORITY
--      until the Platform Admin grants it through the existing governed path (security.ops_learning_eligibility_set_v1). When active, the worker
--      adds its hosts to the provider's hosts for listing reads (svc_reader_config_sch_v1), and the existing listing record, candidates and
--      scholarship admission decide.
--   5. Knowledge and prevention as s1303 (security.ops_learning_record_v1, security.ops_learning_retry_check_v1).
--   6. s1303 correction found live after its release: the entry-matrix job (security.entry_matrix_fire_v1, job 337 every 5 minutes) calls the worker
--      only while entry-matrix work is due, so the lifecycle step and qualification samples never ran (0 entry_ai calls in 2 hours). The job now runs
--      the academic entry lifecycle step itself and counts queued qualification samples as due work (one anchored, md5-guarded edit).
-- G1: no job (the existing scholarship_listing call and job 337 run the steps). G2: the s1303 settings. G3: 75/48 checked. Locks and cron checked.
-- No spend. Nothing dropped or deleted.
-- Replaces: security.entry_matrix_fire_v1 (md5 68213bf4; two anchored additions).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

create temp table s1304_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if to_regprocedure('security.reader_lifecycle_tick_v1()') is null then raise exception 'pre-check: s1303 (20261130143000) is not applied'; end if;
  if md5(pg_get_functiondef('security.entry_matrix_fire_v1()'::regprocedure)) <> '68213bf48d54bd0a82db117c708cd2dd' then
    raise exception 'pre-check: security.entry_matrix_fire_v1 is not the definition this change was written against';
  end if;
end $pre$;

insert into pipeline.ops_remedy_knowledge (code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
  no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
values
  ('reader_config:sch_listing:link_hosts', 'scholarship', 'Scholarship listing whose awards link to another host of the same provider: the listing reader accepts that host',
   array['reader:scholarship:%:link_hosts:%'], 'listing_links_other_host', null,
   '{"signal": "listing page read with 0 items", "configuration": {"hosts_add": "hosts carrying at least two award links on the stored copy"}}'::jsonb,
   'admin', 'platform', 'the listing gives its award links and the existing candidates and scholarship admission take them',
   'the same listing copies already failed qualification: wait for a changed copy',
   'a provider whose listing links its awards to a separate scholarships site or portal; qualified on that provider''s stored copies',
   false, 'no standing authority switches scholarship reader configurations on automatically; the Platform Admin decides through security.ops_learning_eligibility_set_v1', now(), 'S2-Build s1304', 'CF-247 s1304'),
  ('reader_config:sch_listing:not_a_listing', 'scholarship', 'A page recorded as a scholarship listing that is not one (FAQ, tips, application status, renewal)',
   array['reader:scholarship:%:not_a_listing:%'], 'not_a_listing', null, '{"signal": "listing page read with 0 items whose address names a help or status page"}'::jsonb,
   'layer4_human', 'layer4_human', 'the scholarship owner sets the page inactive as a listing', 'recorded once per page and copy', 'never automatic',
   false, 'a page''s listing status is the scholarship owner''s decision', now(), 'S2-Build s1304', 'CF-247 s1304'),
  ('reader_config:sch_listing:items_not_extracted', 'scholarship', 'A scholarship listing whose awards no existing listing reader extracts, with or without added hosts',
   array['reader:scholarship:%:items_not_extracted:%'], 'items_not_extracted', null, '{"signal": "0 items before and after added hosts on the stored copy"}'::jsonb,
   'release', 'claude_engineering', 'a governed listing reader release reads the layout', 'held until the copy changes or a reader release', 'never automatic',
   false, 'no configuration of the existing listing readers extracts these awards', now(), 'S2-Build s1304', 'CF-247 s1304')
on conflict (code) do nothing;

create or replace function security.reader_sch_template_v1(p_url text, p_provider uuid)
returns text language sql stable security definer set search_path = '' as $function$
  select case when p_url ~* '(faq|/tips|tips-for|/status|app_status|application-status|renewal|how-to|/apply|scholarship-application|terms-and-conditions|technical-difficulties|contact)'
                or p_url ~* '([?&](award)?id=|/display\?|/award/[^/]+/?$|/scholarship/[^/]+/?$)'
                -- one award's own page under a listing the provider already has (Wintec …/scholarship-finder/<award>)
                or exists (select 1 from pipeline.scholarship_listing_pages l2 where l2.provider_id = p_provider and l2.active and l2.url <> p_url
                             and length(rtrim(l2.url, '/')) > 12 and p_url like rtrim(l2.url, '/') || '/%')
              then 'not_a_listing' else 'items_not_extracted' end
$function$;
revoke all on function security.reader_sch_template_v1(text, uuid) from public, anon, authenticated;
comment on function security.reader_sch_template_v1(text, uuid) is 'CF-247 s1304: the class of a scholarship listing page read with 0 items: a help, status or application page, or one award''s own page (not_a_listing), or a listing whose awards were not extracted.';

-- the provider's hosts as the listing reader takes them (scholarship discovery: allowed hosts and the site host)
create or replace function security.reader_sch_hosts_v1(p_provider uuid)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce((select to_jsonb(coalesce(d.allowed_hosts, '{}') || array[regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '')])
                     from pipeline.scholarship_discovery_providers d where d.provider_id = p_provider), '[]'::jsonb)
$function$;
revoke all on function security.reader_sch_hosts_v1(uuid) from public, anon, authenticated;

create or replace function security.reader_sch_propose_v1(p_provider uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_code text := 'reader_config:sch_listing:link_hosts'; v_key text := 'reader:scholarship:' || p_provider::text || ':link_hosts:all';
        v_max int := greatest(security.pipeline_num_v1('reader.qualify_samples_max', 8)::int, 2); v_samples jsonb; v_sig text; v_chk jsonb; v_src uuid; v_prof uuid; v_ver uuid; v_next int; v_cfg jsonb; v_n int := 0; r record;
begin
  -- pages that are not listings: one outcome each, for the scholarship owner
  for r in select l.id, l.url, coalesce(l.item_hash, l.read_at::text) sig from pipeline.scholarship_listing_pages l
            where l.provider_id = p_provider and l.active and l.status = 'read' and jsonb_array_length(l.items) = 0 and security.reader_sch_template_v1(l.url, l.provider_id) = 'not_a_listing'
              and not exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = 'reader_config:sch_listing:not_a_listing' and o.entity = 'listing:' || l.id and o.evidence_signature = coalesce(l.item_hash, l.read_at::text)) loop
    perform security.ops_learning_record_v1(jsonb_build_object('code', 'reader_config:sch_listing:not_a_listing', 'entity', 'listing:' || r.id, 'evidence_signature', r.sig,
      'performed_by', 'platform', 'success', false, 'stage_advanced', false, 'expected', 'the scholarship owner sets the page inactive as a listing',
      'observed', jsonb_build_object('url', left(r.url, 300), 'disposition', 'HELD:NOT_A_LISTING'), 'evidence', jsonb_build_object('source', 'security.reader_sch_propose_v1')));
    v_n := v_n + 1;
  end loop;
  -- listing pages whose awards were not extracted and that have a stored copy
  with c as (select l.id, l.url, (select e.storage_path from pipeline.evidence_artifacts e where e.source_url = l.url and e.storage_path is not null order by e.created_at desc limit 1) path,
                    coalesce(l.item_hash, l.read_at::text) h
               from pipeline.scholarship_listing_pages l
              where l.provider_id = p_provider and l.active and l.status = 'read' and jsonb_array_length(l.items) = 0 and security.reader_sch_template_v1(l.url, l.provider_id) = 'items_not_extracted')
  select md5(string_agg(c.id::text || ':' || c.h, ',' order by c.id)), jsonb_agg(jsonb_build_object('listing_id', c.id, 'role', 'positive', 'path', c.path) order by c.id)
    into v_sig, v_samples from (select * from c where c.path is not null order by c.id limit v_max) c;
  if v_samples is null then return jsonb_build_object('proposed', false, 'why', 'no listing page with a stored copy to qualify on', 'not_a_listing_recorded', v_n); end if;
  v_chk := security.ops_learning_retry_check_v1(v_code, 'provider:' || p_provider::text, v_sig);
  -- the pattern is not automatic, so the check names its authority; only a recorded failure on the same copies prevents a proposal
  if exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code in (v_code, 'reader_config:sch_listing:items_not_extracted') and o.entity = 'provider:' || p_provider::text and o.evidence_signature = v_sig and not o.success) then
    return jsonb_build_object('proposed', false, 'why', 'the same listing copies already failed', 'prevented', true, 'not_a_listing_recorded', v_n);
  end if;
  select s.id into v_src from pipeline.sources s where s.provider_id = p_provider order by (s.status = 'active') desc, s.trust_rank desc nulls last, s.created_at limit 1;
  if v_src is null then return jsonb_build_object('proposed', false, 'why', 'the provider has no source record to hold a profile'); end if;
  insert into pipeline.layer2_source_profiles (source_id, profile_key, domain, acquisition_method, target_entity_type, authority_class, enabled, paused, operational_owner)
  values (v_src, v_key, 'scholarship', 'other_deterministic', 'scholarship_listing', 'first_party', false, true, 'S2-Build reader lifecycle (s1304)')
  on conflict (profile_key) do update set updated_at = now() returning id into v_prof;
  if exists (select 1 from pipeline.layer2_source_profile_versions v where v.profile_id = v_prof and (v.validation_status = 'pending'
              or (v.validation_status = 'valid' and v.configuration->>'evidence_signature' = v_sig))) then
    return jsonb_build_object('proposed', false, 'why', 'already being qualified or qualified on these copies', 'not_a_listing_recorded', v_n);
  end if;
  v_cfg := jsonb_build_object('reader_config', 'reader-config-v1', 'domain', 'scholarship', 'template', 'link_hosts', 'provider_id', p_provider, 'hosts_add', '[]'::jsonb,
             'samples', v_samples, 'evidence_signature', v_sig, 'proposed_at', now(), 'proposed_by', 'security.reader_sch_propose_v1');
  select coalesce(max(version_no), 0) + 1 into v_next from pipeline.layer2_source_profile_versions where profile_id = v_prof;
  insert into pipeline.layer2_source_profile_versions (profile_id, version_no, configuration, configuration_hash, validation_status, validation_result, change_control_ref)
  values (v_prof, v_next, v_cfg, md5(v_cfg::text), 'pending',
          jsonb_build_object('samples', (select jsonb_object_agg(e->>'listing_id', jsonb_build_object('state', 'queued', 'role', 'positive', 'path', e->>'path')) from jsonb_array_elements(v_samples) e)), 'CF-247 s1304')
  returning id into v_ver;
  update pipeline.layer2_source_profiles set current_version_id = case when enabled then current_version_id else v_ver end, updated_at = now() where id = v_prof;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reader_lifecycle', 'proposed', 'pipeline.layer2_source_profile_versions', jsonb_build_object('version', v_ver, 'profile_key', v_key, 'template', 'link_hosts', 'samples', jsonb_array_length(v_samples)), null);
  return jsonb_build_object('proposed', true, 'version', v_ver, 'samples', jsonb_array_length(v_samples), 'not_a_listing_recorded', v_n);
end $function$;
comment on function security.reader_sch_propose_v1(uuid) is 'CF-247 s1304: records 0-item pages that are not listings for the scholarship owner, and proposes one provider''s scholarship listing reader configuration (added link hosts) with its stored-copy samples; never again on the same copies after a failure.';
revoke all on function security.reader_sch_propose_v1(uuid) from public, anon, authenticated;

create or replace function security.reader_activate_sch_v1(p_version uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v pipeline.layer2_source_profile_versions%rowtype; k pipeline.ops_remedy_knowledge%rowtype;
begin
  select * into v from pipeline.layer2_source_profile_versions where id = p_version for update;
  if v.id is null or v.validation_status <> 'valid' or v.validation_result ? 'activated_at' then return jsonb_build_object('activated', false, 'why', 'not a qualified version awaiting activation'); end if;
  select * into k from pipeline.ops_remedy_knowledge where code = 'reader_config:sch_listing:link_hosts';
  if k.code is null or not k.auto_eligible then
    if not (v.validation_result ? 'held') then
      update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('held', 'HELD:ACTIVATION_AUTHORITY', 'held_at', now()) where id = v.id;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('reader_lifecycle', 'held_activation_authority', 'pipeline.layer2_source_profile_versions', jsonb_build_object('version', v.id, 'hosts_add', v.configuration->'hosts_add', 'why', k.eligibility_reason), null);
    end if;
    return jsonb_build_object('activated', false, 'why', 'HELD:ACTIVATION_AUTHORITY');
  end if;
  update pipeline.layer2_source_profile_versions set validation_status = 'superseded' where profile_id = v.profile_id and id <> v.id and validation_status = 'valid';
  update pipeline.layer2_source_profiles set current_version_id = v.id, enabled = true, paused = false, updated_at = now() where id = v.profile_id;
  update pipeline.layer2_source_profile_versions set validation_result = validation_result || jsonb_build_object('activated_at', now(), 'authority', k.eligibility_reason) where id = v.id;
  -- the provider's 0-item listing pages are read again at the next listing run
  update pipeline.scholarship_listing_pages l set next_read_at = now()
   where l.provider_id = (v.configuration->>'provider_id')::uuid and l.active and l.status = 'read' and jsonb_array_length(l.items) = 0;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reader_lifecycle', 'activated', 'pipeline.layer2_source_profiles', jsonb_build_object('profile', v.profile_id, 'version', v.id, 'hosts_add', v.configuration->'hosts_add', 'authority', k.eligibility_reason), null);
  return jsonb_build_object('activated', true);
end $function$;
comment on function security.reader_activate_sch_v1(uuid) is 'CF-247 s1304: switches a qualified scholarship listing reader configuration on as its own audited step, only when its knowledge pattern is automatic under a recorded decision (otherwise HELD:ACTIVATION_AUTHORITY), and has the provider''s 0-item listings read again.';
revoke all on function security.reader_activate_sch_v1(uuid) from public, anon, authenticated;

create or replace function security.reader_sch_tick_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_max int := greatest(security.pipeline_num_v1('reader.proposals_per_tick', 2)::int, 1); r record; v_p jsonb; v_out jsonb := '[]'; v_n int := 0; v_act jsonb := '[]';
begin
  if security.pipeline_num_v1('reader.lifecycle_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in select v.id ver from pipeline.layer2_source_profile_versions v join pipeline.layer2_source_profiles p on p.id = v.profile_id
            where p.profile_key like 'reader:scholarship:%' and v.validation_status = 'valid' and not (v.validation_result ? 'activated_at') and not (v.validation_result ? 'held')
            limit 5 loop  -- fixed: activations per run
    v_act := v_act || jsonb_build_array(security.reader_activate_sch_v1(r.ver) || jsonb_build_object('version', r.ver));
  end loop;
  for r in select l.provider_id, count(*) n from pipeline.scholarship_listing_pages l
            where l.active and l.status = 'read' and jsonb_array_length(l.items) = 0
              and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = l.provider_id)
              and not exists (select 1 from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.profile_id = p.id
                               where p.profile_key = 'reader:scholarship:' || l.provider_id::text || ':link_hosts:all' and (v.validation_status = 'pending' or (v.validation_status = 'valid' and p.enabled)))
            group by 1 order by count(*) desc limit 50 loop  -- fixed: candidate providers considered per run
    exit when v_n >= v_max;
    v_p := security.reader_sch_propose_v1(r.provider_id);
    if coalesce((v_p->>'proposed')::boolean, false) then v_n := v_n + 1; end if;  -- a not-a-listing record is cheap and does not use a proposal slot
    if coalesce((v_p->>'proposed')::boolean, false) or coalesce((v_p->>'not_a_listing_recorded')::int, 0) > 0 then
      v_out := v_out || jsonb_build_array(jsonb_build_object('provider', r.provider_id, 'pages', r.n) || v_p); end if;
  end loop;
  return jsonb_build_object('on', true, 'activations', v_act, 'proposals', v_out);
end $function$;
comment on function security.reader_sch_tick_v1() is 'CF-247 s1304: the scholarship reader lifecycle step, run from the existing listing read: activation of qualified configurations (as its own step) and bounded detection and proposals.';
revoke all on function security.reader_sch_tick_v1() from public, anon, authenticated;

create or replace function public.svc_reader_qualify_sch_next(p_limit integer default 3)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tick jsonb; v jsonb := '[]'; r record; v_lim int := greatest(1, least(coalesce(p_limit, 3), 10));  -- fixed: upper bound of one call
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('reader.lifecycle_on', 0) < 1 then return '[]'::jsonb; end if;
  v_tick := security.reader_sch_tick_v1();
  for r in select v.id ver, v.configuration cfg, e.key listing_id, e.value->>'path' path from pipeline.layer2_source_profile_versions v
             join pipeline.layer2_source_profiles p on p.id = v.profile_id, jsonb_each(v.validation_result->'samples') e
            where v.validation_status = 'pending' and p.profile_key like 'reader:scholarship:%'
              and (e.value->>'state' = 'queued' or (e.value->>'state' = 'leased' and (e.value->>'leased_until')::timestamptz < now()))
            order by v.created_at, e.key limit v_lim for update of v skip locked loop
    update pipeline.layer2_source_profile_versions
       set validation_result = jsonb_set(validation_result, array['samples', r.listing_id], (validation_result->'samples'->r.listing_id) || jsonb_build_object('state', 'leased', 'leased_until', now() + interval '5 minutes'))  -- fixed: lease timer
     where id = r.ver;
    v := v || (select jsonb_build_array(jsonb_build_object('qualify_version_id', r.ver, 'listing_id', l.id, 'provider_id', l.provider_id, 'url', l.url, 'storage_path', r.path,
               'hosts', security.reader_sch_hosts_v1(l.provider_id), 'config', r.cfg - 'samples'))
                 from pipeline.scholarship_listing_pages l where l.id = r.listing_id::bigint);
  end loop;
  return v;
end $function$;
comment on function public.svc_reader_qualify_sch_next(integer) is 'CF-247 s1304: runs the scholarship reader lifecycle step, then leases stored-copy samples of proposed listing reader configurations for the worker.';
revoke all on function public.svc_reader_qualify_sch_next(integer) from public, anon, authenticated;
grant execute on function public.svc_reader_qualify_sch_next(integer) to service_role;

create or replace function public.svc_reader_qualify_sch_record(p_version uuid, p_listing bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v pipeline.layer2_source_profile_versions%rowtype; v_out text; v_pos int; v_gain int; v_pass boolean; v_hosts jsonb; v_code text;
        v_min int := greatest(security.pipeline_num_v1('reader.qualify_min_positive', 2)::int, 1);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  v_out := case when p_result ? 'error' then 'not_read'
                when coalesce((p_result->>'items_after')::int, 0) > coalesce((p_result->>'items_before')::int, 0) then 'items_gained'
                else 'no_gain' end;
  update pipeline.layer2_source_profile_versions
     set validation_result = jsonb_set(validation_result, array['samples', p_listing::text], (validation_result->'samples'->p_listing::text)
           || jsonb_build_object('state', 'done', 'outcome', v_out, 'result', p_result, 'read_at', now()))
   where id = p_version and validation_status = 'pending' and validation_result->'samples' ? p_listing::text
   returning * into v;
  if v.id is null or exists (select 1 from jsonb_each(v.validation_result->'samples') e where e.value->>'state' <> 'done') then return jsonb_build_object('status', v_out); end if;
  select count(*), count(*) filter (where e.value->>'outcome' = 'items_gained') into v_pos, v_gain from jsonb_each(v.validation_result->'samples') e;
  select coalesce(jsonb_agg(distinct h), '[]'::jsonb) into v_hosts from jsonb_each(v.validation_result->'samples') e, jsonb_array_elements_text(coalesce(e.value#>'{result,hosts_added}', '[]'::jsonb)) h
   where e.value->>'outcome' = 'items_gained';
  v_pass := v_gain >= least(v_min, v_pos) and v_gain = (select count(*) from jsonb_each(v.validation_result->'samples') e where e.value->>'outcome' <> 'not_read') and v_gain > 0;
  v_code := case when v_pass then 'reader_config:sch_listing:link_hosts' else 'reader_config:sch_listing:items_not_extracted' end;
  update pipeline.layer2_source_profile_versions
     set validation_status = case when v_pass then 'valid' else 'invalid' end,
         configuration = case when v_pass then configuration || jsonb_build_object('hosts_add', v_hosts) else configuration end,
         validation_result = validation_result || jsonb_build_object('decided_at', now(), 'passed', v_pass, 'samples_read', v_pos, 'gained', v_gain, 'hosts_add', v_hosts,
           'disposition', case when v_pass then 'qualified' else 'HELD:READER_RELEASE_REQUIRED' end,
           'rule', 'pass when every sample read gains items with the added hosts (at least least(min_positive, samples)); a pass switches nothing on')
   where id = v.id;
  perform security.ops_learning_record_v1(jsonb_build_object('code', v_code, 'entity', 'provider:' || (v.configuration->>'provider_id'), 'evidence_signature', v.configuration->>'evidence_signature',
    'performed_by', 'platform', 'success', v_pass, 'stage_advanced', v_pass, 'expected', 'qualified on stored listing copies',
    'observed', jsonb_build_object('samples', v_pos, 'gained', v_gain, 'hosts_add', v_hosts), 'evidence', jsonb_build_object('source', 'public.svc_reader_qualify_sch_record', 'version', v.id)));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reader_lifecycle', case when v_pass then 'qualified' else 'qualification_failed' end, 'pipeline.layer2_source_profile_versions', jsonb_build_object('version', v.id, 'gained', v_gain, 'samples', v_pos, 'hosts_add', v_hosts), null);
  return jsonb_build_object('status', v_out, 'decided', true, 'passed', v_pass);
end $function$;
comment on function public.svc_reader_qualify_sch_record(uuid, bigint, jsonb) is 'CF-247 s1304: records one stored-copy sample read of a proposed scholarship listing configuration and decides the version when every sample is read (valid with the hosts that gained items, or HELD:READER_RELEASE_REQUIRED).';
revoke all on function public.svc_reader_qualify_sch_record(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.svc_reader_qualify_sch_record(uuid, bigint, jsonb) to service_role;

create or replace function public.svc_reader_config_sch_v1(p_providers uuid[])
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_object_agg(v.configuration->>'provider_id', v.configuration->'hosts_add')
                     from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id = p.current_version_id
                    where p.profile_key like 'reader:scholarship:%:link_hosts:all' and p.enabled and not p.paused and v.validation_status = 'valid'
                      and (v.configuration->>'provider_id')::uuid = any(p_providers)), '{}'::jsonb);
end $function$;
comment on function public.svc_reader_config_sch_v1(uuid[]) is 'CF-247 s1304: the qualified hosts of each provider''s active scholarship listing reader configuration, for the worker''s listing read.';
revoke all on function public.svc_reader_config_sch_v1(uuid[]) from public, anon, authenticated;
grant execute on function public.svc_reader_config_sch_v1(uuid[]) to service_role;

-- s1303 correction: the entry-matrix job runs the academic entry lifecycle step and counts queued qualification samples as due work
do $edit$
declare d text := pg_get_functiondef('security.entry_matrix_fire_v1()'::regprocedure);
        a1 text := '  v_q := security.entry_matrix_enqueue_v1();';
        a2 text := 'and security.entry_matrix_enabled_v1(s.provider_id));';
begin
  if position(a1 in d) = 0 or position(a2 in d) = 0 then raise exception 'anchor not found in entry_matrix_fire_v1'; end if;
  d := replace(d, a1, a1 || '
  perform security.reader_lifecycle_tick_v1();  -- s1304: the reader lifecycle step (detection, reuse, activation, outcomes) on every run');
  d := replace(d, a2, a2 || '
  -- s1304: queued sample pages of proposed reader configurations are due work for the worker (svc_reader_qualify_next)
  v_due := v_due + (select count(*) from pipeline.layer2_source_profile_versions qv join pipeline.layer2_source_profiles qp on qp.id = qv.profile_id, jsonb_each(qv.validation_result->''samples'') qe
                     where qv.validation_status = ''pending'' and qp.profile_key like ''reader:academic_entry:%'' and qe.value->>''state'' in (''queued'', ''leased''));');
  execute d;
end $edit$;

do $post$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1304_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1304_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('authenticated', 'public.svc_reader_qualify_sch_next(integer)', 'execute') or has_function_privilege('anon', 'public.svc_reader_config_sch_v1(uuid[])', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  if pg_get_functiondef('security.entry_matrix_fire_v1()'::regprocedure) !~ 'reader_lifecycle_tick_v1' then raise exception 'post-check: the entry-matrix job does not run the lifecycle step'; end if;
  if security.reader_sch_template_v1('https://x/scholarships/post_faq/having-technical-difficulties/', null) <> 'not_a_listing'
     or security.reader_sch_template_v1('https://www.upei.ca/scholarships-and-awards/display?awardid=1147', null) <> 'not_a_listing'
     or security.reader_sch_template_v1('https://x/study/fees-scholarships/scholarships', null) <> 'items_not_extracted' then
    raise exception 'post-check: the listing classes are not read as designed';
  end if;
end $post$;
