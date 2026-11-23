-- CF-247 s989 (S2-Build, scholarships owner; Platform Admin 23 Nov 2026 15:39 AEDT: "Update the scholarship queue picker so it only marks pages as
-- due when either a stored copy is available or the Firecrawl budget gate allows fetching - eliminating the ~255 empty 16-32s worker invocations
-- per hour").
-- Measured live 23 Nov 2026 14:30 to 16:10 AEDT (rolled-back read-backs; head 20261123140002):
-- - security.scholarship_ai_fire_v1 (job scholarship-ai-extract, every minute) counted as due every queued item under the attempt cap. The picker
--   (public.svc_scholarship_ai_next) takes an item only when the provider is not hidden and either the scholarship Firecrawl lane may fetch
--   (stored-first off, or no paid hold on lane sch_scrape) or the item has a stored copy (security.scholarship_ai_has_copy_v1).
-- - With the lane on budget hold ("no room left in today's Firecrawl share for scholarships") the 39 queued items (all admit items, none with a
--   stored copy) were due to the fire job and never takeable by the picker: about 255 worker calls an hour, each returning items 0 after 16 to 32
--   seconds, and no extraction since 23 Nov 03:21 AEDT.
-- Fix: the fire job counts only items the picker can take, with the picker's own two filters, and stops counting at the number the send loop
-- can use (calls at once x 8, the loop's existing ratio). Measured: 182 ms for the 39 untakeable items (the worst case, every item checked).
-- With nothing takeable it falls through to the existing idle fill from stored official pages (F-SCH redesign, 12 Nov 2026), which the untakeable
-- items had been blocking; that fill reads stored copies only ($0 Firecrawl) under the same AI use gate and lane ceiling.
-- G1: no job. G2: no new value (lanes.stored_first_on, the sch_scrape hold and the loop ratio are the existing ones). G3: no consumer object
-- (75/48 before and after). Manual locks untouched. Nothing dropped or removed.
-- Replaces: the fire job's due count of every queued item (now items the picker can take).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s989_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $e$
declare v_def text; v_n int; r record;
begin
  v_def := pg_get_functiondef('security.scholarship_ai_fire_v1()'::regprocedure);
  if position('s989 (23 Nov 2026' in v_def) > 0 then raise notice 's989 edit: already applied'; return; end if;
  if md5(v_def) <> '51245484e579a0d918b5368497ab0de6' then
    raise exception 'guard: live security.scholarship_ai_fire_v1 differs from the definition this change edits (live md5 %)', md5(v_def);
  end if;
  for r in select * from (values
    (1, $o$declare v_open int; v_max int; v_due int; v_sent int := 0; v_block timestamptz; v_okat timestamptz;$o$,
        $n$declare v_open int; v_max int; v_due int; v_sent int := 0; v_block timestamptz; v_okat timestamptz;
        -- s989 (23 Nov 2026): the picker's lane test (public.svc_scholarship_ai_next), so only items it can take are counted as due
        v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;$n$),
    (2, $o$  select count(*) into v_due from pipeline.scholarship_ai_queue q where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3;$o$,
        $n$  -- s989 (23 Nov 2026): due means the picker can take it (provider not hidden; the Firecrawl lane may fetch or a stored copy is held), counted
  -- only up to what the send loop can use (calls at once x 8, the loop's ratio below); was every queued item, about 255 empty worker calls an hour
  select count(*) into v_due from (select q.id from pipeline.scholarship_ai_queue q where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
     and (q.provider_id is null or q.run_kind in ('test', 'qualify') or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id))
     and (v_paid or security.scholarship_ai_has_copy_v1(q.id))
     limit greatest(coalesce(v_max, 3), 1) * 8) t;$n$)) v(n, old, new) order by n
  loop
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: fragment % of security.scholarship_ai_fire_v1 is found % times', r.n, v_n; end if;
    v_def := replace(v_def, r.old, r.new);
  end loop;
  execute v_def;
end $e$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s989_locks) then raise exception 'post-check: manual locks changed'; end if;
  if position('s989 (23 Nov 2026' in pg_get_functiondef('security.scholarship_ai_fire_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: the s989 edit is not in security.scholarship_ai_fire_v1';
  end if;
end $p$;
