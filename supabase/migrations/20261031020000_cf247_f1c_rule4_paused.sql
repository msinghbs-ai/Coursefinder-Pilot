-- CF-247 StudySearch transformation, decision F1c (Platform Admin, 31 Oct 2026 11:24, answered in session: "Keep paused, review first";
-- admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §8.9 and §10): job l4-rule-low-agreement is paused on purpose.
-- Why: security.l4_rule_low_agreement_v1 qualifies all 1,185 enabled adapters in one daily call and has failed at the 120 s limit since
-- 29 Oct 2026 (last success 28 Oct). It ADMITS data: for a field an adapter reads on half the pages or more but agrees on under 90%, it sets
-- admit = true ("Rule 4: low agreement, page wins") and starts an adapter apply. Fixing the time-out would restart automatic admissions, so the
-- Platform Admin chose to keep it off until the rule's value is reviewed. Pausing it stops a daily failure being reported as an incident.
-- Also: the job catalogue described it as "Sends values that sources disagree on to review", which is not what it does; the description now
-- says what it does and that it is paused, by whom and why.
-- Hygiene (StudySearch finding F6, §8.5 and §8.10): public.admin_ui_error_report already refuses a caller with no signed-in user before writing;
-- its EXECUTE grant to anon is removed (no behaviour change). Grants to authenticated are restated unchanged.
-- Not changed: the function security.l4_rule_low_agreement_v1, its schedule text, any adapter's admit flags, any data, any consumer object.
-- Restart is a separate decision (re-activate the job, or batch it across runs with a setting: §8.9).
-- Replaces: nothing
-- Retires: nothing (the job is paused, not retired; the rule's future is the Platform Admin's review)
-- Nothing dropped, deleted or renamed. No new table, column, job, setting or status.

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'l4-rule-low-agreement') then raise exception 'F1c: job l4-rule-low-agreement not found'; end if;
end $$;
select cron.alter_job((select jobid from cron.job where jobname = 'l4-rule-low-agreement'), active := false);

update pipeline.automation_catalogue
   set description = 'PAUSED (Platform Admin 31 Oct 2026, StudySearch decision F1c: keep paused until the rule is reviewed). Daily Rule 4 "low agreement, page wins": for each enabled adapter, a field the adapter reads on at least half its pages but agrees with held values on fewer than 90% is admitted from the page (the adapter''s admit flag is set and an adapter apply starts). It had failed at its time limit since 29 Oct 2026 (it checks every adapter in one run); no Rule 4 admission happens while paused.'
 where jobname = 'l4-rule-low-agreement' and description not like 'PAUSED (Platform Admin 31 Oct 2026%';

revoke execute on function public.admin_ui_error_report(text, text, text, jsonb) from public, anon;
grant execute on function public.admin_ui_error_report(text, text, text, jsonb) to authenticated;

-- post-check
do $$
begin
  if (select active from cron.job where jobname = 'l4-rule-low-agreement') then raise exception 'F1c post-check: the job is still active'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'l4-rule-low-agreement' and description like 'PAUSED (Platform Admin 31 Oct 2026%') then
    raise exception 'F1c post-check: the catalogue does not say the job is paused'; end if;
  if has_function_privilege('anon', 'public.admin_ui_error_report(text,text,text,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.admin_ui_error_report(text,text,text,jsonb)', 'execute') then
    raise exception 'F6 post-check: grants on admin_ui_error_report'; end if;
end $$;
