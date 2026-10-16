-- CF-247 R18 fix (17 Oct 2026), after the first add-tests run (80 policies, Duolingo for 14, 347 course rows):
-- 1 Flinders' row "Duolingo English Test^: 105 Overall ; 110 Speaking ; 110 Writing" was read as 110. The policy parser v0.2.4 (coverage-sweep
--   worker v0.27.1) no longer takes a number after "Overall" that names a skill, so it reads 105 (the same fix applies to every test).
-- 2 One approved policy (Canberra, an AI reading with IELTS only) took PTE, TOEFL iBT and Cambridge into its stored defaults (no course rows).
--   Only tests the parser learnt after approval are added now: the worker sends them (add_only, today DET only); anything else is left out.
-- 3 A test added earlier by this rule is read again on each parser version: its rows are corrected to the new reading, or withdrawn (status
--   withdrawn, never deleted) when the new reading no longer gives it or the page's IELTS no longer matches the approved policy; then a flag
--   asks a person to look at the policy (enrichment_flags, reason policy_reading_differs).
-- Every approved policy is checked again because the parser version changed. Job policy-add-tests was paused at 00:51 on 17 Oct 2026 and is
-- switched back on here.
-- Replaces: public.svc_provider_english_add_tests_v1 (same name, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('public.svc_provider_english_add_tests_v1(uuid,text,jsonb,text)'::regprocedure)) <> '8f9bf4618f48a5efb5b05ebe8cc137eb' then
    raise exception 'live public.svc_provider_english_add_tests_v1 differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function public.svc_provider_english_add_tests_v1(p_proposal_id uuid, p_parser text, p_parsed jsonb, p_error text default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare x pipeline.provider_policy_proposals%rowtype; lv text; v_appr jsonb; v_base jsonb; v_new jsonb; v_ia numeric; v_ip numeric; q jsonb; c text;
        v_prop jsonb; v_added jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb; v_ids uuid[]; v_courses uuid[] := '{}'; v_rows int := 0; v_out int := 0; n int;
        v_scope text[] := array(select jsonb_array_elements_text(coalesce(p_parsed->'add_only', '[]'::jsonb)));
        v_prior jsonb; v_keep text[]; v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id for update;
  if x.id is null or x.kind <> 'english_policy' or x.status <> 'approved' then return jsonb_build_object('skipped', 'not an approved English policy'); end if;
  v_prior := coalesce(x.proposal->'added_tests'->'added', '[]'::jsonb);
  v_prop := x.proposal - 'added_tests';
  -- take out what this rule added before (it is read again below)
  for lv in select distinct e->>'level' from jsonb_array_elements(v_prior) e loop
    if jsonb_typeof(v_prop->'defaults'->lv) = 'array' then
      v_prop := jsonb_set(v_prop, array['defaults', lv], (select coalesce(jsonb_agg(a), '[]'::jsonb) from jsonb_array_elements(v_prop->'defaults'->lv) a
                                                         where not exists (select 1 from jsonb_array_elements(v_prior) e where e->>'level' = lv and e->>'test_code' = a->>'test_code')));
    end if;
  end loop;
  if p_parsed is not null and p_error is null and cardinality(v_scope) > 0 then
    for lv in select k from jsonb_object_keys(coalesce(p_parsed->'defaults', '{}'::jsonb)) k where k in ('undergraduate', 'postgraduate') loop
      v_base := v_prop->'defaults'->lv;
      if jsonb_typeof(v_base) is distinct from 'array' then
        v_skipped := v_skipped || jsonb_build_object('level', lv, 'why', 'the approved policy has no default for this level'); continue;
      end if;
      v_ia := null; v_ip := null;
      select (e->>'overall_score')::numeric into v_ia from jsonb_array_elements(v_base) e where e->>'test_code' = 'IELTS' limit 1;
      select (e->>'overall_score')::numeric into v_ip from jsonb_array_elements(p_parsed->'defaults'->lv) e where e->>'test_code' = 'IELTS' limit 1;
      if v_ia is null or v_ip is distinct from v_ia then
        v_skipped := v_skipped || jsonb_build_object('level', lv, 'why', format('IELTS on this reading (%s) is not the approved IELTS (%s)', coalesce(v_ip::text, 'none'), coalesce(v_ia::text, 'none')));
        if v_ip is not null and v_ia is not null then
          insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
          values ('policy', x.id::text, x.provider_id, 'english', 'policy_reading_differs',
                  format('The %s IELTS on the stored policy page reads %s; the approved policy holds %s. A person checks the policy (%s)', lv, v_ip, v_ia, x.url), 'policy-add-tests')
          on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
        end if;
        continue;
      end if;
      select coalesce(jsonb_agg(e), '[]'::jsonb) into v_new from jsonb_array_elements(p_parsed->'defaults'->lv) e
       where e->>'test_code' = any (v_scope) and e->>'test_code' in (select t.code from ref.english_tests t where t.status = 'active')
         and not exists (select 1 from jsonb_array_elements(v_base) a where a->>'test_code' = e->>'test_code');
      if jsonb_array_length(v_new) = 0 then continue; end if;
      v_prop := jsonb_set(v_prop, array['defaults', lv], v_base || v_new);
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
          on conflict (course_id, english_test_id) do update
             set overall_score = excluded.overall_score, component_scores = excluded.component_scores, notes = excluded.notes,
                 evidence_id = excluded.evidence_id, status = 'active', last_verified_at = now()
           where catalogue.course_english_requirements.source_requirement_key = excluded.source_requirement_key  -- only rows this rule wrote
          returning course_id)
        select array_agg(course_id) into v_ids from ins;
        v_rows := v_rows + coalesce(cardinality(v_ids), 0);
        v_courses := v_courses || coalesce(v_ids, '{}');
        v_added := v_added || jsonb_build_object('level', lv, 'test_code', q->>'test_code', 'overall_score', q->'overall_score', 'quote', q->>'quote',
                                                 'courses', coalesce(cardinality(v_ids), 0));
      end loop;
    end loop;
  end if;
  -- a test added before that this reading no longer gives for that level: its rows are withdrawn (kept, not deleted)
  for lv, c in select distinct e->>'level', e->>'test_code' from jsonb_array_elements(v_prior) e loop
    if exists (select 1 from jsonb_array_elements(v_added) a where a->>'level' = lv and a->>'test_code' = c) then continue; end if;
    with w as (
      update catalogue.course_english_requirements r set status = 'withdrawn', last_verified_at = now(),
             notes = r.notes || format(' Withdrawn %s: the stored page read again no longer gives it for this level.', v_day)
        from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id
       where co.id = r.course_id and r.source_requirement_key = 'policy:' || x.id || ':' || lower(c) and r.status = 'active'
         and r.notes like '%from the same stored page, added%'
         and case when sl.code in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                  when sl.code in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate' end = lv
      returning r.course_id)
    select array_agg(course_id) into v_ids from w;
    n := coalesce(cardinality(v_ids), 0); v_out := v_out + n;
    v_courses := v_courses || coalesce(v_ids, '{}');
  end loop;
  update pipeline.provider_policy_proposals
     set proposal = v_prop || jsonb_build_object('added_tests', jsonb_build_object('parser', p_parser, 'checked_at', now(), 'added', v_added, 'skipped', v_skipped,
                                                                                 'withdrawn_rows', v_out, 'error', p_error)),
         plan_at = case when v_rows + v_out > 0 then null else plan_at end, updated_at = now()
   where id = x.id;
  if cardinality(v_courses) > 0 then
    perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct cc) from unnest(v_courses) cc), true);
  end if;
  if v_rows + v_out > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'add_tests', 'english_policy: ' || x.url, jsonb_build_object('proposal_id', x.id, 'provider_id', x.provider_id, 'parser', p_parser,
            'added', v_added, 'rows', v_rows, 'withdrawn_rows', v_out), null);
  end if;
  return jsonb_build_object('added', jsonb_array_length(v_added), 'rows', v_rows, 'withdrawn', v_out, 'skipped', jsonb_array_length(v_skipped));
end $function$;

revoke execute on function public.svc_provider_english_add_tests_v1(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_provider_english_add_tests_v1(uuid, text, jsonb, text) to service_role;

select cron.alter_job((select jobid from cron.job where jobname = 'policy-add-tests'), active := true);
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('automations', 'resume', 'policy-add-tests', jsonb_build_object('reason', 'R18 fix applied (migration 20261017030000, parser v0.2.4)'), null);
