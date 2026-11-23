-- CF-247 s1000 (S2-RM-Design; Platform Admin 23 Nov 2026 12:29 AEDT, Priority 1: "8,515 courses marked academic_entry = no_reader despite having
-- active, evidence-backed international/all-audience academic requirement rows ... across canonical admission, security.entry_resolve_v1, field
-- coverage and Website/Zoho v3 results. Do not merely adjust the coverage counter"; contract: admin DESTINATION-DATA-DESIGN.md v1.12 section A).
-- Measured live 23 Nov 2026 12:30 to 12:47 AEDT (rolled-back read-backs; head 20261123060000):
--   8,957 active courses (AU 8,601, NZ 356) read academic_entry no_reader while holding active, quoted, evidence-backed course entry rows for
--   international or all applicants, every one for any country; 8,515 of them hold the academic kinds minimum_grade, prior_qualification or
--   subject_prerequisite (the audit's figure); 2,905 state a minimum. The rows are already canonical (status active); the gap is that
--   security.entry_resolve_v1 rule 1 reads only kind 'override', and the coverage rule (security.aer_covered_courses_v1 and its chunk copy in
--   security.course_coverage_build_v1) counts only override rows, per-course matrix rows and provider minimums. So Website and Zoho v3 answer
--   "contact the provider" for these courses and field coverage reports no reader.
-- Why the v1 resolver is not edited: it is part of the frozen v2 payload (public.website_v2_course -> security.entry_course_payload_v1 ->
--   security.entry_resolve_v1; its last change, D5 on 30 Oct 2026, needed a recorded consumer API approval). G3 keeps v2 as it is.
-- What changes (no table, job or setting; v2, Zoho v2 and every function of the consumer API unchanged):
--   1. New security.entry_resolve_v3(course, country): security.entry_resolve_v1's answer, except that where it is step 5 (contact the provider),
--      the course's own active rows of kind minimum_grade, prior_qualification or subject_prerequisite for international or all applicants, with
--      a quote and evidence, for this country or any country (a row whose stated minimum is an age is left out: 1,119 such rows read live), are returned as rule 1 (course_override: "a course with its own international
--      rule"), in the v1 row shape. No enum value or field is added; any non-step-5 answer is returned unchanged.
--   2. public.website_v3_course(text, text) uses it only where the v2 answer is step 5; zoho_v3_course copies the Website v3 entry, so Zoho v3
--      follows. Website API v3 is open to additions (Decision 277); this is a data correction, not a shape change.
--   3. Field coverage: the same rows count for academic_entry in security.aer_covered_courses_v1 and its chunk copy in
--      security.course_coverage_build_v1 (rollup-scheduler recomputes every chunk in its normal cycle).
--   4. The Admin resolve views (admin_entry_requirements, admin_aer) show the v3 answer, so operators see what Website and Zoho v3 serve.
-- Live on deploy. G1: no job. G2: no operational value. G3: no consumer object (75/48 before and after; entry_resolve_v1 and website_v2_course
-- md5 checked unchanged). Manual locks untouched. $0. Nothing dropped or removed.
-- Replaces: one fragment each of security.aer_covered_courses_v1, security.course_coverage_build_v1, public.website_v3_course(text, text) (two),
-- public.admin_entry_requirements and public.admin_aer (the resolver they call).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edits

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5((select prosrc from pg_proc where oid = 'security.entry_resolve_v1(uuid,text)'::regprocedure)) <> '9f59f7d54a8a1bcd9d89302c2c977ae3' then
    raise exception 'guard: security.entry_resolve_v1 differs from the definition read on 23 Nov 2026';
  end if;
end $g$;
create temp table s1000_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs,
         (select md5(prosrc) from pg_proc where oid = 'public.website_v2_course(text,text)'::regprocedure) v2md5,
         (select count(*) from security.aer_covered_courses_v1()) covered_before;

create or replace function security.entry_resolve_v3(p_course uuid, p_country text)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare r jsonb := security.entry_resolve_v1(p_course, p_country); v_cc text := upper(btrim(coalesce(p_country, ''))); v_rows jsonb;
begin
  -- s1000 (23 Nov 2026): v1's answer unless it is step 5; then the course page's own evidence-backed academic rows, as rule 1
  if r->>'step' is distinct from '5' then return r; end if;
  select jsonb_agg(jsonb_build_object('text', x.description, 'min_grade', x.min_grade, 'min_score', x.min_entry_score, 'min_score_basis', x.min_entry_score_basis,
                                      'quote', x.quote, 'as_at', x.as_at, 'case_by_case', x.min_grade is null and x.min_entry_score is null, 'scale_stated', null::boolean)
                   order by array_position(array['minimum_grade', 'prior_qualification', 'subject_prerequisite'], x.kind), x.created_at)
    into v_rows from catalogue.course_entry_requirements x left join ref.countries k on k.id = x.country_id
   where x.course_id = p_course and x.status = 'active' and x.kind in ('minimum_grade', 'prior_qualification', 'subject_prerequisite')
     and x.audience in ('international', 'all') and x.evidence_id is not null and nullif(btrim(x.quote), '') is not null
     and not (x.min_entry_score is not null and (coalesce(x.min_entry_score_basis, '') ~* '(\mage\M|years? (old|of age)|years (or|and) (over|older|above))' or x.quote ~* '(minimum age|years of age|years old)'))  -- an age limit is not an academic minimum
     and (x.country_id is null or k.iso_alpha2 = v_cc);
  if v_rows is null then return r; end if;
  return jsonb_build_object('country', v_cc, 'step', 1, 'rule', 'course_override', 'rows', v_rows,
    'outcome', case when exists (select 1 from jsonb_array_elements(v_rows) z where not (z->>'case_by_case')::boolean) then 'minimum_published' else 'case_by_case' end);
end $f$;
revoke all on function security.entry_resolve_v3(uuid, text) from public, anon, authenticated;
comment on function security.entry_resolve_v3(uuid, text) is 'CF-247 s1000: security.entry_resolve_v1''s answer; where it is step 5, the course''s own active, quoted, evidence-backed academic rows (an age limit left out) (minimum_grade, prior_qualification, subject_prerequisite; international or all; this country or any) as rule 1. Used by Website and Zoho API v3 and the Admin resolve views; v2 keeps v1 (G3).';

do $e$
declare r record; v_def text; v_src text; v_n int;
begin
  for r in select * from (values
  (1, 'security.aer_covered_courses_v1()', '0d1881c093696f9c6dd46fa974595627', $o1$   where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)$o1$, $n1$   where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)
  union  -- s1000 (23 Nov 2026): rule 1 of the v3 resolver, the course page's own evidence-backed academic rows
  select r.course_id from catalogue.course_entry_requirements r
   where r.status = 'active' and r.kind in ('minimum_grade', 'prior_qualification', 'subject_prerequisite') and r.audience in ('international', 'all')
     and r.evidence_id is not null and nullif(btrim(r.quote), '') is not null
     and not (r.min_entry_score is not null and (coalesce(r.min_entry_score_basis, '') ~* '(\mage\M|years? (old|of age)|years (or|and) (over|older|above))' or r.quote ~* '(minimum age|years of age|years old)'))$n1$),
  (2, 'security.course_coverage_build_v1()', '97f8eee0bd30d093070ea242fe710ebc', $o2$   where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)
     and r.course_id in (select course_id from _c);$o2$, $n2$   where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)
     and r.course_id in (select course_id from _c)
  union  -- s1000 (23 Nov 2026): rule 1 of the v3 resolver, the course page's own evidence-backed academic rows
  select r.course_id from catalogue.course_entry_requirements r
   where r.status = 'active' and r.kind in ('minimum_grade', 'prior_qualification', 'subject_prerequisite') and r.audience in ('international', 'all')
     and r.evidence_id is not null and nullif(btrim(r.quote), '') is not null
     and not (r.min_entry_score is not null and (coalesce(r.min_entry_score_basis, '') ~* '(\mage\M|years? (old|of age)|years (or|and) (over|older|above))' or r.quote ~* '(minimum age|years of age|years old)'))
     and r.course_id in (select course_id from _c);$n2$),
  (3, 'public.website_v3_course(text,text)', '473289a0a58b4a37e951d54f6a99013d', $o3$declare v jsonb := public.website_v2_course(p_identifier, p_edu_country); v_course uuid; v_provider uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));$o3$, $n3$declare v jsonb := public.website_v2_course(p_identifier, p_edu_country); v_course uuid; v_provider uuid; v_cc text := upper(btrim(coalesce(p_edu_country, ''))); v_res jsonb;$n3$),
  (4, 'public.website_v3_course(text,text)', null, $o4$  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
$o4$, $n4$  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  -- s1000 (23 Nov 2026): where the frozen v2 resolver answers "contact the provider", v3 serves the course page's own evidence-backed academic
  -- rows (security.entry_resolve_v3). Every other answer is left exactly as v2 gives it; v2 is not changed (G3).
  if v #>> '{item,entry,resolution,step}' = '5' then
    select d.course_id into v_course from search.course_documents d
     where lower(d.course_stable_key) = lower(v->'item'->>'course_id') and d.course_stable_key is not null limit 1;
    if v_course is not null then
      v_res := security.entry_resolve_v3(v_course, v_cc);
      if v_res->>'step' is distinct from '5' then v := jsonb_set(v, '{item,entry,resolution}', v_res); end if;
    end if;
  end if;
$n4$),
  (5, 'public.admin_entry_requirements(text,jsonb)', '802659f3ccd66cd419a15d7084495785', $o5$return security.entry_resolve_v1(v_cid, p_args->>'country');$o5$, $n5$return security.entry_resolve_v3(v_cid, p_args->>'country');  -- s1000 (23 Nov 2026): the v3 resolver, as Website and Zoho v3 serve it$n5$),
  (6, 'public.admin_aer(text,jsonb)', 'd493c1b25a2cc55c7dd9d66cee440aa7', $o6$v_out := security.entry_resolve_v1(v_id, v_cc);$o6$, $n6$v_out := security.entry_resolve_v3(v_id, v_cc);  /* s1000 (23 Nov 2026): the v3 resolver, as Website and Zoho v3 serve it */$n6$)
  ) v(n, sig, md5, old, new) order by n
  loop
    v_def := pg_get_functiondef(r.sig::regprocedure); v_src := (select prosrc from pg_proc where oid = r.sig::regprocedure);
    if position(r.new in v_def) > 0 then raise notice 's1000 edit %: already applied', r.n; continue; end if;
    if r.md5 is not null and md5(v_src) <> r.md5 then raise exception 'guard: % differs from the definition this change edits (live md5 %)', r.sig, md5(v_src); end if;
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: the fragment of % is found % times', r.sig, v_n; end if;
    execute replace(v_def, r.old, r.new);
  end loop;
end $e$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record; v_after int; v_k text; v_res jsonb; v_ok int := 0; v_tried int := 0; v_same int := 0; v_cmp int := 0; v_v2 jsonb; v_v3 jsonb;
begin
  select * into b from pg_temp.s1000_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if md5((select prosrc from pg_proc where oid = 'security.entry_resolve_v1(uuid,text)'::regprocedure)) <> '9f59f7d54a8a1bcd9d89302c2c977ae3'
     or (select md5(prosrc) from pg_proc where oid = 'public.website_v2_course(text,text)'::regprocedure) <> b.v2md5 then
    raise exception 'post-check: a v2 path changed';
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  if position('s1000 (23 Nov 2026)' in pg_get_functiondef('public.website_v3_course(text,text)'::regprocedure)) = 0
     or position('s1000 (23 Nov 2026)' in pg_get_functiondef('security.course_coverage_build_v1()'::regprocedure)) = 0
     or position('s1000 (23 Nov 2026)' in pg_get_functiondef('security.aer_covered_courses_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: an edit is missing';
  end if;
  v_after := (select count(*) from security.aer_covered_courses_v1());
  if v_after <= b.covered_before then raise exception 'post-check: academic entry coverage did not grow (% then %)', b.covered_before, v_after; end if;
  -- Website v3 serves rule 1 for courses that had no table row; v3 equals v2 where v2 already had an answer
  for v_k in with cand as materialized (
                select d.course_id, d.course_stable_key from search.course_documents d join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active'
                 where d.course_stable_key is not null
                   and exists (select 1 from catalogue.course_entry_requirements x where x.course_id = d.course_id and x.status = 'active'
                                 and x.kind in ('minimum_grade', 'prior_qualification', 'subject_prerequisite') and x.audience in ('international', 'all')
                                 and x.evidence_id is not null and nullif(btrim(x.quote), '') is not null and x.country_id is null)
                 limit 60),  -- fixed: post-check sample size
              chk as materialized (select course_stable_key, security.entry_resolve_v1(course_id, 'IN')->>'step' st from cand)
              select course_stable_key from chk where st = '5' limit 10 loop  -- fixed: post-check sample size
    v_tried := v_tried + 1; v_res := public.website_v3_course(v_k, 'IN');
    if v_res #>> '{item,entry,resolution,step}' = '1' and jsonb_array_length(v_res #> '{item,entry,resolution,rows}') > 0 then v_ok := v_ok + 1; end if;
  end loop;
  if v_tried = 0 or v_ok <> v_tried then raise exception 'post-check: Website v3 served rule 1 for % of % sampled courses', v_ok, v_tried; end if;
  for v_k in with cand as materialized (
                select d.course_id, d.course_stable_key from search.course_documents d join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active'
                 where d.course_stable_key is not null
                   and exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = c.provider_id and m.status = 'active' and m.country_code = 'IN')
                 limit 60),  -- fixed: post-check sample size
              chk as materialized (select course_stable_key, security.entry_resolve_v1(course_id, 'IN')->>'step' st from cand)
              select course_stable_key from chk where st in ('1', '2', '3', '4') limit 10 loop  -- fixed: post-check sample size
    v_cmp := v_cmp + 1; v_v2 := public.website_v2_course(v_k, 'IN'); v_v3 := public.website_v3_course(v_k, 'IN');
    if (v_v2 #> '{item,entry,resolution}') - 'rows' = (v_v3 #> '{item,entry,resolution}') - 'rows' then v_same := v_same + 1; end if;
  end loop;
  if v_same <> v_cmp then raise exception 'post-check: a non-step-5 Website v3 answer changed (% of % the same)', v_same, v_cmp; end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('aer', 'entry_resolve_v3', 'security.entry_resolve_v3', jsonb_build_object('change', 's1000', 'covered_before', b.covered_before, 'covered_after', v_after,
          'v3_rule1_sampled', v_tried, 'v3_unchanged_sampled', v_cmp, 'decision', 'Platform Admin 23 Nov 2026 12:29 AEDT, Priority 1'), null);
  raise notice 's1000: academic entry coverage % -> % courses; Website v3 rule 1 % of %; unchanged % of %', b.covered_before, v_after, v_ok, v_tried, v_same, v_cmp;
end $p$;
