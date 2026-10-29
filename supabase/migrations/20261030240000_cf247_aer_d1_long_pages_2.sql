-- CF-247 AER D1, step 2: 36 of the other 42 held QUT long pages read again (Platform Admin mandate 30 Oct 2026 08:45, D1; AI ceiling US$6).
-- Probe result (20261030220000, read 08:58 AEDT): 5 of 5 complete at the first attempt (Monash 9, 10 and 10 slices; AUT 10; QUT 18),
-- 29 rows to Layer 4, US$0.1064. QUT measured US$0.00233 a slice (the highest of the probe), so this batch is estimated at that rate.
-- Scope: QUT courses whose newest entry read is held as a page longer than 100,000 and at most 205,000 characters (42), each eligible
-- and bound to the newest stored copy of its page (exactly 36). Six are left out because a newer copy of the same page was stored on 29 Oct
-- (by a sibling course sharing the page) while their binding still points to the 4-5 Oct copy; reading the older copy would not be the newest
-- copy (D1: "confirm newest-copy identity"). They are listed in the handback and are read once their own binding moves to the newest copy; one read task each (course_entry_read_enqueue_v1). Every read goes to Layer 4; nothing is
-- admitted. Preconditions (fails and queues nothing otherwise): no entry read waiting; AI allowed; worker v0.54.x; D1 spend so far plus
-- this batch's estimate (expected slices x the highest measured D1 cost a slice x 1.25) within US$6; balance above its floor by the estimate.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
        v_qut constant uuid := '2c4f515c-c146-4e90-ba8a-294130aa1f40';
        v_ceiling constant numeric := 6;
        v_reason constant text := 'AER D1 long pages batch 2 (QUT held; Platform Admin mandate 30 Oct 2026 08:45; ceiling US$6)';
        v_ids uuid[]; v_slices numeric; v_n int; v_spent numeric; v_slice numeric; v_est numeric; v_bal numeric; v_floor numeric; v_worker text;
        v_jobs jsonb := '[]'::jsonb; c uuid; v_el uuid[];
begin
  select count(*) into v_n from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if v_n <> 0 then raise exception 'D1 precondition: % entry reads are waiting', v_n; end if;
  if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'D1 precondition: AI reading is stopped (AI limits)'; end if;
  select l.detail->>'worker' into v_worker from pipeline.mode_outcome_ledger l where l.detail ? 'worker' order by l.run_at desc limit 1;
  if v_worker is null or v_worker not like 'coverage-sweep-worker-v0.54.%' then raise exception 'D1 precondition: deployed worker is %, expected v0.54.x', v_worker; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.course_page_chars') <> to_jsonb(205000) then raise exception 'D1 precondition: entry.course_page_chars is not 205,000'; end if;

  v_el := array(select e.course_id from security.course_entry_eligible_v1() e where e.provider_id = v_qut);
  with latest as (select distinct on (f.course_id) f.course_id, (substring(f.reason from 'page text is ([0-9]+) characters'))::int chars
                    from pipeline.field_enrich_items f where f.provider_id = v_qut and f.field = 'entry_requirements' order by f.course_id, f.created_at desc)
  select array_agg(l.course_id order by l.course_id), sum(1 + ceil(greatest(l.chars - 11871, 0) / 11280.0))
    into v_ids, v_slices
    from latest l join pipeline.coverage_course_pages g on g.course_id = l.course_id and g.status = 'bound'
   where l.chars > 100000 and l.chars <= 205000 and l.course_id = any (v_el)
     -- the bound copy is the newest stored copy of its page (a double-degree page is shared, so the newest copy may carry a sibling's course id)
     and exists (select 1 from pipeline.evidence_artifacts b where b.id = g.evidence_id and b.storage_path is not null
                   and not exists (select 1 from pipeline.evidence_artifacts n where n.source_url = b.source_url and n.storage_path is not null and n.created_at > b.created_at)
                   and not exists (select 1 from pipeline.evidence_artifacts n where n.metadata->>'course_id' = l.course_id::text and n.storage_path is not null and n.created_at > b.created_at));
  if coalesce(array_length(v_ids, 1), 0) <> 36 then raise exception 'D1 precondition: % QUT held long pages eligible and on their newest copy, expected 36', coalesce(array_length(v_ids, 1), 0); end if;

  select coalesce(sum(f.cost_usd), 0), max(f.cost_usd / nullif((f.value->'coverage'->>'slices')::int, 0)) into v_spent, v_slice
    from pipeline.field_enrich_items f join pipeline.admin_jobs j on j.id = f.job_id where f.field = 'entry_requirements' and j.reason like 'AER D1 long pages%';
  v_est := round(v_slices * coalesce(v_slice, 0.0025) * 1.25, 4);
  if v_spent + v_est > v_ceiling then raise exception 'D1: spend so far US$% plus this batch''s estimate US$% would pass the ceiling US$%', v_spent, v_est, v_ceiling; end if;
  select (l.detail->>'remaining_usd')::numeric into v_bal from pipeline.mode_outcome_ledger l where l.mode = 'openrouter_balance' and l.detail ? 'remaining_usd' order by l.run_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is null or v_bal - v_floor < v_est then raise exception 'D1 precondition: balance US$% is not above the floor US$% by the estimate US$%', v_bal, v_floor, v_est; end if;

  foreach c in array v_ids loop
    v_jobs := v_jobs || to_jsonb(security.course_entry_read_enqueue_v1(c, v_pa, v_reason));
  end loop;
  select count(*) into v_n from pipeline.field_enrich_items f where f.job_id in (select (x)::uuid from jsonb_array_elements_text(v_jobs) x) and f.state = 'queued';
  if v_n <> 36 then raise exception 'D1: % reads queued, expected 36', v_n; end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_requirements', 'programme_batch', 'migration 20261030240000',
          jsonb_build_object('line', 'D1', 'batch', 2, 'courses', 36, 'left_out_not_newest_copy', 6, 'course_ids', to_jsonb(v_ids), 'expected_slices', v_slices, 'spent_before_usd', v_spent,
                             'estimate_usd', v_est, 'ceiling_usd', v_ceiling, 'cost_a_slice_used', v_slice, 'balance_usd', v_bal, 'floor_usd', v_floor,
                             'worker', v_worker, 'reason', v_reason), v_pa);
end $$;
