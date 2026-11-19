CREATE OR REPLACE FUNCTION security.provider_description_registry_tier_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_prof jsonb; v_gate jsonb; v_read uuid; v_item uuid; v_res jsonb; v_ok int := 0; v_held int := 0; v_err int := 0; v_msg text; v_rule text; v_fp text := security.pdesc_text_rule_fingerprint_v1();
        v_rules jsonb := coalesce(security.toolset_setting('pipeline', 'pdesc.registry_after_rules'), '[]'::jsonb); v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account (Decision 263)
begin
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 or security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 or security.pipeline_num_v1('pdesc.registry_factual_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in
    with act as (select pz.country_id, count(*) n from pipeline.provider_description_machine_admissions z join catalogue.providers pz on pz.id = z.provider_id
                  where z.created_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id)
    select p.id from catalogue.providers p left join act on act.country_id = p.country_id
      left join lateral (select x.state, x.rule, x.updated_at, x.checks from pipeline.provider_description_reads x where x.provider_id = p.id order by x.created_at desc, x.id desc limit 1) lr on true
     where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null and security.provider_description_scope_v1(p.id)
       and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = p.id and o.state in ('queued', 'reading', 'proposed'))
       and not exists (select 1 from pipeline.provider_description_reads h where h.provider_id = p.id and h.state = 'held' and h.checks->>'tier' = 'registry_factual' and coalesce(case when (h.checks->>'facts_needed') ~ '^[0-9]+$' then (h.checks->>'facts_needed')::numeric end, 0) <= security.pipeline_num_v1('pdesc.registry_min_facts', 3) and not (h.rule like 'machine_declined_machine_text%' and h.checks->>'text_rule' is distinct from v_fp) and h.updated_at > now() - make_interval(days => security.pipeline_num_v1('pdesc.recheck_days', 180)::int))
       and ((lr.state = 'held' and (v_rules ? lr.rule or (lr.rule like 'machine_declined_machine_text%' and lr.checks->>'tier' = 'registry_factual' and lr.checks->>'text_rule' is distinct from v_fp) or (lr.rule = 'insufficient_verified_facts' and lr.checks->>'tier' = 'registry_factual' and (lr.checks->>'facts_needed') ~ '^[0-9]+$' and (lr.checks->>'facts_needed')::numeric > security.pipeline_num_v1('pdesc.registry_min_facts', 3)))) or lr.state = 'dead_letter'
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
        values (r.id, 'held', 'machine_declined_' || (v_gate->>'rule'), left(v_gate->>'reason', 400), 'registry-factual-v1', 'registry-profile-v1', jsonb_build_object('tier', 'registry_factual', 'tier_hold', true, 'text_rule', v_fp), 0); -- fixed: display width of the stored reason text
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
                jsonb_build_object('tier', 'registry_factual', 'tier_hold', true, 'text_rule', v_fp), 0);
      exception when others then null;
      end;
      v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('on', true, 'admitted', v_ok, 'held', v_held, 'errors', v_err);
end $function$
