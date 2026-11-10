-- HELD (not a migration): forward recovery for 20261110230000 (course descriptions: subset recovery of stuck readings). It restores the five edited function bodies byte for byte (the live bodies read 10 Nov 2026).
-- Run only if the Platform Admin decides to take the change back. Each function is guarded by the md5 of what is live now (the edited text or the original); a function that is neither stops the whole paste with a message.
-- The new helper functions (security.cdesc_sentence_fault_v1, cdesc_subset_plan_v1, cdesc_subset_recover_v1, data_delivery_cdesc_subset_v1, cdesc_page_kind_v1, cdesc_item_detail_v1, admin_course_description_item_v1) and the register rows stay in place and are no longer called: nothing here drops or deletes. Descriptions already admitted by subset stay
-- (withdraw one with public.admin_course_description_machine_withdraw_v1). The original check no longer calls security.cdesc_sentence_fault_v1; nothing the old bodies read is missing.

do $g$
declare r record; v text;
begin
  for r in select * from (values
    ('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '6e65745a7863f0dae97a743821475eb0', 'd310fa64f61f2243df1416d3e48f6bab'),
    ('security.course_description_machine_admit_v1(uuid,text)', '69b8911fe24f041b4cf67a844d8d8f6f', '569f3ceb95c3d31b378ce7288b7abd24'),
    ('security.course_description_machine_check_v1(uuid)', '4c321730269064b42ff9ac10a114336b', '2a5b91aa6b93b920bbb80df9920aca09'),
    ('security.course_description_machine_run_v1()', 'faa6dab1bfeef3464ba86fac11b34766', '42c73e9c0f376150e7778104dfa9830a'),
    ('security.data_delivery_cdesc_flow_v1()', 'bd500303727d5c11a708aa99341809a4', '3d4c538fc23977018982bc64023a4690')
  ) v(sig, md5_old, md5_new) loop
    v := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig));
    if v is null then raise exception '% is missing', r.sig; end if;
    if v not in (r.md5_old, r.md5_new) then raise exception 'live % differs from both texts this recovery knows (body md5 %)', r.sig, v; end if;
  end loop;
end $g$;

CREATE OR REPLACE FUNCTION security.course_description_check_with_v1(p_course uuid, p_result jsonb, p_claim_words jsonb, p_marketing_words jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text; v_sup numeric; v_other record; v_pid uuid;
        v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6); v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_checks jsonb; v_words text[];
        v_claim jsonb := coalesce(p_claim_words, security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb);
        v_mkt jsonb := coalesce(p_marketing_words, security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb);
begin
  select c.provider_id into v_pid from catalogue.courses c where c.id = p_course;
  v_n := jsonb_array_length(v_s);
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_s) with ordinality e(x, o));
  v_checks := jsonb_build_object('sentences', v_n, 'chars', length(coalesce(v_text, '')));
  if coalesce((p_result->>'about_course')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not state it');
  end if;
  if v_n < security.pipeline_num_v1('enrich.course_description_min_sentences', 1) or v_n > security.pipeline_num_v1('enrich.course_description_max_sentences', 4) then
    return jsonb_build_object('ok', false, 'rule', 'sentence_count', 'checks', v_checks, 'reason', v_n || ' sentence(s), outside the set range');
  end if;
  for s in select x from jsonb_array_elements(v_s) x loop
    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s words are not on the course page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(v_mkt) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(v_claim) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w) and not security.cdesc_learner_word_ok_v1(w, t, s->>'quote')) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
    end if;
    -- a sentence that does not end as a sentence is a fragment: held, never cut or completed (Platform Admin 2 Nov 2026 23:24)
    if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
      return jsonb_build_object('ok', false, 'rule', 'incomplete_sentence', 'checks', v_checks, 'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
    end if;
    v_sup := security.pdesc_support_v1(t, s->>'quote');
    if v_sup < v_min_sup then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
        'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
    end if;
  end loop;
  if length(v_text) < security.pipeline_num_v1('enrich.course_description_min_chars', 80) or length(v_text) > security.pipeline_num_v1('enrich.course_description_max_chars', 700) then
    return jsonb_build_object('ok', false, 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range (held whole, never cut)');
  end if;
  -- boilerplate: the same words as another course of the provider (held, or waiting in Layer 4)
  -- CF-247 IQ-00053 residual: the new text is split into words once, and each other text inline, by the rule of security.pdesc_words_v1 and
  -- security.pdesc_similarity_v1 (distinct lower-case words of 3 or more letters or digits; shared words over all words of both)
  v_words := security.pdesc_words_v1(v_text);
  select z.course_id, z.sim into v_other from (
    select x.course_id, case when cardinality(v_words) = 0 or cardinality(x.wb) = 0 then 0
                             else round(k.n::numeric / (cardinality(v_words) + cardinality(x.wb) - k.n), 4) end sim
      from (select x0.course_id, array(select distinct w from regexp_split_to_table(lower(coalesce(x0.d, '')), '[^a-z0-9]+') w where length(w) >= 3) wb from (
      select c.id course_id, c.description d, c.updated_at at from catalogue.courses c
       where c.provider_id = v_pid and c.id <> p_course and nullif(btrim(c.description), '') is not null
      union all
      select r.entity_id, r.proposed_value->>'description', r.created_at from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
       where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid and r.entity_id <> p_course
      order by 3 desc limit security.pipeline_num_v1('enrich.course_description_duplicate_window', 500)::int) x0) x
      cross join lateral (select count(*) n from unnest(v_words) w where w = any (x.wb)) k) z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.course_id is not null then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_other_course', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.course_id, 'similarity', v_other.sim),
      'reason', 'the same words as another course''s description (' || v_other.sim || '): text that is not about this course');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'ok', 'text', v_text, 'checks', v_checks, 'reason', null);
end $function$;

CREATE OR REPLACE FUNCTION security.course_description_machine_admit_v1(p_item uuid, p_via text DEFAULT 'settle'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; v jsonb; v_text text; v_after text; v_pub jsonb; v_shown text; v_cc text; v_dec uuid; v_reason text; v_msg text; v_stamp text; v_next text; v_tr boolean;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account that records Decision 263 rule decisions
        v_rule constant text := 'cdesc-machine-v1'; v_ref constant text := 'CF-247 F-CDESC; Platform Admin decision 10 Nov 2026 (course descriptions: source-verified machine admission)';
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; -- derived: a decline is looked at again after the days the queue reads a course again
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off'); end if;
  select * into i from pipeline.layer4_review_items where id = p_item for update;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_description_first_read' then return jsonb_build_object('ok', false, 'rule', 'not_a_course_description_item'); end if;
  if i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'item_not_pending', 'status', i.status); end if;
  select * into c from catalogue.courses where id = i.entity_id for update;
  v_stamp := security.course_description_machine_policy_stamp_v1();
  v := security.course_description_machine_check_v1(p_item);
  if coalesce((v->>'ok')::boolean, false) then
    v_text := v->>'text';
    begin
      -- the one write, proved on the row: a guard that put the old text back (a hand lock) must stop the admission, not leave an audit that says it was published
      update catalogue.courses set description = v_text, updated_at = now() where id = c.id and nullif(btrim(description), '') is null;
      select nullif(btrim(x.description), '') into v_after from catalogue.courses x where x.id = c.id;
      if v_after is distinct from v_text then raise exception 'cdesc:description_not_written:the catalogue kept the earlier text (a lock or guard put it back)'; end if;
      -- the consumer read-back (read only): what the website function returns for this course now
      begin v_pub := public.website_v2_course(c.stable_key); exception when others then v_pub := null; end;
      v_shown := v_pub->'item'->>'description';
      v_cc := case when v_pub is null then 'error' when v_pub ? 'error' then 'not_in_feed' when v_shown = v_text then 'matched' when nullif(btrim(v_shown), '') is null then 'lag' else 'mismatch' end;
      if v_cc = 'mismatch' then raise exception 'cdesc:consumer_mismatch:the website function shows different text for this course after the write'; end if;
      update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = i.id and status = 'pending';
      v_reason := format('Auto (%s, %s): description read from the course''s own stored page %s (content hash %s); right course and page (identity proof and a margin of at least 0.1 over the runner-up), the quote results the worker stored for each sentence, the sentence, length, support and duplicate checks and the wording policy checked again at admission (the page was not read again). Not a person''s decision.',
                         v_rule, coalesce(p_via, 'settle'), coalesce(v->>'source_url', ''), left(coalesce(v->>'content_hash', ''), 12)); -- fixed: a short hash prefix is shown for reading, the full hash is stored
      insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
      values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
              coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'actor_kind', 'machine', 'via', coalesce(p_via, 'settle')), coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;
      insert into pipeline.admin_control_events (area, action, target, detail, actor)
      values ('layer4', 'inbox_decide', i.id::text, jsonb_build_object('kind', 'course_description', 'ref', i.id::text, 'choice', 'approve', 'reason', v_reason, 'course_id', c.id, 'provider_id', c.provider_id,
              'auto', true, 'machine_rule', v_rule, 'actor_kind', 'machine', 'decision_id', v_dec, 'field_code', i.field_code, 'consumer_check', v_cc), v_sys);
      insert into pipeline.search_refresh_signals (entity_type, entity_id, review_decision_id, reason, change_control_ref)
      values ('course', c.id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
      insert into pipeline.course_description_machine_admissions (course_id, provider_id, review_item_id, reading_item_id, rule, outcome, reason_code, reason, policy_stamp, before_description, after_description, text_md5,
             evidence_id, content_hash, source_url, storage_path, model, prompt_version, worker, checks, recovery, consumer_check, consumer_checked_at, actor)
      values (c.id, c.provider_id, i.id, (v->>'reading_item_id')::bigint, v_rule, 'admitted', 'admitted', v_reason, v_stamp, null, v_text, v->>'text_md5',
              i.evidence_id, v->>'content_hash', v->>'source_url', v->>'storage_path', v->>'model', v->>'prompt_version', v->>'worker',
              coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('decision_id', v_dec, 'via', coalesce(p_via, 'settle'), 'source_recheck', v->>'source_recheck', 'captured_at', v->>'captured_at'),
              'Withdraw with public.admin_course_description_machine_withdraw_v1(course, reason) (Platform Admin): puts the empty description back if no person changed it and no lock was added since.',
              v_cc, now(), v_sys);
      return jsonb_build_object('ok', true, 'rule', v_rule, 'course_id', c.id, 'decision_id', v_dec, 'description_chars', length(v_text), 'consumer_check', v_cc);
    exception when others then
      get stacked diagnostics v_msg = message_text;
      v := security.cdesc_machine_fail_v1(case when v_msg like 'cdesc:%' then split_part(v_msg, ':', 2) else 'admission_error' end,
                                          case when v_msg like 'cdesc:%' then split_part(v_msg, ':', 3) else left(v_msg, 300) end, -- fixed: display width of the stored reason text
                                          'Nothing was written; the item still waits. A person decides in Layer 4, or the next run tries again.', v_msg not like 'cdesc:%' or v_msg like 'cdesc:consumer_mismatch:%'); -- a feed that disagrees is read again after an hour
    end;
  end if;
  -- declined: the item stays waiting with the exact reason on it; recorded once for the item and refreshed
  v_next := coalesce(v->>'next_action', 'A person decides in Layer 4.'); v_tr := coalesce((v->>'transient')::boolean, false);
  v_reason := coalesce(v->>'reason', 'The machine rule did not admit this.');
  insert into pipeline.course_description_machine_admissions (course_id, provider_id, review_item_id, reading_item_id, rule, outcome, reason_code, reason, next_action, transient, retry_after, policy_stamp, text_md5, evidence_id, actor)
  values (c.id, c.provider_id, i.id, case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end, v_rule, 'declined', v->>'rule', v_reason, v_next, v_tr,
          now() + case when v_tr then make_interval(hours => 1) else make_interval(days => v_days) end, -- fixed: a transient decline is looked at again after an hour
          v_stamp, md5(coalesce(i.proposed_value->>'description', '')), i.evidence_id, v_sys)
  on conflict (review_item_id) where outcome = 'declined' do update set reason_code = excluded.reason_code, reason = excluded.reason, next_action = excluded.next_action, transient = excluded.transient,
         retry_after = excluded.retry_after, policy_stamp = excluded.policy_stamp, text_md5 = excluded.text_md5, evidence_id = excluded.evidence_id, created_at = now();
  update pipeline.layer4_review_items set escalation_reason = left('Machine rule ' || v_rule || ' did not admit this: ' || (v->>'rule') || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule [^:]*: [a-z0-9_]+\. ', ''), 1000) -- fixed: the item's reason column shows its first 1000 characters
   where id = i.id and coalesce(escalation_reason, '') not like 'Machine rule ' || v_rule || ' did not admit this: ' || (v->>'rule') || '.%';
  return jsonb_build_object('ok', false, 'rule', v->>'rule', 'reason', v_reason, 'next_action', v_next);
end $function$;

CREATE OR REPLACE FUNCTION security.course_description_machine_check_v1(p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; p catalogue.providers%rowtype; g pipeline.coverage_course_pages%rowtype; e pipeline.evidence_artifacts%rowtype; f pipeline.field_enrich_items%rowtype;
        sc pipeline.course_description_source_checks%rowtype;
        v_rule constant text := 'cdesc-machine-v1'; v_fid bigint; v_text text; v_md5 text; v_chk jsonb; v_pol text; v_sents jsonb; v_share numeric; v_win int; v_words text[]; v_dup record; v_other uuid; v_recheck text := 'not_run'; v_kind text; v_prov jsonb; v_many boolean := false;
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
  -- a page bound by the course's own CRICOS code on the page (Decision 265) is a code proof, not a score contest: the margin does not apply to it while no other course is bound to the same address
  if g.basis = 'ai_match' or (g.score is not null and g.runner_up is not null and g.score - g.runner_up < 0.1
                              and not (g.basis = 'cricos_code_on_page' and not exists (select 1 from pipeline.coverage_course_pages g2 where g2.provider_id = g.provider_id and g2.course_id <> g.course_id
                                                                                                                       and (g2.url = g.url or lower(regexp_replace(regexp_replace(g2.url, '[?#].*$', ''), '/+$', '')) = lower(regexp_replace(regexp_replace(g.url, '[?#].*$', ''), '/+$', ''))
                                                                                                                            or (g2.evidence_id is not null and g2.evidence_id = g.evidence_id))))) then -- fixed: a margin under 0.1 between the chosen page and the runner-up is not a clear match; no setting exists for it and none is added (10 Nov 2026 05:40 rule)
    return security.cdesc_machine_fail_v1('identity_margin_thin', 'The page was matched by an AI match or by a score under 0.1 above the next candidate (' || coalesce(g.basis, 'no basis') || ', score ' || coalesce(g.score::text, 'none') || ', runner-up ' || coalesce(g.runner_up::text, 'none') || ').', 'A person decides in Layer 4.'); end if;
  if g.evidence_id is distinct from i.evidence_id then
    return security.cdesc_machine_fail_v1('evidence_moved', 'The course''s bound page copy changed after this description was read.', 'The queue reads the new copy; the old proposal is superseded or decided by a person.', true); end if;
  if i.proposed_value->>'source_url' is distinct from g.url then
    return security.cdesc_machine_fail_v1('page_url_changed', 'The page address the description was read from is no longer the bound address.', 'A person decides in Layer 4.'); end if;
  -- the kind of page: a requirements, entry, fees, how-to-apply or programme-structure page is not a course overview, so its text is not a description of the course
  select seg.s into v_kind from regexp_split_to_table(lower(regexp_replace(split_part(split_part(coalesce(g.url, ''), '#', 1), '?', 1), '^[a-z][a-z0-9+.-]*://[^/]*', '')), '/') seg(s)
   where seg.s ~ '^(entry|entry-requirements|admission-requirements|requirements|fees|tuition-fees|how-to-apply|programme-structure|program-structure|course-structure)$' limit 1; -- fixed: the page kinds a person decides (10 Nov 2026); a quality rule, no setting exists and none is added
  if v_kind is not null then
    return security.cdesc_machine_fail_v1('wrong_page_kind', 'The description was read from a page whose address has the part "' || v_kind || '" (' || coalesce(g.url, 'no address') || '), so it is not the course overview.', 'A person decides in Layer 4.'); end if;
  v_fid := case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end;
  select * into f from pipeline.field_enrich_items where id = v_fid;
  if f.id is null or f.field <> 'description' then return security.cdesc_machine_fail_v1('reading_missing', 'The reading behind the proposal is not available.', 'A person decides in Layer 4.'); end if;
  if f.course_id is distinct from c.id then return security.cdesc_machine_fail_v1('reading_other_course', 'The reading belongs to another course.', 'A person decides in Layer 4.'); end if;
  if f.state <> 'review' then return security.cdesc_machine_fail_v1('reading_not_current', 'The reading is in state ' || f.state || ', not waiting.', 'A person decides in Layer 4.'); end if;
  if f.evidence_id is distinct from i.evidence_id then return security.cdesc_machine_fail_v1('reading_other_evidence', 'The reading was made on a different page copy than the proposal names.', 'A person decides in Layer 4.'); end if;
  if nullif(btrim(f.value->>'text'), '') is distinct from v_text then return security.cdesc_machine_fail_v1('text_changed', 'The proposal text differs from the reading it came from.', 'A person decides in Layer 4.'); end if;
  -- the reader: recorded on the item, else on the reading, else the stored AI answer that holds exactly this reading's sentences
  v_prov := security.cdesc_reading_provenance_v1(f.id, f.value, i.layer3_state);
  if nullif(v_prov->>'model', '') is null or nullif(v_prov->>'prompt', '') is null then
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
  v_pol := security.cdesc_machine_text_check_v1(p.id, v_text, v_sents);
  if v_pol is not null then
    return security.cdesc_machine_fail_v1('policy_' || split_part(v_pol, ':', 1), 'The wording has a word, figure or markup the admission policy does not admit (' || v_pol || ').', 'A person decides in Layer 4.'); end if;
  -- catalogue-wide duplicates: exact (any course, described or waiting) and near (other providers; this provider is covered by the live check above)
  select d.id into v_other from catalogue.courses d where d.id <> c.id and nullif(btrim(d.description), '') is not null and md5(security.cdesc_norm_v1(d.description)) = v_md5 limit 1;
  if v_other is not null then
    return security.cdesc_machine_fail_v1('duplicate_exact_described', 'Another course already holds exactly this wording (shared qualification wording).', 'A person decides in Layer 4.'); end if;
  -- a twin that waits is only a reason to wait when it is OLDER and can still be admitted; otherwise two courses with the same wording would decline each other for good
  -- wording that waits at three or more different providers is shared training-package wording: nothing is tie-broken, every waiting twin blocks as before
  select count(distinct c3.provider_id) >= 3 into v_many from pipeline.layer4_review_items o3 join catalogue.courses c3 on c3.id = o3.entity_id
   where o3.field_code = i.field_code and o3.status = 'pending' and md5(security.cdesc_norm_v1(o3.proposed_value->>'description')) = v_md5;
  select o.entity_id into v_other from pipeline.layer4_review_items o where o.field_code = i.field_code and o.status = 'pending' and o.entity_id <> c.id and md5(security.cdesc_norm_v1(o.proposed_value->>'description')) = v_md5
     and (v_many or ((o.created_at, o.id) < (i.created_at, i.id) and not security.cdesc_parked_other_v1(o.id))) limit 1;
  if v_other is not null then
    return security.cdesc_machine_fail_v1('duplicate_exact_waiting', 'Another waiting description has exactly this wording (shared qualification wording).', 'A person decides in Layer 4.'); end if;
  v_share := security.pipeline_num_v1('pdesc.duplicate_share', 0.8); v_win := security.pipeline_num_v1('enrich.course_description_duplicate_window', 500)::int; v_words := security.pdesc_words_v1(v_text);
  select z.course_id, z.sim into v_dup from (
    select x.course_id, round(k.n::numeric / (cardinality(v_words) + cardinality(x.wb) - k.n), 4) sim
      from (select x0.course_id, array(select distinct w from regexp_split_to_table(lower(coalesce(x0.d, '')), '[^a-z0-9]+') w where length(w) >= 3) wb
              from (select * from (select r.entity_id course_id, r.proposed_value->>'description' d from pipeline.layer4_review_items r join catalogue.courses c2 on c2.id = r.entity_id
                                    where r.field_code = i.field_code and (r.status in ('approved', 'edited_approved') or (r.status = 'pending' and (v_many or ((r.created_at, r.id) < (i.created_at, i.id) and not security.cdesc_parked_other_v1(r.id))))) and r.entity_id <> c.id and c2.provider_id <> c.provider_id
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
    'model', v_prov->>'model', 'prompt_version', v_prov->>'prompt', 'worker', v_prov->>'worker', 'source_recheck', v_recheck,
    'checks', coalesce(v_chk->'checks', '{}'::jsonb) || jsonb_build_object('identity_basis', g.identity_basis, 'binding', g.status, 'policy', 'ok'));
end $function$;

CREATE OR REPLACE FUNCTION security.course_description_machine_run_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_a jsonb; v_b jsonb; v_h jsonb;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- one failure never stops the run: each part reports its own error
  begin v_h := security.cdesc_recheck_held_v1(); exception when others then v_h := jsonb_build_object('error', sqlerrm); end;
  begin v_a := security.course_description_machine_settle_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.course_description_machine_consumer_recheck_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('on', true, 'held', v_h, 'settle', v_a, 'consumer', v_b);
end $function$;

CREATE OR REPLACE FUNCTION security.data_delivery_cdesc_flow_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_pmax int := security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int;
        v_on boolean := security.pipeline_num_v1('enrich.course_description_machine_on', 0) >= 1; v_stamp text := security.course_description_machine_policy_stamp_v1();
        v_day int; v_full int; v_parked int; v_el jsonb; v_blocker text; v_info jsonb := security.cdesc_job_info_v1(); v_dec jsonb; v_held jsonb; v_gain jsonb; v_last timestamptz; v_lastd timestamptz;
begin
  -- the eligible denominator and where each course is: active, no description, a stored, read, identity-proved page (the rule the standing queue uses)
  select jsonb_build_object('active_courses', (select count(*) from catalogue.courses where lifecycle_status = 'active'),
                            'without_description', count(*), 'never_read', count(*) filter (where z.state is null),
                            'waiting_in_layer4', count(*) filter (where z.state = 'review'),
                            'held_behind_provider_cap', count(*) filter (where z.state = 'skipped' and z.reason like 'held\_first\_admission:%'),
                            'held_by_a_check', count(*) filter (where z.state = 'skipped' and z.reason like 'held: %'),
                            'read_other', count(*) filter (where z.state is not null and z.state <> 'review' and not (z.state = 'skipped' and (z.reason like 'held\_first\_admission:%' or z.reason like 'held: %'))))
    into v_el
    from (select m.cid, l.state, l.reason from (select c.id cid from catalogue.courses c where c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
                                                   and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous') and g.read_status = 'read' and g.identity_basis is not null)) m
            left join lateral (select e.state, e.reason from pipeline.field_enrich_items e where e.course_id = m.cid and e.field = 'description' order by e.id desc limit 1) l on true) z;
  select count(*) into v_day from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
   where e.field = 'description' and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false); -- fixed: the cap is a day's
  select count(*) into v_full from (select c.provider_id from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
                                     where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
                                       and not exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp)
                                     group by 1 having count(*) >= v_pmax) z;
  select count(*) into v_parked from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
     and exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp);
  select coalesce(jsonb_agg(jsonb_build_object('code', k, 'n', n) order by n desc, k), '[]'::jsonb) into v_dec
    from (select d.reason_code k, count(*) n from pipeline.course_description_machine_admissions d join pipeline.layer4_review_items q on q.id = d.review_item_id and q.status = 'pending' where d.outcome = 'declined' and d.withdrawn_at is null group by 1) z;
  select coalesce(jsonb_agg(jsonb_build_object('code', k, 'n', n) order by n desc, k), '[]'::jsonb) into v_held
    from (select case when f.reason like 'held\_first\_admission:%' then 'held_first_admission' else btrim(split_part(f.reason, ':', 2)) end k, count(*) n from pipeline.field_enrich_items f
           where f.field = 'description' and f.state = 'skipped' and (f.reason like 'held: %' or f.reason like 'held\_first\_admission:%') group by 1) z;
  select jsonb_build_object('admitted_24h', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is null and a.created_at > now() - interval '1 day'),   -- fixed: report windows
                            'admitted_7d', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is null and a.created_at > now() - interval '7 days'),
                            'withdrawn_7d', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is not null and a.created_at > now() - interval '7 days'),
                            'retained_total', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is null)),
         max(a.created_at) filter (where a.outcome = 'admitted'), max(a.created_at) filter (where a.outcome = 'declined')
    into v_gain, v_last, v_lastd from pipeline.course_description_machine_admissions a;
  v_blocker := case when not v_on then 'The automatic admission switch is off (Settings, Course descriptions: automatic admission).'
                    when v_day >= v_cap then format('The daily reading cap is used up: %s of %s reads today (Settings, enrich.course_text_items_per_day). Admissions are limited by how many courses are read a day.', v_day, v_cap)
                    when v_full > 0 then format('%s universities have every place taken by descriptions that wait for a person (enrich.course_description_pending_max); their further readings are held.', v_full)
                    else null end;
  return jsonb_build_object('known', true, 'counted_at', now(), 'unit', 'courses', 'eligible', v_el, 'gain', v_gain,
    'declined_by_cause', v_dec, 'held_by_cause', v_held,
    'reads', jsonb_build_object('today', v_day, 'daily_cap', v_cap, 'universities_with_all_places_taken', v_full, 'parked_for_a_person', v_parked),
    'run', jsonb_build_object('automatic_admission_on', v_on, 'last_admission_at', v_last, 'last_decline_at', v_lastd, 'schedule', v_info->>'schedule'),
    'blocker', v_blocker);
exception when others then
  return jsonb_build_object('known', false, 'reason', 'The flow counts could not be read: ' || sqlerrm);
end $function$;

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'))) <> '6e65745a7863f0dae97a743821475eb0' then raise exception 'post-check: the restored security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb) does not have the original body'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_admit_v1(uuid,text)'))) <> '69b8911fe24f041b4cf67a844d8d8f6f' then raise exception 'post-check: the restored security.course_description_machine_admit_v1(uuid,text) does not have the original body'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_check_v1(uuid)'))) <> '4c321730269064b42ff9ac10a114336b' then raise exception 'post-check: the restored security.course_description_machine_check_v1(uuid) does not have the original body'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_run_v1()'))) <> 'faa6dab1bfeef3464ba86fac11b34766' then raise exception 'post-check: the restored security.course_description_machine_run_v1() does not have the original body'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.data_delivery_cdesc_flow_v1()'))) <> 'bd500303727d5c11a708aa99341809a4' then raise exception 'post-check: the restored security.data_delivery_cdesc_flow_v1() does not have the original body'; end if;
end $p$;
