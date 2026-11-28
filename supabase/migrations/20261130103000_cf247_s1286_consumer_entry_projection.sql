-- CF-247 s1286 (S1-Build; SS-Programme-Control 27 Nov 2026 00:08 AEDT, "Production reliability and consumer integrity", item 2; defects found by the
-- s1176b consumer read-back sample, Pilot #1699).
-- HELD: this changes what Website v2, Website v3 and Zoho v2 serve for academic entry. It merges only after the Platform Admin approves it and the
-- Wix and Zoho developers are told (G3 consumer communication gate). Until then the pull request stays a draft and unlabelled.
-- Consumer API change approved: Platform Admin, decision D9, 27 Nov 2026 (coursefinder-admin #1207 comment 7203709925): the three scoped corrections, with
--   safeguards (country-specific evidence keeps precedence; no inferred country equivalence; contextual, pathway or duration wording is not made a requirement;
--   response compatibility and G3 kept). Wix and Zoho developer notice: sent <date, by> (to be recorded before merge).
-- Defects (read live 27 Nov 2026 00:20 AEDT):
--   1. A domestic-only row is served to international readers: 103424H (IN) serves "Equivalent to Australian Year 12." (audience domestic) in
--      requirements_note on Website v2, Zoho v2 and the v3 international read.
--   2. A course's own international requirement is not used by the country resolution: security.entry_resolve_v1 reads a course override
--      (step 1) and the provider's per-country matrix (steps 2 to 4), and otherwise answers contact_provider ("No published requirement for
--      this country"). 9,555 of the 10,192 courses holding an international or all-audience row resolve contact_provider for IN; 2,222 courses
--      hold a minimum grade stated for every country (no country named).
--   3. A minimum grade with no numeric score is not served: 110070D's "grade point average (GPA) of 5.0 on a 7-point scale" (kind minimum_grade,
--      no min_entry_score) is missing from Website v2 and Zoho v2 (min_scores only takes numeric scores; requirements_note skipped the kind).
-- Change, in the shared payload security.entry_course_payload_v1 (md5 guarded, anchored edits; same signature, same keys):
--   the rows exclude audience domestic (the consumers serve international students); a minimum_grade row without a numeric score is given in
--   requirements_note. No key is added, renamed or removed.
-- And in security.entry_resolve_v1 (md5 guarded, one anchored insertion): before contact_provider, a new step answers with the course's own
--   minimum grade and prior qualification rows that are for international or all students and name no country (rule course_general, step 5,
--   the same row shape as course_override; outcome minimum_published when a row holds a grade or score, otherwise case_by_case). A new rule value
--   is additive; contact_provider is unchanged when the course holds no such row. The per-country matrix still wins (steps 1 to 4 unchanged).
--   Safeguards (D9): a row whose wording is about duration, a pathway or a possible route is never used for course_general (exclusion only; 792 of 16,842
--   rows on 27 Nov, the text stays in requirements_note); course_general carries scope all_countries and only the course's own stated text and figures,
--   so no country equivalence, eligibility or threshold is inferred.
-- G1: no job. G2: no setting. G3: no frozen object's definition changes (the payload is a helper they read); the served values change, so the gate above
-- applies. Locks and cron checked. Nothing dropped or deleted.
-- Replaces: security.entry_course_payload_v1 (md5 691bbba7); security.entry_resolve_v1 (md5 69bbc05f). Retires: nothing.
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
  if md5(pg_get_functiondef('security.entry_resolve_v1(uuid,text)'::regprocedure)) <> '69bbc05f650191954a22af09c0c85c74' then raise exception 'guard: entry_resolve_v1 changed'; end if;
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

do $e2$
declare d text := pg_get_functiondef('security.entry_resolve_v1(uuid,text)'::regprocedure);
        a constant text := '  -- 5 nothing published applies: contact the provider (never invented).';
        b constant text := $b$  -- 5 (s1286) the course's own requirement for international or all students that names no country: it applies to every country
  select jsonb_agg(jsonb_build_object('text', r.description, 'min_grade', r.min_grade, 'min_score', r.min_entry_score, 'min_score_basis', r.min_entry_score_basis,
                                      'quote', r.quote, 'as_at', r.as_at, 'case_by_case', r.min_grade is null and r.min_entry_score is null, 'scale_stated', null::boolean) order by r.created_at)
    into v_rows from catalogue.course_entry_requirements r
   where r.course_id = c.id and r.status = 'active' and r.kind in ('minimum_grade', 'prior_qualification') and r.audience in ('international', 'all') and r.country_id is null
     -- D9 safeguard: a row whose wording is about duration, a pathway or a possible route is not made a requirement (it stays in requirements_note)
     and r.description !~* '(\mto (complete|finish)\M[^.]{0,60}\min\M[^.]{0,20}\m(years?|months?|semesters?|trimesters?)\M|\mreduced (duration|length)\M|\maccelerated\M|\mduration\M|\mcomplete (the|this) (course|degree|program|programme)\M[^.]{0,30}\m(sooner|faster|earlier|quicker)\M)'
     and r.description !~* '(\mpathways?\M|\mmay include\M|\mmay (also )?be (eligible|considered|accepted|admitted|offered)\M|\mfoundation (studies|program|programme|year)\M|\madvanced standing\M|\mcredit (transfer|towards|for)\M|\mrecognition of prior learning\M|\mRPL\M|\mguaranteed entry\M)';
  if v_rows is not null then
    return jsonb_build_object('country', v_cc, 'step', 5, 'rule', 'course_general', 'scope', 'all_countries', 'rows', v_rows,
      'outcome', case when exists (select 1 from jsonb_array_elements(v_rows) z where not (z->>'case_by_case')::boolean) then 'minimum_published' else 'case_by_case' end);
  end if;
$b$;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the resolver anchor is not found exactly once'; end if;
  execute replace(d, a, b || a);
end $e2$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1286_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1286_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
