-- CF-247 s1093 (S2-AER, overnight brief 24 Nov 2026 23:15 AEDT: reusable causes of incomplete reads; Tier 2 qualified lean models only where necessary).
-- Measured live 24 Nov 2026 about 23:40 AEDT (rolled-back read-back): 16 entry-matrix runs (10 AU/CA/NZ providers: Alberta x2, Simon Fraser x2, Victoria, Conestoga, NZ School of ...,
--   Whitecliffe, Open Polytechnic, UBC, Sheridan, Lethbridge, Calgary, Manitoba, Durham and others) failed at 04:25 to 04:35 UTC with "held_unparsed: no deterministic reader proved this table,
--   and the entry_matrices route has no qualified model". That was the route state before s1085 (v1.0.39) put the qualified cascade (Mistral Small 3.2, Qwen3 30B, GPT-4.1 mini) on the route; s1085 requeued
--   only the 13 timed-out runs, not these 16. Since then 28 runs finished through the cascade. This change reads those sources again, once, through the existing governed re-read
--   (public.admin_entry_matrix_reread, stored copy, no Firecrawl). The deterministic readers still run first; the model only reads what no deterministic reader proved; every admission rule stays.
-- Only a source whose latest run is still failed with that exact message is read again; at most 40 sources (guard); a source that has a newer run is left alone. Nothing is admitted here.
-- G1: no job. G2: no operational number written into the run (the guard cap is a safety limit, marked). G3: no consumer object (75/48). Manual locks untouched. Nothing dropped or deleted.
-- Replaces: nothing
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the source rows

create temp table s1093_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $r$
declare
  v jsonb; ids uuid[]; n int := 0; v_cap constant int := 40;  -- fixed: safety cap on one re-read
  v_msg constant text := 'held_unparsed: no deterministic reader proved this table, and the entry_matrices route has no qualified model%';
begin
  select array_agg(distinct r.source_id) into ids
    from pipeline.entry_matrix_runs r
   where r.state = 'failed' and r.error like v_msg
     and not exists (select 1 from pipeline.entry_matrix_runs r2 where r2.source_id = r.source_id and r2.created_at > r.created_at);
  if ids is null then raise notice 'requeue: nothing to read again'; return; end if;
  if cardinality(ids) > v_cap then raise exception 'guard: % sources exceed the safety cap %', cardinality(ids), v_cap; end if;
  loop
    n := n + 1;
    begin
      v := public.admin_entry_matrix_reread(ids, 'S2-AER s1093: failed before the entry_matrices route had its qualified cascade (s1085); read again from the stored copy');
      raise notice 'requeue: % sources: %', cardinality(ids), v;
      exit;
    exception when lock_not_available then
      if n >= 5 then raise; end if;
      perform pg_sleep(3);  -- fixed: wait for a live run to release the row
    end;
  end loop;
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1093_locks) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
