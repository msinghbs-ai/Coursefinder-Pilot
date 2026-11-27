-- CF-247 s1294 (S1-Build; SS-Programme-Control 27 Nov 2026 10:48 AEDT, "International Course Source Integrity and Autonomous Learning Integration" §4, §7;
-- design coursefinder-admin #1271; Agent Operating Model v1.29).
-- Read live 27 Nov 2026 11:05 AEDT:
--   * security.ops_learning_harvest_v1 (md5 8daa37d0, the learning step of first-run-verify) records only controller remedy runs. An issue closed by
--     engineering or a person, and a release fix that regressed, leaves no outcome in the recovery knowledge (14 days: 4 engineering closures without
--     a harvested remedy outcome; 24 issues regressed after fix_in_release).
--   * Phase A countrywide baseline reconciled exactly (AU 24,009 in scope: 16,981 international-tagged, 934 untagged, 6,094 missing; NZ 6,380:
--     2,076 / 855 / 3,449; CA 3,829: 1,974 / 778 / 1,077). 33 international-tagged official links (AU 32, NZ 1) have a domestic URL path or subdomain
--     (for example /domestic-courses/, -for-domestic-students, domestic.cbtc.edu.au). A URL is a signal, not proof: "Building (Domestic)" is a
--     qualification name. They are suspects for page verification, not corrections.
-- What it changes:
--   1. Mandatory closure learning, in the existing harvest (one anchored, md5-guarded edit): an issue closed or regressed outside a controller run
--      (a release remedy or a person's verification) records one outcome per closure or regression (deduplicated on the issue and the event time) in
--      pattern <remedy>:<root cause>:closure, created with the remedy's authority, performed by engineering, the Platform Admin or Layer 4, and never
--      automatic. Closed and passed is a success; regressed is a failure. learn.closure_days bounds the window (G2).
--   2. The course-link audience signal is held as knowledge (course_link lane, Layer 4 authority, not automatic) and the 33 suspect links are raised as
--      one integration issue for the course-link owner (S1-Data-Gaps) through security.integration_issue_upsert_v1. No link is changed.
-- G1: no job. G2: learn.closure_days is a setting. G3: 75/48 checked. Locks checked. Nothing dropped or deleted.
-- Replaces: security.ops_learning_harvest_v1 (md5 8daa37d0; one block added). Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

create temp table s1294_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before;
create temp table s1294_cron on commit drop as select jobid from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if md5(pg_get_functiondef('security.ops_learning_harvest_v1()'::regprocedure)) <> '8daa37d0de36cabf94d0fcb73287a373' then raise exception 'guard: security.ops_learning_harvest_v1 changed'; end if;
end $g$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'learn.closure_days', 'Recovery knowledge: closures harvested',
        'Issues closed or regressed in this many days, outside a controller run, each record one outcome in the recovery knowledge (a release fix that held, or one that regressed).',
        'number', to_jsonb(14), 1, 90, 'days', 1935, 'Recovery knowledge', 'security.ops_learning_harvest_v1 (job first-run-verify)', 'CF-247 s1294 (AOM v1.29, mandatory knowledge capture)')
on conflict do nothing;

do $e$
declare d text := pg_get_functiondef('security.ops_learning_harvest_v1()'::regprocedure);
        a1 constant text := '  -- remedy-level eligibility (platform patterns of the controller''s remedies)';
        b1 constant text := $b$  -- s1294: closures and regressions outside a controller run (engineering, Platform Admin, Layer 4) are knowledge too, once per event
  for x in select q.id, q.issue_ref, q.fingerprint, q.remedy_code, q.verified_by, q.verification_outcome, coalesce(q.diagnosis->>'root_cause', q.root_cause_class, 'unclassified') rc,
                  case when q.verification_outcome = 'regressed' then coalesce(q.reopened_at, q.updated_at) else q.closed_at end ev_at
             from pipeline.integration_issues q
            where q.remedy_code is not null
              and ((q.status = 'closed' and q.verification_outcome = 'passed' and q.closed_at > now() - make_interval(days => security.pipeline_num_v1('learn.closure_days', 14)::int))
                or (q.verification_outcome = 'regressed' and coalesce(q.reopened_at, q.updated_at) > now() - make_interval(days => security.pipeline_num_v1('learn.closure_days', 14)::int)))
              and (coalesce(q.verified_by, '') !~* 'ops-controller' or exists (select 1 from pipeline.ops_remedies rm where rm.code = q.remedy_code and rm.authority <> 'auto'))
              and not security.ops_learning_not_remedy_v1(q.fingerprint)
            order by q.id limit security.pipeline_num_v1('recovery.issues_per_run', 200)::int loop
    continue when exists (select 1 from pipeline.ops_remedy_outcomes o where o.issue_id = x.id and o.remedy_run_id is null and o.evidence->>'closure_event' = x.ev_at::text);
    select * into m from pipeline.ops_remedies where code = x.remedy_code;
    v_code := x.remedy_code || ':' || regexp_replace(lower(x.rc), '[^a-z0-9_]', '_', 'g') || ':closure'; v_ok := x.verification_outcome = 'passed';
    insert into pipeline.ops_remedy_knowledge(code, lane, title, fingerprint_like, root_cause, remedy_code, authority, performed_by, expected_outcome, no_retry_condition, reuse_conditions,
           auto_eligible, eligibility_reason, seeded_from)
    values (v_code, security.ops_learning_lane_v1(x.fingerprint, x.remedy_code), coalesce(m.title, x.remedy_code) || ' (closure, ' || x.rc || ')', array[x.fingerprint], x.rc, x.remedy_code,
            case when m.authority in ('auto', 'release', 'admin', 'layer4_human') then m.authority else 'release' end,
            case when x.verified_by ~* 'layer ?4|human|reviewer' then 'layer4_human' when x.verified_by ~* '^platform admin' then 'platform_admin' else 'claude_engineering' end,
            'the issue stays closed after the fix (no regression)', 'a fix that regressed on this fingerprint is not repeated unchanged: read the regression evidence first',
            'the same root cause on the same subsystem', false, 'closure record (s1294): engineering or human resolution, not an automatic remedy', 'integration_issues closure (harvested)')
    on conflict (code) do update set fingerprint_like = case when x.fingerprint = any (pipeline.ops_remedy_knowledge.fingerprint_like) then pipeline.ops_remedy_knowledge.fingerprint_like
                                                              else pipeline.ops_remedy_knowledge.fingerprint_like || x.fingerprint end;
    insert into pipeline.ops_remedy_outcomes(knowledge_code, issue_id, fingerprint, performed_by, applied_at, expected, observed, success, stage_advanced, evidence)
    values (v_code, x.id, x.fingerprint, (select k.performed_by from pipeline.ops_remedy_knowledge k where k.code = v_code), x.ev_at, 'the issue stays closed',
            jsonb_build_object('verification_outcome', x.verification_outcome, 'verified_by', x.verified_by), v_ok, v_ok,
            jsonb_build_object('issue', x.issue_ref, 'closure_event', x.ev_at::text, 'source', 's1294 closure harvest'));
    update pipeline.ops_remedy_knowledge k set applied = k.applied + 1, verified = k.verified + case when v_ok then 1 else 0 end, failed = k.failed + case when v_ok then 0 else 1 end,
           no_yield_streak = case when v_ok then 0 else k.no_yield_streak + 1 end, last_outcome_at = greatest(k.last_outcome_at, x.ev_at)
     where k.code = v_code;
    v_c := v_c + 1;
  end loop;
$b$;
        a2 constant text := 'return jsonb_build_object(''harvested'', v_n,';
        b2 constant text := 'return jsonb_build_object(''closures_harvested'', v_c, ''harvested'', v_n,';
        a3 constant text := 'v_n int := 0; v_b int := 0; v_lost int := 0;';
        b3 constant text := 'v_n int := 0; v_b int := 0; v_lost int := 0; v_c int := 0;';
begin
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1
     or (length(d) - length(replace(d, a3, ''))) / length(a3) <> 1 then raise exception 'guard: a harvest anchor is not found exactly once'; end if;
  execute replace(replace(replace(d, a3, b3), a1, b1 || a1), a2, b2);
end $e$;

insert into pipeline.ops_remedy_knowledge (code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
  no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
values ('course_link:domestic_page_tagged_international', 'course_link', 'Official course link tagged international points at a domestic page',
  array['course_link:audience:%'], 'link_audience_unproven', null,
  '{"signal": "an international-tagged official_course link whose path or subdomain names domestic students", "negative_control": "a qualification name containing Domestic (for example Building (Domestic)) is not an audience"}'::jsonb,
  'layer4_human', 'layer4_human', 'the link opens the exact course in its international view, or the shared page with an honest audience instruction; a domestic page is never kept as international',
  'do not relabel the link or copy domestic values as international; verify the rendered page (identity and audience markers) before any change',
  'the provider''s qualified website rule (course_link_recipes / source profile) selects the international view for this template',
  false, 'signal only: URL wording is not proof (design #1271 §4); verification by the course-link owner', now(), 'S1-Build (s1294)', 'Phase A countrywide baseline 27 Nov (design #1271)')
on conflict (code) do nothing;

do $i$
declare v_list jsonb; v_n int;
begin
  select jsonb_agg(jsonb_build_object('course_code', c.course_code, 'provider', p.canonical_name, 'country', ct.iso_alpha2, 'url', l.url) order by ct.iso_alpha2, p.canonical_name, c.course_code), count(*)
    into v_list, v_n
    from catalogue.course_links l join catalogue.courses c on c.id = l.course_id join catalogue.providers p on p.id = c.provider_id join ref.countries ct on ct.id = p.country_id
   where l.link_type = 'official_course' and l.audience = 'international' and coalesce(l.status, 'active') = 'active' and (l.valid_to is null or l.valid_to >= current_date)
     and c.lifecycle_status = 'active' and p.publication_status = 'published' and ct.iso_alpha2 in ('AU', 'NZ', 'CA') and c.open_to_international is not false
     and l.url ~* '(domestic|/local-students|australian-(students|citizens)|/au-students|[?&](audience|studenttype|student_type|type|residency)=(dom|domestic|local|au|nz))';
  if v_n > 0 then
    perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'course_link:audience:domestic_path_tagged_international',
      'title', v_n || ' international-tagged official course links point at a domestic page path (Phase A, AU/NZ/CA)', 'layer', 'Layer 2', 'subsystem', 'course links',
      'failure', 'The link is tagged international but its path or subdomain names domestic students; the student may land on domestic content.',
      'expected', 'Each link verified on the rendered page: the international view, an honest shared link with audience instruction, or a held exception. URL wording alone is not proof.',
      'source', 'S1-Build Phase A (s1294)', 'validation_layer', 'V4', 'severity', 'P2', 'root_cause_class', 'unclassified', 'workstream', 'A7', 'assignee', 'S1-Data-Gaps',
      'evidence', jsonb_build_object('links', v_list, 'knowledge', 'course_link:domestic_page_tagged_international', 'negative_control', 'Building (Domestic) is a qualification name')), 'S1-Build');
  end if;
end $i$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); d text := pg_get_functiondef('security.ops_learning_harvest_v1()'::regprocedure);
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if position('s1294: closures and regressions outside a controller run' in d) = 0 then raise exception 'post-check: the closure harvest is not in place'; end if;
  if not exists (select 1 from pipeline.ops_remedy_knowledge where code = 'course_link:domestic_page_tagged_international' and not auto_eligible) then raise exception 'post-check: the link signal is not held'; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1294_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1294_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
