-- CF-247 s1073 (S1-RM-Design; Platform Admin 24 Nov 2026 18:02 AEDT, scholarship publication recovery from existing data only).
-- Publication check "provider page limits it to citizens and residents" (security.scholarship_publishability_for_v1) held an award whenever its stored
-- eligibility excerpt named citizens or permanent residents and did not contain the word "international". Excerpts that open the award to
-- international students in other words were held wrongly, e.g. "Open to foreign nationals holding Canadian study permits" (six Canadian graduate
-- awards), "or foreign national enrolled in a doctoral program" (Trudeau), "Visa Students. Foreign students ... are eligible" (Ontario Graduate
-- Scholarship), "must: not be a domestic student" (Griffith International Postgraduate Research Scholarship).
-- The check now also accepts precise international phrases, from the same vocabulary as the worker's audience proof rule (coverage-sweep INTL_WORDS):
-- foreign national(s), foreign student(s), overseas student/applicant/candidate(s), student visa, study permit, subclass 500, "not be a domestic
-- student". Bare "overseas" or "foreign" is not enough ("be born overseas" describes a citizen or resident), and an excerpt that excludes
-- international students ("must not hold a student visa", "international students are not eligible") still holds. No other check changes.
-- Live effect measured 24 Nov 2026 18:40 AEDT: 9 active unpublished awards held only by this check become publishable (8 CA, 1 AU); the hourly
-- scholarship-auto-publish job publishes them. No AI, no Firecrawl, no new job.
-- The function is changed in place from its md5-checked live definition; the edited line must match exactly once.
-- G1: no job. G2: no operational value. G3: no consumer object (75/48 checked). Manual locks and active cron jobs checked unchanged.
-- Replaces: the "international"-only test in the citizens-and-residents publication check
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.scholarship_publishability_for_v1(uuid[])'::regprocedure)) <> '557adb0a40cd99edb4623bd4dbd1eebc' then
    raise exception 'guard: scholarship_publishability_for_v1 is not the definition this change was written against';
  end if;
end $g$;
create temp table s1073_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1073_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1073_before on commit drop as
  select p.scholarship_id, p.publishable, p.missing from security.scholarship_publishability_v1() p;

do $r$
declare d text := pg_get_functiondef('security.scholarship_publishability_for_v1(uuid[])'::regprocedure);
        o text := E'                  and coalesce(sp.facts->>''eligibility_excerpt'','''') !~* ''international'' then ''provider page limits it to citizens and residents'' end,';
        n text := E'                  and coalesce(sp.facts->>''eligibility_excerpt'','''') !~* ''international''\n'
               || E'                  -- s1073: international students named in other words (same vocabulary as the worker''s audience proof), unless the excerpt excludes them\n'
               || E'                  and not (coalesce(sp.facts->>''eligibility_excerpt'','''') ~* ''\\m(foreign nationals?|foreign students?|overseas (students?|applicants?|candidates?)|student visas?|study permits?|subclass 500|not (be )?an? domestic student)\\M''\n'
               || E'                           and coalesce(sp.facts->>''eligibility_excerpt'','''') !~* ''(not|never|cannot|no longer)\\s+(hold|have|be on|be|on)\\s+(an?\\s+)?(temporary|student visa|international|overseas|foreign)|(international|overseas|foreign) (students|applicants|nationals) (are|is) (not |in)eligible|not (open|available) to (international|overseas|foreign)'')\n'
               || E'                  then ''provider page limits it to citizens and residents'' end,';
begin
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 's1073: expected exactly one citizens-and-residents line'; end if;
  execute replace(d, o, n);
end $r$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1(); v_new int; v_other int; v_rule int;
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1073_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1073_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  -- only this check moved: every record keeps every other reason it had
  select count(*) into v_other from s1073_before b join security.scholarship_publishability_v1() a on a.scholarship_id = b.scholarship_id
   where array_remove(b.missing, 'provider page limits it to citizens and residents') is distinct from array_remove(a.missing, 'provider page limits it to citizens and residents');
  if v_other <> 0 then raise exception 'post-check: % records changed a reason other than the citizens-and-residents check', v_other; end if;
  -- the check only ever clears, never adds
  select count(*) into v_rule from s1073_before b join security.scholarship_publishability_v1() a on a.scholarship_id = b.scholarship_id
   where not ('provider page limits it to citizens and residents' = any(b.missing)) and 'provider page limits it to citizens and residents' = any(a.missing);
  if v_rule <> 0 then raise exception 'post-check: % records newly held by the citizens-and-residents check', v_rule; end if;
  select count(*) into v_new from s1073_before b join security.scholarship_publishability_v1() a on a.scholarship_id = b.scholarship_id
    join scholarship.scholarships s on s.id = b.scholarship_id
   where not b.publishable and a.publishable and s.lifecycle_status = 'active' and coalesce(s.publication_status, 'unpublished') = 'unpublished';
  if v_new > 20 then raise exception 'post-check: % records became publishable, more than measured (9); stop and review', v_new; end if;  -- fixed: a bound on the measured effect
  raise notice 's1073: % active unpublished scholarships became publishable', v_new;
end $post$;
