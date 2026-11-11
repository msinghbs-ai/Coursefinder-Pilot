-- CF-247 F-CDESC.01-.06 (Platform Admin 11 Nov 2026: "Implement the Course Description production redesign recorded in Admin PR #430 ... a straight production replacement"; contract: admin docs/platform/COURSE-DESCRIPTION-PRODUCTION-DESIGN.md, steps CD-R2/CD-R3).
--
-- The course description is written with the pinned, versioned prompt cdesc-source-grounded-v1 (worker coverage-sweep v0.72.0, course-text.ts CDESC_SYSTEM, sha-256 e1fcd3e1d34d5700aa3daf14405cbc6cd97aa93f46b863e91ff0f18fc273e7c5):
-- original prose from the course page's numbered source spans, each claim citing its spans; insufficient_verified_course_facts is recorded as such. Each sentence reaches the database with the exact text of the spans it cites as its quote, so the
-- existing checks (quote on the page, marketing and claim words, complete sentence, support, length, duplicates) test every sentence against its evidence. This change adds what the audit (CD-R0, 11 Nov 2026) found missing:
--   * copied text: 65.7% of the course-description sentences read under course-text-v1/v2 were verbatim page copies, and copied paragraphs were admitted. A sentence that repeats enrich.course_description_copy_run_words words of its source in order
--     (new setting, 10 words, range 0 to 60, 0 = off) is held: copied_sentence;
--   * generic filler: 26 admitted and 45 waiting descriptions carry "designed to equip" or "comprehensive program". A sentence with a phrase of enrich.course_description_generic_phrases (new setting, the contract's list) is held: generic_phrase;
--   * unverified claims: a description that carries a claim the writer reported it could not tie to the page is held: unverified_claims;
--   * a reading held by a check, or superseded in Layer 4, that an earlier prompt made is read once more with the released prompt (security.enrich_course_text_gaps_v1; security.cdesc_prompt_version_v1 is the database's copy of the released
--     version, kept equal to course-text.ts by tests/uat/cf-247-cdesc-source-grounded-contract.spec.mjs);
--   * new readings had stopped: 2,030 first descriptions waited in Layer 4, at or over enrich.course_description_pending_global_max (1,500), so field-gap-queue created no description reading after 11 Nov 03:23 AEDT; 2,014 of them were made by
--     course-text-v1/v2 (or an unrecorded prompt) and declined for good by the machine rule. security.cdesc_prompt_supersede_v1 (new, first step of job course-description-machine) supersedes such items in batches of layer4.reconcile_batch
--     (reason decided_before, recorded in pipeline.layer4_supersessions) and their readings are read again with the new prompt. Only a decline for good under the CURRENT policy counts (the new settings change the policy stamp, so
--     the existing settle step first looks at each waiting item again with the new checks). A locked course, a description the machine has not declined for good under the current policy, a transient decline, or one made by the
--     released prompt is never superseded. Back-pressure, the provider places, the daily cap and the AI budget are unchanged.
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 12 Nov 2026), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric)  0aacac45e2a294a51db82777a9d1bc19 -> c17adb1d759d24cf8b41bcdeac7c6b54
--   security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)  d310fa64f61f2243df1416d3e48f6bab -> 0aeeeeee93debfaa6bdc86c0fe528010
--   security.enrich_course_text_gaps_v1(text[])  66d9dad4eb0d743b804097b1bf9d38d2 -> 89e208ffd0c66694d6d26a21b2a4d64f
--   security.course_description_machine_run_v1()  42c73e9c0f376150e7778104dfa9830a -> 545a874051466f132221de12160fbd46
-- Replaces: course-text-v2 as the course description prompt (the deadline keeps it); the four bodies above in place (md5-guarded edits); the D4 length re-ask of the worker
-- Retires: setting enrich.course_description_reask_max (no reader after worker v0.72.0; its used_by says so; removed by a paste file after hygiene.retire_after_days, with the description re-ask code already gone from the worker)
-- Nothing is dropped or deleted. Two settings are added (with label, range, unit and used_by; each recorded in admin_control_events). No table, job, job kind or consumer-API object is added or changed (G3). Forward recovery (restores the four
-- previous bodies byte for byte; the two new functions and settings stay, unused): supabase/held/cdesc_source_grounded_forward_recovery.sql

-- 1. settings ---------------------------------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'enrich.course_description_copy_run_words', 'Course description: words in a row that make a copy',
        'A course description sentence that repeats this many words of its source passage in the same order is page text, not an original description, and is held (copied_sentence). 0 switches the copy test off.',
        'number', to_jsonb(10), '0', '60', 'words', 1121, 'Course description and deadline', 'security.cdesc_sentence_fault_v1 (security.course_description_check_v1)',
        'Platform Admin 11 Nov 2026 (Admin PR #430, cdesc-source-grounded-v1): copied paragraphs must not be admitted; 65.7% of course-description sentences were verbatim page copies (CD-R0 audit). Ten words in a row is a copied clause, not a shared term.'),
       ('pipeline', 'enrich.course_description_generic_phrases', 'Course description: generic phrases',
        'Phrases that say nothing specific about a course. A course description sentence that holds one is held (generic_phrase), even when the page uses it.',
        'list', '["comprehensive programme", "comprehensive program", "designed to equip", "dynamic field", "career-ready", "career ready", "world-class", "world class"]'::jsonb, null, null, 'phrases', 1122, 'Course description and deadline',
        'security.cdesc_sentence_fault_v1 (security.course_description_check_v1)',
        'Platform Admin 11 Nov 2026 (Admin PR #430): the prompt contract''s list of phrases to avoid; 26 admitted and 45 waiting descriptions held "designed to equip" or "comprehensive program" (CD-R0 audit)')
on conflict (toolset_key, key) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'setting', 'pipeline.' || k, jsonb_build_object('before', null, 'after', v, 'reason', 'Added by migration 20261112170000 (Platform Admin 11 Nov 2026, Admin PR #430): cdesc-source-grounded-v1 quality checks'),
       '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
  from (values ('enrich.course_description_copy_run_words', to_jsonb(10)), ('enrich.course_description_generic_phrases', '["comprehensive programme", "comprehensive program", "designed to equip", "dynamic field", "career-ready", "career ready", "world-class", "world class"]'::jsonb)) x(k, v)
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'toolsets' and e.target = 'pipeline.' || x.k);
update pipeline.platform_toolset_settings set used_by = 'retiring: no reader since worker coverage-sweep v0.72.0 (migration 20261112170000); removed by a paste file'
 where toolset_key = 'pipeline' and key = 'enrich.course_description_reask_max' and used_by is distinct from 'retiring: no reader since worker coverage-sweep v0.72.0 (migration 20261112170000); removed by a paste file';

-- 2. new functions -----------------------------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.cdesc_prompt_version_v1() returns text language sql immutable set search_path = '' as $f$
  select 'cdesc-source-grounded-v1'::text  -- fixed: the code identity of the released course description prompt (course-text.ts CDESC_PROMPT_VERSION), not an operational value
$f$;
comment on function security.cdesc_prompt_version_v1() is 'CF-247 F-CDESC (20261112170000): the released course description prompt version; a held or superseded reading made by another prompt is read again once';

create or replace function security.cdesc_prompt_supersede_v1() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_max int := security.pipeline_num_v1('layer4.reconcile_batch', 200)::int; v_ver text := security.cdesc_prompt_version_v1(); v_stamp text := security.course_description_machine_policy_stamp_v1();
        r record; v_n int := 0;
begin
  -- a first course description waiting in Layer 4 that an earlier prompt made, and that the machine rule declined for good, waits for nothing a person can usefully decide:
  -- it is superseded (decided_before: the machine decided it) and its reading is read again with the released prompt. A locked course is never touched.
  for r in select q.id, q.entity_id, q.evidence_id, q.layer3_state->>'prompt' pr,
                  case when coalesce(q.proposed_value->>'item_id', '') ~ '^\d+$' then (q.proposed_value->>'item_id')::bigint end item_id
             from pipeline.layer4_review_items q
            where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
              and coalesce(q.layer3_state->>'prompt', '') <> v_ver
              -- declined for good under the CURRENT policy (the same test as security.cdesc_provider_slots_v1): an item the new checks have not looked at yet waits for them
              and exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient
                             and d.policy_stamp = v_stamp)
              and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.entity_id and k.field in ('description', 'course_description', 'all'))
            order by q.created_at limit v_max
            for update of q skip locked loop
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: decided_before (declined for good by cdesc-machine-v1; read again with ' || v_ver || ')', 400)
     where id = r.id and status = 'pending';
    continue when not found;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (r.id, 'course_description_first_read', 'course', r.entity_id, 'decided_before', null,
            jsonb_build_object('by', 'cdesc-prompt-supersede', 'machine_outcome', 'declined', 'prompt_before', r.pr, 'prompt_after', v_ver, 'evidence_id', r.evidence_id), 'reconcile');
    if to_regclass('pipeline.layer4_item_readiness') is not null then
      execute 'update pipeline.layer4_item_readiness set item_status = ''superseded'', readiness = ''closed'', classified_at = now() where item_id = $1' using r.id;
    end if;
    -- security.course_description_review_trg_v1 has set the reading skipped ("not admitted in Layer 4 (superseded)"); it is marked to be read again
    update pipeline.field_enrich_items e set reason = left('superseded: declined for good under ' || coalesce(r.pr, 'an unrecorded prompt') || '; read again with ' || v_ver, 300), updated_at = now()
     where e.field = 'description' and e.course_id = r.entity_id and e.state = 'skipped' and (e.id = r.item_id or e.value->>'review_item_id' = r.id::text);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('superseded', v_n, 'prompt', v_ver, 'batch', v_max);
end $f$;
comment on function security.cdesc_prompt_supersede_v1() is 'CF-247 F-CDESC (20261112170000): supersedes first course descriptions an earlier prompt made that the machine declined for good, so they are read again with cdesc-source-grounded-v1 (job course-description-machine)';
revoke all on function security.cdesc_prompt_supersede_v1() from public;
revoke all on function security.cdesc_prompt_version_v1() from public;

-- 3. the four md5-guarded edits ------------------------------------------------------------------------------------------------------------------------------------------------
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;
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

select pg_temp.edit_all('security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric)', '0aacac45e2a294a51db82777a9d1bc19', 'c17adb1d759d24cf8b41bcdeac7c6b54',
  array[$o0$declare t text := btrim(coalesce(p_text, '')); v_sup numeric;$o0$,
        $o1$  -- a sentence that does not end as a sentence is a fragment$o1$,
        $o2$  return null;$o2$],
  array[$n0$declare t text := btrim(coalesce(p_text, '')); v_sup numeric;
        v_run int := security.pipeline_num_v1('enrich.course_description_copy_run_words', 10)::int;
        v_gen jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_generic_phrases'), '[]'::jsonb); v_sw text[]; v_qw text; i int;$n0$,
        $n1$  -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): a stock phrase that says nothing about this course is held, whatever the page says
  if exists (select 1 from jsonb_array_elements_text(v_gen) w where security.pdesc_has_term_v1(t, w)) then
    return jsonb_build_object('rule', 'generic_phrase', 'reason', 'a generic phrase that says nothing specific about this course: ' || left(t, 120));
  end if;
  -- a sentence that does not end as a sentence is a fragment$n1$,
        $n2$  -- cdesc-source-grounded-v1: a run of v_run words of the sentence, in order, in its source passage is the page's text, not an original description (0 = off)
  if v_run > 0 then
    v_sw := array(select w from regexp_split_to_table(lower(t), '[^a-z0-9]+') w where w <> '');
    v_qw := ' ' || array_to_string(array(select w from regexp_split_to_table(lower(coalesce(p_quote, '')), '[^a-z0-9]+') w where w <> ''), ' ') || ' ';
    for i in 1 .. coalesce(array_length(v_sw, 1), 0) - v_run + 1 loop
      if position(' ' || array_to_string(v_sw[i:i + v_run - 1], ' ') || ' ' in v_qw) > 0 then
        return jsonb_build_object('rule', 'copied_sentence', 'checks', jsonb_build_object('copy_run_words', v_run),
          'reason', 'a sentence repeats ' || v_run || ' or more words of the page in order (copied, not an original description): ' || left(t, 120));
      end if;
    end loop;
  end if;
  return null;$n2$]);

select pg_temp.edit_all('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', 'd310fa64f61f2243df1416d3e48f6bab', '0aeeeeee93debfaa6bdc86c0fe528010',
  array[$o0$  if v_n < security.pipeline_num_v1('enrich.course_description_min_sentences', 1)$o0$],
  array[$n0$  -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): a claim the writer reported it could not tie to the page is never published; the description
  -- is held when it carries one (most of the claim's words are in the text)
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(p_result->'unverified_claims') = 'array' then p_result->'unverified_claims' else '[]'::jsonb end) u
              where security.pdesc_support_v1(u, v_text) >= v_min_sup) then
    return jsonb_build_object('ok', false, 'rule', 'unverified_claims', 'checks', v_checks,
      'reason', 'the description carries a claim the writer could not tie to the page: ' || left(p_result->'unverified_claims'->>0, 120));
  end if;
  if v_n < security.pipeline_num_v1('enrich.course_description_min_sentences', 1)$n0$]);

select pg_temp.edit_all('security.enrich_course_text_gaps_v1(text[])', '66d9dad4eb0d743b804097b1bf9d38d2', '89e208ffd0c66694d6d26a21b2a4d64f',
  array[$o0$                                  and a.answer->'value'->'sentences' = e.value->'sentences')) unproven$o0$,
        $o1$case when coalesce(l.unproven, false) then 0 when l.state is null then 1$o1$,
        $o2$or coalesce(l.unproven, false) or l.updated_at <$o2$],
  array[$n0$                                  and a.answer->'value'->'sentences' = e.value->'sentences')) unproven,
               -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): a description reading held by a check, or superseded in Layer 4, that an earlier prompt made is read once more with the released prompt
               (f = 'description' and e.state = 'skipped' and (e.reason like 'held%' or e.reason like 'superseded:%')
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) old_prompt$n0$,
        $n1$case when coalesce(l.unproven, false) then 0 when l.state is null or coalesce(l.old_prompt, false) then 1$n1$,
        $n2$or coalesce(l.unproven, false) or coalesce(l.old_prompt, false) or l.updated_at <$n2$]);

select pg_temp.edit_all('security.course_description_machine_run_v1()', '42c73e9c0f376150e7778104dfa9830a', '545a874051466f132221de12160fbd46',
  array[$o0$declare v_a jsonb; v_b jsonb; v_h jsonb; v_s jsonb;$o0$,
        $o1$  begin v_h := security.cdesc_recheck_held_v1();$o1$,
        $o2$return jsonb_build_object('on', true, 'held', v_h,$o2$],
  array[$n0$declare v_a jsonb; v_b jsonb; v_h jsonb; v_s jsonb; v_p jsonb;$n0$,
        $n1$  -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): waiting descriptions an earlier prompt made that the machine declined for good are superseded and read again
  begin v_p := security.cdesc_prompt_supersede_v1(); exception when others then v_p := jsonb_build_object('error', sqlerrm); end;
  begin v_h := security.cdesc_recheck_held_v1();$n1$,
        $n2$return jsonb_build_object('on', true, 'prompt', v_p, 'held', v_h,$n2$]);

-- 4. component register and post-check --------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.cdesc_prompt_version_v1', 'Layer 2', 'F-CDESC: the released course description prompt version (cdesc-source-grounded-v1); readings by another prompt are read again once', 'active', '{}', '20261112170000'),
 ('function', 'security.cdesc_prompt_supersede_v1', 'Layer 4', 'F-CDESC: supersedes waiting first course descriptions an earlier prompt made that the machine declined for good, so they are read again (job course-description-machine)', 'active', '{}', '20261112170000')
on conflict do nothing;

do $chk$
begin
  if (select count(*) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key in ('enrich.course_description_copy_run_words', 'enrich.course_description_generic_phrases') and s.used_by is not null and s.unit is not null) <> 2 then
    raise exception 'post-check: a cdesc-source-grounded-v1 setting is missing';
  end if;
  if security.cdesc_prompt_version_v1() <> 'cdesc-source-grounded-v1' then raise exception 'post-check: the released prompt version is wrong'; end if;
end $chk$;
