-- HELD (not a migration): forward recovery for 20261110180000 (course descriptions: declines and throughput). It restores the seven edited function bodies byte for byte (the live bodies read 10 Nov 2026).
-- Run only if the Platform Admin decides to take the change back. Each function is guarded by the md5 of what is live now (the edited text or the original); a function that is neither stops the whole paste with a message.
-- The new helper functions, the two lists (enrich.course_description_learner_words, enrich.course_description_supported_words) and the register rows stay in place: nothing here drops or deletes. Nothing the old bodies read is missing.

do $g$
declare r record; v text;
begin
  for r in select * from (values
    ('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '3bb5d62b5e86cd7c76707171e02a3ae5', '6e65745a7863f0dae97a743821475eb0'),
    ('security.course_description_machine_check_v1(uuid)', '3e0fe24d762e7fc4348865ea09499690', '4c321730269064b42ff9ac10a114336b'),
    ('security.enrich_course_text_record_v1(bigint,jsonb)', 'c52c1969a80f2d3db1d81a4e46a49cd9', '82e93b8b73d1f13ac3fd62dbb59264f9'),
    ('security.course_description_promote_held_v1(uuid)', '1c990fb9c93b1841195160a0e9a712ae', '2f46bf63e50726d67bdd9d7cf74e915a'),
    ('security.enrich_course_text_gaps_v1(text[])', '5352bc7ea7bbf3ef00bd616f2897f2f4', '66d9dad4eb0d743b804097b1bf9d38d2'),
    ('security.course_description_machine_run_v1()', '452e3ae1ed2ab196865e2905ad2801e1', 'faa6dab1bfeef3464ba86fac11b34766'),
    ('security.data_delivery_cdesc_stages_v1()', 'd2a913a4d294f71fadf949bff6786f94', 'bf7c8c712273ae99b885e748ff58b998')
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
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
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

CREATE OR REPLACE FUNCTION security.course_description_machine_check_v1(p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; p catalogue.providers%rowtype; g pipeline.coverage_course_pages%rowtype; e pipeline.evidence_artifacts%rowtype; f pipeline.field_enrich_items%rowtype;
        sc pipeline.course_description_source_checks%rowtype;
        v_rule constant text := 'cdesc-machine-v1'; v_fid bigint; v_text text; v_md5 text; v_chk jsonb; v_pol text; v_sents jsonb; v_share numeric; v_win int; v_words text[]; v_dup record; v_other uuid; v_recheck text := 'not_run'; v_kind text;
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
end $function$;

CREATE OR REPLACE FUNCTION security.enrich_course_text_record_v1(p_item bigint, p_r jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.field_enrich_items%rowtype; g record; v_chk jsonb; v_text text; v_review uuid; v_pid uuid; v_n int := 0; x jsonb; it record;
        v_date date; v_kept jsonb := '[]'::jsonb; v_dl jsonb := '[]'::jsonb; v_why text; v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
        v_targets uuid[]; v_one uuid; v_kinds text[];
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  if i.id is null or i.course_id is null or i.field not in ('description', 'deadline') then return 'nothing'; end if;
  select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.captured_at into g
    from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.course_id = i.course_id;
  if g.provider_id is null or not security.coverage_identity_allowed(g.provider_id, g.identity_basis, i.field) then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit ' || i.field || ' for this country',
           value = p_r->'value', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  -- only the course's own page: the stored copy read is the copy bound to the course now
  if i.evidence_id is distinct from g.evidence_id then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the copy read is no longer the course''s bound page (it is read again with the new copy)', value = p_r->'value', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.course_id
               and l.field in (i.field, case i.field when 'deadline' then 'intake' else 'course_description' end, 'all')) then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'locked by hand', value = p_r->'value', updated_at = now() where id = i.id;
    return 'locked';
  end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = i.course_id;

  if i.field = 'description' then
    if exists (select 1 from catalogue.courses c where c.id = i.course_id and nullif(btrim(c.description), '') is not null) then
      update pipeline.field_enrich_items set state = 'skipped', reason = 'already filled', value = p_r->'value', updated_at = now() where id = i.id; return 'already';
    end if;
    v_chk := security.course_description_check_v1(i.course_id, p_r->'value');
    if not coalesce((v_chk->>'ok')::boolean, false) then
      update pipeline.field_enrich_items set state = 'skipped', value = coalesce(p_r->'value', '{}'::jsonb) || jsonb_build_object('check', v_chk),
             reason = left(case when v_chk->>'rule' = 'not_stated' then coalesce(nullif(p_r->>'reason', ''), 'the page does not state it')
                                else 'held: ' || (v_chk->>'rule') || ': ' || (v_chk->>'reason') end, 300), updated_at = now()
       where id = i.id;
      return case when v_chk->>'rule' = 'not_stated' then 'not_stated' else 'held' end;
    end if;
    v_text := v_chk->>'text';
    if security.course_description_trusted_v1(v_pid) then
      update catalogue.courses set description = v_text, updated_at = now() where id = i.course_id and nullif(btrim(description), '') is null;
      get diagnostics v_n = row_count;
      update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end, reason = case when v_n > 0 then null else 'already filled' end,
             value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'admitted', 'checks (provider''s first descriptions approved in Layer 4)'),
             quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
       where v_n > 0 and not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
      return case when v_n > 0 then 'filled' else 'already' end;
    end if;
    -- Layer 4 on first admission: at most enrich.course_description_pending_max of the provider's wait at once; the rest keep their reading
    if (select count(*) from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
         where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid)
       >= security.pipeline_num_v1('enrich.course_description_pending_max', 10) then
      update pipeline.field_enrich_items set state = 'skipped', reason = 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved',
             value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk), quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      return 'held_first_admission';
    end if;
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values ('course', i.course_id, 'course_description_first_read', g.evidence_id, jsonb_build_object('description', null),
            jsonb_build_object('description', v_text, 'item_id', i.id, 'source_url', g.url, 'checks', v_chk->'checks',
                               'sentences', (select jsonb_agg(jsonb_build_object('text', s->>'text', 'quote', s->>'quote') order by o) from jsonb_array_elements(p_r->'value'->'sentences') with ordinality e(s, o))),
            jsonb_build_object('source', 'course description reader', 'page', g.url, 'identity_basis', g.identity_basis),
            jsonb_build_object('item_id', i.id, 'model', p_r->>'model', 'prompt', p_r->>'prompt_version', 'worker', p_r->>'worker'),
            'pending', 'Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.',
            'CF-CHG-20260915-247')
    returning id into v_review;
    update pipeline.field_enrich_items set state = 'review', reason = null, value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'review_item_id', v_review),
           quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
    return 'review';
  end if;

  -- deadline: explicit dates only, tied to an intake the page names (or the course's only active intake)
  if not exists (select 1 from catalogue.course_intakes x where x.course_id = i.course_id and x.status = 'active') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'no active intake to hold a deadline', value = p_r->'value', updated_at = now() where id = i.id; return 'not_admitted';
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_r->'value'->'deadlines', '[]'::jsonb)) loop
    v_why := null; v_targets := '{}'; v_date := null;
    if x->>'kind' <> 'date' then v_why := coalesce(x->>'kind', 'not_stated');
    elsif not coalesce((x->>'on_page')::boolean, false) then v_why := 'quote_not_on_page';
    elsif coalesce(x->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then v_why := 'no_full_date';
    else
      begin v_date := (x->>'date')::date; exception when others then v_date := null; end;
      if v_date is null then v_why := 'no_full_date';
      elsif not security.course_deadline_in_quote_v1(v_date, x->>'quote') then v_why := 'date_not_in_quote';
      end if;
    end if;
    if v_why is null then
      if nullif(btrim(x->>'intake'), '') is null then
        select array_agg(ci.id) into v_targets from catalogue.course_intakes ci where ci.course_id = i.course_id and ci.status = 'active';
        if cardinality(v_targets) <> 1 then v_why := 'not_tied_to_one_intake'; v_targets := '{}'; end if;
      else
        select coalesce(array_agg(ci.id), '{}') into v_targets from catalogue.course_intakes ci
         where ci.course_id = i.course_id and ci.status = 'active' and security.course_deadline_intake_match_v1(ci.intake_label, ci.intake_year, x->>'intake');
        if cardinality(v_targets) = 0 then v_why := 'intake_not_matched'; end if;
      end if;
    end if;
    v_dl := v_dl || (x || jsonb_build_object('outcome', coalesce(v_why, 'kept'), 'intake_ids', to_jsonb(v_targets)));
    if v_why is null then
      foreach v_one in array v_targets loop v_kept := v_kept || jsonb_build_object('intake_id', v_one, 'date', v_date, 'quote', x->>'quote'); end loop;
    end if;
  end loop;
  -- per intake: one date only (two different dates for one intake are held), within the intake's window, never over a deadline held
  for it in select ci.id, ci.start_date, ci.intake_year, ci.application_deadline, array_agg(distinct (k->>'date')::date) dates, min(k->>'quote') quote
              from jsonb_array_elements(v_kept) k join catalogue.course_intakes ci on ci.id = (k->>'intake_id')::uuid group by 1, 2, 3, 4 loop
    if cardinality(it.dates) > 1 then v_dl := v_dl || jsonb_build_object('intake_ids', jsonb_build_array(it.id), 'outcome', 'conflicting_dates'); continue; end if;
    v_date := it.dates[1];
    if it.application_deadline is not null then continue; end if;
    if (it.start_date is not null and (v_date > it.start_date or v_date < it.start_date - v_max_before))
       or (it.start_date is null and it.intake_year is not null and (v_date < make_date(it.intake_year - 1, 1, 1) or v_date > make_date(it.intake_year, 12, 31))) then
      v_dl := v_dl || jsonb_build_object('intake_ids', jsonb_build_array(it.id), 'outcome', 'outside_intake_window', 'date', v_date); continue;
    end if;
    update catalogue.course_intakes set application_deadline = v_date where id = it.id and application_deadline is null;
    if found then v_n := v_n + 1; end if;
  end loop;
  v_kinds := array(select distinct d->>'outcome' from jsonb_array_elements(v_dl) d);
  update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end,
         value = jsonb_build_object('deadlines', v_dl, 'applied', v_n),
         quote = left(coalesce((select k->>'quote' from jsonb_array_elements(v_kept) k limit 1), p_r->>'quote', i.quote), 300),
         reason = case when v_n > 0 then null
                       when cardinality(v_kinds) = 0 or v_kinds <@ array['not_stated'] then coalesce(nullif(p_r->>'reason', ''), 'the page does not state it')
                       when v_kinds <@ array['rolling', 'not_stated'] then 'the page says applications are rolling (no date to hold)'
                       when 'kept' = any (v_kinds) then 'already filled or outside the intake''s dates'
                       else left('held: ' || array_to_string(v_kinds, ', '), 300) end,
         updated_at = now()
   where id = i.id;
  if v_n > 0 then
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  return case when v_n > 0 then 'filled' else 'not_admitted' end;
end $function$;

CREATE OR REPLACE FUNCTION security.course_description_promote_held_v1(p_provider uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_n int := 0; v_slots int; v_chk jsonb; v_review uuid; v_text text;
begin
  if p_provider is null or security.pipeline_num_v1('enrich.course_description_promote_held_on', 1) < 1 then return 0; end if;
  if security.course_description_trusted_v1(p_provider) then return 0; end if;
  v_slots := security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int
           - (select count(*) from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
               where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending' and c.provider_id = p_provider);
  if v_slots <= 0 then return 0; end if;
  for r in select e.id, e.course_id, e.value, e.quote, g.evidence_id, g.url, g.identity_basis, g.provider_id
             from pipeline.field_enrich_items e join pipeline.coverage_course_pages g on g.course_id = e.course_id
            where e.provider_id = p_provider and e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%'
              and nullif(btrim(e.value->>'text'), '') is not null and e.evidence_id is not distinct from g.evidence_id
            order by e.id
              for update of e skip locked loop
    exit when v_n >= v_slots;
    continue when not security.coverage_identity_allowed(r.provider_id, r.identity_basis, 'description');
    continue when exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('description', 'course_description', 'all'));
    continue when exists (select 1 from catalogue.courses c where c.id = r.course_id and nullif(btrim(c.description), '') is not null);
    continue when exists (select 1 from pipeline.layer4_review_items q where q.entity_type = 'course' and q.entity_id = r.course_id
                           and q.field_code = 'course_description_first_read' and q.status = 'pending');
    v_chk := security.course_description_check_v1(r.course_id, r.value);
    continue when not coalesce((v_chk->>'ok')::boolean, false);
    v_text := v_chk->>'text';
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values ('course', r.course_id, 'course_description_first_read', r.evidence_id, jsonb_build_object('description', null),
            jsonb_build_object('description', v_text, 'item_id', r.id, 'source_url', r.url, 'checks', v_chk->'checks',
                               'sentences', (select jsonb_agg(jsonb_build_object('text', s->>'text', 'quote', s->>'quote') order by o) from jsonb_array_elements(r.value->'sentences') with ordinality e(s, o))),
            jsonb_build_object('source', 'course description reader', 'page', r.url, 'identity_basis', r.identity_basis),
            jsonb_build_object('item_id', r.id, 'held_first_admission', true),
            'pending', 'Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.',
            'CF-CHG-20260915-247')
    returning id into v_review;
    update pipeline.field_enrich_items set state = 'review', reason = null, value = r.value || jsonb_build_object('review_item_id', v_review, 'promoted_from', 'held_first_admission'), updated_at = now()
     where id = r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION security.enrich_course_text_gaps_v1(p_fields text[])
 RETURNS TABLE(provider_id uuid, course_id uuid, field text, pri integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int;
        f text; v_room int; v_gmax int := security.pipeline_num_v1('enrich.course_description_pending_global_max', 0)::int;
begin
  foreach f in array array['description', 'deadline'] loop
    continue when not (f = any (coalesce(p_fields, '{}'::text[])));
    -- back-pressure (CF-247 C-DESC 8 Nov 2026): no new description readings while v_gmax descriptions already wait for a person (0 = off)
    continue when f = 'description' and v_gmax > 0
      and (select count(*) from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending') >= v_gmax;
    select v_cap - count(*) into v_room from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
     where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false);  -- fixed: the cap is a day's
    continue when coalesce(v_room, 0) <= 0;
    return query
      with miss as (
        select c.id cid, c.provider_id pid from catalogue.courses c
         where c.lifecycle_status = 'active'
           and case f when 'description' then nullif(btrim(c.description), '') is null else security.enrich_deadline_missing_v1(c.id) end
           -- read from the stored page only: the slice's rule (bound, or ambiguous with an identity proof, read)
           and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                         and g.read_status = 'read' and g.identity_basis is not null)),
      last as (
        select distinct on (e.course_id) e.course_id cid, e.state, e.updated_at, e.reason
          from pipeline.field_enrich_items e where e.field = f and e.course_id in (select m.cid from miss m) order by e.course_id, e.id desc)
      select m.pid, m.cid, f, case when l.state is null then 1
                                    when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at) then 0 else 2 end
        from miss m left join last l on l.cid = m.cid
       where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = m.cid and k.field in (f, 'all'))
         and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
         and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or l.updated_at < now() - make_interval(days => v_days)
              or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at))
         and not security.enrich_item_held_v1(m.cid, f)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.pid)
       order by 4, m.cid
       limit v_room;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION security.course_description_machine_run_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_a jsonb; v_b jsonb;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- one failure never stops the run: each part reports its own error
  begin v_a := security.course_description_machine_settle_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.course_description_machine_consumer_recheck_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('on', true, 'settle', v_a, 'consumer', v_b);
end $function$;

CREATE OR REPLACE FUNCTION security.data_delivery_cdesc_stages_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_top int := security.pipeline_num_v1('data_delivery.reasons_shown', 3)::int; -- derived: the existing Data Delivery setting, how many exact reasons a stream lists
begin
  return (
  with l4 as (select i.id, i.status, i.entity_id from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read'),
       led as (select a.course_id, a.review_item_id, a.outcome, a.reason_code, a.reason, a.created_at, a.withdrawn_at, a.consumer_check from pipeline.course_description_machine_admissions a),
       live_m as (select l.course_id, coalesce(l.consumer_check, 'not_checked') chk from led l where l.outcome = 'admitted' and l.withdrawn_at is null),
       declined as (select l.reason_code, l.reason, l.created_at from led l join l4 on l4.id = l.review_item_id where l.outcome = 'declined' and l4.status = 'pending'),
       top as (select d.reason_code code, count(*) n, (array_agg(d.reason order by d.created_at desc))[1] example from declined d group by 1 order by 2 desc, 1 limit v_top),
       described as (select c.id from catalogue.courses c where nullif(btrim(c.description), '') is not null),
       shown as (select d.course_id from search.course_documents d where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id) and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id)), -- served to the Website: every course document whose provider is not hidden and that Layer 4 does not block; the course's own publication_status is not what the Website reads
       held as (select count(*) filter (where f.reason like 'held\_first\_admission:%') behind_cap, count(*) filter (where f.reason like 'held: %') by_check
                  from pipeline.field_enrich_items f where f.field = 'description' and f.state = 'skipped'),
       zl as (select z.item ? 'description' has_key from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null order by z.seq desc limit 1)
  select jsonb_build_object(
    'known', true, 'counted_at', now(), 'unit', 'courses',
    'source', jsonb_build_object('proposals_from_a_stored_page', (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.evidence_id is not null)),
    'proposal', jsonb_build_object('waiting_in_layer4', (select count(*) from l4 where l4.status = 'pending'),
                                   'held_behind_provider_cap', (select behind_cap from held), 'held_by_a_check', (select by_check from held)),
    'validation', jsonb_build_object('not_yet_checked_by_machine', (select count(*) from l4 where l4.status = 'pending' and not exists (select 1 from led l where l.review_item_id = l4.id)),
                                     'declined_by_machine', (select count(*) from declined),
                                     'top_decline_reasons', coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'n', t.n, 'example', t.example) order by t.n desc, t.code) from top t), '[]'::jsonb)),
    'admitted', jsonb_build_object('by_machine', (select count(*) from live_m),
                                   'by_person', (select count(*) from l4 where l4.status in ('approved', 'edited_approved')
                                                    and not exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = l4.id and md.layer2_state->>'actor_kind' = 'machine')),
                                   'withdrawn', (select count(*) from led where outcome = 'admitted' and withdrawn_at is not null),
                                   'described_courses', (select count(*) from described),
                                   'described_other_route', (select count(*) from described d where d.id not in (select course_id from live_m) and d.id not in (select l4.entity_id from l4 where l4.status in ('approved', 'edited_approved')))),
    'consumers', jsonb_build_object('website_published', (select count(*) from described d where d.id in (select course_id from shown)),
                                    'unpublished_course', (select count(*) from described d where d.id not in (select course_id from shown)),
                                    'machine_readback', jsonb_build_object('matched', (select count(*) from live_m where chk = 'matched'), 'lag', (select count(*) from live_m where chk = 'lag'),
                                                                           'not_in_feed', (select count(*) from live_m where chk = 'not_in_feed'), 'error', (select count(*) from live_m where chk = 'error'),
                                                                           'not_checked', (select count(*) from live_m where chk not in ('matched', 'lag', 'not_in_feed', 'error'))),
                                    'zoho', coalesce((select case when zl.has_key then jsonb_build_object('known', false, 'reason', 'The Zoho course feed now carries a description field, but how many reach Zoho is not counted yet.')
                                                         else jsonb_build_object('known', false, 'reason', 'The latest course item in the Zoho course feed has no description field, so a course description does not reach Zoho. Nothing is counted for it.') end from zl),
                                                    jsonb_build_object('known', false, 'reason', 'The Zoho course feed holds no course item, so nothing is counted for it.'))))
  );
exception when others then
  -- a count that cannot be made is shown as such, never as 0, and does not stop the rest of Data Delivery
  return jsonb_build_object('known', false, 'reason', 'The stage counts could not be read: ' || sqlerrm);
end $function$;

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'))) <> '3bb5d62b5e86cd7c76707171e02a3ae5' then raise exception 'post-check: the restored security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb) does not match'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_check_v1(uuid)'))) <> '3e0fe24d762e7fc4348865ea09499690' then raise exception 'post-check: the restored security.course_description_machine_check_v1(uuid) does not match'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.enrich_course_text_record_v1(bigint,jsonb)'))) <> 'c52c1969a80f2d3db1d81a4e46a49cd9' then raise exception 'post-check: the restored security.enrich_course_text_record_v1(bigint,jsonb) does not match'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_promote_held_v1(uuid)'))) <> '1c990fb9c93b1841195160a0e9a712ae' then raise exception 'post-check: the restored security.course_description_promote_held_v1(uuid) does not match'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.enrich_course_text_gaps_v1(text[])'))) <> '5352bc7ea7bbf3ef00bd616f2897f2f4' then raise exception 'post-check: the restored security.enrich_course_text_gaps_v1(text[]) does not match'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_run_v1()'))) <> '452e3ae1ed2ab196865e2905ad2801e1' then raise exception 'post-check: the restored security.course_description_machine_run_v1() does not match'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.data_delivery_cdesc_stages_v1()'))) <> 'd2a913a4d294f71fadf949bff6786f94' then raise exception 'post-check: the restored security.data_delivery_cdesc_stages_v1() does not match'; end if;
end $p$;
