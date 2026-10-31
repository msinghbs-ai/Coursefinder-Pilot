-- CF-247 StudySearch SS-008 decision D3 (Platform Admin 31 Oct 2026 13:30, "APPROVED FOR LOGICAL RETIREMENT"; admin
-- 2026-10-31-studysearch-d1-d6-approval.md and 2026-10-31-studysearch-transformation.md §14 and §27): Rule 4 ("low agreement, page wins")
-- is retired logically.
-- Why (record §14): across all 1,185 enabled adapters it would admit 1 field today; it made 22 admissions ever (13-23 Oct 2026) and none since
-- 24 Oct; it failed daily at its time limit; a field whose sources disagree belongs to Layer 4 review, not automatic admission.
-- What:
--   * the job stays inactive (paused in v2.15.378) and its catalogue entry says it is retired, by whom and why;
--   * job l4-rule-low-agreement and function security.l4_rule_low_agreement_v1 are marked `retiring` in the component register, replaced by
--     Layer 4 review, with retire_after = today + setting hygiene.retire_after_days; the drop goes to the Platform Admin as a paste after that;
--   * nobody but the database owner can execute the function (EXECUTE revoked from public, anon, authenticated and service_role), so it
--     cannot be run from an app or a worker in the meantime.
-- Dependencies checked live (31 Oct 2026): no function, edge function, screen, setting or job other than the inactive job refers to it.
-- Preserved: the 22 historical Rule 4 admissions, their adapter flags, evidence and audit rows; the function and the job definition.
-- Replaces: nothing
-- Retires: job l4-rule-low-agreement and security.l4_rule_low_agreement_v1 (logically now; dropped by paste after hygiene.retire_after_days)
-- Nothing dropped, deleted or renamed. No new table, job, setting or status. Consumer API untouched.

do $$
begin
  if (select active from cron.job where jobname = 'l4-rule-low-agreement') is distinct from false then raise exception 'D3: the Rule 4 job must already be inactive'; end if;
  if exists (select 1 from pg_proc p where p.prosrc ~ 'l4_rule_low_agreement_v1' and p.proname <> 'l4_rule_low_agreement_v1') then
    raise exception 'D3: another function now calls security.l4_rule_low_agreement_v1; review before retiring'; end if;
end $$;

update pipeline.automation_catalogue
   set description = 'RETIRED (Platform Admin 31 Oct 2026, StudySearch decision D3: logical retirement; paused since 31 Oct, F1c). Was the daily Rule 4 "low agreement, page wins": a field an adapter reads on at least half its pages but agrees with held values on fewer than 90% was admitted from the page. Replaced by Layer 4 review. The job stays inactive and is removed by a paste after the retirement period; its 22 past admissions (13-23 Oct 2026) and their evidence are kept.'
 where jobname = 'l4-rule-low-agreement' and description not like 'RETIRED (Platform Admin 31 Oct 2026%';

update pipeline.component_register
   set status = 'retiring', replaced_by = 'Layer 4 review (low-agreement fields are reviewed by a person, not admitted automatically)',
       retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
       note = 'Retired logically by Platform Admin decision D3, 31 Oct 2026 (StudySearch SS-008); job inactive; EXECUTE revoked', updated_at = now()
 where kind = 'job' and name = 'l4-rule-low-agreement' and status = 'active';

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, replaced_by, introduced_in, retire_after, note) values
 ('function', 'security.l4_rule_low_agreement_v1', 'L4 admit', 'Admission', 'Rule 4 "low agreement, page wins" (job l4-rule-low-agreement)', 'retiring', '{}',
  'Layer 4 review (low-agreement fields are reviewed by a person, not admitted automatically)', null,
  current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
  'Retired logically by Platform Admin decision D3, 31 Oct 2026 (StudySearch SS-008); EXECUTE revoked')
on conflict do nothing;

revoke all on function security.l4_rule_low_agreement_v1() from public, anon, authenticated, service_role;

-- post-check
do $$
begin
  if (select active from cron.job where jobname = 'l4-rule-low-agreement') then raise exception 'D3 post-check: the job is active'; end if;
  if not exists (select 1 from pipeline.component_register where kind = 'job' and name = 'l4-rule-low-agreement' and status = 'retiring') then
    raise exception 'D3 post-check: job not marked retiring'; end if;
  if not exists (select 1 from pipeline.component_register where kind = 'function' and name = 'security.l4_rule_low_agreement_v1' and status = 'retiring') then
    raise exception 'D3 post-check: function not marked retiring'; end if;
  if has_function_privilege('service_role', 'security.l4_rule_low_agreement_v1()', 'execute') or has_function_privilege('authenticated', 'security.l4_rule_low_agreement_v1()', 'execute') then
    raise exception 'D3 post-check: the function is still executable by an app role'; end if;
end $$;
