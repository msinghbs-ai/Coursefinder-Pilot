-- CF-247 F-PDESC delivery (Platform Admin decision 10 Nov 2026 19:47, F-PDESC.01 to .05): a provider-description reading that the automatic text rule declined for only SOME of its sentences is recovered by leaving those sentences out, never by re-reading, rewording or adding.
--
-- Production fact (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026 09:04 UTC): 22 provider-description Layer 4 items are pending; the latest ledger row of 19 is a decline by security.provider_description_machine_gate_v1 for a word or a figure the automatic text rule does not admit
--   (refused_word 14 (campus 4, accredited 3, unique 2, excellence 2, others 3), figure 4, validation 2 (a page that is not an About page, one of them with a stale refused_word reason), and others). Every sentence of those readings has an exact on-page quote. The rule looks at the text as a whole, so ONE offending
--   sentence declines a reading whose other sentences are clean: the field example is Monash University (item 2f74870f-b34a-417d-a2c9-4b45166d620c, read from https://www.monash.edu/about): sentence 2 ("... began in 1961 ... a single campus with fewer than 400 students ...") trips the word list ("campus") and the figures rule;
--   sentences 1 and 3 alone pass security.pdesc_machine_text_check_v1 (null) and the whole validation. Measured with the live functions, read only: 12 of the 22 readings have a remainder that passes the whole validation and the whole machine gate.
--
-- What this changes (no new setting, table, column, job or consumer object; word lists, thresholds and settings are NOT changed):
--   1 security.provider_description_subset_v1(provider, sentences) NEW (read only, security definer, search path empty, not granted to anon or authenticated): for each sentence it asks the SAME machine text check (security.pdesc_machine_text_check_ctx_v1, the sentence alone with its own quote)
--     and returns the sentences that pass (kept, in order) and the sentences the rule refuses (dropped: index, text, quote, exact code such as refused_word:campus or figure:400). It never rewords, merges or adds a word.
--   2 security.provider_description_machine_admit_v1(item): when the gate declines a source-tier reading (stored, direct, firecrawl) with machine_text_refused_word, machine_text_figure or machine_text_entity_encoded, the function takes the kept sentences and runs the SAME checks again on them: the validation
--     (host, About page, pdesc.min_sentences, pdesc.max_sentences, pdesc.min_chars, pdesc.max_chars, the sentence rules, the quote on the page for every sentence, the source age, the duplicate and near-duplicate guard), the machine gate (switch, provider live, scope, manual lock, description held,
--     rejection memory, withdrawal, open identity finding, usable name, and the full text check) and, for a reading without an identity snapshot, the provider name in a kept quote. The identity, host, evidence-lineage and snapshot proofs of the reading do not depend on its sentences and were already passed.
--     If the remainder passes everything it is admitted through the existing admission below under the existing machine actor and rule (pdesc-machine-v1): the description written is exactly the kept sentences. A reading whose refusal is not removable by dropping sentences (identity, host, name, lock, rejection,
--     duplicate, a remainder below the minimums or with no sentence left) stays exactly as before: declined, in Layer 4. The ledger row of the decline now also says what the recovery tried and why it did not apply (checks.subset_recovery: refusal, dropped, kept, result).
--   3 The audit of a recovered reading: the admitted ledger row (pipeline.provider_description_machine_admissions) starts its reason with "subset_of_reading:" and holds checks.subset_of_reading (the sentences left out with their text, quote and exact code, how many were kept, the original refusal, the original read, evidence and
--     source hash, the md5 and length of the original text); the earlier declined ledger row, the decision history and the original proposal are kept (decision proposed_value, the ledger checks and the item's layer2_state.subset_of_reading hold every sentence, the ones left out and why). At admission the read's proposal and the item's proposed_value are set to the kept description and sentences, the text the catalogue holds, because security.provider_description_approved_lineage_v1 (and so the Website and Zoho read-back, the run result and the selection) finds an admitted description only when the read and the item carry that exact text. The Layer 4 item is settled by the existing machine decision: layer4_decisions has proposed_value = the original
--     proposal and final_value = the original proposal with the kept description and sentences and subset_of_reading, layer2_state.subset_of_reading = true; the control event carries subset_of_reading. Nothing is deleted.
--   4 security.data_delivery_pdesc_v1(): one additive key subset_recovery (recovered, recovered_ever, sentences_left_out, waiting_items, still_declined, still_declined_by_cause, causes). Existing keys unchanged; a count that cannot be made is shown as before.
--   5 security.provider_description_fill_status_v1(uuid[],boolean,uuid) (the status read of Provider Fill Fields, read only): one additive key machine for each provider (the latest machine ledger row: outcome, tier, reason, time, the Layer 4 item, whether it is for the current reading, the sentences left out of a recovered reading
--     without their quotes, and what the recovery found for a declined one) and four more facts of the reader (ai_calls, model, content_hash, source_captured_at). Today the screen cannot tell a reading the machine rule declined from one that only waits for a person (the read says proposed whatever the ledger says).
--     Existing keys unchanged. The screen builds its single Extract / refresh description now action and its stage view on it.
-- Not changed: the settle (its hourly re-check and its per-run bound), the step, the gate, the text check, the validation, the word lists, pdesc.machine_numbers_allowed, pdesc.min_sentences, pdesc.min_chars, the identity proof, the quote proof, rejection memory, locks, budgets, the reader, any read, ledger row, Layer 4 item or description by this migration.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.provider_description_machine_admit_v1(uuid) dedf28930cc7a12ad31570dec0d2f334 -> 86d2596a13efe885b597771e70542efd
--   security.data_delivery_pdesc_v1() 15b2f9882e77d7fcf0a8a4be2b6df18f -> 575bded841d3ceca0afc9bdf13bf4d82
--   security.provider_description_fill_status_v1(uuid[],boolean,uuid) 4a37300325d9da37ba26c92a0eda8279 -> e0fea4e1e736f97b5a7172ecb981501a
--   security.provider_description_subset_v1(uuid,jsonb) (new) -> 5f2d1a514ffcb45582888a2f455c63b8
-- Each edit is guarded: the migration stops, and nothing is applied, if a live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is kept in supabase/held/pdesc_sentence_subset_recovery_forward_recovery.sql.
-- Depends on 20261110040000 (the admission as it leaves it) and 20261110150000 (the Data Delivery stream as it leaves it). Consumer API (G3): not touched (internal provider-description functions; the description is written by the same existing admission statement, so the Website and Zoho read it exactly as they read any machine-admitted description).
-- No operational value is written into code (G2): the sentence range, the character range, the figure rule, the word lists and the duplicate share are read by the existing checks from pipeline settings; the only constants are the three refusal codes of the text rule that dropping a sentence can remove, and the codes of the audit (marked `-- fixed:`). No job is added (G1): the recovery runs inside the existing machine settlement.
-- Replaces: security.provider_description_machine_admit_v1 (it declined a whole reading for one offending sentence) and security.data_delivery_pdesc_v1 (it had no recovery key) and security.provider_description_fill_status_v1 (it did not say what the machine rule decided); the earlier text is kept in supabase/held/pdesc_sentence_subset_recovery_forward_recovery.sql
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration; no existing read, ledger row, Layer 4 item, description or setting value is changed by it (the recovery runs later, inside the existing hourly machine settlement and at the record of a new reading).

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_machine_admit_v1(uuid)'), ('security.data_delivery_pdesc_v1()'), ('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'),
                                 ('security.provider_description_machine_gate_v1(uuid,text,jsonb)'), ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'),
                                 ('security.provider_description_basic_profile_v1(uuid)'), ('security.provider_description_fill_status_v1(uuid[],boolean,uuid)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.provider_description_machine_admissions') is null or to_regclass('pipeline.layer4_decisions') is null then raise exception 'required provider-description tables are missing'; end if;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
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
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 1 the sentence subset (new; applying again writes the same text)
create or replace function security.provider_description_subset_v1(p_provider uuid, p_sentences jsonb) returns jsonb
language plpgsql stable security definer set search_path to ''
as $subset$
-- provider-description-subset-v1
declare s jsonb; v_o int := 0; v_bad text; v_kept jsonb := '[]'::jsonb; v_drop jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_sentences) is distinct from 'array' then return null; end if;
  for s in select x from jsonb_array_elements(p_sentences) x loop
    v_o := v_o + 1;
    -- the SAME machine text check the whole description goes through, on this sentence alone with its own official quote (a neutral population word is allowed only when the quote holds it and does not negate it, as for the whole text)
    v_bad := security.pdesc_machine_text_check_ctx_v1(p_provider, s->>'text', '{}'::text[], jsonb_build_array(s));
    if v_bad is null then v_kept := v_kept || jsonb_build_array(s);
    else v_drop := v_drop || jsonb_build_array(jsonb_build_object('index', v_o, 'code', v_bad, 'text', s->>'text', 'quote', left(coalesce(s->>'quote', ''), 600))); -- fixed: the audit shows the first 600 characters of the quote; the full quote stays in the proposal
    end if;
  end loop;
  return jsonb_build_object('kept', v_kept, 'dropped', v_drop);
end $subset$;

comment on function security.provider_description_subset_v1(uuid, jsonb) is 'CF-247 F-PDESC: splits the sentences of a provider-description reading into those the machine text rule passes (kept, in order) and those it refuses (dropped: index, exact code, text, quote), by running security.pdesc_machine_text_check_ctx_v1 on each sentence alone with its own quote. Read only; never rewords, merges or adds. Used by security.provider_description_machine_admit_v1 (sentence-subset recovery).';
revoke all on function security.provider_description_subset_v1(uuid, jsonb) from public, anon, authenticated;

-- 2 the machine admission recovers a reading by leaving out the sentences the text rule refuses; 4 Data Delivery counts the recovery
select pg_temp.edit_all('security.provider_description_machine_admit_v1(uuid)', 'dedf28930cc7a12ad31570dec0d2f334', '86d2596a13efe885b597771e70542efd',
array[$o1$v_url text; v_hash text; v_reason text; v_decline text; v_basic jsonb; v_upg boolean := false;$o1$,
      $o2$  v_text := nullif(btrim(i.proposed_value->>'description'), '');$o2$,
      $o3$    if not (v_gate->>'ok')::boolean then v_decline := v_gate->>'rule'; v_reason := v_gate->>'reason'; end if;
  end if;
$o3$,
      $o4$jsonb_array_length(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) < security.pipeline_num_v1('pdesc.min_sentences', 2)$o4$,
      $o5$insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, evidence_id, source_url, source_hash, facts, actor)
    values (i.entity_id, i.id, v_read.id, case when v_tier in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_tier else 'stored' end, v_rule, 'declined', v_reason, i.evidence_id, v_read.source_url, v_read.content_hash, v_facts, v_sys)
    on conflict (review_item_id) where outcome = 'declined' do update set reason = excluded.reason, tier = excluded.tier, facts = excluded.facts, created_at = now();$o5$,
      $o6$-- fixed: a short hash prefix is shown for reading, the full hash is stored
$o6$,
      $o7$values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine'), coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;$o7$,
      $o8$'machine_rule', v_rule, 'tier', v_tier, 'decision_id', v_dec, 'field_code', i.field_code), v_sys);$o8$,
      $o9$checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') where id = v_read.id;$o9$,
      $o10$'admitted', v_reason || case when v_upg then$o10$,
      $o11$'neutral_words', to_jsonb(security.pdesc_machine_neutral_supported_v1(v_text, case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end))), v_sys);$o11$,
      $o12$'sentences', jsonb_array_length(coalesce(i.proposed_value->'sentences', '[]'::jsonb))))$o12$,
      $o13$'description_chars', length(v_text), 'published', v_shown = v_text);$o13$,
      $o14$  update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = i.id and status = 'pending';$o14$],
array[$n1$v_url text; v_hash text; v_reason text; v_decline text; v_basic jsonb; v_upg boolean := false;
        v_sent jsonb; v_sub jsonb; v_subinfo jsonb; v_try jsonb; v_gate2 jsonb; v_text0 text; -- sentence-subset recovery$n1$,
      $n2$  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  v_sent := coalesce(i.proposed_value->'sentences', '[]'::jsonb); -- the sentences the description is made of (the proposal itself is never changed)$n2$,
      $n3$    if not (v_gate->>'ok')::boolean then v_decline := v_gate->>'rule'; v_reason := v_gate->>'reason'; end if;
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
$n3$,
      $n4$jsonb_array_length(v_sent) < security.pipeline_num_v1('pdesc.min_sentences', 2)$n4$,
      $n5$insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, evidence_id, source_url, source_hash, facts, checks, actor)
    values (i.entity_id, i.id, v_read.id, case when v_tier in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_tier else 'stored' end, v_rule, 'declined', v_reason, i.evidence_id, v_read.source_url, v_read.content_hash, v_facts,
            case when v_try is not null then jsonb_build_object('subset_recovery', v_try) else '{}'::jsonb end, v_sys)
    on conflict (review_item_id) where outcome = 'declined' do update set reason = excluded.reason, tier = excluded.tier, facts = excluded.facts, created_at = now(),
            checks = (coalesce(pipeline.provider_description_machine_admissions.checks, '{}'::jsonb) - 'subset_recovery') || excluded.checks;$n5$,
      $n6$-- fixed: a short hash prefix is shown for reading, the full hash is stored
  if v_subinfo is not null then
    v_reason := v_reason || format(' Sentence subset of the reading: %s of %s sentences kept, %s left out because the automatic text rule refused them; nothing was reworded or added.', v_subinfo->>'kept_sentences', v_subinfo->>'given_sentences', jsonb_array_length(v_subinfo->'dropped'));
  end if;
$n6$,
      $n7$values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value,
          case when v_subinfo is not null then i.proposed_value || jsonb_build_object('description', v_text, 'sentences', v_sent, 'subset_of_reading', v_subinfo) else i.proposed_value end, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') || case when v_subinfo is not null then jsonb_build_object('subset_of_reading', true) else '{}'::jsonb end, coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;$n7$,
      $n8$'machine_rule', v_rule, 'tier', v_tier, 'decision_id', v_dec, 'field_code', i.field_code, 'subset_of_reading', v_subinfo is not null), v_sys);$n8$,
      $n9$proposal = case when v_subinfo is not null then coalesce(proposal, '{}'::jsonb) || jsonb_build_object('description', v_text, 'sentences', v_sent) else proposal end,
         checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') || case when v_subinfo is not null then jsonb_build_object('subset_of_reading', v_subinfo) else '{}'::jsonb end where id = v_read.id;$n9$,
      $n10$'admitted', case when v_subinfo is not null then 'subset_of_reading: ' else '' end || v_reason || case when v_upg then$n10$,
      $n11$'neutral_words', to_jsonb(security.pdesc_machine_neutral_supported_v1(v_text, case when v_tier = 'registry_factual' then '[]'::jsonb else v_sent end)))
          || case when v_subinfo is not null then jsonb_build_object('subset_of_reading', v_subinfo) else '{}'::jsonb end, v_sys);$n11$,
      $n12$'sentences', jsonb_array_length(v_sent)))$n12$,
      $n13$'description_chars', length(v_text), 'published', v_shown = v_text, 'subset_of_reading', v_subinfo is not null);$n13$,
      $n14$  -- a recovered reading: the item and the read hold the description the catalogue now holds (the kept sentences), so the approved-lineage test of the Website and Zoho read-back, the run result and the selection find it; the original proposal (every sentence, the sentences left out and why) stays in the decision row (proposed_value), the ledger row and layer2_state.subset_of_reading
  update pipeline.layer4_review_items set status = 'approved', decided_at = now(),
         proposed_value = case when v_subinfo is not null then proposed_value || jsonb_build_object('description', v_text, 'sentences', v_sent) else proposed_value end,
         layer2_state = case when v_subinfo is not null then coalesce(layer2_state, '{}'::jsonb) || jsonb_build_object('subset_of_reading', v_subinfo) else layer2_state end
   where id = i.id and status = 'pending';$n14$]);

select pg_temp.edit_all('security.provider_description_fill_status_v1(uuid[],boolean,uuid)', '4a37300325d9da37ba26c92a0eda8279', 'e0fea4e1e736f97b5a7172ecb981501a',
array[$o1$r.review_item_id, r.evidence_id, r.source_url, r.read_via
        from pipeline.provider_description_reads r where r.provider_id = any(p_ids)$o1$,
      $o2$'read_via', lr.read_via),$o2$,
      $o3$       where m.provider_id = any(p_ids) order by m.provider_id, c.created_at desc, c.id desc
    )
$o3$,
      $o4$      'latest_task', case when lt.cohort_id is null then null else$o4$,
      $o5$left join lr on lr.provider_id = p.id left join lt on lt.provider_id = p.id$o5$],
array[$n1$r.review_item_id, r.evidence_id, r.source_url, r.read_via, r.ai_calls, r.model, r.content_hash, r.source_captured_at
        from pipeline.provider_description_reads r where r.provider_id = any(p_ids)$n1$,
      $n2$'read_via', lr.read_via, 'ai_calls', lr.ai_calls, 'model', lr.model, 'source_captured_at', lr.source_captured_at, 'content_hash', lr.content_hash),$n2$,
      $n3$       where m.provider_id = any(p_ids) order by m.provider_id, c.created_at desc, c.id desc
    ), mc as (
      -- the latest machine decision of each provider (migration 20261110210000): admitted, or declined with the reason and what the sentence-subset recovery found
      select distinct on (a.provider_id) a.provider_id, a.outcome, a.tier, a.reason, a.created_at, a.review_item_id, a.checks
        from pipeline.provider_description_machine_admissions a where a.provider_id = any(p_ids) and a.withdrawn_at is null order by a.provider_id, a.created_at desc, a.id desc
    )
$n3$,
      $n4$      'machine', case when mc.provider_id is null then null else jsonb_build_object('outcome', mc.outcome, 'tier', mc.tier, 'reason', mc.reason, 'at', mc.created_at, 'review_item_id', mc.review_item_id,
        'current_reading', mc.review_item_id is not distinct from lr.review_item_id,
        'subset', case when mc.checks ? 'subset_of_reading' then jsonb_build_object('kept_sentences', mc.checks->'subset_of_reading'->'kept_sentences', 'given_sentences', mc.checks->'subset_of_reading'->'given_sentences',
          'dropped', (select coalesce(jsonb_agg(d - 'quote'), '[]'::jsonb) from jsonb_array_elements(mc.checks->'subset_of_reading'->'dropped') d)) end,
        'subset_result', mc.checks->'subset_recovery'->>'result') end,
      'latest_task', case when lt.cohort_id is null then null else$n4$,
      $n5$left join lr on lr.provider_id = p.id left join lt on lt.provider_id = p.id left join mc on mc.provider_id = p.id$n5$]);

select pg_temp.edit_all('security.data_delivery_pdesc_v1()', '15b2f9882e77d7fcf0a8a4be2b6df18f', '575bded841d3ceca0afc9bdf13bf4d82',
array[$o1$'[]'::jsonb))));$o1$],
array[$n1$'[]'::jsonb)),
    -- sentence-subset recovery (migration 20261110210000): readings recovered by leaving out the sentences the text rule refuses, and the readings still declined, by cause
    'subset_recovery', jsonb_build_object(
        'recovered', (select count(*) from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.withdrawn_at is null and a.checks ? 'subset_of_reading'),
        'recovered_ever', (select count(*) from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.checks ? 'subset_of_reading'),
        'sentences_left_out', (select coalesce(sum(jsonb_array_length(a.checks->'subset_of_reading'->'dropped')), 0) from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.checks ? 'subset_of_reading'),
        'waiting_items', (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'provider' and i.field_code = 'provider_description' and i.status = 'pending'),
        'still_declined', (select count(*) from pipeline.layer4_review_items i join pipeline.provider_description_machine_admissions d on d.review_item_id = i.id and d.outcome = 'declined'
                            where i.entity_type = 'provider' and i.field_code = 'provider_description' and i.status = 'pending'),
        'causes', (select count(distinct z.cause) from (select case when d.checks->'subset_recovery'->>'result' is not null and d.checks->'subset_recovery'->>'result' <> 'adopted' then 'subset: ' || (d.checks->'subset_recovery'->>'result')
                                                                    else coalesce(substring(d.reason from '\(([a-z_]+)'), 'other') end cause
                                                          from pipeline.layer4_review_items i join pipeline.provider_description_machine_admissions d on d.review_item_id = i.id and d.outcome = 'declined'
                                                         where i.entity_type = 'provider' and i.field_code = 'provider_description' and i.status = 'pending') z),
        'still_declined_by_cause', coalesce((select jsonb_agg(jsonb_build_object('cause', c.cause, 'n', c.n, 'example', c.example) order by c.n desc, c.cause)
                                               from (select z.cause, count(*) n, (array_agg(z.reason order by z.created_at desc))[1] example
                                                       from (select case when d.checks->'subset_recovery'->>'result' is not null and d.checks->'subset_recovery'->>'result' <> 'adopted' then 'subset: ' || (d.checks->'subset_recovery'->>'result')
                                                                         else coalesce(substring(d.reason from '\(([a-z_]+)'), 'other') end cause, d.reason, d.created_at
                                                               from pipeline.layer4_review_items i join pipeline.provider_description_machine_admissions d on d.review_item_id = i.id and d.outcome = 'declined'
                                                              where i.entity_type = 'provider' and i.field_code = 'provider_description' and i.status = 'pending') z
                                                      group by z.cause order by 2 desc, 1 limit v_top) c), '[]'::jsonb))));$n1$]);

-- the new function is the text this change recorded
do $c$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.provider_description_subset_v1(uuid,jsonb)'::regprocedure) <> '5f2d1a514ffcb45582888a2f455c63b8' then
    raise exception 'security.provider_description_subset_v1 does not have the recorded body md5';
  end if;
end $c$;
