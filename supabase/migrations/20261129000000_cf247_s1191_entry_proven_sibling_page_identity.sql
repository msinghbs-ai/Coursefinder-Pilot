-- CF-247 s1191 (S1-Build / Integration Controller with S2-AER; Platform Admin decision 26 Nov 2026 06:57 AEDT: "Option 2 is approved subject to the
-- following safeguards. Accept proven sibling-page identity for academic entry requirements only where: the provider, normalised programme title and
-- qualification level match; the same official source page is already verified through CRICOS or an approved adapter; the evidence supports applicability
-- to the target course variant and international audience; no contradictory campus, study mode, pathway, edition or programme-specific requirements exist;
-- existing evidence, quote, mapping, validation and admission safeguards remain enforced. Do not permit title-only identity, transitive sibling identity
-- or indiscriminate copying of existing canonical rows.")
-- Decision paper: admin docs/platform/p0-aer-activation/2026-11-26-entry-identity-shared-programme-pages-decision.md.
-- What this does (live on apply):
--   1. security.entry_sibling_identity_v1(course, url): true only when another active course of the same provider, with the same normalised title (the
--      normalisation of security.course_entry_shared_page_v1) and the same study level, is bound to the same page URL by its own CRICOS code or approved
--      adapter code (never by a sibling: not transitive); the target is open to international students, its page is read and is not a domestic page, the
--      read gate's course page check refuses it for no reason other than a shared page, and none of the target's own stored readings names a campus, study
--      mode, pathway, edition or intake. Entry requirements only: fee, intake and every other field keep their own identity rule.
--   2. security.aer_det_propose_v1 (md5 guarded, one line edited in place): a page refused by the country identity rule is proposed when that proof holds.
--      Everything after it is unchanged: shared-page, variant, over-row-limit, quote and score rules, Layer 4 and the existing fast admission. The course's own
--      stored readings are proposed; no canonical row is copied from the sibling.
--   3. the deterministic pages held as not_admitted that now meet the proof are made due again, so the existing sweep (aer-det-sweep) re-evaluates them.
-- G1: no job. G2: no new value (the wording lists are the decision's own terms). G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: security.aer_det_propose_v1 (same function; its identity line also accepts the proven sibling page).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '300s';  -- fixed: the course page check over the held pages

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure)) <> '1eec1fef14b7a3eeef28dc33d5f02ef2' then
    raise exception 'guard: security.aer_det_propose_v1 is not the definition read on 26 Nov 2026';
  end if;
end $g$;
create temp table s1191_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1191_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1191_idf on commit drop as select md5(pg_get_functiondef('security.coverage_identity_allowed(uuid,text,text)'::regprocedure)) m;  -- course-specific fee and intake identity: unchanged

create or replace function security.entry_sibling_identity_v1(p_course uuid, p_url text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare c record; g record; s record; v_chk jsonb; v_q text;
begin
  select co.id, co.provider_id, co.study_level_id, co.open_to_international oi, co.lifecycle_status ls,
         lower(regexp_replace(regexp_replace(coalesce(co.canonical_title, ''), '\(Level [0-9]+\)', '', 'gi'), '[^[:alnum:]]', '', 'g')) nt
    into c from catalogue.courses co where co.id = p_course;
  if c.id is null or c.ls <> 'active' then return jsonb_build_object('ok', false, 'reason', 'no active course'); end if;
  if c.oi is not true then return jsonb_build_object('ok', false, 'reason', 'the course is not shown as open to international students'); end if;
  if c.nt = '' or c.study_level_id is null then return jsonb_build_object('ok', false, 'reason', 'no title or study level to match'); end if;
  select * into g from pipeline.coverage_course_pages p where p.course_id = p_course and p.url = p_url and p.status = 'bound' and p.read_status = 'read' order by p.bound_at desc nulls last limit 1;
  if g.course_id is null then return jsonb_build_object('ok', false, 'reason', 'the page is not bound to this course and read'); end if;
  if p_url ~* '(^|[/_.-])domestic([/_.-]|$)' then return jsonb_build_object('ok', false, 'reason', 'a domestic page'); end if;
  -- the same page, proved for a sibling by its own CRICOS code or adapter code (a sibling proof is never itself the proof: not transitive)
  select o.id sid, gp.identity_basis sb into s
    from catalogue.courses o join pipeline.coverage_course_pages gp on gp.course_id = o.id and gp.url = p_url and gp.status = 'bound'
   where o.provider_id = c.provider_id and o.id <> c.id and o.lifecycle_status = 'active' and o.study_level_id = c.study_level_id
     and lower(regexp_replace(regexp_replace(coalesce(o.canonical_title, ''), '\(Level [0-9]+\)', '', 'gi'), '[^[:alnum:]]', '', 'g')) = c.nt
     and gp.identity_basis in ('cricos_code', 'adapter_code')
     and security.coverage_identity_allowed(c.provider_id, gp.identity_basis, 'entry_requirements')
   order by gp.bound_at desc nulls last limit 1;
  if s.sid is null then return jsonb_build_object('ok', false, 'reason', 'no same-title, same-level sibling has this page proved by CRICOS or adapter code'); end if;
  -- the read gate's own page check: only the shared-page rule may refuse it
  v_chk := security.course_page_check_v1(p_course, coalesce(nullif(g.candidates->>'final_url', ''), g.url), coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1'), g.identity_basis);
  if v_chk->>'verdict' = 'refuse' and coalesce(v_chk->>'rule', '') <> 'shared_page' then
    return jsonb_build_object('ok', false, 'reason', 'the course page check refuses it: ' || coalesce(v_chk->>'reason', v_chk->>'rule'), 'sibling', s.sid);
  end if;
  -- no campus, study mode, pathway, edition or intake specific requirement among the course's own readings
  select r.quote into v_q from pipeline.aer_det_academic_readings r where r.course_id = p_course and r.evidence_id = g.evidence_id
     and r.quote ~* '(\mcampus\M|\monline\M|on[- ]campus|part[- ]time|full[- ]time|\mpathway|\medition\M|\mintake\M|\mtrimester\M|\msemester\M|mid[- ]year)' limit 1;  -- fixed: the decision's own terms
  if v_q is not null then return jsonb_build_object('ok', false, 'reason', 'a reading is specific to a campus, study mode, pathway, edition or intake', 'quote', left(v_q, 160), 'sibling', s.sid); end if;
  return jsonb_build_object('ok', true, 'sibling', s.sid, 'sibling_basis', s.sb, 'url', p_url, 'rule', 'proven_sibling_page');
end $function$;
comment on function security.entry_sibling_identity_v1(uuid, text) is 'CF-247 s1191 (Platform Admin decision 26 Nov 2026 06:57 AEDT, option 2): proven sibling-page identity for academic entry requirements only; same provider, normalised title and study level; the same page proved by the sibling''s own CRICOS or adapter code (not transitive); international, read, page check refusing only as shared; no campus, mode, pathway, edition or intake specific reading.';
revoke all on function security.entry_sibling_identity_v1(uuid, text) from public, anon, authenticated;

do $p$
declare d text := pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure);
  v_old constant text := 'elsif not security.coverage_identity_allowed(pg.provider_id, g.identity_basis, ''entry_requirements'') then v_outcome := ''not_admitted'';';
  v_new constant text := 'elsif not security.coverage_identity_allowed(pg.provider_id, g.identity_basis, ''entry_requirements'') and (security.entry_sibling_identity_v1(pg.course_id, g.url)->>''ok'') is distinct from ''true'' then v_outcome := ''not_admitted'';  -- CF-247 s1191: or the proven sibling page (Platform Admin 26 Nov 2026 06:57 AEDT)';
begin
  if (length(d) - length(replace(d, v_old, ''))) / length(v_old) <> 1 then raise exception 's1191: the identity line is not found exactly once'; end if;
  execute replace(d, v_old, v_new);
end $p$;

do $rel$
declare v_n int; v_ids jsonb;
begin
  create temp table s1191_rel on commit drop as
    select a.course_id, a.evidence_id, x.v
      from pipeline.aer_det_academic_pages a
      join lateral (select g.url from pipeline.coverage_course_pages g where g.course_id = a.course_id and g.status = 'bound' order by g.bound_at desc nulls last limit 1) g on true
      cross join lateral (select security.entry_sibling_identity_v1(a.course_id, g.url) v) x
     where a.outcome = 'not_admitted' and (x.v->>'ok')::boolean;
  update pipeline.aer_det_academic_pages a set outcome = null, outcome_at = null from s1191_rel r where a.course_id = r.course_id and a.evidence_id = r.evidence_id and a.outcome = 'not_admitted';
  get diagnostics v_n = row_count;
  if v_n > 600 then raise exception 's1191: % pages released, more than the identity-held cohort', v_n; end if;  -- fixed: the measured cohort's size
  select coalesce(jsonb_agg(jsonb_build_object('course', course_id, 'sibling', v->'sibling', 'basis', v->'sibling_basis')), '[]'::jsonb) into v_ids from s1191_rel;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'identity_rule', 'security.entry_sibling_identity_v1', jsonb_build_object('reason', 'Platform Admin decision 26 Nov 2026 06:57 AEDT (option 2, proven sibling page, academic entry only)',
          'by', 'migration 20261129000000 (CF-247 s1191)', 'released_pages', v_n, 'courses', v_ids), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');  -- fixed: the deciding Platform Admin
  raise notice 's1191: % deterministic pages made due again under the proven sibling page', v_n;
end $rel$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1191_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1191_locks) then raise exception 'post-check: manual locks changed'; end if;
  if md5(pg_get_functiondef('security.coverage_identity_allowed(uuid,text,text)'::regprocedure)) <> (select m from s1191_idf) then raise exception 'post-check: the identity rule of other fields changed'; end if;
  if pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure) not like '%entry_sibling_identity_v1(pg.course_id, g.url)%' then raise exception 'post-check: the proposer does not use the proven sibling page'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
