-- CF-247 (20 Oct 2026). All 1,130 Canadian providers came from the IRCC Designated Learning Institutions (DLI) list and each holds a
-- verified IRCC DLI number (catalogue.provider_identifiers scheme 'ircc_dli'), yet their international-enrolment flag was blank. In Canada
-- only a DLI (a school a province or territory has approved to host international students) may enrol study-permit students, so the DLI
-- list is to Canada what CRICOS is to Australia. Platform Admin, 20 Oct 2026, choice "All DLIs Yes (Recommended)".
-- 1 security.ca_dli_apply_v1(): a Canadian provider with a current DLI number is Yes, basis "IRCC Designated Learning Institution (DLI
--   <number>)". Only blank values or values this rule set are touched; a value a person set never changes. A provider whose DLI number
--   ended goes back to blank (its departure from the register is decided in the Layer 4 Inbox as before). Each run that changes something
--   is logged in admin_control_events.
-- 2 Job ca-dli-flag, daily, so providers the DLI register run adds or ends are flagged the same day (catalogued).
-- Replaces: nothing (Canada had no international-enrolment rule)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): only values of enrols_international change, as for New Zealand.

create or replace function security.ca_dli_apply_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_yes int := 0; v_clear int := 0;
begin
  with dli as (
    select distinct on (i.provider_id) i.provider_id, i.identifier
      from catalogue.provider_identifiers i
     where i.scheme = 'ircc_dli' and (i.valid_to is null or i.valid_to > now())
     order by i.provider_id, i.is_primary desc nulls last, i.verified_at desc nulls last),
  m as (
    select p.id,
           case when d.provider_id is not null then true end val,
           case when d.provider_id is not null then 'IRCC Designated Learning Institution (DLI ' || d.identifier || ')' end basis
      from catalogue.providers p
      left join dli d on d.provider_id = p.id
     where security.coverage_country(p.id) = 'CA'
       and (p.enrols_international is null or coalesce(p.enrols_international_basis, '') like 'IRCC Designated Learning Institution%')),
  u as (update catalogue.providers p set enrols_international = m.val, enrols_international_basis = m.basis
          from m where p.id = m.id and (p.enrols_international is distinct from m.val or p.enrols_international_basis is distinct from m.basis)
        returning m.val)
  select count(*) filter (where val), count(*) filter (where val is null) into v_yes, v_clear from u;
  if v_yes + v_clear > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer1', 'ca_dli_apply', 'CA', jsonb_build_object('set_yes', v_yes, 'cleared', v_clear, 'rule', 'IRCC DLI: Platform Admin 20 Oct 2026 "All DLIs Yes"'), null);
  end if;
  return jsonb_build_object('set_yes', v_yes, 'cleared', v_clear);
end $function$;
revoke execute on function security.ca_dli_apply_v1() from public, anon, authenticated;
comment on function security.ca_dli_apply_v1() is 'CF-247 20 Oct 2026: Canadian international-enrolment flag from the IRCC DLI number (Platform Admin "All DLIs Yes")';

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('ca-dli-flag', 'Layer 1 register', 9, 'Canada: international-enrolment flag from the IRCC DLI list', 'Daily: sets each Canadian provider with a current IRCC Designated Learning Institution number to enrols international students (Yes); a provider whose DLI number ended goes back to blank. Values a person set never change.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('ca-dli-flag', '17 19 * * *', $$select security.ca_dli_apply_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.ca_dli_apply_v1', 'Layer 1', 'Sets the Canadian international-enrolment flag from the IRCC DLI number', 'active', '20261020130000')
on conflict (kind, name) do nothing;

select security.ca_dli_apply_v1();
