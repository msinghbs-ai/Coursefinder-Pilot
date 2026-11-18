-- CF-247 Decision 265 (18 Oct 2026): ACU English by course group. Platform Admin 18 Oct 2026: "Yes, UAC for ACU (Recommended)".
-- ACU's course pages refer to an English schedule ACU has rescinded; UAC (the NSW admissions centre) publishes ACU's requirements by course group.
-- The UAC page was read and stored on 18 Oct 2026 (provider fact source 1e1c3ed9). This written-out policy holds each group's scores (each quoted
-- from the stored page) and the order in which a course's title and study level pick its group (level_rules, used by
-- security.english_level_apply_v1 from 20261018010000). A course whose own page prints a score keeps it. Checked before writing: for the 29 ACU
-- courses whose own page prints an IELTS score, the group rule gives the same IELTS in every case.
-- Proposed only: a Platform Admin approves.
-- Also: a level may give skill minimums only (ACU's Education groups print no overall score); the "already written" check in
--   security.english_level_apply_v1 now compares the overall score null-safely, so such rows are not rewritten every run.
-- Replaces: security.english_level_apply_v1 (md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('security.english_level_apply_v1(uuid,boolean)'::regprocedure)) <> 'cd638f2de25dabb3872692d5b69f9532' then
    raise exception 'live security.english_level_apply_v1 differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function security.english_level_apply_v1(p_provider_id uuid, p_apply boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare x pipeline.provider_policy_proposals%rowtype; r record; v_lv jsonb; v_write jsonb; v_tests text[]; v_src uuid; v_name text; v_out int;
        v_written int := 0; v_same int := 0; v_own_differs int := 0; v_own int := 0; v_held int := 0; v_withdrawn int := 0; v_unknown jsonb := '{}'::jsonb;
        v_courses uuid[] := '{}'; v_err int := 0; v_last text; v_label text; v_k text; v_how text; v_rule text;
        v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
begin
  -- the approved English policy in force that names levels (Decision 262 keeps one in force per level; the latest decision wins here)
  select * into x from pipeline.provider_policy_proposals
   where provider_id = p_provider_id and kind = 'english_policy' and status = 'approved' and jsonb_typeof(proposal->'levels') = 'object'
   order by decided_at desc nulls last limit 1;
  if x.id is null then return jsonb_build_object('skipped', 'no approved English policy with levels'); end if;
  if x.evidence_id is null or coalesce(x.content_hash, '') = '' then return jsonb_build_object('skipped', 'the policy page has no stored evidence'); end if;
  v_src := security.coverage_sweep_source(x.provider_id);
  select coalesce(p.display_name, p.canonical_name) into v_name from catalogue.providers p where p.id = x.provider_id;
  for r in
    select co.id course_id, co.canonical_title title, security.english_level_group(sl.code) grp,
           -- Decision 265: the level the course page names, else the one its companion page names (Melbourne's entry requirements page)
           case when coalesce(g.candidates->'adapter_extra'->>'english_level', '') <> '' then g.candidates->'adapter_extra'->>'english_level'
                when cp.status = 'read' then nullif(cp.values->>'english_level', '') end raw,
           case when coalesce(g.candidates->'adapter_extra'->>'english_level', '') <> '' then g.url else cp.url end page_url,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = co.id and i.field_code = 'course_english' and i.status = 'pending') in_review
      from catalogue.courses co
      join pipeline.coverage_course_pages g on g.course_id = co.id
      left join pipeline.course_companion_pages cp on cp.course_id = co.id
      left join ref.study_levels sl on sl.id = co.study_level_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active' and g.read_status = 'read'
  loop
    v_k := security.english_level_key(r.raw); v_how := format('named on the course page (%s)', r.page_url);
    -- Decision 265: no level named on a page: the policy's course group rules, in order (title pattern, and study level group when given)
    if v_k is null then
      select q->>'level', q->>'group_name' into v_k, v_rule
        from jsonb_array_elements(coalesce(x.proposal->'level_rules', '[]'::jsonb)) with ordinality t(q, n)
       where r.title ~* (q->>'title_regex')
         and (jsonb_typeof(q->'groups') is distinct from 'array' or r.grp in (select jsonb_array_elements_text(q->'groups')))
       order by n limit 1;
      if v_k is null then continue; end if;
      v_k := security.english_level_key(v_k); v_how := format('for this course group ("%s")', v_rule);
    end if;
    v_lv := x.proposal->'levels'->v_k;
    v_label := coalesce(x.proposal->'level_names'->>v_k, btrim(coalesce(r.raw, v_k)));
    if jsonb_typeof(v_lv) is distinct from 'array' or jsonb_array_length(v_lv) = 0 then
      v_unknown := jsonb_set(v_unknown, array[coalesce(v_k, '?')], to_jsonb(coalesce((v_unknown->>coalesce(v_k, '?'))::int, 0) + 1)); continue;
    end if;
    if r.locked or r.in_review then v_held := v_held + 1; continue; end if;
    -- the course page prints its own score for a test of the level, and it differs: the page has its own requirement (an accreditation
    -- standard, for example), so the level is not used for this course and rows this rule wrote before are withdrawn
    if exists (select 1 from jsonb_array_elements(v_lv) q
                join ref.english_tests t on t.code = upper(q->>'test_code')
                join catalogue.course_english_requirements e on e.course_id = r.course_id and e.english_test_id = t.id and e.status = 'active'
               where coalesce(e.source_requirement_key, '') not like 'policy:%' and e.overall_score <> (q->>'overall_score')::numeric) then
      v_own_differs := v_own_differs + 1;
      if p_apply then
        with w as (
          update catalogue.course_english_requirements e set status = 'withdrawn', last_verified_at = now(),
                 notes = coalesce(e.notes, '') || format(' Withdrawn %s: the course page prints its own English score, which differs from level "%s" (Decision 264).', v_day, v_label)
           where e.course_id = r.course_id and e.status = 'active' and e.source_requirement_key like 'policy:%' and e.notes like 'English level %Decision 264%'
          returning e.course_id)
        select count(*) into v_out from w;
        v_withdrawn := v_withdrawn + v_out;
        if v_out > 0 then v_courses := v_courses || r.course_id; end if;
      end if;
      continue;
    end if;
    v_tests := array(select upper(q->>'test_code') from jsonb_array_elements(v_lv) q);
    -- the course's own reading (any key that is not a policy's) is never replaced
    v_own := v_own + (select count(*) from jsonb_array_elements(v_lv) q
                       where exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                                      where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                                        and coalesce(e.source_requirement_key, '') not like 'policy:%'))::int;
    select coalesce(jsonb_agg(jsonb_build_object(
             'test_code', upper(q->>'test_code'), 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
             'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
             'notes', format('English level "%s" %s; scores for that level from %s''s English language requirements (%s), approved by a Platform Admin (Decision 264, 265).',
                             v_label, v_how, v_name, x.url))), '[]'::jsonb)
      into v_write
      from jsonb_array_elements(v_lv) q
     where upper(q->>'test_code') in (select t.code from ref.english_tests t where t.status = 'active')
       and not exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                        where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                          and (coalesce(e.source_requirement_key, '') not like 'policy:%'
                               or (e.source_requirement_key = 'policy:' || x.id || ':' || lower(q->>'test_code')
                                   and e.overall_score is not distinct from (q->>'overall_score')::numeric  -- a level may give skill minimums only (no overall)
                                   and e.component_scores = coalesce(q->'component_scores', '{}'::jsonb)
                                   and e.notes like 'English level %Decision 264%')));
    if jsonb_array_length(v_write) = 0 then v_same := v_same + 1; continue; end if;
    if not p_apply then v_written := v_written + 1; continue; end if;
    begin
      perform security.coverage_apply_course_v1(r.course_id, v_src, x.evidence_id, x.url, x.content_hash, jsonb_build_object('english_requirements', v_write));
      -- policy rows for tests this level does not give are withdrawn (kept, not deleted)
      with w as (
        update catalogue.course_english_requirements e set status = 'withdrawn', last_verified_at = now(),
               notes = coalesce(e.notes, '') || format(' Withdrawn %s: the course page names English level "%s", which does not give this test (Decision 264).', v_day, v_label)
          from ref.english_tests t
         where t.id = e.english_test_id and e.course_id = r.course_id and e.status = 'active'
           and e.source_requirement_key like 'policy:%' and t.code <> all (v_tests)
        returning 1)
      select count(*) into v_out from w;
      v_withdrawn := v_withdrawn + v_out;
      v_written := v_written + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'course_english', v_src, 'approved', 'CF-CHG-20260915-247; Decision 227 (English from the provider''s policy, approved by a Platform Admin)', now(), now(), now()
     where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_english' and g.source_id = v_src);
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'english_levels', 'english_policy: ' || x.url,
            jsonb_build_object('proposal_id', x.id, 'provider_id', x.provider_id, 'courses', cardinality(v_courses), 'withdrawn_rows', v_withdrawn,
                               'unknown_levels', v_unknown, 'decision', 264), null);
  end if;
  update pipeline.provider_policy_proposals
     set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('levels', jsonb_build_object(
           'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'own_differs', v_own_differs, 'held', v_held, 'withdrawn_rows', v_withdrawn,
           'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last, 'checked_at', now(), 'applied', p_apply)), updated_at = now()
   where id = x.id and p_apply;
  return jsonb_build_object('policy', x.id, 'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'own_differs', v_own_differs, 'own_differs', v_own_differs, 'held', v_held,
                            'withdrawn_rows', v_withdrawn, 'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last);
end $function$;
revoke execute on function security.english_level_apply_v1(uuid, boolean) from public, anon, authenticated;

insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
select fs.provider_id, fs.id, 'english_policy', 'written out from the central page', fs.content_hash, fs.evidence_id, fs.url, 'level_map', $j${"style": "level_map", "parser": "written out from the central page", "decision": 265, "source_note": "Published by UAC (the NSW admissions centre) for ACU; ACU's course pages refer to a schedule ACU has rescinded. Used as the source by the Platform Admin's choice (18 Oct 2026: 'Yes, UAC for ACU').", "level_reading": "ACU course pages print no English scores for these courses. Each course takes the first course group (in this order) whose title pattern and study level fit; a course whose own page prints a score keeps it. Diplomas and postgraduate courses other than Master of Teaching (Secondary) are not listed by UAC and get nothing.", "defaults": {}, "named": [], "exceptions": [], "caveats": ["third_party_admissions_centre_source", "education_groups_give_skill_minimums_only"], "signals": [], "conflicts": [], "level_names": {"education": "Education: Initial Teacher preparation courses, Double Degrees, Dip in Educational Studies", "ite vertical": "Education: Initial Teacher Education vertical degrees", "pg teaching secondary": "Master of Teaching (Secondary)", "nursing midwifery and registered health": "B Nursing, B Midwifery, B Occupational Therapy, B Physiotherapy (tests from 23 April 2026)", "psychology": "B Psychological Science and associated double degrees, B Psychology (Honours)", "speech pathology": "Speech Pathology", "social work": "B Social Work", "health sciences": "Health Science: all other courses, B Early Childhood Education (Birth to Five Years), B Arts (Western Civilisation)", "law and criminology": "Law and Criminology: all courses", "bachelor degrees": "Bachelor degrees (unless specified otherwise)"}, "levels": {"education": [{"test_code": "IELTS", "overall_score": null, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 7.5, "listening": 7.5}, "quote": "Min. 7.0 in reading and writing, 7.5 in listening and speaking"}, {"test_code": "TOEFL_IBT", "overall_score": null, "component_scores": {"reading": 24, "writing": 27, "speaking": 24, "listening": 27}, "quote": "Min. 24 in reading, 27 in writing, 27 in listening and 24 in speaking"}, {"test_code": "PTE", "overall_score": null, "component_scores": {"reading": 65, "writing": 65, "speaking": 73, "listening": 73}, "quote": "Min. 65 in reading and writing, 73 in listening and speaking"}, {"test_code": "CAE", "overall_score": null, "component_scores": {"reading": 185, "writing": 185, "speaking": 191, "listening": 191}, "quote": "Min. 185 in reading and writing, 191 in listening and speaking"}], "ite vertical": [{"test_code": "IELTS", "overall_score": null, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 8.0, "listening": 8.0}, "quote": "Min. 7 in reading and writing, min. 8 in listening and speaking"}, {"test_code": "TOEFL_IBT", "overall_score": null, "component_scores": {"reading": 24, "writing": 27, "speaking": 26, "listening": 28}, "quote": "Min. 24 in reading, 27 in writing, 28 in listening and 26 in speaking"}, {"test_code": "PTE", "overall_score": null, "component_scores": {"reading": 65, "writing": 65, "speaking": 79, "listening": 79}, "quote": "Min. 65 in reading and writing, min. 79 in listening and speaking"}, {"test_code": "CAE", "overall_score": null, "component_scores": {"reading": 185, "writing": 185, "speaking": 200, "listening": 200}, "quote": "Min. 185 in reading and writing, min. 200 in listening and speaking"}], "pg teaching secondary": [{"test_code": "IELTS", "overall_score": null, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 8.0, "listening": 8.0}, "quote": "Min. 7.0 in reading and writing, 8.0 in listening and speaking"}, {"test_code": "TOEFL_IBT", "overall_score": null, "component_scores": {"reading": 24, "writing": 27, "speaking": 26, "listening": 28}, "quote": "min. 26 in speaking, 27 in writing, 24 in reading and 28 in listening"}, {"test_code": "PTE", "overall_score": null, "component_scores": {"reading": 65, "writing": 65, "speaking": 79, "listening": 79}, "quote": "Min. 65 in reading and writing, 79 in listening and speaking"}, {"test_code": "CAE", "overall_score": null, "component_scores": {"reading": 185, "writing": 185, "speaking": 200, "listening": 200}, "quote": "Min. 185 in reading and writing, 200 in listening and speaking"}], "nursing midwifery and registered health": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 7.0, "writing": 6.5, "speaking": 7.0, "listening": 7.0}, "quote": "7.0 overall (min. 7.0 in listening, reading and speaking, 6.5 in writing)"}, {"test_code": "PTE", "overall_score": 63, "component_scores": {"reading": 59, "writing": 60, "speaking": 76, "listening": 58}, "quote": "63 overall (min. 58 in listening, 59 in reading, 60 in writing and 76 in speaking)"}, {"test_code": "CAE", "overall_score": 178, "component_scores": {"reading": 179, "writing": 180, "speaking": 194, "listening": 175}, "quote": "Minimum score of 175 in listening, 179 in reading, 180 in writing and 194 in speaking"}], "psychology": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 7.0, "writing": 6.5, "speaking": 7.0, "listening": 7.0}, "quote": "7.0 overall (min.7.0 in listening, reading and speaking, and 6.5 in writing)"}, {"test_code": "TOEFL_IBT", "overall_score": 94, "component_scores": {"reading": 24, "writing": 24, "speaking": 23, "listening": 24}, "quote": "Internet-based score: 94 (min.24 in reading, listening and writing, 23 in speaking)"}, {"test_code": "PTE", "overall_score": 66, "component_scores": {"reading": 66, "writing": 56, "speaking": 66, "listening": 66}, "quote": "66 overall (min. 66 in listening, reading and speaking, 56 in writing)"}, {"test_code": "CAE", "overall_score": 185, "component_scores": {"reading": 185, "writing": 176, "speaking": 185, "listening": 185}, "quote": "185 overall (min. 185 in listening, reading and speaking, 176 in writing)"}], "speech pathology": [{"test_code": "IELTS", "overall_score": 8.0, "component_scores": {"reading": 8.0, "writing": 8.0, "speaking": 8.0, "listening": 8.0}, "quote": "8.0 overall (min. 8.0 in each subtest)"}, {"test_code": "TOEFL_IBT", "overall_score": 110, "component_scores": {"reading": 29, "writing": 30, "speaking": 26, "listening": 28}, "quote": "Internet-based score: 110 (min. 28 in listening, 29 in reading, 30 in writing, 26 in speaking)"}, {"test_code": "PTE", "overall_score": 79, "component_scores": {"reading": 79, "writing": 79, "speaking": 79, "listening": 79}, "quote": "79 overall (min. 79 in listening, reading, speaking and writing)"}, {"test_code": "CAE", "overall_score": 200, "component_scores": {"reading": 200, "writing": 200, "speaking": 200, "listening": 200}, "quote": "200 overall (min. 200 in each subtest)"}], "social work": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 7.0, "listening": 7.0}, "quote": "7.0 overall (min. 7.0 in each subtest)"}, {"test_code": "TOEFL_IBT", "overall_score": 94, "component_scores": {"reading": 24, "writing": 27, "speaking": 23, "listening": 24}, "quote": "Internet-based score: 94 (min. 27 in writing, 23 in speaking, 24 in reading and listening)"}, {"test_code": "PTE", "overall_score": 65, "component_scores": {"reading": 65, "writing": 65, "speaking": 65, "listening": 65}, "quote": "65 overall (min. 65 in listening, reading, speaking and writing)"}, {"test_code": "CAE", "overall_score": 185, "component_scores": {"reading": 185, "writing": 185, "speaking": 185, "listening": 185}, "quote": "185 overall (min. 185 in each subtest)"}], "health sciences": [{"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "6.5 overall (min. 6.0 in each subtest)"}, {"test_code": "TOEFL_IBT", "overall_score": 79, "component_scores": {"reading": 13, "writing": 21, "speaking": 18, "listening": 12}, "quote": "Internet-based score: 79 (min. 12 in listening, 13 in reading, 21 in writing, 18 in speaking)"}, {"test_code": "PTE", "overall_score": 58, "component_scores": {"reading": 50, "writing": 50, "speaking": 50, "listening": 50}, "quote": "58 overall (min. 50 in listening, reading, speaking and writing)"}, {"test_code": "CAE", "overall_score": 185, "component_scores": {"reading": 176, "writing": 176, "speaking": 176, "listening": 176}, "quote": "185 overall (min. 176 in each subtest)"}], "law and criminology": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 6.5, "writing": 6.5, "speaking": 6.5, "listening": 6.5}, "quote": "7.0 overall (min. 6.5 in each subtest)"}, {"test_code": "TOEFL_IBT", "overall_score": 94, "component_scores": {"reading": 19, "writing": 24, "speaking": 20, "listening": 20}, "quote": "Internet-based score: 94 (19 in reading, 24 in writing, 20 in listening and speaking)"}, {"test_code": "PTE", "overall_score": 65, "component_scores": {"reading": 58, "writing": 58, "speaking": 58, "listening": 58}, "quote": "65 overall (min. 58 in listening, reading, speaking and writing)"}, {"test_code": "CAE", "overall_score": 185, "component_scores": {"reading": 176, "writing": 176, "speaking": 176, "listening": 176}, "quote": "185 overall (min. 176 in each subtest)"}], "bachelor degrees": [{"test_code": "IELTS", "overall_score": 6.0, "component_scores": {"reading": 5.5, "writing": 6.0, "speaking": 6.0, "listening": 5.5}, "quote": "6.0 overall (min. 6.0 in writing and speaking, 5.5 in listening and reading)"}, {"test_code": "TOEFL_IBT", "overall_score": 60, "component_scores": {"reading": 8, "writing": 21, "speaking": 18, "listening": 7}, "quote": "Internet-based score: 60 (8 in reading, 21 in writing, 7 in listening, 18 in speaking)"}, {"test_code": "PTE", "overall_score": 50, "component_scores": {"reading": 42, "writing": 50, "speaking": 50, "listening": 42}, "quote": "50 overall (min. 50 in writing and speaking, 42 in listening and reading)"}]}, "level_rules": [{"level": "ite vertical", "group_name": "Education: Initial Teacher Education vertical degrees", "title_regex": "Bachelor of .*/\\s*Master of Teaching"}, {"level": "pg teaching secondary", "group_name": "Master of Teaching (Secondary)", "title_regex": "^Master of Teaching \\(Secondary\\)"}, {"level": "speech pathology", "group_name": "Speech Pathology", "title_regex": "Speech Pathology", "groups": ["undergraduate"]}, {"level": "social work", "group_name": "B Social Work", "title_regex": "^Bachelor of Social Work", "groups": ["undergraduate"]}, {"level": "nursing midwifery and registered health", "group_name": "B Nursing, B Midwifery, B Occupational Therapy, B Physiotherapy (tests from 23 April 2026)", "title_regex": "^Bachelor of (Nursing|Midwifery|Occupational Therapy|Physiotherapy)", "groups": ["undergraduate"]}, {"level": "psychology", "group_name": "B Psychological Science and associated double degrees, B Psychology (Honours)", "title_regex": "Bachelor of Psycholog", "groups": ["undergraduate"]}, {"level": "education", "group_name": "Education: Initial Teacher preparation courses, Double Degrees, Dip in Educational Studies", "title_regex": "^(Bachelor of Education \\(|Diploma in Educational Studies)"}, {"level": "law and criminology", "group_name": "Law and Criminology: all courses", "title_regex": "(Laws|Criminology)", "groups": ["undergraduate"]}, {"level": "health sciences", "group_name": "Health Science: all other courses, B Early Childhood Education (Birth to Five Years), B Arts (Western Civilisation)", "title_regex": "(Allied Health|Public Health|Biomedical|Exercise|Sport|Nutrition|Paramedicine|Dietetic|Early Childhood Education \\(Birth to Five|^Bachelor of Arts \\(Western Civilisation\\)$)", "groups": ["undergraduate"]}, {"level": "bachelor degrees", "group_name": "Bachelor degrees (unless specified otherwise)", "title_regex": "^Bachelor of", "groups": ["undergraduate"]}]}$j$::jsonb, 'proposed'
  from pipeline.provider_fact_sources fs
 where fs.id = '1e1c3ed9-3ff0-4554-bafb-a1fbff976fb9' and fs.status = 'read' and fs.evidence_id is not null
on conflict on constraint provider_policy_proposals_key do nothing;

do $post$
begin
  if not exists (select 1 from pipeline.provider_policy_proposals where fact_source_id = '1e1c3ed9-3ff0-4554-bafb-a1fbff976fb9' and parser = 'written out from the central page'
                  and status = 'proposed' and jsonb_array_length(proposal->'level_rules') = 10) then
    raise exception 'ACU policy post-check';
  end if;
end $post$;
