-- CF-247 s1152 (S1-Build / Release Controller; Platform Admin 25 Nov 2026 15:40 AEDT: "Retain the existing v6 meaningful-content selector and correct the
-- three demonstrated missed lines").
-- Found live (rolled back, 25 Nov 2026 16:05 AEDT, recall check run s1140-entry-cohort-v6-2026-11-25): three entry lines are on their stored pages but
-- outside the v6 selection. Two of them are lost when the page becomes lean text (gold_in_lean false: CTI "Previous completion of a Diploma of
-- Information Technology ... OR ability to demonstrate ...", Holmesglen "You may also be considered if you have: Completed an Australian Diploma ...");
-- one is in the lean text but its block is not selected (SP Jain "Graduate with an AUSTRALIAN DEGREE (AQF Level 9)"). The same lines are selected on a
-- test page, so the cause is in each page's markup, which the recall check does not keep.
-- What this does (worker v1.0.45, lean-miss.ts): the existing recall check (job lean-sections-eval) also records where such a line sits (its lean block,
-- the selector's signal, the nearest heading and the stored markup around it) in a new column pipeline.lean_section_eval_cases.miss_detail, and the six
-- missed v6 cases are read again under run s1152-entry-miss-detail-2026-11-25, first handed out ten minutes after this migration so the new worker reads
-- them. Stored copies only: no AI, no Firecrawl, nothing admitted, no selection change. The fix follows from what it records.
-- public.svc_lean_sections_eval_record_v1 was live only (no migration in the repository); it is now kept here, with the one added column.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: public.svc_lean_sections_eval_record_v1 (same function, also records miss_detail).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_lean_sections_eval_record_v1(jsonb)'::regprocedure)) <> '4c152f2eb34861faaf537117c167996a' then
    raise exception 'guard: public.svc_lean_sections_eval_record_v1 is not the definition read on 25 Nov 2026';
  end if;
end $g$;
create temp table s1152_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1152_cron on commit drop as select count(*) n from cron.job where active;

alter table pipeline.lean_section_eval_cases add column if not exists miss_detail jsonb;
comment on column pipeline.lean_section_eval_cases.miss_detail is 'CF-247 s1152: for a labelled line on the stored page but outside the selection, where it sits (lean block, signal, heading, stored markup around it); diagnostic only, written by worker mode lean_sections_eval from v1.0.45.';

create or replace function public.svc_lean_sections_eval_record_v1(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows) <> 'array' then return jsonb_build_object('recorded', 0); end if;
  update pipeline.lean_section_eval_cases c set state = case when x->>'error' is null then 'done' else 'failed' end, leased_until = null, done_at = now(),
    selector = left(x->>'selector', 40), converter = left(x->>'converter', 40), worker = left(x->>'worker', 60), page_chars = (x->>'page_chars')::int,
    cut_chars = (x->>'cut_chars')::int, lean_chars = (x->>'lean_chars')::int, lean_blocks = (x->>'lean_blocks')::int, gold_in_page = (x->>'gold_in_page')::boolean,
    gold_in_current = (x->>'gold_in_current')::boolean, gold_in_first_cut = (x->>'gold_in_first_cut')::boolean, gold_in_lean = (x->>'gold_in_lean')::boolean,
    gold_in_selection = (x->>'gold_in_selection')::boolean, no_selection = (x->>'no_selection')::boolean, selected_blocks = (x->>'selected_blocks')::int,
    selected_chars = (x->>'selected_chars')::int, block_ids = case when jsonb_typeof(x->'block_ids') = 'array' then x->'block_ids' end,
    miss_detail = case when jsonb_typeof(x->'miss_detail') = 'array' then x->'miss_detail' end,  -- s1152
    error = left(x->>'error', 300)
  from jsonb_array_elements(p_rows) x where c.id = (x->>'case_id')::bigint and c.state = 'pending';
  get diagnostics v_n = row_count;
  return jsonb_build_object('recorded', v_n);
end $function$;
revoke all on function public.svc_lean_sections_eval_record_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_lean_sections_eval_record_v1(jsonb) to service_role;

do $seed$
declare v_run constant text := 's1152-entry-miss-detail-2026-11-25'; v_from constant text := 's1140-entry-cohort-v6-2026-11-25'; v_n int;
begin
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold, leased_until)
  select v_run, x.field, x.gold_source, x.source_ref, x.course_id, x.evidence_id, x.storage_path, x.gold, now() + interval '10 minutes'  -- fixed: after the worker deploy
    from pipeline.lean_section_eval_cases x
   where x.run_label = v_from and x.state = 'done' and x.gold_in_page and not x.gold_in_selection
  on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n < 1 or v_n > 12 then raise exception 's1152: % missed cases, not the six found', v_n; end if;  -- fixed: the planned run's size
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'seed', 'pipeline.lean_section_eval_cases', jsonb_build_object('reason', 'Where the v6 selection misses three demonstrated entry lines (Platform Admin 25 Nov 2026 15:40 AEDT)',
          'by', 'migration 20261127010000 (CF-247 s1152)', 'run', v_run, 'from_run', v_from, 'cases', v_n), null);
end $seed$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1152_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1152_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
