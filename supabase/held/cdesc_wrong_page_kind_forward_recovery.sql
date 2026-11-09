-- HELD (not a migration): forward recovery for 20261110100100 (the machine rule's wrong_page_kind decline), its one in-place edit: security.course_description_machine_check_v1.
-- Run only if the Platform Admin decides to take the decline back. It restores the function byte for byte (the live body, read 10 Nov 2026), guarded by the md5 of what is live now (the edited text,
-- 3e0fe24d762e7fc4348865ea09499690, or the original fca43249b1846aae9eae0df7fc83ecb4); a function that is neither stops with a message.

do $g$
declare v text := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_check_v1(uuid)'));
begin
  if v is null then raise exception 'security.course_description_machine_check_v1(uuid) is missing'; end if;
  if v not in ('3e0fe24d762e7fc4348865ea09499690', 'fca43249b1846aae9eae0df7fc83ecb4') then raise exception 'live security.course_description_machine_check_v1(uuid) differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.course_description_machine_check_v1(p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; p catalogue.providers%rowtype; g pipeline.coverage_course_pages%rowtype; e pipeline.evidence_artifacts%rowtype; f pipeline.field_enrich_items%rowtype;
        sc pipeline.course_description_source_checks%rowtype;
        v_rule constant text := 'cdesc-machine-v1'; v_fid bigint; v_text text; v_md5 text; v_chk jsonb; v_pol text; v_sents jsonb; v_share numeric; v_win int; v_words text[]; v_dup record; v_other uuid; v_recheck text := 'not_run';
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

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_machine_check_v1(uuid)'))) <> 'fca43249b1846aae9eae0df7fc83ecb4' then raise exception 'post-check: the restored security.course_description_machine_check_v1(uuid) does not match'; end if;
end $p$;
