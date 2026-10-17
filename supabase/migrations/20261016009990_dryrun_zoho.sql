-- CF-247 Decision 264 (17 Oct 2026): English levels named on course pages. Platform Admin 17 Oct 2026 ("Band reader (Recommended)") and
-- 18:56 ("Proceed with band reader"); choice "Level map first (Recommended)".
-- Some universities publish English as named levels: the course page names the level ("Band 2", "This course has higher ELC requirements")
-- and one central table gives each level's test scores (JCU Admissions Policy Schedule II, UWA English language requirements). The policy
-- parser reads defaults and named courses only, so these universities had no approved English policy and their courses no English.
-- 1 An English policy proposal may carry "levels": normalised level name -> requirements (each with its quote from the stored policy page),
--   besides "defaults" and "exceptions". The written-out proposals below (JCU, UWA, ANU) are approved by a Platform Admin as before
--   (Decision 227); nothing here approves them.
-- 2 Adapters may read english_level (the level the course page names) as a pattern field (worker v0.28.0); it is kept with the page reading.
-- 3 security.english_level_apply_v1 writes the level's requirements to a course whose page names a level of the approved policy in force:
--   key policy:<policy>:<test> like policy defaults, so Decision 262 and the policy screens treat them alike. A course's own reading (any other
--   key), a value set by hand (manual lock) or a pending Layer 4 item is never replaced. Policy rows for tests the level does not give are
--   withdrawn (kept, not deleted). A level name the policy does not hold is reported, not guessed.
-- 4 It runs in provider-english-defaults after the in-force step, before defaults are applied (a course with a level is then not given the
--   default).
-- 5 Policies written out by hand ("written out from the central page") are not read again by policy-add-tests: the parser cannot read their
--   tables, so a new reading would only raise false "policy reading differs" flags.
-- Replaces: security.uni_adapter_pattern_fields (adds english_level), public.svc_provider_policy_add_tests_next (skips written-out
--   policies), the provider-english-defaults job command (adds the level step); all md5-guarded
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('security.uni_adapter_pattern_fields()'::regprocedure)) <> 'c8dc54ee12e8bba301673cb738da5d68' then
    raise exception 'live security.uni_adapter_pattern_fields differs from the definition this change replaces';
  end if;
  if md5(pg_get_functiondef('public.svc_provider_policy_add_tests_next(text,integer)'::regprocedure)) <> '7f261e733c1b06ea48c534af9fcb2890' then
    raise exception 'live public.svc_provider_policy_add_tests_next differs from the definition this change replaces';
  end if;
  if (select md5(command) from cron.job where jobname = 'provider-english-defaults') <> '74b92c10e3aca0eb76ccabe8808ad141' then
    raise exception 'live provider-english-defaults command differs from the one this change replaces';
  end if;
end $guard$;

create or replace function security.uni_adapter_pattern_fields()
 returns text[] language sql immutable set search_path to '' as $function$
  select array['intakes', 'fee', 'ielts_overall', 'campus', 'mode', 'duration', 'study_level', 'student_type', 'not_admitting', 'aqf_level', 'location', 'fee_total', 'course_years', 'exit_awards', 'entry_requirement', 'other_requirements', 'english_level']
$function$;

create or replace function public.svc_provider_policy_add_tests_next(p_parser text, p_limit integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_agg(s.x) from (
    select jsonb_build_object('id', pp.id, 'source_id', pp.fact_source_id, 'provider', p.canonical_name, 'url', pp.url, 'storage_path', e.storage_path) x
      from pipeline.provider_policy_proposals pp
      join pipeline.evidence_artifacts e on e.id = pp.evidence_id
      join catalogue.providers p on p.id = pp.provider_id
     where pp.kind = 'english_policy' and pp.status = 'approved' and e.storage_path is not null
       and pp.parser <> 'written out from the central page'  -- Decision 264: hand-written policies are not read again by the parser
       and coalesce(pp.proposal->'added_tests'->>'parser', '') is distinct from p_parser
     order by pp.decided_at
     limit greatest(1, least(coalesce(p_limit, 40), 200))) s), '[]'::jsonb);  -- fixed: per-call safety cap; the run size is batch.policy_add_tests
end $function$;
revoke execute on function public.svc_provider_policy_add_tests_next(text, integer) from public, anon, authenticated;
grant execute on function public.svc_provider_policy_add_tests_next(text, integer) to service_role;

-- The level name as compared: lower case, quotes and stray punctuation off, single spaces ("”Band 3a”" -> "band 3a").
create or replace function security.english_level_key(p text)
returns text language sql immutable set search_path = '' as $function$
  select nullif(btrim(regexp_replace(regexp_replace(lower(coalesce(p, '')), '[“”"''’‘`:;,()]', ' ', 'g'), '\s+', ' ', 'g')), '')
$function$;

create or replace function security.english_level_apply_v1(p_provider_id uuid, p_apply boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare x pipeline.provider_policy_proposals%rowtype; r record; v_lv jsonb; v_write jsonb; v_tests text[]; v_src uuid; v_name text; v_out int;
        v_written int := 0; v_same int := 0; v_own int := 0; v_held int := 0; v_withdrawn int := 0; v_unknown jsonb := '{}'::jsonb;
        v_courses uuid[] := '{}'; v_err int := 0; v_last text; v_label text;
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
    select co.id course_id, g.url page_url, g.candidates->'adapter_extra'->>'english_level' raw,
           security.english_level_key(g.candidates->'adapter_extra'->>'english_level') k,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = co.id and i.field_code = 'course_english' and i.status = 'pending') in_review
      from catalogue.courses co
      join pipeline.coverage_course_pages g on g.course_id = co.id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active' and g.read_status = 'read'
       and coalesce(g.candidates->'adapter_extra'->>'english_level', '') <> ''
  loop
    v_lv := x.proposal->'levels'->r.k;
    if jsonb_typeof(v_lv) is distinct from 'array' or jsonb_array_length(v_lv) = 0 then
      v_unknown := jsonb_set(v_unknown, array[coalesce(r.k, '?')], to_jsonb(coalesce((v_unknown->>coalesce(r.k, '?'))::int, 0) + 1)); continue;
    end if;
    if r.locked or r.in_review then v_held := v_held + 1; continue; end if;
    v_label := coalesce(x.proposal->'level_names'->>r.k, btrim(r.raw));
    v_tests := array(select upper(q->>'test_code') from jsonb_array_elements(v_lv) q);
    -- the course's own reading (any key that is not a policy's) is never replaced
    v_own := v_own + (select count(*) from jsonb_array_elements(v_lv) q
                       where exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                                      where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                                        and coalesce(e.source_requirement_key, '') not like 'policy:%'))::int;
    select coalesce(jsonb_agg(jsonb_build_object(
             'test_code', upper(q->>'test_code'), 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
             'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
             'notes', format('English level "%s" named on the course page (%s); scores for that level from %s''s English language requirements (%s), approved by a Platform Admin (Decision 264).',
                             v_label, r.page_url, v_name, x.url))), '[]'::jsonb)
      into v_write
      from jsonb_array_elements(v_lv) q
     where upper(q->>'test_code') in (select t.code from ref.english_tests t where t.status = 'active')
       and not exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                        where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                          and (coalesce(e.source_requirement_key, '') not like 'policy:%'
                               or (e.source_requirement_key = 'policy:' || x.id || ':' || lower(q->>'test_code')
                                   and e.overall_score = (q->>'overall_score')::numeric
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
           'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'held', v_held, 'withdrawn_rows', v_withdrawn,
           'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last, 'checked_at', now(), 'applied', p_apply)), updated_at = now()
   where id = x.id and p_apply;
  return jsonb_build_object('policy', x.id, 'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'held', v_held,
                            'withdrawn_rows', v_withdrawn, 'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last);
end $function$;

create or replace function security.english_level_apply_all_v1(p_apply boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare p uuid; v jsonb := '{}'::jsonb;
begin
  for p in select distinct provider_id from pipeline.provider_policy_proposals
            where kind = 'english_policy' and status = 'approved' and jsonb_typeof(proposal->'levels') = 'object' loop
    v := v || jsonb_build_object(p::text, security.english_level_apply_v1(p, p_apply));
  end loop;
  return v;
end $function$;

revoke execute on function security.english_level_apply_v1(uuid, boolean), security.english_level_apply_all_v1(boolean) from public, anon, authenticated;

-- provider-english-defaults: in force, then levels, then refresh plans and defaults
select cron.alter_job((select jobid from cron.job where jobname = 'provider-english-defaults'),
  command := $$select security.english_policy_in_force_all_v1(true); select security.english_level_apply_all_v1(true); select security.provider_policy_refresh_plans_v1(security.pipeline_num_v1('batch.provider_policy_refresh', 12)::int); select security.provider_english_apply_all_v1();$$);

-- Written-out policies from each university's stored page (every value quoted from it). Proposed only: a Platform Admin approves.
insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
select fs.provider_id, fs.id, 'english_policy', 'written out from the central page', fs.content_hash, fs.evidence_id, fs.url, v.style, v.proposal, 'proposed'
  from (values
  ('957049d4-5171-4d99-8280-c27e435c4b27'::uuid, 'level_map', $j${
    "style": "level_map", "parser": "written out from the central page", "decision": 264,
    "level_reading": "Each course page names its band: \"Applicants of non-English speaking backgrounds must meet the English language proficiency requirements of \"Band 2\" – Schedule II of the JCU Admissions Policy.\"",
    "defaults": {}, "named": [], "exceptions": [], "caveats": ["no_default_course_names_its_band"], "signals": [], "conflicts": [],
    "level_names": {"band p": "Band P", "band 1": "Band 1", "band 2": "Band 2", "band 3a": "Band 3a", "band 3b": "Band 3b", "band 3c": "Band 3c"},
    "levels": {
      "band p": [
        {"test_code": "IELTS", "overall_score": 5.5, "component_scores": {"reading": 5.0, "writing": 5.0, "speaking": 5.0, "listening": 5.0}, "quote": "| **IELTS** | 5.5<br>(no component lower than 5.0) |"},
        {"test_code": "TOEFL_IBT", "overall_score": 56, "component_scores": {"reading": 16, "writing": 16, "speaking": 16, "listening": 16}, "quote": "| **TOEFL**<br>(internet based) | 56<br>(no component less than 16) |"},
        {"test_code": "PTE", "overall_score": 46, "component_scores": {"reading": 42, "writing": 42, "speaking": 42, "listening": 42}, "quote": "| **Pearson**<br>(PTE Academic) | 46<br>(no component less than 42) |"},
        {"test_code": "CAE", "overall_score": 162, "component_scores": {"reading": 154, "writing": 154, "speaking": 154, "listening": 154}, "quote": "| **C1 Advanced/**<br>**C2 Proficiency** | 162<br>(no component less than 154) |"}],
      "band 1": [
        {"test_code": "IELTS", "overall_score": 6.0, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "6<br>(no component lower than 6.0)"},
        {"test_code": "TOEFL_IBT", "overall_score": 74, "component_scores": {"reading": 18, "writing": 18, "speaking": 18, "listening": 18}, "quote": "74<br>(no component less than 18)"},
        {"test_code": "PTE", "overall_score": 52, "component_scores": {"reading": 52, "writing": 52, "speaking": 52, "listening": 52}, "quote": "52<br>(no component less than 52)"},
        {"test_code": "CAE", "overall_score": 169, "component_scores": {"reading": 169, "writing": 169, "speaking": 169, "listening": 169}, "quote": "169<br>(no component less than 169)"}],
      "band 2": [
        {"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "6.5<br>(no component lower than 6.0)"},
        {"test_code": "TOEFL_IBT", "overall_score": 86, "component_scores": {"reading": 21, "writing": 21, "speaking": 21, "listening": 21}, "quote": "86<br>(no component less than 21)"},
        {"test_code": "PTE", "overall_score": 58, "component_scores": {"reading": 54, "writing": 54, "speaking": 54, "listening": 54}, "quote": "58<br>(no component less than 54)"},
        {"test_code": "CAE", "overall_score": 176, "component_scores": {"reading": 169, "writing": 169, "speaking": 169, "listening": 169}, "quote": "176<br>(no component less than 169)"}],
      "band 3a": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 6.5, "writing": 6.5, "speaking": 6.5, "listening": 6.5}, "quote": "7<br>(no component lower than 6.5)"},
        {"test_code": "TOEFL_IBT", "overall_score": 94, "component_scores": {"reading": 23, "writing": 23, "speaking": 23, "listening": 23}, "quote": "94<br>(no component less than 23)"},
        {"test_code": "PTE", "overall_score": 65, "component_scores": {"reading": 58, "writing": 58, "speaking": 58, "listening": 58}, "quote": "65<br>(no component less than 58)"}],
      "band 3b": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {}, "quote": "7<br>(with 7.0 in three components and 6.5 in one component)"},
        {"test_code": "TOEFL_IBT", "overall_score": 94, "component_scores": {"reading": 24, "writing": 27, "speaking": 23, "listening": 24}, "quote": "94<br>(23 in Speaking, 24 in Listening and Reading, and 27 in Writing)"},
        {"test_code": "PTE", "overall_score": 65, "component_scores": {}, "quote": "65<br>(with 65 in three components and 58 in one component"}],
      "band 3c": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 7.0, "listening": 7.0}, "quote": "7<br>(no component lower than 7.0)"},
        {"test_code": "TOEFL_IBT", "overall_score": 94, "component_scores": {"reading": 24, "writing": 27, "speaking": 23, "listening": 24}, "quote": "94<br>(23 in Speaking, 24 in Listening and Reading, and 27 in Writing) |"},
        {"test_code": "PTE", "overall_score": 65, "component_scores": {"reading": 65, "writing": 65, "speaking": 65, "listening": 65}, "quote": "65<br>(no component less than 65)"}]
    }}$j$::jsonb),
  ('6c481f19-21ec-4259-a452-6225e302a07a'::uuid, 'level_map', $j${
    "style": "level_map", "parser": "written out from the central page", "decision": 264,
    "level_reading": "Courses with the Higher standard say so on the course page: \"This course has higher ELC requirements.\" Other coursework courses take the Minimum standard. Courses with Accreditation ELC requirements print their own scores (read from the course page).",
    "named": [], "exceptions": [], "caveats": ["accreditation_courses_print_their_own"], "signals": [], "conflicts": [],
    "defaults": {
      "undergraduate": [
        {"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "Minimum standard ELC requirements - a minimum overall score of 6.5 with no band less than 6.0."},
        {"test_code": "PTE", "overall_score": 64, "component_scores": {"reading": 60, "writing": 60, "speaking": 60, "listening": 60}, "quote": "Minimum standard ELC requirements - a minimum overall score of 64 with no band score less than 60."},
        {"test_code": "TOEFL_IBT", "overall_score": 82, "component_scores": {"reading": 17, "writing": 20, "speaking": 20, "listening": 17}, "quote": "Minimum standard ELC requirements - a minimum overall score of 82 with a minimum score of 20 in the Speaking and Writing sections, and a minimum score of 17 in the Listening and Reading sections."},
        {"test_code": "CAE", "overall_score": 170, "component_scores": {"reading": 165, "writing": 175, "speaking": 175, "listening": 165}, "quote": "Minimum standard ELC requirements - a minimum overall grade of 170 with a minimum grade of 175 in the Speaking and Writing sections, and a minimum grade of 165 in the Listening and Reading sections."},
        {"test_code": "DET", "overall_score": 125, "component_scores": {}, "quote": "Minimum standard ELC requirements - an overall score of 125 with a minimum score of 115 in Speaking, 125 in Writing, 115 in Reading and 110 in Listening."}],
      "postgraduate": [
        {"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "Minimum standard ELC requirements - a minimum overall score of 6.5 with no band less than 6.0."},
        {"test_code": "PTE", "overall_score": 64, "component_scores": {"reading": 60, "writing": 60, "speaking": 60, "listening": 60}, "quote": "Minimum standard ELC requirements - a minimum overall score of 64 with no band score less than 60."},
        {"test_code": "TOEFL_IBT", "overall_score": 82, "component_scores": {"reading": 17, "writing": 20, "speaking": 20, "listening": 17}, "quote": "Minimum standard ELC requirements - a minimum overall score of 82 with a minimum score of 20 in the Speaking and Writing sections, and a minimum score of 17 in the Listening and Reading sections."},
        {"test_code": "CAE", "overall_score": 170, "component_scores": {"reading": 165, "writing": 175, "speaking": 175, "listening": 165}, "quote": "Minimum standard ELC requirements - a minimum overall grade of 170 with a minimum grade of 175 in the Speaking and Writing sections, and a minimum grade of 165 in the Listening and Reading sections."},
        {"test_code": "DET", "overall_score": 125, "component_scores": {}, "quote": "Minimum standard ELC requirements - an overall score of 125 with a minimum score of 115 in Speaking, 125 in Writing, 115 in Reading and 110 in Listening."}]},
    "level_names": {"higher": "Higher standard ELC"},
    "levels": {
      "higher": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 6.5, "writing": 6.5, "speaking": 6.5, "listening": 6.5}, "quote": "Higher standard ELC requirements - a minimum overall score of 7.0 with no band less than 6.5."},
        {"test_code": "PTE", "overall_score": 70, "component_scores": {"reading": 64, "writing": 64, "speaking": 64, "listening": 64}, "quote": "Higher standard ELC requirements - a minimum overall score of 70 with no band score less than 64."},
        {"test_code": "TOEFL_IBT", "overall_score": 92, "component_scores": {"reading": 20, "writing": 23, "speaking": 23, "listening": 20}, "quote": "Higher standard ELC requirements - a minimum overall score of 92 with a minimum score of 23 in the Speaking and Writing sections, and a minimum score of 20 in the Listening and Reading sections."},
        {"test_code": "CAE", "overall_score": 180, "component_scores": {"reading": 170, "writing": 185, "speaking": 185, "listening": 170}, "quote": "Higher standard ELC requirements - a minimum overall grade of 180 with a minimum grade of 185 in the Speaking and Writing sections, and a minimum grade of 170 in the Listening and Reading sections."}]
    }}$j$::jsonb),
  ('81e57d80-e705-4ae0-950f-525e98185270'::uuid, 'level_default', $j${
    "style": "level_default", "parser": "written out from the central page", "decision": 264,
    "level_reading": "Program pages do not print English scores; they refer to this policy. Table 2 (undergraduate), Table 6 (postgraduate coursework, unspecified programs) and Table 8 (research) give the defaults; TOEFL, Cambridge and PTE use the values for study commencing on or after 1 January 2027.",
    "caveats": [], "signals": [], "conflicts": [],
    "named": ["Doctor of Medicine and Surgery", "Master of Clinical Psychology", "Master of Professional Psychology", "Doctor of Philosophy (Clinical Psychology)"],
    "defaults": {
      "undergraduate": [
        {"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "All of the following:<br>Overall score: 6.5<br>Reading: 6.0<br>Writing: 6.0<br>Listening: 6.0<br>Speaking: 6.0"},
        {"test_code": "TOEFL_IBT", "overall_score": 81, "component_scores": {"reading": 16, "writing": 19, "speaking": 19, "listening": 16}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 81<br>Reading: 16<br>Writing: 19<br>Listening: 16<br>Speaking: 19"},
        {"test_code": "CAE", "overall_score": 169, "component_scores": {"reading": 163, "writing": 170, "speaking": 179, "listening": 163}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 169<br>Reading: 163<br>Writing: 170<br>Listening: 163<br>Speaking: 179"},
        {"test_code": "PTE", "overall_score": 64, "component_scores": {"reading": 60, "writing": 60, "speaking": 60, "listening": 60}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 64 <br>Communicative Skills:<br>Reading: 60<br>Writing: 60<br>Listening: 60<br>Speaking: 60"}],
      "postgraduate": [
        {"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "All of the following:<br>Overall score: 6.5<br>Reading: 6.0<br>Writing: 6.0<br>Speaking: 6.0<br>Listening: 6.0"},
        {"test_code": "TOEFL_IBT", "overall_score": 81, "component_scores": {"reading": 16, "writing": 19, "speaking": 19, "listening": 16}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 81<br>Reading: 16<br>Writing: 19<br>Listening: 16<br>Speaking: 19"},
        {"test_code": "CAE", "overall_score": 169, "component_scores": {"reading": 163, "writing": 170, "speaking": 179, "listening": 163}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 169<br>Reading: 163<br>Writing: 170<br>Listening: 163<br>Speaking: 179"},
        {"test_code": "PTE", "overall_score": 64, "component_scores": {"reading": 60, "writing": 60, "speaking": 60, "listening": 60}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 64 <br>Communicative Skills:<br>Reading: 60<br>Writing: 60<br>Listening: 60<br>Speaking: 60"}],
      "research": [
        {"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "All of the following:<br>Overall score: 6.5<br>Reading: 6.0<br>Writing: 6.0<br>Listening: 6.0<br>Speaking: 6.0"},
        {"test_code": "TOEFL_IBT", "overall_score": 81, "component_scores": {"reading": 16, "writing": 19, "speaking": 19, "listening": 16}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 81<br>Reading: 16<br>Writing: 19<br>Listening: 16<br>Speaking: 19"},
        {"test_code": "CAE", "overall_score": 169, "component_scores": {"reading": 163, "writing": 170, "speaking": 179, "listening": 163}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 169<br>Reading: 163<br>Writing: 170<br>Listening: 163<br>Speaking: 179"},
        {"test_code": "PTE", "overall_score": 64, "component_scores": {"reading": 60, "writing": 60, "speaking": 60, "listening": 60}, "quote": "For study commencing on or after 1 January 2027:<br>All of the following:<br>Overall score: 64 <br>Communicative Skills:<br>Reading: 60<br>Writing: 60<br>Listening: 60<br>Speaking: 60"}]},
    "exceptions": [
      {"name": "Doctor of Medicine and Surgery", "level": "postgraduate", "reqs": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 6.0, "writing": 6.0, "speaking": 6.0, "listening": 6.0}, "quote": "All of the following:<br>Overall score: 7.0<br>Reading: 6.0<br>Writing: 6.0<br>Speaking: 6.0<br>Listening: 6.0"},
        {"test_code": "TOEFL_IBT", "overall_score": 100, "component_scores": {"reading": 22, "writing": 22, "speaking": 22, "listening": 22}, "quote": "All of the following:<br>Overall score: 100<br>Reading: 22<br>Writing: 22<br>Listening: 22<br>Speaking: 22"},
        {"test_code": "PTE", "overall_score": 70, "component_scores": {"reading": 60, "writing": 60, "speaking": 60, "listening": 60}, "quote": "All of the following:<br>Overall score: 70 <br>Communicative Skills:<br>Reading: 60<br>Writing: 60<br>Listening: 60<br>Speaking: 60"}]},
      {"name": "Master of Clinical Psychology", "level": "postgraduate", "reqs": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 7.0, "listening": 7.0}, "quote": "All of the following:<br>Overall score: 7.0<br>Reading: 7.0<br>Writing: 7.0<br>Speaking: 7.0<br>Listening: 7.0"},
        {"test_code": "TOEFL_IBT", "overall_score": 100, "component_scores": {"reading": 24, "writing": 27, "speaking": 23, "listening": 24}, "quote": "All of the following:<br>Overall score: 100<br>Reading: 24<br>Writing: 27<br>Listening: 24<br>Speaking: 23"},
        {"test_code": "PTE", "overall_score": 70, "component_scores": {"reading": 65, "writing": 65, "speaking": 65, "listening": 65}, "quote": "All of the following:<br>Overall score: 70 <br>Communicative Skills:<br>Reading: 65<br>Writing: 65<br>Listening: 65<br>Speaking: 65"}]},
      {"name": "Master of Professional Psychology", "level": "postgraduate", "reqs": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 7.0, "listening": 7.0}, "quote": "All of the following:<br>Overall score: 7.0<br>Reading: 7.0<br>Writing: 7.0<br>Speaking: 7.0<br>Listening: 7.0"},
        {"test_code": "TOEFL_IBT", "overall_score": 100, "component_scores": {"reading": 24, "writing": 27, "speaking": 23, "listening": 24}, "quote": "All of the following:<br>Overall score: 100<br>Reading: 24<br>Writing: 27<br>Listening: 24<br>Speaking: 23"},
        {"test_code": "PTE", "overall_score": 70, "component_scores": {"reading": 65, "writing": 65, "speaking": 65, "listening": 65}, "quote": "All of the following:<br>Overall score: 70 <br>Communicative Skills:<br>Reading: 65<br>Writing: 65<br>Listening: 65<br>Speaking: 65"}]},
      {"name": "Doctor of Philosophy (Clinical Psychology)", "level": "research", "reqs": [
        {"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"reading": 7.0, "writing": 7.0, "speaking": 7.0, "listening": 7.0}, "quote": "All of the following:<br>Overall score: 7.0<br>Reading: 7.0<br>Writing: 7.0<br>Speaking: 7.0<br>Listening: 7.0"}]}]
    }$j$::jsonb)
  ) v(source_id, style, proposal)
  join pipeline.provider_fact_sources fs on fs.id = v.source_id
on conflict on constraint provider_policy_proposals_key do nothing;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.english_level_key', 'Layer 2', 'English level name as compared (Decision 264)', 'active', '20261017070000'),
 ('function', 'security.english_level_apply_v1', 'Layer 2', 'Writes the English level a course page names from the approved policy in force (Decision 264)', 'active', '20261017070000'),
 ('function', 'security.english_level_apply_all_v1', 'Layer 2', 'English levels for every university whose approved policy names levels (job provider-english-defaults)', 'active', '20261017070000')
on conflict (kind, name) do nothing;

do $post$
begin
  if not ('english_level' = any (security.uni_adapter_pattern_fields())) then raise exception 'Decision 264 post-check: english_level not a pattern field'; end if;
  if security.english_level_key('”Band 3a”') <> 'band 3a' then raise exception 'Decision 264 post-check: level key'; end if;
  if (select count(*) from pipeline.provider_policy_proposals where parser = 'written out from the central page' and created_at > now() - interval '1 hour'
        and fact_source_id in ('957049d4-5171-4d99-8280-c27e435c4b27', '6c481f19-21ec-4259-a452-6225e302a07a', '81e57d80-e705-4ae0-950f-525e98185270')) <> 3 then
    raise exception 'Decision 264 post-check: three written-out policies expected';
  end if;
  if (select command from cron.job where jobname = 'provider-english-defaults') not like '%english_level_apply_all_v1%' then raise exception 'Decision 264 post-check: job'; end if;
end $post$;

do $d$
declare v text := '';
begin
  select string_agg(format('%s %s: %s', left(p.canonical_name, 12), pp.style,
           (select jsonb_object_agg(o, n) from (select pl.outcome o, count(*) n from security.provider_english_plan_v1(pp.id) pl group by 1) s)), ' | ')
    into v
    from pipeline.provider_policy_proposals pp join catalogue.providers p on p.id = pp.provider_id
   where pp.parser = 'written out from the central page' and pp.created_at > now() - interval '1 hour';
  raise exception 'DRYRUN levels: plans %; level apply JCU %; job %', v,
    security.english_level_apply_v1('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', false),
    (select left(command, 120) from cron.job where jobname = 'provider-english-defaults');
end $d$;
