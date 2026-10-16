-- CF-247 R18 (17 Oct 2026): Duolingo English Test (DET) scores on courses. Website developer request (Raghav, 16 Oct 2026); Platform Admin
-- 16 Oct 2026 23:44 ("Start planning developer latest request & create feature number for each of them") and 17 Oct 2026 00:29 ("Proceed with
-- next steps").
-- 1 DET is an English test (10 to 160 in steps of 5; overall score only: its subscores are not the four IELTS skills).
-- 2 The policy parser (coverage-sweep policy.ts v0.2.3) reads DET. New policy readings carry it from the start.
-- 3 Policies approved before the parser knew a test: job policy-add-tests (hourly, catalogued) has the worker read each approved policy's own
--   stored page again (mode provider_facts_add_tests; no Firecrawl, no AI) and svc_provider_english_add_tests_v1 adds a test for a level only
--   where this reading's IELTS for the level equals the approved IELTS, and only to courses that already hold that policy's level default
--   (key policy:<proposal>:ielts, notes "Default for ..."). A course the policy names, or one with its own DET, is left as it is. The approved
--   policy keeps the added test, so courses that take the policy later get it too. Each policy is checked once per parser version.
-- 50 stored policy pages of 385 mention Duolingo (41 universities, mostly Canada), measured 17 Oct 2026.
-- The website API needs no change: english_test_codes, the reference list and course items take every test held (DET appears as data).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted.

insert into ref.english_tests(code, name, status, score_scale)
values ('DET', 'Duolingo English Test', 'active', '{"min": 10, "max": 160, "step": 5, "overall_only": true}'::jsonb)
on conflict (code) do nothing;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.policy_add_tests', 'Approved English policies checked for new tests per run', 'Each run of the policy-add-tests job reads this many approved English policy pages again (stored copies, no Firecrawl, no AI) to add tests the parser has learnt since (first the Duolingo English Test).', 'number', to_jsonb(40), 5, 200, 'policies', 312, 'CF-247 R18, 17 Oct 2026: Duolingo English Test', 'Enrichment', 'job policy-add-tests; coverage-sweep provider_facts_add_tests')
on conflict (toolset_key, key) do nothing;

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
       and coalesce(pp.proposal->'added_tests'->>'parser', '') is distinct from p_parser
     order by pp.decided_at
     limit greatest(1, least(coalesce(p_limit, 40), 200))) s), '[]'::jsonb);  -- fixed: per-call safety cap; the run size is batch.policy_add_tests
end $function$;

create or replace function public.svc_provider_english_add_tests_v1(p_proposal_id uuid, p_parser text, p_parsed jsonb, p_error text default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare x pipeline.provider_policy_proposals%rowtype; lv text; v_appr jsonb; v_new jsonb; v_ia numeric; v_ip numeric; q jsonb;
        v_prop jsonb; v_added jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb; v_ids uuid[]; v_courses uuid[] := '{}'; v_rows int := 0;
        v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id for update;
  if x.id is null or x.kind <> 'english_policy' or x.status <> 'approved' then return jsonb_build_object('skipped', 'not an approved English policy'); end if;
  v_prop := x.proposal - 'added_tests';
  if p_parsed is not null and p_error is null then
    for lv in select k from jsonb_object_keys(coalesce(p_parsed->'defaults', '{}'::jsonb)) k where k in ('undergraduate', 'postgraduate') loop
      v_appr := v_prop->'defaults'->lv;
      if jsonb_typeof(v_appr) is distinct from 'array' then
        v_skipped := v_skipped || jsonb_build_object('level', lv, 'why', 'the approved policy has no default for this level'); continue;
      end if;
      v_ia := null; v_ip := null;
      select (e->>'overall_score')::numeric into v_ia from jsonb_array_elements(v_appr) e where e->>'test_code' = 'IELTS' limit 1;
      select (e->>'overall_score')::numeric into v_ip from jsonb_array_elements(p_parsed->'defaults'->lv) e where e->>'test_code' = 'IELTS' limit 1;
      if v_ia is null or v_ip is distinct from v_ia then
        v_skipped := v_skipped || jsonb_build_object('level', lv, 'why', format('IELTS on this reading (%s) is not the approved IELTS (%s)', coalesce(v_ip::text, 'none'), coalesce(v_ia::text, 'none')));
        continue;
      end if;
      select coalesce(jsonb_agg(e), '[]'::jsonb) into v_new from jsonb_array_elements(p_parsed->'defaults'->lv) e
       where e->>'test_code' in (select t.code from ref.english_tests t where t.status = 'active')
         and not exists (select 1 from jsonb_array_elements(v_appr) a where a->>'test_code' = e->>'test_code');
      if jsonb_array_length(v_new) = 0 then continue; end if;
      v_prop := jsonb_set(v_prop, array['defaults', lv], v_appr || v_new);
      for q in select e from jsonb_array_elements(v_new) e loop
        with ins as (
          insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id,
                                                            confidence, source_requirement_key, status, last_verified_at)
          select r.course_id, t.id, (q->>'overall_score')::numeric, coalesce(q->'component_scores', '{}'::jsonb),
                 format('%s %s from the same stored page, added %s (the page''s IELTS for this level matches the approved policy).', r.notes, t.name, v_day),
                 r.source_id, r.evidence_id, r.confidence, 'policy:' || x.id || ':' || lower(q->>'test_code'), 'active', now()
            from catalogue.course_english_requirements r
            join ref.english_tests ti on ti.id = r.english_test_id and ti.code = 'IELTS'
            join catalogue.courses co on co.id = r.course_id
            left join ref.study_levels sl on sl.id = co.study_level_id
            join ref.english_tests t on t.code = q->>'test_code'
           where r.source_requirement_key = 'policy:' || x.id || ':ielts' and r.status = 'active' and r.overall_score = v_ia
             and r.notes like 'Default for %'  -- level defaults only: a course the policy names keeps its own requirement
             and case when sl.code in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                      when sl.code in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate' end = lv
          on conflict (course_id, english_test_id) do nothing
          returning course_id)
        select array_agg(course_id) into v_ids from ins;
        v_rows := v_rows + coalesce(cardinality(v_ids), 0);
        v_courses := v_courses || coalesce(v_ids, '{}');
        v_added := v_added || jsonb_build_object('level', lv, 'test_code', q->>'test_code', 'overall_score', q->'overall_score', 'quote', q->>'quote',
                                                 'courses', coalesce(cardinality(v_ids), 0));
      end loop;
    end loop;
  end if;
  update pipeline.provider_policy_proposals
     set proposal = v_prop || jsonb_build_object('added_tests', jsonb_build_object('parser', p_parser, 'checked_at', now(), 'added', v_added, 'skipped', v_skipped, 'error', p_error)),
         plan_at = case when jsonb_array_length(v_added) > 0 then null else plan_at end, updated_at = now()
   where id = x.id;
  if cardinality(v_courses) > 0 then
    perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct c) from unnest(v_courses) c), true);
  end if;
  if jsonb_array_length(v_added) > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'add_tests', 'english_policy: ' || x.url, jsonb_build_object('proposal_id', x.id, 'provider_id', x.provider_id, 'parser', p_parser, 'added', v_added, 'rows', v_rows), null);
  end if;
  return jsonb_build_object('added', jsonb_array_length(v_added), 'rows', v_rows, 'skipped', jsonb_array_length(v_skipped));
end $function$;

revoke execute on function public.svc_provider_policy_add_tests_next(text, integer), public.svc_provider_english_add_tests_v1(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_provider_policy_add_tests_next(text, integer), public.svc_provider_english_add_tests_v1(uuid, text, jsonb, text) to service_role;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('policy-add-tests', 'Enrichment', 47, 'English policies: add new tests', 'Hourly: reads approved English policy pages again from their stored copies (no Firecrawl, no AI) and adds tests the parser has learnt since approval (first the Duolingo English Test), only where the page''s IELTS for the level matches the approved policy. Each policy is checked once per parser version.', 4, false)
on conflict (jobname) do nothing;
select cron.schedule('policy-add-tests', '17 * * * *',
  $$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_facts_add_tests', 'limit', security.pipeline_num_v1('batch.policy_add_tests', 40)::int))$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('job', 'policy-add-tests', 'Layer 2', 'Adds tests learnt by the policy parser (DET) to approved English policies from their stored pages', 'active', '20261017020000'),
 ('function', 'public.svc_provider_policy_add_tests_next', 'Layer 2', 'Approved English policies not yet checked by the current parser', 'active', '20261017020000'),
 ('function', 'public.svc_provider_english_add_tests_v1', 'Layer 2', 'Adds a newly read test to an approved English policy and its level-default courses', 'active', '20261017020000')
on conflict (kind, name) do nothing;

do $post$
begin
  if not exists (select 1 from ref.english_tests where code = 'DET' and status = 'active') then raise exception 'R18 post-check: DET missing'; end if;
  if not exists (select 1 from cron.job where jobname = 'policy-add-tests' and active) then raise exception 'R18 post-check: job missing'; end if;
end $post$;
