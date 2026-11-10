-- CF-247 F-AER.04 rule aer-machine-v1, correction from its first shadow run (Integration Controller, 11 Nov 2026 00:0x AEDT; within Platform Admin decision 10 Nov 2026, AER recovery pack decision 1).
-- Evidence (production, read only): the first shadow run declined all 60 items it looked at as page_changed_since_read. In every case the course is still bound to the SAME address;
--   the page was captured again on 2 Nov 2026 and its raw-copy hash differs (pages carry per-day tokens), while the read was taken from the 4-29 Oct copy of that address.
--   The rule treated a re-capture of the same page as a different page. History check: the row rules agree with all 498 human decisions (302 would admit, all approved by a person; 0 disagreements).
-- Change (one function, md5-guarded, created by 20261111020000): a different stored copy of the SAME bound address passes when the read's copy is inside the platform's existing
--   freshness period for entry sources (aer.stale_source_days, 90 days, set 2 Nov 2026 under AER mandate section 11); a different address still declines (page_changed_since_read),
--   and a copy older than the period declines as read_copy_stale. The re-capture is recorded in the checks. Nothing else changes; the mode stays shadow.
-- Replaces: security.aer_machine_check_v1 (same name; md5-guarded edit). Retires: nothing.

do $g$
begin
  if md5(pg_get_functiondef('security.aer_machine_check_v1(uuid)'::regprocedure)) <> '19f394ec148d9d1452d5845945d72da1' then
    raise exception 'security.aer_machine_check_v1 differs from the version created by 20261111020000';
  end if;
end $g$;

create or replace function security.aer_machine_check_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; g pipeline.coverage_course_pages%rowtype; v_gate jsonb; v_ev pipeline.evidence_artifacts%rowtype; v_bev pipeline.evidence_artifacts%rowtype;
        v_conf numeric := security.pipeline_num_v1('aer.machine_min_confidence', 0.8); v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int;
        v_audit numeric := security.pipeline_num_v1('aer.machine_audit_pct', 5); v_n int; v_bad int; v_bucket int; v_checks jsonb := '{}'::jsonb;
  function_fail constant text := 'A person decides in Layer 4.';
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_entry_first_read' then
    return jsonb_build_object('ok', false, 'rule', 'not_a_course_entry_read', 'reason', 'Only first course entry reads are in scope.', 'next_action', function_fail);
  end if;
  if i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'item_not_pending', 'reason', 'The item is ' || i.status || '.', 'next_action', 'Nothing to do.'); end if;
  if i.claimed_at is not null and i.claimed_at > now() - make_interval(mins => 60) then -- fixed: a person who opened the item in the last hour keeps it
    return jsonb_build_object('ok', false, 'rule', 'claimed_by_person', 'reason', 'A person opened this item in the last hour.', 'next_action', 'The person decides; the rule looks again later.', 'transient', true);
  end if;
  select * into c from catalogue.courses where id = i.entity_id;
  if c.id is null or c.lifecycle_status <> 'active' then return jsonb_build_object('ok', false, 'rule', 'course_not_active', 'reason', 'The course is not active.', 'next_action', function_fail); end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id) then
    return jsonb_build_object('ok', false, 'rule', 'provider_hidden', 'reason', 'The provider is hidden.', 'next_action', function_fail);
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('entry_requirements', 'all')) then
    return jsonb_build_object('ok', false, 'rule', 'manual_lock', 'reason', 'The course''s entry requirements are locked by a person.', 'next_action', function_fail);
  end if;
  -- no earlier person's rejection or return of an entry read for this course (conflicting evidence goes to a person)
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_id = c.id and o.field_code = 'course_entry_first_read' and o.id <> i.id
               and o.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')) then
    return jsonb_build_object('ok', false, 'rule', 'earlier_rejection', 'reason', 'A person rejected or returned an earlier entry read of this course.', 'next_action', function_fail);
  end if;
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_id = c.id and o.field_code = 'course_entry_first_read' and o.status = 'pending' and o.id <> i.id) then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_waiting', 'reason', 'Another entry read of this course is also waiting.', 'next_action', function_fail);
  end if;
  if exists (select 1 from catalogue.course_entry_requirements x where x.course_id = c.id and x.status = 'active') then
    return jsonb_build_object('ok', false, 'rule', 'active_rows_exist', 'reason', 'The course already has active entry requirements; replacing them is a person''s decision.', 'next_action', function_fail);
  end if;
  if exists (select 1 from pipeline.aer_machine_admissions m where m.course_id = c.id and m.outcome = 'withdrawn') then
    return jsonb_build_object('ok', false, 'rule', 'withdrawn_awaiting_person', 'reason', 'A machine admission of this course was withdrawn.', 'next_action', function_fail);
  end if;
  -- source identity and provenance: the course's current bound page, an identity basis admitted for entry requirements, and the read taken from that page's content
  select * into g from pipeline.coverage_course_pages p where p.course_id = c.id and p.status = 'bound' order by p.bound_at desc nulls last limit 1;
  if g.course_id is null then return jsonb_build_object('ok', false, 'rule', 'no_bound_page', 'reason', 'The course has no bound course page now.', 'next_action', function_fail); end if;
  if not security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements') then
    return jsonb_build_object('ok', false, 'rule', 'identity_not_admitted', 'reason', format('The page is matched to the course by %s, which is not admitted for entry requirements.', coalesce(g.identity_basis, 'no basis')), 'next_action', function_fail);
  end if;
  select * into v_ev from pipeline.evidence_artifacts where id = i.evidence_id;
  select * into v_bev from pipeline.evidence_artifacts where id = g.evidence_id;
  if v_ev.id is null or v_ev.storage_path is null then return jsonb_build_object('ok', false, 'rule', 'evidence_missing', 'reason', 'The stored page the read came from is missing.', 'next_action', function_fail); end if;
  -- the read's stored page must be the course's bound page: the same stored copy, the same content, or (the bound page captured again since) the same address
  -- with the read's copy still inside the platform's freshness period for entry sources (aer.stale_source_days, 90; a re-capture changes the raw hash every day)
  if i.evidence_id is distinct from g.evidence_id and (v_ev.content_hash is null or v_ev.content_hash is distinct from v_bev.content_hash) then
    if v_bev.id is null or v_ev.source_url is distinct from v_bev.source_url then
      return jsonb_build_object('ok', false, 'rule', 'page_changed_since_read', 'reason', 'The course is now bound to a different page from the one this read was taken from.', 'next_action', 'A person decides, or the read is replaced by a read of the current page.');
    end if;
    if v_ev.captured_at < now() - make_interval(days => security.pipeline_num_v1('aer.stale_source_days', 90)::int) then
      return jsonb_build_object('ok', false, 'rule', 'read_copy_stale', 'reason', format('The read was taken from a copy captured %s, older than the freshness period for entry sources.', v_ev.captured_at::date), 'next_action', 'A person decides, or the read is replaced by a read of the current page.');
    end if;
    v_checks := v_checks || jsonb_build_object('recaptured_since_read', true, 'read_copy_captured_at', v_ev.captured_at, 'bound_copy_captured_at', v_bev.captured_at);
  end if;
  v_checks := v_checks || jsonb_build_object('identity_basis', g.identity_basis, 'source_url', v_ev.source_url, 'content_hash', v_ev.content_hash, 'evidence_id', v_ev.id);
  -- the rows: at least one, each with an exact quote (verified on the page by the reader), enough confidence, from this item's evidence
  select count(*), count(*) filter (where coalesce(length(btrim(x.quote)), 0) < v_qmin or coalesce(x.confidence, 0) < v_conf or x.evidence_id is distinct from i.evidence_id)
    into v_n, v_bad
    from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = i.id::text and x.status = 'proposed';
  if v_n = 0 then return jsonb_build_object('ok', false, 'rule', 'no_rows', 'reason', 'The read has no waiting rows.', 'next_action', function_fail); end if;
  if v_bad > 0 then
    return jsonb_build_object('ok', false, 'rule', 'row_unsupported', 'reason', format('%s of %s waiting rows lack an exact quote of %s characters, confidence %s or this read''s evidence.', v_bad, v_n, v_qmin, v_conf), 'next_action', function_fail, 'checks', v_checks);
  end if;
  -- completeness: E13 + D-R3 (the same gate a person's approval runs)
  v_gate := security.course_entry_gate_v1(i.id, '{}'::uuid[]);
  if v_gate is null or not coalesce((v_gate->>'complete')::boolean, false) then
    return jsonb_build_object('ok', false, 'rule', 'gate_incomplete', 'reason', coalesce((select string_agg(w, '; ') from jsonb_array_elements_text(v_gate->'reasons') w), 'The completeness gate did not pass.'),
                              'next_action', 'Technical recovery (aer-replay, corrected reads) or a person in Layer 4.', 'checks', v_checks);
  end if;
  v_checks := v_checks || jsonb_build_object('rows', v_n, 'gate', 'E13 complete', 'min_confidence', v_conf, 'min_quote_chars', v_qmin);
  -- random audit sample: deterministic per item, so a re-run gives the same answer
  v_bucket := (('x' || substr(md5(i.id::text || ':aer-machine-v1'), 1, 8))::bit(32)::bigint % 100)::int; -- fixed: 100 buckets for a per-cent share
  if v_bucket < v_audit then
    return jsonb_build_object('ok', false, 'rule', 'audit_sample', 'audit', true, 'reason', format('Random audit sample (%s%%): the rule would admit this read; a person checks it.', v_audit), 'next_action', function_fail, 'checks', v_checks);
  end if;
  return jsonb_build_object('ok', true, 'rule', 'aer-machine-v1', 'course_id', c.id, 'provider_id', c.provider_id, 'checks', v_checks);
end $f$;
comment on function security.aer_machine_check_v1(uuid) is 'CF-247 F-AER.04 rule aer-machine-v1 (read only): whether a waiting first course entry read is complete and source-proved enough for machine admission. The first failing check names the rule, the reason and the next action. A random audit sample (aer.machine_audit_pct) is returned as audit_sample. A re-capture of the same bound address passes inside aer.stale_source_days (20261111030000).';
revoke all on function security.aer_machine_check_v1(uuid) from public, anon, authenticated;
