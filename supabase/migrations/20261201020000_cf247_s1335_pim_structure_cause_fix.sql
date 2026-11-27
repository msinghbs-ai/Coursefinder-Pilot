-- CF-247 s1335 (S2-RM-Design; [PC-20261128-0938-S2-RM-Design], DR-19 acceptance work, 28 Nov 2026 10:05 AEDT): correctness fix to s1295.
-- Found live 28 Nov 2026 09:58 AEDT: the record trace's recovery cause unsupported_website_structure matched the bare word "unsupported", so
-- description guard holds ("held: unsupported_sentence: a sentence is not supported by its quote", "held: unsupported_claim: ...", at least
-- 2,413 skipped attempts in the eight commonest reasons) read as a website-structure problem. They are insufficient evidence.
-- With a structure-only pattern (unsupported page/site/format/file type/structure/layout, JavaScript, scanned or image-only, no text layer,
-- client-side rendering) and guard holds ("held:") excluded, 0 open absences and 0 failed or skipped attempts are structure cases today.
-- What changes: one anchored replacement in security.pim_record_trace_v1 (fragment found exactly once). Read-only function; nothing else.
-- G1: no job. G2: no number. G3: 75/48 asserted. Locks and cron asserted. Nothing dropped.
-- Replaces: the unsupported_website_structure pattern in security.pim_record_trace_v1 (s1295).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

do $e$
declare
  v jsonb := security.consumer_api_check_v1(); v_def text; v_n int; v_locks bigint := (select count(*) from pipeline.manual_locks); v_jobs bigint := (select count(*) from cron.job where active);
  v_old text := $o$when coalesce(v_abs->>'reason', v_last.reason, '') ~* '(unsupported|layout|structure|javascript|scanned|image-only|no text layer)' then 'unsupported_website_structure'$o$;
  v_new text := $n$when coalesce(v_abs->>'reason', v_last.reason, '') ~* '(unsupported (page|site|format|file type|structure|layout)|page layout|site structure|javascript|scanned|image-only|no text layer|client-side render)'
            and coalesce(v_abs->>'reason', v_last.reason, '') !~* 'held:' then 'unsupported_website_structure'$n$;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  v_def := pg_get_functiondef('security.pim_record_trace_v1(uuid, text, boolean)'::regprocedure);
  if position(v_new in v_def) > 0 then raise notice 's1335: already applied'; return; end if;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'guard: the s1295 structure pattern is found % times', v_n; end if;
  execute replace(v_def, v_old, v_new);
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> v_locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> v_jobs then raise exception 'post-check: active job count changed'; end if;
end $e$;
