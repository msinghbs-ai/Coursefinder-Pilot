-- CF-247 s1047 (S1-Build; Platform Admin 24 Nov 2026 15:10 AEDT, P1 Item 2; UAT feedback-4 "PTE/TOEFL is not there (each band score is also
-- missing)"): the other English tests of an approved university English policy reach the courses whose IELTS already agrees with it.
-- Found live (rolled back, 24 Nov 2026): Victoria University's approved policy (46cb12d6, its international entry page) gives undergraduate and
-- postgraduate IELTS, PTE and CAE with all four band scores, and TOEFL iBT with an overall score only. security.provider_english_plan_v1 marks a
-- course whose own IELTS already equals the policy's "agrees" and writes nothing, so PTE and CAE never reached those 149 courses (17 VU courses
-- hold a PTE row). Adelaide University's and The University of Newcastle's approved policies give IELTS only (nothing to inherit yet; their
-- PTE and TOEFL equivalents are on pages not stored yet).
-- 1. security.provider_english_inherit_tests_v1(p_proposal_id): for each course holding this policy's level-default IELTS row (key
--    policy:<id>:ielts, "Default for ..."), at the IELTS value the policy gives that level, add each other test the policy gives that level with
--    an overall score and all four band scores, when the course holds no active row for that test. Insert only: a course's own value is never
--    replaced; source and stored copy are the policy row's; key policy:<id>:<test>. Machine write: the lock guard (manual locks) and the s1020
--    English bands gate apply as to any machine write. Logged in pipeline.admin_control_events; search documents refreshed for the courses.
--    TOEFL iBT without its section scores is left out (the page's section list is not read yet), so nothing is held by the bands gate.
-- 2. Run now for the approved English policies of the three feedback-4 universities.
-- G1: no job. G2: no operational value (the four bands are the rule itself). G3: no consumer object changed (checked). Manual locks and active
-- cron checked unchanged. Nothing dropped or deleted.
-- Replaces: the "agrees" outcome leaving a policy's other tests unwritten.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1047_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1047_cron on commit drop as select count(*) n from cron.job where active;

CREATE OR REPLACE FUNCTION security.provider_english_inherit_tests_v1(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; lv text; v_ia numeric; q jsonb; v_ids uuid[]; v_courses uuid[] := '{}'; v_rows int := 0; v_added jsonb := '[]'::jsonb;
        v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' or x.status <> 'approved' then return jsonb_build_object('skipped', 'not an approved English policy'); end if;
  for lv in select k from jsonb_object_keys(coalesce(x.proposal->'defaults', '{}'::jsonb)) k where k in ('undergraduate', 'postgraduate') loop
    continue when jsonb_typeof(x.proposal->'defaults'->lv) is distinct from 'array';
    select (e->>'overall_score')::numeric into v_ia from jsonb_array_elements(x.proposal->'defaults'->lv) e where e->>'test_code' = 'IELTS' limit 1;
    continue when v_ia is null;
    for q in select e from jsonb_array_elements(x.proposal->'defaults'->lv) e
              where e->>'test_code' <> 'IELTS' and e->>'test_code' in (select t.code from ref.english_tests t where t.status = 'active')
                and coalesce(e->>'overall_score', '') ~ '^[0-9]+(\.[0-9]+)?$'
                and (select count(*) from jsonb_object_keys(case when jsonb_typeof(e->'component_scores') = 'object' then e->'component_scores' else '{}'::jsonb end) k
                      where k in ('listening', 'reading', 'writing', 'speaking')) = 4 loop
      with ins as (
        insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id,
                                                          confidence, source_requirement_key, status, last_verified_at)
        select r.course_id, t.id, (q->>'overall_score')::numeric, q->'component_scores',
               format('%s %s from the same approved English policy, added %s (the course''s IELTS for this level agrees with the policy; CF-247 s1047).', r.notes, t.name, v_day),
               r.source_id, r.evidence_id, r.confidence, 'policy:' || x.id || ':' || lower(q->>'test_code'), 'active', now()
          from catalogue.course_english_requirements r
          join ref.english_tests ti on ti.id = r.english_test_id and ti.code = 'IELTS'
          join catalogue.courses co on co.id = r.course_id and co.lifecycle_status = 'active'
          left join ref.study_levels sl on sl.id = co.study_level_id
          join ref.english_tests t on t.code = q->>'test_code'
         where r.source_requirement_key = 'policy:' || x.id || ':ielts' and r.status = 'active' and r.overall_score = v_ia
           and r.notes like 'Default for %'  -- level defaults only: a course the policy names keeps its own requirement
           and case when sl.code in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                    when sl.code in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate' end = lv
           and not exists (select 1 from catalogue.course_english_requirements o where o.course_id = r.course_id and o.english_test_id = t.id and o.status = 'active')
        on conflict (course_id, english_test_id) do nothing
        returning course_id)
      select array_agg(course_id) into v_ids from ins;
      v_rows := v_rows + coalesce(cardinality(v_ids), 0);
      v_courses := v_courses || coalesce(v_ids, '{}');
      v_added := v_added || jsonb_build_object('level', lv, 'test_code', q->>'test_code', 'overall_score', q->'overall_score', 'component_scores', q->'component_scores',
                                               'quote', q->>'quote', 'courses', coalesce(cardinality(v_ids), 0));
    end loop;
  end loop;
  if cardinality(v_courses) > 0 then
    perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct cc) from unnest(v_courses) cc), true);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'inherit_tests', 'english_policy: ' || x.url, jsonb_build_object('proposal_id', x.id, 'provider_id', x.provider_id, 'added', v_added, 'rows', v_rows,
            'rule', 'CF-247 s1047: other tests of the approved policy, four bands, insert only'), null);
  end if;
  return jsonb_build_object('proposal_id', x.id, 'rows', v_rows, 'courses', (select count(distinct cc) from unnest(v_courses) cc), 'added', v_added);
end $function$;
revoke all on function security.provider_english_inherit_tests_v1(uuid) from public, anon, authenticated;

create temp table s1047_out on commit drop as
select x.provider_id, x.id, security.provider_english_inherit_tests_v1(x.id) result
  from pipeline.provider_policy_proposals x
 where x.kind = 'english_policy' and x.status = 'approved'
   and x.provider_id in ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7', 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0', '1822b40a-8b13-44dc-8c37-106ae31bb447');

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1047_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1047_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if exists (select 1 from catalogue.course_english_requirements r where r.source_requirement_key like 'policy:%' and r.notes like '%CF-247 s1047%'
              and (select count(*) from jsonb_object_keys(r.component_scores) k where k in ('listening', 'reading', 'writing', 'speaking')) <> 4) then
    raise exception 'post-check: a row was added without its four band scores';
  end if;
end $post$;
