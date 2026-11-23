-- CF-247 s1009 (S2-RM-Design; Platform Admin 23 Nov 2026 15:52 AEDT, Priority 2 Step 1 items 1 and 3, approved in order: "Strict-Proof Row Rule ... admit
-- the ~165 verified rows ... keeping the 5% audit sample and leaving the 0.8 confidence threshold untouched" and "Reader Fix + $0 Re-Read: Fix the AER
-- reader so 'maximum / up to' is never parsed as a minimum and the quote must contain the extracted value, then run the $0 re-read across stored pages").
-- Measured live 23 Nov 2026 14:40 to 16:30 AEDT (rolled-back read-backs; head 20261123150002):
--   284 pending course entry first reads wait as all_rows_held: their rows come from the deterministic reader aer-det-v1.3 as "mentioned" readings,
--   which it stamps 0.70 (aer_det.confidence_mentioned) against aer.machine_min_confidence 0.8. Of 463 held rows for international or all applicants
--   with an academic kind, 165 have their value word for word in the quote with no maximum, "up to" or age wording; 99 of those are one misread
--   ("Senior School Certificate awarded by CBSE Senior Secondary 65% in English" stored as an overall 65% average), so the rule also refuses a value
--   that is a mark in one named subject. Samples of the rest: "Up to a maximum international ATAR of 99.95" read as a minimum ATAR of 99.95, and IB
--   rows whose quote was cut to "International". The ledger's repeated hashes are by design (one shadow and one admit row per item; shared pages): 0
--   repeated declines for one item in 7 days, so no de-duplication guard is added (item 2 needs no change).
-- What changes (in place, md5-guarded; no new table, job, setting or function; no consumer object):
--   1. security.aer_partial_admit_v1 (rule aer-partial-admit of admission-rule-runner, every 15 minutes) gains a third pass, rule aer-course-proof-v1:
--      in a pending course entry first read the course machine rule last stopped at all_rows_held or gate_incomplete, with no manual lock, no active
--      entry row for the course (no overwrite), not claimed or assigned, outside the 5% audit share (aer.machine_audit_pct), while the course machine
--      rule is admitting, a proposed row from that read's own evidence becomes active when it proves itself: international or all applicants, kind
--      minimum_grade, prior_qualification or subject_prerequisite, a quote of at least aer.machine_min_quote_chars, its value word for word in the
--      quote, no "maximum", "up to" or "max." wording, no age, the value not a mark in one named subject, and no numeric minimum without a scale.
--      Every other row stays proposed; ledger pipeline.aer_machine_admissions (rule aer-course-proof-v1, checks.admitted_row_ids).
--      aer.machine_min_confidence is neither read nor changed by this pass.
--   2. security.aer_current_findings_v1 counts a row named by an admitted aer-course-proof-v1 ledger row as admitted (no false P0).
--   3. Reader aer-det-v1.4 (coverage-sweep worker, same deploy): a maximum or "up to" figure is never read as a minimum; a reading's quote carries
--      its value; an overall average is never taken from one subject's mark; "International Baccalaureate" is no longer cut as a Canadian
--      baccalauréat (v1.3 cut IB quotes to "International"). security.aer_det_sweep_v1 and security.aer_det_propose_v1 take v1.4 readings, so the
--      job aer-det-sweep re-reads every stored course page of a course with no active entry row from storage ($0: no model, no Firecrawl).
--   4. security.aer_det_propose_v1: when v1.4 has read a page, the course's pending item from an older deterministic read is superseded (supersession
--      row, readiness closed, its proposed rows inactive by the item's own trigger), unless claimed or assigned, an audit sample, locked, or the course
--      has an active entry row; the v1.4 read is then proposed and the unchanged machine rule and Layer 4 decide it.
-- Live on deploy. G1: no job. G2: existing settings only (batch.aer_partial_admit, aer.machine_min_quote_chars, aer.machine_audit_pct,
-- aer.machine_mode, aer.machine_suspended); the 60 s guard is a fire guard. G3: 75/48 before and after. Manual locks untouched. $0. Nothing dropped.
-- Replaces: one fragment each of security.aer_current_findings_v1 and security.aer_partial_admit_v1 (its answer), the reader constant of
-- security.aer_det_sweep_v1 and security.aer_det_propose_v1, and the start of the proposer's page loop.
-- Retires: reader aer-det-v1.3 (its readings stay as recorded).
set local lock_timeout = '5s';  -- fixed: lock wait for the function edits

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1009_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs,
         (select value from pipeline.platform_toolset_settings where key = 'aer.machine_min_confidence') conf,
         (select count(*) from catalogue.course_entry_requirements where status = 'active') active_rows;

do $e$
declare r record; v_def text; v_src text; v_n int;
begin
  for r in select * from (values
    (1, 'security.aer_current_findings_v1()', 'f9fcaed44a848edd9af5c73b0482075d', $o1$and ma.rule = 'aer-course-partial-v1' and ma.checks->'admitted_row_ids' ? x.id::text$o1$, $n1$and ma.rule in ('aer-course-partial-v1', 'aer-course-proof-v1') and ma.checks->'admitted_row_ids' ? x.id::text  /* s1009 (23 Nov 2026): strict-proof admissions too */$n1$),
    (2, 'security.aer_partial_admit_v1()', 'a0937504d0e9106321d2d607f4537e71', $o2$    return jsonb_build_object('on', true, 'looked_at', v_seen, 'items_admitted', v_items, 'rows_admitted', v_rows, 'errors', v_err, 'last_error', v_last,
                              'course_looked_at', c_seen, 'course_items_admitted', c_items, 'course_rows_admitted', c_rows,
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));$o2$, $n2$    -- s1009 (23 Nov 2026): strict-proof admission (rule aer-course-proof-v1, Platform Admin 15:52 AEDT): rows of a held course entry read that
    -- prove themselves: international or all applicants, an academic kind, the value word for word in the row's quote, no maximum or "up to"
    -- wording, no age, and the value not a mark in one named subject. The confidence setting is not used or changed; 5% of items stay for a person.
    declare
      pr record; p_ok uuid[]; p_on int; p_heldn int; p_reason text; p_pid uuid; p_last text; p_bucket int;
      p_audit numeric := security.pipeline_num_v1('aer.machine_audit_pct', 5);
      p_seen int := 0; p_items int := 0; p_rows int := 0;
    begin
      if security.pipeline_num_v1('aer.machine_mode', 0) >= 2 and security.pipeline_num_v1('aer.machine_suspended', 0) < 1 then
        for pr in select i.id, i.entity_id, i.evidence_id from pipeline.layer4_review_items i
                   where i.status = 'pending' and i.field_code = 'course_entry_first_read' and i.entity_type = 'course'
                     and i.claimed_at is null and i.assigned_to is null
                     and not exists (select 1 from pipeline.aer_machine_admissions a where a.review_item_id = i.id and a.rule = 'aer-course-proof-v1' and a.outcome = 'admitted')
                     and not exists (select 1 from catalogue.course_entry_requirements a where a.course_id = i.entity_id and a.status = 'active')
                     and (select a.reason_code from pipeline.aer_machine_admissions a where a.review_item_id = i.id order by a.created_at desc limit 1) in ('all_rows_held', 'gate_incomplete')
                   order by i.created_at, i.id limit v_batch
        loop
          exit when clock_timestamp() - v_t0 > interval '60 seconds';  -- fixed: fire guard, the tick stays inside the job's statement limit
          begin
            p_seen := p_seen + 1;
            p_bucket := (('x' || substr(md5(pr.id::text || ':aer-course-proof-v1'), 1, 8))::bit(32)::bigint % 100)::int;  -- fixed: 100 buckets for a per-cent share
            continue when p_bucket < p_audit;  -- the audit share stays for a person
            continue when exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = pr.entity_id and l.field in ('entry_requirements', 'all'));
            select coalesce(array_agg(x.id order by x.id), '{}'::uuid[]) into p_ok
              from catalogue.course_entry_requirements x
             where x.provenance->>'review_item_id' = pr.id::text and x.status = 'proposed'
               and x.evidence_id is not null and x.evidence_id is not distinct from pr.evidence_id
               and length(btrim(coalesce(x.quote, ''))) >= v_qmin
               and not (x.min_value is not null and coalesce(x.grade_scale, 'none') = 'none')
               and x.audience in ('international', 'all') and x.kind in ('minimum_grade', 'prior_qualification', 'subject_prerequisite')
                 and coalesce(x.min_grade, regexp_replace(x.min_entry_score::text, '\.0+$', '')) is not null
                 and position(lower(coalesce(x.min_grade, regexp_replace(x.min_entry_score::text, '\.0+$', ''))) in lower(x.quote)) > 0
                 and x.quote !~* '(maximum|up to|max\.)' and x.quote !~* '(minimum age|years of age|years old)'
                 and x.quote !~ ('(^|[^0-9.])' || regexp_replace(coalesce(x.min_grade, regexp_replace(x.min_entry_score::text, '\.0+$', '')), '([.+*?^$()\[\]{}|\\])', '\\\1', 'g') || '(\.0+)? ?(%|per ?cent)? (in|for) [A-Z][a-z]');
            continue when cardinality(p_ok) = 0;
            select count(*) into p_heldn from catalogue.course_entry_requirements x
             where x.provenance->>'review_item_id' = pr.id::text and x.status = 'proposed' and not (x.id = any(p_ok));
            update catalogue.course_entry_requirements x set status = 'active', status_reason = null,
                   provenance = coalesce(x.provenance, '{}'::jsonb) || jsonb_build_object('proof_admission', jsonb_build_object('rule', 'aer-course-proof-v1',
                     'change', 's1009', 'review_item_id', pr.id, 'at', now())),
                   updated_at = now()
             where x.id = any(p_ok) and x.status = 'proposed';
            get diagnostics p_on = row_count;
            if p_on <> cardinality(p_ok) then raise exception 'aer-course-proof: % of % rows became active', p_on, cardinality(p_ok); end if;
            select c.provider_id into p_pid from catalogue.courses c where c.id = pr.entity_id;
            p_reason := format('Strict-proof admission (aer-course-proof-v1, s1009, Platform Admin 23 Nov 2026 15:52): %s row(s) admitted, each for international or all applicants, with its value word for word in its quote on the stored page, no maximum, "up to", age or one-subject mark. Still for a person: %s row(s) held.', p_on, p_heldn);
            insert into pipeline.aer_machine_admissions (review_item_id, course_id, provider_id, mode, outcome, rule, reason_code, reason, next_action, checks,
                                                         rows_admitted, evidence_id, actor)
            values (pr.id, pr.entity_id, p_pid, 'admit', 'admitted', 'aer-course-proof-v1', 'partial', p_reason, 'A person decides the held rows in Layer 4.',
                    jsonb_build_object('admitted_row_ids', to_jsonb(p_ok), 'held_back', p_heldn, 'proof', 'audience, academic kind, value in quote, no maximum, no age, no one-subject mark'),
                    p_on, pr.evidence_id, v_sys);
            update pipeline.layer4_review_items
               set escalation_reason = left(format('Strict-proof admission (aer-course-proof-v1): %s row(s) admitted. Still for a person: %s row(s) held.', p_on, p_heldn)
                                            || ' | ' || coalesce(escalation_reason, ''), 1000)  -- fixed: the column shows 1000 characters
             where id = pr.id and status = 'pending';
            insert into pipeline.admin_control_events (area, action, target, detail, actor)
            values ('layer4', 'aer_course_proof_admit', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', pr.id, 'course_id', pr.entity_id,
                    'rows_admitted', p_on, 'held_back', p_heldn, 'rule', 'aer-course-proof-v1', 'change', 's1009', 'auto', true, 'actor_kind', 'machine'), v_sys);
            p_items := p_items + 1; p_rows := p_rows + p_on;
          exception when others then
            v_err := v_err + 1; v_last := left(sqlerrm, 200);
          end;
        end loop;
      end if;
    return jsonb_build_object('on', true, 'looked_at', v_seen, 'items_admitted', v_items, 'rows_admitted', v_rows, 'errors', v_err, 'last_error', v_last,
                              'course_looked_at', c_seen, 'course_items_admitted', c_items, 'course_rows_admitted', c_rows,
                              'proof_looked_at', p_seen, 'proof_items_admitted', p_items, 'proof_rows_admitted', p_rows,
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    end;$n2$),
    (3, 'security.aer_det_sweep_v1()', '5a7509f942850edd2ed8c5f26679a4af', $o3$v_ext constant text := 'aer-det-v1.3';$o3$, $n3$v_ext constant text := 'aer-det-v1.4';  /* s1009 (23 Nov 2026) */$n3$),
    (4, 'security.aer_det_propose_v1()', '0d321c926e9003fc3ac88bc6dc49a650', $o4$v_ext constant text := 'aer-det-v1.3';$o4$, $n4$v_ext constant text := 'aer-det-v1.4';  /* s1009 (23 Nov 2026) */$n4$),
    (5, 'security.aer_det_propose_v1()', null, $o5$    v_checked := v_checked + 1; v_outcome := null;$o5$, $n5$    v_checked := v_checked + 1; v_outcome := null;
    -- s1009 (23 Nov 2026): a held read by an older deterministic reader gives way to this reader's read of the same stored page ($0): the old item is
    -- superseded (its proposed rows go inactive by the item's own trigger) unless a person holds it, it is an audit sample, the course is locked or
    -- already has an active entry row; this read is then proposed as usual and the unchanged machine rule and Layer 4 decide it.
    if exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = pg.course_id and r.field_code = 'course_entry_first_read'
                 and r.status = 'pending' and r.proposed_value->>'reader' = 'aer_det' and r.proposed_value->>'extractor' is distinct from v_ext)
       and not exists (select 1 from catalogue.course_entry_requirements a where a.course_id = pg.course_id and a.status = 'active')
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = pg.course_id and l.field in ('entry_requirements', 'all')) then
      with s as (
        update pipeline.layer4_review_items r set status = 'superseded', decided_at = now(),
               change_control_ref = left(coalesce(r.change_control_ref, '') || ' | superseded: read again from the stored copy by ' || v_ext || ' ($0, s1009)', 400)
         where r.entity_type = 'course' and r.entity_id = pg.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending'
           and r.proposed_value->>'reader' = 'aer_det' and r.proposed_value->>'extractor' is distinct from v_ext
           and r.claimed_at is null and r.assigned_to is null
           and coalesce((select a.reason_code from pipeline.aer_machine_admissions a where a.review_item_id = r.id order by a.created_at desc limit 1), '') <> 'audit_sample'
        returning r.id, r.field_code, r.entity_type, r.entity_id)
      insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
      select s.id, s.field_code, s.entity_type, s.entity_id, 'decided_before', null,
             jsonb_build_object('by', 'aer-det-propose', 'change', 's1009', 'reader_after', v_ext, 'evidence_id', pg.evidence_id), 'reconcile' from s;
      update pipeline.layer4_item_readiness k set item_status = 'superseded', readiness = 'closed', classified_at = now()
       where k.item_id in (select r.id from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = pg.course_id
                             and r.field_code = 'course_entry_first_read' and r.status = 'superseded' and r.change_control_ref like '%($0, s1009)%')
         and k.item_status is distinct from 'superseded';
    end if;$n5$)
  ) v(n, sig, md5, old, new) order by n
  loop
    v_def := pg_get_functiondef(r.sig::regprocedure); v_src := (select prosrc from pg_proc where oid = r.sig::regprocedure);
    if position(r.new in v_def) > 0 then raise notice 's1009 edit %: already applied', r.n; continue; end if;
    if r.md5 is not null and md5(v_src) <> r.md5 then raise exception 'guard: % differs from the definition this change edits (live md5 %)', r.sig, md5(v_src); end if;
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: the fragment of % (edit %) is found % times', r.sig, r.n, v_n; end if;
    execute replace(v_def, r.old, r.new);
  end loop;
end $e$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s1009_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  if (select value from pipeline.platform_toolset_settings where key = 'aer.machine_min_confidence') is distinct from b.conf then raise exception 'post-check: the confidence setting changed'; end if;
  if (select count(*) from catalogue.course_entry_requirements where status = 'active') <> b.active_rows then raise exception 'post-check: active entry rows changed during the migration'; end if;
  if position('s1009 (23 Nov 2026)' in pg_get_functiondef('security.aer_partial_admit_v1()'::regprocedure)) = 0
     or position('aer-det-v1.4' in pg_get_functiondef('security.aer_det_sweep_v1()'::regprocedure)) = 0
     or position('aer-det-v1.4' in pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure)) = 0
     or position('aer-det-v1.3' in pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure)) > 0
     or position('aer-course-proof-v1' in pg_get_functiondef('security.aer_current_findings_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: an edit is missing';
  end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('aer', 'aer_proof_and_reader_v14', 'security.aer_partial_admit_v1', jsonb_build_object('change', 's1009', 'reader', 'aer-det-v1.4',
          'decision', 'Platform Admin 23 Nov 2026 15:52 AEDT, Priority 2 Step 1 items 1 and 3'), null);
end $p$;
