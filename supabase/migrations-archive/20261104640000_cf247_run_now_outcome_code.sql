-- CF-247 hotfix: governed Run Now records its outcome with a code production allows (Platform Admin decision 4 Nov 2026 20:05; 10-minute gate 20:02).
-- Cause (production 21:50 AEDT, immediate validation of v2.15.477): security.job_run_now_v1 wrote pipeline.admin_jobs.outcome = 'ran', which is not in
-- pipeline.ops_outcome_codes (foreign key admin_jobs_outcome_fkey, a live constraint the PG16 fixture did not carry), so the whole run rolled back
-- and nothing was filled. The refused path wrote 'refused', also not a code. Fix: succeeded_with_result when the job admitted at least one value,
-- succeeded_no_movement when it ran and admitted nothing, failed_retryable on error, blocked_policy when Run Now refuses (switch, pause, in-flight
-- run, cap). Nothing else in the function changes; the scheduled job is untouched.
-- Live before: security.job_run_now_v1(text,text,jsonb,uuid) cabacd4094ed138a57f6b102183eeacc (guarded; the edit applies exactly once).
-- Replaces: security.job_run_now_v1(text,text,jsonb,uuid) (same name; the admin_jobs outcome code only)
-- Retires: nothing

do $hf$
declare v_sig constant text := 'security.job_run_now_v1(text,text,jsonb,uuid)';
        v_def text := pg_get_functiondef(v_sig::regprocedure);
        v_old constant text := $o$'cohort:' || v_cohort.id, case when v_err is null then 'ran' else 'failed' end)$o$;
        v_new constant text := $n$'cohort:' || v_cohort.id, case when v_err is not null then 'failed_retryable' when coalesce((v_res->>'admitted')::int, 0) > 0 then 'succeeded_with_result' else 'succeeded_no_movement' end)$n$;
        v_old2 constant text := $o$'cohort:' || coalesce(v_cohort.id::text, '-'), 'refused');$o$;
        v_new2 constant text := $n$'cohort:' || coalesce(v_cohort.id::text, '-'), 'blocked_policy');$n$;
        v_n int;
begin
  if position(v_new in v_def) > 0 then raise notice '%: already applied', v_sig; return; end if;
  -- fixed: guard against editing a definition other than the one this hotfix was written against
  if md5(v_def) <> 'cabacd4094ed138a57f6b102183eeacc' then raise exception 'live % differs from the definition this hotfix edits (md5 %)', v_sig, md5(v_def); end if;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception '%: the outcome expression must occur exactly once (found %)', v_sig, v_n; end if;
  v_n := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  if v_n <> 1 then raise exception '%: the refused outcome must occur exactly once (found %)', v_sig, v_n; end if;
  execute replace(replace(v_def, v_old, v_new), v_old2, v_new2);
  raise notice '%: applied, md5 %', v_sig, md5(pg_get_functiondef(v_sig::regprocedure));
end $hf$;
