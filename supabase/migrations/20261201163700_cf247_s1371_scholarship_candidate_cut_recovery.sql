-- CF-247 s1371 (S2-Build; PC-20261128-CONTINUOUS-BUILD-EXECUTE scope "scholarship reader/listing and coverage machinery: fix reusable bottlenecks only";
-- Agent Operating Model, S2-Scholarship rule 2 "long-page failures are a technical recovery lane"; DR-19).
-- Defect (live read 28 Nov 2026 22:20 AEDT): scholarship candidate pages whose prompt-version-3 read is cut at the answer limit never reach a decision.
--   * s985 (23 Nov) reads a cut answer next as the two-part read (sectioned-v1), but only on escalation to the next model in the chain. The active
--     chain is qwen3-30b alone (security.scholarship_ai_next_model_v1('qwen3-30b') is null), so the same whole-page request is asked again, word for
--     word, until the attempt cap: 316 cut calls on 187 items in 7 days, US$0.51 spent on answers that are thrown away.
--   * The long-page recovery queue (security.scholarship_detail_recovery_queue_v1) takes admitted scholarships only. A candidate page whose reads all
--     failed stays read_status 'read', admit_status null, with its stored copy and rule facts, and is never asked again: 114 candidates on 28 Nov
--     (98 cut, the rest no answer or unreadable), the oldest read on 2 Nov. No sectioned-v1 item has ever been queued for a candidate.
-- Fix (two anchored edits on the live definitions; no table, column, job, setting, route or data change):
--   1. public.svc_scholarship_ai_record: when a cut answer is retried by the same model (no next model), the retry is the two-part read, as s985
--      already does on escalation. Only prompt version 3 or later, only while a try is left, and an item already marked keeps its variant.
--   2. security.scholarship_detail_recovery_queue_v1: within the same limit (after the scholarship recovery items), a candidate page with a stored
--      copy, no successful version 3 read, a version 3 read that was cut, empty or unreadable, and no recovery item yet, is queued once as an 'admit'
--      item with the sectioned-v1 variant. The existing picker, worker two-part read, record and admission path (scholarship_ai_apply_v1) settle it.
--      Runs from the existing scholarship-ai-extract job through security.scholarship_ai_fire_v1 -> scholarship_detail_backfill_v1 when nothing
--      else is due (batch.sch_detail_backfill); provider hidden, directory site and the route's switch, cap and daily ceiling apply as before.
-- Bounded: at most one recovery item per candidate (q.recovery is not null excludes it afterwards). AI spend stays under the existing route caps and
-- the US$5.00 daily ceiling. G3: not the consumer API (75/48 asserted). Manual locks and active cron asserted unchanged.
-- Replaces: the same-model retry branch of public.svc_scholarship_ai_record (cut answers were retried as the same whole-page request);
--           the scholarship-only selection of security.scholarship_detail_recovery_queue_v1 (candidate pages added).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

do $t$
declare v_def text; v_n int; r record; v jsonb;
  v_locks bigint := (select count(*) from pipeline.manual_locks); v_jobs bigint := (select count(*) from cron.job where active);
begin
  for r in select * from (values
    ('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)', 1,
     $o1$         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id where id = q.id;$o1$,
     $n1$         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id,
         -- s1371 (28 Nov 2026): a cut answer retried by the same model (no next model in the chain) is read next as the two-part read, as s985 does on escalation
         recovery = case when coalesce(p_error, '') like 'held_partial: output_truncated%' and coalesce(q.prompt_version, 0) >= 3 and q.attempts < 3 and q.recovery is null
                         then 'sectioned-v1' else q.recovery end
   where id = q.id;$n1$),
    ('security.scholarship_detail_recovery_queue_v1(integer)', 2,
     $o2$declare a record; n int;$o2$,
     $n2$declare a record; n int; v_k int;$n2$),
    ('security.scholarship_detail_recovery_queue_v1(integer)', 3,
     $o3$  get diagnostics n = row_count;
  return n;$o3$,
     $n3$  get diagnostics n = row_count;
  -- s1371 (28 Nov 2026): candidate pages whose version 3 reads were all cut, empty or unreadable are read once as the two-part read, within the same limit
  if n < p_limit then
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, candidate_id, provider_id, url, storage_path, recovery)
    select a.model_code, a.prompt_version, 'admit', c.id, c.provider_id, coalesce(c.final_url, c.url), c.storage_path, 'sectioned-v1'
      from pipeline.scholarship_page_candidates c
     where c.read_status = 'read' and c.admit_status is null and c.storage_path is not null
       and c.source <> 'register' and c.admitted_scholarship_id is null and c.matched_scholarship_id is null
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not security.third_party_host_v1(coalesce(c.final_url, c.url))
       and not exists (select 1 from pipeline.scholarship_ai_extractions x where x.candidate_id = c.id and x.prompt_version >= 3 and x.error is null)
       and exists (select 1 from pipeline.scholarship_ai_extractions x where x.candidate_id = c.id and x.prompt_version >= 3
                    and (x.error like 'held_partial: output_truncated%' or x.error like 'no_answer%' or x.error like 'unreadable_answer%'))
       and not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id = c.id and (q.state in ('queued', 'leased') or q.recovery is not null))
     order by c.read_at desc
     limit p_limit - n;
    get diagnostics v_k = row_count;
    n := n + v_k;
  end if;
  return n;$n3$)
  ) x(fn, n, old, new) order by n loop
    v_def := pg_get_functiondef(r.fn::regprocedure);
    if position(r.new in v_def) > 0 then raise notice 's1371 edit %: already applied', r.n; continue; end if;
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: fragment % of % found % times', r.n, r.fn, v_n; end if;
    execute replace(v_def, r.old, r.new);
  end loop;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> v_locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> v_jobs then raise exception 'post-check: active job count changed'; end if;
end $t$;
