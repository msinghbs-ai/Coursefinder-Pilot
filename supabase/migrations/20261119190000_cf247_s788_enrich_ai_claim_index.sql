-- CF-247 s788, IQ-00053 (Platform Admin 19 Nov 2026 23:12 and 23:21 AEDT, chat S1-Build): the remaining enrich_ai HTTP 500s.
-- Found (rolled-back live reads through GitHub Actions, 19 Nov 2026 23:20-23:30 AEDT):
--   - every enrich_ai HTTP 500 since 21:00 AEDT (52 of 2,781 coverage-sweep replies) is "svc_enrich_ai_next: canceling statement due to
--     statement timeout"; no lock waits;
--   - the claim's first pick (pick0) filters state with an OR (state = 'ai' or an expired lease), which no index matches, so the planner walks
--     idx_field_enrich_items_job_state in job order to satisfy ORDER BY ... LIMIT: 266,611 rows read and discarded to find 0 to 12 claimable
--     ones (252 exist), 2.5 s with nothing contending and past the time-out when callers overlap. The other parts take 1 to 300 ms.
-- What changes (index and md5-guarded fragment edit; no table, job or setting):
--   - partial index field_enrich_items_claim_idx on (job_id, (course_id is null), course_id, id) where state in ('ai','leased') and
--     attempts < 3: the claimable rows only, in the pick's own order, so the pick is a keyset read of the index under FOR UPDATE SKIP LOCKED;
--   - both picks of public.svc_enrich_ai_next name state in ('ai','leased') first (same rows as before). With it the planner starts from the
--     claimable rows (this index, or the existing partial idx_field_enrich_items_state) instead of walking every item.
-- Replaces: the full-index walk of pick0.
-- Retires: nothing.
-- G1: no job. G2: no setting. G3: untouched (75 functions, 48 tables; public.svc_enrich_ai_next is a worker function, not consumer API).

create index if not exists field_enrich_items_claim_idx
  on pipeline.field_enrich_items (job_id, (course_id is null), course_id, id)
  where state in ('ai', 'leased') and attempts < 3;
comment on index pipeline.field_enrich_items_claim_idx is
  'CF-247 s788 (IQ-00053): claimable enrich items in the order svc_enrich_ai_next hands them out (keyset read under FOR UPDATE SKIP LOCKED).';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.cf_edit_def('public.svc_enrich_ai_next(integer)'::regprocedure, '91b15e0d47ea762d391f3a937b49f72c',
  array[$o$  with pick0 as (select e.id, e.job_id, e.course_id from pipeline.field_enrich_items e
                 where (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3$o$,
        $o$               and (e.job_id, e.course_id) in (select p0.job_id, p0.course_id from pick0 p0 where p0.course_id is not null)
               and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3$o$],
  array[$n$  with pick0 as (select e.id, e.job_id, e.course_id from pipeline.field_enrich_items e
                 where e.state in ('ai', 'leased') and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3  -- s788: field_enrich_items_claim_idx$n$,
        $n$               and (e.job_id, e.course_id) in (select p0.job_id, p0.course_id from pick0 p0 where p0.course_id is not null)
               and e.state in ('ai', 'leased') and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3$n$]);

-- post-checks: the pick reads the new index, and the whole claim is well under a second
do $$
declare v_r jsonb := security.ai_enrich_routes_v1(); q text; r record; v_plan text := ''; t timestamptz; v_ms int;
  v_off text[] := array(select jsonb_array_elements_text(v_r->'off_fields')); v_capf text[] := array(select jsonb_array_elements_text(v_r->'limit_fields'));
  v_not text[] := array(select jsonb_array_elements_text(v_r->'rest_except')); v_od uuid[] := array(select jsonb_array_elements_text(v_r->'on_demand_providers'))::uuid[];
  v_off_rest boolean := coalesce((v_r->>'off_rest')::boolean, false); v_cap_rest boolean := coalesce((v_r->>'limit_rest')::boolean, false);
begin
  q := format($q$explain (costs off) select e.id from pipeline.field_enrich_items e
     where e.state in ('ai', 'leased') and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
       and not (e.field = any(%L::text[])) and not (%L::boolean and not (e.field = any(%L::text[])))
       and (e.provider_id = any(%L::uuid[]) or (not (e.field = any(%L::text[])) and not (%L::boolean and not (e.field = any(%L::text[])))))
     order by e.job_id, (e.course_id is null), e.course_id, e.id limit 40 for update skip locked$q$, v_off, v_off_rest, v_not, v_od, v_capf, v_cap_rest, v_not);
  for r in execute q loop v_plan := v_plan || r."QUERY PLAN" || ' '; end loop;
  -- the planner may read the new keyset index or the existing partial state index (both start from the claimable rows); never the walk of
  -- idx_field_enrich_items_job_state over every item, which is what timed out
  if v_plan !~ '(field_enrich_items_claim_idx|idx_field_enrich_items_state)' or v_plan ~ 'idx_field_enrich_items_job_state' then
    raise exception 'post-check: the claim does not start from the claimable rows: %', v_plan;
  end if;
  -- timed inside a sub-block that is always rolled back, so the check leases nothing and spends no attempt
  begin
    t := clock_timestamp(); perform public.svc_enrich_ai_next(40); v_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
    raise exception 'cf-s788-undo';
  exception when raise_exception then
    if sqlerrm <> 'cf-s788-undo' then raise; end if;
  end;
  if v_ms > 1000 then raise exception 'post-check: svc_enrich_ai_next(40) took % ms (target under 1 s)', v_ms; end if;
  perform set_config('cf.diag', format('claim plan: %s | svc_enrich_ai_next(40) %s ms', left(regexp_replace(v_plan, '\s+', ' ', 'g'), 600), v_ms), true);
end $$;
