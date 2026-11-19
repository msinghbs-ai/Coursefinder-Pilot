-- CF-247 s791b, IQ-00313 / F-INT VERIFY-01 (Platform Admin 19 Nov 2026 23:12 and 23:21 AEDT, chat S1-Build): Run Now follows the dispatchers.
-- Found in the s790/s791 live read-back (20 Nov 2026 00:58 AEDT): Course intake Run & Validate showed "Blocked: job is paused or not scheduled",
-- and security.job_run_now_v1 refused 'job is paused', because both still read cron.job. Since the cutover of 16 Nov 2026 (migration
-- 20261116190000) intake-dates-apply runs as a live rule of admission-rule-runner (pipeline.admission_rules, legacy_job, mode live, enabled)
-- and its legacy cron row is off and retiring. 33 catalogued jobs are held this way (field_execution_registry, rollup_targets, admission_rules).
-- Fix: security.job_schedule_refusal_v1(job) says why a job is not running on schedule, reading the live dispatcher target first and the
-- cron row only when no dispatcher holds the job (the same sources as security.job_effective_state_v1). Both checks call it (md5-guarded edits).
-- Nothing else in Run Now changes: the Run now list, the catalogue rank, the Intake dates switch, the cohort cap, the job's own lock, and
-- admission through security.intake_dates_apply_v1 with its no-overwrite, manual-lock and same-month guards.
-- Parity before writing (read live 20 Nov 2026 00:58 AEDT): head 20261120002000, 2,197 rows; post-cut-off versions = supabase/migrations one to one.
-- G3: no consumer object. No spend.
-- Replaces: the cron.job reads in security.job_run_now_v1 and public.admin_intake_run_read_v1 (edited in place).
-- Retires: nothing.

create or replace function security.job_schedule_refusal_v1(p_job text)
returns text language sql stable security definer set search_path to '' as $f$
  with d as (
    select r.enabled from pipeline.field_execution_registry r where r.kind = 'worker_lane' and r.mode = 'live' and r.legacy_job = p_job
    union all select t.enabled from pipeline.rollup_targets t where t.mode = 'live' and t.legacy_job = p_job
    union all select a.enabled from pipeline.admission_rules a where a.mode = 'live' and a.legacy_job = p_job)
  select case
    when exists (select 1 from d) then case when bool_or(d.enabled) then null else 'job is paused (its dispatcher target is switched off)' end
    when not exists (select 1 from cron.job j where j.jobname = p_job) then 'job is not scheduled'
    when not exists (select 1 from cron.job j where j.jobname = p_job and j.active) then 'job is paused'
  end from (select 1) one left join d on true
$f$;
revoke all on function security.job_schedule_refusal_v1(text) from public, anon, authenticated;
comment on function security.job_schedule_refusal_v1(text) is 'CF-247 s791b: why a job is not running on schedule (null when it is): its live dispatcher target first (field_execution_registry, rollup_targets, admission_rules by legacy_job), else its cron row.';

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

select pg_temp.cf_edit_def('security.job_run_now_v1(text,text,jsonb,uuid)'::regprocedure, '3c769a37828264b0292e13ca02ef6537',
  array[$o$    when not exists (select 1 from cron.job j where j.jobname = p_job) then 'job is not scheduled'
    when exists (select 1 from cron.job j where j.jobname = p_job and not j.active) then 'job is paused'$o$],
  array[$n$    when security.job_schedule_refusal_v1(p_job) is not null then security.job_schedule_refusal_v1(p_job)  -- s791b: the live dispatcher target, else the cron row$n$]);

select pg_temp.cf_edit_def('public.admin_intake_run_read_v1(text,jsonb)'::regprocedure, 'd98dd923bb41fde5ef5314bca7d2050c',
  array[$o$ when not exists(select 1 from cron.job where jobname='intake-dates-apply' and active) then 'job is paused or not scheduled'$o$],
  array[$n$ when security.job_schedule_refusal_v1('intake-dates-apply') is not null then security.job_schedule_refusal_v1('intake-dates-apply')  -- s791b$n$]);

-- post-checks
do $$
declare v_o text; v_admin uuid; v_coh uuid; cap jsonb; r jsonb; v_paused text;
begin
  if security.job_schedule_refusal_v1('intake-dates-apply') is not null then
    raise exception 'post-check: intake-dates-apply still refused: %', security.job_schedule_refusal_v1('intake-dates-apply'); end if;
  if security.job_schedule_refusal_v1('no-such-job-s791b') is distinct from 'job is not scheduled' then raise exception 'post-check: an unknown job is not refused'; end if;
  select j.jobname into v_paused from cron.job j where not j.active
     and not exists (select 1 from pipeline.field_execution_registry r where r.mode = 'live' and r.legacy_job = j.jobname)
     and not exists (select 1 from pipeline.rollup_targets t where t.mode = 'live' and t.legacy_job = j.jobname)
     and not exists (select 1 from pipeline.admission_rules a where a.mode = 'live' and a.legacy_job = j.jobname) limit 1;
  if v_paused is not null and security.job_schedule_refusal_v1(v_paused) is distinct from 'job is paused' then raise exception 'post-check: paused job % not refused', v_paused; end if;
  v_o := format('intake-dates-apply scheduled (dispatcher); paused example %s: %s; held jobs now scheduled: %s', coalesce(v_paused, '-'), coalesce(security.job_schedule_refusal_v1(v_paused), '-'),
    (select count(*) from cron.job j where not j.active and security.job_schedule_refusal_v1(j.jobname) is null));
  -- the screen and a Run Now on the latest cohort, as a signed-in Platform Admin, always rolled back (nothing kept)
  begin
    select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
     where ro.status = 'active' and (ur.expires_at is null or ur.expires_at > now()) order by ro.rank desc limit 1;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
    cap := public.admin_intake_run_read_v1('capabilities', '{}');
    if cap->>'blocked_reason' is not null then raise exception 'post-check: capabilities still blocked: %', cap->>'blocked_reason'; end if;
    select id into v_coh from pipeline.run_now_cohorts where job = 'intake-dates-apply' order by created_at desc limit 1;
    if v_coh is not null then
      r := security.job_run_now_v1('intake-dates-apply', 's791b post-check (rolled back)', jsonb_build_object('cohort_id', v_coh), v_admin);
      if r->>'state' = 'refused' and r->>'refused' <> 'a run of this job is in progress' then raise exception 'post-check: Run Now refused: %', r->>'refused'; end if;
      v_o := v_o || format(' | Run Now on the latest cohort: %s (processed %s, admitted %s, vendor calls %s)', r->>'state', r->>'processed', r->>'admitted', r->>'vendor_calls');
    end if;
    raise exception 'cf-s791b-undo';
  exception when raise_exception then if sqlerrm <> 'cf-s791b-undo' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('cf.diag', v_o, true);
end $$;
