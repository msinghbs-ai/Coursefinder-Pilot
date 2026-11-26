-- CF-247 s1286 (S1-Build; SS-Programme-Control 27 Nov 2026 00:08 AEDT, "Production reliability and consumer integrity", item 2; defects found by the
-- s1176b consumer read-back sample, Pilot #1699).
-- HELD: this changes what Website v2, Website v3 and Zoho v2 serve for academic entry. It merges only after the Platform Admin approves it and the
-- Wix and Zoho developers are told (G3 consumer communication gate). Until then the pull request stays a draft and unlabelled.
-- Consumer API change approved: (pending, to be written here by the Platform Admin's decision with who, when and why)
-- Defects (read live 27 Nov 2026 00:20 AEDT):
--   1. A domestic-only row is served to international readers: 103424H (IN) serves "Equivalent to Australian Year 12." (audience domestic) in
--      requirements_note on Website v2, Zoho v2 and the v3 international read.
--   2. (not in this change; under investigation) a course resolves contact_provider for a country although it holds a course-level row.
--   3. A minimum grade with no numeric score is not served: 110070D's "grade point average (GPA) of 5.0 on a 7-point scale" (kind minimum_grade,
--      no min_entry_score) is missing from Website v2 and Zoho v2 (min_scores only takes numeric scores; requirements_note skipped the kind).
-- Change, in the shared payload security.entry_course_payload_v1 (md5 guarded, anchored edits; same signature, same keys):
--   the rows exclude audience domestic (the consumers serve international students); a minimum_grade row without a numeric score is given in
--   requirements_note. No key is added, renamed or removed.
-- G1: no job. G2: no setting. G3: no frozen object's definition changes (the payload is a helper they read); the served values change, so the gate above
-- applies. Locks and cron checked. Nothing dropped or deleted.
-- Replaces: security.entry_course_payload_v1 (md5 691bbba7). Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

create temp table s1286_guard on commit drop as select (select count(*) from pipeline.manual_locks) as locks_before;
create temp table s1286_cron on commit drop as select jobid from cron.job;  -- the job ids: this change creates none

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('security.entry_course_payload_v1(uuid,text)'::regprocedure)) <> '691bbba7958ebcd35ac332879c27d341' then raise exception 'guard: entry_course_payload_v1 changed'; end if;
end $g$;

do $e$
declare d text := pg_get_functiondef('security.entry_course_payload_v1(uuid,text)'::regprocedure);
        a1 constant text := 'where x.course_id = p_course and x.status = ''active'')';
        b1 constant text := 'where x.course_id = p_course and x.status = ''active'' and x.audience is distinct from ''domestic'' /* s1286: international readers only */)';
        a2 constant text := '''work_experience'')),';
        b2 constant text := '''work_experience'') or (r.kind = ''minimum_grade'' and r.min_entry_score is null /* s1286: a grade with no numeric score */)),';
begin
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then raise exception 'guard: the payload anchors are not found exactly once'; end if;
  execute replace(replace(d, a1, b1), a2, b2);
end $e$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1286_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1286_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
