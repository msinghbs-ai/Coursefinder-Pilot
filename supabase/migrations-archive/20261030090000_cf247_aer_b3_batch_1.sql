-- CF-247 AER bounded paid reads, B3 batch 1 (Platform Admin mandate 30 Oct 2026 06:53: "B3 — APPROVED: the next 500 eligible AU courses after R1 identity reconciliation, hard ceiling US$6").
-- One course-level batch through security.course_entry_batch_v1 (next by priority). Preconditions in this migration (it fails and queues
-- nothing if any does not hold): no course read waiting; AI reading allowed; deployed worker v0.54.x; every course chosen is AU and eligible;
-- B3 so far plus this batch stays within 500 courses; B3 spend so far plus this batch's estimate at the measured cost plus 25% stays within
-- US$6; the latest observed OpenRouter balance stays above its floor by that estimate. Every course read goes to Layer 4; nothing is admitted.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

-- the batch size setting, within its range (1-200), so the approved scope runs in a few bounded batches instead of many; reason recorded
update pipeline.platform_toolset_settings set value = to_jsonb(200), updated_at = now(),
       reason = 'CF-247 AER bounded paid reads B3/B4 (Platform Admin mandate 30 Oct 2026 06:53): 200-course batches, one at a time, each checked for cost, holds and Layer 4 output before the next'
 where toolset_key = 'pipeline' and key = 'entry.course_batch_size' and value = to_jsonb(50);

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
        v_line constant text := 'B3'; v_total constant int := 500; v_ceiling constant numeric := 6; v_cc constant text := 'AU';
        v_reason text; v_done int; v_spent numeric; v_cost numeric; v_size int; v_est numeric; v_bal numeric; v_floor numeric; v_worker text;
        v_n int; v_batch jsonb; v_job uuid; v_bad int; v_inel int; v_out jsonb := '[]'::jsonb;
begin
  select count(*), coalesce(sum(f.cost_usd), 0) into v_done, v_spent from pipeline.field_enrich_items f join pipeline.admin_jobs j on j.id = f.job_id
   where f.field = 'entry_requirements' and j.reason like 'AER bounded paid reads ' || v_line || ' batch%';
  -- measured cost a course (course reads with spend, last 7 days), plus 25%
  select coalesce(avg(f.cost_usd) filter (where f.cost_usd > 0), 0.0085) * 1.25 into v_cost from pipeline.field_enrich_items f
   where f.field = 'entry_requirements' and f.updated_at > now() - interval '7 days';
  v_size := least(200, v_total - v_done);
  if v_size <= 0 then raise exception '%: the approved scope of % courses is complete (% read); nothing queued', v_line, v_total, v_done; end if;
  v_est := round(v_size * v_cost, 4);
  if v_spent + v_est > v_ceiling then raise exception '%: spend so far US$% plus this batch''s estimate US$% would pass the ceiling US$%', v_line, v_spent, v_est, v_ceiling; end if;
  select count(*) into v_n from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if v_n <> 0 then raise exception 'precondition: % course reads are already waiting', v_n; end if;
  if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'precondition: AI reading is stopped (AI limits)'; end if;
  select (l.detail->>'remaining_usd')::numeric into v_bal from pipeline.mode_outcome_ledger l where l.mode = 'openrouter_balance' and l.detail ? 'remaining_usd' order by l.run_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is null or v_bal - v_floor < v_est then raise exception 'precondition: balance US$% is not above the floor US$% by the estimate US$%', v_bal, v_floor, v_est; end if;
  select l.detail->>'worker' into v_worker from pipeline.mode_outcome_ledger l where l.detail ? 'worker' order by l.run_at desc limit 1;
  if v_worker is null or v_worker not like 'coverage-sweep-worker-v0.54.%' then raise exception 'precondition: deployed worker is %, expected v0.54.x', v_worker; end if;
  v_reason := 'AER bounded paid reads ' || v_line || ' batch 1 (Platform Admin mandate 30 Oct 2026 06:53; ceiling US$' || v_ceiling || ' for ' || v_total || ' courses)';
  v_batch := security.course_entry_batch_v1(null, v_size, v_reason, v_pa, false);
  v_job := (v_batch->>'job_id')::uuid; v_out := jsonb_build_array(v_batch);
  -- post-checks: exactly the batch, every course of the scope country and eligible
  select count(*), count(*) filter (where security.coverage_country(f.provider_id) <> v_cc),
         count(*) filter (where f.course_id not in (select e.course_id from security.course_entry_eligible_v1() e))
    into v_n, v_bad, v_inel from pipeline.field_enrich_items f where f.job_id = v_job;
  if v_n <> v_size and v_n <> (v_batch->>'courses')::int then raise exception '%: % courses queued, expected %', v_line, v_n, v_size; end if;
  if v_bad <> 0 then raise exception '%: % queued courses are not %', v_line, v_bad, v_cc; end if;
  if v_inel <> 0 then raise exception '%: % queued courses are not eligible', v_line, v_inel; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_requirements', 'programme_batch', 'migration 20261030090000',
          jsonb_build_object('line', v_line, 'batch', 1, 'courses', v_n, 'scope_done_before', v_done, 'scope_total', v_total, 'spent_before_usd', v_spent,
                             'estimate_usd', v_est, 'ceiling_usd', v_ceiling, 'cost_a_course_used', v_cost, 'balance_usd', v_bal, 'floor_usd', v_floor, 'worker', v_worker,
                             'job', v_out, 'reason', v_reason), v_pa);
end $$;

