-- CF-247 AER D1, step 1 (Platform Admin mandate 30 Oct 2026 08:45, D1: "LONG COURSE PAGES: APPROVED WITH A HARD CEILING. Raise
-- entry.course_page_chars to 205,000 through the normal settings/governance path ... Combined hard AI ceiling: US$6"). Decision: admin
-- docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md §11 (recorded before code).
-- 1. Settings (G2), each with its reason and the Platform Admin as the actor; the values before are kept in the audit event for rollback:
--    entry.course_page_chars 100,000 -> 205,000 (range maximum 150,000 -> 250,000);
--    enrich.course_entry_max_slices 10 -> 19 (205,000 characters at the measured slicer step of about 11,280 need 19; range 1-20 unchanged);
--    enrich.course_entry_slice_concurrency 4 -> 10 for D1 only (a 19-slice read stays inside the worker's time budget; back to 4 at close-out).
--    No worker change: the slicer's whole-page coverage check, held_partial on any cut or failed slice, and cost recording are unchanged (W29).
-- 2. The probe batch: 5 held courses read again one by one (course_entry_read_enqueue_v1): Monash 3 (B2; 100,365-108,295 characters),
--    AUT 1 (108,958) and the longest QUT page (201,314, 18 slices). Every read goes to Layer 4; nothing is admitted.
-- Preconditions (the migration fails and changes nothing if any does not hold): each course eligible, bound to its newest stored copy, its
-- newest entry item held as a long page; no entry read waiting; AI reading allowed; worker v0.54.x; D1 spend so far plus this batch's
-- estimate (measured cost a slice x expected slices + 25%) within US$6; the latest OpenRouter balance above its floor by the estimate.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
        v_ceiling constant numeric := 6;
        v_ids constant uuid[] := array['e58e7771-7bb9-4ea6-89fa-f1d2a82fb9b9', '512b56fe-ccd7-4efb-bf4f-59674e891e66', '9cf18451-9cb7-43ca-8a79-a94c81ae17e3',
                                       '9f363419-2501-4d6c-9b6e-c38034a6f330', '8ad169d1-27a5-4074-a8c0-466dcd2e0e86']::uuid[];
        v_reason constant text := 'AER D1 long pages batch 1 (probe; Platform Admin mandate 30 Oct 2026 08:45; ceiling US$6)';
        v_before jsonb; v_n int; v_spent numeric; v_slice numeric; v_est numeric := 0; v_bal numeric; v_floor numeric; v_worker text;
        v_jobs jsonb := '[]'::jsonb; c uuid; v_chars int; v_el uuid[];
begin
  -- preconditions
  select count(*) into v_n from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if v_n <> 0 then raise exception 'D1 precondition: % entry reads are waiting', v_n; end if;
  if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'D1 precondition: AI reading is stopped (AI limits)'; end if;
  select l.detail->>'worker' into v_worker from pipeline.mode_outcome_ledger l where l.detail ? 'worker' order by l.run_at desc limit 1;
  if v_worker is null or v_worker not like 'coverage-sweep-worker-v0.54.%' then raise exception 'D1 precondition: deployed worker is %, expected v0.54.x', v_worker; end if;
  v_el := array(select e.course_id from security.course_entry_eligible_v1() e where e.course_id = any (v_ids));
  foreach c in array v_ids loop
    if not (c = any (v_el)) then raise exception 'D1 precondition: course % is not eligible', c; end if;
    if not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c and g.status = 'bound'
                     and g.evidence_id = (select e.id from pipeline.evidence_artifacts e where e.storage_path is not null and e.metadata->>'course_id' = c::text order by e.created_at desc limit 1)) then
      raise exception 'D1 precondition: course % is not bound to its newest stored copy', c; end if;
    select (substring(f.reason from 'page text is ([0-9]+) characters'))::int into v_chars
      from pipeline.field_enrich_items f where f.course_id = c and f.field = 'entry_requirements' order by f.created_at desc limit 1;
    if v_chars is null or v_chars <= 100000 or v_chars > 205000 then raise exception 'D1 precondition: course % newest read is not a held long page within 205,000 (%)', c, v_chars; end if;
    v_est := v_est + 1 + ceil(greatest(v_chars - 11871, 0) / 11280.0);  -- expected slices (measured slicer step)
  end loop;
  select coalesce(sum(f.cost_usd), 0) into v_spent from pipeline.field_enrich_items f join pipeline.admin_jobs j on j.id = f.job_id
   where f.field = 'entry_requirements' and j.reason like 'AER D1 long pages%';
  select avg(f.cost_usd / (f.value->'coverage'->>'slices')::int) into v_slice from pipeline.field_enrich_items f
   where f.field = 'entry_requirements' and f.cost_usd > 0 and f.value->'coverage' ? 'slices' and f.updated_at > now() - interval '7 days';
  v_est := round(v_est * coalesce(v_slice, 0.0023) * 1.25, 4);
  if v_spent + v_est > v_ceiling then raise exception 'D1: spend so far US$% plus this batch''s estimate US$% would pass the ceiling US$%', v_spent, v_est, v_ceiling; end if;
  select (l.detail->>'remaining_usd')::numeric into v_bal from pipeline.mode_outcome_ledger l where l.mode = 'openrouter_balance' and l.detail ? 'remaining_usd' order by l.run_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is null or v_bal - v_floor < v_est then raise exception 'D1 precondition: balance US$% is not above the floor US$% by the estimate US$%', v_bal, v_floor, v_est; end if;

  -- 1. settings (the values before kept for rollback)
  select jsonb_object_agg(s.key, jsonb_build_object('value', s.value, 'max_value', s.max_value, 'reason', s.reason, 'updated_at', s.updated_at)) into v_before
    from pipeline.platform_toolset_settings s
   where s.toolset_key = 'pipeline' and s.key in ('entry.course_page_chars', 'enrich.course_entry_max_slices', 'enrich.course_entry_slice_concurrency');
  update pipeline.platform_toolset_settings set max_value = 250000, value = to_jsonb(205000), updated_by = v_pa, updated_at = now(),
         reason = 'CF-247 AER D1 (Platform Admin mandate 30 Oct 2026 08:45): long course pages read whole up to 205,000 characters (QUT 173,314-201,314); a longer page is still held'
   where toolset_key = 'pipeline' and key = 'entry.course_page_chars' and value = to_jsonb(100000);
  get diagnostics v_n = row_count; if v_n <> 1 then raise exception 'D1: entry.course_page_chars was not 100,000'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(19), updated_by = v_pa, updated_at = now(),
         reason = 'CF-247 AER D1 (Platform Admin mandate 30 Oct 2026 08:45): 205,000 characters at the measured slicer step (about 11,280) need 19 slices'
   where toolset_key = 'pipeline' and key = 'enrich.course_entry_max_slices' and value = to_jsonb(10);
  get diagnostics v_n = row_count; if v_n <> 1 then raise exception 'D1: enrich.course_entry_max_slices was not 10'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(10), updated_by = v_pa, updated_at = now(),
         reason = 'CF-247 AER D1 (Platform Admin mandate 30 Oct 2026 08:45): for the D1 long-page reads only (19 slices inside the worker time budget); back to 4 at D1 close-out'
   where toolset_key = 'pipeline' and key = 'enrich.course_entry_slice_concurrency' and value = to_jsonb(4);
  get diagnostics v_n = row_count; if v_n <> 1 then raise exception 'D1: enrich.course_entry_slice_concurrency was not 4'; end if;

  -- 2. the probe reads, one task each
  foreach c in array v_ids loop
    v_jobs := v_jobs || to_jsonb(security.course_entry_read_enqueue_v1(c, v_pa, v_reason));
  end loop;
  select count(*) into v_n from pipeline.field_enrich_items f where f.job_id in (select (x)::uuid from jsonb_array_elements_text(v_jobs) x) and f.state = 'queued';
  if v_n <> 5 then raise exception 'D1: % reads queued, expected 5', v_n; end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_requirements', 'programme_batch', 'migration 20261030220000',
          jsonb_build_object('line', 'D1', 'batch', 1, 'courses', 5, 'course_ids', to_jsonb(v_ids), 'jobs', v_jobs, 'spent_before_usd', v_spent, 'estimate_usd', v_est,
                             'ceiling_usd', v_ceiling, 'cost_a_slice_used', v_slice, 'balance_usd', v_bal, 'floor_usd', v_floor, 'worker', v_worker,
                             'settings_before', v_before, 'reason', v_reason), v_pa);
end $$;
