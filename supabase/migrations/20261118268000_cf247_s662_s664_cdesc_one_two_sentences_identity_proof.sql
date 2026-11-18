-- CF-247 S1-Courses s662 and s664 (Platform Admin 18 Nov 2026, chat S1-Courses, spec block s660 to s669): the course description reader writes 1 to 2
-- sentences, the machine rule admits a description whose own page proves the course, the provider's first-description hold is off, and the Layer 4
-- course description card explains each hold in plain English with four purpose-built decisions. Worker coverage-sweep v1.0.23 ships in the same change.
-- Found on Layer 4 (Ara Institute of Canterbury, New Zealand Diploma in Applied Science (Level 5)) and read live 18 Nov 2026 21:15 AEDT (rolled-back probe):
-- 666 course descriptions wait (identity margin thin 451, binding ambiguous 143, refused word 44, evidence moved 15, wrong page kind 13), 2.96 sentences
-- each on average; of the 451 held on the margin, the binder proved the page by the course's own CRICOS code 161, NZQA code 9, exact title 172 (degree
-- name 58, title and level 40, field and award 7, adapter title 4 stay with a person). Only 2 readings wait behind the first-description hold
-- (enrich.course_description_review_first is 100,000, so no provider is ever "trusted"); the card still told every item it was "one of the provider's
-- first course descriptions".
--   1. Prompt cdesc-source-grounded-v4 is released: security.cdesc_prompt_version_v1 returns it (md5-guarded), the course_description route names it and
--      the prompt registry holds it verbatim in shadow (v3 retired there, row kept). v4 is v3 with its length line replaced: 1 to 2 sentences, never
--      more than 2, about 180 to 360 characters, the academic focus, core skills and (only where a cited span states them) career outcomes, and no
--      sentence for intake dates, campus names or addresses, fees, or duration and study load. Quote grounding per sentence is unchanged.
--   2. Settings: enrich.course_description_max_sentences 4 -> 2 and enrich.course_description_max_chars 700 -> 360 (the live check, stated to the model).
--   3. Identity proof (setting enrich.course_description_identity_proof_on, new, 1): in cdesc-machine-v2 the 0.1 margin does not apply when the page's
--      proof is the course's own CRICOS or NZQA code, or its exact title (or an address whose last part is that title) that no other active course of
--      the provider shares, and no other course of the provider is bound to the same address or stored copy. Every other check is unchanged.
--   4. First-description hold (setting enrich.course_description_first_hold_on, new, 0): a checked reading goes to Layer 4 at once and the machine rule
--      decides it; held readings are promoted without the provider's place limit. The card's reason says what really happens.
--   5. Layer 4 › Inbox, course descriptions: the item detail carries the machine rule's latest reason, the page binding and the limits (for the
--      plain-English "Why this is held" box); two new choices: Re-read (1-2 sentences) supersedes the item and marks its reading reread: (the gap queue
--      reads the stored page again with v4; the course is not marked bad), and Approve all verified for provider admits, after the person confirms the
--      count, every waiting description of the provider read from its own page (CRICOS, NZQA or exact title) whose sentences all pass the live check.
-- How the 666 clear: the two settings change the machine rule's policy stamp, so the next settle run looks at every decline again; the v3 readings now
-- fail the 2-sentence limit and are declined, then security.cdesc_prompt_supersede_v1 supersedes them and the gap queue reads each stored page again with
-- v4 (no Firecrawl), and the new reading is admitted by the machine rule where its page proves the course. No overwrite: a course that holds a description
-- is never written (unchanged).
-- Each function edit is guarded by the md5 of the live body (pg_proc.prosrc, read 18 Nov 2026 21:10 AEDT) before and after.
-- G1: no new job. G2: two new settings with label, range, unit and used_by; two values moved with a reason. G3: no consumer API object is read or changed
-- (security.consumer_api_check_v1() before and after); no new table or function. AER v1 untouched.
-- Replaces: security.cdesc_prompt_version_v1(), security.course_description_machine_check_v1(uuid), security.enrich_course_text_record_v1(bigint,jsonb),
--   security.course_description_promote_held_v1(uuid), security.layer4_inbox_kinds_v1(), security.layer4_inbox_items_v2(uuid,text,text[],boolean),
--   public.admin_layer4_inbox(text,jsonb) (same names and signatures; md5-guarded edits in place).
-- Retires: the course_description prompt registry row cdesc-source-grounded-v3 (status retired; the row is kept). Nothing is dropped or deleted.

set local lock_timeout = '5s';

select set_config('cf247.s662_api_before', (security.consumer_api_check_v1() - 'checked_at')::text, true);
select set_config('cf247.s662_fn_before', (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'security', 'pipeline', 'api')), true);

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[], p_counts int[]) returns text language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_def text; v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig::regprocedure), chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> p_counts[i] then raise exception '%: edit % must match % time(s), found %', p_sig, i, p_counts[i], v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '%: body md5 after the edit is %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': edited';
end $f$;

-- 1 to 5: the seven function edits
select pg_temp.edit_all('security.cdesc_prompt_version_v1()', '46449a8715ab34d3826ec80dc9e1724b', '73f9c9cf6bec7216d20f790edcc409a1',
  array[
    $o$'cdesc-source-grounded-v3'$o$],
  array[
    $n$'cdesc-source-grounded-v4'$n$],
  array[1]);

select pg_temp.edit_all('security.course_description_machine_check_v1(uuid)', '1be689ae7ed55af7899088257c35e331', 'b0227cfb868d9e1d56c9d1056adbbd98',
  array[
    $o$v_prov jsonb; v_many boolean := false;$o$,
    $o$  if g.basis = 'ai_match' or (g.score is not null and g.runner_up is not null and g.score - g.runner_up < 0.1
$o$,
    $o$                                                                                                                            or (g2.evidence_id is not null and g2.evidence_id = g.evidence_id))))) then$o$,
    $o$'binding', g.status, 'policy', 'ok'))$o$],
  array[
    $n$v_prov jsonb; v_many boolean := false; v_proof boolean := false; v_slug text;$n$,
    $n$  -- s662 (CF-247 S1-Courses, Platform Admin 18 Nov 2026): identity proof. The margin judges how the page was FOUND; it does not apply when what the binder
  -- PROVED after reading the page is the course's own CRICOS or NZQA code, its exact title that no other active course of the provider shares, or an address
  -- whose last part is that title, and no other course of the provider is bound to the same address or stored copy (setting enrich.course_description_identity_proof_on)
  v_slug := btrim(regexp_replace(lower(coalesce(c.canonical_title, '')), '[^a-z0-9]+', '-', 'g'), '-');
  v_proof := security.pipeline_num_v1('enrich.course_description_identity_proof_on', 0) >= 1
    and not exists (select 1 from pipeline.coverage_course_pages g3 where g3.provider_id = g.provider_id and g3.course_id <> g.course_id
                      and (lower(regexp_replace(regexp_replace(g3.url, '[?#].*$', ''), '/+$', '')) = lower(regexp_replace(regexp_replace(g.url, '[?#].*$', ''), '/+$', ''))
                           or (g3.evidence_id is not null and g3.evidence_id = g.evidence_id)))
    and (g.identity_basis in ('cricos_code', 'nzqa_code')
         or ((g.identity_basis = 'exact_title'
              or (v_slug <> '' and v_slug = (select s.p from (select seg.p, seg.o from regexp_split_to_table(lower(regexp_replace(regexp_replace(coalesce(g.url, ''), '[?#].*$', ''), '^[a-z][a-z0-9+.-]*://[^/]*', '')), '/') with ordinality seg(p, o) where seg.p <> '' order by seg.o desc limit 1) s)))
             and not exists (select 1 from catalogue.courses c4 where c4.provider_id = c.provider_id and c4.id <> c.id and c4.lifecycle_status = 'active'
                               and security.cdesc_norm_v1(c4.canonical_title) = security.cdesc_norm_v1(c.canonical_title))));
  if not v_proof and (g.basis = 'ai_match' or (g.score is not null and g.runner_up is not null and g.score - g.runner_up < 0.1
$n$,
    $n$                                                                                                                            or (g2.evidence_id is not null and g2.evidence_id = g.evidence_id)))))) then$n$,
    $n$'binding', g.status, 'policy', 'ok', 'identity_proof', v_proof))$n$],
  array[1,1,1,1]);

select pg_temp.edit_all('security.enrich_course_text_record_v1(bigint,jsonb)', '82e93b8b73d1f13ac3fd62dbb59264f9', '2811e8058b787234ce60c3bf1b7b2aa5',
  array[
    $o$    if security.cdesc_provider_slots_v1(v_pid) <= 0 then
$o$,
    $o$Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.$o$],
  array[
    $n$    -- s662 (18 Nov 2026): the provider's first-description hold applies only while enrich.course_description_first_hold_on is 1; with it off every checked reading goes to
    -- Layer 4 at once, where the machine rule (cdesc-machine-v2) admits it on its own page's proof and its quotes, or leaves it for a person with the reason
    if security.pipeline_num_v1('enrich.course_description_first_hold_on', 1) >= 1 and security.cdesc_provider_slots_v1(v_pid) <= 0 then
$n$,
    $n$Course description read from the course''s own page. The machine rule admits it when the page proves the course and every sentence matches its quote; it waits here only when a check did not pass (the reason is shown).$n$],
  array[1,1]);

select pg_temp.edit_all('security.course_description_promote_held_v1(uuid)', '2f46bf63e50726d67bdd9d7cf74e915a', '0a507ed319ca15ae2aeff95a45d6bb19',
  array[
    $o$  v_slots := security.cdesc_provider_slots_v1(p_provider);
$o$,
    $o$Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.$o$],
  array[
    $n$  v_slots := case when security.pipeline_num_v1('enrich.course_description_first_hold_on', 1) < 1 then security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int -- derived (s662): with the first-description hold off every held reading may enter, bounded by a day's reads
                  else security.cdesc_provider_slots_v1(p_provider) end;
$n$,
    $n$Course description read from the course''s own page. The machine rule admits it when the page proves the course and every sentence matches its quote; it waits here only when a check did not pass (the reason is shown).$n$],
  array[1,1]);

select pg_temp.edit_all('security.layer4_inbox_kinds_v1()', '8c820d6912a240ece0e731221261e6de', 'e56cf8d360ff6413638a77dd3a34d8ac',
  array[
    $o$     {"key": "reject", "label": "Reject", "returns": "Nothing is published; the university is read again after the set wait"}]},
   "course_page_needed"$o$],
  array[
    $n$     {"key": "reject", "label": "Reject", "returns": "Nothing is published; the university is read again after the set wait"},
     {"key": "reread", "label": "Re-read (1-2 sentences)", "returns": "The stored page is read again by the released 1-2 sentence reader; the course is not marked bad, nothing is published, and the new reading comes back here only if the machine rule cannot admit it"},
     {"key": "approve_provider", "label": "Approve all verified for provider", "input": "count", "returns": "Every waiting course description of this provider whose sentences all pass the quote check on the course''s own page is admitted as read; the count is shown first and you confirm it"}]},
   "course_page_needed"$n$],
  array[1]);

select pg_temp.edit_all('security.layer4_inbox_items_v2(uuid,text,text[],boolean)', '14e939ac0df0320a116e450da20109c0', '9c30f272f44e09661724c621049da862',
  array[
    $o$n.captured_at > ev.captured_at)) end
$o$],
  array[
    $n$n.captured_at > ev.captured_at))
                            -- s664 (18 Nov 2026): a course description carries the machine rule's latest reason and the page binding, for the plain-English explanation
                            || case when r.field_code = 'course_description_first_read' then jsonb_build_object(
                                 'machine', (select jsonb_build_object('reason_code', md.reason_code, 'reason', md.reason, 'next_action', md.next_action, 'transient', md.transient)
                                               from pipeline.course_description_machine_admissions md where md.review_item_id = r.id and md.outcome = 'declined' order by md.id desc limit 1),
                                 'binding', (select jsonb_build_object('status', gb.status, 'basis', gb.basis, 'identity_basis', gb.identity_basis, 'score', gb.score, 'runner_up', gb.runner_up, 'url', gb.url)
                                               from pipeline.coverage_course_pages gb where gb.course_id = r.entity_id),
                                 'limits', jsonb_build_object('max_sentences', security.pipeline_num_v1('enrich.course_description_max_sentences', 2), 'max_chars', security.pipeline_num_v1('enrich.course_description_max_chars', 360)))
                                 else '{}'::jsonb end end
$n$],
  array[1]);

select pg_temp.edit_all('public.admin_layer4_inbox(text,jsonb)', 'e5f79c1bc29578e053cba6411d6a5d05', 'aa5333b31a5f3563d6d8212fd9d4ee08',
  array[
    $o$v_np bigint; v_ho int;$o$,
    $o$  elsif v_kind = 'provider_description' then
    -- CF-247 P1 (Platform Admin 2 Nov 2026 10:28): a university description is approved as read or rejected, never edited
$o$],
  array[
    $n$v_np bigint; v_ho int; v_cd_n int; v_cd_ok int;$n$,
    $n$  elsif v_kind = 'provider_description' and v_choice in ('reread', 'approve_provider') and v_det->>'field_code' is distinct from 'course_description_first_read' then
    raise exception 'this choice is for course descriptions only';
  elsif v_kind = 'provider_description' and v_choice = 'reread' then
    -- s664 (CF-247 S1-Courses, Platform Admin 18 Nov 2026): the stored page is read again by the released 1-2 sentence reader; the course is not marked bad
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: re-read asked by a person (' || security.cdesc_prompt_version_v1() || ')', 400)
     where id = v_ref::uuid and status = 'pending';
    if not found then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (v_ref::uuid, 'course_description_first_read', 'course', (v_det->>'course_id')::uuid, 'decided_before', null,
            jsonb_build_object('by', 'layer4-reread', 'actor', v_actor, 'reason', v_reason, 'prompt_after', security.cdesc_prompt_version_v1(), 'evidence_id', v_det->>'evidence_id'), 'reconcile');
    if to_regclass('pipeline.layer4_item_readiness') is not null then
      execute 'update pipeline.layer4_item_readiness set item_status = ''superseded'', readiness = ''closed'', classified_at = now() where item_id = $1' using v_ref::uuid;
    end if;
    update pipeline.field_enrich_items e set reason = left('reread: a person asked in Layer 4 for a re-read with ' || security.cdesc_prompt_version_v1() || ' (' || v_reason || ')', 300), updated_at = now()
     where e.field = 'description' and e.course_id = (v_det->>'course_id')::uuid and e.state = 'skipped'
       and (e.id::text = v_det->'proposed'->>'item_id' or e.value->>'review_item_id' = v_ref);
    get diagnostics v_cd_n = row_count;
    v_r := jsonb_build_object('reread', true, 'readings_queued', v_cd_n, 'prompt', security.cdesc_prompt_version_v1());
  elsif v_kind = 'provider_description' and v_choice = 'approve_provider' then
    -- s664: every waiting course description of this provider read from the course's own bound page (its CRICOS or NZQA code, or its exact title) whose sentences all
    -- pass the live quote and sentence check; the count is returned first and admitted only when the person types the same count
    select coalesce(array_agg(q.id order by q.created_at, q.id), '{}') into v_ids
      from pipeline.layer4_review_items q
      join catalogue.courses cq on cq.id = q.entity_id and cq.provider_id = v_pid and cq.lifecycle_status = 'active' and nullif(btrim(cq.description), '') is null
      join pipeline.coverage_course_pages gq on gq.course_id = cq.id and gq.status = 'bound' and gq.provider_id = cq.provider_id and gq.evidence_id is not distinct from q.evidence_id
      join pipeline.field_enrich_items fq on fq.id::text = q.proposed_value->>'item_id' and fq.course_id = cq.id and fq.field = 'description' and fq.state = 'review'
     where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
       and q.proposed_value->>'source_url' is not distinct from gq.url
       and gq.identity_basis in ('cricos_code', 'nzqa_code', 'exact_title')
       and not exists (select 1 from pipeline.manual_locks lq where lq.entity = 'course' and lq.entity_id = cq.id and lq.field in ('description', 'course_description', 'all'))
       and coalesce((security.course_description_check_v1(cq.id, fq.value)->>'ok')::boolean, false);
    v_cd_n := coalesce(cardinality(v_ids), 0);
    if v_cd_n = 0 then raise exception 'no waiting course description of this provider passes the quote check on its own page'; end if;
    if v_value is null or v_value !~ '^\d+$' or v_value::int <> v_cd_n then
      return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', false, 'kind', v_kind, 'choice', v_choice, 'ref', v_ref, 'eligible', v_cd_n,
               'request', v_cd_n || ' waiting course description(s) of this provider pass the quote check on the course''s own page. Type ' || v_cd_n || ' in the box and choose again to approve them all.'));
    end if;
    v_cd_ok := 0;
    foreach v_prov in array v_ids loop
      begin
        v_hp := public.layer4_review_decide(v_prov, 'approve', left('[bulk provider, ' || v_cd_n || ' verified] ' || v_reason, 500), null);
        v_cd_ok := v_cd_ok + 1;
      exception when others then null; -- one item never stops the rest; it stays waiting
      end;
    end loop;
    v_r := jsonb_build_object('approved', v_cd_ok, 'eligible', v_cd_n);
  elsif v_kind = 'provider_description' then
    -- CF-247 P1 (Platform Admin 2 Nov 2026 10:28): a university description is approved as read or rejected, never edited
$n$],
  array[1,1]);

-- 2 and 3, 4: settings
update pipeline.platform_toolset_settings set value = to_jsonb(2), updated_at = now(),
       reason = 'CF-247 s662 (Platform Admin 18 Nov 2026, S1-Courses): course descriptions are 1 to 2 sentences (prompt cdesc-source-grounded-v4); was 4'
 where toolset_key = 'pipeline' and key = 'enrich.course_description_max_sentences';
update pipeline.platform_toolset_settings set value = to_jsonb(360), updated_at = now(),
       reason = 'CF-247 s662 (Platform Admin 18 Nov 2026, S1-Courses): target 180 to 360 characters for a 1 to 2 sentence description; was 700'
 where toolset_key = 'pipeline' and key = 'enrich.course_description_max_chars';
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.course_description_identity_proof_on', 'Course description: admit on the page''s own identity proof',
  'On (1): the machine rule does not hold a description for a thin page-match margin when the page proves the course by its own CRICOS or NZQA code, or by its exact title (or an address ending in it) that no other course of the provider shares, and no other course is bound to the same page. Off (0): the margin applies as before.',
  'number', to_jsonb(1), 0, 1, 'switch', 1131, 'Course description and deadline',
  'security.course_description_machine_check_v1 (rule cdesc-machine-v2)', 'CF-247 s662 (Platform Admin 18 Nov 2026, S1-Courses): clear the identity-margin holds of descriptions read from the course''s own page'),
 ('pipeline', 'enrich.course_description_first_hold_on', 'Course description: hold a provider''s first descriptions behind its places',
  'On (1): once a provider''s places in Layer 4 are taken, its further checked readings wait (held_first_admission) until one is decided. Off (0): every checked reading goes to Layer 4 at once and the machine rule decides it; held readings are promoted without the place limit.',
  'number', to_jsonb(0), 0, 1, 'switch', 1132, 'Course description and deadline',
  'security.enrich_course_text_record_v1, security.course_description_promote_held_v1', 'CF-247 s662 (Platform Admin 18 Nov 2026, S1-Courses): no manual first-item sign-off for quote-verified descriptions from the course''s own page')
on conflict (toolset_key, key) do nothing;

-- 1: the route and the registry
with u as (
  update pipeline.ai_service_routes set prompt_source = 'worker code: cdesc-source-grounded-v4',
         reason = 'prompt cdesc-source-grounded-v4 released (Platform Admin 18 Nov 2026, S1-Courses s662, migration 20261118268000)'
   where service_code = 'course_description' and prompt_source = 'worker code: cdesc-source-grounded-v3'
  returning service_code)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'migration', 'ai_service_routes.course_description', jsonb_build_object('migration', '20261118268000', 'field', 'prompt_source',
       'before', 'worker code: cdesc-source-grounded-v3', 'after', 'worker code: cdesc-source-grounded-v4'), null from u;

insert into pipeline.prompt_templates(service_code, version, system_text, system_sha256, user_template, variables, answer_schema, pinned_models, source, status, note)
select t.service_code, 'cdesc-source-grounded-v4', $cdesc$SYSTEM — STUDYSEARCH COURSE DESCRIPTION / cdesc-source-grounded-v4
You are producing a neutral Australian-English description of ONE identified course.
Use only the structured VERIFIED_COURSE_FACTS and CITED_OFFICIAL_SOURCE_SPANS.
Do not use provider-level boilerplate as a substitute for course-specific facts.
Do not open with, and do not write, a sentence that only introduces the course, such as
"The <course title> at <provider> is a ..." or "<course title> is a ... offered by <provider>":
the reader already has the course title and the provider.
Start the first sentence directly with a substantive fact about this course that a cited span
prints (its subject matter, structure or units), and cite that span.
Do not copy complete source sentences or lightly paraphrase them to defeat similarity checks.
Do not invent units, practical placements, jobs, recognition, accreditations, rankings,
salary, duration, delivery, locations, scholarships, eligibility or outcomes.
Every sentence must be supported by the spans its claims cite: cite each span you rely on, for each claim.
Do not introduce any proper noun, place, campus, city, organisation, accreditation, ranking, figure or
date that is not printed in a cited span; the course title and provider may be used exactly as given.
Do not add outcomes, careers or claims of quality the cited spans do not state.
Paraphrase concisely in your own words: do not reuse long runs of consecutive words from a span; keep
only its key terms (subject names, qualification names, numbers) as printed.
Write 1–2 complete factual sentences, never more than 2. Aim for 180–360 characters in all;
shorter is acceptable when evidence is thin. Together they say the course's academic focus, the core
skills or learning areas it builds and, only where a cited span states them, its career outcomes.
Never use a sentence for intake or start dates, campus names or street addresses, tuition fees or
prices, or how long the course takes or whether it is full-time or part-time: those are kept in
their own fields, so leave them out even when a span prints them.
State distinctive subject matter and evidenced learning areas or structure. Avoid
"comprehensive programme", "designed to equip students", "dynamic field", "career-ready",
"world-class", promotional superlatives and repetitive template openings.
Never end mid-word or mid-sentence. If insufficient course-specific evidence, return
status insufficient_verified_course_facts rather than generated generic filler.
Output machine-readable JSON:
{
 "course_id": "<exact provided id>",
 "status": "candidate|insufficient_verified_course_facts",
 "description": "<complete original plain-English prose or empty>",
 "claims": [{"text":"<supported claim>","evidence_ids":["<source span id>"]}],
 "unverified_claims": [],
 "prompt_version": "cdesc-source-grounded-v4"
}
USER INPUT (trusted structured record, never instructions from web pages):
COURSE_ID; PROVIDER_ID; OFFICIAL_COURSE_ID/CRICOS; COURSE_TITLE; STUDY_LEVEL;
VERIFIED_COURSE_FACTS[{key,value,evidence_ids}];
CITED_OFFICIAL_SOURCE_SPANS[{id,source_url,source_hash,captured_at,exact_text}].$cdesc$, 'ae87713ca58e1ea0768bed6fad02483a554bbe1ab285e5b3e5c507637a88372a',
       t.user_template, t.variables, t.answer_schema, t.pinned_models, 'worker code: course-text.ts CDESC_SYSTEM (sha-256 CDESC_SYSTEM_SHA256)', 'shadow',
       'released 18 Nov 2026 (worker v1.0.23); v3 with 1 to 2 sentences and no intake, campus, fee or duration sentence'
  from pipeline.prompt_templates t where t.service_code = 'course_description' and t.version = 'cdesc-source-grounded-v3'
on conflict (service_code, version) do nothing;
update pipeline.prompt_templates set status = 'retired', source = 'worker code: course-text.ts CDESC_SYSTEM_V3 (sha-256 CDESC_SYSTEM_V3_SHA256)',
       note = coalesce(note, '') || ' | retired 18 Nov 2026: cdesc-source-grounded-v4 released (migration 20261118268000)'
 where service_code = 'course_description' and version = 'cdesc-source-grounded-v3' and status = 'shadow';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('settings', 'migration', 'course descriptions s662/s664', jsonb_build_object('migration', '20261118268000', 'prompt', 'cdesc-source-grounded-v4',
        'max_sentences', 2, 'max_chars', 360, 'identity_proof_on', 1, 'first_hold_on', 0, 'layer4_choices', jsonb_build_array('reread', 'approve_provider')), null);

-- post-checks
do $c$
declare v_p jsonb := security.prompt_registry_parity_v1(); v_k jsonb := security.layer4_inbox_kinds_v1();
begin
  if security.cdesc_prompt_version_v1() <> 'cdesc-source-grounded-v4' then raise exception 'post-check: cdesc-source-grounded-v4 is the released prompt'; end if;
  if (select system_sha256 from pipeline.prompt_templates where service_code = 'course_description' and version = 'cdesc-source-grounded-v4')
     is distinct from encode(sha256(convert_to((select system_text from pipeline.prompt_templates where service_code = 'course_description' and version = 'cdesc-source-grounded-v4'), 'UTF8')), 'hex') then
    raise exception 'post-check: the v4 prompt text does not have the worker''s sha-256';
  end if;
  -- the course description rows only: another service's row is that service's lane (18 Nov 2026 21:25: the provider description row differs since its prompt version 5)
  if exists (select 1 from jsonb_array_elements(v_p) x where x->>'service' = 'course_description' and ((x->>'system_text_matches') = 'false' or (x->>'status' = 'shadow' and (x->>'models_match_route') <> 'true'))) then
    raise exception 'post-check: prompt registry parity failed for course_description: %', v_p;
  end if;
  if security.pipeline_num_v1('enrich.course_description_max_sentences', 0) <> 2 or security.pipeline_num_v1('enrich.course_description_max_chars', 0) <> 360
     or security.pipeline_num_v1('enrich.course_description_identity_proof_on', 0) <> 1 or security.pipeline_num_v1('enrich.course_description_first_hold_on', 1) <> 0 then
    raise exception 'post-check: course description settings';
  end if;
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) <> 1 then raise exception 'post-check: the machine switch is unchanged (on)'; end if;
  if (select count(*) from jsonb_array_elements(v_k->'provider_description'->'choices') ch where ch->>'key' in ('approve', 'reject', 'reread', 'approve_provider')) <> 4 then
    raise exception 'post-check: the course description card has its four choices';
  end if;
  if (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'security', 'pipeline', 'api')) is distinct from current_setting('cf247.s662_fn_before', true) then
    raise exception 'post-check: no function is added or removed';
  end if;
  if (security.consumer_api_check_v1() - 'checked_at')::text is distinct from current_setting('cf247.s662_api_before', true) then
    raise exception 'post-check (G3): the consumer API check result changed';
  end if;
  if coalesce(current_setting('cf247.s662_api_before', true)::jsonb->'drift', '[]'::jsonb) not in ('[]'::jsonb, '{}'::jsonb, 'null'::jsonb) then
    raise exception 'post-check (G3): the consumer API differs from its baseline';
  end if;
end $c$;
