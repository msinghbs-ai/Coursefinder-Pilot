-- CF-247 StudySearch SS-016 UR-08, UR-10, UR-11, UR-12 (Platform Admin direction 1 Nov 2026 22:01).
-- After md5 values from a rolled-back dry run, 1 Nov 2026 23:00 AEDT (live unchanged afterwards): platform_notices_v1 88cffd39, admin_automations_read_v1 419aef5d, platform_health_state_v1 27dfaf03.
-- Why: the automation catalogue, the field register and three admin read functions still say what the platform no longer does:
--   platform-alerts says external delivery is off (D12 switched it on 31 Oct 2026 23:05; alerts.delivery_enabled = true);
--   provider-onboarding says it stops at Ready to admit for a person (Admit automatically is on since 12 Oct 2026);
--   central-ai and provider-facts say a person approves every central page (policy-auto-approve approves checked English and calendar readings);
--   policy-auto-approve names focus providers only (central.auto_approve_english_all covers English for every university since 23 Oct 2026);
--   field_register academic_entry says "No reader yet" (the AER reader exists; only this coverage measure is not connected);
--   two notice hints send people to retired screens (Jobs › Priority, Scrapers & fetchers);
--   a retiring automation does not carry its note (dependencies) and a health check does not carry its cadence.
-- What: text only, plus two additive keys on two admin reads. No switch, value, schedule, rank or boundary changes.
-- Rollback: re-apply the before texts / definitions (each edit reversed).
-- Replaces: pipeline.automation_catalogue descriptions of platform-alerts, provider-onboarding, central-ai, provider-facts, policy-auto-approve; pipeline.field_register.fills of academic_entry; security.platform_notices_v1 (same name; two hints); security.admin_automations_read_v1 (same name; retirement adds note and purpose); security.platform_health_state_v1 (same name; checks add cadence_minutes)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3: admin reads and pipeline tables only). No setting: words, not values (G2). No new table or job (G1).

-- 1. Catalogue descriptions (guarded on the exact current text; a row already changed is left alone and reported)
do $$
declare r record; n int;
begin
  for r in select * from (values
    ('platform-alerts',
     'Every 10 minutes, two minutes after the health check: turns open critical issues into alerts (deduplicated, escalated, reminded, one recovery notice) under Pipeline settings › Alerts, retries undelivered alerts and fails them visibly. External delivery is off until the Platform Admin approves a destination (decision D7): alerts are then recorded on Platform health only. Admits, reads, queues and spends nothing.',
     'Every 10 minutes, two minutes after the health check: turns open critical issues into alerts (deduplicated, escalated, reminded, one recovery notice) under Pipeline settings › Alerts, retries undelivered alerts and fails them visibly. Alerts are sent by push and e-mail by the hourly "Work queue alerts" scheduled task (D12, while Alerts: deliver outside the platform is on); expect up to about 75 minutes from an issue to the message. Admits, reads, queues and spends nothing.'),
    ('provider-onboarding',
     'Runs each university''s onboarding a step at a time: website, course pages, sample pages, the model''s proposal, save and apply, qualify, central pages, scholarships; stops at Ready to admit for a person.',
     'Runs each university''s onboarding a step at a time: website, course pages, sample pages, the model''s proposal, save and apply, qualify, central pages, scholarships. At Ready to admit: automatic while its switch is on (Admit automatically, Onboarding settings), which admits only the fields that pass and logs them; with the switch off, a Platform Admin admits them on Layer 2 › Adapters.'),
    ('central-ai',
     'Sends queued English language policy and academic calendar pages to the pinned model (GPT-4.1 mini); each score and month must be quoted from the page. Results are proposals a person approves in the Adapter builder (1.3); nothing is applied by the AI.',
     'Sends queued English language policy and academic calendar pages to the pinned model (GPT-4.1 mini); each score and month must be quoted from the page. Proposed: the readings are approved by job policy-auto-approve while its switches are on, otherwise by a Platform Admin (Approvals waiting or the Adapter builder 1.3); the AI applies nothing itself.'),
    ('provider-facts',
     'Finds each university''s international fee schedule, English language policy and academic calendar on its own site and reads them as evidence (fee schedules only where the regulator does not publish fees). Fees, English defaults and semester dates are used only after a Platform Admin approves each document.',
     'Finds each university''s international fee schedule, English language policy and academic calendar on its own site and reads them as evidence (fee schedules only where the regulator does not publish fees). Proposed: a fee schedule is used only after a Platform Admin approves it; English policies and calendars read by the AI are approved by job policy-auto-approve while its switches are on, otherwise by a Platform Admin.'),
    ('policy-auto-approve',
     'Every 10 minutes: approves an AI reading of a focus provider''s English policy or calendar when every value is quoted on the page and course pages do not mostly disagree; otherwise flags it for a person.',
     'Every 10 minutes, automatic while its switches are on (Pipeline settings: central pages for focus providers; English rules for every university): approves an AI reading of an English policy or calendar when every value is quoted on the page and course pages do not mostly disagree; otherwise flags it for a person in Approvals waiting.')
  ) as t(jobname, old_text, new_text) loop
    update pipeline.automation_catalogue c set description = r.new_text where c.jobname = r.jobname and c.description = r.old_text;
    get diagnostics n = row_count;
    if n = 0 and not exists (select 1 from pipeline.automation_catalogue c where c.jobname = r.jobname and c.description = r.new_text) then
      raise notice 'catalogue %: description differs from the text this change replaces; left as it is', r.jobname;
    end if;
  end loop;
end $$;

-- 2. Field register: name the measure, not a missing reader (reader stays 'none' so the stalled-field check is unchanged)
update pipeline.field_register set fills = 'Not measured here yet: entry requirements are read and admitted on Catalogue › Entry requirements (AER)'
 where field = 'academic_entry' and fills = 'No reader yet (next release)';

-- 3. Functions: md5-guarded edits (pattern of 20261101090000_cf247_automation_denial_message.sql)
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- before md5 values read live 1 Nov 2026; after values from the rolled-back dry run
select pg_temp.edit_once('security.platform_notices_v1()', '81bf986bfc60a1525e65cbee733e47f1', '88cffd39d76483d6b91f8f4b092f47d7', array[
  array[$o$'hint', 'Work that needs Firecrawl stops at the reserve set on Scrapers & fetchers.'$o$,
        $n$'hint', 'Firecrawl refuses work when the month''s credits are gone. Top up the Firecrawl account (Models & services › Toolsets & limits › Firecrawl credits).'$n$],
  array[$o$'hint', 'Change the monthly cap on Jobs › Priority.'$o$,
        $n$'hint', 'Change the monthly cap on Models & services › Toolsets & limits › Course-page search budget.'$n$]],
  array[1, 1]);

select pg_temp.edit_once('security.admin_automations_read_v1()', 'f5120aedfd35a82bdf905597cec0267f', '419aef5d1f13e46081a35f23b01d6a15', array[
  array[$o$'retirement',(select jsonb_build_object('status',cr.status,'replaced_by',cr.replaced_by,'retire_after',cr.retire_after) from pipeline.component_register cr$o$,
        $n$'retirement',(select jsonb_build_object('status',cr.status,'replaced_by',cr.replaced_by,'retire_after',cr.retire_after,'note',cr.note,'purpose',cr.purpose) from pipeline.component_register cr$n$]],
  array[1]);

select pg_temp.edit_once('security.platform_health_state_v1(boolean)', '3efe25a96e24bfc4fd0d5d59538e92d0', '27dfaf0312180fefc272d8e3f92f91ce', array[
  array[$o$'checked_at',c.checked_at) order by c.sort_order)$o$,
        $n$'checked_at',c.checked_at,'cadence_minutes',c.cadence_minutes) order by c.sort_order)$n$]],
  array[1]);
