-- CF-247 AER bounded paid reads, step 1: B1 and B2 validation reads (Platform Admin mandate 30 Oct 2026 06:53; admin
-- docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md §9; decision paper ui-audit/2026-10-30-platform-admin-decision-paper.md).
--   B1 (hard ceiling US$0.05): three provider sources read again on their newest stored copy through security.aer_reread_v1 (W28):
--      ANU Croatian Matura 87f40035 (kept 0 of 8; quote form accepted since v0.52.0), ANU Bosnia-Herzegovina 6aee5653 (item 509c8f82,
--      1 of 5 kept, quote_not_on_page 4), Melbourne India State Board 467c7a0c (item 290bd250, 1 of 9 kept, quote_not_on_page 8).
--      Their earlier reads cost US$0.0060, US$0.0014 and US$0.0029.
--   B2 (hard ceiling US$0.10): the three Monash course reads cut at about 8,000 characters on 29 Oct (e58e7771, 512b56fe, 9cf18451),
--      read again once each through security.course_entry_read_enqueue_v1; worker v0.54.x reads long pages in slices (W29) and holds a
--      cut read whole (held_partial) instead of proposing part of it. Their failed items stay as history.
-- Preconditions are checked here and the whole migration fails (nothing is queued) if any does not hold: each source's newest run is on
-- its current stored copy and nothing of it is waiting; each Monash course is still eligible and its bound page is the read evidence;
-- no course read is waiting; AI reading is allowed; the latest observed OpenRouter balance is above its floor by more than both ceilings;
-- the deployed worker is v0.54.x. Every output goes to Layer 4 for a person; nothing is admitted here.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
        v_reason constant text := 'AER bounded paid reads step 1 (Platform Admin mandate 30 Oct 2026 06:53)';
        v_sources constant uuid[] := array['87f40035-ff4a-47b2-be18-0f2bfd817f1d', '6aee5653-0741-4e97-ba77-57f222e858aa', '467c7a0c-c3b1-42c1-b4ca-32511f6afd04']::uuid[];
        v_courses constant uuid[] := array['e58e7771-7bb9-4ea6-89fa-f1d2a82fb9b9', '512b56fe-ccd7-4efb-bf4f-59674e891e66', '9cf18451-9cb7-43ca-8a79-a94c81ae17e3']::uuid[];
        v_n int; v_bal numeric; v_floor numeric; v_worker text; v_out jsonb := '[]'::jsonb; v_s uuid; v_c uuid; v_r jsonb; v_job uuid;
begin
  -- preconditions (B1): the newest run of each source is on its current stored copy, finished, and nothing of it is waiting
  select count(*) into v_n from pipeline.entry_matrix_sources s
   where s.id = any (v_sources)
     and (select r.content_hash from pipeline.entry_matrix_runs r where r.source_id = s.id order by r.created_at desc, r.id desc limit 1) is not distinct from s.content_hash
     and not exists (select 1 from pipeline.entry_matrix_runs r where r.source_id = s.id and r.state in ('queued', 'leased'));
  if v_n <> 3 then raise exception 'B1 precondition: expected 3 sources on their newest copy with nothing waiting, found %', v_n; end if;
  -- preconditions (B2): still eligible, bound page read with its CRICOS code, the failed item is the only one, nothing waiting
  select count(*) into v_n from security.course_entry_eligible_v1() e where e.course_id = any (v_courses);
  if v_n <> 3 then raise exception 'B2 precondition: expected 3 eligible Monash courses, found %', v_n; end if;
  select count(*) into v_n from pipeline.field_enrich_items f where f.course_id = any (v_courses) and f.field = 'entry_requirements' and f.state = 'failed';
  if v_n <> 3 then raise exception 'B2 precondition: expected exactly 3 failed course reads, found %', v_n; end if;
  select count(*) into v_n from pipeline.field_enrich_items f where f.course_id = any (v_courses) and f.field = 'entry_requirements' and f.state <> 'failed';
  if v_n <> 0 then raise exception 'B2 precondition: % other course read items already exist for these courses', v_n; end if;
  select count(*) into v_n from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if v_n <> 0 then raise exception 'precondition: % course reads are already waiting', v_n; end if;
  if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'precondition: AI reading is stopped (AI limits)'; end if;
  select (l.detail->>'remaining_usd')::numeric into v_bal from pipeline.mode_outcome_ledger l where l.mode = 'openrouter_balance' and l.detail ? 'remaining_usd' order by l.run_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is null or v_bal - v_floor < 0.15 then raise exception 'precondition: balance US$% is not above the floor US$% by both ceilings (US$0.15)', v_bal, v_floor; end if;
  select l.detail->>'worker' into v_worker from pipeline.mode_outcome_ledger l where l.detail ? 'worker' order by l.run_at desc limit 1;
  if v_worker is null or v_worker not like 'coverage-sweep-worker-v0.54.%' then raise exception 'precondition: deployed worker is %, expected v0.54.x', v_worker; end if;

  -- B1: Read again on the newest stored copy (W28), one source at a time
  foreach v_s in array v_sources loop
    v_r := security.aer_reread_v1(v_s, v_reason || ': B1 source re-read (ceiling US$0.05 for the three)', v_pa);
    v_out := v_out || jsonb_build_array(jsonb_build_object('line', 'B1', 'source', v_s, 'result', v_r));
  end loop;
  -- B2: one course read each (sliced by the worker when long)
  foreach v_c in array v_courses loop
    v_job := security.course_entry_read_enqueue_v1(v_c, v_pa, v_reason || ': B2 Monash course read (ceiling US$0.10 for the three)');
    v_out := v_out || jsonb_build_array(jsonb_build_object('line', 'B2', 'course', v_c, 'job', v_job));
  end loop;

  -- post-checks: exactly 3 runs queued for the three sources, 3 course reads queued
  select count(*) into v_n from pipeline.entry_matrix_runs r where r.source_id = any (v_sources) and r.state = 'queued';
  if v_n <> 3 then raise exception 'B1 post-check: expected 3 queued runs, found %', v_n; end if;
  select count(*) into v_n from pipeline.field_enrich_items f where f.course_id = any (v_courses) and f.field = 'entry_requirements' and f.state = 'queued';
  if v_n <> 3 then raise exception 'B2 post-check: expected 3 queued course reads, found %', v_n; end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'programme_batch', 'migration 20261030050000',
          jsonb_build_object('step', 'B1+B2', 'ceilings_usd', jsonb_build_object('B1', 0.05, 'B2', 0.10), 'balance_usd', v_bal, 'floor_usd', v_floor,
                             'worker', v_worker, 'queued', v_out, 'reason', v_reason), v_pa);
end $$;
