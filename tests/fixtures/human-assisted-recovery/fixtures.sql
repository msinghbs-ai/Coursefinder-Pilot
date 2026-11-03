-- CF-247 human-assisted recovery: the decision's §8 lifecycles end to end, and the §2-§7 and §9 rules (run by run.sh after seed.sql).
\set ON_ERROR_STOP on
create or replace function pg_temp.as_user(p_uid text, p_rank int) returns void language sql as
  $f$ select set_config('fx.uid', coalesce(p_uid, ''), false), set_config('fx.rank', coalesce(p_rank::text, ''), false) $f$;
create or replace function pg_temp.iv(p_fact text, p_entity_like text default '%') returns pipeline.layer4_interventions language sql as
  $f$ select * from pipeline.layer4_interventions where missing_fact = p_fact and entity like p_entity_like order by id limit 1 $f$;
create or replace function pg_temp.act(p_id bigint, p_action text, p_value text, p_reason text default 'checked on the official site') returns jsonb language sql as
  $f$ select security.layer4_intervention_inbox_decide_v1(p_id::text, p_action, p_value, p_reason) $f$;

-- G0 nothing is raised while har.on is 0, or before automatic recovery has used its attempts
do $$
declare v jsonb; n int;
begin
  update pipeline.platform_toolset_settings set value = '0' where key = 'har.on';
  v := security.layer4_interventions_tick_v1();
  if v->>'held' <> 'har.on is 0' or exists (select 1 from pipeline.layer4_interventions) then raise exception 'G0: har.on 0 must hold everything (%)', v; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'har.on';
  v := security.layer4_intervention_raise_v1(jsonb_build_object('class', 'aer_source_missing', 'entity', 'x', 'attempts', 0));
  if (v->>'raised')::boolean then raise exception 'G0: raised before any automatic attempt'; end if;
  raise notice 'G0 ok: switched off holds; nothing is asked before automatic recovery has tried';
end $$;

-- L1 missing AER source URL (Deakin: the official site refused the free read) and the first run over everything held
do $$
declare v jsonb; i pipeline.layer4_interventions; w pipeline.work_items; n_l4 int := (select count(*) from pipeline.layer4_review_items);
begin
  v := security.layer4_interventions_tick_v1();
  raise notice 'L1 first run: %', v->'generated';
  i := pg_temp.iv('aer_source_missing', 'c5c5d225%');
  if i.id is null or i.status <> 'awaiting_input' or i.provider_id <> 'c5c5d225-3d4c-4e41-8275-78eddd261073' then raise exception 'L1: Deakin intervention missing (%)', i; end if;
  if jsonb_array_length(i.evidence->'attempts') < 2 or i.evidence->>'stored_copies' not like '%5106f65f%' then raise exception 'L1: evidence not prefilled (%)', i.evidence; end if;
  if i.required_input->>'ask' not like 'The official web address%' or i.recommended->>'action' <> 'provide_url' then raise exception 'L1: request (%)', i.required_input; end if;
  select * into w from pipeline.work_items where id = i.work_item_id;
  if w.stage <> 'awaiting_review' or w.lease_until is not null or w.next_eligible_at is not null or w.review_ref <> 'intervention:' || i.id then raise exception 'L1: work item must wait without lease (%)', w; end if;
  -- the other universities in the same run (other work continues), and the never-searched provider is not asked
  if (select count(*) from pipeline.layer4_interventions where lane in ('aer_source', 'aer_course')) <> 6 then
    raise exception 'L1: expected ACU, Deakin, JCU, CDU, UWA and Torrens (%)', (select array_agg(missing_fact || ':' || subject) from pipeline.layer4_interventions); end if;
  if exists (select 1 from pipeline.layer4_interventions where provider_id = '51000000-0000-4000-8000-000000000003') then raise exception 'L1: a provider never searched was asked'; end if;
  if (select count(*) from pipeline.layer4_review_items) <> n_l4 then raise exception 'L1: an intervention is not a Layer 4 review item (the AER 600 limit is untouched)'; end if;
  if (select stage from pipeline.work_items where lane = 'ai_extraction' and entity like 'c0000000-0000-4000-8000-000000000005%') <> 'eligible' then raise exception 'L1: unrelated work changed'; end if;
  -- an unchanged failure is never raised again
  v := security.layer4_interventions_tick_v1();
  if (select count(*) from pipeline.layer4_interventions) <> (select count(distinct (lane, entity, missing_fact)) from pipeline.layer4_interventions)
     or (v->'generated'->'aer_source'->>'raised_or_changed')::int <> 0 then raise exception 'L1: a second run raised again (%)', v; end if;
  if (select repeat_count from pipeline.layer4_interventions where id = i.id) <> 0 then null; end if;
  raise notice 'L1 ok: the missing fact is identified, the card is prefilled, the work waits without a lease; a second run raises nothing';
end $$;

-- L1 (cont.) the reviewer supplies the address; invalid input gets a specific request on the same item; the reader resumes; the result closes it
do $$
declare v jsonb; i pipeline.layer4_interventions; s record; ev int;
begin
  i := pg_temp.iv('aer_source_missing', 'c5c5d225%');
  perform pg_temp.as_user(null, null);
  begin perform security.layer4_intervention_resolve_v1(i.id, 'provide_url', '{"value": "https://www.deakin.edu.au/x", "reason": "found it"}'); raise exception 'L1: anonymous accepted';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 3);
  begin perform pg_temp.act(i.id, 'provide_url', 'https://www.deakin.edu.au/x'); raise exception 'L1: a curator (rank 3) was allowed';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(i.id, 'provide_url', 'https://studyabroad.example.com/deakin-entry');
  if (v->>'ok')::boolean or v->>'request' not like '%directory site%' then raise exception 'L1: a directory site was accepted (%)', v; end if;
  v := pg_temp.act(i.id, 'provide_url', 'https://www.monash.edu/entry');
  if (v->>'ok')::boolean or v->>'request' not like '%not on the provider%' then raise exception 'L1: another university''s site was accepted (%)', v; end if;
  i := pg_temp.iv('aer_source_missing', 'c5c5d225%');
  if i.status <> 'awaiting_input' or i.required_input->>'follow_up' not like '%not on the provider%' then raise exception 'L1: the same item must carry the new request (%)', i.required_input; end if;
  begin perform pg_temp.act(i.id, 'enter_value', '{}'); raise exception 'L1: an action the class does not offer was accepted';
  exception when others then if sqlerrm not like '%not offered%' then raise; end if; end;
  v := pg_temp.act(i.id, 'provide_url', 'https://www.deakin.edu.au/international-students/entry-requirements/academic');
  if not (v->>'ok')::boolean or v->'result'->'resume'->>'scheduled' <> 'true' then raise exception 'L1: valid input did not resume (%)', v; end if;
  select * into s from pipeline.entry_matrix_sources where provider_id = 'c5c5d225-3d4c-4e41-8275-78eddd261073';
  if s.status <> 'found' or s.found_via <> 'manual' then raise exception 'L1: the source must be attached for the existing reader (%)', s; end if;
  i := pg_temp.iv('aer_source_missing', 'c5c5d225%');
  if i.status <> 'resuming' or i.resumed_at is null or i.admitted_at is not null then raise exception 'L1: resuming, never admitted by the input (%)', i; end if;
  if (select stage from pipeline.work_items where id = i.work_item_id) <> 'eligible' then raise exception 'L1: the dependency must be resolved'; end if;
  if exists (select 1 from catalogue.provider_entry_matrix) then raise exception 'L1: an address is never approval to publish'; end if;
  if (select count(*) from pipeline.layer4_intervention_values where intervention_id = i.id and state = 'proposed') <> 1 then raise exception 'L1: provenance not recorded'; end if;
  if (select count(*) from pipeline.admin_control_events where area = 'layer4' and action = 'inbox_decide' and target = 'intervention:' || i.id) <> 3 then raise exception 'L1: every decision audited'; end if;
  select count(*) into ev from pipeline.layer4_intervention_events where intervention_id = i.id and action in ('insufficient', 'provide_url') and actor_label = 'operator@example.org' and role_rank = 4;
  if ev <> 3 then raise exception 'L1: reviewer identity on the audit (%)', ev; end if;
  -- not yet read: the job waits
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  if (pg_temp.iv('aer_source_missing', 'c5c5d225%')).status <> 'resuming' then raise exception 'L1: must wait for the read'; end if;
  -- the existing reader reads it and its first read goes to Layer 4; a person admits the rows there; the website shows them
  update pipeline.entry_matrix_sources set status = 'read', read_at = now() where id = s.id;
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values ('e0000000-0000-4000-8000-000000000009', 'provider', 'c5c5d225-3d4c-4e41-8275-78eddd261073', 'entry_matrix_first_run', 'pending');
  insert into pipeline.entry_matrix_runs(provider_id, source_id, state, review_item_id, updated_at) values ('c5c5d225-3d4c-4e41-8275-78eddd261073', s.id, 'done', 'e0000000-0000-4000-8000-000000000009', now());
  insert into catalogue.provider_entry_matrix(provider_id, status) values ('c5c5d225-3d4c-4e41-8275-78eddd261073', 'active');
  v := security.layer4_interventions_tick_v1();
  i := pg_temp.iv('aer_source_missing', 'c5c5d225%');
  if i.status <> 'resolved' or i.verified_outcome <> 'read_in_layer4' or i.admitted_at is null or i.published_at is null then raise exception 'L1: verified outcome (%)', i; end if;
  if (select stage from pipeline.work_items where id = i.work_item_id) <> 'done' then raise exception 'L1: the work item must succeed'; end if;
  raise notice 'L1 ok: invalid input returns a specific request on the same item; valid input attaches the source, resumes, and closes on the verified read, admission and publication';
end $$;

-- L2 rendered or inaccessible document (ACU names a PDF whose address could not be verified): the stronger-model step, validated; a failed read
-- returns to the reviewer; a second document succeeds; the class's integration issue opens and closes on the result
do $$
declare v jsonb; i pipeline.layer4_interventions; q bigint;
begin
  i := pg_temp.iv('aer_document_unverified', '030992c3%');
  if i.status <> 'awaiting_input' then raise exception 'L2: with the AI step off an interpretative item goes straight to the reviewer (%)', i.status; end if;
  -- switch the step on (as a person would, with a pinned model) and raise again with new evidence
  update pipeline.platform_toolset_settings set value = '1' where key in ('har.ai_escalate_on', 'ops.ai_diagnosis_on');
  update pipeline.platform_toolset_settings set value = to_jsonb('anthropic/claude-fixture-pinned'::text) where key = 'har.ai_escalation_model';
  update pipeline.layer4_interventions set status = 'resolved', closed_fingerprint = fingerprint where id = i.id;  -- closed earlier
  v := security.layer4_intervention_raise_v1(jsonb_build_object('class', 'aer_document_unverified', 'entity', i.entity, 'provider_id', i.provider_id, 'attempts', 1,
         'signature', 'unverified_link|new landing copy', 'evidence', jsonb_build_object('official_links', jsonb_build_array('https://www.acu.edu.au/study-at-acu/how-to-apply/international-students/international-undergraduate-students'))));
  i := pg_temp.iv('aer_document_unverified', '030992c3%');
  if i.status <> 'ai_pending' or i.reopen_count <> 1 or v->>'id' <> i.id::text then raise exception 'L2: a changed failure reopens the same item (%)', i; end if;
  v := security.har_ai_tick_v1();
  select (ai_analysis->>'request_id')::bigint into q from pipeline.layer4_interventions where id = i.id;
  if q is null or (select context->>'model' from pipeline.ops_ai_diagnosis_requests where id = q) <> 'anthropic/claude-fixture-pinned' then raise exception 'L2: one request on the pinned model (%)', v; end if;
  v := security.har_ai_tick_v1();
  if (select count(*) from pipeline.ops_ai_diagnosis_requests) <> 1 then raise exception 'L2: one request only'; end if;
  -- the answer: one invented address, one address the platform has seen in a stored copy, one off-site address
  insert into pipeline.evidence_artifacts(source_url, storage_path) values ('https://www.acu.edu.au/-/media/minimum-academic-entry-requirements.pdf', 'x');
  update pipeline.ops_ai_diagnosis_requests set state = 'answered', answered_at = now(), model = 'anthropic/claude-fixture-pinned',
         answer = '{"analysis": "the landing page links the PDF", "confidence": 0.8, "uncertainty": "the PDF year is not shown", "proposals": [
           {"kind": "url", "url": "https://www.acu.edu.au/invented/requirements.pdf", "confidence": 0.9},
           {"kind": "url", "url": "https://www.acu.edu.au/-/media/minimum-academic-entry-requirements.pdf", "confidence": 0.85},
           {"kind": "url", "url": "https://www.example.com/acu.pdf", "confidence": 0.95}]}' where id = q;
  v := security.har_ai_tick_v1();
  i := pg_temp.iv('aer_document_unverified', '030992c3%');
  if i.status <> 'awaiting_input' or i.recommended->'suggested'->>'url' <> 'https://www.acu.edu.au/-/media/minimum-academic-entry-requirements.pdf'
     or jsonb_array_length(i.ai_analysis->'refused') <> 2 or i.ai_analysis->>'uncertainty' is null then raise exception 'L2: only the evidenced address is suggested (%)', i.ai_analysis; end if;
  update pipeline.platform_toolset_settings set value = '0' where key in ('har.ai_escalate_on', 'ops.ai_diagnosis_on');
  -- the reviewer gives the document; the reader cannot read it; the same item comes back with what happened
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(i.id, 'attach_document', 'https://www.acu.edu.au/-/media/minimum-academic-entry-requirements.pdf');
  if not (v->>'ok')::boolean or v->'result'->'resume'->>'stored_copy' is null then raise exception 'L2: the stored copy is reused (%)', v; end if;
  update pipeline.layer4_interventions set integration_issue_id = security.har_class_issue_v1('aer_source', 'aer_document_unverified', 'fixture') where id = i.id;
  update pipeline.entry_matrix_sources set status = 'failed', error = 'pdf columns ambiguous' where url like '%minimum-academic-entry%';
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  i := pg_temp.iv('aer_document_unverified', '030992c3%');
  if i.status <> 'awaiting_input' or i.required_input->>'follow_up' not like '%could not be read (pdf columns ambiguous)%' or i.reopen_count <> 2 then raise exception 'L2: back to the reviewer with the reason (%)', i; end if;
  if (select stage from pipeline.work_items where id = i.work_item_id) <> 'awaiting_review' then raise exception 'L2: the work waits again'; end if;
  -- the same failed address with no new copy is refused up front
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  update pipeline.entry_matrix_sources set attempts = 3 where url like '%minimum-academic-entry%';
  delete from pipeline.evidence_artifacts where source_url like '%minimum-academic-entry%';
  v := pg_temp.act(i.id, 'attach_document', 'https://www.acu.edu.au/-/media/minimum-academic-entry-requirements.pdf');
  if (v->>'ok')::boolean or v->>'request' not like '%read before%' then raise exception 'L2: an address that failed every read is refused (%)', v; end if;
  v := pg_temp.act(i.id, 'attach_document', 'https://www.acu.edu.au/study-at-acu/entry-requirements-by-country.html');
  update pipeline.entry_matrix_sources set status = 'read' where url like '%by-country%';
  insert into pipeline.entry_matrix_runs(provider_id, source_id, state, updated_at)
  select provider_id, id, 'done', now() from pipeline.entry_matrix_sources where url like '%by-country%';
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  i := pg_temp.iv('aer_document_unverified', '030992c3%');
  if i.status <> 'resolved' or i.verified_outcome <> 'read_recorded' then raise exception 'L2: resolved on the read (%)', i; end if;
  if (select status from pipeline.integration_issues where id = i.integration_issue_id) <> 'closed' then raise exception 'L2: the class issue closes on the verified result'; end if;
  raise notice 'L2 ok: one pinned-model request; invented and off-site addresses refused; a failed read returns with its reason; the next document resumes and the issue closes';
end $$;

-- L3 ambiguous course identity (Torrens: a page shared with another programme)
do $$
declare v jsonb; i pipeline.layer4_interventions;
begin
  i := pg_temp.iv('aer_course_identity');
  if i.id is null or i.lane <> 'aer_course' or i.course_id <> 'c0000000-0000-4000-8000-000000000001' or i.resume_target->'work_item'->>'lane' <> 'aer_technical' then raise exception 'L3: raised on the parked item (%)', i; end if;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(i.id, 'confirm_identity', '044444Z');
  if (v->>'ok')::boolean or v->>'request' not like 'No active course%' then raise exception 'L3: an unknown course was accepted (%)', v; end if;
  v := pg_temp.act(i.id, 'confirm_identity', '099999A');
  if not (v->>'ok')::boolean then raise exception 'L3: the course code was refused (%)', v; end if;
  if (select stage from pipeline.work_items where lane = 'aer_technical' and entity = i.entity) <> 'eligible' then raise exception 'L3: the held item returns to its lane'; end if;
  -- the lane's technical check succeeds with the course confirmed
  perform security.work_item_report_v1('aer_technical', i.entity, 'l4_item', 'succeeded', '{}'::jsonb);
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  i := pg_temp.iv('aer_course_identity');
  if i.status <> 'resolved' or i.verified_outcome <> 'held_item_recovered' then raise exception 'L3: resolved (%)', i; end if;
  raise notice 'L3 ok: the course is confirmed against the same university, the held item resumes and the result closes the intervention';
end $$;

-- L4 missing scholarship eligibility (international unresolved), with the other two scholarship states
do $$
declare v jsonb; i pipeline.layer4_interventions; o pipeline.layer4_interventions; s pipeline.layer4_interventions;
begin
  i := pg_temp.iv('sch_international_unresolved');
  o := pg_temp.iv('sch_ownership_conflict');
  s := pg_temp.iv('sch_source_missing');
  if i.id is null or o.id is null or s.id is null then raise exception 'L4: the three scholarship states map onto interventions'; end if;
  if exists (select 1 from pipeline.layer4_interventions where provider_id = '51000000-0000-4000-8000-000000000002') then raise exception 'L4: a policy-excluded provider was asked'; end if;
  if s.recommended->'suggested'->>'url' <> 'https://www.boxuni.edu.au/scholarships' then raise exception 'L4: the register page is suggested (%)', s.recommended; end if;
  if o.assigned_to <> 'Platform Admin (provider identity)' then raise exception 'L4: ownership is the Platform Admin''s'; end if;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(i.id, 'confirm_scope', 'international');
  if (v->>'ok')::boolean or v->>'request' not like '%sentence from the official page%' then raise exception 'L4: no quotation must be refused (%)', v; end if;
  v := pg_temp.act(i.id, 'confirm_scope', '{"audience": "international", "quote": "International students commencing in 2027 are eligible to apply for this award."}');
  if not (v->>'ok')::boolean or (select requested_at from pipeline.scholarship_page_candidates where id = 501) is null then raise exception 'L4: Read again must be requested (%)', v; end if;
  begin perform pg_temp.act(o.id, 'confirm_identity', 'Box University'); raise exception 'L4: ownership decided below Platform Admin';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000006', 6);
  v := pg_temp.act(o.id, 'confirm_identity', 'Box University');
  if not (v->>'ok')::boolean then raise exception 'L4: ownership (%)', v; end if;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(s.id, 'provide_url', 'https://www.boxuni.edu.au/scholarships');
  if (select source || status from pipeline.scholarship_listing_pages where provider_id = s.provider_id) <> 'manualwaiting' then raise exception 'L4: listing source (%)', v; end if;
  -- the readers run: the candidate is read and admitted (by the existing admission), the coverage case moves; the listing is read
  update pipeline.scholarship_page_candidates set admitted_at = now() where id = 501;
  update pipeline.scholarship_coverage_items set state = 'published_verified' where item_key = 'cand:501';
  update pipeline.scholarship_listing_pages set status = 'read', read_at = now() where provider_id = s.provider_id;
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  i := pg_temp.iv('sch_international_unresolved'); o := pg_temp.iv('sch_ownership_conflict'); s := pg_temp.iv('sch_source_missing');
  if i.status <> 'resolved' or i.admitted_at is null or o.status <> 'resolved' or o.verified_outcome <> 'decision_recorded' or s.status <> 'resolved' or s.verified_outcome <> 'listing_read' then
    raise exception 'L4: resolved (% / % / %)', i.status, o.verified_outcome, s.verified_outcome; end if;
  raise notice 'L4 ok: the audience needs a quotation, Read again resumes the page, admission stays with the existing checks; ownership needs the Platform Admin';
end $$;

-- L5 conflicting tuition evidence (the fee lane raises its own intervention through the contract)
do $$
declare v jsonb; i pipeline.layer4_interventions;
begin
  v := security.layer4_intervention_raise_v1(jsonb_build_object('class', 'fee_evidence_conflict', 'entity', 'c0000000-0000-4000-8000-000000000004', 'provider_id', '51000000-0000-4000-8000-000000000003',
         'course_id', 'c0000000-0000-4000-8000-000000000004', 'field', 'tuition', 'attempts', 2, 'signature', '38,000 AUD 2027 vs 41,500 AUD 2027',
         'evidence', jsonb_build_object('conflicts', jsonb_build_array('course page: 38,000 AUD 2027', 'fee PDF: 41,500 AUD 2027'))));
  i := pg_temp.iv('fee_evidence_conflict');
  if i.status <> 'awaiting_input' or jsonb_array_length(i.evidence->'conflicts') <> 2 then raise exception 'L5: raised with the conflict (%)', i; end if;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(i.id, 'correct_value', '{"amount": "41500", "currency": "aud", "year": ' || extract(year from now())::int || ', "basis": "annual", "quote": "International tuition fee 2027: A$41,500 per year", "url": "https://www.feeuni.edu.au/fees.pdf"}');
  if (v->>'ok')::boolean or v->>'request' not like '%three-letter%' then raise exception 'L5: field rules (%)', v; end if;
  v := pg_temp.act(i.id, 'correct_value', '{"amount": "41500", "currency": "AUD", "year": ' || extract(year from now())::int || ', "basis": "annual", "quote": "International tuition fee 2027: A$41,500 per year", "url": "https://www.feeuni.edu.au/fees.pdf"}');
  if not (v->>'ok')::boolean then raise exception 'L5: valid fee refused (%)', v; end if;
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  if (pg_temp.iv('fee_evidence_conflict')).status <> 'resuming' then raise exception 'L5: the proposal waits for the fee lane'; end if;
  update pipeline.layer4_intervention_values set state = 'admitted', state_at = now(), state_detail = '{"published": true}' where intervention_id = i.id;
  v := security.layer4_interventions_tick_v1();
  i := pg_temp.iv('fee_evidence_conflict');
  if i.status <> 'resolved' or i.admitted_at is null or i.published_at is null then raise exception 'L5: admitted by the lane, then resolved (%)', i; end if;
  raise notice 'L5 ok: the fee is checked like an extracted value, is a proposal, and closes only when the fee lane admits it';
end $$;

-- L6 incomplete intake: the lane refuses the first answer; the same item returns with the lane's reason; the second is admitted
do $$
declare v jsonb; i pipeline.layer4_interventions; y int := extract(year from now())::int + 1;
begin
  perform security.layer4_intervention_raise_v1(jsonb_build_object('class', 'intake_incomplete', 'entity', 'c0000000-0000-4000-8000-000000000005', 'provider_id', '51000000-0000-4000-8000-000000000003',
           'course_id', 'c0000000-0000-4000-8000-000000000005', 'field', 'intakes', 'attempts', 3, 'signature', 'no commencement found in 3 reads'));
  i := pg_temp.iv('intake_incomplete');
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(i.id, 'enter_value', '{"commencement": ["' || y || '-02-23"], "deadline": "' || y || '-03-30", "quote": "Semester 1 starts 23 February; apply by 30 November", "url": "https://www.feeuni.edu.au/dates"}');
  if (v->>'ok')::boolean or v->>'request' not like '%deadline must not be after%' then raise exception 'L6: date rule (%)', v; end if;
  v := pg_temp.act(i.id, 'enter_value', '{"commencement": ["' || y || '-02-23"], "deadline": "' || (y - 1) || '-11-30", "quote": "Semester 1 starts 23 February; apply by 30 November", "url": "https://www.feeuni.edu.au/dates"}');
  if not (v->>'ok')::boolean then raise exception 'L6: valid dates refused (%)', v; end if;
  update pipeline.layer4_intervention_values set state = 'refused', state_detail = '{"reason": "the page is the 2025 calendar"}' where intervention_id = i.id;
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  i := pg_temp.iv('intake_incomplete');
  if i.status <> 'awaiting_input' or i.required_input->>'follow_up' not like '%refused the value: the page is the 2025 calendar%' then raise exception 'L6: back with the lane''s reason (%)', i; end if;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  v := pg_temp.act(i.id, 'enter_value', '{"commencement": ["' || y || '-02-23", "' || y || '-07-20"], "deadline": "' || (y - 1) || '-11-30", "quote": "Semester 1 starts 23 February; Semester 2 starts 20 July", "url": "https://www.feeuni.edu.au/dates/current"}');
  update pipeline.layer4_intervention_values set state = 'admitted' where intervention_id = i.id and state = 'proposed';
  perform pg_temp.as_user(null, null);
  v := security.layer4_interventions_tick_v1();
  if (pg_temp.iv('intake_incomplete')).status <> 'resolved' then raise exception 'L6: resolved'; end if;
  raise notice 'L6 ok: dates are checked, a refusal by the intake lane returns the same item with its reason, the corrected dates are admitted by the lane';
end $$;

-- R1 recheck, escalation, return to technical, reject evidence, not published, the open limit, and the Inbox functions
do $$
declare v jsonb; i pipeline.layer4_interventions; n int; c jsonb; p jsonb; d jsonb;
begin
  -- JCU: a source gets read by another route; the waiting item closes without a person
  insert into pipeline.entry_matrix_sources(provider_id, url, found_via, status) values ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'https://www.jcu.edu.au/requirements.pdf', 'search', 'read');
  update pipeline.layer4_interventions set next_action_at = now() - interval '1 minute' where missing_fact = 'aer_rendered_only';
  v := security.layer4_interventions_tick_v1();
  if (pg_temp.iv('aer_rendered_only')).status <> 'auto_resolved' then raise exception 'R1: recheck must close a cleared failure'; end if;
  -- UWA unanswered past its escalation time: one issue for the class, once
  update pipeline.layer4_interventions set escalate_at = now() - interval '1 minute' where missing_fact = 'aer_read_held';
  v := security.layer4_interventions_tick_v1();
  v := security.layer4_interventions_tick_v1();
  if (select count(*) from pipeline.integration_issues where fingerprint = 'har:aer_source:aer_read_held') <> 1 or (pg_temp.iv('aer_read_held')).escalated_at is null then raise exception 'R1: escalated once'; end if;
  -- the Inbox functions: counts, a compact page, lazy detail with the caller's allowed actions
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000004', 4);
  c := security.layer4_intervention_inbox_counts_v1();
  p := security.layer4_intervention_inbox_page_v1('{"limit": 1}');
  if (c->>'n')::int < 2 or jsonb_array_length(p->'items') <> 1 or p->'items'->0 ? 'evidence' then raise exception 'R1: counts and a compact page (% / %)', c, p; end if;
  v := security.layer4_intervention_inbox_page_v1(jsonb_build_object('limit', 50, 'after_at', p->'items'->0->>'created_at', 'after_ref', p->'items'->0->>'ref'));
  if jsonb_array_length(v->'items') <> (c->>'n')::int - 1 then raise exception 'R1: keyset paging reaches every item once'; end if;
  d := security.layer4_intervention_inbox_detail_v1((pg_temp.iv('aer_read_held')).id::text);
  if not (d ? 'issue' and d ? 'evidence' and d ? 'recommended' and d ? 'resolution') then raise exception 'R1: the four sections (%)', d; end if;
  if (select count(*) from jsonb_array_elements(d->'resolution'->'actions')) <> 4 then raise exception 'R1: only the class''s actions (%)', d->'resolution'->'actions'; end if;
  -- return to technical recovery and reject evidence
  i := pg_temp.iv('aer_read_held');
  v := pg_temp.act(i.id, 'reject_evidence', null, 'the held rows are a reader defect');
  if (pg_temp.iv('aer_read_held')).status <> 'awaiting_input' or (pg_temp.iv('aer_read_held')).ai_analysis->'rejected_by_reviewer' is null then raise exception 'R1: reject keeps it waiting'; end if;
  v := pg_temp.act(i.id, 'return_technical', null, 'reader fix B2 pending');
  if (pg_temp.iv('aer_read_held')).status <> 'returned_technical' then raise exception 'R1: return to technical'; end if;
  -- the unchanged failure is not asked again; a changed one reopens the same item
  v := security.layer4_interventions_tick_v1();
  if (pg_temp.iv('aer_read_held')).status <> 'returned_technical' then raise exception 'R1: an unchanged failure came back'; end if;
  update pipeline.aer_provider_coverage set runs_held = 2, last_run_id = 99 where provider_id = '9109fe0c-9f44-4e2d-a136-eb00dec24701';
  v := security.layer4_interventions_tick_v1();
  if (pg_temp.iv('aer_read_held')).status <> 'awaiting_input' or (pg_temp.iv('aer_read_held')).id <> i.id then raise exception 'R1: a changed failure reopens the same item'; end if;
  -- not published needs rank 5 and an official page
  i := pg_temp.iv('aer_empty_read');
  begin perform pg_temp.act(i.id, 'confirm_not_published', 'https://www.cdu.edu.au/x'); raise exception 'R1: rank 4 confirmed not published';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000006', 5);
  v := pg_temp.act(i.id, 'confirm_not_published', 'https://www.cdu.edu.au/international/how-apply/entry-requirements', 'only a university-wide rule is published');
  if (pg_temp.iv('aer_empty_read')).status <> 'not_published' then raise exception 'R1: not published'; end if;
  -- the open limit: a full lane raises nothing new
  perform pg_temp.as_user(null, null);
  update pipeline.platform_toolset_settings set value = '1' where key = 'har.open_max_per_lane';
  v := security.layer4_intervention_raise_v1(jsonb_build_object('class', 'aer_source_missing', 'entity', 'b0000000-0000-4000-8000-00000000000f', 'attempts', 5, 'signature', 'z'));
  if (v->>'raised')::boolean or v->>'reason' not like '%open limit%' then raise exception 'R1: open limit (%)', v; end if;
  update pipeline.platform_toolset_settings set value = '150' where key = 'har.open_max_per_lane';
  raise notice 'R1 ok: recheck closes, escalation once, Inbox counts/page/detail, return and reject audited, unchanged not re-asked, changed reopens, rank 5 for not published, open limit';
end $$;

-- M §9 metrics in the operations report section; nothing admitted by the contract itself
do $$
declare r jsonb; a jsonb;
begin
  r := security.layer4_intervention_report_v1();
  select x into a from jsonb_array_elements(r->'workstreams') x where x->>'workstream' = 'AER';
  if (a->>'human_resolved')::int < 4 or (a->>'resumed')::int < 3 or (a->>'admitted')::int < 1 or (a->>'published')::int < 1 or (a->>'automatically_resolved')::int <> 1
     or a->>'avg_minutes_to_resume' is null or a->>'recovery_success_rate' is null then raise exception 'M: AER row (%)', a; end if;
  if jsonb_array_length(r->'workstreams') <> 4 then raise exception 'M: four workstreams (%)', r; end if;
  if position('human_assisted_recovery' in pg_get_functiondef('security.ops_report_v1(integer)'::regprocedure)) = 0 then raise exception 'M: the ops report carries the section'; end if;
  if exists (select 1 from pipeline.layer4_intervention_values where state = 'admitted' and lane in ('aer_source', 'aer_course', 'sch_coverage')) then raise exception 'M: nothing admitted by the contract'; end if;
  if security.pipeline_num_v1('har.ai_escalate_on', 0) <> 0 then raise exception 'M: AI step off again'; end if;
  raise notice 'M ok: %', r->'workstreams';
end $$;
