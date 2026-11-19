-- CF-247 (2 Oct 2026, 23:00 AEST). Platform Admin, 21:18: "Outcome id maximum data admitted till tomm morning for
-- au,nz,Canada." By 22:45 the AI link matcher had worked only on Australian universities: by default the priority list
-- puts Australia first and then the universities with the most courses, so Canada (26 universities with a site map)
-- and New Zealand (268) were never reached. Canada and New Zealand are pinned first (Canada, then New Zealand) for the
-- night. The pins show on the Priority queue screen, where a Platform Admin can remove them; nothing else changes.
insert into pipeline.priority_pins(kind, target_id, sort, note)
select 'country', k.id, v.sort, 'Overnight run 2–3 Oct 2026: AI link matcher reaches Canada and New Zealand (set by Claude, 23:00)'
  from (values ('CA', 1), ('NZ', 2)) v(code, sort) join ref.countries k on k.iso_alpha2 = v.code
on conflict (kind, target_id) do nothing;

select security.provider_priority_refresh_v1();
