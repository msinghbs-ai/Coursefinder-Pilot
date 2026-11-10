-- HELD (not a migration): forward recovery for 20261110230000 (course descriptions: subset recovery of stuck readings). It restores the four edited function bodies byte for byte (the live bodies read 10 Nov 2026).
-- Run only if the Platform Admin decides to take the change back. Each function is guarded by the md5 of what is live now (the edited text or the original); a function that is neither stops the whole paste with a message.
-- The new helper functions (security.cdesc_sentence_fault_v1, cdesc_subset_plan_v1, cdesc_subset_recover_v1, data_delivery_cdesc_subset_v1) and the register rows stay in place and are no longer called: nothing here drops or deletes. Descriptions already admitted by subset stay
-- (withdraw one with public.admin_course_description_machine_withdraw_v1). The original check no longer calls security.cdesc_sentence_fault_v1; nothing the old bodies read is missing.

do $g$
declare r record; v text;
begin
  for r in select * from (values
    ('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '6e65745a7863f0dae97a743821475eb0', 'd310fa64f61f2243df1416d3e48f6bab'),
    ('security.course_description_machine_admit_v1(uuid,text)', '69b8911fe24f041b4cf67a844d8d8f6f', '569f3ceb95c3d31b378ce7288b7abd24'),
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
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_run_v1()'))) <> 'faa6dab1bfeef3464ba86fac11b34766' then raise exception 'post-check: the restored security.course_description_machine_run_v1() does not have the original body'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.data_delivery_cdesc_flow_v1()'))) <> 'bd500303727d5c11a708aa99341809a4' then raise exception 'post-check: the restored security.data_delivery_cdesc_flow_v1() does not have the original body'; end if;
end $p$;
