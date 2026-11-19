CREATE OR REPLACE FUNCTION security.provider_description_machine_admit_v1(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; v_read pipeline.provider_description_reads%rowtype; v_tier text; v_text text; v_gate jsonb; v_check jsonb; v_prof jsonb; v_now text; v_pub jsonb; v_shown text; v_key text;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account that records Decision 263 rule decisions
        v_rule constant text := 'pdesc-machine-v1'; v_ref text := 'CF-247 F-PDESC; Platform Admin decision 9 Nov 2026 (source-verified machine admission, tiers 1 to 4)'; v_dec uuid; v_facts jsonb := '[]'::jsonb; v_codes jsonb := '[]'::jsonb;
        v_url text; v_hash text; v_reason text; v_decline text; v_basic jsonb; v_upg boolean := false;
        v_sent jsonb; v_sub jsonb; v_subinfo jsonb; v_try jsonb; v_gate2 jsonb; v_text0 text; -- sentence-subset recovery
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off'); end if;
  select * into i from pipeline.layer4_review_items where id = p_item_id for update;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' or i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'not_a_waiting_provider_description'); end if;
  select * into v_read from pipeline.provider_description_reads r where r.review_item_id = i.id and r.state = 'proposed' for update;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  v_sent := coalesce(i.proposed_value->'sentences', '[]'::jsonb); -- the sentences the description is made of (the proposal itself is never changed)
  v_tier := coalesce(nullif(v_read.checks->>'tier', ''), v_read.read_via, i.proposed_value->>'tier');
  v_decline := null;
  -- upgrade of a register-fact profile (pdesc.registry_upgrade_on): the item's before text is the profile the provider holds now and the proposal comes from a source tier
  v_basic := security.provider_description_basic_profile_v1(i.entity_id);
  v_upg := v_basic is not null and v_tier in ('stored', 'direct', 'firecrawl') and btrim(coalesce(i.before_value->>'description', '')) = btrim(v_basic->>'text');
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
    v_gate := security.provider_description_machine_gate_v1(i.entity_id, v_text, jsonb_build_object('tier', v_tier, 'codes', v_codes, 'sentences', case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end));
    if not (v_gate->>'ok')::boolean then v_decline := v_gate->>'rule'; v_reason := v_gate->>'reason'; end if;
  end if;
  -- Sentence-subset recovery (CF-247 F-PDESC, Platform Admin 10 Nov 2026): a reading from an official page that the text rule declined (a word or a figure, or page markup) is not parked for a person when the refusal sits in only some of its sentences.
  -- Exactly those sentences are left out (never reworded, never added to), and the SAME validation (host, About page, sentence range, character range, quote on the page for every sentence, age, duplicate guard), the SAME machine gate (lock, rejection memory,
  -- withdrawal, identity finding, name, full text check) and, for a reading without an identity snapshot, the name in a quote, are run again on what is left. The identity, host, evidence and snapshot proofs above do not depend on the sentences.
  -- If anything fails the reading stays declined exactly as before, and the ledger row says what was tried. The decision row, the ledger row and the item's layer2_state keep the original proposal (every sentence, the sentences left out and why); once admitted, the read's proposal and the item's proposed_value hold the kept description the catalogue holds, so the read-back lineage finds it.
  if v_decline in ('machine_text_refused_word', 'machine_text_figure', 'machine_text_entity_encoded') and v_tier in ('stored', 'direct', 'firecrawl') then -- fixed: the three refusals of the text rule that leaving a sentence out can remove
    v_sub := security.provider_description_subset_v1(i.entity_id, v_sent);
    v_try := jsonb_build_object('refusal', v_decline, 'reason', v_reason, 'dropped', coalesce(v_sub->'dropped', '[]'::jsonb), 'kept_sentences', jsonb_array_length(coalesce(v_sub->'kept', '[]'::jsonb)), 'given_sentences', jsonb_array_length(v_sent), 'at', now());
    if jsonb_array_length(coalesce(v_sub->'kept', '[]'::jsonb)) = 0 then v_try := v_try || jsonb_build_object('result', 'every_sentence_refused');
    elsif jsonb_array_length(coalesce(v_sub->'dropped', '[]'::jsonb)) = 0 then v_try := v_try || jsonb_build_object('result', 'no_sentence_to_leave_out');
    elsif v_read.checks->'identity_snapshot' is null and not exists (select 1 from catalogue.providers p cross join lateral jsonb_array_elements(v_sub->'kept') sentence
           where p.id = i.entity_id and exists (select 1 from unnest(array[p.canonical_name, p.display_name]) nm where nullif(btrim(nm), '') is not null
             and position(regexp_replace(lower(nm), '[^a-z0-9]+', '', 'g') in regexp_replace(lower(sentence->>'quote'), '[^a-z0-9]+', '', 'g')) > 0)) then
      v_try := v_try || jsonb_build_object('result', 'name_not_in_remaining_quotes');
    else
      v_check := security.provider_description_validate_v1(i.entity_id, v_read.source_url, v_read.source_captured_at, jsonb_build_object('about_page', true, 'sentences', v_sub->'kept'));
      if coalesce(v_check->>'outcome', '') not in ('propose', 'verified') or nullif(v_check->>'text', '') is null then
        v_try := v_try || jsonb_build_object('result', 'remainder_validation_' || coalesce(v_check->>'rule', 'changed'), 'remainder_reason', v_check->>'reason');
      else
        v_gate2 := security.provider_description_machine_gate_v1(i.entity_id, v_check->>'text', jsonb_build_object('tier', v_tier, 'codes', v_codes, 'sentences', v_sub->'kept'));
        if not coalesce((v_gate2->>'ok')::boolean, false) then
          v_try := v_try || jsonb_build_object('result', 'remainder_' || coalesce(v_gate2->>'rule', 'not_ok'), 'remainder_reason', v_gate2->>'reason');
        else
          v_text0 := v_text;
          v_subinfo := jsonb_build_object('refusal', v_decline, 'refusal_reason', v_reason, 'dropped', v_sub->'dropped', 'kept_sentences', jsonb_array_length(v_sub->'kept'), 'given_sentences', jsonb_array_length(v_sent),
                         'original_text_chars', length(v_text0), 'original_text_md5', md5(v_text0), 'original_text', v_text0, 'original_sentences', v_sent, 'original_read_id', v_read.id, 'original_evidence_id', i.evidence_id, 'source_url', v_read.source_url, 'source_hash', v_read.content_hash, 'review_item_id', i.id);
          v_sent := v_sub->'kept'; v_text := v_check->>'text'; v_gate := v_gate2; v_decline := null; v_reason := null;
          v_facts := coalesce((select jsonb_agg(jsonb_build_object('sentence', s->>'text', 'quote', s->>'quote', 'source_url', v_read.source_url, 'source_hash', v_read.content_hash, 'evidence_id', v_read.evidence_id,
                    'captured_at', v_read.source_captured_at, 'model', v_read.model, 'prompt_version', v_read.prompt_version, 'worker', v_read.worker)) from jsonb_array_elements(v_sent) s), '[]'::jsonb);
          v_try := v_try || jsonb_build_object('result', 'adopted');
        end if;
      end if;
    end if;
  end if;
  if v_decline is null and v_upg and (jsonb_array_length(v_sent) < security.pipeline_num_v1('pdesc.min_sentences', 2) or v_text = btrim(v_basic->>'text')) then v_decline := 'upgrade_too_short_or_unchanged'; end if;
  if v_decline is null and not v_upg and i.before_value->>'description' is not null and nullif(btrim(i.before_value->>'description'), '') is not null then v_decline := 'before_value_not_empty'; end if;
  if v_decline is null then
    select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
    if v_now is not null and not (v_upg and v_now = btrim(v_basic->>'text')) then v_decline := 'description_already_held'; end if;
  end if;
  if v_decline is not null then
    v_reason := coalesce(v_reason, 'The automatic rule did not admit this description (' || v_decline || '); a person decides in Layer 4.');
    insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, evidence_id, source_url, source_hash, facts, checks, actor)
    values (i.entity_id, i.id, v_read.id, case when v_tier in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_tier else 'stored' end, v_rule, 'declined', v_reason, i.evidence_id, v_read.source_url, v_read.content_hash, v_facts,
            case when v_try is not null then jsonb_build_object('subset_recovery', v_try) else '{}'::jsonb end, v_sys)
    on conflict (review_item_id) where outcome = 'declined' do update set reason = excluded.reason, tier = excluded.tier, facts = excluded.facts, created_at = now(),
            checks = (coalesce(pipeline.provider_description_machine_admissions.checks, '{}'::jsonb) - 'subset_recovery') || excluded.checks;
    update pipeline.layer4_review_items set escalation_reason = left('Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule [^.]*\. ', ''), 1000) -- fixed: the item's reason column shows its first 1000 characters
     where id = i.id and coalesce(escalation_reason, '') not like 'Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '.%';
    return jsonb_build_object('ok', false, 'rule', v_decline, 'reason', v_reason);
  end if;
  -- write the one description, settle the item as a machine decision, record everything
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- proved on the row: a guard that put the old text back must stop the admission, not leave an audit that says it was published
  if (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = i.entity_id) is distinct from v_text then raise exception 'description_not_written: the catalogue kept the earlier text'; end if;
  -- a recovered reading: the item and the read hold the description the catalogue now holds (the kept sentences), so the approved-lineage test of the Website and Zoho read-back, the run result and the selection find it; the original proposal (every sentence, the sentences left out and why) stays in the decision row (proposed_value), the ledger row and layer2_state.subset_of_reading
  update pipeline.layer4_review_items set status = 'approved', decided_at = now(),
         proposed_value = case when v_subinfo is not null then proposed_value || jsonb_build_object('description', v_text, 'sentences', v_sent) else proposed_value end,
         layer2_state = case when v_subinfo is not null then coalesce(layer2_state, '{}'::jsonb) || jsonb_build_object('subset_of_reading', v_subinfo) else layer2_state end
   where id = i.id and status = 'pending';
  v_reason := format('Auto (%s, tier %s): %s. Not a person''s decision.', v_rule, v_tier,
                     case when v_tier = 'registry_factual' then 'built only from the verified register listing, provider record and active catalogue courses; every sentence tied to its facts'
                          else 'official page ' || coalesce(v_url, '') || ' (hash ' || left(coalesce(v_hash, ''), 12) || '); identity, evidence lineage and every sentence''s quote proved again at admission' end); -- fixed: a short hash prefix is shown for reading, the full hash is stored
  if v_subinfo is not null then
    v_reason := v_reason || format(' Sentence subset of the reading: %s of %s sentences kept, %s left out because the automatic text rule refused them; nothing was reworded or added.', v_subinfo->>'kept_sentences', v_subinfo->>'given_sentences', jsonb_array_length(v_subinfo->'dropped'));
  end if;
  insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value,
          case when v_subinfo is not null then i.proposed_value || jsonb_build_object('description', v_text, 'sentences', v_sent, 'subset_of_reading', v_subinfo) else i.proposed_value end, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') || case when v_subinfo is not null then jsonb_build_object('subset_of_reading', true) else '{}'::jsonb end, coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', i.id::text, jsonb_build_object('kind', 'provider_description', 'ref', i.id::text, 'choice', 'approve', 'reason', v_reason, 'provider_id', i.entity_id, 'auto', true,
          'machine_rule', v_rule, 'tier', v_tier, 'decision_id', v_dec, 'field_code', i.field_code, 'subset_of_reading', v_subinfo is not null), v_sys);
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin v_pub := public.website_v2_provider(v_key); v_shown := v_pub->'item'->>'description'; exception when others then v_shown := null; end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(), published_at = case when v_shown = v_text then now() end, updated_at = now(),
         proposal = case when v_subinfo is not null then coalesce(proposal, '{}'::jsonb) || jsonb_build_object('description', v_text, 'sentences', v_sent) else proposal end,
         checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') || case when v_subinfo is not null then jsonb_build_object('subset_of_reading', v_subinfo) else '{}'::jsonb end where id = v_read.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now() where provider_id = i.entity_id and state = 'admitted' and id <> v_read.id;
  insert into pipeline.search_refresh_signals (entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', i.entity_id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
  if v_upg then
    -- the profile admission is closed, never deleted: its text stays as the earlier version (one live admission a provider)
    update pipeline.provider_description_machine_admissions set withdrawn_at = now(), withdrawn_by = v_sys,
           withdrawn_reason = 'Upgraded to a source-verified description from ' || coalesce(v_url, 'the official page') || '; the register-fact profile is kept in this row.'
     where id = (v_basic->>'admission_id')::uuid and outcome = 'admitted' and withdrawn_at is null;
  end if;
  insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, before_description, after_description, evidence_id, source_url, source_hash, facts, checks, actor)
  values (i.entity_id, i.id, v_read.id, v_tier, v_rule, 'admitted', case when v_subinfo is not null then 'subset_of_reading: ' else '' end || v_reason || case when v_upg then ' Upgrade of the register-fact profile, which is kept as the earlier version.' else '' end, case when v_upg then v_basic->>'text' end, v_text, i.evidence_id, v_url, v_hash, v_facts,
          jsonb_build_object('decision_id', v_dec, 'published', v_shown = v_text, 'validation', coalesce(v_check->'checks', v_prof->'facts'),
          'neutral_words', to_jsonb(security.pdesc_machine_neutral_supported_v1(v_text, case when v_tier = 'registry_factual' then '[]'::jsonb else v_sent end)))
          || case when v_subinfo is not null then jsonb_build_object('subset_of_reading', v_subinfo) else '{}'::jsonb end, v_sys);
  if v_upg then
    update pipeline.provider_description_machine_admissions set checks = checks || jsonb_build_object('upgrade', jsonb_build_object('from_tier', 'registry_factual', 'prior_admission_id', v_basic->'admission_id', 'prior_read_id', v_basic->'read_id',
           'source_url', v_url, 'source_hash', v_hash, 'evidence_id', i.evidence_id, 'sentences', jsonb_array_length(v_sent)))
     where review_item_id = i.id and outcome = 'admitted';
  end if;
  return jsonb_build_object('ok', true, 'provider_id', i.entity_id, 'tier', v_tier, 'rule', v_rule, 'decision_id', v_dec, 'description_chars', length(v_text), 'published', v_shown = v_text, 'subset_of_reading', v_subinfo is not null);
end $function$
