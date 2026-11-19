-- CF-247: one Layer 3 English or intake claim at a time per task. After 20261001179000 a few claims (3 to 4 every 10
-- minutes until 09:10 UTC on 1 Oct 2026) still failed with the one-open-call rule: two claims sent together each chose
-- the same course, because the second one locked the course page just after the first committed, and its own view
-- was taken before. The claim now waits for any other claim of the same task to finish before choosing pages (a claim
-- takes under a second since 20261001179100). Edited in place, only if its body is the one left by 179100 (md5 guard).

do $claim$
declare s text; d text; v text;
  o text := E'  -- stale claims (worker lost)';
  n text := E'  -- one claim at a time per task, so two claims sent together never choose the same course\n  perform pg_advisory_xact_lock(hashtext(''layer3-fact-claim:''||p_task_class));\n\n  -- stale claims (worker lost)';
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'layer3_fact_claim_service';
  v := md5(s);
  if v is distinct from '475d1026145fd952a6f39096e07544f6' then raise exception 'layer3_fact_claim_service changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'stale-claim step not found once'; end if;
  execute replace(d, o, n);
end $claim$;
