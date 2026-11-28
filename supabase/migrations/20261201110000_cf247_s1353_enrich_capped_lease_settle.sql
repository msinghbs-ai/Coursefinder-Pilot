-- CF-247 s1353 (S1-Build; SS-Programme-Control 28 Nov 2026 PC-20261128-1636-RESUME: "close/recover 27 expired capped field_enrich_items leases
-- through existing governed operational path preserving evidence and retry cap, repair terminal state/trace ... no extra queue").
-- Cause: public.svc_enrich_ai_next re-leases an expired lease only while attempts < 3; an item whose third lease expired was never moved to a
-- terminal state, so it stayed 'leased' for ever (27 at 16:36: deadline 23, description 3, intakes 1). A stuck item also blocks E13 and the
-- first-read selectors for its course (they skip a course with a queued, waiting, AI or leased entry item) and counts as AI work waiting.
-- Fix: the claim itself first settles every expired lease at the attempt cap as 'failed' with its reason (the retry cap is kept: nothing is
-- tried a fourth time); value, quote, evidence and attempts are kept as the trace. The next claim settles the 27; nothing else changes.
-- Edited from the live definition (md5 7756cab7, read 28 Nov 2026 16:55), the edit checked to apply exactly once.
-- G1: no job. G2: the cap is the claim's existing 3 (-- fixed: unchanged here). G3: not the consumer API. Nothing dropped or deleted.
-- Replaces: the claim of public.svc_enrich_ai_next that left capped expired leases leased.
-- Retires: nothing.
do $e$
declare d text := pg_get_functiondef('public.svc_enrich_ai_next(integer)'::regprocedure);
  m text := '  with pick0 as (select e.id, e.job_id, e.course_id from pipeline.field_enrich_items e';
  ins text := '  -- s1353: an expired lease at the attempt cap is settled, not left leased (the cap is kept; value, quote, evidence and attempts stay as the trace)
  update pipeline.field_enrich_items e set state = ''failed'', leased_until = null, updated_at = now(),
         reason = left(''lease expired at the attempt cap (3)'' || coalesce('': '' || e.reason, ''''), 300)
   where e.state = ''leased'' and e.leased_until < now() and e.attempts >= 3;  -- fixed: the claim''s existing cap of 3
';
begin
  if md5(d) <> '7756cab77b5e27d4f275003a4c04f76c' then raise exception 'pre-check: public.svc_enrich_ai_next changed since it was read (md5 7756cab7)'; end if;
  if (length(d) - length(replace(d, m, ''))) / length(m) <> 1 then raise exception 'pre-check: the claim marker is not found exactly once'; end if;
  execute replace(d, m, ins || m);
end $e$;

do $e$
declare d text := pg_get_functiondef('public.svc_enrich_ai_next(integer)'::regprocedure);
begin
  if position('lease expired at the attempt cap (3)' in d) = 0 then raise exception 'post-check: the settle step is missing'; end if;
  if has_function_privilege('anon', 'public.svc_enrich_ai_next(integer)', 'EXECUTE') then raise exception 'post-check: anon may run the claim'; end if;
end $e$;
