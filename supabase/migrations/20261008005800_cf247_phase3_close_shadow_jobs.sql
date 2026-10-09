-- CF-247 Phase 3 closes (Platform Admin decision 9 Oct 2026, multiple choice: "Keep Layer 3, stop shadow").
-- Three shadow rounds (a single adapter model, a stronger single model, and the adapter model with one escalation step)
-- each agreed with Layer 3 where both found a value, but none found values as often at a lower cost, so Layer 3 keeps
-- intakes, English and tuition. The shadow run was switched off through admin_adapter_shadow (logged); this removes its
-- three jobs. The shadow tables, functions and every read are kept as the record of the comparison.

do $close$
declare j text;
begin
  if exists (select 1 from pipeline.adapter_shadow_settings where id = 1 and enabled) then
    raise exception 'the shadow run is still switched on; switch it off first';
  end if;
  foreach j in array array['adapter-shadow-intake','adapter-shadow-english','adapter-shadow-tuition'] loop
    if exists (select 1 from cron.job where jobname = j) then perform cron.unschedule(j); end if;
  end loop;
end $close$;
