-- CF-247 s983 (S2-Build; Platform Admin 23 Nov 2026 11:10 AEDT, Phase 1 and 2: "eliminate false-positive admission holds where valid rows satisfy
-- canonical source-verification and required-field rules"; the morning batch 07:16, Part 1.1: "verified ... course entry rows ... promote
-- immediately ..., routing only the missing or ambiguous rows to Layer 4"): row-level partial admission for course entry first reads, the same
-- policy the Platform Admin approved for entry tables on 21 Nov 2026 10:03 (aer-partial-v1, s914).
-- Measured live 23 Nov 2026 11:11 to 11:35 AEDT (rolled-back read-backs; head 20261123040000):
--   615 deterministic course entry reads wait in Layer 4. 284 are "all_rows_held": all 291 rows carry confidence 0.70, below
--   aer.machine_min_confidence 0.8, and the samples are genuinely unreliable ("Units 3 and 4" read as a score of 4, "65% in English" read as an
--   overall average), so they stay held; nothing here touches them. 347 are "gate_incomplete": the completeness gate holds the whole read because
--   the reader left a printed "other requirement" uncaptured (det_other_requirement 331, quote_not_on_page 15, score_without_basis 1), while 933
--   of their 1,214 rows pass every machine row rule (exact quote of at least 8 characters on the stored page, confidence at least 0.8, this read's
--   evidence). None of the 347 courses has an active entry row, so nothing is overwritten.
-- What changes (in place, md5-guarded; no new table, function, job or setting):
--   1. security.aer_partial_admit_v1 (rule aer-partial-admit of admission-rule-runner, every 15 minutes) gains a second pass, rule
--      aer-course-partial-v1: for a pending course entry first read that security.aer_machine_check_v1 stops only at the completeness gate
--      (rule gate_incomplete), with no manual lock on the course's entry requirements, no active entry row for the course (no overwrite), not
--      claimed or assigned, while the course machine rule is admitting (aer.machine_mode 2, not suspended), the rows that pass every machine row
--      rule and carry no numeric minimum without its scale become active. Every other row stays proposed and the item stays in Layer 4 with a
--      reason naming the gate finding and the rows held. Ledger: pipeline.aer_machine_admissions (outcome admitted, rule aer-course-partial-v1,
--      checks.admitted_row_ids). No reader, word list, threshold or recovery path changes (Decision 276).
--   2. security.aer_current_findings_v1: a course row named by an admitted aer-course-partial-v1 ledger row is admitted (as s978 did for
--      aer-partial-v1 entry-table rows), so the assurance check raises no false P0.
-- Live on deploy: the next admission-rule-runner tick admits. G1: no job. G2: values are the existing settings (batch.aer_partial_admit,
-- aer.machine_min_confidence, aer.machine_min_quote_chars, aer.machine_mode, aer.machine_suspended); the 60 s tick guard is a fire guard.
-- G3: no consumer object (75/48 before and after). Manual locks untouched. $0. Nothing dropped or removed.
-- Replaces: the end of security.aer_partial_admit_v1 (a course pass before its answer) and the course branch of the consumer_unadmitted test in
-- security.aer_current_findings_v1 (one fragment each).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edits

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s983_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs,
         (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) decided;

do $e$
declare r record; v_def text; v_n int;
begin
  for r in select * from (values
    (1, 'security.aer_current_findings_v1()', 'cef712d1644e034078597bdf863f26c7',
     $o$             where x.status = 'active' and coalesce(x.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')) z$o$,
     $n$             where x.status = 'active' and coalesce(x.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')
               -- s983 (23 Nov 2026): a course row the partial admission rule admitted (aer-course-partial-v1) is admitted; its ledger row names it
               and not exists (select 1 from pipeline.aer_machine_admissions ma where ma.review_item_id = li.id and ma.outcome = 'admitted'
                                  and ma.rule = 'aer-course-partial-v1' and ma.checks->'admitted_row_ids' ? x.id::text)) z$n$),
    (2, 'security.aer_partial_admit_v1()', '87b8109532ee26748656fce045742895',
     $o$  return jsonb_build_object('on', true, 'looked_at', v_seen, 'items_admitted', v_items, 'rows_admitted', v_rows, 'errors', v_err, 'last_error', v_last,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));$o$,
     $n$  -- s983 (23 Nov 2026): course entry first reads stopped only by the completeness gate (rule aer-course-partial-v1)
  declare
    cr record; cc jsonb; c_ok uuid[]; c_on int; c_heldn int; c_reason text; c_pid uuid;
    c_conf numeric := security.pipeline_num_v1('aer.machine_min_confidence', 0.8);
    c_seen int := 0; c_items int := 0; c_rows int := 0;
  begin
    if security.pipeline_num_v1('aer.machine_mode', 0) >= 2 and security.pipeline_num_v1('aer.machine_suspended', 0) < 1 then
      for cr in select i.id, i.entity_id, i.evidence_id from pipeline.layer4_review_items i
                 where i.status = 'pending' and i.field_code = 'course_entry_first_read' and i.entity_type = 'course'
                   and i.claimed_at is null and i.assigned_to is null
                   and not exists (select 1 from pipeline.aer_machine_admissions a where a.review_item_id = i.id and a.rule = 'aer-course-partial-v1' and a.outcome = 'admitted')
                   and not exists (select 1 from catalogue.course_entry_requirements a where a.course_id = i.entity_id and a.status = 'active')
                 order by i.created_at, i.id limit v_batch
      loop
        exit when clock_timestamp() - v_t0 > interval '60 seconds';  -- fixed: fire guard, the tick stays inside the job's statement limit
        begin
          c_seen := c_seen + 1;
          cc := security.aer_machine_check_v1(cr.id);
          continue when coalesce(cc->>'rule', '') <> 'gate_incomplete';
          continue when exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = cr.entity_id and l.field in ('entry_requirements', 'all'));
          select coalesce(array_agg(x.id order by x.id), '{}'::uuid[]) into c_ok
            from catalogue.course_entry_requirements x
           where x.provenance->>'review_item_id' = cr.id::text and x.status = 'proposed'
             and x.evidence_id is not null and x.evidence_id is not distinct from cr.evidence_id
             and length(btrim(coalesce(x.quote, ''))) >= v_qmin and coalesce(x.confidence, 0) >= c_conf
             and not (x.min_value is not null and coalesce(x.grade_scale, 'none') = 'none');
          continue when cardinality(c_ok) = 0;
          select count(*) into c_heldn from catalogue.course_entry_requirements x
           where x.provenance->>'review_item_id' = cr.id::text and x.status = 'proposed' and not (x.id = any(c_ok));
          update catalogue.course_entry_requirements x set status = 'active', status_reason = null,
                 provenance = coalesce(x.provenance, '{}'::jsonb) || jsonb_build_object('partial_admission', jsonb_build_object('rule', 'aer-course-partial-v1',
                   'change', 's983', 'review_item_id', cr.id, 'gate', cc->>'reason', 'at', now())),
                 updated_at = now()
           where x.id = any(c_ok) and x.status = 'proposed';
          get diagnostics c_on = row_count;
          if c_on <> cardinality(c_ok) then raise exception 'aer-course-partial: % of % rows became active', c_on, cardinality(c_ok); end if;
          select c.provider_id into c_pid from catalogue.courses c where c.id = cr.entity_id;
          c_reason := format('Partial admission (aer-course-partial-v1, s983, Platform Admin 23 Nov 2026): %s row(s) of this course read admitted, each with an exact quote on the stored page %s and confidence at least %s. Still for a person: %s; %s row(s) held.',
                             c_on, coalesce(cc->'checks'->>'source_url', ''), c_conf, coalesce(cc->>'reason', ''), c_heldn);
          insert into pipeline.aer_machine_admissions (review_item_id, course_id, provider_id, mode, outcome, rule, reason_code, reason, next_action, checks,
                                                       rows_admitted, evidence_id, content_hash, source_url, actor)
          values (cr.id, cr.entity_id, c_pid, 'admit', 'admitted', 'aer-course-partial-v1', 'partial', c_reason, 'A person decides the held rows in Layer 4.',
                  coalesce(cc->'checks', '{}'::jsonb) || jsonb_build_object('admitted_row_ids', to_jsonb(c_ok), 'held_back', c_heldn, 'machine_rule', cc->>'rule'),
                  c_on, cr.evidence_id, cc->'checks'->>'content_hash', cc->'checks'->>'source_url', v_sys);
          update pipeline.layer4_review_items
             set escalation_reason = left(format('Partial admission (aer-course-partial-v1): %s row(s) admitted. Still for a person: %s row(s) held (%s).',
                                                 c_on, c_heldn, coalesce(cc->>'reason', '')) || ' | ' || coalesce(escalation_reason, ''), 1000)  -- fixed: the column shows 1000 characters
           where id = cr.id and status = 'pending';
          insert into pipeline.admin_control_events (area, action, target, detail, actor)
          values ('layer4', 'aer_course_partial_admit', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', cr.id, 'course_id', cr.entity_id,
                  'rows_admitted', c_on, 'held_back', c_heldn, 'rule', 'aer-course-partial-v1', 'change', 's983', 'auto', true, 'actor_kind', 'machine'), v_sys);
          c_items := c_items + 1; c_rows := c_rows + c_on;
        exception when others then
          v_err := v_err + 1; v_last := left(sqlerrm, 200);
        end;
      end loop;
    end if;
    return jsonb_build_object('on', true, 'looked_at', v_seen, 'items_admitted', v_items, 'rows_admitted', v_rows, 'errors', v_err, 'last_error', v_last,
                              'course_looked_at', c_seen, 'course_items_admitted', c_items, 'course_rows_admitted', c_rows,
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  end;$n$)) v(n, sig, md5, old, new) order by n
  loop
    v_def := pg_get_functiondef(r.sig::regprocedure);
    if position('s983 (23 Nov 2026)' in v_def) > 0 then raise notice 's983 edit %: already applied', r.n; continue; end if;
    if md5(v_def) <> r.md5 then raise exception 'guard: % differs from the definition this change edits (live md5 %)', r.sig, md5(v_def); end if;
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: the fragment of % is found % times', r.sig, v_n; end if;
    execute replace(v_def, r.old, r.new);
  end loop;
end $e$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s983_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> b.decided then
    raise exception 'post-check: a Layer 4 item was decided';
  end if;
  if position('s983 (23 Nov 2026)' in pg_get_functiondef('security.aer_partial_admit_v1()'::regprocedure)) = 0
     or position('s983 (23 Nov 2026)' in pg_get_functiondef('security.aer_current_findings_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: an edit is missing';
  end if;
end $p$;
